import { describe, expect, it } from "vitest";
import {
  looksLikeBot,
  normalizePhone,
  validateInquiry,
  validateViewingRequest,
} from "../../supabase/functions/_shared/validation.ts";
import { agentSlug, isStrongPassword, validateAdminAction } from "../../supabase/functions/_shared/admin-validation.ts";
import { corsHeaders, isOriginAllowed, mapDbError } from "../../supabase/functions/_shared/http.ts";
import { formatPriceXof, propertyFilePath } from "../../src/types/contracts.ts";

const PROPERTY_ID = "3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e";

describe("normalizePhone", () => {
  it.each([
    ["77 123 45 67", "+221771234567"],
    ["33 800 11 22", "+221338001122"],
    ["+221 77-123-45-67", "+221771234567"],
    ["00221771234567", "+221771234567"],
    ["+33 6 12 34 56 78", "+33612345678"],
    ["(+1) 202 555 0143", "+12025550143"],
  ])("%s -> %s", (input, expected) => expect(normalizePhone(input)).toBe(expected));

  it.each(["", "abc", "12345", "+0123456789", "771234"])("rejette %j", (input) => {
    expect(normalizePhone(input)).toBeNull();
  });

  it("rejette les valeurs non textuelles", () => expect(normalizePhone(771234567)).toBeNull());
});

describe("validateInquiry", () => {
  it("accepte une demande valide et nettoie les champs", () => {
    const r = validateInquiry({
      full_name: "  Awa   Diop ",
      email: "AWA@Example.SN",
      phone: "77 000 11 22",
      message: " Bonjour ",
      property_id: PROPERTY_ID.toUpperCase(),
      utm: { utm_source: "facebook", evil: "x" },
      page_url: "javascript:alert(1)",
    });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data).toMatchObject({
      full_name: "Awa Diop",
      email: "awa@example.sn",
      phone: "+221770001122",
      message: "Bonjour",
      property_id: PROPERTY_ID,
      inquiry_type: "property_info",
      consent_marketing: false,
      page_url: null,
      utm: { utm_source: "facebook" },
    });
  });

  it("exige un moyen de contact", () => {
    const r = validateInquiry({ full_name: "Awa Diop", message: "Bonjour" });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.contact).toBeDefined();
  });

  it("exige un message sans bien ciblé", () => {
    const r = validateInquiry({ full_name: "Awa Diop", email: "a@b.sn" });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.message).toBeDefined();
  });

  it("signale chaque champ invalide", () => {
    const r = validateInquiry({
      full_name: "A",
      email: "pas-un-email",
      phone: "123",
      property_id: "pas-un-uuid",
      inquiry_type: "hack",
      preferred_contact: "pigeon",
      message: "x".repeat(5001),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(Object.keys(r.errors).sort()).toEqual(
        ["email", "full_name", "inquiry_type", "message", "phone", "preferred_contact", "property_id"].sort(),
      );
    }
  });

  it("exige l'e-mail si le contact préféré est l'e-mail", () => {
    const r = validateInquiry({ full_name: "Awa Diop", phone: "770001122", message: "Bonjour", preferred_contact: "email" });
    expect(r.ok).toBe(false);
  });

  it.each([null, "texte", [1, 2]])("rejette un corps %j", (body) => {
    expect(validateInquiry(body).ok).toBe(false);
  });
});

describe("validateViewingRequest", () => {
  const now = new Date("2026-10-16T10:00:00Z");

  it("accepte une demande valide", () => {
    const r = validateViewingRequest(
      { full_name: "Awa Diop", phone: "770001122", property_id: PROPERTY_ID, preferred_date: "2026-10-20", preferred_time_slot: "morning" },
      now,
    );
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.data).toMatchObject({ phone: "+221770001122", preferred_time_slot: "morning" });
  });

  it("exige un téléphone et un bien", () => {
    const r = validateViewingRequest({ full_name: "Awa Diop", email: "a@b.sn" }, now);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.errors.phone).toBeDefined();
      expect(r.errors.property_id).toBeDefined();
    }
  });

  it.each(["2026-10-15", "2027-03-01", "2026-02-30", "16/10/2026"])("rejette la date %s", (d) => {
    const r = validateViewingRequest({ full_name: "Awa Diop", phone: "770001122", property_id: PROPERTY_ID, preferred_date: d }, now);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.preferred_date).toBeDefined();
  });

  it("accepte aujourd'hui et +120 jours", () => {
    for (const d of ["2026-10-16", "2027-02-13"]) {
      expect(validateViewingRequest({ full_name: "Awa Diop", phone: "770001122", property_id: PROPERTY_ID, preferred_date: d }, now).ok)
        .toBe(true);
    }
  });
});

