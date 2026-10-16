// =============================================================================
// Sécurité des formulaires publics : empreinte IP, CAPTCHA Cloudflare Turnstile.
// Aucune adresse IP n'est stockée en clair : seule une empreinte SHA-256 salée
// (secret RATE_LIMIT_SALT) est conservée pour la limitation de débit.
// =============================================================================

export function getClientIp(req: Request): string | null {
  const cf = req.headers.get("cf-connecting-ip");
  if (cf) return cf.trim();
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  return req.headers.get("x-real-ip");
}

export async function hashIp(ip: string | null, salt: string): Promise<string | null> {
  if (!ip) return null;
  const data = new TextEncoder().encode(`${salt}|${ip}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Vérifie un jeton Turnstile si TURNSTILE_SECRET_KEY est configuré.
 * Sans secret configuré, la vérification est désactivée (développement local).
 */
export async function verifyCaptcha(
  token: unknown,
  ip: string | null,
  secret: string | undefined,
  fetchImpl: typeof fetch = fetch,
): Promise<boolean> {
  if (!secret) return true;
  if (typeof token !== "string" || token.length === 0 || token.length > 2048) return false;
  const form = new FormData();
  form.append("secret", secret);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  try {
    const res = await fetchImpl("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: form,
    });
    const data = (await res.json()) as { success?: boolean };
    return data.success === true;
  } catch {
    return false;
  }
}
