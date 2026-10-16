// Contrat du back-office : authentification, comptes, biens, photos, prospects, statistiques.
import { describe, expect, it } from "vitest";
import { propertyFilePath, type DashboardStats, type MyAccess } from "../../src/types/index.ts";
import { anonClient, callFunction, DEMO, randomIp, serviceClient, signIn, TINY_JPEG, uniqueEmail } from "./helpers.ts";

describe("Authentification et accès", () => {
  it("connexion, get_my_access et déconnexion", async () => {
    const { client } = await signIn(DEMO.agent1);
    const { data } = await client.rpc("get_my_access");
    const access = data as unknown as MyAccess;
    expect(access.roles).toEqual(["agent"]);
    expect(access.permissions).toContain("properties.create");
    expect(access.permissions).not.toContain("properties.publish");
    expect((await client.auth.signOut()).error).toBeNull();
  });

  it("mauvais mot de passe refusé", async () => {
    const { error } = await anonClient().auth.signInWithPassword({ email: DEMO.agent1, password: "Mauvais-2026" });
    expect(error).not.toBeNull();
  });

  it("demande de réinitialisation du mot de passe acceptée", async () => {
    const { error } = await anonClient().auth.resetPasswordForEmail(DEMO.agent2);
    expect(error).toBeNull();
  });
});

describe("Administration des comptes (admin-users)", () => {
  it("refuse sans jeton et pour un agent", async () => {
    expect((await callFunction("admin-users", { action: "deactivate", user_id: crypto.randomUUID() })).status).toBe(401);
    const { session } = await signIn(DEMO.agent1);
    const r = await callFunction("admin-users",
      { action: "create", email: uniqueEmail("x"), password: "Motdepasse2026", full_name: "Pirate Test", role: "agent" },
      { token: session.access_token });
    expect(r.status).toBe(403);
  });

  it("un admin ne peut pas créer un administrateur", async () => {
    const { session } = await signIn(DEMO.admin);
    const r = await callFunction("admin-users",
      { action: "create", email: uniqueEmail("adm"), password: "Motdepasse2026", full_name: "Faux Admin", role: "admin" },
      { token: session.access_token });
    expect(r.status).toBe(403);
  });

  it("cycle complet : création, connexion, désactivation, réactivation", async () => {
    const { session } = await signIn(DEMO.admin);
    const email = uniqueEmail("nouvel.agent");
    const password = "Motdepasse2026";

    const created = await callFunction("admin-users",
      { action: "create", email, password, full_name: "Nouvel Agent Test", role: "agent", phone: "77 999 00 11", create_agent_profile: true },
      { token: session.access_token });
    expect(created.status).toBe(201);
    expect(created.json.data.agent_profile_created).toBe(true);
    const userId = created.json.data.user_id as string;

    const { client: newClient } = await signIn(email, password);
    const access = (await newClient.rpc("get_my_access")).data as unknown as MyAccess;
    expect(access.roles).toEqual(["agent"]);
    expect(access.is_agent).toBe(true);

    // L'utilisateur ne peut pas s'élever lui-même
    expect((await newClient.rpc("assign_role", { p_user_id: userId, p_role_code: "admin" })).error?.code).toBe("42501");

    const off = await callFunction("admin-users", { action: "deactivate", user_id: userId }, { token: session.access_token });
    expect(off.status).toBe(200);
    // Le JWT encore valide ne donne plus aucun accès (RLS vérifie is_active)…
    expect((await newClient.from("properties").select("id")).data).toEqual([]);
    // …et toute nouvelle connexion est refusée (compte banni dans Auth).
    expect((await anonClient().auth.signInWithPassword({ email, password })).error).not.toBeNull();

    const on = await callFunction("admin-users", { action: "reactivate", user_id: userId }, { token: session.access_token });
    expect(on.status).toBe(200);
    expect((await anonClient().auth.signInWithPassword({ email, password })).error).toBeNull();

    // Nettoyage
    await serviceClient().auth.admin.deleteUser(userId);
  });

  it("refuse un e-mail déjà utilisé", async () => {
    const { session } = await signIn(DEMO.admin);
    const r = await callFunction("admin-users",
      { action: "create", email: DEMO.agent1, password: "Motdepasse2026", full_name: "Doublon Test", role: "agent" },
      { token: session.access_token });
    expect(r.status).toBe(409);
  });
});

