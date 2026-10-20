-- =============================================================================
-- ABS IMMO & SERVICES — Migration 20261020000100 : annonces bilingues FR/EN
-- Contrat 1.1.0 (rétrocompatible : uniquement des ajouts).
-- -----------------------------------------------------------------------------
-- * Champs anglais facultatifs sur les biens (NULL => le site affiche le français).
-- * Libellés anglais des types de biens et des équipements.
-- * Vecteur de recherche anglais : search_properties trouve les annonces avec
--   une requête en français OU en anglais, sans changement de signature.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Recherche plein texte anglaise insensible aux accents (noms de lieux : Thiès…)
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_ts_config where cfgname = 'english_unaccent') then
    create text search configuration public.english_unaccent (copy = pg_catalog.english);
    alter text search configuration public.english_unaccent
      alter mapping for hword, hword_part, word with extensions.unaccent, pg_catalog.english_stem;
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- Biens : champs anglais
-- -----------------------------------------------------------------------------
alter table public.properties
  add column title_en             text check (title_en is null or char_length(title_en) between 5 and 160),
  add column short_description_en text check (char_length(short_description_en) <= 300),
  add column description_en       text check (char_length(description_en) <= 20000),
  add column seo_title_en         text check (char_length(seo_title_en) <= 120),
  add column seo_description_en   text check (char_length(seo_description_en) <= 320),
  add column search_vector_en     tsvector;

comment on column public.properties.title_en is 'Titre anglais facultatif. NULL : le site affiche title (français).';

create index properties_search_en_idx on public.properties using gin (search_vector_en);

grant update (title_en, short_description_en, description_en, seo_title_en, seo_description_en)
  on public.properties to authenticated;

-- -----------------------------------------------------------------------------
-- Référentiels : libellés anglais (NULL => repli sur le libellé français)
-- -----------------------------------------------------------------------------
alter table public.property_types
  add column label_en        text check (char_length(label_en) <= 80),
  add column label_plural_en text check (char_length(label_plural_en) <= 80);

alter table public.amenities
  add column label_en text check (char_length(label_en) <= 80);

update public.property_types t set label_en = v.l, label_plural_en = v.p
from (values
  ('apartment',  'Apartment',        'Apartments'),
  ('house',      'House',            'Houses'),
  ('villa',      'Villa',            'Villas'),
  ('land',       'Land',             'Land plots'),
  ('office',     'Office',           'Offices'),
  ('commercial', 'Commercial space', 'Commercial spaces'),
  ('building',   'Building',         'Buildings'),
  ('studio',     'Studio',           'Studios'),
  ('room',       'Room',             'Rooms'),
  ('warehouse',  'Warehouse',        'Warehouses')
) as v(code, l, p)
where t.code = v.code;

update public.amenities a set label_en = v.l
from (values
  ('air_conditioning',  'Air conditioning'),
  ('furnished_kitchen', 'Fitted kitchen'),
  ('water_heater',      'Water heater'),
  ('wardrobes',         'Built-in wardrobes'),
  ('internet',          'Internet / fibre'),
  ('generator',         'Generator'),
  ('solar_panels',      'Solar panels'),
  ('water_tank',        'Water tank / booster pump'),
  ('security_guard',    'Security guard'),
  ('cctv',              'CCTV'),
  ('alarm',             'Alarm system'),
  ('gated_community',   'Gated community'),
  ('swimming_pool',     'Swimming pool'),
  ('garden',            'Garden'),
  ('terrace',           'Terrace'),
  ('balcony',           'Balcony'),
  ('sea_view',          'Sea view'),
  ('rooftop',           'Rooftop terrace'),
  ('parking',           'Parking'),
  ('garage',            'Garage'),
  ('elevator',          'Elevator'),
  ('caretaker_room',    'Caretaker''s room'),
  ('maid_room',         'Staff room'),
  ('gym',               'Gym'),
  ('cleaning_service',  'Cleaning service')
) as v(code, l)
where a.code = v.code;

