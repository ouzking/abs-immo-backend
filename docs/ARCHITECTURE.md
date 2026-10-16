# Architecture

## Vue d'ensemble

```
 abs-immo-frontend (React, anon)        abs-immo-backoffice (React, authenticated)
        │  vues publiques + RPC                │  tables (RLS) + RPC + Storage
        │  Edge Functions (formulaires)        │  Edge Function admin-users
        ▼                                      ▼
 ┌──────────────────────── Supabase ───────────────────────────────┐
 │ PostgREST ── PostgreSQL 17                                      │
 │   public  : tables métier (RLS), vues publiques, RPC            │
 │   private : autorisations, utilitaires, limitation de débit     │
 │ Auth (e-mail/mot de passe, MFA TOTP, inscription fermée)        │
 │ Storage (4 buckets, politiques par rôle)                        │
 │ Edge Functions (Deno) : submit-inquiry, submit-viewing-request, │
 │                         admin-users                             │
 └─────────────────────────────────────────────────────────────────┘
```

Aucun serveur Node/Laravel : les besoins serveur (secrets, anti-abus, Auth Admin) sont couverts par 3 Edge Functions ;
tout le reste passe par l'API native avec RLS.

## Migrations

| Fichier | Contenu |
|---|---|
| `0100_foundation` | Extensions, schéma `private`, privilèges par défaut verrouillés, recherche FR sans accents, slug, téléphone E.164, audit |
| `0200_identity_roles` | Rôles/permissions, profils, `user_roles`, agents, fonctions d'autorisation, RPC de gestion des comptes, amorçage |
| `0300_catalog_locations` | Pays, localités hiérarchiques (14 régions du Sénégal, villes, communes de Dakar, quartiers), types de biens, équipements |
| `0400_properties` | Biens, photos, équipements, caractéristiques, documents, workflow et garde-fous |
| `0500_leads` | Prospects, demandes, visites, historique, cloisonnement, soumissions publiques, limitation de débit |
| `0600_settings` | Paramètres publics de l'agence, paramètres opérationnels, lecture de l'audit |
| `0700_public_api` | Vues publiques, recherche, détail, annonces similaires, filtres |
| `0800_statistics` | Tableau de bord, séries temporelles, performance par agent |
| `0900_storage` | Buckets et politiques Storage |

## Modèle de données (principales relations)

```
auth.users 1─1 profiles 1─* user_roles *─1 roles *─* permissions (role_permissions)
profiles 1─0..1 agents
agents 1─* properties ─* property_media / property_amenities / property_features / property_documents
properties *─1 property_types ; properties *─1 localities (+ region/city/commune/neighborhood dérivés)
leads 1─* inquiries / viewing_requests / lead_activities ; inquiries, viewing_requests *─0..1 properties
agents 1─* leads / inquiries / viewing_requests (affectation)
```

Suppressions : bien → photos/équipements/caractéristiques/documents en cascade, demandes et visites conservées
(`property_id = NULL`) ; prospect → demandes, visites, historique en cascade ; utilisateur Auth → profil, rôles, fiche agent
en cascade, biens et prospects conservés (`agent_id = NULL`). En pratique, on archive les biens et on désactive les comptes.

## Choix notables

* **Statut commercial ≠ publication** : deux colonnes, deux énumérations, contraintes croisées (`sold` ⇒ vente, `rented` ⇒ location).
* **Prix** : `bigint` en FCFA (exact, pas de flottant), `currency_code` pour d'autres marchés.
* **Localisation** : localité la plus précise + chaîne dérivée par déclencheur, ce qui donne des filtres indexés par région/ville/commune/quartier et une hiérarchie extensible à d'autres pays.
* **Recherche** : `tsvector` pondéré (titre > lieux/type > résumé > description), configuration `french_unaccent`.
* **Photos privées** : bucket privé et URL signées, pour que les photos des brouillons ne soient jamais publiques.
* **Formulaires** : Edge Function (anti-robot, CAPTCHA, CORS) + RPC SQL (validation, limites, dédoublonnage), sans aucun droit direct pour `anon`.
* **Audit** générique par déclencheur, limité aux colonnes modifiées.