describe("Biens, photos et Storage", () => {
  it("workflow agent → responsable, avec accès public aux seules photos publiées", async () => {
    const agent = await signIn(DEMO.agent1);
    const agent2 = await signIn(DEMO.agent2);
    const manager = await signIn(DEMO.manager);
    const anon = anonClient();
    const { data: locality } = await anon.from("localities").select("id").eq("slug", "mermoz").single();

    // 1. L'agent crée un brouillon
    const { data: property, error } = await agent.client.from("properties").insert({
      title: "Appartement test intégration Mermoz",
      property_type: "apartment",
      transaction_type: "rent",
      rent_period: "month",
      price_amount: 600000,
      locality_id: locality!.id,
      short_description: "Bel appartement de test pour l'intégration.",
    }).select("id, reference, slug, agent_id, publication_status").single();
    expect(error).toBeNull();
    expect(property!.agent_id).toBe(agent.user.id);
    expect(property!.reference).toMatch(/^ABS-L-/);

    // 2. Téléversement d'une photo (bucket privé, chemin <property_id>/<uuid>.jpg)
    const path = propertyFilePath(property!.id, "image/jpeg");
    const upload = await agent.client.storage.from("property-images").upload(path, TINY_JPEG, { contentType: "image/jpeg" });
    expect(upload.error).toBeNull();
    expect((await agent.client.from("property_media").insert({ property_id: property!.id, storage_path: path, alt_text: "Salon" })).error).toBeNull();

    // Un collègue ne peut pas téléverser sur ce bien ; type de fichier contrôlé
    const intrus = await agent2.client.storage.from("property-images")
      .upload(propertyFilePath(property!.id, "image/jpeg"), TINY_JPEG, { contentType: "image/jpeg" });
    expect(intrus.error).not.toBeNull();
    const svg = await agent.client.storage.from("property-images")
      .upload(`${property!.id}/x.svg`, new TextEncoder().encode("<svg/>"), { contentType: "image/svg+xml" });
    expect(svg.error).not.toBeNull();

    // 3. Brouillon : photo inaccessible publiquement
    expect((await anon.storage.from("property-images").createSignedUrl(path, 60)).error).not.toBeNull();

    // 4. L'agent ne peut pas publier ; il soumet à validation
    const pub = await agent.client.from("properties").update({ publication_status: "published" }).eq("id", property!.id);
    expect(pub.error?.code).toBe("42501");
    expect((await agent.client.from("properties").update({ publication_status: "pending_review" }).eq("id", property!.id)).error).toBeNull();

    // 5. Le responsable publie
    expect((await manager.client.from("properties").update({ publication_status: "published" }).eq("id", property!.id)).error).toBeNull();
    const signed = await anon.storage.from("property-images").createSignedUrl(path, 60);
    expect(signed.error).toBeNull();
    const img = await fetch(signed.data!.signedUrl);
    expect(img.status).toBe(200);
    expect((await anon.from("public_properties").select("id").eq("id", property!.id)).data).toHaveLength(1);

    // 6. Retrait : la photo redevient privée
    expect((await manager.client.from("properties").update({ publication_status: "unpublished" }).eq("id", property!.id)).error).toBeNull();
    expect((await anon.storage.from("property-images").createSignedUrl(path, 60)).error).not.toBeNull();

    // 7. Suppression de la photo (ligne + fichier) par l'agent
    expect((await agent.client.from("property_media").delete().eq("storage_path", path)).error).toBeNull();
    expect((await agent.client.storage.from("property-images").remove([path])).error).toBeNull();

    // Nettoyage (suppression définitive réservée au super admin)
    await serviceClient().from("properties").delete().eq("id", property!.id);
  });

  it("documents internes jamais accessibles publiquement", async () => {
    const admin = await signIn(DEMO.admin);
    const { data: p } = await serviceClient().from("properties").select("id").eq("publication_status", "published").limit(1).single();
    const path = `${p!.id}/mandat-${Date.now()}.pdf`;
    const up = await admin.client.storage.from("property-documents")
      .upload(path, new TextEncoder().encode("%PDF-1.4 test"), { contentType: "application/pdf" });
    expect(up.error).toBeNull();
    expect((await anonClient().storage.from("property-documents").createSignedUrl(path, 60)).error).not.toBeNull();
    expect((await admin.client.storage.from("property-documents").createSignedUrl(path, 60)).error).toBeNull();
    await serviceClient().storage.from("property-documents").remove([path]);
  });
});

