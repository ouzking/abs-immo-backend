-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0500 : prospects, demandes, visites, suivi
-- -----------------------------------------------------------------------------
--   leads (personne / prospect, dédoublonné par e-mail ou téléphone)
--     ├─< inquiries         (demandes de renseignement)
--     ├─< viewing_requests  (demandes de visite)
--     └─< lead_activities   (historique + notes internes)
--
-- Aucune de ces tables n'est accessible à `anon`. Les formulaires publics
-- passent par les Edge Functions submit-inquiry / submit-viewing-request, qui
-- appellent `submit_inquiry` / `submit_viewing_request` avec la clé service_role
-- après validation, anti-robot et limitation de débit.
-- =============================================================================

create type public.lead_status       as enum ('new', 'contacted', 'qualified', 'visit_scheduled', 'negotiation', 'won', 'lost');
create type public.lead_source       as enum ('website', 'whatsapp', 'phone', 'email', 'walk_in', 'facebook', 'instagram', 'referral', 'partner', 'other');
create type public.contact_method    as enum ('phone', 'whatsapp', 'email');
create type public.inquiry_type      as enum ('general', 'property_info', 'price', 'availability', 'sell_property', 'rent_out_property', 'other');
create type public.inquiry_status    as enum ('new', 'in_progress', 'answered', 'closed', 'spam');
create type public.viewing_status    as enum ('requested', 'confirmed', 'completed', 'cancelled', 'no_show');
create type public.time_slot         as enum ('morning', 'afternoon', 'evening', 'any');
create type public.lead_activity_type as enum (
  'note', 'call', 'email', 'whatsapp', 'sms', 'meeting', 'visit',          -- saisies manuelles
  'status_change', 'assignment', 'inquiry_received', 'viewing_requested', 'system'  -- système
);

-- -----------------------------------------------------------------------------
-- Prospects
-- -----------------------------------------------------------------------------
create table public.leads (
  id                      uuid primary key default gen_random_uuid(),
  full_name               text not null check (char_length(full_name) between 2 and 120),
  email                   text check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 254)),
  phone                   text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp_phone          text check (whatsapp_phone is null or whatsapp_phone ~ '^\+[1-9][0-9]{7,14}$'),
  preferred_contact       public.contact_method,
  source                  public.lead_source not null default 'website',
  status                  public.lead_status not null default 'new',
  assigned_agent_id       uuid references public.agents (profile_id) on delete set null,
  budget_min              bigint check (budget_min >= 0),
  budget_max              bigint check (budget_max >= 0),
  desired_transaction     public.transaction_type,
  desired_property_type   text references public.property_types (code) on update cascade on delete set null,
  desired_locality_id     uuid references public.localities (id) on delete set null,
  consent_marketing       boolean not null default false,
  consent_at              timestamptz,
  lost_reason             text check (char_length(lost_reason) <= 500),
  last_activity_at        timestamptz not null default now(),
  created_by              uuid references public.profiles (id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint leads_contact_required check (email is not null or phone is not null),
  constraint leads_budget_range check (budget_min is null or budget_max is null or budget_min <= budget_max)
);
comment on table public.leads is 'Prospects (personnes). Dédoublonnés par e-mail / téléphone lors des soumissions publiques.';

create index leads_email_idx on public.leads (email) where email is not null;
create index leads_phone_idx on public.leads (phone) where phone is not null;
create index leads_assigned_idx on public.leads (assigned_agent_id, status);
create index leads_status_idx on public.leads (status, last_activity_at desc);
create index leads_created_idx on public.leads (created_at desc);
create index leads_name_trgm_idx on public.leads using gin (full_name extensions.gin_trgm_ops);
alter table public.leads enable row level security;

