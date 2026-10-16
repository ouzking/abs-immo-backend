-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0800 : statistiques
-- -----------------------------------------------------------------------------
-- Toutes les statistiques sont calculées à partir des données réelles.
-- Périmètre :
--   stats.read_all → toute l'agence (et filtre facultatif par agent) ;
--   stats.read_own → uniquement les biens / demandes / prospects de l'appelant.
-- Les définitions précises figurent dans docs/STATISTICS.md.
-- Fuseau : Africa/Dakar (UTC+0, sans heure d'été).
-- =============================================================================

-- Détermine l'agent ciblé par le périmètre (NULL = toute l'agence).
create or replace function private.stats_scope(p_agent_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if private.has_permission('stats.read_all') then
    return p_agent_id;
  elsif private.has_permission('stats.read_own') then
    if p_agent_id is not null and p_agent_id <> auth.uid() then
      raise exception 'Vous ne pouvez consulter que vos propres statistiques.' using errcode = '42501';
    end if;
    return auth.uid();
  end if;
  raise exception 'Permission stats.read_own ou stats.read_all requise.' using errcode = '42501';
end;
$$;

create or replace function public.get_dashboard_stats(
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now(),
  p_agent_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agent uuid;
  v_result jsonb;
begin
  if p_from >= p_to then
    raise exception 'Période invalide : p_from doit précéder p_to.' using errcode = '22023';
  end if;
  v_agent := private.stats_scope(p_agent_id);

  with props as (
    select * from public.properties where v_agent is null or agent_id = v_agent
  ),
  inq as (
    select * from public.inquiries where v_agent is null or assigned_agent_id = v_agent
  ),
  vis as (
    select * from public.viewing_requests where v_agent is null or assigned_agent_id = v_agent
  ),
  lds as (
    select * from public.leads where v_agent is null or assigned_agent_id = v_agent
  )
  select jsonb_build_object(
    'scope', jsonb_build_object('agent_id', v_agent, 'from', p_from, 'to', p_to),
    'properties', jsonb_build_object(
      'total',            (select count(*) from props where publication_status <> 'archived'),
      'archived',         (select count(*) from props where publication_status = 'archived'),
      'draft',            (select count(*) from props where publication_status = 'draft'),
      'pending_review',   (select count(*) from props where publication_status = 'pending_review'),
      'published',        (select count(*) from props where publication_status = 'published'),
      'unpublished',      (select count(*) from props where publication_status = 'unpublished'),
      'available',        (select count(*) from props where commercial_status = 'available' and publication_status <> 'archived'),
      'reserved',         (select count(*) from props where commercial_status = 'reserved' and publication_status <> 'archived'),
      'sold',             (select count(*) from props where commercial_status = 'sold'),
      'rented',           (select count(*) from props where commercial_status = 'rented'),
      'sold_in_period',   (select count(*) from props where commercial_status = 'sold' and status_changed_at >= p_from and status_changed_at < p_to),
      'rented_in_period', (select count(*) from props where commercial_status = 'rented' and status_changed_at >= p_from and status_changed_at < p_to),
      'published_in_period', (select count(*) from props where published_at >= p_from and published_at < p_to),
      'by_type', coalesce((
        select jsonb_agg(jsonb_build_object('property_type', t.property_type, 'transaction_type', t.transaction_type,
                                            'total', t.total, 'published', t.published) order by t.property_type, t.transaction_type)
        from (select property_type, transaction_type, count(*) total,
                     count(*) filter (where publication_status = 'published') published
                from props where publication_status <> 'archived' group by 1, 2) t), '[]'::jsonb),
      'by_transaction', coalesce((
        select jsonb_object_agg(t.transaction_type, t.n)
        from (select transaction_type, count(*) n from props where publication_status <> 'archived' group by 1) t), '{}'::jsonb)
    ),
    'inquiries', jsonb_build_object(
      'received_in_period', (select count(*) from inq where created_at >= p_from and created_at < p_to),
      'pending',            (select count(*) from inq where status = 'new'),
      'in_progress',        (select count(*) from inq where status = 'in_progress'),
      'answered_in_period', (select count(*) from inq where answered_at >= p_from and answered_at < p_to),
      'spam_in_period',     (select count(*) from inq where status = 'spam' and created_at >= p_from and created_at < p_to),
      'median_response_hours', (
        select round((extract(epoch from percentile_cont(0.5) within group (order by answered_at - created_at)) / 3600)::numeric, 1)
        from inq where answered_at is not null and created_at >= p_from and created_at < p_to)
    ),
    'viewings', jsonb_build_object(
      'requested_in_period', (select count(*) from vis where created_at >= p_from and created_at < p_to),
      'pending',             (select count(*) from vis where status = 'requested'),
      'upcoming',            (select count(*) from vis where status = 'confirmed' and scheduled_at >= now()),
      'completed_in_period', (select count(*) from vis where status = 'completed' and completed_at >= p_from and completed_at < p_to)
    ),
    'leads', jsonb_build_object(
      'new_in_period',  (select count(*) from lds where created_at >= p_from and created_at < p_to),
      'open',           (select count(*) from lds where status not in ('won', 'lost')),
      'unassigned',     (select count(*) from lds where assigned_agent_id is null and status not in ('won', 'lost')),
      'by_status', coalesce((select jsonb_object_agg(s.status, s.n)
                               from (select status, count(*) n from lds group by 1) s), '{}'::jsonb)
    )
  ) into v_result;

  return v_result;
end;
$$;

-- Série temporelle des demandes et visites.
create or replace function public.get_inquiry_timeseries(
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now(),
  p_interval text default 'day',
  p_agent_id uuid default null
)
returns table (bucket date, inquiries integer, viewing_requests integer, new_leads integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agent uuid;
  v_step interval;
begin
  if p_interval not in ('day', 'week', 'month') then
    raise exception 'Intervalle invalide : day, week ou month.' using errcode = '22023';
  end if;
  if p_from >= p_to or p_to - p_from > interval '3 years' then
    raise exception 'Période invalide (maximum 3 ans).' using errcode = '22023';
  end if;
  v_agent := private.stats_scope(p_agent_id);
  v_step := ('1 ' || p_interval)::interval;

  return query
  with buckets as (
    select generate_series(date_trunc(p_interval, p_from at time zone 'Africa/Dakar'),
                           date_trunc(p_interval, p_to at time zone 'Africa/Dakar'), v_step)::date as b
  )
  select bk.b,
    (select count(*) from public.inquiries i
      where (v_agent is null or i.assigned_agent_id = v_agent)
        and i.created_at >= p_from and i.created_at < p_to
        and date_trunc(p_interval, i.created_at at time zone 'Africa/Dakar')::date = bk.b)::integer,
    (select count(*) from public.viewing_requests v
      where (v_agent is null or v.assigned_agent_id = v_agent)
        and v.created_at >= p_from and v.created_at < p_to
        and date_trunc(p_interval, v.created_at at time zone 'Africa/Dakar')::date = bk.b)::integer,
    (select count(*) from public.leads l
      where (v_agent is null or l.assigned_agent_id = v_agent)
        and l.created_at >= p_from and l.created_at < p_to
        and date_trunc(p_interval, l.created_at at time zone 'Africa/Dakar')::date = bk.b)::integer
  from buckets bk
  order by bk.b;
end;
$$;

-- Performance commerciale par agent.
create or replace function public.get_agent_performance(
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now()
)
returns table (
  agent_id uuid, display_name text, is_active boolean,
  properties_total integer, properties_published integer,
  sold_in_period integer, rented_in_period integer,
  leads_assigned_open integer, inquiries_received integer, inquiries_answered integer,
  viewings_requested integer, viewings_completed integer, activities_logged integer, leads_won integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_agent uuid;
begin
  if p_from >= p_to then
    raise exception 'Période invalide.' using errcode = '22023';
  end if;
  v_agent := private.stats_scope(null);

  return query
  select a.profile_id, a.display_name, a.is_active,
    (select count(*) from public.properties p where p.agent_id = a.profile_id and p.publication_status <> 'archived')::integer,
    (select count(*) from public.properties p where p.agent_id = a.profile_id and p.publication_status = 'published')::integer,
    (select count(*) from public.properties p where p.agent_id = a.profile_id and p.commercial_status = 'sold'
        and p.status_changed_at >= p_from and p.status_changed_at < p_to)::integer,
    (select count(*) from public.properties p where p.agent_id = a.profile_id and p.commercial_status = 'rented'
        and p.status_changed_at >= p_from and p.status_changed_at < p_to)::integer,
    (select count(*) from public.leads l where l.assigned_agent_id = a.profile_id and l.status not in ('won', 'lost'))::integer,
    (select count(*) from public.inquiries i where i.assigned_agent_id = a.profile_id
        and i.created_at >= p_from and i.created_at < p_to)::integer,
    (select count(*) from public.inquiries i where i.assigned_agent_id = a.profile_id
        and i.answered_at >= p_from and i.answered_at < p_to)::integer,
    (select count(*) from public.viewing_requests v where v.assigned_agent_id = a.profile_id
        and v.created_at >= p_from and v.created_at < p_to)::integer,
    (select count(*) from public.viewing_requests v where v.assigned_agent_id = a.profile_id and v.status = 'completed'
        and v.completed_at >= p_from and v.completed_at < p_to)::integer,
    (select count(*) from public.lead_activities la where la.actor_id = a.profile_id
        and la.activity_type in ('note', 'call', 'email', 'whatsapp', 'sms', 'meeting', 'visit')
        and la.created_at >= p_from and la.created_at < p_to)::integer,
    (select count(distinct la.lead_id) from public.lead_activities la
       join public.leads l on l.id = la.lead_id
      where l.assigned_agent_id = a.profile_id and la.activity_type = 'status_change'
        and la.metadata ->> 'entity' = 'leads' and la.metadata ->> 'to' = 'won'
        and la.created_at >= p_from and la.created_at < p_to)::integer
  from public.agents a
  where v_agent is null or a.profile_id = v_agent
  order by a.display_name;
end;
$$;

grant execute on function
  public.get_dashboard_stats(timestamptz, timestamptz, uuid),
  public.get_inquiry_timeseries(timestamptz, timestamptz, text, uuid),
  public.get_agent_performance(timestamptz, timestamptz)
to authenticated;
