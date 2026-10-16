-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0200 : identité, rôles, permissions, agents
-- -----------------------------------------------------------------------------
-- Modèle RBAC :
--   roles (hiérarchisés par `rank`) ─< role_permissions >─ permissions
--   auth.users ─ profiles ─< user_roles >─ roles
--   profiles ─ agents (fiche commerciale publique facultative)
--
-- La matrice rôles/permissions est une donnée de référence gérée UNIQUEMENT
-- par migration (aucun droit d'écriture via l'API).
-- L'attribution des rôles passe exclusivement par les RPC `assign_role` /
-- `revoke_role`, qui appliquent la règle de rang.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Rôles et permissions (référentiel)
-- -----------------------------------------------------------------------------
create table public.roles (
  code        text primary key check (code ~ '^[a-z_]{2,40}$'),
  label       text not null,
  description text,
  rank        smallint not null unique check (rank between 1 and 1000)
);
comment on table public.roles is 'Rôles applicatifs. Plus le rang est élevé, plus le rôle est privilégié.';

create table public.permissions (
  code        text primary key check (code ~ '^[a-z_]+\.[a-z_]+$'),
  description text not null
);

create table public.role_permissions (
  role_code       text not null references public.roles (code) on delete cascade,
  permission_code text not null references public.permissions (code) on delete cascade,
  primary key (role_code, permission_code)
);
create index role_permissions_permission_idx on public.role_permissions (permission_code);

insert into public.roles (code, label, description, rank) values
  ('super_admin',   'Super administrateur',   'Contrôle total, y compris la gestion des administrateurs et la suppression définitive.', 100),
  ('admin',         'Administrateur',         'Gestion de l''agence, des utilisateurs (rangs inférieurs), du catalogue et des paramètres.', 80),
  ('sales_manager', 'Responsable commercial', 'Publication des annonces, supervision et répartition des prospects, statistiques globales.', 60),
  ('agent',         'Agent immobilier',       'Gestion de ses propres annonces et des prospects qui lui sont affectés.', 40);

insert into public.permissions (code, description) values
  ('properties.read_all',    'Lire toutes les annonces, y compris brouillons et archives'),
  ('properties.create',      'Créer une annonce'),
  ('properties.update_own',  'Modifier les annonces dont on est l''agent responsable'),
  ('properties.update_all',  'Modifier toutes les annonces et changer l''agent responsable'),
  ('properties.publish',     'Publier, retirer, archiver et mettre en avant une annonce'),
  ('properties.delete',      'Supprimer définitivement une annonce'),
  ('leads.access_assigned',  'Accéder aux prospects et demandes qui nous sont affectés'),
  ('leads.read_all',         'Lire tous les prospects et demandes'),
  ('leads.create',           'Saisir manuellement un prospect ou une demande'),
  ('leads.update_all',       'Modifier tous les prospects et demandes'),
  ('leads.assign',           'Affecter un prospect ou une demande à un agent'),
  ('leads.delete',           'Supprimer un prospect (droit à l''effacement)'),
  ('agents.manage',          'Créer et gérer les fiches agents'),
  ('users.read',             'Consulter la liste des utilisateurs et leurs rôles'),
  ('users.manage',           'Inviter, désactiver et réactiver des utilisateurs de rang inférieur'),
  ('roles.assign',           'Attribuer et retirer des rôles de rang inférieur'),
  ('catalog.manage',         'Gérer les types de biens, équipements et localités'),
  ('settings.manage',        'Modifier les paramètres de l''agence'),
  ('stats.read_own',         'Consulter ses propres statistiques'),
  ('stats.read_all',         'Consulter les statistiques globales et par agent'),
  ('audit.read',             'Consulter le journal d''audit');

-- super_admin : toutes les permissions
insert into public.role_permissions (role_code, permission_code)
select 'super_admin', code from public.permissions;

-- admin : tout sauf la suppression définitive des annonces
insert into public.role_permissions (role_code, permission_code)
select 'admin', code from public.permissions where code <> 'properties.delete';

insert into public.role_permissions (role_code, permission_code) values
  ('sales_manager', 'properties.read_all'),
  ('sales_manager', 'properties.create'),
  ('sales_manager', 'properties.update_own'),
  ('sales_manager', 'properties.update_all'),
  ('sales_manager', 'properties.publish'),
  ('sales_manager', 'leads.access_assigned'),
  ('sales_manager', 'leads.read_all'),
  ('sales_manager', 'leads.create'),
  ('sales_manager', 'leads.update_all'),
  ('sales_manager', 'leads.assign'),
  ('sales_manager', 'users.read'),
  ('sales_manager', 'stats.read_own'),
  ('sales_manager', 'stats.read_all'),
  ('agent', 'properties.read_all'),
  ('agent', 'properties.create'),
  ('agent', 'properties.update_own'),
  ('agent', 'leads.access_assigned'),
  ('agent', 'leads.create'),
  ('agent', 'stats.read_own');

