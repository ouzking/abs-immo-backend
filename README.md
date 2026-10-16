# abs-immo-backend

Backend Supabase de **ABS IMMO & SERVICES**, agence immobilière au Sénégal : base PostgreSQL, sécurité RLS,
Storage, Edge Functions, types TypeScript et contrats d'intégration pour :

* [`abs-immo-frontend`](../abs-immo-frontend) : site public (annonces, recherche, formulaires) ;
* [`abs-immo-backoffice`](../abs-immo-backoffice) : back-office (biens, photos, prospects, utilisateurs, statistiques).

Ce dépôt est **l'unique source du schéma**. Les applications React ne créent aucune table.

## Fonctionnalités

| Domaine | Contenu |
|---|---|
| Biens | Vente/location, maisons, appartements, villas, terrains, bureaux, locaux… ; prix exacts en FCFA ; référence lisible (`ABS-V-2600001`) et slug SEO ; statut commercial (disponible/réservé/vendu/loué) **séparé** de la publication (brouillon/en validation/publié/retiré/archivé) ; mise en avant ; confidentialité de l'adresse |
| Localisation | Régions, villes, communes, quartiers (Sénégal pré-rempli, extensible multi-pays) |
| Photos et documents | Plusieurs photos par bien, couverture unique, ordre ; documents internes privés |
| Recherche publique | Filtres (transaction, type, lieu, budget, chambres, surface, équipements), plein texte français insensible aux accents, tris, pagination avec total |
| Prospects | Demandes de renseignement et de visite, dédoublonnage, affectation automatique à l'agent du bien, historique et notes internes |
| Anti-abus | Champ piège, délai de saisie, CAPTCHA Turnstile optionnel, limitation de débit par IP hachée et par contact, CORS |
| Rôles | Super administrateur, administrateur, responsable commercial, agent ; 21 permissions ; règle de rang |
| Comptes | Inscription fermée, invitation/création contrôlée, désactivation immédiate, MFA TOTP |
| Statistiques | Biens, publications, ventes/locations, demandes, visites, prospects, performance par agent |
| Audit | Journal immuable des opérations sensibles |

## Démarrage rapide

```bash
npm ci
npm run db:start     # pile Supabase locale (Docker), ports 546xx
npm run db:reset     # migrations + données de démonstration
npm test             # 294 tests pgTAP + tests unitaires + tests d'intégration
```

Comptes de démonstration locaux : voir `supabase/seed.sql`.

## Scripts

| Commande | Rôle |
|---|---|
| `npm run db:start` / `db:stop` / `db:reset` | Pile locale |
| `npm run db:lint` | Linter du schéma |
| `npm run types:gen` | Régénère `src/types/database.types.ts` |
| `npm run types:check` | Vérification TypeScript |
| `npm run test:db` / `test:unit` / `test:integration` | Suites de tests |
| `npm run deploy:db` / `deploy:functions` | Déploiement (projet lié) |

## Structure

```
supabase/
  config.toml              configuration locale (Auth, Storage, fonctions)
  migrations/              9 migrations SQL versionnées (source de vérité)
  functions/
    _shared/               validation, HTTP/CORS/erreurs, sécurité, clients
    submit-inquiry/        formulaire de renseignement (public)
    submit-viewing-request/  formulaire de visite (public)
    admin-users/           gestion des comptes (back-office)
  tests/database/          tests pgTAP (contraintes, RLS, rôles, prospects, Storage, stats)
  seed.sql                 données de démonstration (local uniquement)
src/types/                 types générés + contrats d'intégration
tests/unit/                validation et utilitaires
tests/integration/         HTTP réel : API publique, formulaires, Auth, Storage, back-office
docs/                      documentation
```

## Documentation

* [Architecture](docs/ARCHITECTURE.md)
* [Contrat d'intégration](docs/INTEGRATION_CONTRACT.md) (React)
* [Sécurité](docs/SECURITY.md), avec la liste de vérification
* [Statistiques](docs/STATISTICS.md) : définitions
* [Premier administrateur](docs/FIRST_ADMIN.md)
* [Installation, déploiement, sauvegarde/restauration](docs/DEPLOYMENT.md)

## Projet Supabase

Projet `abs-immo-backend`, réf. `sasssoloprjakfysajvt`, PostgreSQL 17, eu-west-1.
Variables : voir [.env.example](.env.example). Aucune clé secrète ne doit être versionnée.

## Historique

| Version | Date | Changements |
|---|---|---|
| 1.0.0 | 2026-10-16 | Version initiale : schéma complet, RLS, Storage, Edge Functions, statistiques, contrat d'intégration |
