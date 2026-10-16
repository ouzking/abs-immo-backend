-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0300 : référentiels (localités, types, équipements)
-- -----------------------------------------------------------------------------
-- Localités hiérarchiques et multi-pays :
--   region  (parent : aucun)
--   city    (parent : region)
--   commune (parent : city)
--   neighborhood / quartier (parent : commune OU city)
-- Les données sénégalaises insérées ici sont un point de départ ; elles sont
-- enrichies depuis le back-office (permission catalog.manage).
-- =============================================================================

create type public.locality_level as enum ('region', 'city', 'commune', 'neighborhood');

create table public.countries (
  code          char(2) primary key check (code ~ '^[A-Z]{2}$'),   -- ISO 3166-1 alpha-2
  name          text not null,
  phone_prefix  text not null check (phone_prefix ~ '^\+[1-9][0-9]{0,3}$'),
  currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'), -- ISO 4217
  is_active     boolean not null default true
);

insert into public.countries (code, name, phone_prefix, currency_code) values
  ('SN', 'Sénégal', '+221', 'XOF');

create table public.localities (
  id           uuid primary key default gen_random_uuid(),
  country_code char(2) not null references public.countries (code),
  parent_id    uuid references public.localities (id) on delete restrict,
  level        public.locality_level not null,
  name         text not null check (char_length(name) between 2 and 120),
  slug         text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  latitude     numeric(9, 6) check (latitude between -90 and 90),
  longitude    numeric(9, 6) check (longitude between -180 and 180),
  is_active    boolean not null default true,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint localities_parent_required check ((level = 'region') = (parent_id is null))
);
comment on table public.localities is 'Découpage géographique hiérarchique (région > ville > commune > quartier).';

-- Unicité du slug parmi les enfants d'un même parent (et parmi les régions d'un pays).
create unique index localities_parent_slug_key
  on public.localities (country_code, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), slug);
create index localities_parent_idx on public.localities (parent_id);
create index localities_level_idx on public.localities (country_code, level) where is_active;
create index localities_name_trgm_idx on public.localities using gin (name extensions.gin_trgm_ops);

create trigger localities_set_updated_at
  before update on public.localities
  for each row execute function private.set_updated_at();

-- Vérifie la cohérence parent/enfant (niveau et pays).
create or replace function private.localities_validate()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_parent public.localities;
begin
  if new.slug is null or new.slug = '' then
    new.slug := private.slugify(new.name);
  end if;
  if new.parent_id is null then
    return new;
  end if;
  if new.parent_id = new.id then
    raise exception 'Une localité ne peut pas être son propre parent.' using errcode = '23514';
  end if;
  select * into v_parent from public.localities where id = new.parent_id;
  if v_parent.country_code <> new.country_code then
    raise exception 'La localité parente doit appartenir au même pays.' using errcode = '23514';
  end if;
  if not (
       (new.level = 'city' and v_parent.level = 'region')
    or (new.level = 'commune' and v_parent.level = 'city')
    or (new.level = 'neighborhood' and v_parent.level in ('city', 'commune'))
  ) then
    raise exception 'Hiérarchie invalide : un(e) % ne peut pas dépendre d''un(e) %.', new.level, v_parent.level
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger localities_validate
  before insert or update on public.localities
  for each row execute function private.localities_validate();

-- Résout la chaîne complète (region, city, commune, neighborhood) d'une localité.
create or replace function private.locality_chain(p_locality_id uuid)
returns table (region_id uuid, city_id uuid, commune_id uuid, neighborhood_id uuid)
language sql
stable
set search_path = ''
as $$
  with recursive chain as (
    select l.id, l.parent_id, l.level from public.localities l where l.id = p_locality_id
    union all
    select p.id, p.parent_id, p.level from public.localities p join chain c on p.id = c.parent_id
  )
  select
    max(id::text) filter (where level = 'region')::uuid,
    max(id::text) filter (where level = 'city')::uuid,
    max(id::text) filter (where level = 'commune')::uuid,
    max(id::text) filter (where level = 'neighborhood')::uuid
  from chain;
$$;

-- -----------------------------------------------------------------------------
-- Types de biens
-- -----------------------------------------------------------------------------
create table public.property_types (
  code        text primary key check (code ~ '^[a-z_]{2,40}$'),
  label       text not null,
  label_plural text not null,
  is_land     boolean not null default false,   -- terrain : pas de chambres/salles de bain
  is_active   boolean not null default true,
  sort_order  integer not null default 0
);

