# Sécurité — ABS IMMO & SERVICES

Public visé : développeurs backend/React et responsable technique.

## 1. Principes

1. **Moindre privilège par défaut.** Les privilèges implicites de PostgreSQL/Supabase sont retirés
   (migration 0100) : aucune table, séquence ou fonction n'est accessible à `anon`/`authenticated`
   sans `GRANT` explicite. EXECUTE est retiré à `PUBLIC` **globalement** : PostgreSQL ne permet pas de le retirer schéma par schéma.
2. **RLS sur 100 % des tables du schéma `public`.** Ce point est vérifié par un test pgTAP.
3. **Les autorisations vivent dans la base**, pas dans l'interface : politiques RLS, droits par
   colonne, et déclencheurs garde-fous pour ce que RLS ne sait pas exprimer (transitions de statut,
   colonnes protégées, réaffectations).
4. **Aucun secret côté client.** React n'utilise que la clé publique (*publishable*/`anon`).
5. **Défense en profondeur** pour les entrées publiques : validation dans l'Edge Function **et** en SQL.

## 2. Modèle d'accès

### Fonctions d'autorisation (schéma `private`, non exposé)

| Fonction | Rôle |
|---|---|
| `has_permission(code)` | L'utilisateur **actif** possède la permission (via ses rôles) |
| `is_active_staff()` | Au moins un rôle et compte actif |
| `can_manage_user(id)` | Règle de rang (super_admin, sinon rang strictement supérieur ; jamais soi-même) |
| `can_read_property(id)` / `can_edit_property(id)` | Accès à un bien |
| `can_access_lead(id)` / `can_access_request(...)` | Cloisonnement des prospects |
| `is_service_role()` | Appel de confiance (clé serveur ou connexion postgres). Utilisée par les RPC `SECURITY DEFINER` |
| `is_trusted_writer()` | Utilisée **seulement** dans les déclencheurs `SECURITY INVOKER` : reconnaît aussi les écritures émises par une fonction `SECURITY DEFINER` du backend |

Toutes sont `SECURITY DEFINER` avec `search_path = ''` (non détournables), sauf `is_service_role`/`is_trusted_writer`,
qui ne doivent **pas** l'être : dans une fonction `SECURITY DEFINER`, `current_user` vaut toujours le propriétaire.
`is_service_role` s'appuie donc sur le GUC `role` fixé par PostgREST.

### Comptes désactivés

`admin_set_user_active(false)` met `profiles.is_active = false`. Toutes les fonctions d'autorisation exigent un profil actif,
donc **un JWT encore valide (≤ 1 h) ne donne plus aucun accès**. L'Edge Function `admin-users` bannit en plus le compte
dans Supabase Auth, ce qui bloque connexion et rafraîchissement.

### Rôles privilégiés

* Aucun droit d'écriture sur `user_roles`, `roles`, `role_permissions` via l'API.
* Attribution uniquement par `assign_role`/`revoke_role` (règle de rang, pas sur soi-même, dernier super_admin protégé), journalisée.
* `profiles.is_active` n'est pas dans les colonnes modifiables (`GRANT UPDATE` par colonne) et un garde-fou bloque toute tentative.
* Premier super_admin : fonction `private.bootstrap_super_admin`, exécutable seulement depuis l'éditeur SQL et seulement s'il n'en existe aucun ([FIRST_ADMIN.md](FIRST_ADMIN.md)).

### Données publiques

Le site public ne lit que trois vues (`public_properties`, `public_property_media`, `public_agents`) et des RPC.
Ces vues s'exécutent avec les droits de leur propriétaire (*security definer views*) **volontairement** : elles filtrent
explicitement `publication_status = 'published'` et n'exposent que des colonnes publiques (`internal_notes`, `created_by`,
`agent_id`, adresse exacte et coordonnées précises sont exclues selon `address_visibility`). Elles sont déclarées
`security_barrier`. Le Security Advisor de Supabase signale ces trois vues : **avertissement attendu et documenté**.
Toute nouvelle vue publique doit suivre cette règle et être couverte par un test.

### Prospects

* `anon` n'a **aucun** droit sur `leads`, `inquiries`, `viewing_requests`, `lead_activities`.
* Les soumissions passent par les Edge Functions, qui appellent `submit_inquiry`/`submit_viewing_request` (EXECUTE réservé à `service_role`).
* Un agent ne voit que les prospects et demandes qui lui sont affectés ; changer un identifiant dans l'URL ne donne rien (filtrage RLS).
* Historique non modifiable ; les types d'activité « système » ne peuvent pas être forgés.

## 3. Formulaires publics : anti-abus