-- -----------------------------------------------------------------------------
-- Vecteur de recherche anglais
-- Calculé même sans traduction (lieux + type en anglais) pour qu'une requête
-- comme « villa dakar » ou « apartment almadies » trouve toutes les annonces.
-- -----------------------------------------------------------------------------
create or replace function private.property_search_vector_en(p public.properties)
returns tsvector
language sql
stable
set search_path = ''
as $$
  select
       setweight(to_tsvector('public.english_unaccent', coalesce(p.title_en, '') || ' ' || coalesce(p.reference, '')), 'A')
    || setweight(to_tsvector('public.english_unaccent',
         coalesce((select string_agg(l.name, ' ') from public.localities l
                    where l.id in (p.region_id, p.city_id, p.commune_id, p.neighborhood_id)), '')
         || ' ' || coalesce((select t.label_en from public.property_types t where t.code = p.property_type), '')), 'B')
    || setweight(to_tsvector('public.english_unaccent', coalesce(p.short_description_en, '')), 'C')
    || setweight(to_tsvector('public.english_unaccent', coalesce(p.description_en, '')), 'D');
$$;

-- Déclencheur distinct, exécuté après properties_derive (ordre alphabétique),
-- qui a déjà renseigné la chaîne géographique.
create or replace function private.properties_search_en()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_vector_en := private.property_search_vector_en(new);
  return new;
end;
$$;

create trigger properties_search_en
  before insert or update on public.properties
  for each row execute function private.properties_search_en();

grant execute on function private.property_search_vector_en(public.properties) to authenticated, service_role;

-- Rattrapage des biens existants sans déclencher les autres déclencheurs
-- (updated_at et audit inchangés).
set local session_replication_role = replica;
update public.properties p set search_vector_en = private.property_search_vector_en(p);
set local session_replication_role = origin;

-- -----------------------------------------------------------------------------
-- Vue publique : nouvelles colonnes AJOUTÉES EN FIN (compatibilité des
-- applications existantes et des fonctions qui renvoient ce type de ligne).
-- -----------------------------------------------------------------------------
create or replace view public.public_properties
with (security_barrier = true)
as
select
  p.id,
  p.reference,
  p.slug,
  p.title,
  p.short_description,
  p.description,
  p.property_type,
  pt.label                                   as property_type_label,
  p.transaction_type,
  case when p.price_on_request then null else p.price_amount end as price_amount,
  p.currency_code,
  p.price_on_request,
  p.price_negotiable,
  p.rent_period,
  p.deposit_amount,
  p.agency_fee_amount,
  p.surface_area,
  p.surface_unit,
  p.land_area,
  p.bedrooms,
  p.bathrooms,
  p.rooms,
  p.toilets,
  p.floor,
  p.total_floors,
  p.parking_spaces,
  p.year_built,
  p.is_furnished,
  p.legal_status,
  p.country_code,
  p.region_id,
  lr.name                                    as region_name,
  lr.slug                                    as region_slug,
  p.city_id,
  lc.name                                    as city_name,
  lc.slug                                    as city_slug,
  p.commune_id,
  lco.name                                   as commune_name,
  lco.slug                                   as commune_slug,
  p.neighborhood_id,
  ln.name                                    as neighborhood_name,
  ln.slug                                    as neighborhood_slug,
  p.location_label,
  case when p.address_visibility = 'exact' then p.address_line end as address_line,
  case p.address_visibility
    when 'exact' then p.latitude
    when 'approximate' then round(p.latitude, 2)
  end                                        as latitude,
  case p.address_visibility
    when 'exact' then p.longitude
    when 'approximate' then round(p.longitude, 2)
  end                                        as longitude,
  p.address_visibility                       as location_precision,
  p.commercial_status,
  p.is_featured,
  p.featured_rank,
  p.published_at,
  p.updated_at,
  p.seo_title,
  p.seo_description,
  cover.storage_path                         as cover_image_path,
  cover.alt_text                             as cover_image_alt,
  (select count(*) from public.property_media m where m.property_id = p.id)::integer as image_count,
  coalesce((select array_agg(pa.amenity_code order by pa.amenity_code)
              from public.property_amenities pa where pa.property_id = p.id), '{}') as amenity_codes,
  case when a.is_public and a.is_active and ap.is_active then
    jsonb_build_object(
      'slug', a.slug, 'display_name', a.display_name, 'job_title', a.job_title,
      'public_phone', a.public_phone, 'whatsapp_phone', a.whatsapp_phone,
      'public_email', a.public_email, 'photo_path', a.photo_path)
  end                                        as agent,
  p.search_vector,
  -- 1.1.0 : contenu anglais
  p.title_en,
  p.short_description_en,
  p.description_en,
  p.seo_title_en,
  p.seo_description_en,
  pt.label_en                                as property_type_label_en,
  (p.title_en is not null)                   as has_english,
  p.search_vector_en
