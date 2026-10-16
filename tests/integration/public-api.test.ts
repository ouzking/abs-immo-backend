// Contrat du site public : lecture des annonces, recherche, pagination, formulaires.
import { describe, expect, it } from "vitest";
import { PROPERTY_CARD_COLUMNS, type PublicFilters, type PublicPropertyDetail } from "../../src/types/index.ts";
import { anonClient, callFunction, randomIp, randomSnPhone, serviceClient, uniqueEmail } from "./helpers.ts";

describe("Lecture publique des annonces", () => {
  it("refuse la lecture directe des tables internes", async () => {
    const anon = anonClient();
    for (const table of ["properties", "leads", "inquiries", "profiles", "audit_logs"] as const) {
      const { data, error } = await anon.from(table).select("id").limit(1);
      expect(error?.code, table).toBe("42501");
      expect(data).toBeNull();
    }
  });

  it("liste uniquement les annonces publiées, avec pagination et total", async () => {
    const anon = anonClient();
    const page1 = await anon.from("public_properties").select(PROPERTY_CARD_COLUMNS, { count: "exact" })
      .order("published_at", { ascending: false }).range(0, 2);
    expect(page1.error).toBeNull();
    expect(page1.count).toBeGreaterThanOrEqual(6);
    expect(page1.data).toHaveLength(3);

    const { count: drafts } = await serviceClient().from("properties").select("id", { count: "exact", head: true })
      .neq("publication_status", "published");
    expect(drafts).toBeGreaterThan(0);
    const all = await anon.from("public_properties").select("id,title");
    expect(all.data!.some((p) => p.title?.includes("préparation"))).toBe(false);
  });

  it("search_properties : filtres, tri, pagination et total via PostgREST", async () => {
    const anon = anonClient();
    const { data, count, error } = await anon
      .rpc("search_properties", { p_transaction_type: "rent", p_sort: "price_asc" }, { count: "exact" })
      .select("id,price_amount,transaction_type")
      .range(0, 1);
    expect(error).toBeNull();
    expect(count).toBeGreaterThanOrEqual(3);
    expect(data).toHaveLength(2);
    expect(data!.every((p) => p.transaction_type === "rent")).toBe(true);
    expect(data![0].price_amount!).toBeLessThanOrEqual(data![1].price_amount!);

    const text = await anon.rpc("search_properties", { p_query: "piscine almadies" }).select("title");
    expect(text.data!.map((p) => p.title)).toContain("Villa contemporaine avec piscine aux Almadies");

    const bad = await anon.rpc("search_properties", { p_sort: "nope" });
    expect(bad.error?.code).toBe("22023");
  });

  it("get_public_property renvoie le détail public sans données internes", async () => {
    const anon = anonClient();
    const { data: card } = await anon.from("public_properties").select("slug").eq("is_featured", true).limit(1).single();
    const { data, error } = await anon.rpc("get_public_property", { p_slug: card!.slug! });
    expect(error).toBeNull();
    const detail = data as unknown as PublicPropertyDetail;
    expect(detail.images.length).toBeGreaterThan(0);
    expect(detail.amenities.length).toBeGreaterThan(0);
    expect(detail.agent?.display_name).toBeTruthy();
    expect(detail).not.toHaveProperty("internal_notes");
    expect(detail).not.toHaveProperty("search_vector");
    expect(detail.address_line).toBeNull(); // visibilité approximative
  });

  it("get_public_filters ne reflète que les annonces publiées", async () => {
    const { data } = await anonClient().rpc("get_public_filters");
    const f = data as unknown as PublicFilters;
    const total = f.transaction_types.reduce((s, t) => s + t.count, 0);
    const { count } = await anonClient().from("public_properties").select("id", { count: "exact", head: true });
    expect(total).toBe(count);
    expect(f.cities.length).toBeGreaterThan(0);
  });

  it("expose les paramètres publics et les référentiels actifs", async () => {
    const anon = anonClient();
    expect((await anon.from("agency_settings").select("agency_name").single()).data?.agency_name).toBe("ABS IMMO & SERVICES");
    expect((await anon.from("localities").select("id").eq("level", "region")).data).toHaveLength(14);
    expect((await anon.from("property_types").select("code")).data!.length).toBeGreaterThanOrEqual(6);
    expect((await anon.from("app_settings").select("key")).error?.code).toBe("42501");
  });

  it("l'inscription publique est désactivée", async () => {
    const { error } = await anonClient().auth.signUp({ email: uniqueEmail("signup"), password: "Motdepasse2026" });
    expect(error).not.toBeNull();
  });
});