insert into public.property_types (code, label, label_plural, is_land, sort_order) values
  ('apartment',       'Appartement',       'Appartements',       false, 10),
  ('house',           'Maison',            'Maisons',            false, 20),
  ('villa',           'Villa',             'Villas',             false, 30),
  ('land',            'Terrain',           'Terrains',           true,  40),
  ('office',          'Bureau',            'Bureaux',            false, 50),
  ('commercial',      'Local commercial',  'Locaux commerciaux', false, 60),
  ('building',        'Immeuble',          'Immeubles',          false, 70),
  ('studio',          'Studio',            'Studios',            false, 80),
  ('room',            'Chambre',           'Chambres',           false, 90),
  ('warehouse',       'Entrepôt',          'Entrepôts',          false, 100);

-- -----------------------------------------------------------------------------
-- Équipements
-- -----------------------------------------------------------------------------
create table public.amenities (
  code       text primary key check (code ~ '^[a-z_]{2,40}$'),
  label      text not null,
  category   text not null check (category in ('comfort', 'security', 'outdoor', 'services', 'building', 'utilities')),
  icon       text,
  is_active  boolean not null default true,
  sort_order integer not null default 0
);

insert into public.amenities (code, label, category, sort_order) values
  ('air_conditioning', 'Climatisation',            'comfort',   10),
  ('furnished_kitchen','Cuisine équipée',          'comfort',   20),
  ('water_heater',     'Chauffe-eau',              'comfort',   30),
  ('wardrobes',        'Placards',                 'comfort',   40),
  ('internet',         'Internet / fibre',         'utilities', 50),
  ('generator',        'Groupe électrogène',       'utilities', 60),
  ('solar_panels',     'Panneaux solaires',        'utilities', 70),
  ('water_tank',       'Réserve d''eau / surpresseur', 'utilities', 80),
  ('security_guard',   'Gardiennage',              'security',  90),
  ('cctv',             'Vidéosurveillance',        'security',  100),
  ('alarm',            'Alarme',                   'security',  110),
  ('gated_community',  'Résidence sécurisée',      'security',  120),
  ('swimming_pool',    'Piscine',                  'outdoor',   130),
  ('garden',           'Jardin',                   'outdoor',   140),
  ('terrace',          'Terrasse',                 'outdoor',   150),
  ('balcony',          'Balcon',                   'outdoor',   160),
  ('sea_view',         'Vue sur mer',              'outdoor',   170),
  ('rooftop',          'Toit-terrasse',            'outdoor',   180),
  ('parking',          'Parking',                  'building',  190),
  ('garage',           'Garage',                   'building',  200),
  ('elevator',         'Ascenseur',                'building',  210),
  ('caretaker_room',   'Chambre de gardien',       'building',  220),
  ('maid_room',        'Chambre de service',       'building',  230),
  ('gym',              'Salle de sport',           'services',  240),
  ('cleaning_service', 'Service de ménage',        'services',  250);

-- -----------------------------------------------------------------------------
-- Données de départ : Sénégal (14 régions, principales villes, communes de Dakar)
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
  v_region uuid;
  v_city uuid;
  v_commune uuid;
