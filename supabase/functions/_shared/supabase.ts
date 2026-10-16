// =============================================================================
// Clients Supabase côté serveur (Edge Functions uniquement).
// La clé service_role n'existe QUE dans l'environnement des Edge Functions
// (injectée automatiquement par Supabase) — jamais dans les applications React.
// =============================================================================
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

function env(...names: string[]): string {
  for (const n of names) {
    const v = Deno.env.get(n);
    if (v) return v;
  }
  throw new Error(`Variable d'environnement manquante : ${names.join(" | ")}`);
}

const SUPABASE_URL = () => env("SUPABASE_URL");
const ANON_KEY = () => env("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY");
const SERVICE_KEY = () => env("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY");

const noSession = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

/** Client privilégié (contourne RLS). À n'utiliser qu'après contrôle d'accès. */
export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL(), SERVICE_KEY(), noSession);
}

/** Client agissant au nom de l'appelant : RLS et permissions s'appliquent. */
export function userClient(accessToken: string): SupabaseClient {
  return createClient(SUPABASE_URL(), ANON_KEY(), {
    ...noSession,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}

/** Client anonyme (ex. envoi d'un e-mail de réinitialisation). */
export function anonClient(): SupabaseClient {
  return createClient(SUPABASE_URL(), ANON_KEY(), noSession);
}

export function bearerToken(req: Request): string | null {
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : null;
}