describe("Formulaire de demande (submit-inquiry)", () => {
  async function publishedProperty(transaction: "sale" | "rent" = "sale") {
    const { data } = await anonClient().from("public_properties").select("id")
      .eq("transaction_type", transaction).eq("commercial_status", "available").limit(1).single();
    return data!.id;
  }

  it("crée une demande puis détecte le doublon", async () => {
    const propertyId = await publishedProperty();
    const email = uniqueEmail("prospect");
    const phone = randomSnPhone();
    const body = { full_name: "Prospect Intégration", email, phone, message: "Intéressé", property_id: propertyId };
    const headers = { "x-forwarded-for": randomIp() };

    const first = await callFunction("submit-inquiry", body, { headers });
    expect(first.status).toBe(201);
    expect(first.json.data.duplicate).toBe(false);

    const second = await callFunction("submit-inquiry", body, { headers });
    expect(second.status).toBe(200);
    expect(second.json.data).toEqual({ id: first.json.data.id, duplicate: true });

    const { data: inquiry } = await serviceClient().from("inquiries")
      .select("assigned_agent_id, submission_meta, lead:leads(email, phone)").eq("id", first.json.data.id).single();
    expect(inquiry!.lead).toMatchObject({ email, phone: `+221${phone}` });
    expect(inquiry!.assigned_agent_id).not.toBeNull();
    const meta = inquiry!.submission_meta as Record<string, unknown>;
    expect(meta.ip_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(meta)).not.toContain(headers["x-forwarded-for"]); // IP jamais stockée en clair
  });

  it("renvoie les erreurs de validation par champ", async () => {
    const r = await callFunction("submit-inquiry", { full_name: "A", email: "x" }, { headers: { "x-forwarded-for": randomIp() } });
    expect(r.status).toBe(422);
    expect(r.json.error.code).toBe("VALIDATION_ERROR");
    expect(Object.keys(r.json.error.fields)).toEqual(expect.arrayContaining(["full_name", "email"]));
  });

  it("refuse une demande sur une annonce non publiée", async () => {
    const { data: draft } = await serviceClient().from("properties").select("id").eq("publication_status", "draft").limit(1).single();
    const r = await callFunction("submit-inquiry", { full_name: "Curieux Test", email: uniqueEmail("c"), property_id: draft!.id },
      { headers: { "x-forwarded-for": randomIp() } });
    expect(r.status).toBe(404);
    expect(r.json.error.code).toBe("PROPERTY_UNAVAILABLE");
  });

  it("piège à robots : succès factice, rien n'est enregistré", async () => {
    const email = uniqueEmail("robot");
    const r = await callFunction("submit-inquiry", { full_name: "Robot Spam", email, message: "spam", website: "http://spam.example" });
    expect(r.status).toBe(201);
    const { count } = await serviceClient().from("leads").select("id", { count: "exact", head: true }).eq("email", email);
    expect(count).toBe(0);
  });

  it("limite le débit par adresse IP (429 à la 6e soumission en 10 min)", async () => {
    const headers = { "x-forwarded-for": randomIp() };
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      const r = await callFunction("submit-inquiry", { full_name: `Rafale ${i}`, email: uniqueEmail("burst"), message: "test" }, { headers });
      statuses.push(r.status);
    }
    expect(statuses.slice(0, 5)).toEqual([201, 201, 201, 201, 201]);
    expect(statuses[5]).toBe(429);
  });

  it("rejette les méthodes, JSON et tailles invalides", async () => {
    expect((await callFunction("submit-inquiry", null, { method: "GET" })).status).toBe(405);
    expect((await callFunction("submit-inquiry", null, { rawBody: "{pas du json" })).json.error.code).toBe("INVALID_JSON");
    const big = await callFunction("submit-inquiry", { full_name: "Gros", email: "g@x.sn", message: "x".repeat(20_000) });
    expect(big.status).toBe(413);
  });
});

describe("Formulaire de visite (submit-viewing-request)", () => {
  it("crée une demande de visite et refuse une date passée", async () => {
    const { data } = await anonClient().from("public_properties").select("id").eq("commercial_status", "available").limit(1).single();
    const headers = { "x-forwarded-for": randomIp() };
    const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    const phone = randomSnPhone();

    const ok = await callFunction("submit-viewing-request", {
      full_name: "Visiteur Intégration", phone, property_id: data!.id,
      preferred_date: tomorrow, preferred_time_slot: "afternoon",
    }, { headers });
    expect(ok.status).toBe(201);

    const past = await callFunction("submit-viewing-request", {
      full_name: "Visiteur Intégration", phone, property_id: data!.id, preferred_date: "2020-01-01",
    }, { headers });
    expect(past.status).toBe(422);
    expect(past.json.error.fields.preferred_date).toBeDefined();

    const { data: viewing } = await serviceClient().from("viewing_requests").select("status, preferred_time_slot")
      .eq("id", ok.json.data.id).single();
    expect(viewing).toEqual({ status: "requested", preferred_time_slot: "afternoon" });
  });
});