describe("Prospects et statistiques", () => {
  it("cloisonnement des prospects entre agents et suivi", async () => {
    // Demande sur un bien d'agent1
    const agent1 = await signIn(DEMO.agent1);
    const { data: prop } = await serviceClient().from("properties").select("id")
      .eq("agent_id", agent1.user.id).eq("publication_status", "published").eq("commercial_status", "available").limit(1).single();
    const r = await callFunction("submit-inquiry",
      { full_name: "Prospect Cloisonné", email: uniqueEmail("iso"), message: "Bonjour", property_id: prop!.id },
      { headers: { "x-forwarded-for": randomIp() } });
    expect(r.status).toBe(201);
    const inquiryId = r.json.data.id as string;

    const { data: seen } = await agent1.client.from("inquiries").select("id, lead_id, lead:leads(full_name)").eq("id", inquiryId).single();
    expect(seen?.lead).toMatchObject({ full_name: "Prospect Cloisonné" });

    const agent2 = await signIn(DEMO.agent2);
    expect((await agent2.client.from("inquiries").select("id").eq("id", inquiryId)).data).toEqual([]);
    expect((await agent2.client.from("leads").select("id").eq("id", seen!.lead_id)).data).toEqual([]);

    // Suivi par l'agent 1
    expect((await agent1.client.from("inquiries").update({ status: "answered" }).eq("id", inquiryId)).error).toBeNull();
    expect((await agent1.client.from("lead_activities").insert({ lead_id: seen!.lead_id, activity_type: "call", content: "Rappelé" })).error).toBeNull();
    const { data: history } = await agent1.client.from("lead_activities").select("activity_type").eq("lead_id", seen!.lead_id);
    expect(history!.map((h) => h.activity_type)).toEqual(expect.arrayContaining(["inquiry_received", "status_change", "call"]));

    // Réaffectation : réservée au responsable
    expect((await agent1.client.rpc("assign_lead", { p_lead_id: seen!.lead_id, p_agent_id: agent2.user.id })).error?.code).toBe("42501");
    const manager = await signIn(DEMO.manager);
    expect((await manager.client.rpc("assign_lead", { p_lead_id: seen!.lead_id, p_agent_id: agent2.user.id })).error).toBeNull();
  });

  it("statistiques selon le périmètre", async () => {
    const manager = await signIn(DEMO.manager);
    const global = (await manager.client.rpc("get_dashboard_stats")).data as unknown as DashboardStats;
    expect(global.scope.agent_id).toBeNull();
    expect(global.properties.published).toBeGreaterThanOrEqual(6);

    const agent = await signIn(DEMO.agent1);
    const own = (await agent.client.rpc("get_dashboard_stats")).data as unknown as DashboardStats;
    expect(own.scope.agent_id).toBe(agent.user.id);
    expect(own.properties.total).toBeLessThan(global.properties.total);
    expect((await agent.client.rpc("get_dashboard_stats", { p_agent_id: manager.user.id })).error?.code).toBe("42501");
  });
});
