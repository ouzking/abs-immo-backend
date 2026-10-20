// =============================================================================
// ABS IMMO & SERVICES — Contrats d'intégration (frontend public + back-office)
// -----------------------------------------------------------------------------
// Ce fichier complète `database.types.ts` (généré depuis le schéma) avec :
//   * les alias métier lisibles ;
//   * les formes JSON renvoyées par les RPC qui retournent `jsonb` ;
//   * les corps/réponses des Edge Functions ;
//   * les codes d'erreur ;
//   * les conventions Storage.
// Source de vérité : les migrations SQL. Toute évolution est versionnée ici et
// documentée dans docs/INTEGRATION_CONTRACT.md (§ Compatibilité).
// =============================================================================
import type { Database } from "./database.types.ts";

export const CONTRACT_VERSION = "1.1.0";

type PublicSchema = Database["public"];
export type Tables<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Row"];
export type TablesInsert<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Insert"];
export type TablesUpdate<T extends keyof PublicSchema["Tables"]> = PublicSchema["Tables"][T]["Update"];
export type Views<T extends keyof PublicSchema["Views"]> = PublicSchema["Views"][T]["Row"];
export type Enums<T extends keyof PublicSchema["Enums"]> = PublicSchema["Enums"][T];
export type RpcArgs<T extends keyof PublicSchema["Functions"]> = PublicSchema["Functions"][T]["Args"];

// -----------------------------------------------------------------------------
// Énumérations métier
// -----------------------------------------------------------------------------
export type TransactionType = Enums<"transaction_type">;       // 'sale' | 'rent'
export type RentPeriod = Enums<"rent_period">;
export type PublicationStatus = Enums<"publication_status">;   // draft | pending_review | published | unpublished | archived
export type CommercialStatus = Enums<"commercial_status">;     // available | reserved | sold | rented
export type SurfaceUnit = Enums<"surface_unit">;
export type AddressVisibility = Enums<"address_visibility">;
export type LegalStatus = Enums<"property_legal_status">;
export type LeadStatus = Enums<"lead_status">;
export type LeadSource = Enums<"lead_source">;
export type InquiryType = Enums<"inquiry_type">;
export type InquiryStatus = Enums<"inquiry_status">;
export type ViewingStatus = Enums<"viewing_status">;
export type TimeSlot = Enums<"time_slot">;
export type ContactMethod = Enums<"contact_method">;
export type LeadActivityType = Enums<"lead_activity_type">;
export type DocumentType = Enums<"property_document_type">;

/** Activités qu'un utilisateur peut saisir ; les autres sont produites par le système. */
export const MANUAL_ACTIVITY_TYPES = ["note", "call", "email", "whatsapp", "sms", "meeting", "visit"] as const satisfies readonly LeadActivityType[];

export const ROLE_CODES = ["super_admin", "admin", "sales_manager", "agent"] as const;
export type RoleCode = (typeof ROLE_CODES)[number];

export const PERMISSION_CODES = [
  "properties.read_all", "properties.create", "properties.update_own", "properties.update_all",
  "properties.publish", "properties.delete",
  "leads.access_assigned", "leads.read_all", "leads.create", "leads.update_all", "leads.assign", "leads.delete",
  "agents.manage", "users.read", "users.manage", "roles.assign",
  "catalog.manage", "settings.manage", "stats.read_own", "stats.read_all", "audit.read",
] as const;
export type PermissionCode = (typeof PERMISSION_CODES)[number];

// -----------------------------------------------------------------------------
// Entités (lignes de tables / vues)
// -----------------------------------------------------------------------------
export type Property = Tables<"properties">;
export type PropertyInsert = TablesInsert<"properties">;
export type PropertyUpdate = TablesUpdate<"properties">;
export type PropertyMedia = Tables<"property_media">;
export type PropertyDocument = Tables<"property_documents">;
export type PropertyFeature = Tables<"property_features">;
export type Lead = Tables<"leads">;
export type Inquiry = Tables<"inquiries">;
export type ViewingRequest = Tables<"viewing_requests">;
export type LeadActivity = Tables<"lead_activities">;
export type Profile = Tables<"profiles">;
export type Agent = Tables<"agents">;
export type Locality = Tables<"localities">;
export type PropertyType = Tables<"property_types">;
export type Amenity = Tables<"amenities">;
export type AgencySettings = Tables<"agency_settings">;
export type AppSetting = Tables<"app_settings">;
export type AuditLog = Tables<"audit_logs">;