begin
  -- Régions
  for r in select * from (values
    ('Dakar', 1), ('Thiès', 2), ('Diourbel', 3), ('Saint-Louis', 4), ('Ziguinchor', 5),
    ('Kaolack', 6), ('Fatick', 7), ('Louga', 8), ('Kolda', 9), ('Tambacounda', 10),
    ('Matam', 11), ('Kaffrine', 12), ('Kédougou', 13), ('Sédhiou', 14)
  ) as t(name, ord) loop
    insert into public.localities (country_code, level, name, slug, sort_order)
    values ('SN', 'region', r.name, private.slugify(r.name), r.ord);
  end loop;

  -- Villes principales par région
  for r in select * from (values
    ('Dakar', 'Dakar'), ('Dakar', 'Pikine'), ('Dakar', 'Guédiawaye'), ('Dakar', 'Rufisque'),
    ('Dakar', 'Keur Massar'), ('Dakar', 'Diamniadio'), ('Dakar', 'Bargny'), ('Dakar', 'Sébikotane'),
    ('Thiès', 'Thiès'), ('Thiès', 'Mbour'), ('Thiès', 'Saly'), ('Thiès', 'Somone'), ('Thiès', 'Ngaparou'),
    ('Thiès', 'Popenguine'), ('Thiès', 'Tivaouane'), ('Thiès', 'Pout'), ('Thiès', 'Joal-Fadiouth'),
    ('Diourbel', 'Diourbel'), ('Diourbel', 'Touba'), ('Diourbel', 'Mbacké'),
    ('Saint-Louis', 'Saint-Louis'), ('Saint-Louis', 'Richard-Toll'), ('Saint-Louis', 'Dagana'),
    ('Ziguinchor', 'Ziguinchor'), ('Ziguinchor', 'Cap Skirring'), ('Ziguinchor', 'Oussouye'), ('Ziguinchor', 'Bignona'),
    ('Kaolack', 'Kaolack'), ('Fatick', 'Fatick'), ('Fatick', 'Foundiougne'), ('Louga', 'Louga'),
    ('Kolda', 'Kolda'), ('Tambacounda', 'Tambacounda'), ('Matam', 'Matam'),
    ('Kaffrine', 'Kaffrine'), ('Kédougou', 'Kédougou'), ('Sédhiou', 'Sédhiou')
  ) as t(region, city) loop
    select id into v_region from public.localities where level = 'region' and name = r.region;
    insert into public.localities (country_code, parent_id, level, name, slug)
    values ('SN', v_region, 'city', r.city, private.slugify(r.city));
  end loop;

  -- Communes d'arrondissement de la ville de Dakar
  select l.id into v_city from public.localities l
   join public.localities p on p.id = l.parent_id
   where l.level = 'city' and l.name = 'Dakar' and p.name = 'Dakar';
  for r in select * from (values
    ('Plateau'), ('Médina'), ('Gueule Tapée-Fass-Colobane'), ('Fann-Point E-Amitié'), ('Grand Dakar'),
    ('Biscuiterie'), ('HLM'), ('Hann Bel-Air'), ('Sicap-Liberté'), ('Dieuppeul-Derklé'),
    ('Mermoz-Sacré-Cœur'), ('Ouakam'), ('Ngor'), ('Yoff'), ('Grand Yoff'), ('Patte d''Oie'),
    ('Parcelles Assainies'), ('Cambérène'), ('Gorée')
  ) as t(name) loop
    insert into public.localities (country_code, parent_id, level, name, slug)
    values ('SN', v_city, 'commune', r.name, private.slugify(r.name));
  end loop;

  -- Quartiers recherchés (rattachés à leur commune)
  for r in select * from (values
    ('Ngor', 'Almadies'), ('Ngor', 'Ngor Village'),
    ('Ouakam', 'Mamelles'), ('Ouakam', 'Ouakam'),
    ('Mermoz-Sacré-Cœur', 'Mermoz'), ('Mermoz-Sacré-Cœur', 'Sacré-Cœur'),
    ('Fann-Point E-Amitié', 'Point E'), ('Fann-Point E-Amitié', 'Fann Résidence'), ('Fann-Point E-Amitié', 'Amitié'),
    ('Plateau', 'Plateau'), ('Yoff', 'Yoff'), ('Hann Bel-Air', 'Hann Maristes')
  ) as t(commune, name) loop
    select id into v_commune from public.localities where level = 'commune' and parent_id = v_city and name = r.commune;
    insert into public.localities (country_code, parent_id, level, name, slug)
    values ('SN', v_commune, 'neighborhood', r.name, private.slugify(r.name));
  end loop;
end $$;

-- =============================================================================
-- RLS et privilèges : référentiels lisibles publiquement (éléments actifs),
-- modifiables avec catalog.manage.
-- =============================================================================
alter table public.countries enable row level security;
alter table public.localities enable row level security;
alter table public.property_types enable row level security;
alter table public.amenities enable row level security;

create policy countries_select on public.countries
  for select to anon, authenticated using (is_active or (select private.has_permission('catalog.manage')));
create policy countries_write on public.countries
  for all to authenticated
  using ((select private.has_permission('catalog.manage')))
  with check ((select private.has_permission('catalog.manage')));

create policy localities_select on public.localities
  for select to anon, authenticated using (is_active or (select private.is_active_staff()));
create policy localities_write on public.localities
  for all to authenticated
  using ((select private.has_permission('catalog.manage')))
  with check ((select private.has_permission('catalog.manage')));

create policy property_types_select on public.property_types
  for select to anon, authenticated using (is_active or (select private.is_active_staff()));
create policy property_types_write on public.property_types
  for all to authenticated
  using ((select private.has_permission('catalog.manage')))
  with check ((select private.has_permission('catalog.manage')));

create policy amenities_select on public.amenities
  for select to anon, authenticated using (is_active or (select private.is_active_staff()));
create policy amenities_write on public.amenities
  for all to authenticated
  using ((select private.has_permission('catalog.manage')))
  with check ((select private.has_permission('catalog.manage')));

grant select on public.countries, public.localities, public.property_types, public.amenities to anon, authenticated;
grant insert, update, delete on public.countries, public.localities, public.property_types, public.amenities to authenticated;

create trigger localities_audit
  after insert or update or delete on public.localities
  for each row execute function private.audit_trigger();
create trigger property_types_audit
  after insert or update or delete on public.property_types
  for each row execute function private.audit_trigger();
create trigger amenities_audit
  after insert or update or delete on public.amenities
  for each row execute function private.audit_trigger();