-- -----------------------------------------------------------------------------
-- Demandes de renseignement
-- -----------------------------------------------------------------------------
create table public.inquiries (
  id                uuid primary key default gen_random_uuid(),
  lead_id           uuid not null references public.leads (id) on delete cascade,
  property_id       uuid references public.properties (id) on delete set null,
  inquiry_type      public.inquiry_type not null default 'general',
  channel           public.lead_source not null default 'website',
  message           text check (char_length(message) <= 5000),
  status            public.inquiry_status not null default 'new',
  assigned_agent_id uuid references public.agents (profile_id) on delete set null,
  answered_at       timestamptz,
  closed_at         timestamptz,
  submission_meta   jsonb not null default '{}'::jsonb,   -- ip_hash, user_agent, page_url, utm (aucune IP en clair)
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index inquiries_lead_idx on public.inquiries (lead_id, created_at desc);
create index inquiries_property_idx on public.inquiries (property_id);
create index inquiries_assigned_idx on public.inquiries (assigned_agent_id, status);
create index inquiries_status_idx on public.inquiries (status, created_at desc);
create index inquiries_created_idx on public.inquiries (created_at desc);
alter table public.inquiries enable row level security;

-- -----------------------------------------------------------------------------
-- Demandes de visite
-- -----------------------------------------------------------------------------
create table public.viewing_requests (
  id                  uuid primary key default gen_random_uuid(),
  lead_id             uuid not null references public.leads (id) on delete cascade,
  property_id         uuid references public.properties (id) on delete set null,
  preferred_date      date,
  preferred_time_slot public.time_slot not null default 'any',
  alternative_date    date,
  message             text check (char_length(message) <= 2000),
  status              public.viewing_status not null default 'requested',
  scheduled_at        timestamptz,
  assigned_agent_id   uuid references public.agents (profile_id) on delete set null,
  completed_at        timestamptz,
  outcome_notes       text check (char_length(outcome_notes) <= 5000),   -- interne
  cancellation_reason text check (char_length(cancellation_reason) <= 500),
  submission_meta     jsonb not null default '{}'::jsonb,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint viewing_confirmed_requires_schedule check (status not in ('confirmed', 'completed') or scheduled_at is not null)
);
create index viewing_requests_lead_idx on public.viewing_requests (lead_id, created_at desc);
create index viewing_requests_property_idx on public.viewing_requests (property_id);
create index viewing_requests_assigned_idx on public.viewing_requests (assigned_agent_id, status);
create index viewing_requests_status_idx on public.viewing_requests (status, created_at desc);
create index viewing_requests_scheduled_idx on public.viewing_requests (scheduled_at) where status = 'confirmed';
alter table public.viewing_requests enable row level security;

-- -----------------------------------------------------------------------------
-- Historique commercial et notes internes
-- -----------------------------------------------------------------------------
create table public.lead_activities (
  id                 uuid primary key default gen_random_uuid(),
  lead_id            uuid not null references public.leads (id) on delete cascade,
  inquiry_id         uuid references public.inquiries (id) on delete set null,
  viewing_request_id uuid references public.viewing_requests (id) on delete set null,
  actor_id           uuid references public.profiles (id) on delete set null,
  activity_type      public.lead_activity_type not null,
  content            text check (char_length(content) <= 10000),
  metadata           jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);
create index lead_activities_lead_idx on public.lead_activities (lead_id, created_at desc);
create index lead_activities_actor_idx on public.lead_activities (actor_id, created_at desc);
alter table public.lead_activities enable row level security;

-- -----------------------------------------------------------------------------
-- Limitation de débit (schéma privé, jamais exposé)
-- -----------------------------------------------------------------------------
create table private.rate_limit_events (
  id         bigint generated always as identity primary key,
  scope      text not null,
  key_hash   text not null,
  created_at timestamptz not null default now()
);
create index rate_limit_events_lookup_idx on private.rate_limit_events (scope, key_hash, created_at desc);

-- Enregistre un événement et renvoie false si la limite est dépassée.
create or replace function private.hit_rate_limit(p_scope text, p_key text, p_max integer, p_window interval)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_key is null or p_key = '' then
    return true;
  end if;
  -- Nettoyage opportuniste des événements anciens.
  if random() < 0.02 then
    delete from private.rate_limit_events where created_at < now() - interval '2 days';
  end if;
  select count(*) into v_count from private.rate_limit_events
   where scope = p_scope and key_hash = p_key and created_at > now() - p_window;
  if v_count >= p_max then
    return false;
  end if;
  insert into private.rate_limit_events (scope, key_hash) values (p_scope, p_key);
  return true;
end;
$$;

-- =============================================================================
-- Autorisations sur les prospects
-- =============================================================================

-- Accès à un prospect : leads.read_all, ou prospect affecté, ou une de ses
-- demandes/visites affectée à l'utilisateur courant.
create or replace function private.can_access_lead(p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('leads.read_all')
      or (private.has_permission('leads.access_assigned') and (
            exists (select 1 from public.leads l where l.id = p_lead_id and l.assigned_agent_id = auth.uid())
         or exists (select 1 from public.inquiries i where i.lead_id = p_lead_id and i.assigned_agent_id = auth.uid())
         or exists (select 1 from public.viewing_requests v where v.lead_id = p_lead_id and v.assigned_agent_id = auth.uid())));
$$;

-- Accès à une demande/visite : read_all, ou affectée à moi, ou prospect affecté à moi.
create or replace function private.can_access_request(p_assigned uuid, p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('leads.read_all')
      or (private.has_permission('leads.access_assigned') and (
            p_assigned = auth.uid()
         or exists (select 1 from public.leads l where l.id = p_lead_id and l.assigned_agent_id = auth.uid())));
$$;

grant execute on function private.can_access_lead(uuid), private.can_access_request(uuid, uuid) to authenticated;

create or replace function private.is_assignable_agent(p_agent_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_agent_id is null or exists (
    select 1 from public.agents a join public.profiles p on p.id = a.profile_id
     where a.profile_id = p_agent_id and a.is_active and p.is_active);
$$;

-- =============================================================================
-- Garde-fous et automatisations
-- =============================================================================
create or replace function private.leads_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.email := nullif(lower(btrim(new.email)), '');
  if new.phone is not null then new.phone := coalesce(private.normalize_phone(new.phone), new.phone); end if;
  if new.whatsapp_phone is not null then new.whatsapp_phone := coalesce(private.normalize_phone(new.whatsapp_phone), new.whatsapp_phone); end if;

  if (tg_op = 'INSERT' or new.assigned_agent_id is distinct from old.assigned_agent_id)
     and not private.is_assignable_agent(new.assigned_agent_id) then
    raise exception 'Le prospect doit être affecté à un agent actif.' using errcode = '23514';
  end if;
  if new.consent_marketing and (tg_op = 'INSERT' or not old.consent_marketing) then
    new.consent_at := now();
  end if;

  if private.is_trusted_writer() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    if not private.has_permission('leads.assign') then
      if new.assigned_agent_id is null and private.is_assignable_agent(auth.uid())
         and exists (select 1 from public.agents where profile_id = auth.uid()) then
        new.assigned_agent_id := auth.uid();
      elsif new.assigned_agent_id is distinct from auth.uid() then
        raise exception 'Permission leads.assign requise pour affecter un prospect à un autre agent.' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if new.assigned_agent_id is distinct from old.assigned_agent_id and not private.has_permission('leads.assign') then
    raise exception 'Permission leads.assign requise pour réaffecter un prospect.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'Colonne non modifiable.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger leads_guard
  before insert or update on public.leads
  for each row execute function private.leads_guard();

create trigger leads_set_updated_at
  before update on public.leads
  for each row execute function private.set_updated_at();

-- Garde-fou commun aux demandes et visites.
create or replace function private.lead_requests_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' or new.assigned_agent_id is distinct from old.assigned_agent_id)
     and not private.is_assignable_agent(new.assigned_agent_id) then
    raise exception 'La demande doit être affectée à un agent actif.' using errcode = '23514';
  end if;

  -- Horodatages de traitement
  if tg_table_name = 'inquiries' then
    if new.status::text = 'answered' and (tg_op = 'INSERT' or old.status::text <> 'answered') then
      new.answered_at := coalesce(new.answered_at, now());
    end if;
    if new.status::text in ('closed', 'spam') and (tg_op = 'INSERT' or old.status::text not in ('closed', 'spam')) then
      new.closed_at := now();
    end if;
  else
    if new.status::text = 'completed' and (tg_op = 'INSERT' or old.status::text <> 'completed') then
      new.completed_at := coalesce(new.completed_at, now());
    end if;
  end if;

  if private.is_trusted_writer() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.submission_meta := jsonb_build_object('entered_manually', true);
    if not private.has_permission('leads.assign') and new.assigned_agent_id is distinct from auth.uid() then
      if new.assigned_agent_id is null then
        new.assigned_agent_id := case when private.is_assignable_agent(auth.uid())
                                       and exists (select 1 from public.agents where profile_id = auth.uid())
                                      then auth.uid() end;
      else
        raise exception 'Permission leads.assign requise pour affecter une demande à un autre agent.' using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if new.assigned_agent_id is distinct from old.assigned_agent_id and not private.has_permission('leads.assign') then
    raise exception 'Permission leads.assign requise pour réaffecter une demande.' using errcode = '42501';
  end if;
  if new.lead_id is distinct from old.lead_id or new.submission_meta is distinct from old.submission_meta
     or new.created_at is distinct from old.created_at or new.created_by is distinct from old.created_by then
    raise exception 'Colonne non modifiable.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger inquiries_guard
  before insert or update on public.inquiries
  for each row execute function private.lead_requests_guard();
create trigger viewing_requests_guard
  before insert or update on public.viewing_requests
  for each row execute function private.lead_requests_guard();
create trigger inquiries_set_updated_at
  before update on public.inquiries
  for each row execute function private.set_updated_at();
create trigger viewing_requests_set_updated_at
  before update on public.viewing_requests
  for each row execute function private.set_updated_at();

-- Historique automatique : création de demandes, changements de statut et affectations.
create or replace function private.log_lead_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lead uuid;
  v_inquiry uuid;
  v_viewing uuid;
begin
  if tg_table_name = 'leads' then
    v_lead := new.id;
  else
    v_lead := new.lead_id;
    if tg_table_name = 'inquiries' then v_inquiry := new.id; else v_viewing := new.id; end if;
  end if;

  if tg_op = 'INSERT' then
    if tg_table_name = 'inquiries' then
      insert into public.lead_activities (lead_id, inquiry_id, actor_id, activity_type, content, metadata)
      values (v_lead, v_inquiry, auth.uid(), 'inquiry_received', new.message,
              jsonb_build_object('property_id', new.property_id, 'inquiry_type', new.inquiry_type, 'channel', new.channel));
    elsif tg_table_name = 'viewing_requests' then
      insert into public.lead_activities (lead_id, viewing_request_id, actor_id, activity_type, content, metadata)
      values (v_lead, v_viewing, auth.uid(), 'viewing_requested', new.message,
              jsonb_build_object('property_id', new.property_id, 'preferred_date', new.preferred_date,
                                 'preferred_time_slot', new.preferred_time_slot));
    end if;
    return null;
  end if;

  if new.status is distinct from old.status then
    insert into public.lead_activities (lead_id, inquiry_id, viewing_request_id, actor_id, activity_type, metadata)
    values (v_lead, v_inquiry, v_viewing, auth.uid(), 'status_change',
            jsonb_build_object('entity', tg_table_name, 'from', old.status, 'to', new.status));
  end if;
  if new.assigned_agent_id is distinct from old.assigned_agent_id then
    insert into public.lead_activities (lead_id, inquiry_id, viewing_request_id, actor_id, activity_type, metadata)
    values (v_lead, v_inquiry, v_viewing, auth.uid(), 'assignment',
            jsonb_build_object('entity', tg_table_name, 'from', old.assigned_agent_id, 'to', new.assigned_agent_id));
  end if;

  -- Une visite confirmée fait progresser le prospect.
  -- (comparaison en texte : NEW peut être une ligne d'une autre table/enum)
  if tg_table_name = 'viewing_requests' then
    if new.status::text = 'confirmed' and old.status::text <> 'confirmed' then
      update public.leads set status = 'visit_scheduled'
       where id = v_lead and status in ('new', 'contacted', 'qualified');
    end if;
  end if;
  return null;
end;
$$;

create trigger leads_log_events
  after update on public.leads
  for each row execute function private.log_lead_events();
create trigger inquiries_log_events
  after insert or update on public.inquiries
  for each row execute function private.log_lead_events();
create trigger viewing_requests_log_events
  after insert or update on public.viewing_requests
  for each row execute function private.log_lead_events();

-- Activités : contrôle de saisie et mise à jour de last_activity_at.
create or replace function private.lead_activities_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_writer() then
    return new;    -- activité système (déclencheur ou fonction du backend)
  end if;
  if new.activity_type not in ('note', 'call', 'email', 'whatsapp', 'sms', 'meeting', 'visit') then
    raise exception 'Type d''activité réservé au système : %', new.activity_type using errcode = '42501';
  end if;
  new.actor_id := auth.uid();
  new.created_at := now();
  return new;
end;
$$;

create trigger lead_activities_guard
  before insert on public.lead_activities
  for each row execute function private.lead_activities_guard();

create or replace function private.touch_lead_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.leads set last_activity_at = new.created_at where id = new.lead_id and last_activity_at < new.created_at;
  return null;
end;
$$;

create trigger lead_activities_touch_lead
  after insert on public.lead_activities
  for each row execute function private.touch_lead_activity();

create trigger leads_audit
  after update or delete on public.leads
  for each row execute function private.audit_trigger('status,assigned_agent_id,email,phone,full_name');

-- =============================================================================
-- Politiques RLS (aucune pour anon)
-- =============================================================================
create policy leads_select on public.leads
  for select to authenticated
  using ((select private.has_permission('leads.read_all'))
         or ((select private.has_permission('leads.access_assigned')) and assigned_agent_id = (select auth.uid()))
         or private.can_access_lead(id));
create policy leads_insert on public.leads
  for insert to authenticated with check ((select private.has_permission('leads.create')));
create policy leads_update on public.leads
  for update to authenticated
  using ((select private.has_permission('leads.update_all'))
         or ((select private.has_permission('leads.access_assigned')) and assigned_agent_id = (select auth.uid())))
  with check ((select private.has_permission('leads.update_all'))
              or ((select private.has_permission('leads.access_assigned')) and assigned_agent_id = (select auth.uid()))
              or (select private.has_permission('leads.assign')));
create policy leads_delete on public.leads
  for delete to authenticated using ((select private.has_permission('leads.delete')));

create policy inquiries_select on public.inquiries
  for select to authenticated using (private.can_access_request(assigned_agent_id, lead_id));
create policy inquiries_insert on public.inquiries
  for insert to authenticated
  with check ((select private.has_permission('leads.create')) and private.can_access_lead(lead_id));
create policy inquiries_update on public.inquiries
  for update to authenticated
  using ((select private.has_permission('leads.update_all'))
         or ((select private.has_permission('leads.access_assigned')) and private.can_access_request(assigned_agent_id, lead_id)))
  with check ((select private.has_permission('leads.update_all'))
              or (select private.has_permission('leads.assign'))
              or ((select private.has_permission('leads.access_assigned')) and private.can_access_request(assigned_agent_id, lead_id)));
create policy inquiries_delete on public.inquiries
  for delete to authenticated using ((select private.has_permission('leads.delete')));

create policy viewing_requests_select on public.viewing_requests
  for select to authenticated using (private.can_access_request(assigned_agent_id, lead_id));
create policy viewing_requests_insert on public.viewing_requests
  for insert to authenticated
  with check ((select private.has_permission('leads.create')) and private.can_access_lead(lead_id));
create policy viewing_requests_update on public.viewing_requests
  for update to authenticated
  using ((select private.has_permission('leads.update_all'))
         or ((select private.has_permission('leads.access_assigned')) and private.can_access_request(assigned_agent_id, lead_id)))
  with check ((select private.has_permission('leads.update_all'))
              or (select private.has_permission('leads.assign'))
              or ((select private.has_permission('leads.access_assigned')) and private.can_access_request(assigned_agent_id, lead_id)));
create policy viewing_requests_delete on public.viewing_requests
  for delete to authenticated using ((select private.has_permission('leads.delete')));

create policy lead_activities_select on public.lead_activities
  for select to authenticated using (private.can_access_lead(lead_id));
create policy lead_activities_insert on public.lead_activities
  for insert to authenticated with check (private.can_access_lead(lead_id));
create policy lead_activities_delete on public.lead_activities
  for delete to authenticated using ((select private.has_permission('leads.delete')));

-- =============================================================================
-- Soumissions publiques (appelées UNIQUEMENT par les Edge Functions, service_role)
-- Codes d'erreur personnalisés :
--   AB422 : données invalides       AB404 : bien indisponible
--   AB429 : trop de soumissions
-- =============================================================================

-- Retrouve ou crée le prospect correspondant aux coordonnées.
create or replace function private.find_or_create_public_lead(
  p_full_name text, p_email text, p_phone text, p_preferred_contact public.contact_method,
  p_consent_marketing boolean, p_agent_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lead public.leads;
begin
  select * into v_lead from public.leads
   where (p_email is not null and email = p_email) or (p_phone is not null and phone = p_phone)
   order by updated_at desc
   limit 1
   for update;

  if v_lead.id is null then
    insert into public.leads (full_name, email, phone, whatsapp_phone, preferred_contact, source,
                              assigned_agent_id, consent_marketing)
    values (p_full_name, p_email, p_phone,
            case when p_preferred_contact = 'whatsapp' then p_phone end,
            p_preferred_contact, 'website', p_agent_id, coalesce(p_consent_marketing, false))
    returning * into v_lead;
  else
    update public.leads
       set email = coalesce(email, p_email),
           phone = coalesce(phone, p_phone),
           whatsapp_phone = coalesce(whatsapp_phone, case when p_preferred_contact = 'whatsapp' then p_phone end),
           preferred_contact = coalesce(p_preferred_contact, preferred_contact),
           consent_marketing = consent_marketing or coalesce(p_consent_marketing, false),
           assigned_agent_id = coalesce(assigned_agent_id, p_agent_id),
           status = case when status = 'lost' then 'new'::public.lead_status else status end
     where id = v_lead.id;
  end if;
  return v_lead.id;
end;
$$;

-- Contrôles communs : format des coordonnées, limitation de débit.
create or replace function private.validate_public_submission(
  inout p_full_name text, inout p_email text, inout p_phone text, p_ip_hash text, p_scope text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  p_full_name := btrim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  p_email := nullif(lower(btrim(coalesce(p_email, ''))), '');
  p_phone := private.normalize_phone(p_phone);

  if char_length(p_full_name) < 2 or char_length(p_full_name) > 120 then
    raise exception 'Nom invalide.' using errcode = 'AB422', hint = 'full_name';
  end if;
  if p_email is not null and (p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(p_email) > 254) then
    raise exception 'Adresse e-mail invalide.' using errcode = 'AB422', hint = 'email';
  end if;
  if p_email is null and p_phone is null then
    raise exception 'Un e-mail ou un numéro de téléphone valide est requis.' using errcode = 'AB422', hint = 'contact';
  end if;

  -- Limites : par empreinte IP et par coordonnée (configurables dans app_settings).
  if not private.hit_rate_limit(p_scope || ':ip:10m', p_ip_hash, private.setting_int('rate_limit.per_ip_10min', 5), interval '10 minutes')
     or not private.hit_rate_limit(p_scope || ':ip:1d', p_ip_hash, private.setting_int('rate_limit.per_ip_day', 30), interval '1 day')
     or not private.hit_rate_limit(p_scope || ':contact:1d',
                                   encode(extensions.digest(coalesce(p_email, '') || '|' || coalesce(p_phone, ''), 'sha256'), 'hex'),
                                   private.setting_int('rate_limit.per_contact_day', 10), interval '1 day') then
    raise exception 'Trop de demandes. Veuillez réessayer plus tard.' using errcode = 'AB429';
  end if;
end;
$$;

create or replace function public.submit_inquiry(
  p_full_name text,
  p_email text default null,
  p_phone text default null,
  p_message text default null,
  p_property_id uuid default null,
  p_inquiry_type public.inquiry_type default 'general',
  p_preferred_contact public.contact_method default null,
  p_consent_marketing boolean default false,
  p_ip_hash text default null,
  p_submission_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_property public.properties;
  v_agent uuid;
  v_lead_id uuid;
  v_existing uuid;
  v_inquiry_id uuid;
  v_message text := nullif(btrim(coalesce(p_message, '')), '');
begin
  select * into p_full_name, p_email, p_phone
    from private.validate_public_submission(p_full_name, p_email, p_phone, p_ip_hash, 'inquiry');

  if v_message is not null and char_length(v_message) > 5000 then
    raise exception 'Message trop long.' using errcode = 'AB422', hint = 'message';
  end if;

  if p_property_id is not null then
    select * into v_property from public.properties where id = p_property_id and publication_status = 'published';
    if v_property.id is null then
      raise exception 'Bien introuvable ou non publié.' using errcode = 'AB404';
    end if;
    if private.setting_bool('leads.auto_assign_to_property_agent', true)
       and private.is_assignable_agent(v_property.agent_id) then
      v_agent := v_property.agent_id;
    end if;
  end if;

  v_lead_id := private.find_or_create_public_lead(p_full_name, p_email, p_phone, p_preferred_contact,
                                                  p_consent_marketing, v_agent);

  -- Doublon : même prospect, même bien, même type, < 24 h, non clôturé.
  select id into v_existing from public.inquiries
   where lead_id = v_lead_id
     and property_id is not distinct from p_property_id
     and inquiry_type = p_inquiry_type
     and status not in ('closed', 'spam')
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;

  if v_existing is not null then
    if v_message is not null then
      insert into public.lead_activities (lead_id, inquiry_id, activity_type, content, metadata)
      values (v_lead_id, v_existing, 'system', v_message, jsonb_build_object('reason', 'duplicate_submission'));
    end if;
    return jsonb_build_object('inquiry_id', v_existing, 'lead_id', v_lead_id, 'duplicate', true);
  end if;

  insert into public.inquiries (lead_id, property_id, inquiry_type, channel, message, assigned_agent_id, submission_meta)
  values (v_lead_id, p_property_id, p_inquiry_type, 'website', v_message,
          coalesce(v_agent, (select assigned_agent_id from public.leads where id = v_lead_id)),
          coalesce(p_submission_meta, '{}'::jsonb) || jsonb_build_object('ip_hash', p_ip_hash))
  returning id into v_inquiry_id;

  return jsonb_build_object('inquiry_id', v_inquiry_id, 'lead_id', v_lead_id, 'duplicate', false);
end;
$$;

create or replace function public.submit_viewing_request(
  p_full_name text,
  p_property_id uuid,
  p_email text default null,
  p_phone text default null,
  p_preferred_date date default null,
  p_preferred_time_slot public.time_slot default 'any',
  p_alternative_date date default null,
  p_message text default null,
  p_preferred_contact public.contact_method default null,
  p_consent_marketing boolean default false,
  p_ip_hash text default null,
  p_submission_meta jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_property public.properties;
  v_agent uuid;
  v_lead_id uuid;
  v_existing uuid;
  v_viewing_id uuid;
  v_message text := nullif(btrim(coalesce(p_message, '')), '');
  v_today date := (now() at time zone 'Africa/Dakar')::date;
begin
  select * into p_full_name, p_email, p_phone
    from private.validate_public_submission(p_full_name, p_email, p_phone, p_ip_hash, 'viewing');

  if p_phone is null then
    raise exception 'Un numéro de téléphone est requis pour organiser une visite.' using errcode = 'AB422', hint = 'phone';
  end if;
  if v_message is not null and char_length(v_message) > 2000 then
    raise exception 'Message trop long.' using errcode = 'AB422', hint = 'message';
  end if;
  if p_preferred_date is not null and (p_preferred_date < v_today or p_preferred_date > v_today + 120) then
    raise exception 'La date souhaitée doit être comprise entre aujourd''hui et 120 jours.' using errcode = 'AB422', hint = 'preferred_date';
  end if;
  if p_alternative_date is not null and (p_alternative_date < v_today or p_alternative_date > v_today + 120) then
    raise exception 'La date alternative doit être comprise entre aujourd''hui et 120 jours.' using errcode = 'AB422', hint = 'alternative_date';
  end if;

  select * into v_property from public.properties
   where id = p_property_id and publication_status = 'published' and commercial_status in ('available', 'reserved');
  if v_property.id is null then
    raise exception 'Ce bien n''est pas disponible à la visite.' using errcode = 'AB404';
  end if;
  if private.setting_bool('leads.auto_assign_to_property_agent', true)
     and private.is_assignable_agent(v_property.agent_id) then
    v_agent := v_property.agent_id;
  end if;

  v_lead_id := private.find_or_create_public_lead(p_full_name, p_email, p_phone, p_preferred_contact,
                                                  p_consent_marketing, v_agent);

  -- Doublon : une demande de visite ouverte existe déjà pour ce prospect et ce bien.
  select id into v_existing from public.viewing_requests
   where lead_id = v_lead_id and property_id = p_property_id and status in ('requested', 'confirmed')
   order by created_at desc limit 1;

  if v_existing is not null then
    insert into public.lead_activities (lead_id, viewing_request_id, activity_type, content, metadata)
    values (v_lead_id, v_existing, 'system', v_message,
            jsonb_build_object('reason', 'duplicate_submission', 'preferred_date', p_preferred_date,
                               'preferred_time_slot', p_preferred_time_slot));
    return jsonb_build_object('viewing_request_id', v_existing, 'lead_id', v_lead_id, 'duplicate', true);
  end if;

  insert into public.viewing_requests (lead_id, property_id, preferred_date, preferred_time_slot, alternative_date,
                                       message, assigned_agent_id, submission_meta)
  values (v_lead_id, p_property_id, p_preferred_date, coalesce(p_preferred_time_slot, 'any'), p_alternative_date,
          v_message, coalesce(v_agent, (select assigned_agent_id from public.leads where id = v_lead_id)),
          coalesce(p_submission_meta, '{}'::jsonb) || jsonb_build_object('ip_hash', p_ip_hash))
  returning id into v_viewing_id;

  return jsonb_build_object('viewing_request_id', v_viewing_id, 'lead_id', v_lead_id, 'duplicate', false);
end;
$$;

-- Affectation groupée d'un prospect et de ses demandes ouvertes.
create or replace function public.assign_lead(p_lead_id uuid, p_agent_id uuid, p_include_open_requests boolean default true)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not private.has_permission('leads.assign') then
    raise exception 'Permission leads.assign requise.' using errcode = '42501';
  end if;
  update public.leads set assigned_agent_id = p_agent_id where id = p_lead_id;
  if not found then
    raise exception 'Prospect introuvable.' using errcode = 'P0002';
  end if;
  if p_include_open_requests then
    update public.inquiries set assigned_agent_id = p_agent_id
     where lead_id = p_lead_id and status in ('new', 'in_progress') and assigned_agent_id is distinct from p_agent_id;
    update public.viewing_requests set assigned_agent_id = p_agent_id
     where lead_id = p_lead_id and status in ('requested', 'confirmed') and assigned_agent_id is distinct from p_agent_id;
  end if;
end;
$$;

-- =============================================================================
-- Privilèges
-- =============================================================================
grant select, insert, delete on public.leads to authenticated;
grant update (full_name, email, phone, whatsapp_phone, preferred_contact, source, status, assigned_agent_id,
              budget_min, budget_max, desired_transaction, desired_property_type, desired_locality_id,
              consent_marketing, lost_reason) on public.leads to authenticated;
grant select, insert, delete on public.inquiries to authenticated;
grant update (inquiry_type, status, assigned_agent_id, property_id) on public.inquiries to authenticated;
grant select, insert, delete on public.viewing_requests to authenticated;
grant update (preferred_date, preferred_time_slot, alternative_date, status, scheduled_at, assigned_agent_id,
              outcome_notes, cancellation_reason, property_id) on public.viewing_requests to authenticated;
grant select, insert, delete on public.lead_activities to authenticated;

revoke execute on function public.submit_inquiry(text, text, text, text, uuid, public.inquiry_type, public.contact_method, boolean, text, jsonb) from public, anon, authenticated;
revoke execute on function public.submit_viewing_request(text, uuid, text, text, date, public.time_slot, date, text, public.contact_method, boolean, text, jsonb) from public, anon, authenticated;
grant execute on function public.submit_inquiry(text, text, text, text, uuid, public.inquiry_type, public.contact_method, boolean, text, jsonb) to service_role;
grant execute on function public.submit_viewing_request(text, uuid, text, text, date, public.time_slot, date, text, public.contact_method, boolean, text, jsonb) to service_role;
grant execute on function public.assign_lead(uuid, uuid, boolean) to authenticated;

-- Utilitaires appelés par des déclencheurs SECURITY INVOKER (droits de l'appelant).
grant execute on function private.normalize_phone(text, text), private.is_assignable_agent(uuid) to authenticated;
