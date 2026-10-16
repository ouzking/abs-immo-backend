-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0600 : paramètres de l'agence
-- -----------------------------------------------------------------------------
-- agency_settings : ligne unique, entièrement PUBLIQUE (site vitrine).
-- app_settings    : paramètres opérationnels internes (clé/valeur JSON).
-- AUCUN SECRET ne doit être stocké ici : les secrets vont dans les secrets
-- des Edge Functions (`supabase secrets set`).
-- =============================================================================

create table public.agency_settings (
  id                  boolean primary key default true check (id),   -- ligne unique
  agency_name         text not null default 'ABS IMMO & SERVICES' check (char_length(agency_name) between 2 and 120),
  legal_name          text check (char_length(legal_name) <= 200),
  tagline             text check (char_length(tagline) <= 200),
  description         text check (char_length(description) <= 4000),
  phone               text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  secondary_phone     text check (secondary_phone is null or secondary_phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp_phone      text check (whatsapp_phone is null or whatsapp_phone ~ '^\+[1-9][0-9]{7,14}$'),
  email               text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  address_line        text check (char_length(address_line) <= 300),
  locality_id         uuid references public.localities (id) on delete set null,
  latitude            numeric(9, 6) check (latitude between -90 and 90),
  longitude           numeric(9, 6) check (longitude between -180 and 180),
  opening_hours       jsonb not null default '[]'::jsonb check (jsonb_typeof(opening_hours) = 'array'),
  social_links        jsonb not null default '{}'::jsonb check (jsonb_typeof(social_links) = 'object'),
  logo_path           text check (char_length(logo_path) <= 300),
  default_currency    char(3) not null default 'XOF',
  default_country     char(2) not null default 'SN' references public.countries (code),
  ninea               text check (char_length(ninea) <= 30),       -- identifiant fiscal (public sur factures)
  rccm                text check (char_length(rccm) <= 60),        -- registre du commerce
  seo_default_title   text check (char_length(seo_default_title) <= 120),
  seo_default_description text check (char_length(seo_default_description) <= 320),
  updated_at          timestamptz not null default now(),
  updated_by          uuid references public.profiles (id) on delete set null
);
comment on table public.agency_settings is 'Informations publiques de l''agence (ligne unique). Aucune donnée secrète.';
comment on column public.agency_settings.opening_hours is 'Ex. [{"days":"Lun-Ven","open":"09:00","close":"18:00"}]';
comment on column public.agency_settings.social_links is 'Ex. {"facebook":"https://…","instagram":"https://…","linkedin":"…","tiktok":"…","youtube":"…"}';

insert into public.agency_settings (id, agency_name, tagline, default_currency, default_country,
                                    opening_hours, social_links)
values (true, 'ABS IMMO & SERVICES', 'Votre partenaire immobilier au Sénégal', 'XOF', 'SN',
        '[{"days":"Lundi - Vendredi","open":"09:00","close":"18:00"},{"days":"Samedi","open":"09:00","close":"13:00"}]',
        '{}');

create or replace function private.agency_settings_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := true;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger agency_settings_stamp
  before update on public.agency_settings
  for each row execute function private.agency_settings_stamp();

create trigger agency_settings_audit
  after update on public.agency_settings
  for each row execute function private.audit_trigger();

alter table public.agency_settings enable row level security;

create policy agency_settings_select on public.agency_settings
  for select to anon, authenticated using (true);
create policy agency_settings_update on public.agency_settings
  for update to authenticated
  using ((select private.has_permission('settings.manage')))
  with check ((select private.has_permission('settings.manage')));

grant select on public.agency_settings to anon, authenticated;
grant update (agency_name, legal_name, tagline, description, phone, secondary_phone, whatsapp_phone, email,
              address_line, locality_id, latitude, longitude, opening_hours, social_links, logo_path,
              default_currency, default_country, ninea, rccm, seo_default_title, seo_default_description)
  on public.agency_settings to authenticated;

-- -----------------------------------------------------------------------------
-- Paramètres opérationnels internes
-- -----------------------------------------------------------------------------
create table public.app_settings (
  key         text primary key check (key ~ '^[a-z0-9_]+(\.[a-z0-9_]+)*$'),
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id) on delete set null
);
comment on table public.app_settings is 'Paramètres opérationnels (non secrets). Lecture/écriture : settings.manage.';

insert into public.app_settings (key, value, description) values
  ('rate_limit.per_ip_10min',     '5',   'Soumissions publiques max. par empreinte IP sur 10 minutes (par formulaire).'),
  ('rate_limit.per_ip_day',       '30',  'Soumissions publiques max. par empreinte IP sur 24 heures (par formulaire).'),
  ('rate_limit.per_contact_day',  '10',  'Soumissions publiques max. par e-mail/téléphone sur 24 heures (par formulaire).'),
  ('leads.auto_assign_to_property_agent', 'true', 'Affecter automatiquement les demandes à l''agent responsable du bien.');

create or replace function private.app_settings_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger app_settings_stamp
  before insert or update on public.app_settings
  for each row execute function private.app_settings_stamp();

create trigger app_settings_audit
  after insert or update or delete on public.app_settings
  for each row execute function private.audit_trigger();

alter table public.app_settings enable row level security;

create policy app_settings_select on public.app_settings
  for select to authenticated using ((select private.has_permission('settings.manage')));
create policy app_settings_write on public.app_settings
  for all to authenticated
  using ((select private.has_permission('settings.manage')))
  with check ((select private.has_permission('settings.manage')));

grant select, insert, delete on public.app_settings to authenticated;
grant update (value, description) on public.app_settings to authenticated;

-- Lecture typée d'un paramètre avec valeur par défaut (usage interne).
create or replace function private.setting_int(p_key text, p_default integer)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select (value #>> '{}')::integer from public.app_settings where key = p_key), p_default);
$$;

create or replace function private.setting_bool(p_key text, p_default boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select (value #>> '{}')::boolean from public.app_settings where key = p_key), p_default);
$$;

-- -----------------------------------------------------------------------------
-- Journal d'audit : lecture réservée (aucune écriture via l'API)
-- -----------------------------------------------------------------------------
create policy audit_logs_select on public.audit_logs
  for select to authenticated using ((select private.has_permission('audit.read')));
grant select on public.audit_logs to authenticated;