export type PublicProperty = Views<"public_properties">;
export type PublicPropertyMedia = Views<"public_property_media">;
export type PublicAgent = Views<"public_agents">;

/** Agent tel qu'exposé dans `public_properties.agent` (null si non public). */
export interface PublicPropertyAgent {
  slug: string;
  display_name: string;
  job_title: string | null;
  public_phone: string | null;
  whatsapp_phone: string | null;
  public_email: string | null;
  photo_path: string | null;
}

/** Colonnes conseillées pour une carte d'annonce (liste). */
export const PROPERTY_CARD_COLUMNS =
  "id,reference,slug,title,short_description,property_type,property_type_label,transaction_type," +
  "price_amount,currency_code,price_on_request,rent_period,surface_area,surface_unit,bedrooms,bathrooms," +
  "city_name,neighborhood_name,commercial_status,is_featured,published_at,cover_image_path,cover_image_alt,image_count";

/** Colonnes anglaises à ajouter à une carte pour le site en anglais (1.1.0). */
export const PROPERTY_CARD_COLUMNS_EN = "title_en,short_description_en,property_type_label_en,has_english";

export type PropertyCard = Pick<
  PublicProperty,
  | "id" | "reference" | "slug" | "title" | "short_description" | "property_type" | "property_type_label"
  | "transaction_type" | "price_amount" | "currency_code" | "price_on_request" | "rent_period" | "surface_area"
  | "surface_unit" | "bedrooms" | "bathrooms" | "city_name" | "neighborhood_name" | "commercial_status"
  | "is_featured" | "published_at" | "cover_image_path" | "cover_image_alt" | "image_count"
>;

// -----------------------------------------------------------------------------
// RPC publiques
// -----------------------------------------------------------------------------
export type SearchPropertiesParams = RpcArgs<"search_properties">;
export type SearchSort = "relevance" | "newest" | "oldest" | "price_asc" | "price_desc" | "surface_desc" | "featured";

/** Réponse de `get_public_property` (null si introuvable ou non publiée). */
export type PublicPropertyDetail = Omit<PublicProperty, "search_vector" | "agent"> & {
  agent: PublicPropertyAgent | null;
  images: Array<{
    id: string;
    storage_path: string;
    alt_text: string | null;
    sort_order: number;
    is_cover: boolean;
    width: number | null;
    height: number | null;
  }>;
  amenities: Array<{ code: string; label: string; label_en: string | null; category: string; icon: string | null }>;
  features: Array<{ label: string; value: string | null }>;
};

/** Réponse de `get_public_filters`. */
export interface PublicFilters {
  transaction_types: Array<{ value: TransactionType; count: number }>;
  property_types: Array<{
    code: string;
    label: string;
    label_plural: string;
    label_en: string | null;
    label_plural_en: string | null;
    count: number;
  }>;
  cities: Array<{ id: string; name: string; slug: string; region_name: string; count: number }>;
  neighborhoods: Array<{ id: string; name: string; slug: string; city_id: string; count: number }>;
  price_ranges: Partial<Record<TransactionType, { min: number; max: number }>>;
}

// -----------------------------------------------------------------------------
// RPC back-office
// -----------------------------------------------------------------------------
/** Réponse de `get_my_access`. */
export interface MyAccess {
  user_id: string;
  email: string | null;
  full_name: string;
  is_active: boolean;
  is_agent: boolean;
  rank: number;
  roles: RoleCode[];
  permissions: PermissionCode[];
}

/** Ligne de `list_users`. */
export interface UserListItem {
  id: string;
  email: string | null;
  full_name: string;
  phone: string | null;
  is_active: boolean;
  last_sign_in_at: string | null;
  created_at: string;
  roles: RoleCode[];
  rank: number;
  is_agent: boolean;
  can_manage: boolean;
}

/** Réponse de `get_dashboard_stats`. Définitions : docs/STATISTICS.md. */
export interface DashboardStats {
  scope: { agent_id: string | null; from: string; to: string };
  properties: {
    total: number; archived: number; draft: number; pending_review: number; published: number; unpublished: number;
    available: number; reserved: number; sold: number; rented: number;
    sold_in_period: number; rented_in_period: number; published_in_period: number;
    by_type: Array<{ property_type: string; transaction_type: TransactionType; total: number; published: number }>;
    by_transaction: Partial<Record<TransactionType, number>>;
  };
  inquiries: {
    received_in_period: number; pending: number; in_progress: number; answered_in_period: number;
    spam_in_period: number; median_response_hours: number | null;
  };
  viewings: { requested_in_period: number; pending: number; upcoming: number; completed_in_period: number };
  leads: { new_in_period: number; open: number; unassigned: number; by_status: Partial<Record<LeadStatus, number>> };
}

