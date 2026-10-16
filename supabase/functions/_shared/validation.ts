// =============================================================================
// Validation des formulaires publics — module PUR (aucune dépendance).
// Importable par les Edge Functions (Deno) et par les tests (Node/Vitest).
// Les mêmes règles sont revérifiées en base (défense en profondeur).
// =============================================================================

export const INQUIRY_TYPES = [
  "general",
  "property_info",
  "price",
  "availability",
  "sell_property",
  "rent_out_property",
  "other",
] as const;
export type InquiryType = (typeof INQUIRY_TYPES)[number];

export const CONTACT_METHODS = ["phone", "whatsapp", "email"] as const;
export type ContactMethod = (typeof CONTACT_METHODS)[number];

export const TIME_SLOTS = ["morning", "afternoon", "evening", "any"] as const;
export type TimeSlot = (typeof TIME_SLOTS)[number];

export const LIMITS = {
  fullNameMin: 2,
  fullNameMax: 120,
  emailMax: 254,
  inquiryMessageMax: 5000,
  viewingMessageMax: 2000,
  maxDaysAhead: 120,
  minFillTimeMs: 2500,
  maxBodyBytes: 16 * 1024,
} as const;

export type FieldErrors = Record<string, string>;
export type ValidationResult<T> =
  | { ok: true; data: T }
  | { ok: false; errors: FieldErrors };

export interface InquiryInput {
  full_name: string;
  email: string | null;
  phone: string | null;
  message: string | null;
  property_id: string | null;
  inquiry_type: InquiryType;
  preferred_contact: ContactMethod | null;
  consent_marketing: boolean;
  page_url: string | null;
  utm: Record<string, string>;
}