describe("looksLikeBot", () => {
  it("détecte le champ piège", () => expect(looksLikeBot({ website: "http://spam" })).toBe(true));
  it("détecte une saisie trop rapide", () => expect(looksLikeBot({ form_started_at: 1000 }, 2000)).toBe(true));
  it("laisse passer un humain", () => expect(looksLikeBot({ website: "", form_started_at: 1000 }, 10_000)).toBe(false));
});

describe("validateAdminAction", () => {
  it("valide une invitation", () => {
    const r = validateAdminAction({ action: "invite", email: "New@Abs.SN", full_name: "Nouvel Agent", role: "agent", phone: "770001122" });
    expect(r.ok).toBe(true);
    if (r.ok && r.data.action === "invite") {
      expect(r.data.email).toBe("new@abs.sn");
      expect(r.data.phone).toBe("+221770001122");
    }
  });
  it("refuse un rôle inconnu", () => {
    expect(validateAdminAction({ action: "invite", email: "a@b.sn", full_name: "Nom", role: "god" }).ok).toBe(false);
  });
  it("impose la politique de mot de passe", () => {
    expect(validateAdminAction({ action: "create", email: "a@b.sn", full_name: "Nom", role: "agent", password: "faible" }).ok).toBe(false);
    expect(isStrongPassword("Motdepasse2026")).toBe(true);
    expect(isStrongPassword("motdepasse2026")).toBe(false);
  });
  it("valide les actions sur un utilisateur", () => {
    expect(validateAdminAction({ action: "deactivate", user_id: PROPERTY_ID }).ok).toBe(true);
    expect(validateAdminAction({ action: "deactivate", user_id: "1" }).ok).toBe(false);
    expect(validateAdminAction({ action: "drop_database" }).ok).toBe(false);
  });
  it("génère un slug d'agent", () => expect(agentSlug("Aïssatou Ndiaye", PROPERTY_ID)).toBe("aissatou-ndiaye-3f2b8c"));
});

describe("http", () => {
  it.each([
    ["AB422", 422, "VALIDATION_ERROR"],
    ["AB404", 404, "PROPERTY_UNAVAILABLE"],
    ["AB429", 429, "RATE_LIMITED"],
    ["42501", 403, "FORBIDDEN"],
    ["23514", 409, "BUSINESS_RULE_VIOLATION"],
    ["XX000", 500, "INTERNAL_ERROR"],
  ])("mappe %s -> %i %s", (code, status, apiCode) => {
    const m = mapDbError({ code, message: "msg", hint: "email" });
    expect(m.status).toBe(status);
    expect(m.error.code).toBe(apiCode);
  });

  it("n'expose pas le message des erreurs internes", () => {
    expect(mapDbError({ code: "XX000", message: "relation secrète" }).error.message).not.toContain("secrète");
  });

  it("champ en erreur pour AB422", () => {
    expect(mapDbError({ code: "AB422", message: "E-mail invalide", hint: "email" }).error.fields).toEqual({ email: "E-mail invalide" });
  });

  it("gère les origines autorisées", () => {
    const allowed = "https://abs-immo.sn,https://www.abs-immo.sn";
    expect(isOriginAllowed("https://abs-immo.sn", allowed)).toBe(true);
    expect(isOriginAllowed("https://evil.example", allowed)).toBe(false);
    expect(isOriginAllowed(null, allowed)).toBe(true);
    expect(corsHeaders("https://www.abs-immo.sn", allowed)["Access-Control-Allow-Origin"]).toBe("https://www.abs-immo.sn");
    expect(corsHeaders("https://evil.example", undefined)["Access-Control-Allow-Origin"]).toBe("*");
  });
});

describe("contracts", () => {
  it("construit un chemin de photo conforme", () => {
    expect(propertyFilePath(PROPERTY_ID, "image/webp", "abc")).toBe(`${PROPERTY_ID}/abc.webp`);
    expect(() => propertyFilePath(PROPERTY_ID, "image/svg+xml")).toThrow();
  });
  it("formate les prix en FCFA", () => {
    expect(formatPriceXof(150000000)).toBe("150 000 000 FCFA");
    expect(formatPriceXof(850000, "month")).toBe("850 000 FCFA / mois");
    expect(formatPriceXof(null)).toBe("Prix sur demande");
  });
});
