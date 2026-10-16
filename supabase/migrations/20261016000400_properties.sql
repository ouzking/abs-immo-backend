-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0400 : biens immobiliers
-- -----------------------------------------------------------------------------
-- Deux axes de statut INDÉPENDANTS :
--   publication_status : draft → pending_review → published → unpublished / archived
--   commercial_status  : available → reserved → sold (vente) | rented (location)
-- La table `properties` n'est JAMAIS lisible par `anon` : le site public passe
-- par la vue `public_properties` et les RPC de la migration 0700, qui ne
-- renvoient que les annonces publiées et les colonnes publiques.
-- =============================================================================

create type public.transaction_type     as enum ('sale', 'rent');
create type public.rent_period          as enum ('day', 'week', 'month', 'year');
create type public.publication_status   as enum ('draft', 'pending_review', 'published', 'unpublished', 'archived');
create type public.commercial_status    as enum ('available', 'reserved', 'sold', 'rented');
create type public.surface_unit         as enum ('sqm', 'are', 'hectare');
create type public.address_visibility   as enum ('hidden', 'approximate', 'exact');
create type public.property_legal_status as enum ('titre_foncier', 'bail', 'deliberation', 'permis_occuper', 'autre');
create type public.property_document_type as enum ('title_deed', 'mandate', 'contract', 'plan', 'tax', 'identity', 'other');

create sequence public.property_reference_seq;

create table public.properties (
  id                  uuid primary key default gen_random_uuid(),
  -- default '' : générés par properties_derive (avant contrôle des contraintes) ; facultatifs à l'insertion.
  reference           text not null unique default '' check (reference ~ '^[A-Z0-9-]{4,30}$'),
  title               text not null check (char_length(title) between 5 and 160),
  slug                text not null unique default '' check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 200),
  short_description   text check (char_length(short_description) <= 300),
  description         text check (char_length(description) <= 20000),

  property_type       text not null references public.property_types (code) on update cascade,
  transaction_type    public.transaction_type not null,

  -- Prix : entier exact en unité monétaire (FCFA n'a pas de sous-unité usuelle).
  price_amount        bigint check (price_amount > 0 and price_amount < 1000000000000000),
  currency_code       char(3) not null default 'XOF' check (currency_code ~ '^[A-Z]{3}$'),
  price_on_request    boolean not null default false,
  price_negotiable    boolean not null default false,
  rent_period         public.rent_period,
  deposit_amount      bigint check (deposit_amount >= 0),
  agency_fee_amount   bigint check (agency_fee_amount >= 0),

  surface_area        numeric(12, 2) check (surface_area > 0),
  surface_unit        public.surface_unit not null default 'sqm',
  land_area           numeric(12, 2) check (land_area > 0),
  bedrooms            smallint check (bedrooms between 0 and 200),
  bathrooms           smallint check (bathrooms between 0 and 200),
  rooms               smallint check (rooms between 0 and 500),
  toilets             smallint check (toilets between 0 and 200),
  floor               smallint check (floor between -5 and 200),
  total_floors        smallint check (total_floors between 0 and 200),
  parking_spaces      smallint check (parking_spaces between 0 and 1000),
  year_built          smallint check (year_built between 1800 and 2200),
  is_furnished        boolean,
  legal_status        public.property_legal_status,

  -- Localisation : `locality_id` = niveau le plus précis connu ; la chaîne
  -- région/ville/commune/quartier est déduite automatiquement (déclencheur).
  country_code        char(2) not null default 'SN' references public.countries (code),
  locality_id         uuid not null references public.localities (id),
  region_id           uuid references public.localities (id),
  city_id             uuid references public.localities (id),
  commune_id          uuid references public.localities (id),
  neighborhood_id     uuid references public.localities (id),
  location_label      text check (char_length(location_label) <= 160),   -- public : "Proche VDN"
  address_line        text check (char_length(address_line) <= 300),     -- interne
  latitude            numeric(9, 6) check (latitude between -90 and 90),
  longitude           numeric(9, 6) check (longitude between -180 and 180),
  address_visibility  public.address_visibility not null default 'approximate',

  commercial_status   public.commercial_status not null default 'available',
  publication_status  public.publication_status not null default 'draft',
  status_changed_at   timestamptz not null default now(),   -- dernier changement de commercial_status
  published_at        timestamptz,                           -- première publication
  unpublished_at      timestamptz,
  archived_at         timestamptz,

  is_featured         boolean not null default false,
  featured_rank       smallint not null default 0,

  agent_id            uuid references public.agents (profile_id) on delete set null,
  created_by          uuid references public.profiles (id) on delete set null default auth.uid(),

  seo_title           text check (char_length(seo_title) <= 120),
  seo_description     text check (char_length(seo_description) <= 320),
  internal_notes      text check (char_length(internal_notes) <= 10000),  -- jamais exposé publiquement

  search_vector       tsvector,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint properties_price_required   check (price_on_request or price_amount is not null),
  constraint properties_rent_period      check ((transaction_type = 'rent') = (rent_period is not null)),
  constraint properties_status_sale      check (commercial_status <> 'sold'   or transaction_type = 'sale'),
  constraint properties_status_rent      check (commercial_status <> 'rented' or transaction_type = 'rent'),
  constraint properties_coordinates_pair check ((latitude is null) = (longitude is null))
);

