# Définition des statistiques

Toutes les valeurs sont calculées en temps réel sur les tables métier (aucun compteur dénormalisé).
Périodes semi-ouvertes `[p_from, p_to)`. Fuseau : Africa/Dakar (UTC+0, sans heure d'été).
Périmètre : `stats.read_all` → toute l'agence (ou `p_agent_id`) ; `stats.read_own` → l'appelant uniquement.
En périmètre agent : biens dont il est responsable (`properties.agent_id`), demandes et visites qui lui sont affectées, prospects affectés.

## `get_dashboard_stats`

| Clé | Définition |
|---|---|
| `properties.total` | Biens dont `publication_status ≠ archived` |
| `properties.archived` / `draft` / `pending_review` / `published` / `unpublished` | Biens par statut de publication |
| `properties.available` / `reserved` | Statut commercial, hors archives |
| `properties.sold` / `rented` | Statut commercial actuel `sold`/`rented`, **archives comprises** (stock cumulé) |
| `properties.sold_in_period` / `rented_in_period` | Statut actuel `sold`/`rented` **et** `status_changed_at` dans la période |
| `properties.published_in_period` | Première publication (`published_at`) dans la période |
| `properties.by_type` | Hors archives, par (type, transaction) : total et publiés |
| `properties.by_transaction` | Hors archives, par transaction |
| `inquiries.received_in_period` | Demandes créées dans la période. Les doublons ne créent pas de ligne, ils ne sont donc **pas** comptés |
| `inquiries.pending` | Demandes au statut `new` (toutes dates) |
| `inquiries.in_progress` | Demandes `in_progress` |
| `inquiries.answered_in_period` | `answered_at` dans la période |
| `inquiries.spam_in_period` | Créées dans la période et marquées `spam` |
| `inquiries.median_response_hours` | Médiane de `answered_at − created_at` (heures) des demandes créées dans la période et répondues |
| `viewings.requested_in_period` | Demandes de visite créées dans la période |
| `viewings.pending` | Visites `requested` |
| `viewings.upcoming` | Visites `confirmed` avec `scheduled_at ≥ maintenant` |
| `viewings.completed_in_period` | `completed_at` dans la période |
| `leads.new_in_period` | Prospects **distincts** créés dans la période (dédoublonnés par e-mail/téléphone) |
| `leads.open` | Prospects hors `won`/`lost` |
| `leads.unassigned` | Prospects ouverts sans agent |
| `leads.by_status` | Répartition par statut |

## `get_inquiry_timeseries`

Une ligne par intervalle (`day`, `week` = lundi, `month`), intervalles vides inclus (valeur 0). Période ≤ 3 ans.
`inquiries`, `viewing_requests`, `new_leads` : lignes créées dans l'intervalle.

## `get_agent_performance`

| Colonne | Définition |
|---|---|
| `properties_total` / `properties_published` | Biens dont l'agent est responsable (hors archives / publiés) |
| `sold_in_period` / `rented_in_period` | Comme ci-dessus, par agent |
| `leads_assigned_open` | Prospects ouverts affectés |
| `inquiries_received` | Demandes affectées créées dans la période |
| `inquiries_answered` | Demandes affectées avec `answered_at` dans la période |
| `viewings_requested` / `viewings_completed` | Visites affectées créées / réalisées dans la période |
| `activities_logged` | Activités **manuelles** saisies par l'agent dans la période |
| `leads_won` | Prospects distincts actuellement affectés, passés à `won` dans la période (d'après l'historique) |

Limite connue : une vente est attribuée à l'agent responsable **actuel** du bien.
