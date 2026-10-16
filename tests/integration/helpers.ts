import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { inject } from "vitest";
import type { Database } from "../../src/types/index.ts";

export const DEMO_PASSWORD = "AbsImmo-Local-2026"; // comptes de démonstration du seed LOCAL
export const DEMO = {
  superAdmin: "superadmin@abs-immo.test",
  admin: "admin@abs-immo.test",
  manager: "manager@abs-immo.test",
  agent1: "agent1@abs-immo.test",
  agent2: "agent2@abs-immo.test",
} as const;

export function local() {
  const env = inject("supabase");
  if (!env) throw new Error("Pile Supabase locale introuvable : lancez `npm run db:start` puis `npm run db:reset`.");
  return env;
}

const opts = { auth: { persistSession: false, autoRefreshToken: false } };

export function anonClient(): SupabaseClient<Database> {
  const env = local();
  return createClient<Database>(env.url, env.anonKey, opts);
}

export function serviceClient(): SupabaseClient<Database> {
  const env = local();
  return createClient<Database>(env.url, env.serviceRoleKey, opts);
}

export async function signIn(email: string, password = DEMO_PASSWORD) {
  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`Connexion impossible pour ${email} : ${error.message}`);
  return { client, session: data.session!, user: data.user! };
}

/** Appel brut d'une Edge Function (pour contrôler statut et en-têtes). */
export async function callFunction(
  name: string,
  body: unknown,
  init: { token?: string; headers?: Record<string, string>; method?: string; rawBody?: string } = {},
) {
  const env = local();
  const res = await fetch(`${env.functionsUrl}/${name}`, {
    method: init.method ?? "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: env.anonKey,
      Authorization: `Bearer ${init.token ?? env.anonKey}`,
      ...init.headers,
    },
    body: init.method === "GET" ? undefined : init.rawBody ?? JSON.stringify(body),
  });
  const text = await res.text();
  let json: any = null;
  try { json = JSON.parse(text); } catch { /* corps non JSON */ }
  return { status: res.status, json, headers: res.headers };
}

export const randomIp = () => `10.${rand(255)}.${rand(255)}.${rand(255)}`;
const rand = (n: number) => Math.floor(Math.random() * n);
/** Mobile sénégalais aléatoire au format local (9 chiffres). */
export const randomSnPhone = () => `77${String(rand(1e7)).padStart(7, "0")}`;
export const uniqueEmail = (prefix: string) => `${prefix}.${Date.now()}.${rand(1e6)}@example.sn`;

/** JPEG minimal valide (1×1 px). */
export const TINY_JPEG = Uint8Array.from(Buffer.from(
  "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=",
  "base64",
));