comment on table public.properties is 'Biens immobiliers (données internes complètes). Accès public via public_properties uniquement.';
comment on column public.properties.price_amount is 'Prix exact en unité de la devise (FCFA). bigint : aucune perte de précision.';
comment on column public.properties.address_visibility is 'hidden : aucune coordonnée publique ; approximate : coordonnées arrondies (~1 km) ; exact : adresse et coordonnées exactes.';

create index properties_public_listing_idx on public.properties (publication_status, transaction_type, property_type, price_amount);
create index properties_published_at_idx on public.properties (published_at desc) where publication_status = 'published';
create index properties_featured_idx on public.properties (featured_rank desc, published_at desc) where is_featured and publication_status = 'published';
create index properties_city_idx on public.properties (city_id);
create index properties_neighborhood_idx on public.properties (neighborhood_id);
create index properties_commune_idx on public.properties (commune_id);
create index properties_region_idx on public.properties (region_id);
create index properties_locality_idx on public.properties (locality_id);
create index properties_agent_idx on public.properties (agent_id);
create index properties_created_by_idx on public.properties (created_by);
create index properties_commercial_idx on public.properties (commercial_status, status_changed_at);
create index properties_search_idx on public.properties using gin (search_vector);
create index properties_title_trgm_idx on public.properties using gin (title extensions.gin_trgm_ops);

alter table public.properties enable row level security;

-- -----------------------------------------------------------------------------
-- Photos
-- -----------------------------------------------------------------------------
create table public.property_media (
  id           uuid primary key default gen_random_uuid(),
  property_id  uuid not null references public.properties (id) on delete cascade,
  storage_path text not null unique check (char_length(storage_path) <= 500),
  alt_text     text check (char_length(alt_text) <= 250),
  sort_order   integer not null default 0 check (sort_order >= 0),
  is_cover     boolean not null default false,
  width        integer check (width > 0),
  height       integer check (height > 0),
  size_bytes   integer check (size_bytes > 0),
  mime_type    text check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'image/avif')),
  created_by   uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  -- Convention de stockage : bucket property-images, chemin "<property_id>/<fichier>"
  constraint property_media_path_prefix check (storage_path like property_id::text || '/%')
);
comment on table public.property_media is 'Photos des biens (bucket property-images, chemin <property_id>/<fichier>).';

create unique index property_media_one_cover_idx on public.property_media (property_id) where is_cover;
create index property_media_property_order_idx on public.property_media (property_id, sort_order);

alter table public.property_media enable row level security;

-- -----------------------------------------------------------------------------
-- Équipements et caractéristiques libres
-- -----------------------------------------------------------------------------
create table public.property_amenities (
  property_id  uuid not null references public.properties (id) on delete cascade,
  amenity_code text not null references public.amenities (code) on update cascade on delete cascade,
  primary key (property_id, amenity_code)
);
create index property_amenities_amenity_idx on public.property_amenities (amenity_code);
alter table public.property_amenities enable row level security;

create table public.property_features (
  id          uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  label       text not null check (char_length(label) between 1 and 80),
  value       text check (char_length(value) <= 200),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);