| Mesure | Où |
|---|---|
| Champ piège `website` + délai de saisie minimal (2,5 s) : succès factice, rien n'est stocké | Edge Function |
| CAPTCHA Cloudflare Turnstile (activé si `TURNSTILE_SECRET_KEY` est défini) | Edge Function |
| Taille de corps ≤ 16 Ko, JSON strict, liste blanche des champs | Edge Function |
| Origines autorisées (`ALLOWED_ORIGINS`) | Edge Function |
| Limitation : 5 / 10 min et 30 / jour par empreinte IP, 10 / jour par e-mail/téléphone, par formulaire (réglable dans `app_settings`) | SQL |
| Dédoublonnage des prospects (e-mail/téléphone) et des demandes (< 24 h) / visites ouvertes | SQL |
| Annonce obligatoirement publiée (et disponible ou réservée pour une visite) | SQL |

**Confidentialité :** l'adresse IP n'est jamais stockée, seulement `SHA-256(RATE_LIMIT_SALT | ip)`.
L'IP est lue dans `cf-connecting-ip` (fixée par Cloudflare), sinon dans le premier `x-forwarded-for` (falsifiable,
d'où la limite complémentaire par contact).

## 4. Storage

| Bucket | Public | Lecture | Écriture |
|---|:-:|---|---|
| `property-images` | non | `anon` : uniquement les fichiers référencés par une photo d'annonce **publiée** ; personnel : catalogue | qui peut modifier le bien ; dossier = id du bien ; extensions et types MIME contrôlés |
| `property-documents` | non | qui peut modifier le bien | idem |
| `agent-photos` | oui | publique | soi-même (`<user_id>/…`) ou `agents.manage` |
| `site-assets` | oui | publique | `settings.manage` |

SVG interdit partout (risque XSS). Tailles max : 10 / 20 / 3 / 5 Mo.
Limite connue : une URL signée reste valable jusqu'à son expiration même si l'annonce est retirée ; on utilise donc des durées courtes (≤ 24 h) pour l'affichage.

## 5. Secrets

| Secret | Emplacement | Jamais dans |
|---|---|---|
| `service_role` / `sb_secret_…` | injecté automatiquement dans les Edge Functions | React, dépôt, logs |
| `RATE_LIMIT_SALT`, `TURNSTILE_SECRET_KEY` | `supabase secrets set` | dépôt |
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` | secrets GitHub Actions / poste du déployeur | dépôt |

`.gitignore` exclut `.env*` (sauf `.env.example`). En cas de fuite : régénérer la clé (Dashboard > API Keys), redéployer, auditer `audit_logs`.

## 6. Audit

`audit_logs` (immuable via l'API, lecture `audit.read`) trace : rôles attribués/retirés, activation des comptes,
profils (nom, téléphone, e-mail), fiches agents, statuts/prix/agent/vedette des biens, photos et documents ajoutés/supprimés,
prospects (statut, affectation, coordonnées), paramètres, référentiels. Seules les colonnes modifiées sont enregistrées.
Purge éventuelle : par migration ou par l'éditeur SQL (rôle postgres), selon la politique de conservation de l'agence.

## 7. Protection des données personnelles (loi sénégalaise n° 2008-12, CDP)

* Données de prospects minimisées ; consentement marketing horodaté (`consent_at`).
* Droit à l'effacement : suppression du prospect (`leads.delete`), en cascade sur ses demandes, visites et historique.
* Pas d'IP en clair ; accès cloisonné par agent ; journal d'audit.
* À la charge de l'agence : déclaration auprès de la CDP, mentions légales et politique de confidentialité sur le site.

## 8. Liste de vérification de sécurité

Avant chaque mise en production :

- [ ] `npm test` vert (pgTAP + unitaires + intégration) et `npm run db:lint` sans alerte.
- [ ] Aucune nouvelle table sans `enable row level security` (test automatique).
- [ ] Toute nouvelle fonction a ses `GRANT EXECUTE` explicites ; `SECURITY DEFINER` ⇒ `set search_path = ''`.
- [ ] Aucune clé secrète dans le dépôt : `git grep -nE "sb_secret_|service_role\"?\s*[:=]\s*\"ey"` ne renvoie rien.
- [ ] Dashboard > Authentication > Sign In / Providers : **« Allow new users to sign up » désactivé**, e-mail activé.
- [ ] Politique de mot de passe : longueur ≥ 10, minuscules/majuscules/chiffres ; protection contre les mots de passe divulgués (plan Pro).
- [ ] Confirmation d'e-mail activée ; SMTP personnalisé configuré (le SMTP par défaut est limité).
- [ ] URL du site et URL de redirection limitées aux domaines de l'agence.
- [ ] MFA TOTP activé et **utilisé** par les comptes super_admin/admin.
- [ ] Secrets `RATE_LIMIT_SALT`, `ALLOWED_ORIGINS`, `BACKOFFICE_ORIGINS` (et `TURNSTILE_SECRET_KEY`) définis.
- [ ] Security Advisor : seuls les avertissements attendus (3 vues publiques).
- [ ] Sauvegardes vérifiées ([DEPLOYMENT.md](DEPLOYMENT.md#5-sauvegarde-et-restauration)).
- [ ] Revue trimestrielle des comptes actifs (`list_users`) et du journal d'audit.
