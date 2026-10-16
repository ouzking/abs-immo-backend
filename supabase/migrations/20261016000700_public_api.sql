-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0700 : API publique (site vitrine)
-- -----------------------------------------------------------------------------
-- Choix de conception :
--   Les tables métier ne sont pas lisibles par `anon`. Le site public lit des
--   VUES dédiées qui :
--     * ne renvoient que les annonces `published` ;
--     * n'exposent que les colonnes publiques (jamais internal_notes,
--       created_by, adresse exacte sauf autorisation…) ;
--     * appliquent la règle de confidentialité de localisation.
--   Ces vues s'exécutent avec les droits de leur propriétaire (comportement
--   par défaut, security_invoker = false) : c'est VOLONTAIRE et c'est le seul
--   endroit où le filtrage RLS est remplacé par un filtrage explicite dans la
--   définition de la vue. `security_barrier` empêche les fuites via des
--   prédicats non étanches.
--   L'avertissement « security definer view » du Security Advisor de Supabase
--   est donc attendu pour ces trois vues (voir docs/SECURITY.md).
-- =============================================================================

create view public.public_properties
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
  p.search_vector
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

comment on view public.public_properties is
  'Annonces publiées, colonnes publiques uniquement. Lecture anonyme autorisée. Coordonnées arrondies (~1 km) si location_precision = approximate.';

create view public.public_property_media
with (security_barrier = true)
as
select m.id, m.property_id, m.storage_path, m.alt_text, m.sort_order, m.is_cover, m.width, m.height
from public.property_media m
join public.properties p on p.id = m.property_id
where p.publication_status = 'published';

comment on view public.public_property_media is 'Photos des annonces publiées (chemins du bucket property-images).';

create view public.public_agents
with (security_barrier = true)
as
select a.slug, a.display_name, a.job_title, a.bio, a.public_phone, a.whatsapp_phone, a.public_email,
       a.photo_path, a.languages,
       (select count(*) from public.properties p
         where p.agent_id = a.profile_id and p.publication_status = 'published')::integer as published_property_count
from public.agents a
join public.profiles pr on pr.id = a.profile_id
where a.is_public and a.is_active and pr.is_active;

comment on view public.public_agents is 'Fiches publiques des agents actifs.';

grant select on public.public_properties, public.public_property_media, public.public_agents to anon, authenticated;

-- =============================================================================
-- Recherche d'annonces
-- Utilisation (supabase-js) :
--   supabase.rpc('search_properties', { p_transaction_type: 'sale', p_city_id, ... }, { count: 'exact' })
--           .select('id,slug,title,price_amount,cover_image_path,...')
--           .range(0, 11)
-- Les filtres PostgREST supplémentaires (.eq('city_slug', ...)) restent possibles.
-- =============================================================================
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
begin
  if p_sort not in ('relevance', 'newest', 'oldest', 'price_asc', 'price_desc', 'surface_desc', 'featured') then
    raise exception 'Tri invalide : %', p_sort using errcode = '22023';
  end if;
  if p_min_price is not null and p_max_price is not null and p_min_price > p_max_price then
    raise exception 'Le budget minimum dépasse le budget maximum.' using errcode = '22023';
  end if;
  if nullif(btrim(p_query), '') is not null then
    v_query := websearch_to_tsquery('public.french_unaccent', left(p_query, 200));
  end if;

  return query
  select pp.*
  from public.public_properties pp
  where (v_query is null or pp.search_vector @@ v_query)
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
    case when p_sort = 'relevance' and v_query is not null then ts_rank(pp.search_vector, v_query) end desc nulls last,
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

-- =============================================================================
-- Détail d'une annonce (par slug ou par référence)
-- =============================================================================
-- SECURITY DEFINER : lit property_features (non exposée à anon), mais
-- UNIQUEMENT pour un bien présent dans public_properties (donc publié).
create or replace function public.get_public_property(p_slug text default null, p_reference text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(pp) - 'search_vector'
    || jsonb_build_object(
      'images', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'storage_path', m.storage_path, 'alt_text', m.alt_text,
                 'sort_order', m.sort_order, 'is_cover', m.is_cover, 'width', m.width, 'height', m.height)
               order by m.is_cover desc, m.sort_order, m.id)
        from public.public_property_media m where m.property_id = pp.id), '[]'::jsonb),
      'amenities', coalesce((
        select jsonb_agg(jsonb_build_object('code', am.code, 'label', am.label, 'category', am.category, 'icon', am.icon)
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

-- Annonces similaires (même transaction, même type ou même ville).
create or replace function public.get_similar_properties(p_property_id uuid, p_limit integer default 4)
returns setof public.public_properties
language sql
stable
set search_path = ''
as $$
  select pp.*
  from public.public_properties pp
  join public.public_properties ref on ref.id = p_property_id
  where pp.id <> ref.id
    and pp.transaction_type = ref.transaction_type
    and pp.commercial_status = 'available'
    and (pp.property_type = ref.property_type or pp.city_id = ref.city_id)
  order by (pp.property_type = ref.property_type and pp.city_id = ref.city_id) desc,
           abs(coalesce(pp.price_amount, 0) - coalesce(ref.price_amount, 0)),
           pp.published_at desc
  limit least(greatest(coalesce(p_limit, 4), 1), 12);
$$;

-- =============================================================================
-- Valeurs de filtres disponibles (uniquement ce qui est réellement publié)
-- =============================================================================
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

grant execute on function
  public.search_properties(text, public.transaction_type, text[], uuid, uuid, uuid, uuid, bigint, bigint, smallint,
                           smallint, numeric, numeric, text[], public.commercial_status[], boolean, boolean, text),
  public.get_public_property(text, text),
  public.get_similar_properties(uuid, integer),
  public.get_public_filters()
to anon, authenticated;