-- -----------------------------------------------------------------------------
-- Profils
-- -----------------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  email           text,                                   -- copie en lecture seule de auth.users.email
  full_name       text not null default '' check (char_length(full_name) <= 120),
  phone           text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  avatar_path     text check (avatar_path is null or char_length(avatar_path) <= 300),
  locale          text not null default 'fr' check (locale in ('fr', 'en', 'wo')),
  is_active       boolean not null default true,
  deactivated_at  timestamptz,
  deactivated_by  uuid references public.profiles (id) on delete set null,
  last_sign_in_at timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.profiles is 'Profil interne d''un utilisateur authentifié (personnel de l''agence).';
comment on column public.profiles.is_active is 'Compte actif. Modifiable uniquement via admin_set_user_active / Edge Function admin-users.';

create index profiles_active_idx on public.profiles (is_active);
create unique index profiles_email_key on public.profiles (lower(email)) where email is not null;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

create trigger profiles_audit
  after update or delete on public.profiles
  for each row execute function private.audit_trigger('is_active,full_name,phone,email');

alter table public.profiles enable row level security;

-- -----------------------------------------------------------------------------
-- Rôles des utilisateurs
-- -----------------------------------------------------------------------------
create table public.user_roles (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  role_code  text not null references public.roles (code) on delete restrict,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default now(),
  primary key (user_id, role_code)
);
create index user_roles_role_idx on public.user_roles (role_code);

create trigger user_roles_audit
  after insert or delete on public.user_roles
  for each row execute function private.audit_trigger();

alter table public.user_roles enable row level security;

-- -----------------------------------------------------------------------------
-- Agents (fiche commerciale)
-- -----------------------------------------------------------------------------
create table public.agents (
  profile_id     uuid primary key references public.profiles (id) on delete cascade,
  slug           text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  display_name   text not null check (char_length(display_name) between 2 and 120),
  job_title      text check (char_length(job_title) <= 120),
  bio            text check (char_length(bio) <= 2000),
  public_phone   text check (public_phone is null or public_phone ~ '^\+[1-9][0-9]{7,14}$'),
  whatsapp_phone text check (whatsapp_phone is null or whatsapp_phone ~ '^\+[1-9][0-9]{7,14}$'),
  public_email   text check (public_email is null or public_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  photo_path     text check (photo_path is null or char_length(photo_path) <= 300),
  languages      text[] not null default array['fr']::text[],
  license_number text check (char_length(license_number) <= 60),
  is_public      boolean not null default true,    -- affiché sur le site public
  is_active      boolean not null default true,    -- peut recevoir des biens / prospects
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
comment on table public.agents is 'Fiche commerciale d''un membre du personnel pouvant être responsable de biens et de prospects.';

create index agents_active_idx on public.agents (is_active) where is_active;

create trigger agents_set_updated_at
  before update on public.agents
  for each row execute function private.set_updated_at();

create trigger agents_audit
  after insert or update or delete on public.agents
  for each row execute function private.audit_trigger('is_active,is_public,display_name,public_phone,whatsapp_phone,public_email');

alter table public.agents enable row level security;

-- =============================================================================
-- Fonctions d'autorisation (utilisées par les politiques RLS)
-- SECURITY DEFINER + search_path vide : elles lisent les tables de rôles sans
-- dépendre des droits de l'appelant et ne sont pas détournables.
-- =============================================================================

-- L'utilisateur courant est-il un membre actif du personnel (au moins un rôle) ?
create or replace function private.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid() and p.is_active
  );
$$;

-- L'utilisateur courant (actif) dispose-t-il de la permission ?
create or replace function private.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_code = ur.role_code
    join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid()
      and p.is_active
      and rp.permission_code = p_permission
  );
$$;

-- Rang maximal d'un utilisateur (0 s'il n'a aucun rôle).
create or replace function private.user_rank(p_user_id uuid)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(r.rank), 0)::smallint
  from public.user_roles ur
  join public.roles r on r.code = ur.role_code
  where ur.user_id = p_user_id;
$$;

create or replace function private.current_rank()
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select case when (select is_active from public.profiles where id = auth.uid())
              then private.user_rank(auth.uid()) else 0 end::smallint;
$$;

create or replace function private.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id
    where ur.user_id = auth.uid() and ur.role_code = 'super_admin' and p.is_active
  );
