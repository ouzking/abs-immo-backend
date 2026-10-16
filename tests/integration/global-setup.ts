// Récupère l'URL et les clés de la pile Supabase LOCALE via `supabase status`.
// Aucune clé n'est écrite dans le dépôt. Les tests unitaires n'en dépendent pas.
import { execSync } from "node:child_process";
import type { TestProject } from "vitest/node";

export interface LocalSupabase {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
  functionsUrl: string;
}

declare module "vitest" {
  export interface ProvidedContext {
    supabase: LocalSupabase | null;
  }
}

export default function setup(project: TestProject) {
  let env: LocalSupabase | null = null;
  try {
    const raw = execSync("npx supabase status -o json", { stdio: ["ignore", "pipe", "ignore"], timeout: 60_000 }).toString();
    const s = JSON.parse(raw.slice(raw.indexOf("{")));
    env = {
      url: s.API_URL,
      anonKey: s.ANON_KEY,
      serviceRoleKey: s.SERVICE_ROLE_KEY,
      functionsUrl: s.FUNCTIONS_URL ?? `${s.API_URL}/functions/v1`,
    };
  } catch {
    env = null; // pile locale arrêtée : seuls les tests unitaires peuvent s'exécuter
  }
  project.provide("supabase", env);
}