from public.properties p
join public.property_types pt on pt.code = p.property_type
left join public.localities lr  on lr.id  = p.region_id
left join public.localities lc  on lc.id  = p.city_id
left join public.localities lco on lco.id = p.commune_id
left join public.localities ln  on ln.id  = p.neighborhood_id
left join public.agents a on a.profile_id = p.agent_id
left join public.profiles ap on ap.id = a.profile_id
left join lateral (
  select m.storage_path, m.alt_text from public.property_media m
   where m.property_id = p.id and m.is_cover limit 1
) cover on true
where p.publication_status = 'published';

-- -----------------------------------------------------------------------------
-- Recherche : requête comparée aux vecteurs FR et EN (même signature).
-- -----------------------------------------------------------------------------
create or replace function public.search_properties(
  p_query              text default null,
  p_transaction_type   public.transaction_type default null,
  p_property_types     text[] default null,
  p_region_id          uuid default null,
  p_city_id            uuid default null,
  p_commune_id         uuid default null,
  p_neighborhood_id    uuid default null,
  p_min_price          bigint default null,
  p_max_price          bigint default null,
  p_min_bedrooms       smallint default null,
  p_min_bathrooms      smallint default null,
  p_min_surface        numeric default null,
  p_max_surface        numeric default null,
  p_amenities          text[] default null,
  p_commercial_statuses public.commercial_status[] default null,
  p_featured_only      boolean default false,
  p_furnished          boolean default null,
  p_sort               text default 'newest'
)
returns setof public.public_properties
language plpgsql
stable
set search_path = ''
as $$
declare
  v_query tsquery;
  v_query_en tsquery;
begin
  if p_sort not in ('relevance', 'newest', 'oldest', 'price_asc', 'price_desc', 'surface_desc', 'featured') then
    raise exception 'Tri invalide : %', p_sort using errcode = '22023';
  end if;
  if p_min_price is not null and p_max_price is not null and p_min_price > p_max_price then
    raise exception 'Le budget minimum dépasse le budget maximum.' using errcode = '22023';
  end if;
  if nullif(btrim(p_query), '') is not null then
    v_query := websearch_to_tsquery('public.french_unaccent', left(p_query, 200));
    v_query_en := websearch_to_tsquery('public.english_unaccent', left(p_query, 200));
  end if;

  return query
  select pp.*
  from public.public_properties pp
  where (v_query is null or pp.search_vector @@ v_query or pp.search_vector_en @@ v_query_en)
    and (p_transaction_type is null or pp.transaction_type = p_transaction_type)
    and (p_property_types is null or pp.property_type = any (p_property_types))
    and (p_region_id is null or pp.region_id = p_region_id)
    and (p_city_id is null or pp.city_id = p_city_id)
    and (p_commune_id is null or pp.commune_id = p_commune_id)
    and (p_neighborhood_id is null or pp.neighborhood_id = p_neighborhood_id)
    and (p_min_price is null or pp.price_amount >= p_min_price)
    and (p_max_price is null or pp.price_amount <= p_max_price)
    and (p_min_bedrooms is null or pp.bedrooms >= p_min_bedrooms)
    and (p_min_bathrooms is null or pp.bathrooms >= p_min_bathrooms)
    and (p_min_surface is null or pp.surface_area >= p_min_surface)
    and (p_max_surface is null or pp.surface_area <= p_max_surface)
    and (p_amenities is null or pp.amenity_codes @> p_amenities)
    and (p_commercial_statuses is null or pp.commercial_status = any (p_commercial_statuses))
    and (not coalesce(p_featured_only, false) or pp.is_featured)
    and (p_furnished is null or pp.is_furnished = p_furnished)
  order by
    case when p_sort = 'relevance' and v_query is not null
         then greatest(ts_rank(pp.search_vector, v_query), ts_rank(pp.search_vector_en, v_query_en)) end desc nulls last,
    case when p_sort = 'featured' then pp.is_featured end desc,
    case when p_sort = 'featured' then pp.featured_rank end desc,
    case when p_sort = 'price_asc' then pp.price_amount end asc nulls last,
    case when p_sort = 'price_desc' then pp.price_amount end desc nulls last,
    case when p_sort = 'surface_desc' then pp.surface_area end desc nulls last,
    case when p_sort = 'oldest' then pp.published_at end asc,
    pp.published_at desc,
    pp.id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Détail : libellés anglais des équipements ; vecteurs exclus de la réponse.