$$;

-- Appel de confiance : clé service_role (Edge Functions, scripts serveur) ou
-- connexion directe en tant que postgres (éditeur SQL, migrations).
-- ATTENTION : on n'utilise PAS current_user, qui vaut le propriétaire à
-- l'intérieur d'une fonction SECURITY DEFINER. Le GUC `role` reflète le
-- `SET ROLE` effectué par PostgREST (anon / authenticated / service_role) et
-- n'est pas modifié par SECURITY DEFINER.
create or replace function private.is_service_role()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or coalesce(current_setting('role', true), 'none') = 'service_role'
      or (coalesce(current_setting('role', true), 'none') = 'none'
          and session_user in ('postgres', 'supabase_admin'));
$$;

-- Écriture de confiance, à utiliser UNIQUEMENT dans les déclencheurs
-- SECURITY INVOKER (garde-fous) : service_role, connexion postgres, OU
-- écriture émise depuis une fonction SECURITY DEFINER du backend (dans ce
-- cas current_user = propriétaire `postgres`, rôle qu'un client de l'API ne
-- peut jamais endosser). Ne JAMAIS l'appeler depuis une fonction SECURITY
-- DEFINER : current_user y vaut toujours le propriétaire.
create or replace function private.is_trusted_writer()
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.is_service_role() or current_user in ('postgres', 'supabase_admin');
$$;

-- L'acteur courant peut-il gérer (rôles, activation) l'utilisateur cible ?
-- Règle : super_admin peut tout ; sinon rang de l'acteur strictement supérieur
-- au rang actuel de la cible. On ne se gère jamais soi-même.
create or replace function private.can_manage_user(p_target uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_target is distinct from auth.uid()
     and (private.is_super_admin() or private.current_rank() > private.user_rank(p_target));
$$;

-- anon reçoit aussi EXECUTE : certaines politiques publiques (lecture des
-- référentiels) combinent `is_active OR has_permission(...)`. Sans session,
-- ces fonctions renvoient simplement false.
grant execute on function
  private.is_active_staff(),
  private.has_permission(text),
  private.current_rank(),
  private.is_super_admin(),
  private.is_service_role(),
  private.is_trusted_writer(),
  private.can_manage_user(uuid)
to anon, authenticated;

-- =============================================================================
-- Création automatique du profil à l'inscription / invitation
-- =============================================================================
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 120)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- Synchronise l'e-mail et la dernière connexion.
create or replace function private.handle_auth_user_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email or new.last_sign_in_at is distinct from old.last_sign_in_at then
    update public.profiles
       set email = new.email,
           last_sign_in_at = new.last_sign_in_at
     where id = new.id;
  end if;
  return new;
end;
$$;

create trigger on_auth_user_updated
  after update of email, last_sign_in_at on auth.users
  for each row execute function private.handle_auth_user_updated();

-- =============================================================================
-- Garde-fous sur les profils et les agents (colonnes protégées)
-- =============================================================================
create or replace function private.profiles_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_writer() then
    return new;
  end if;
  -- Colonnes jamais modifiables directement via l'API.
  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.is_active is distinct from old.is_active
     or new.deactivated_at is distinct from old.deactivated_at
     or new.deactivated_by is distinct from old.deactivated_by
     or new.last_sign_in_at is distinct from old.last_sign_in_at
     or new.created_at is distinct from old.created_at then
    raise exception 'Colonne protégée : utilisez les fonctions d''administration dédiées.'
      using errcode = '42501';
  end if;
  -- Modifier le profil d'un autre utilisateur exige users.manage + rang supérieur.
  if old.id <> auth.uid() and not (private.has_permission('users.manage') and private.can_manage_user(old.id)) then
    raise exception 'Vous ne pouvez pas modifier ce profil.' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profiles_guard
  before update on public.profiles
  for each row execute function private.profiles_guard();

create or replace function private.agents_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_trusted_writer() or private.has_permission('agents.manage') then
    return new;
  end if;
  -- Un agent ne modifie que sa fiche, et pas ses indicateurs de statut.
  if new.profile_id is distinct from old.profile_id
     or new.is_active is distinct from old.is_active
     or new.is_public is distinct from old.is_public
     or new.slug is distinct from old.slug then
    raise exception 'Seul un gestionnaire peut modifier le statut ou l''identifiant d''un agent.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger agents_guard
  before update on public.agents
  for each row execute function private.agents_guard();

-- =============================================================================
-- Politiques RLS
-- =============================================================================

-- Référentiels de rôles : lisibles par le personnel actif.
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;

create policy roles_select_staff on public.roles
  for select to authenticated using ((select private.is_active_staff()));
