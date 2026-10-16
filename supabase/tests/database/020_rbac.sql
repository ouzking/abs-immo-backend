-- Rôles, permissions, profils, désactivation des comptes.
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('super@test.sn', array['super_admin']) as super_id \gset
select tests.create_user('admin@test.sn', array['admin']) as admin_id \gset
select tests.create_user('manager@test.sn', array['sales_manager'], true) as manager_id \gset
select tests.create_user('agent@test.sn', array['agent'], true) as agent_id \gset
select tests.create_user('newbie@test.sn') as newbie_id \gset
select tests.create_user('admin2@test.sn', array['admin']) as admin2_id \gset

select is((select count(*)::int from public.profiles where id = :'newbie_id'), 1, 'Profil créé automatiquement à la création du compte Auth');
select is((select full_name from public.profiles where id = :'newbie_id'), 'newbie', 'Nom repris des métadonnées');

-- ---------------------------------------------------------------------------
-- Utilisateur sans rôle : aucun accès personnel
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'newbie_id');
select is((select private.is_active_staff()), false, 'Sans rôle : pas membre du personnel');
select is((select count(*)::int from public.profiles), 1, 'Sans rôle : ne voit que son propre profil');
select is((select count(*)::int from public.roles), 0, 'Sans rôle : référentiel des rôles invisible');
select is(jsonb_array_length(public.get_my_access() -> 'permissions'), 0, 'Sans rôle : aucune permission');
select throws_ok(format($$select public.assign_role(%L, 'super_admin')$$, :'newbie_id'), '42501', null,
  'Un utilisateur ne peut pas s''attribuer un rôle');
select throws_ok(format($$insert into public.user_roles (user_id, role_code) values (%L, 'admin')$$, :'newbie_id'), '42501', null,
  'Insertion directe dans user_roles refusée');
select throws_ok(format($$update public.profiles set is_active = true where id = %L$$, :'newbie_id'), '42501', null,
  'is_active non modifiable par l''utilisateur');
reset role;

-- ---------------------------------------------------------------------------
-- Agent
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent_id');
select ok((public.get_my_access() -> 'permissions') ? 'properties.create', 'Agent : properties.create');
select ok(not ((public.get_my_access() -> 'permissions') ? 'properties.publish'), 'Agent : pas properties.publish');
select ok(not ((public.get_my_access() -> 'permissions') ? 'leads.read_all'), 'Agent : pas leads.read_all');
select is((public.get_my_access() ->> 'is_agent')::boolean, true, 'Agent : fiche agent détectée');
select throws_ok(format($$select public.assign_role(%L, 'agent')$$, :'newbie_id'), '42501', null, 'Agent : ne peut pas attribuer de rôle');
select throws_ok(format($$select public.admin_set_user_active(%L, false)$$, :'newbie_id'), '42501', null, 'Agent : ne peut pas désactiver un compte');
select is((select count(*)::int from public.list_users()), 0, 'Agent : list_users vide (users.read requis)');
select lives_ok($$update public.profiles set full_name = 'Agent Modifié', phone = '+221770000099' where id = auth.uid()$$,
  'Agent : peut modifier son nom et téléphone');
update public.profiles set full_name = 'Piraté' where id = :'manager_id';
select is((select full_name from public.profiles where id = :'manager_id'), 'manager',
  'Agent : ne peut pas modifier le profil d''un collègue (filtré par RLS)');
select lives_ok($$update public.agents set bio = 'Spécialiste Almadies' where profile_id = auth.uid()$$, 'Agent : peut modifier sa fiche');
select throws_ok($$update public.agents set is_public = false where profile_id = auth.uid()$$, '42501', null,
  'Agent : ne peut pas modifier son statut public');
select is((select count(*)::int from public.agents where profile_id = :'manager_id' and bio is null), 1, 'Agent : lit les fiches collègues');
update public.agents set bio = 'x' where profile_id = :'manager_id';
reset role;
select is((select bio from public.agents where profile_id = :'manager_id'), null, 'Agent : la fiche d''un collègue n''est pas modifiée (RLS)');