-- -----------------------------------------------------------------------------
create or replace function public.get_public_property(p_slug text default null, p_reference text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(pp) - 'search_vector' - 'search_vector_en'
    || jsonb_build_object(
      'images', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'storage_path', m.storage_path, 'alt_text', m.alt_text,
                 'sort_order', m.sort_order, 'is_cover', m.is_cover, 'width', m.width, 'height', m.height)
               order by m.is_cover desc, m.sort_order, m.id)
        from public.public_property_media m where m.property_id = pp.id), '[]'::jsonb),
      'amenities', coalesce((
        select jsonb_agg(jsonb_build_object('code', am.code, 'label', am.label, 'label_en', am.label_en,
                                            'category', am.category, 'icon', am.icon)
               order by am.sort_order)
        from public.amenities am where am.code = any (pp.amenity_codes) and am.is_active), '[]'::jsonb),
      'features', coalesce((
        select jsonb_agg(jsonb_build_object('label', f.label, 'value', f.value) order by f.sort_order, f.label)
        from public.property_features f where f.property_id = pp.id), '[]'::jsonb)
    )
  from public.public_properties pp
  where (p_slug is not null and pp.slug = p_slug)
     or (p_reference is not null and pp.reference = upper(p_reference))
  limit 1;
$$;

-- -----------------------------------------------------------------------------
-- Filtres : libellés anglais des types de biens.
-- -----------------------------------------------------------------------------
create or replace function public.get_public_filters()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'transaction_types', coalesce((
      select jsonb_agg(jsonb_build_object('value', t.transaction_type, 'count', t.n) order by t.transaction_type)
      from (select transaction_type, count(*) n from public.public_properties group by 1) t), '[]'::jsonb),
    'property_types', coalesce((
      select jsonb_agg(jsonb_build_object('code', pt.code, 'label', pt.label, 'label_plural', pt.label_plural,
                                          'label_en', pt.label_en, 'label_plural_en', pt.label_plural_en,
                                          'count', coalesce(c.n, 0)) order by pt.sort_order)
      from public.property_types pt
      left join (select property_type, count(*) n from public.public_properties group by 1) c on c.property_type = pt.code
      where pt.is_active), '[]'::jsonb),
    'cities', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.city_id, 'name', c.city_name, 'slug', c.city_slug,
                                          'region_name', c.region_name, 'count', c.n) order by c.n desc, c.city_name)
      from (select city_id, city_name, city_slug, region_name, count(*) n
              from public.public_properties where city_id is not null group by 1, 2, 3, 4) c), '[]'::jsonb),
    'neighborhoods', coalesce((
      select jsonb_agg(jsonb_build_object('id', n.neighborhood_id, 'name', n.neighborhood_name, 'slug', n.neighborhood_slug,
                                          'city_id', n.city_id, 'count', n.n) order by n.n desc, n.neighborhood_name)
      from (select neighborhood_id, neighborhood_name, neighborhood_slug, city_id, count(*) n
              from public.public_properties where neighborhood_id is not null group by 1, 2, 3, 4) n), '[]'::jsonb),
    'price_ranges', coalesce((
      select jsonb_object_agg(r.transaction_type, jsonb_build_object('min', r.min_price, 'max', r.max_price))
      from (select transaction_type, min(price_amount) min_price, max(price_amount) max_price
              from public.public_properties where price_amount is not null group by 1) r), '{}'::jsonb)
  );
$$;