create policy permissions_select_staff on public.permissions
  for select to authenticated using ((select private.is_active_staff()));
create policy role_permissions_select_staff on public.role_permissions
  for select to authenticated using ((select private.is_active_staff()));

-- Profils : chacun lit le sien ; le personnel actif lit ceux de ses collègues
-- (noms affichés dans le back-office).
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_active_staff()));

create policy profiles_update on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or (select private.has_permission('users.manage')))
  with check (id = (select auth.uid()) or (select private.has_permission('users.manage')));

-- Rôles des utilisateurs : on lit les siens ; users.read pour tous.
-- Aucune politique d'écriture : uniquement via assign_role / revoke_role.
create policy user_roles_select on public.user_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.has_permission('users.read')));

-- Agents : lecture par le personnel actif ; écriture contrôlée.
create policy agents_select_staff on public.agents
  for select to authenticated using ((select private.is_active_staff()));
create policy agents_insert on public.agents
  for insert to authenticated with check ((select private.has_permission('agents.manage')));
create policy agents_update on public.agents
  for update to authenticated
  using (profile_id = (select auth.uid()) or (select private.has_permission('agents.manage')))
  with check (profile_id = (select auth.uid()) or (select private.has_permission('agents.manage')));
create policy agents_delete on public.agents
  for delete to authenticated using ((select private.has_permission('agents.manage')));

-- =============================================================================
-- RPC : gestion des rôles et des comptes
-- =============================================================================

-- Accès de l'utilisateur courant (utilisé par le back-office au chargement).
create or replace function public.get_my_access()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', p.id,
    'email', p.email,
    'full_name', p.full_name,
    'is_active', p.is_active,
    'is_agent', exists (select 1 from public.agents a where a.profile_id = p.id and a.is_active),
    'rank', private.user_rank(p.id),
    'roles', coalesce((select jsonb_agg(ur.role_code order by r.rank desc)
                         from public.user_roles ur join public.roles r on r.code = ur.role_code
                        where ur.user_id = p.id), '[]'::jsonb),
    'permissions', case when p.is_active then coalesce((
                      select jsonb_agg(distinct rp.permission_code)
                        from public.user_roles ur
                        join public.role_permissions rp on rp.role_code = ur.role_code
                       where ur.user_id = p.id), '[]'::jsonb)
                   else '[]'::jsonb end
  )
  from public.profiles p
  where p.id = auth.uid();
$$;

