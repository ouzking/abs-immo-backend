-- =============================================================================
-- Utilitaires de test pgTAP (base LOCALE uniquement — jamais déployés).
-- Ce fichier s'exécute en premier (ordre alphabétique) et installe le schéma
-- `tests`. Les autres fichiers s'exécutent dans une transaction annulée.
-- =============================================================================
create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Crée un utilisateur Auth (le déclencheur crée le profil), ses rôles et,
-- si demandé, sa fiche agent. Renvoie son id.
create or replace function tests.create_user(
  p_email text,
  p_roles text[] default '{}',
  p_with_agent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
  v_role text;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email, '',
          now(), '{"provider":"email","providers":["email"]}',
          jsonb_build_object('full_name', split_part(p_email, '@', 1)), now(), now());
  foreach v_role in array p_roles loop
    insert into public.user_roles (user_id, role_code) values (v_id, v_role);
  end loop;
  if p_with_agent then
    insert into public.agents (profile_id, slug, display_name)
    values (v_id, private.slugify(split_part(p_email, '@', 1)) || '-' || left(v_id::text, 6), split_part(p_email, '@', 1));
  end if;
  return v_id;
end;
$$;

-- Simule une requête PostgREST authentifiée.
-- À appeler après `reset role;`.
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims',
                     jsonb_build_object('sub', p_user_id, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
end;
$$;

create or replace function tests.authenticate_as_service_role()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('role', 'service_role', true);
end;
$$;

-- Crée un bien (en tant que postgres) ; publié si demandé (avec photo de couverture).
create or replace function tests.create_property(
  p_agent_id uuid,
  p_publish boolean default false,
  p_title text default 'Villa de test aux Almadies',
  p_transaction public.transaction_type default 'sale',
  p_type text default 'villa',
  p_price bigint default 150000000
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_locality uuid;
begin
  select id into v_locality from public.localities where slug = 'almadies' limit 1;
  insert into public.properties (title, short_description, description, property_type, transaction_type,
                                 price_amount, rent_period, surface_area, bedrooms, bathrooms, locality_id,
                                 latitude, longitude, address_line, internal_notes, agent_id)
  values (p_title, 'Description courte suffisamment longue pour publier.', 'Description détaillée.',
          p_type, p_transaction, p_price, case when p_transaction = 'rent' then 'month'::public.rent_period end,
          350, 4, 3, v_locality, 14.745678, -17.512345, '12 rue secrète', 'NOTE INTERNE CONFIDENTIELLE', p_agent_id)
  returning id into v_id;
  if p_publish then
    insert into public.property_media (property_id, storage_path, alt_text)
    values (v_id, v_id || '/cover.jpg', 'Façade');
    update public.properties set publication_status = 'published' where id = v_id;
  end if;
  return v_id;
end;
$$;

-- Vide les données métier DANS la transaction du test (annulé par le ROLLBACK
-- final) : chaque fichier s'exécute sur une base vierge, quelles que soient les
-- données de démonstration ou d'intégration présentes localement.
create or replace function tests.reset_business_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.leads;
  delete from public.properties;
  delete from private.rate_limit_events;
  delete from public.audit_logs;
  delete from auth.users;   -- cascade : profils, rôles, fiches agents
end;
$$;

-- Seules les fonctions de simulation d'authentification sont appelables après
-- un changement de rôle ; les utilitaires de données restent réservés à postgres.
revoke execute on all functions in schema tests from public, anon, authenticated, service_role;
grant execute on function tests.authenticate_as(uuid), tests.authenticate_as_anon(), tests.authenticate_as_service_role()
  to anon, authenticated, service_role;

begin;
select plan(1);
select has_schema('tests', 'Le schéma de test est installé');
select * from finish();
rollback;