-- ---------------------------------------------------------------------------
-- Administrateur : rôles de rang inférieur uniquement
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select lives_ok(format($$select public.assign_role(%L, 'agent')$$, :'newbie_id'), 'Admin : peut attribuer agent');
select lives_ok(format($$select public.assign_role(%L, 'sales_manager')$$, :'newbie_id'), 'Admin : peut attribuer sales_manager');
select throws_ok(format($$select public.assign_role(%L, 'admin')$$, :'newbie_id'), '42501', null, 'Admin : ne peut pas attribuer admin');
select throws_ok(format($$select public.assign_role(%L, 'super_admin')$$, :'newbie_id'), '42501', null, 'Admin : ne peut pas attribuer super_admin');
select throws_ok(format($$select public.revoke_role(%L, 'admin')$$, :'admin2_id'), '42501', null, 'Admin : ne peut pas gérer un autre admin');
select throws_ok(format($$select public.revoke_role(%L, 'admin')$$, :'admin_id'), '42501', null, 'Admin : ne peut pas modifier ses propres rôles');
select throws_ok(format($$select public.admin_set_user_active(%L, false)$$, :'super_id'), '42501', null, 'Admin : ne peut pas désactiver un super admin');
select throws_ok(format($$select public.admin_set_user_active(%L, false)$$, :'admin_id'), '42501', null, 'Admin : ne peut pas se désactiver');
select is((select count(*)::int from public.list_users()), 6, 'Admin : voit tous les utilisateurs');
select is((select can_manage from public.list_users() where id = :'agent_id'), true, 'Admin : peut gérer un agent');
select is((select can_manage from public.list_users() where id = :'super_id'), false, 'Admin : ne peut pas gérer le super admin');
select lives_ok(format($$update public.profiles set full_name = 'Agent Renommé' where id = %L$$, :'agent_id'), 'Admin : peut renommer un agent');
reset role;
select ok(exists (select 1 from public.user_roles where user_id = :'newbie_id' and role_code = 'agent' and granted_by = :'admin_id'),
  'Attribution tracée (granted_by)');
select ok(exists (select 1 from public.audit_logs where table_name = 'user_roles' and record_id = :'newbie_id' and actor_id = :'admin_id'),
  'Attribution de rôle journalisée dans l''audit');

-- ---------------------------------------------------------------------------
-- Super administrateur
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'super_id');
select lives_ok(format($$select public.assign_role(%L, 'admin')$$, :'newbie_id'), 'Super admin : peut attribuer admin');
select lives_ok(format($$select public.assign_role(%L, 'super_admin')$$, :'admin2_id'), 'Super admin : peut attribuer super_admin');
select lives_ok(format($$select public.revoke_role(%L, 'super_admin')$$, :'admin2_id'), 'Super admin : peut retirer super_admin à un autre');
reset role;
-- Dernier super admin : protection (via service_role pour contourner la règle « pas soi-même »)
select throws_ok(format($$select public.revoke_role(%L, 'super_admin')$$, :'super_id'), '23514', null,
  'Impossible de retirer le dernier super admin');
select throws_ok(format($$select public.admin_set_user_active(%L, false)$$, :'super_id'), '23514', null,
  'Impossible de désactiver le dernier super admin');

-- ---------------------------------------------------------------------------
-- Désactivation : perte immédiate des droits, même avec un JWT encore valide
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select lives_ok(format($$select public.admin_set_user_active(%L, false)$$, :'agent_id'), 'Admin : désactive un agent');
reset role;
select is((select is_active from public.profiles where id = :'agent_id'), false, 'Profil désactivé');
select is((select is_active from public.agents where profile_id = :'agent_id'), false, 'Fiche agent désactivée');
select isnt((select deactivated_by from public.profiles where id = :'agent_id'), null, 'Auteur de la désactivation tracé');
select tests.authenticate_as(:'agent_id');
select is((select private.has_permission('properties.create')), false, 'Compte désactivé : plus aucune permission');
select is((select count(*)::int from public.properties), 0, 'Compte désactivé : plus aucun bien visible');
select is(jsonb_array_length(public.get_my_access() -> 'permissions'), 0, 'Compte désactivé : get_my_access sans permission');
reset role;
select tests.authenticate_as(:'admin_id');
select lives_ok(format($$select public.admin_set_user_active(%L, true)$$, :'agent_id'), 'Admin : réactive l''agent');
reset role;
select tests.authenticate_as(:'agent_id');
select is((select private.has_permission('properties.create')), true, 'Compte réactivé : permissions restaurées');
reset role;

-- ---------------------------------------------------------------------------
-- Amorçage du premier super admin
-- ---------------------------------------------------------------------------
select throws_ok($$select private.bootstrap_super_admin('newbie@test.sn')$$, 'P0001', null,
  'bootstrap_super_admin refusé si un super admin existe déjà');

select * from finish();
rollback;