-- Attribue un rôle. Règles :
--   * permission roles.assign ;
--   * jamais sur soi-même ;
--   * l'acteur doit pouvoir gérer la cible (rang supérieur) ;
--   * le rôle attribué doit être de rang strictement inférieur à celui de
--     l'acteur, sauf pour un super_admin.
create or replace function public.assign_role(p_user_id uuid, p_role_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_rank smallint;
begin
  select rank into v_role_rank from public.roles where code = p_role_code;
  if v_role_rank is null then
    raise exception 'Rôle inconnu : %', p_role_code using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Utilisateur introuvable.' using errcode = 'P0002';
  end if;

  if not private.is_service_role() then
    if not private.has_permission('roles.assign') then
      raise exception 'Permission roles.assign requise.' using errcode = '42501';
    end if;
    if not private.can_manage_user(p_user_id) then
      raise exception 'Vous ne pouvez pas gérer les rôles de cet utilisateur.' using errcode = '42501';
    end if;
    if not private.is_super_admin() and v_role_rank >= private.current_rank() then
      raise exception 'Vous ne pouvez attribuer que des rôles de rang inférieur au vôtre.' using errcode = '42501';
    end if;
  end if;

  insert into public.user_roles (user_id, role_code, granted_by)
  values (p_user_id, p_role_code, auth.uid())
  on conflict (user_id, role_code) do nothing;
end;
$$;

create or replace function public.revoke_role(p_user_id uuid, p_role_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_service_role() then
    if not private.has_permission('roles.assign') then
      raise exception 'Permission roles.assign requise.' using errcode = '42501';
    end if;
    if not private.can_manage_user(p_user_id) then
      raise exception 'Vous ne pouvez pas gérer les rôles de cet utilisateur.' using errcode = '42501';
    end if;
  end if;

  if p_role_code = 'super_admin' and (
       select count(*) from public.user_roles ur join public.profiles p on p.id = ur.user_id
        where ur.role_code = 'super_admin' and p.is_active and ur.user_id <> p_user_id) = 0 then
    raise exception 'Impossible de retirer le dernier super administrateur actif.' using errcode = '23514';
  end if;

  delete from public.user_roles where user_id = p_user_id and role_code = p_role_code;
end;
$$;

-- Active / désactive un compte (côté données). L'Edge Function admin-users
-- appelle cette RPC avec le JWT de l'acteur PUIS bannit/débannit le compte
-- dans Supabase Auth avec la clé service_role.
create or replace function public.admin_set_user_active(p_user_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Utilisateur introuvable.' using errcode = 'P0002';
  end if;
  if not private.is_service_role() then
    if not private.has_permission('users.manage') then
      raise exception 'Permission users.manage requise.' using errcode = '42501';
    end if;
    if not private.can_manage_user(p_user_id) then
      raise exception 'Vous ne pouvez pas gérer ce compte.' using errcode = '42501';
    end if;
  end if;
  if not p_active and exists (select 1 from public.user_roles where user_id = p_user_id and role_code = 'super_admin')
     and (select count(*) from public.user_roles ur join public.profiles p on p.id = ur.user_id
           where ur.role_code = 'super_admin' and p.is_active and ur.user_id <> p_user_id) = 0 then
    raise exception 'Impossible de désactiver le dernier super administrateur actif.' using errcode = '23514';
  end if;

  update public.profiles
     set is_active = p_active,
         deactivated_at = case when p_active then null else now() end,
         deactivated_by = case when p_active then null else auth.uid() end
   where id = p_user_id;

  -- Un compte désactivé ne peut plus recevoir de biens ni de prospects.
  if not p_active then
    update public.agents set is_active = false where profile_id = p_user_id;
  end if;
end;
$$;

-- Liste des utilisateurs pour l'écran d'administration.
create or replace function public.list_users()
returns table (
  id uuid, email text, full_name text, phone text, is_active boolean,
  last_sign_in_at timestamptz, created_at timestamptz, roles text[], rank smallint,
  is_agent boolean, can_manage boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.email, p.full_name, p.phone, p.is_active, p.last_sign_in_at, p.created_at,
         coalesce(array_agg(ur.role_code order by r.rank desc) filter (where ur.role_code is not null), '{}'),
         private.user_rank(p.id),
         exists (select 1 from public.agents a where a.profile_id = p.id),
         private.has_permission('users.manage') and private.can_manage_user(p.id)
  from public.profiles p
  left join public.user_roles ur on ur.user_id = p.id
  left join public.roles r on r.code = ur.role_code
  where private.has_permission('users.read')
  group by p.id
  order by p.created_at;
$$;

-- -----------------------------------------------------------------------------
-- Amorçage : premier super administrateur.
-- Exécutable UNIQUEMENT depuis l'éditeur SQL (rôle postgres), et seulement
-- tant qu'aucun super administrateur n'existe. Voir docs/FIRST_ADMIN.md.
-- -----------------------------------------------------------------------------
create or replace function private.bootstrap_super_admin(p_email text, p_display_name text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if exists (select 1 from public.user_roles where role_code = 'super_admin') then
    raise exception 'Un super administrateur existe déjà. Utilisez le back-office pour gérer les rôles.';
  end if;
  select id into v_user_id from auth.users where lower(email) = lower(p_email);
  if v_user_id is null then
    raise exception 'Aucun utilisateur Auth avec l''e-mail %. Créez-le d''abord (Dashboard > Authentication > Add user).', p_email;
  end if;

  insert into public.profiles (id, email, full_name)
  values (v_user_id, p_email, coalesce(p_display_name, ''))
  on conflict (id) do update set full_name = coalesce(nullif(excluded.full_name, ''), public.profiles.full_name);

  insert into public.user_roles (user_id, role_code) values (v_user_id, 'super_admin')
  on conflict do nothing;

  perform private.write_audit('RPC', 'user_roles', v_user_id::text, null,
                              jsonb_build_object('role_code', 'super_admin'),
                              jsonb_build_object('operation', 'bootstrap_super_admin'));
  return v_user_id;
end;
$$;

-- =============================================================================
-- Privilèges
-- =============================================================================
grant select on public.roles, public.permissions, public.role_permissions to authenticated;
grant select on public.profiles to authenticated;
-- Seules les colonnes "personnelles" sont modifiables (le garde-fou vérifie le reste).
grant update (full_name, phone, avatar_path, locale) on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert, delete on public.agents to authenticated;
grant update (display_name, job_title, bio, public_phone, whatsapp_phone, public_email, photo_path,
              languages, license_number, is_public, is_active, slug) on public.agents to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.get_my_access(),
  public.assign_role(uuid, text),
  public.revoke_role(uuid, text),
  public.admin_set_user_active(uuid, boolean),
  public.list_users()
to authenticated, service_role;