create index property_features_property_idx on public.property_features (property_id, sort_order);
alter table public.property_features enable row level security;

-- -----------------------------------------------------------------------------
-- Documents internes (titres, mandats, contrats) — jamais publics
-- -----------------------------------------------------------------------------
create table public.property_documents (
  id            uuid primary key default gen_random_uuid(),
  property_id   uuid not null references public.properties (id) on delete cascade,
  storage_path  text not null unique check (char_length(storage_path) <= 500),
  title         text not null check (char_length(title) between 1 and 200),
  document_type public.property_document_type not null default 'other',
  mime_type     text check (char_length(mime_type) <= 100),
  size_bytes    integer check (size_bytes > 0),
  uploaded_by   uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  constraint property_documents_path_prefix check (storage_path like property_id::text || '/%')
);
create index property_documents_property_idx on public.property_documents (property_id);
alter table public.property_documents enable row level security;

-- =============================================================================
-- Autorisations par bien
-- =============================================================================
create or replace function private.can_read_property(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('properties.read_all')
      or (private.is_active_staff() and exists (
            select 1 from public.properties p
             where p.id = p_property_id
               and (p.agent_id = auth.uid() or p.created_by = auth.uid())));
$$;

create or replace function private.can_edit_property(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('properties.update_all')
      or (private.has_permission('properties.update_own') and exists (
            select 1 from public.properties p
             where p.id = p_property_id and p.agent_id = auth.uid()));
$$;

grant execute on function private.can_read_property(uuid), private.can_edit_property(uuid) to authenticated;

-- =============================================================================
-- Déclencheurs des biens
-- =============================================================================

-- Valeurs dérivées : référence, slug, chaîne de localités, recherche, dates.
create or replace function private.properties_derive()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_chain record;
  v_type_label text;
  v_names text;
begin
  if tg_op = 'INSERT' then
    if new.reference is null or new.reference = '' then
      new.reference := 'ABS-' || case new.transaction_type when 'sale' then 'V' else 'L' end
                       || '-' || to_char(now(), 'YY')
                       || lpad(nextval('public.property_reference_seq')::text, 5, '0');
    end if;
    if new.slug is null or new.slug = '' then
      new.slug := left(private.slugify(new.title), 180) || '-' || lower(new.reference);
    end if;
  end if;

  new.slug := private.slugify(new.slug);

  -- Les terrains n'ont pas de pièces.
  if exists (select 1 from public.property_types t where t.code = new.property_type and t.is_land) then
    new.bedrooms := null; new.bathrooms := null; new.rooms := null; new.toilets := null;
  end if;

  -- Chaîne géographique
  if tg_op = 'INSERT' or new.locality_id is distinct from old.locality_id then
    select * into v_chain from private.locality_chain(new.locality_id);
    new.region_id := v_chain.region_id;
    new.city_id := v_chain.city_id;
    new.commune_id := v_chain.commune_id;
    new.neighborhood_id := v_chain.neighborhood_id;
    select l.country_code into new.country_code from public.localities l where l.id = new.locality_id;
  end if;

  -- Dates de statut
  if tg_op = 'UPDATE' and new.commercial_status is distinct from old.commercial_status then
    new.status_changed_at := now();
  end if;
  if new.publication_status = 'published' and (tg_op = 'INSERT' or old.publication_status <> 'published') then
    new.published_at := coalesce(new.published_at, now());
    new.unpublished_at := null;
    new.archived_at := null;
  elsif tg_op = 'UPDATE' and new.publication_status is distinct from old.publication_status then
    if new.publication_status = 'unpublished' then new.unpublished_at := now(); end if;
    if new.publication_status = 'archived' then new.archived_at := now(); end if;
  end if;
  if new.publication_status <> 'published' then
    new.is_featured := case when new.publication_status = 'archived' then false else new.is_featured end;
  end if;

  -- Vecteur de recherche (titre/référence > lieux/type > résumés > description)
  select t.label into v_type_label from public.property_types t where t.code = new.property_type;
  select string_agg(l.name, ' ') into v_names
    from public.localities l
   where l.id in (new.region_id, new.city_id, new.commune_id, new.neighborhood_id);

  new.search_vector :=
       setweight(to_tsvector('public.french_unaccent', coalesce(new.title, '') || ' ' || coalesce(new.reference, '')), 'A')
    || setweight(to_tsvector('public.french_unaccent', coalesce(v_names, '') || ' ' || coalesce(v_type_label, '')), 'B')
    || setweight(to_tsvector('public.french_unaccent', coalesce(new.short_description, '') || ' ' || coalesce(new.location_label, '')), 'C')
    || setweight(to_tsvector('public.french_unaccent', coalesce(new.description, '')), 'D');

  return new;
end;
$$;

create trigger properties_derive
  before insert or update on public.properties
  for each row execute function private.properties_derive();

-- Règles métier et autorisations fines (ce que RLS ne peut pas exprimer :
-- comparaison ancienne/nouvelle valeur, transitions de statut).
create or replace function private.properties_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_trusted boolean := private.is_trusted_writer();
  v_can_publish boolean;
  v_can_all boolean;
begin
  -- 1. Autorisations (utilisateurs de l'API uniquement) — vérifiées AVANT les
  --    règles de données pour renvoyer « permission refusée » en priorité.
  if not v_trusted then
    v_can_publish := private.has_permission('properties.publish');
    v_can_all := private.has_permission('properties.update_all');

    if tg_op = 'INSERT' then
      -- Un agent crée ses propres biens ; seul update_all peut désigner un autre agent.
      if not v_can_all then
        if new.agent_id is null and exists (select 1 from public.agents where profile_id = auth.uid() and is_active) then
          new.agent_id := auth.uid();
        elsif new.agent_id is distinct from auth.uid() then
          raise exception 'Vous ne pouvez créer des biens que pour vous-même.' using errcode = '42501';
        end if;
      end if;
      if new.publication_status not in ('draft', 'pending_review') and not v_can_publish then
        raise exception 'Un bien doit être créé en brouillon ou soumis à validation.' using errcode = '42501';
      end if;
      if new.is_featured and not v_can_publish then
        raise exception 'Permission properties.publish requise pour la mise en avant.' using errcode = '42501';
      end if;
      -- Colonnes système : jamais fournies par le client.
      new.created_by := auth.uid();
      new.created_at := now();
      new.status_changed_at := now();
      new.published_at := case when new.publication_status = 'published' then now() end;
      new.unpublished_at := null;
      new.archived_at := null;
    else
      -- published_at/unpublished_at/archived_at sont gérés par properties_derive
      -- (exécuté avant ce garde-fou) et ne figurent pas dans les GRANT UPDATE.
      if new.reference is distinct from old.reference or new.created_by is distinct from old.created_by
         or new.created_at is distinct from old.created_at then
        raise exception 'Colonne non modifiable.' using errcode = '42501';
      end if;
      if old.publication_status = 'archived' and not v_can_publish then
        raise exception 'Un bien archivé ne peut être modifié que par un responsable.' using errcode = '42501';
      end if;
      if new.agent_id is distinct from old.agent_id and not v_can_all then
        raise exception 'Permission properties.update_all requise pour changer l''agent responsable.' using errcode = '42501';
      end if;
      if (new.is_featured is distinct from old.is_featured or new.featured_rank is distinct from old.featured_rank)
         and not v_can_publish then
        raise exception 'Permission properties.publish requise pour la mise en avant.' using errcode = '42501';
      end if;
      if new.publication_status is distinct from old.publication_status and not v_can_publish
         -- Sans droit de publication : seulement brouillon <-> en attente de validation.
         and not (old.publication_status in ('draft', 'pending_review')
                  and new.publication_status in ('draft', 'pending_review')) then
        raise exception 'Permission properties.publish requise pour passer de % à %.', old.publication_status, new.publication_status
          using errcode = '42501';
      end if;
    end if;
  end if;

  -- 2. Règles de données (toujours appliquées, même pour service_role)
  if new.agent_id is not null and (tg_op = 'INSERT' or new.agent_id is distinct from old.agent_id)
     and not exists (select 1 from public.agents a join public.profiles p on p.id = a.profile_id
                      where a.profile_id = new.agent_id and a.is_active and p.is_active) then
    raise exception 'L''agent responsable doit être un agent actif.' using errcode = '23514';
  end if;

  if new.publication_status = 'published' and (tg_op = 'INSERT' or old.publication_status <> 'published') then
    if tg_op = 'INSERT' or not exists (select 1 from public.property_media m where m.property_id = new.id and m.is_cover) then
      raise exception 'Publication impossible : le bien doit avoir au moins une photo de couverture.'
        using errcode = '23514', hint = 'PUBLISH_REQUIRES_COVER';
    end if;
    if coalesce(char_length(new.short_description), 0) < 20 then
      raise exception 'Publication impossible : la description courte doit contenir au moins 20 caractères.'
        using errcode = '23514', hint = 'PUBLISH_REQUIRES_SHORT_DESCRIPTION';
    end if;
  end if;

  return new;
end;
$$;

create trigger properties_guard
  before insert or update on public.properties
  for each row execute function private.properties_guard();

create trigger properties_set_updated_at
  before update on public.properties
  for each row execute function private.set_updated_at();

create trigger properties_audit
  after insert or update or delete on public.properties
  for each row execute function private.audit_trigger(
    'publication_status,commercial_status,price_amount,price_on_request,agent_id,is_featured,transaction_type,title,slug,address_visibility');

-- =============================================================================
-- Déclencheurs des photos : une seule couverture, couverture automatique,
-- protection de la dernière photo d'un bien publié.
-- =============================================================================
create or replace function private.property_media_before()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and (new.property_id <> old.property_id or new.storage_path <> old.storage_path) then
    raise exception 'Le bien et le chemin d''une photo ne sont pas modifiables.' using errcode = '42501';
  end if;
  if new.is_cover and (tg_op = 'INSERT' or not old.is_cover) then
    update public.property_media set is_cover = false
     where property_id = new.property_id and is_cover and id <> new.id;
  end if;
  if tg_op = 'INSERT' and not new.is_cover
     and not exists (select 1 from public.property_media where property_id = new.property_id and is_cover) then
    new.is_cover := true;
  end if;
  return new;
end;
$$;

create trigger property_media_before
  before insert or update on public.property_media
  for each row execute function private.property_media_before();

create or replace function private.property_media_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.properties p where p.id = old.property_id and p.publication_status = 'published')
     and not exists (select 1 from public.property_media m where m.property_id = old.property_id and m.id <> old.id) then
    raise exception 'Impossible de supprimer la dernière photo d''un bien publié. Retirez d''abord la publication.'
      using errcode = '23514', hint = 'LAST_MEDIA_OF_PUBLISHED_PROPERTY';
  end if;
  return old;
end;
$$;

create trigger property_media_before_delete
  before delete on public.property_media
  for each row execute function private.property_media_before_delete();

create or replace function private.property_media_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.is_cover then
    update public.property_media set is_cover = true
     where id = (select id from public.property_media
                  where property_id = old.property_id
                  order by sort_order, created_at limit 1);
  end if;
  return null;
end;
$$;

create trigger property_media_after_delete
  after delete on public.property_media
  for each row execute function private.property_media_after_delete();

create trigger property_media_set_updated_at
  before update on public.property_media
  for each row execute function private.set_updated_at();

create trigger property_media_audit
  after insert or delete on public.property_media
  for each row execute function private.audit_trigger();

create trigger property_documents_audit
  after insert or delete on public.property_documents
  for each row execute function private.audit_trigger();

-- Réordonne les photos d'un bien selon l'ordre du tableau fourni.
-- SECURITY INVOKER : les politiques RLS de property_media s'appliquent.
create or replace function public.reorder_property_media(p_property_id uuid, p_media_ids uuid[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.property_media m
     set sort_order = o.ord - 1
    from unnest(p_media_ids) with ordinality as o(id, ord)
   where m.id = o.id and m.property_id = p_property_id;
  get diagnostics v_updated = row_count;
  if v_updated <> coalesce(array_length(p_media_ids, 1), 0) then
    raise exception 'Certaines photos sont introuvables ou non modifiables.' using errcode = 'P0002';
  end if;
end;
$$;

-- Remplace la liste des équipements d'un bien (SECURITY INVOKER).
create or replace function public.set_property_amenities(p_property_id uuid, p_amenity_codes text[])
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not private.can_edit_property(p_property_id) then
    raise exception 'Vous ne pouvez pas modifier ce bien.' using errcode = '42501';
  end if;
  delete from public.property_amenities
   where property_id = p_property_id and amenity_code <> all (coalesce(p_amenity_codes, '{}'));
  insert into public.property_amenities (property_id, amenity_code)
  select p_property_id, unnest(coalesce(p_amenity_codes, '{}'))
  on conflict do nothing;
end;
$$;

-- =============================================================================
-- Politiques RLS
-- =============================================================================
create policy properties_select on public.properties
  for select to authenticated
  using ((select private.has_permission('properties.read_all'))
         or ((select private.is_active_staff()) and (agent_id = (select auth.uid()) or created_by = (select auth.uid()))));

create policy properties_insert on public.properties
  for insert to authenticated
  with check ((select private.has_permission('properties.create')));

create policy properties_update on public.properties
  for update to authenticated
  using ((select private.has_permission('properties.update_all'))
         or ((select private.has_permission('properties.update_own')) and agent_id = (select auth.uid())))
  with check ((select private.has_permission('properties.update_all'))
              or ((select private.has_permission('properties.update_own')) and agent_id = (select auth.uid())));

create policy properties_delete on public.properties
  for delete to authenticated
  using ((select private.has_permission('properties.delete')));

-- Tables filles : lecture si on peut lire le bien ; écriture si on peut le modifier.
create policy property_media_select on public.property_media
  for select to authenticated using (private.can_read_property(property_id));
create policy property_media_insert on public.property_media
  for insert to authenticated with check (private.can_edit_property(property_id));
create policy property_media_update on public.property_media
  for update to authenticated using (private.can_edit_property(property_id)) with check (private.can_edit_property(property_id));
create policy property_media_delete on public.property_media
  for delete to authenticated using (private.can_edit_property(property_id));

create policy property_amenities_select on public.property_amenities
  for select to authenticated using (private.can_read_property(property_id));
create policy property_amenities_insert on public.property_amenities
  for insert to authenticated with check (private.can_edit_property(property_id));
create policy property_amenities_delete on public.property_amenities
  for delete to authenticated using (private.can_edit_property(property_id));

create policy property_features_select on public.property_features
  for select to authenticated using (private.can_read_property(property_id));
create policy property_features_insert on public.property_features
  for insert to authenticated with check (private.can_edit_property(property_id));
create policy property_features_update on public.property_features
  for update to authenticated using (private.can_edit_property(property_id)) with check (private.can_edit_property(property_id));
create policy property_features_delete on public.property_features
  for delete to authenticated using (private.can_edit_property(property_id));

create policy property_documents_select on public.property_documents
  for select to authenticated using (private.can_edit_property(property_id));
create policy property_documents_insert on public.property_documents
  for insert to authenticated with check (private.can_edit_property(property_id));
create policy property_documents_delete on public.property_documents
  for delete to authenticated using (private.can_edit_property(property_id));

-- =============================================================================
-- Privilèges (aucun pour anon)
-- =============================================================================
grant select, insert, delete on public.properties to authenticated;
grant usage on sequence public.property_reference_seq to authenticated;
grant update (title, slug, short_description, description, property_type, transaction_type,
              price_amount, currency_code, price_on_request, price_negotiable, rent_period, deposit_amount,
              agency_fee_amount, surface_area, surface_unit, land_area, bedrooms, bathrooms, rooms, toilets,
              floor, total_floors, parking_spaces, year_built, is_furnished, legal_status, locality_id,
              location_label, address_line, latitude, longitude, address_visibility, commercial_status,
              publication_status, is_featured, featured_rank, agent_id, seo_title, seo_description, internal_notes)
  on public.properties to authenticated;
grant select, insert, delete on public.property_media to authenticated;
grant update (alt_text, sort_order, is_cover, width, height) on public.property_media to authenticated;
grant select, insert, delete on public.property_amenities to authenticated;
grant select, insert, update, delete on public.property_features to authenticated;
grant select, insert, delete on public.property_documents to authenticated;

grant execute on function public.reorder_property_media(uuid, uuid[]), public.set_property_amenities(uuid, text[])
  to authenticated;

-- Utilitaires appelés par des déclencheurs SECURITY INVOKER (droits de l'appelant).
grant execute on function private.slugify(text), private.locality_chain(uuid) to authenticated;
