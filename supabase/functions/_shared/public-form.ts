// =============================================================================
// Pipeline commun des formulaires publics.
//   1. CORS / méthode / origine
//   2. Taille et analyse du corps JSON
//   3. Détection silencieuse des robots (champ piège, délai de saisie)
//   4. CAPTCHA (si TURNSTILE_SECRET_KEY est configuré)
//   5. Validation stricte des champs
//   6. Appel de la RPC SECURITY DEFINER (service_role) : dédoublonnage,
//      limitation de débit par empreinte IP et par coordonnée, affectation.
// =============================================================================
import { adminClient } from "./supabase.ts";
import { corsHeaders, errorResponse, isOriginAllowed, json, mapDbError, readJsonBody } from "./http.ts";
import { getClientIp, hashIp, verifyCaptcha } from "./security.ts";
import { LIMITS, looksLikeBot, type ValidationResult } from "./validation.ts";

interface PublicFormOptions<T> {
  validate: (body: unknown) => ValidationResult<T>;
  rpc: "submit_inquiry" | "submit_viewing_request";
  toParams: (data: T, ipHash: string | null, meta: Record<string, unknown>) => Record<string, unknown>;
  idKey: "inquiry_id" | "viewing_request_id";
}

export function servePublicForm<T extends { page_url: string | null; utm: Record<string, string> }>(
  opts: PublicFormOptions<T>,
) {
  return async (req: Request): Promise<Response> => {
    const origin = req.headers.get("origin");
    const allowed = Deno.env.get("ALLOWED_ORIGINS");
    const cors = corsHeaders(origin, allowed);

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (req.method !== "POST") {
      return errorResponse(405, { code: "METHOD_NOT_ALLOWED", message: "Méthode non autorisée." }, cors);
    }
    if (!isOriginAllowed(origin, allowed)) {
      return errorResponse(403, { code: "ORIGIN_NOT_ALLOWED", message: "Origine non autorisée." }, cors);
    }

    const parsed = await readJsonBody(req, LIMITS.maxBodyBytes);
    if (!parsed.ok) return errorResponse(parsed.status, parsed.error, cors);
    const body = parsed.body as Record<string, unknown>;

    // Robot détecté : réponse de succès factice, rien n'est enregistré.
    if (looksLikeBot(body)) {
      return json({ data: { id: crypto.randomUUID(), duplicate: false } }, 201, cors);
    }

    const ip = getClientIp(req);
    if (!(await verifyCaptcha(body?.captcha_token, ip, Deno.env.get("TURNSTILE_SECRET_KEY")))) {
      return errorResponse(400, { code: "CAPTCHA_FAILED", message: "Vérification anti-robot échouée." }, cors);
    }

    const result = opts.validate(body);
    if (!result.ok) {
      return errorResponse(422, {
        code: "VALIDATION_ERROR",
        message: "Certains champs sont invalides.",
        fields: result.errors,
      }, cors);
    }

    const salt = Deno.env.get("RATE_LIMIT_SALT") ?? "abs-immo-local-dev-salt";
    const ipHash = await hashIp(ip, salt);
    const meta: Record<string, unknown> = {
      user_agent: (req.headers.get("user-agent") ?? "").slice(0, 300),
      page_url: result.data.page_url,
      utm: result.data.utm,
      origin,
    };

    const { data, error } = await adminClient().rpc(opts.rpc, opts.toParams(result.data, ipHash, meta));
    if (error) {
      const mapped = mapDbError(error);
      if (mapped.status >= 500) console.error(`[${opts.rpc}]`, error);
      return errorResponse(mapped.status, mapped.error, cors);
    }

    const row = data as Record<string, unknown>;
    return json({ data: { id: row[opts.idKey], duplicate: row.duplicate === true } }, row.duplicate ? 200 : 201, cors);
  };
}
