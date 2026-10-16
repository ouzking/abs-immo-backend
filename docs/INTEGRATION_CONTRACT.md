# Contrat d'intégration — ABS IMMO & SERVICES

**Version du contrat : 1.0.0** (`CONTRACT_VERSION` dans `src/types/contracts.ts`)
Public visé : équipes `abs-immo-frontend` (site public) et `abs-immo-backoffice` (back-office).

> Le dépôt `abs-immo-backend` est **l'unique responsable du schéma**. Les applications React ne créent
> ni table, ni vue, ni fonction, ni politique, ni bucket. Tout besoin passe par une migration de ce dépôt.

---

## 1. Connexion

```ts
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@abs-immo/backend/types"; // ou copie de src/types

export const supabase = createClient<Database>(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY, // clé publique : sûre côté navigateur grâce à RLS
);
```

| Variable | Où | Secret ? |
|---|---|---|
| `VITE_SUPABASE_URL` | les deux apps | non |
| `VITE_SUPABASE_PUBLISHABLE_KEY` (ou ancienne clé `anon`) | les deux apps | non |
| `VITE_TURNSTILE_SITE_KEY` | site public, si CAPTCHA activé | non |
| clé `service_role` / `sb_secret_…` | **jamais** dans React | **oui** |

**Partage des types** : `src/types/` est la source. Options : dépendance Git
(`"@abs-immo/backend": "github:<org>/abs-immo-backend#v1.0.0"`, import `@abs-immo/backend/types`)
ou copie du dossier à chaque version taguée. Ne modifiez jamais ces fichiers côté React.

---

## 2. Site public (rôle `anon`)

### 2.1 Ressources lisibles

| Ressource | Type | Contenu |
|---|---|---|
| `public_properties` | vue | Annonces **publiées** uniquement, colonnes publiques |
| `public_property_media` | vue | Photos des annonces publiées |
| `public_agents` | vue | Fiches publiques des agents actifs |
| `agency_settings` | table (1 ligne) | Coordonnées, horaires, réseaux sociaux |
| `localities`, `property_types`, `amenities`, `countries` | tables | Référentiels actifs |
| `search_properties(...)` | RPC | Recherche filtrée/triée/paginable |
| `get_public_property(p_slug, p_reference)` | RPC | Détail complet (photos, équipements, caractéristiques) |
| `get_similar_properties(p_property_id, p_limit)` | RPC | Annonces similaires |
| `get_public_filters()` | RPC | Valeurs de filtres réellement disponibles (avec compteurs) |

Toute autre table (`properties`, `leads`…) renvoie `42501 permission denied` pour `anon`.

### 2.2 Liste et pagination

```ts
import { PROPERTY_CARD_COLUMNS } from "@abs-immo/backend/types";

const pageSize = 12;
const { data, count, error } = await supabase
  .rpc("search_properties", {
    p_transaction_type: "sale",          // 'sale' | 'rent'
    p_property_types: ["villa", "house"],
    p_city_id: cityId,                   // ou p_region_id / p_commune_id / p_neighborhood_id
    p_min_price: 50_000_000,             // FCFA, entiers
    p_max_price: 300_000_000,
    p_min_bedrooms: 3,
    p_amenities: ["swimming_pool"],      // tous requis
    p_query: "piscine vue mer",          // plein texte FR, insensible aux accents
    p_sort: "newest",                    // relevance | newest | oldest | price_asc | price_desc | surface_desc | featured
  }, { count: "exact" })
  .select(PROPERTY_CARD_COLUMNS)
  .range(page * pageSize, page * pageSize + pageSize - 1);
```

* Pagination : `.range(from, to)` (bornes incluses) ; total dans `count`.
* Paramètres tous facultatifs. Filtres PostgREST additionnels possibles après `.select()` (ex. `.eq("city_slug", "dakar")`).
* `p_commercial_statuses: ["available"]` pour masquer les biens vendus/loués (affichés par défaut avec leur statut).
* Annonces en vedette : `p_featured_only: true, p_sort: "featured"`.
* Erreurs : `22023` (tri invalide, budget min > max).

