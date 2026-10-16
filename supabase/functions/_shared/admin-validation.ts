// Validation des actions d'administration des comptes — module PUR.
import { isUuid, normalizePhone, type FieldErrors, type ValidationResult } from "./validation.ts";

export const ROLE_CODES = ["super_admin", "admin", "sales_manager", "agent"] as const;
export type RoleCode = (typeof ROLE_CODES)[number];

export type AdminAction =
  | {
    action: "invite" | "create";
    email: string;
    full_name: string;
    role: RoleCode;
    phone: string | null;
    password: string | null;
    create_agent_profile: boolean;
    redirect_to: string | null;
  }
  | { action: "deactivate" | "reactivate"; user_id: string }
  | { action: "send_password_reset"; user_id: string; redirect_to: string | null };

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/** Politique alignée sur config.toml : ≥ 10 caractères, minuscule, majuscule, chiffre. */
export function isStrongPassword(p: string): boolean {
  return p.length >= 10 && p.length <= 72 && /[a-z]/.test(p) && /[A-Z]/.test(p) && /[0-9]/.test(p);
}

function cleanRedirect(v: unknown, errors: FieldErrors): string | null {
  if (v == null || v === "") return null;
  if (typeof v !== "string") {
    errors.redirect_to = "URL invalide.";
    return null;
  }
  try {
    const u = new URL(v);
    if (u.protocol !== "https:" && u.protocol !== "http:") throw new Error();
    return u.toString();
  } catch {
    errors.redirect_to = "URL invalide.";
    return null;
  }
}

export function validateAdminAction(body: unknown): ValidationResult<AdminAction> {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, errors: { body: "Corps JSON invalide." } };
  }
  const b = body as Record<string, unknown>;
  const errors: FieldErrors = {};

  switch (b.action) {
    case "invite":
    case "create": {
      const email = typeof b.email === "string" ? b.email.trim().toLowerCase() : "";
      if (!EMAIL_RE.test(email) || email.length > 254) errors.email = "Adresse e-mail invalide.";
      const full_name = typeof b.full_name === "string" ? b.full_name.replace(/\s+/g, " ").trim() : "";
      if (full_name.length < 2 || full_name.length > 120) errors.full_name = "Nom requis (2 à 120 caractères).";
      if (!ROLE_CODES.includes(b.role as RoleCode)) errors.role = "Rôle invalide.";
      let phone: string | null = null;
      if (b.phone != null && b.phone !== "") {
        phone = normalizePhone(b.phone);
        if (!phone) errors.phone = "Numéro de téléphone invalide.";
      }
      let password: string | null = null;
      if (b.action === "create") {
        if (typeof b.password !== "string" || !isStrongPassword(b.password)) {
          errors.password = "Mot de passe : 10 caractères minimum avec minuscule, majuscule et chiffre.";
        } else {
          password = b.password;
        }
      }
      const redirect_to = cleanRedirect(b.redirect_to, errors);
      if (Object.keys(errors).length) return { ok: false, errors };
      return {
        ok: true,
        data: {
          action: b.action,
          email,
          full_name,
          role: b.role as RoleCode,
          phone,
          password,
          create_agent_profile: b.create_agent_profile === true,
          redirect_to,
        },
      };
    }
    case "deactivate":
    case "reactivate":
      if (!isUuid(b.user_id)) return { ok: false, errors: { user_id: "Identifiant utilisateur invalide." } };
      return { ok: true, data: { action: b.action, user_id: b.user_id.toLowerCase() } };
    case "send_password_reset": {
      if (!isUuid(b.user_id)) errors.user_id = "Identifiant utilisateur invalide.";
      const redirect_to = cleanRedirect(b.redirect_to, errors);
      if (Object.keys(errors).length) return { ok: false, errors };
      return { ok: true, data: { action: "send_password_reset", user_id: (b.user_id as string).toLowerCase(), redirect_to } };
    }
    default:
      return {
        ok: false,
        errors: { action: "Action inconnue (invite, create, deactivate, reactivate, send_password_reset)." },
      };
  }
}

/** Slug d'agent : "Awa Ndiaye" + id -> "awa-ndiaye-1a2b3c" */
export function agentSlug(fullName: string, userId: string): string {
  const base = fullName
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
  return `${base || "agent"}-${userId.replace(/-/g, "").slice(0, 6)}`;
}