export interface ViewingRequestInput {
  full_name: string;
  email: string | null;
  phone: string;
  property_id: string;
  preferred_date: string | null;
  preferred_time_slot: TimeSlot;
  alternative_date: string | null;
  message: string | null;
  preferred_contact: ContactMethod | null;
  consent_marketing: boolean;
  page_url: string | null;
  utm: Record<string, string>;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const E164_RE = /^\+[1-9][0-9]{7,14}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"];

/**
 * Normalise un numéro au format E.164.
 * - supprime espaces, points, tirets, parenthèses ;
 * - "00" initial -> "+" ;
 * - numéro sénégalais à 9 chiffres commençant par 7 (mobile) ou 3 (fixe) -> +221.
 * Renvoie null si le numéro est invalide.
 */
export function normalizePhone(raw: unknown, defaultPrefix = "+221"): string | null {
  if (typeof raw !== "string") return null;
  let v = raw.replace(/[\s.\-()/]/g, "");
  if (v === "") return null;
  if (v.startsWith("00")) v = "+" + v.slice(2);
  if (/^[37][0-9]{8}$/.test(v) && defaultPrefix === "+221") v = "+221" + v;
  return E164_RE.test(v) ? v : null;
}

export function isUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

function cleanText(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.replace(/\u0000/g, "").trim();
  return t === "" ? null : t;
}

function cleanName(v: unknown): string {
  return typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "";
}

/** Date du jour à Dakar (UTC+0) au format AAAA-MM-JJ. */
export function todayInDakar(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function addDays(isoDate: string, days: number): string {
  const d = new Date(isoDate + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function isValidIsoDate(v: string): boolean {
  if (!DATE_RE.test(v)) return false;
  const d = new Date(v + "T00:00:00Z");
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

function pickUtm(v: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (v && typeof v === "object" && !Array.isArray(v)) {
    for (const k of UTM_KEYS) {
      const val = (v as Record<string, unknown>)[k];
      if (typeof val === "string" && val.trim() !== "") out[k] = val.trim().slice(0, 100);
    }
  }
  return out;
}

function cleanUrl(v: unknown): string | null {
  const t = cleanText(v);
  if (!t) return null;
  try {
    const u = new URL(t);
    if (u.protocol !== "https:" && u.protocol !== "http:") return null;
    return u.toString().slice(0, 500);
  } catch {
    return null;
  }
}

function validateContact(body: Record<string, unknown>, errors: FieldErrors) {
  const full_name = cleanName(body.full_name);
  if (full_name.length < LIMITS.fullNameMin || full_name.length > LIMITS.fullNameMax) {
    errors.full_name = `Le nom doit contenir entre ${LIMITS.fullNameMin} et ${LIMITS.fullNameMax} caractères.`;
  }

  const rawEmail = cleanText(body.email);
  const email = rawEmail ? rawEmail.toLowerCase() : null;
  if (email && (!EMAIL_RE.test(email) || email.length > LIMITS.emailMax)) {
    errors.email = "Adresse e-mail invalide.";
  }

  const rawPhone = cleanText(body.phone);
  const phone = rawPhone ? normalizePhone(rawPhone) : null;
  if (rawPhone && !phone) {
    errors.phone = "Numéro de téléphone invalide (format international attendu, ex. +221 77 123 45 67).";
  }

  if (!email && !rawPhone) {
    errors.contact = "Un e-mail ou un numéro de téléphone est requis.";
  }

  let preferred_contact: ContactMethod | null = null;
  if (body.preferred_contact != null && body.preferred_contact !== "") {
    if (CONTACT_METHODS.includes(body.preferred_contact as ContactMethod)) {
      preferred_contact = body.preferred_contact as ContactMethod;
    } else {
      errors.preferred_contact = "Moyen de contact invalide.";
    }
  }
  if (preferred_contact === "email" && !email) errors.email = "E-mail requis pour être contacté par e-mail.";
  if ((preferred_contact === "phone" || preferred_contact === "whatsapp") && !rawPhone) {
    errors.phone = "Numéro requis pour être contacté par téléphone ou WhatsApp.";
  }

  return {
    full_name,
    email,
    phone,
    preferred_contact,
    consent_marketing: body.consent_marketing === true,
    page_url: cleanUrl(body.page_url),
    utm: pickUtm(body.utm),
  };
}

export function validateInquiry(body: unknown): ValidationResult<InquiryInput> {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, errors: { body: "Corps JSON invalide." } };
  }
  const b = body as Record<string, unknown>;
  const errors: FieldErrors = {};
  const contact = validateContact(b, errors);

  const message = cleanText(b.message);
  if (message && message.length > LIMITS.inquiryMessageMax) {
    errors.message = `Le message ne doit pas dépasser ${LIMITS.inquiryMessageMax} caractères.`;
  }

  let property_id: string | null = null;
  if (b.property_id != null && b.property_id !== "") {
    if (isUuid(b.property_id)) property_id = b.property_id.toLowerCase();
    else errors.property_id = "Identifiant de bien invalide.";
  }

  let inquiry_type: InquiryType = property_id ? "property_info" : "general";
  if (b.inquiry_type != null && b.inquiry_type !== "") {
    if (INQUIRY_TYPES.includes(b.inquiry_type as InquiryType)) inquiry_type = b.inquiry_type as InquiryType;
    else errors.inquiry_type = "Type de demande invalide.";
  }

  if (!message && !property_id) {
    errors.message = "Merci de préciser votre demande.";
  }

  if (Object.keys(errors).length > 0) return { ok: false, errors };
  return { ok: true, data: { ...contact, message, property_id, inquiry_type } };
}

export function validateViewingRequest(body: unknown, now: Date = new Date()): ValidationResult<ViewingRequestInput> {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, errors: { body: "Corps JSON invalide." } };
  }
  const b = body as Record<string, unknown>;
  const errors: FieldErrors = {};
  const contact = validateContact(b, errors);

  if (!contact.phone && !errors.phone) {
    errors.phone = "Un numéro de téléphone est requis pour organiser une visite.";
  }

  if (!isUuid(b.property_id)) errors.property_id = "Identifiant de bien requis.";

  const today = todayInDakar(now);
  const maxDate = addDays(today, LIMITS.maxDaysAhead);
  const checkDate = (field: string, v: unknown): string | null => {
    if (v == null || v === "") return null;
    if (typeof v !== "string" || !isValidIsoDate(v)) {
      errors[field] = "Date invalide (format AAAA-MM-JJ).";
      return null;
    }
    if (v < today || v > maxDate) {
      errors[field] = `La date doit être comprise entre aujourd'hui et ${LIMITS.maxDaysAhead} jours.`;
      return null;
    }
    return v;
  };
  const preferred_date = checkDate("preferred_date", b.preferred_date);
  const alternative_date = checkDate("alternative_date", b.alternative_date);

  let preferred_time_slot: TimeSlot = "any";
  if (b.preferred_time_slot != null && b.preferred_time_slot !== "") {
    if (TIME_SLOTS.includes(b.preferred_time_slot as TimeSlot)) preferred_time_slot = b.preferred_time_slot as TimeSlot;
    else errors.preferred_time_slot = "Créneau invalide.";
  }

  const message = cleanText(b.message);
  if (message && message.length > LIMITS.viewingMessageMax) {
    errors.message = `Le message ne doit pas dépasser ${LIMITS.viewingMessageMax} caractères.`;
  }

  if (Object.keys(errors).length > 0) return { ok: false, errors };
  return {
    ok: true,
    data: {
      ...contact,
      phone: contact.phone as string,
      property_id: (b.property_id as string).toLowerCase(),
      preferred_date,
      preferred_time_slot,
      alternative_date,
      message,
    },
  };
}

/**
 * Détection silencieuse des robots :
 * - champ piège `website` (invisible pour un humain) rempli ;
 * - formulaire soumis trop vite après son affichage (`form_started_at`, ms epoch).
 */
export function looksLikeBot(body: unknown, now: number = Date.now()): boolean {
  if (!body || typeof body !== "object") return false;
  const b = body as Record<string, unknown>;
  if (typeof b.website === "string" && b.website.trim() !== "") return true;
  if (typeof b.form_started_at === "number" && Number.isFinite(b.form_started_at)) {
    const elapsed = now - b.form_started_at;
    if (elapsed >= 0 && elapsed < LIMITS.minFillTimeMs) return true;
  }
  return false;
}
