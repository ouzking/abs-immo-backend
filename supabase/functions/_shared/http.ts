// =============================================================================
// Réponses HTTP, CORS et traduction des erreurs PostgreSQL — module PUR.
// Format d'erreur unique pour toutes les fonctions :
//   { "error": { "code": "VALIDATION_ERROR", "message": "…", "fields": { … } } }
// =============================================================================

export type ErrorCode =
  | "VALIDATION_ERROR"
  | "INVALID_JSON"
  | "PAYLOAD_TOO_LARGE"
  | "METHOD_NOT_ALLOWED"
  | "ORIGIN_NOT_ALLOWED"
  | "CAPTCHA_FAILED"
  | "RATE_LIMITED"
  | "PROPERTY_UNAVAILABLE"
  | "UNAUTHENTICATED"
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "BUSINESS_RULE_VIOLATION"
  | "INVALID_PARAMETER"
  | "INTERNAL_ERROR";

export interface ApiError {
  code: ErrorCode;
  message: string;
  fields?: Record<string, string>;
}

/** Calcule les en-têtes CORS. `allowedOrigins` vide ou "*" = toutes origines. */
export function corsHeaders(origin: string | null, allowedOrigins: string | undefined): Record<string, string> {
  const list = (allowedOrigins ?? "*").split(",").map((s) => s.trim()).filter(Boolean);
  const allowAll = list.length === 0 || list.includes("*");
  const allowOrigin = allowAll ? "*" : origin && list.includes(origin) ? origin : list[0];
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

export function isOriginAllowed(origin: string | null, allowedOrigins: string | undefined): boolean {
  const list = (allowedOrigins ?? "*").split(",").map((s) => s.trim()).filter(Boolean);
  if (list.length === 0 || list.includes("*")) return true;
  // Les appels serveur-à-serveur (sans en-tête Origin) restent possibles.
  return origin === null || list.includes(origin);
}

export function json(body: unknown, status: number, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });
}

export function errorResponse(status: number, error: ApiError, headers: Record<string, string> = {}): Response {
  return json({ error }, status, headers);
}

interface PgLikeError {
  code?: string;
  message?: string;
  hint?: string | null;
  details?: string | null;
}

/** Traduit une erreur PostgREST/PostgreSQL en statut HTTP + erreur d'API. */
export function mapDbError(err: PgLikeError): { status: number; error: ApiError } {
  const message = err.message ?? "Erreur inattendue.";
  switch (err.code) {
    case "AB422":
      return {
        status: 422,
        error: { code: "VALIDATION_ERROR", message, fields: err.hint ? { [err.hint]: message } : undefined },
      };
    case "AB404":
      return { status: 404, error: { code: "PROPERTY_UNAVAILABLE", message } };
    case "AB429":
      return { status: 429, error: { code: "RATE_LIMITED", message } };
    case "42501":
      return { status: 403, error: { code: "FORBIDDEN", message } };
    case "P0002":
      return { status: 404, error: { code: "NOT_FOUND", message } };
    case "23505":
      return { status: 409, error: { code: "CONFLICT", message } };
    case "23514":
    case "23503":
      return { status: 409, error: { code: "BUSINESS_RULE_VIOLATION", message } };
    case "22023":
    case "22P02":
      return { status: 400, error: { code: "INVALID_PARAMETER", message } };
    default:
      return { status: 500, error: { code: "INTERNAL_ERROR", message: "Erreur interne. Veuillez réessayer." } };
  }
}

/** Lit un corps JSON en limitant sa taille. */
export async function readJsonBody(
  req: Request,
  maxBytes: number,
): Promise<{ ok: true; body: unknown } | { ok: false; status: number; error: ApiError }> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) {
    return { ok: false, status: 413, error: { code: "PAYLOAD_TOO_LARGE", message: "Requête trop volumineuse." } };
  }
  const text = await req.text();
  if (new TextEncoder().encode(text).length > maxBytes) {
    return { ok: false, status: 413, error: { code: "PAYLOAD_TOO_LARGE", message: "Requête trop volumineuse." } };
  }
  try {
    return { ok: true, body: JSON.parse(text) };
  } catch {
    return { ok: false, status: 400, error: { code: "INVALID_JSON", message: "Corps JSON invalide." } };
  }
}