export type AgentPerformanceRow = PublicSchema["Functions"]["get_agent_performance"]["Returns"][number];
export type InquiryTimeseriesRow = PublicSchema["Functions"]["get_inquiry_timeseries"]["Returns"][number];

// -----------------------------------------------------------------------------
// Edge Functions
// -----------------------------------------------------------------------------
/** Champs anti-robot communs aux formulaires publics. */
export interface AntiBotFields {
  /** Champ piège : à rendre invisible (CSS) et laisser VIDE. */
  website?: string;
  /** Date.now() au moment de l'affichage du formulaire. */
  form_started_at?: number;
  /** Jeton Cloudflare Turnstile (obligatoire si activé côté serveur). */
  captcha_token?: string;
}

export interface UtmParams {
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_term?: string;
  utm_content?: string;
}

/** POST /functions/v1/submit-inquiry */
export interface SubmitInquiryRequest extends AntiBotFields {
  full_name: string;                 // 2–120 caractères
  email?: string | null;             // e-mail OU téléphone obligatoire
  phone?: string | null;             // normalisé E.164 (+221 par défaut pour 9 chiffres)
  message?: string | null;           // ≤ 5000 ; obligatoire si aucun bien
  property_id?: string | null;       // uuid d'une annonce publiée
  inquiry_type?: InquiryType;        // défaut : property_info si bien, sinon general
  preferred_contact?: ContactMethod | null;
  consent_marketing?: boolean;
  page_url?: string | null;
  utm?: UtmParams;
}

/** POST /functions/v1/submit-viewing-request */
export interface SubmitViewingRequest extends AntiBotFields {
  full_name: string;
  phone: string;                     // obligatoire pour une visite
  email?: string | null;
  property_id: string;               // annonce publiée, disponible ou réservée
  preferred_date?: string | null;    // AAAA-MM-JJ, aujourd'hui → +120 jours
  preferred_time_slot?: TimeSlot;    // défaut : any
  alternative_date?: string | null;
  message?: string | null;           // ≤ 2000
  preferred_contact?: ContactMethod | null;
  consent_marketing?: boolean;
  page_url?: string | null;
  utm?: UtmParams;
}

/** 201 (créée) ou 200 (doublon déjà enregistré). */
export interface SubmitResponse {
  data: { id: string; duplicate: boolean };
}

/** POST /functions/v1/admin-users (Authorization: Bearer <access_token>) */
export type AdminUsersRequest =
  | {
    action: "invite";
    email: string;
    full_name: string;
    role: RoleCode;
    phone?: string | null;
    create_agent_profile?: boolean;
    redirect_to?: string | null;
  }
  | {
    action: "create";
    email: string;
    password: string;                // ≥ 10 caractères, minuscule + majuscule + chiffre
    full_name: string;
    role: RoleCode;
    phone?: string | null;
    create_agent_profile?: boolean;
  }
  | { action: "deactivate" | "reactivate"; user_id: string }
  | { action: "send_password_reset"; user_id: string; redirect_to?: string | null };

export type AdminUsersResponse =
  | { data: { user_id: string; email: string; role: RoleCode; agent_profile_created: boolean; warning?: string } }
  | { data: { user_id: string; is_active: boolean } }
  | { data: { user_id: string; email_sent: true } };

// -----------------------------------------------------------------------------
// Erreurs
// -----------------------------------------------------------------------------
/** Codes renvoyés par les Edge Functions : { error: { code, message, fields? } } */
export type ApiErrorCode =
  | "VALIDATION_ERROR" | "INVALID_JSON" | "PAYLOAD_TOO_LARGE" | "METHOD_NOT_ALLOWED" | "ORIGIN_NOT_ALLOWED"
  | "CAPTCHA_FAILED" | "RATE_LIMITED" | "PROPERTY_UNAVAILABLE" | "UNAUTHENTICATED" | "FORBIDDEN" | "NOT_FOUND"
  | "CONFLICT" | "BUSINESS_RULE_VIOLATION" | "INVALID_PARAMETER" | "INTERNAL_ERROR";