### 2.3 Détail d'une annonce

```ts
const { data } = await supabase.rpc("get_public_property", { p_slug: slug });
// data: PublicPropertyDetail | null  (null => page 404)
```

Champs notables :
* `price_amount` : `null` si `price_on_request` → afficher « Prix sur demande » (`formatPriceXof`).
* `location_precision` : `hidden` (aucune carte), `approximate` (coordonnées arrondies ~1 km, cercle plutôt qu'un marqueur), `exact`.
* `address_line` : non nul uniquement si `exact`.
* `agent` : `null` si l'agent n'est pas public → afficher les coordonnées de l'agence (`agency_settings`).
* `commercial_status` : `available | reserved | sold | rented` → badge.

### 2.4 Photos (bucket privé `property-images`)

Le bucket est **privé** : seules les photos d'annonces publiées peuvent être signées par `anon`.

```ts
const paths = cards.map((c) => c.cover_image_path).filter(Boolean) as string[];
const { data: signed } = await supabase.storage
  .from("property-images")
  .createSignedUrls(paths, 60 * 60 * 24); // 24 h
```

* Une requête par page de résultats (`createSignedUrls`), pas une par image.
* Redimensionnement : `createSignedUrl(path, ttl, { transform: { width: 800, quality: 75 } })` si les transformations d'images sont actives sur le plan Supabase.
* Images Open Graph/SEO : générer côté serveur (SSR) une URL signée longue (ex. 7 jours).
* Photo d'agent / logo : buckets **publics** → `supabase.storage.from("agent-photos").getPublicUrl(path)`.

### 2.5 Formulaires publics (Edge Functions)

Les tables de prospects ne sont **pas** accessibles en écriture à `anon`. Passer **uniquement** par :

| Endpoint | Corps (`SubmitInquiryRequest` / `SubmitViewingRequest`) |
|---|---|
| `POST {SUPABASE_URL}/functions/v1/submit-inquiry` | `full_name`*, `email` ou `phone`*, `message` (* si pas de bien), `property_id`, `inquiry_type`, `preferred_contact`, `consent_marketing`, `page_url`, `utm` |
| `POST {SUPABASE_URL}/functions/v1/submit-viewing-request` | `full_name`*, `phone`*, `property_id`*, `email`, `preferred_date` (AAAA-MM-JJ, aujourd'hui → +120 j), `preferred_time_slot` (`morning|afternoon|evening|any`), `alternative_date`, `message`, … |

```ts
const { data, error } = await supabase.functions.invoke("submit-inquiry", {
  body: {
    full_name, email, phone, message, property_id,
    website: "",                 // champ piège, caché en CSS, laissé vide
    form_started_at: openedAt,   // Date.now() à l'affichage du formulaire
    captcha_token,               // si Turnstile activé
    page_url: location.href,
  },
});
```

Réponses :

| Statut | Corps | Signification |
|---|---|---|
| 201 | `{ data: { id, duplicate: false } }` | Demande créée |
| 200 | `{ data: { id, duplicate: true } }` | Doublon (< 24 h, ou visite déjà ouverte) : afficher le même message de succès |
| 422 | `{ error: { code: "VALIDATION_ERROR", fields: { champ: message } } }` | Erreurs par champ |
| 404 | `PROPERTY_UNAVAILABLE` | Bien non publié / non visitable |
| 429 | `RATE_LIMITED` | Trop de soumissions (5 / 10 min par IP, 30 / jour, 10 / jour par contact) |
| 400 | `CAPTCHA_FAILED`, `INVALID_JSON` | |
| 413 | `PAYLOAD_TOO_LARGE` | Corps > 16 Ko |
| 403 | `ORIGIN_NOT_ALLOWED` | Origine absente de `ALLOWED_ORIGINS` |

Téléphones : saisie libre acceptée (`77 123 45 67`, `+221…`, `00221…`) ; stockage E.164.
Avec `supabase.functions.invoke`, le corps d'erreur s'obtient via `await error.context.json()`.

---

## 3. Back-office (rôle `authenticated`)

### 3.1 Authentification

| Action | Appel |
|---|---|
| Connexion | `supabase.auth.signInWithPassword({ email, password })` |
| Déconnexion | `supabase.auth.signOut()` |
| Mot de passe oublié | `supabase.auth.resetPasswordForEmail(email, { redirectTo: "<backoffice>/reset-password" })` |
| Nouveau mot de passe (après lien) | `supabase.auth.updateUser({ password })` |
| Session | `supabase.auth.getSession()` / `onAuthStateChange` (rafraîchissement automatique) |
| MFA (TOTP, recommandé pour les admins) | `supabase.auth.mfa.enroll/challenge/verify` |
| Droits de l'utilisateur | `supabase.rpc("get_my_access")` → `MyAccess` |

L'inscription publique est **désactivée** : les comptes sont créés par `admin-users`.
Politique de mot de passe : ≥ 10 caractères, minuscule, majuscule, chiffre.
L'interface **doit** masquer les actions non autorisées d'après `permissions`, mais la sécurité réelle est appliquée par la base.

### 3.2 Matrice des rôles

| Permission | super_admin | admin | sales_manager | agent |
|---|:-:|:-:|:-:|:-:|
| properties.read_all (catalogue interne) | ✓ | ✓ | ✓ | ✓ |
| properties.create | ✓ | ✓ | ✓ | ✓ |
| properties.update_own | ✓ | ✓ | ✓ | ✓ |
| properties.update_all (dont changer l'agent) | ✓ | ✓ | ✓ | |
| properties.publish (publier, retirer, archiver, vedette) | ✓ | ✓ | ✓ | |
| properties.delete (suppression définitive) | ✓ | | | |
| leads.access_assigned | ✓ | ✓ | ✓ | ✓ |
| leads.read_all / update_all / assign | ✓ | ✓ | ✓ | |
| leads.create (saisie manuelle) | ✓ | ✓ | ✓ | ✓ |
| leads.delete (effacement) | ✓ | ✓ | | |
| agents.manage | ✓ | ✓ | | |
| users.read | ✓ | ✓ | ✓ | |
| users.manage, roles.assign (rangs inférieurs) | ✓ | ✓ | | |
| catalog.manage, settings.manage, audit.read | ✓ | ✓ | | |
| stats.read_all | ✓ | ✓ | ✓ | |
| stats.read_own | ✓ | ✓ | ✓ | ✓ |

Rangs : super_admin 100 > admin 80 > sales_manager 60 > agent 40. On n'attribue que des rôles de rang **inférieur** au sien (sauf super_admin), on ne gère jamais son propre compte, et le dernier super_admin actif est protégé.

### 3.3 Biens

```ts
// Création (agent : devient responsable automatiquement ; brouillon par défaut)
const { data, error } = await supabase.from("properties").insert({
  title, property_type: "apartment", transaction_type: "rent", rent_period: "month",
  price_amount: 850000, locality_id, short_description, description,
  surface_area: 140, bedrooms: 3, bathrooms: 2, address_line, latitude, longitude,
  address_visibility: "approximate",
}).select().single();
// reference (ABS-L-26xxxxx), slug, région/ville/commune/quartier : générés.
```

| Champ | Règle |
|---|---|
| `title` | 5–160 caractères |
| `price_amount` | entier FCFA > 0, requis sauf `price_on_request = true` |
| `rent_period` | requis si et seulement si `transaction_type = 'rent'` |
| `locality_id` | localité la plus précise connue (quartier > commune > ville > région) |
| `latitude`/`longitude` | ensemble ou aucune |
| `commercial_status` | `sold` uniquement en vente, `rented` uniquement en location |
| Terrain (`property_types.is_land`) | chambres/salles de bain/pièces mises à `null` |
| Non modifiables | `reference`, `created_by`, `created_at`, `published_at`, `search_vector` |

Workflow de publication :

```
draft ⇄ pending_review ──(properties.publish)──▶ published ──▶ unpublished / archived
```

Publication refusée (`23514`) si aucune photo de couverture (`hint = PUBLISH_REQUIRES_COVER`) ou description courte < 20 caractères (`PUBLISH_REQUIRES_SHORT_DESCRIPTION`).
Archiver = `update({ publication_status: "archived" })` ; un bien archivé n'est modifiable que par un responsable.

Équipements : `supabase.rpc("set_property_amenities", { p_property_id, p_amenity_codes: [...] })`.
Caractéristiques libres : CRUD sur `property_features` (`label`, `value`, `sort_order`).

### 3.4 Photos et documents

```ts
import { propertyFilePath } from "@abs-immo/backend/types";

const path = propertyFilePath(propertyId, file.type);  // "<property_id>/<uuid>.jpg"
await supabase.storage.from("property-images").upload(path, file, { contentType: file.type });
await supabase.from("property_media").insert({ property_id: propertyId, storage_path: path, alt_text, width, height });
```

* Formats : JPEG, PNG, WebP, AVIF ; 10 Mo max ; un seul niveau de dossier (= id du bien).
* La 1re photo devient la couverture ; changer : `update({ is_cover: true })` sur une photo (l'ancienne est retirée automatiquement).
* Ordre : `supabase.rpc("reorder_property_media", { p_property_id, p_media_ids: [id1, id2, …] })`.
* Suppression : 1) `delete()` sur `property_media` ; 2) `storage.remove([path])`. La dernière photo d'un bien publié ne peut pas être supprimée (`LAST_MEDIA_OF_PUBLISHED_PROPERTY`).
* Affichage back-office : `createSignedUrls` (le personnel peut signer toutes les photos du catalogue).
* Documents internes : bucket `property-documents` (PDF, images, DOCX ; 20 Mo) + table `property_documents`. Accès limité à ceux qui peuvent modifier le bien.

### 3.5 Prospects, demandes, visites

| Table | Lecture | Écriture |
|---|---|---|
| `leads` | `leads.read_all`, ou prospect affecté, ou l'une de ses demandes/visites affectée | `update_all` ou prospect affecté ; réaffectation = `leads.assign` |
| `inquiries`, `viewing_requests` | `read_all`, ou affectée à moi, ou prospect affecté à moi | idem ; statut, planification |
| `lead_activities` | qui peut accéder au prospect | insertion de types manuels uniquement (`note, call, email, whatsapp, sms, meeting, visit`) ; jamais modifiable |

```ts
// Boîte de réception
supabase.from("inquiries")
  .select("*, lead:leads(id, full_name, phone, email, status), property:properties(id, reference, title)", { count: "exact" })
  .eq("status", "new").order("created_at", { ascending: false }).range(0, 24);

// Confirmer une visite
supabase.from("viewing_requests").update({ status: "confirmed", scheduled_at }).eq("id", id);

// Note interne
supabase.from("lead_activities").insert({ lead_id, activity_type: "call", content: "Rappel jeudi" });

// Affectation (responsable) : prospect + demandes ouvertes
supabase.rpc("assign_lead", { p_lead_id, p_agent_id, p_include_open_requests: true });
```

Automatismes : historique des statuts et affectations (`status_change`, `assignment`), `answered_at`, `closed_at`, `completed_at`, passage du prospect en `visit_scheduled` à la confirmation d'une visite, `last_activity_at`.
Statuts : prospect `new → contacted → qualified → visit_scheduled → negotiation → won | lost` ; demande `new → in_progress → answered → closed | spam` ; visite `requested → confirmed → completed | cancelled | no_show` (`confirmed` exige `scheduled_at`).

### 3.6 Utilisateurs (`admin-users`)

`POST /functions/v1/admin-users` avec `Authorization: Bearer <access_token>` (automatique via `supabase.functions.invoke`).

| `action` | Corps | Réponse |
|---|---|---|
| `invite` | `email, full_name, role, phone?, create_agent_profile?, redirect_to?` | 201 — e-mail d'invitation envoyé |
| `create` | `email, password, full_name, role, phone?, create_agent_profile?` | 201 — compte actif immédiatement |
| `deactivate` / `reactivate` | `user_id` | 200 — accès coupé immédiatement + connexion bloquée |
| `send_password_reset` | `user_id, redirect_to?` | 202 |

Erreurs : 401 `UNAUTHENTICATED`, 403 `FORBIDDEN` (permission ou rang), 409 `CONFLICT` (e-mail existant), 422 `VALIDATION_ERROR`.
Lecture : `supabase.rpc("list_users")` (`can_manage` indique les actions possibles).
Rôles : `supabase.rpc("assign_role" | "revoke_role", { p_user_id, p_role_code })`.
Profil personnel : `update` de `profiles` (`full_name`, `phone`, `avatar_path`, `locale`) ; fiche agent : `agents` (sa propre fiche, hors `is_active`, `is_public`, `slug`).

### 3.7 Statistiques

| RPC | Paramètres | Retour |
|---|---|---|
| `get_dashboard_stats` | `p_from`, `p_to` (ISO, défaut 30 j), `p_agent_id?` | `DashboardStats` |
| `get_inquiry_timeseries` | `p_from`, `p_to`, `p_interval` (`day|week|month`), `p_agent_id?` | lignes `{ bucket, inquiries, viewing_requests, new_leads }` |
| `get_agent_performance` | `p_from`, `p_to` | une ligne par agent |

Un agent obtient automatiquement son propre périmètre ; demander celui d'un autre renvoie `42501`. Définitions : [STATISTICS.md](STATISTICS.md).

### 3.8 Paramètres, référentiels, audit

* `agency_settings` (`settings.manage`) : une ligne, tout est **public**, ne jamais y mettre de secret.
* `app_settings` (`settings.manage`) : limites anti-abus, auto-affectation.
* `localities`, `property_types`, `amenities` (`catalog.manage`) : désactiver (`is_active = false`) plutôt que supprimer.
* `audit_logs` (`audit.read`) : lecture seule ; `old_data`/`new_data` ne contiennent que les colonnes modifiées.

---

## 4. Erreurs

Appels directs (tables/RPC) : `error.code` = SQLSTATE PostgreSQL (`DB_ERROR_CODES`).

| Code | Sens | Conduite UI |
|---|---|---|
| `42501` | Permission refusée (RLS, droit de colonne, garde-fou) | Message « action non autorisée » |
| `23514` | Règle métier/contrainte (`error.hint` précise parfois) | Afficher `error.message` (en français) |
| `23505` | Unicité (slug, e-mail) | Proposer une autre valeur |
| `23503` | Référence invalide | |
| `P0002` | Introuvable | |
| `22023` | Paramètre invalide | |
| `PGRST116` | `.single()` sans ligne (souvent : ligne filtrée par RLS) | 404 |

**Important :** un `update`/`delete` sur une ligne non autorisée ne lève pas d'erreur, il affecte 0 ligne (filtrage RLS). Utilisez `.select()` après l'écriture pour vérifier le résultat.

Edge Functions : `{ error: { code, message, fields? } }` (`ApiErrorCode`).

---

## 5. Compatibilité et évolution du schéma

* Versionnage sémantique du contrat (`CONTRACT_VERSION`, tags Git `vX.Y.Z`).
  * **Mineure** : ajout de colonne, vue, RPC, valeur facultative → rétrocompatible.
  * **Majeure** : suppression/renommage de colonne, changement de type ou de sémantique → annoncée, avec période de transition (ancienne colonne/vue conservée au moins une version).
* Ne pas utiliser `select("*")` sur les vues publiques en production : lister les colonnes (`PROPERTY_CARD_COLUMNS`).
* Les valeurs d'énumérations peuvent s'enrichir : prévoir un affichage par défaut.
* Chaque migration régénère `src/types/database.types.ts` (vérifié en CI).
* Changelog : section « Historique » du README.
