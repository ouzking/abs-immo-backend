# Création du premier super administrateur

À faire **une seule fois**, après le déploiement des migrations. Aucun secret ne transite par le chat ni par le dépôt.

1. **Créer le compte** : Dashboard Supabase → *Authentication* → *Users* → **Add user** → *Create new user*.
   * E-mail professionnel de la personne responsable.
   * Mot de passe fort (≥ 10 caractères, minuscule, majuscule, chiffre), généré dans un gestionnaire de mots de passe.
   * Cocher **Auto Confirm User**.
2. **Attribuer le rôle** : Dashboard → *SQL Editor* → exécuter :

   ```sql
   select private.bootstrap_super_admin('prenom.nom@abs-immo.sn', 'Prénom Nom');
   ```

   La fonction n'est exécutable que depuis l'éditeur SQL (rôle `postgres`), et **refuse** de s'exécuter si un super administrateur existe déjà.
   L'opération est inscrite dans `audit_logs`.
3. **Vérifier** :

   ```sql
   select p.email, ur.role_code from public.user_roles ur join public.profiles p on p.id = ur.user_id;
   ```

4. **Sécuriser** : se connecter au back-office, changer le mot de passe et **activer le MFA TOTP**.
5. **Créer les autres comptes** depuis le back-office (Edge Function `admin-users`, action `invite`), jamais par SQL.

Il est conseillé d'avoir **deux** super administrateurs (le dernier super administrateur actif ne peut être ni rétrogradé ni désactivé). Le second est promu depuis le back-office par le premier (`assign_role`).