export interface ApiErrorBody {
  error: { code: ApiErrorCode; message: string; fields?: Record<string, string> };
}

/**
 * Codes SQLSTATE renvoyés par PostgREST (champ `error.code` de supabase-js)
 * lors des appels directs aux tables / RPC.
 */
export const DB_ERROR_CODES = {
  FORBIDDEN: "42501",            // permission/RLS/garde-fou
  BUSINESS_RULE: "23514",        // contrainte CHECK ou règle métier (voir error.hint)
  UNIQUE_VIOLATION: "23505",     // ex. slug déjà utilisé
  FOREIGN_KEY: "23503",
  NOT_FOUND: "P0002",
  INVALID_PARAMETER: "22023",
  NO_ROWS_FOR_SINGLE: "PGRST116", // .single() sans résultat (ex. ligne filtrée par RLS)
} as const;

/** Valeurs de `error.hint` pour les règles de publication. */
export const BUSINESS_RULE_HINTS = {
  PUBLISH_REQUIRES_COVER: "PUBLISH_REQUIRES_COVER",
  PUBLISH_REQUIRES_SHORT_DESCRIPTION: "PUBLISH_REQUIRES_SHORT_DESCRIPTION",
  LAST_MEDIA_OF_PUBLISHED_PROPERTY: "LAST_MEDIA_OF_PUBLISHED_PROPERTY",
} as const;

// -----------------------------------------------------------------------------
// Storage
// -----------------------------------------------------------------------------
export const STORAGE_BUCKETS = {
  /** PRIVÉ — lecture publique par URL signée, uniquement pour les annonces publiées. */
  propertyImages: "property-images",
  /** PRIVÉ — documents internes. */
  propertyDocuments: "property-documents",
  /** PUBLIC — photos des agents. Chemin : <profile_id>/<fichier> */
  agentPhotos: "agent-photos",
  /** PUBLIC — logo et visuels. Écriture : settings.manage */
  siteAssets: "site-assets",
} as const;

export const STORAGE_LIMITS = {
  "property-images": { maxBytes: 10 * 1024 * 1024, mime: ["image/jpeg", "image/png", "image/webp", "image/avif"] },
  "property-documents": {
    maxBytes: 20 * 1024 * 1024,
    mime: ["application/pdf", "image/jpeg", "image/png", "image/webp",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"],
  },
  "agent-photos": { maxBytes: 3 * 1024 * 1024, mime: ["image/jpeg", "image/png", "image/webp"] },
  "site-assets": { maxBytes: 5 * 1024 * 1024, mime: ["image/jpeg", "image/png", "image/webp", "image/x-icon"] },
} as const;

const EXT_BY_MIME: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/avif": "avif",
  "application/pdf": "pdf",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
  "image/x-icon": "ico",
};

/**
 * Chemin d'un fichier de bien : "<property_id>/<uuid>.<ext>".
 * Les politiques Storage et la contrainte property_media_path_prefix
 * exigent exactement ce format (un seul niveau de dossier).
 */
export function propertyFilePath(propertyId: string, mimeType: string, fileId: string = crypto.randomUUID()): string {
  const ext = EXT_BY_MIME[mimeType];
  if (!ext) throw new Error(`Type de fichier non pris en charge : ${mimeType}`);
  return `${propertyId}/${fileId}.${ext}`;
}

// -----------------------------------------------------------------------------
// Internationalisation (1.1.0)
// -----------------------------------------------------------------------------
export type SiteLocale = "fr" | "en" | "wo";

/**
 * Texte localisé avec repli sur le français : les champs *_en sont facultatifs.
 * Le wolof utilise le contenu français tant qu'aucune traduction n'existe.
 */
export function localized(fr: string | null, en: string | null | undefined, locale: SiteLocale): string | null {
  return locale === "en" && en ? en : fr;
}

/** Formate un prix en FCFA : 150000000 -> "150 000 000 FCFA". */
export function formatPriceXof(amount: number | null, rentPeriod?: RentPeriod | null): string {
  if (amount === null) return "Prix sur demande";
  const n = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 }).format(amount).replace(/ | /g, " ");
  const suffix = rentPeriod ? { day: " / jour", week: " / semaine", month: " / mois", year: " / an" }[rentPeriod] : "";
  return `${n} FCFA${suffix}`;
}
