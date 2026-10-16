-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0100 : fondations
-- -----------------------------------------------------------------------------
-- * Schéma `private` (non exposé par l'API Data) pour les fonctions internes.
-- * Extensions, configuration de recherche plein texte française sans accents.
-- * Utilitaires : updated_at, slug, normalisation des téléphones.
-- * Journal d'audit et déclencheur générique.
-- * Verrouillage des privilèges par défaut : rien n'est accessible aux rôles
--   `anon` / `authenticated` sans GRANT explicite dans les migrations.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Extensions (Supabase les installe dans le schéma `extensions`)
-- -----------------------------------------------------------------------------
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Schéma privé : jamais ajouté à `api.schemas` dans config.toml.
-- USAGE est accordé pour que les politiques RLS puissent appeler les fonctions
-- d'autorisation ; chaque fonction a ensuite ses propres droits EXECUTE.
-- -----------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Privilèges par défaut : on retire les droits implicites accordés par
-- Supabase sur les nouveaux objets du schéma public. Chaque table, vue et
-- fonction reçoit ensuite des GRANT explicites (principe du moindre privilège).
-- -----------------------------------------------------------------------------
-- IMPORTANT : PostgreSQL accorde EXECUTE à PUBLIC sur toute nouvelle fonction,
-- et ce droit GLOBAL ne peut pas être retiré schéma par schéma. On le retire
-- donc globalement pour le rôle propriétaire des migrations (postgres).
alter default privileges revoke execute on functions from public;
-- service_role (clé serveur) doit pouvoir exécuter les utilitaires privés
-- appelés par les déclencheurs lors de ses propres écritures.
alter default privileges in schema private grant execute on functions to service_role;

alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Recherche plein texte : configuration française insensible aux accents.
-- Utilisable côté PostgREST : `.textSearch('search_vector', q, { config: 'french_unaccent' })`
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_ts_config where cfgname = 'french_unaccent') then
    create text search configuration public.french_unaccent (copy = pg_catalog.french);
    alter text search configuration public.french_unaccent
      alter mapping for hword, hword_part, word with extensions.unaccent, pg_catalog.french_stem;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Utilitaires
-- -----------------------------------------------------------------------------

-- Met à jour la colonne updated_at.
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Transforme un texte en slug SEO : "Villa à Saly — 4 ch." -> "villa-a-saly-4-ch"
create or replace function private.slugify(p_text text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select trim(both '-' from
           regexp_replace(
             lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p_text, ''))),
             '[^a-z0-9]+', '-', 'g'));
$$;

-- Normalise un numéro de téléphone au format E.164.
-- Règles : espaces/points/tirets/parenthèses supprimés ; préfixe "00" -> "+" ;
-- numéro sénégalais à 9 chiffres (7x… mobile, 3x… fixe) -> +221.
-- Renvoie NULL si le numéro est invalide.
create or replace function private.normalize_phone(p_phone text, p_default_prefix text default '+221')
returns text
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  v text;
begin
  if p_phone is null or btrim(p_phone) = '' then
    return null;
  end if;
  v := regexp_replace(p_phone, '[\s\.\-\(\)/]', '', 'g');
  if v like '00%' then
    v := '+' || substr(v, 3);
  end if;
  if v ~ '^[37][0-9]{8}$' and p_default_prefix = '+221' then
    v := '+221' || v;
  end if;
  if v ~ '^\+[1-9][0-9]{7,14}$' then
    return v;
  end if;
  return null;
end;
$$;

-- Conversion sûre texte -> uuid (NULL si invalide). Utilisée par les politiques Storage.
create or replace function private.try_uuid(p_text text)
returns uuid
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
begin
  return p_text::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- Journal d'audit
-- -----------------------------------------------------------------------------
create table public.audit_logs (
  id          bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id    uuid,                         -- auth.uid() ; NULL = système / service_role
  actor_role  text,                         -- rôle Postgres/JWT au moment de l'action
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE', 'RPC')),
  table_name  text not null,
  record_id   text,
  old_data    jsonb,                        -- UPDATE : uniquement les colonnes modifiées
  new_data    jsonb,
  context     jsonb not null default '{}'::jsonb
);

comment on table public.audit_logs is
  'Journal d''audit immuable des opérations sensibles. Écrit uniquement par déclencheurs/fonctions SECURITY DEFINER.';

create index audit_logs_occurred_at_idx on public.audit_logs (occurred_at desc);
create index audit_logs_table_record_idx on public.audit_logs (table_name, record_id);
create index audit_logs_actor_idx on public.audit_logs (actor_id) where actor_id is not null;

alter table public.audit_logs enable row level security;

-- Écriture d'une entrée d'audit "métier" (RPC, opérations hors déclencheur).
create or replace function private.write_audit(
  p_action text,
  p_table text,
  p_record_id text,
  p_old jsonb default null,
  p_new jsonb default null,
  p_context jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_logs (actor_id, actor_role, action, table_name, record_id, old_data, new_data, context)
  values (
    auth.uid(),
    coalesce(auth.jwt() ->> 'role', current_user),
    p_action, p_table, p_record_id, p_old, p_new, coalesce(p_context, '{}'::jsonb)
  );
end;
$$;

-- Déclencheur d'audit générique.
-- TG_ARGV[0] (optionnel) : liste de colonnes séparées par des virgules à
-- surveiller ; si aucune n'a changé lors d'un UPDATE, rien n'est journalisé.
-- Les colonnes `updated_at` et `search_vector` sont toujours ignorées.
create or replace function private.audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_old_diff jsonb := '{}'::jsonb;
  v_new_diff jsonb := '{}'::jsonb;
  v_watch text[];
  v_key text;
  v_id text;
begin
  if tg_op in ('UPDATE', 'DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('UPDATE', 'INSERT') then v_new := to_jsonb(new); end if;

  v_id := coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'user_id', v_old ->> 'user_id',
                   v_new ->> 'profile_id', v_old ->> 'profile_id', v_new ->> 'key', v_old ->> 'key');

  if tg_op = 'UPDATE' then
    if tg_nargs > 0 then
      v_watch := string_to_array(replace(tg_argv[0], ' ', ''), ',');
    end if;
    for v_key in select jsonb_object_keys(v_new) loop
      continue when v_key in ('updated_at', 'search_vector');
      if (v_new -> v_key) is distinct from (v_old -> v_key) then
        v_old_diff := v_old_diff || jsonb_build_object(v_key, v_old -> v_key);
        v_new_diff := v_new_diff || jsonb_build_object(v_key, v_new -> v_key);
      end if;
    end loop;
    if v_new_diff = '{}'::jsonb then
      return new;
    end if;
    if v_watch is not null and not exists (
      select 1 from jsonb_object_keys(v_new_diff) k where k = any (v_watch)
    ) then
      return new;
    end if;
    v_old := v_old_diff;
    v_new := v_new_diff;
  end if;

  -- Ne jamais journaliser le vecteur de recherche (volumineux, dérivé).
  v_old := v_old - 'search_vector';
  v_new := v_new - 'search_vector';

  insert into public.audit_logs (actor_id, actor_role, action, table_name, record_id, old_data, new_data)
  values (auth.uid(), coalesce(auth.jwt() ->> 'role', current_user), tg_op, tg_table_name, v_id, v_old, v_new);

  return coalesce(new, old);
end;
$$;

-- Les fonctions privées ne sont exécutables par personne par défaut ; les
-- migrations suivantes accordent EXECUTE au cas par cas.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on all functions in schema private to service_role;
grant execute on function private.try_uuid(text) to anon, authenticated;
