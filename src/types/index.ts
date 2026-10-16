// Point d'entrée des types partagés avec abs-immo-frontend et abs-immo-backoffice.
// Usage côté React : createClient<Database>(url, publishableKey)
export type { Database, Json } from "./database.types.ts";
export * from "./contracts.ts";
