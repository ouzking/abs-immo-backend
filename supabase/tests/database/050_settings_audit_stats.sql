-- Paramètres, audit, statistiques.
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('admin.s@test.sn', array['admin']) as admin_id \gset
select tests.create_user('manager.s@test.sn', array['sales_manager'], true) as manager_id \gset
select tests.create_user('agent.s1@test.sn', array['agent'], true) as agent1_id \gset
select tests.create_user('agent.s2@test.sn', array['agent'], true) as agent2_id \gset

select tests.create_property(:'agent1_id', true, 'Villa vendue statistiques') as p1 \gset
select tests.create_property(:'agent1_id', false, 'Brouillon statistiques') as p2 \gset
select tests.create_property(:'agent2_id', true, 'Appartement loué statistiques', 'rent', 'apartment', 500000) as p3 \gset
update public.properties set commercial_status = 'sold' where id = :'p1';
update public.properties set commercial_status = 'rented' where id = :'p3';

select tests.authenticate_as_service_role();
select public.submit_inquiry(p_full_name => 'Stat Un', p_email => 'stat1@x.sn', p_property_id => :'p1', p_ip_hash => 's1');
select public.submit_inquiry(p_full_name => 'Stat Deux', p_email => 'stat2@x.sn', p_property_id => :'p3', p_ip_hash => 's2');
select public.submit_inquiry(p_full_name => 'Stat Deux', p_email => 'stat2@x.sn', p_property_id => :'p3', p_ip_hash => 's2'); -- doublon
reset role;

-- ---------------------------------------------------------------------------
-- Paramètres de l'agence
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select is((select agency_name from public.agency_settings), 'ABS IMMO & SERVICES', 'anon : lit les paramètres publics');
select throws_ok($$update public.agency_settings set agency_name = 'Pirate'$$, '42501', null, 'anon : modification des paramètres interdite');
select throws_ok($$select * from public.app_settings$$, '42501', null, 'anon : paramètres internes interdits');
reset role;
select is((select agency_name from public.agency_settings), 'ABS IMMO & SERVICES', 'anon : modification sans effet');

select tests.authenticate_as(:'agent1_id');
update public.agency_settings set agency_name = 'Agent';
select is((select count(*)::int from public.app_settings), 0, 'Agent : paramètres internes invisibles');
reset role;
select is((select agency_name from public.agency_settings), 'ABS IMMO & SERVICES', 'Agent : ne modifie pas les paramètres');

select tests.authenticate_as(:'admin_id');
select lives_ok($$update public.agency_settings set phone = '+221338009988', whatsapp_phone = '+221770009988',
                    social_links = '{"facebook":"https://facebook.com/absimmo"}'$$, 'Admin : modifie les coordonnées');
select throws_ok($$update public.agency_settings set phone = '0000'$$, '23514', null, 'Téléphone de l''agence validé');
select throws_ok($$insert into public.agency_settings (id) values (false)$$, '42501', null, 'Ligne unique : insertion interdite');
select lives_ok($$update public.app_settings set value = '8' where key = 'rate_limit.per_ip_10min'$$, 'Admin : ajuste un paramètre opérationnel');
reset role;
select is((select updated_by from public.agency_settings), :'admin_id'::uuid, 'Auteur de la modification tracé');

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from public.audit_logs where table_name = 'agency_settings' and actor_id = :'admin_id'
                    and new_data ? 'phone' and not (new_data ? 'agency_name')),
  'Audit : seules les colonnes modifiées sont enregistrées');
select ok(exists (select 1 from public.audit_logs where table_name = 'properties' and record_id = :'p1'
                    and old_data ->> 'commercial_status' = 'available' and new_data ->> 'commercial_status' = 'sold'),
  'Audit : changement de statut commercial');
select tests.authenticate_as(:'agent1_id');
select is((select count(*)::int from public.audit_logs), 0, 'Agent : journal d''audit invisible');
reset role;
select tests.authenticate_as(:'admin_id');
select ok((select count(*)::int from public.audit_logs) > 0, 'Admin : lit le journal d''audit');
select throws_ok($$delete from public.audit_logs$$, '42501', null, 'Journal d''audit non effaçable');
select throws_ok($$update public.audit_logs set action = 'X'$$, '42501', null, 'Journal d''audit non modifiable');
reset role;

-- ---------------------------------------------------------------------------
-- Statistiques
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'manager_id');
select public.get_dashboard_stats(now() - interval '30 days', now() + interval '1 minute') as s \gset
reset role;
select is((:'s'::jsonb #>> '{properties,total}')::int, 3, 'Global : 3 biens (hors archives)');
select is((:'s'::jsonb #>> '{properties,published}')::int, 2, 'Global : 2 publiés');
select is((:'s'::jsonb #>> '{properties,draft}')::int, 1, 'Global : 1 brouillon');
select is((:'s'::jsonb #>> '{properties,available}')::int, 1, 'Global : 1 disponible');
select is((:'s'::jsonb #>> '{properties,sold}')::int, 1, 'Global : 1 vendu');
select is((:'s'::jsonb #>> '{properties,rented}')::int, 1, 'Global : 1 loué');
select is((:'s'::jsonb #>> '{properties,sold_in_period}')::int, 1, 'Global : 1 vendu sur la période');
select is((:'s'::jsonb #>> '{inquiries,received_in_period}')::int, 2, 'Global : 2 demandes (le doublon n''est pas compté)');
select is((:'s'::jsonb #>> '{inquiries,pending}')::int, 2, 'Global : 2 demandes en attente');
select is((:'s'::jsonb #>> '{properties,by_transaction,sale}')::int, 2, 'Répartition : 2 en vente');

select tests.authenticate_as(:'agent1_id');
select public.get_dashboard_stats(now() - interval '30 days', now() + interval '1 minute') as sa \gset
select throws_ok(format($$select public.get_dashboard_stats(p_agent_id => %L)$$, :'agent2_id'), '42501', null,
  'Agent : ne peut pas consulter les statistiques d''un collègue');
select is((select count(*)::int from public.get_agent_performance()), 1, 'Agent : performance limitée à lui-même');
reset role;
select is((:'sa'::jsonb #>> '{scope,agent_id}')::uuid, :'agent1_id'::uuid, 'Agent : périmètre forcé à lui-même');
select is((:'sa'::jsonb #>> '{properties,total}')::int, 2, 'Agent : ne compte que ses biens');
select is((:'sa'::jsonb #>> '{inquiries,received_in_period}')::int, 1, 'Agent : ne compte que ses demandes');

select tests.authenticate_as(:'manager_id');
select is((select count(*)::int from public.get_agent_performance()), 3, 'Responsable : performance de tous les agents');
select is((select inquiries_received from public.get_agent_performance(now() - interval '1 day', now() + interval '1 minute') where agent_id = :'agent2_id'), 1, 'Performance : demandes reçues par agent');
select is((select count(*)::int from public.get_inquiry_timeseries(now() - interval '6 days', now(), 'day')), 7, 'Série temporelle : 7 jours');
select is((select sum(inquiries)::int from public.get_inquiry_timeseries(now() - interval '6 days', now() + interval '1 minute', 'day')), 2, 'Série temporelle : total cohérent');
select throws_ok($$select * from public.get_inquiry_timeseries(p_interval => 'hour')$$, '22023', null, 'Intervalle invalide refusé');
reset role;

select tests.create_user('nobody.s@test.sn') as nobody_id \gset
select tests.authenticate_as(:'nobody_id');
select throws_ok($$select public.get_dashboard_stats()$$, '42501', null, 'Sans rôle : statistiques interdites');
reset role;

select * from finish();
rollback;
