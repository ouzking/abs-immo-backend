# Installation, déploiement, sauvegarde

Public visé : développeur ou responsable technique chargé du backend.

## 1. Prérequis

* Node.js ≥ 20 (le CLI Supabase est une dépendance du projet : `npx supabase …`, version 2.121.0).
* Docker Desktop (pile locale et tests).
* Accès au projet Supabase `abs-immo-backend` (réf. `sasssoloprjakfysajvt`, région eu-west-1).

## 2. Environnement local

```bash
npm ci
npm run db:start      # démarre Supabase local (ports 546xx, voir supabase/config.toml)
npm run db:reset      # applique les migrations + seed de démonstration
npm test              # pgTAP + unitaires + intégration
```

* API locale : `http://127.0.0.1:54621` ; URL/clés locales : `npx supabase status`.
* E-mails (invitations, réinitialisations) : Mailpit sur `http://127.0.0.1:54624`.
* Comptes de démonstration : voir l'en-tête de `supabase/seed.sql` (local uniquement).
* Les ports 546xx évitent les conflits avec d'autres projets Supabase locaux (et les plages réservées par Hyper-V sous Windows).

### Ajouter une migration

```bash
npx supabase migration new nom_explicite   # écrire le SQL dans le fichier créé
npm run db:reset && npm test
npm run types:gen                           # met à jour src/types/database.types.ts
```

Règles : RLS + GRANT explicites sur toute nouvelle table ; `SECURITY DEFINER` ⇒ `set search_path = ''` ;
ne jamais modifier une migration déjà déployée (en écrire une nouvelle).

## 3. Déploiement

L'environnement local (Docker) sert d'environnement de test. Pour une recette distincte avant la production,
créer un second projet Supabase (« staging ») ou utiliser Supabase Branching, et y exécuter les mêmes commandes.

### 3.1 Base de données

```bash
npx supabase login                                   # une fois (ou SUPABASE_ACCESS_TOKEN)
npx supabase link --project-ref sasssoloprjakfysajvt
npx supabase db push --linked --dry-run              # affiche les migrations à appliquer
npx supabase db push --linked                        # applique (ne pousse PAS seed.sql)
npx supabase migration list --linked                 # vérifie local = distant
```

`db push` n'applique que les migrations manquantes ; il ne réinitialise jamais la base.
**Ne jamais exécuter `supabase db reset --linked`** (destructif) ni `supabase test db --linked` (les tests créent et suppriment des données).

### 3.2 Secrets et Edge Functions

```bash
npx supabase secrets set RATE_LIMIT_SALT="$(openssl rand -hex 32)"
npx supabase secrets set ALLOWED_ORIGINS="https://abs-immo.sn,https://www.abs-immo.sn"
npx supabase secrets set BACKOFFICE_ORIGINS="https://admin.abs-immo.sn"
# optionnel : npx supabase secrets set TURNSTILE_SECRET_KEY=...
npm run deploy:functions
npx supabase functions list
```

### 3.3 Réglages du Dashboard (non couverts par les migrations)

Ne **pas** utiliser `supabase config push` : `config.toml` contient des URL locales.

| Écran | Réglage |
|---|---|
| Authentication → Sign In / Providers | Email **activé** ; **Allow new users to sign up : désactivé** ; Confirm email : activé |
| Authentication → Sign In / Providers → Email | Longueur min. 10, exigences « minuscules, majuscules, chiffres » ; Secure password change |
| Authentication → URL Configuration | Site URL = URL du back-office ; Redirect URLs = `https://admin.abs-immo.sn/**`, URL du site public si nécessaire |
| Authentication → Multi-Factor | TOTP activé |
| Authentication → Emails → SMTP | SMTP de l'agence (le SMTP par défaut est limité à quelques e-mails/heure) |
| Authentication → Email Templates | Modèles en français (invitation, réinitialisation) |
| Project Settings → API | Schémas exposés : `public`, `graphql_public` (jamais `private`) |
| Advisors → Security | Seuls les avertissements « security definer view » attendus (voir SECURITY.md) |

### 3.4 Premier administrateur

Voir [FIRST_ADMIN.md](FIRST_ADMIN.md).

### 3.5 CI/CD

`.github/workflows/ci.yml` exécute à chaque PR : démarrage Supabase éphémère, lint, types à jour, `tsc`, `deno check`, pgTAP, unitaires, intégration.
Déploiement automatique conseillé (job séparé sur `main`, protégé par un environnement GitHub avec approbation) :
secrets `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, puis `supabase link`, `supabase db push`, `supabase functions deploy`.

## 4. Mise à jour d'une version déployée

1. PR → CI verte → revue.
2. `db push --dry-run` sur staging puis production ; contrôler la liste.
3. Sauvegarde manuelle (§5) avant toute migration qui transforme des données.
4. `db push`, puis `deploy:functions` si les fonctions ont changé.
5. Tag `vX.Y.Z`, mise à jour de `CONTRACT_VERSION` si le contrat change, information des équipes React.

## 5. Sauvegarde et restauration

### Sauvegardes gérées par Supabase

* Plan Pro : sauvegardes quotidiennes conservées 7 jours (Dashboard → Database → Backups).
* **Point-in-Time Recovery** (option payante) recommandé dès la mise en production commerciale : restauration à la seconde près.
* Plan gratuit : pas de sauvegarde téléchargeable ⇒ les sauvegardes logiques ci-dessous sont **obligatoires**.

### Sauvegarde logique (à planifier, ex. chaque nuit)

```bash
mkdir -p backups/$(date +%F)
npx supabase db dump --linked -f backups/$(date +%F)/roles.sql --role-only
npx supabase db dump --linked -f backups/$(date +%F)/schema.sql
npx supabase db dump --linked -f backups/$(date +%F)/data.sql --use-copy --data-only
```

* `data.sql` inclut `auth.users` et les données personnelles des prospects : chiffrer (ex. `age`/`gpg`) et stocker hors du dépôt (`backups/` est ignoré par Git), avec accès restreint.
* Fichiers Storage : non inclus dans le dump. Les copier via l'API S3 de Supabase (Project Settings → Storage → S3 access keys), par exemple `aws s3 sync s3://property-images ./backups/storage/property-images --endpoint-url https://sasssoloprjakfysajvt.supabase.co/storage/v1/s3`.
* Conserver au moins 30 sauvegardes quotidiennes et 12 mensuelles.

### Restauration

1. Restaurer **dans un projet neuf ou de staging**, jamais directement par-dessus la production.
2. ```bash
   psql "$TARGET_DB_URL" --single-transaction -v ON_ERROR_STOP=1 \
     -f roles.sql -f schema.sql -c "SET session_replication_role = replica" -f data.sql
   ```
   (`TARGET_DB_URL` : Dashboard → Connect → chaîne de connexion directe ; ne pas la versionner.)
3. Recopier les fichiers Storage, redéfinir les secrets, redéployer les Edge Functions.
4. Vérifier : `npx supabase migration list`, nombre de biens/prospects, connexion d'un administrateur.
5. Basculer les applications (URL et clé publique) si un nouveau projet est utilisé.

Tester une restauration complète **au moins une fois par trimestre**.
