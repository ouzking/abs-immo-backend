## Objet

<!-- Quoi et pourquoi, en quelques lignes. -->

## Type

- [ ] Migration de base de données
- [ ] Edge Function
- [ ] Types / contrat d'intégration
- [ ] Tests, CI, documentation

## Vérifications

- [ ] `npm test` vert en local (pgTAP, unitaires, intégration)
- [ ] Nouvelle table : RLS activé, `GRANT` explicites, politiques testées
- [ ] Nouvelle fonction : `GRANT EXECUTE` explicite ; `SECURITY DEFINER` ⇒ `set search_path = ''`
- [ ] Aucune migration déjà déployée n'a été modifiée
- [ ] `npm run types:gen` exécuté si le schéma change
- [ ] Contrat modifié : `CONTRACT_VERSION`, docs/INTEGRATION_CONTRACT.md et historique du README mis à jour
- [ ] Aucun secret ajouté

## Impact sur les applications React

<!-- Aucun / rétrocompatible / changement majeur (préciser la migration côté frontend et back-office). -->
