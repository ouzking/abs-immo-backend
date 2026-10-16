-- Prospects, demandes, visites : soumissions publiques, cloisonnement, affectation, historique.
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('manager.l@test.sn', array['sales_manager'], true) as manager_id \gset
select tests.create_user('agent.l1@test.sn', array['agent'], true) as agent1_id \gset
select tests.create_user('agent.l2@test.sn', array['agent'], true) as agent2_id \gset
select tests.create_user('admin.l@test.sn', array['admin']) as admin_id \gset
select tests.create_property(:'agent1_id', true, 'Villa publiée pour prospects') as pub_id \gset
select tests.create_property(:'agent1_id', false, 'Villa brouillon pour prospects') as draft_id \gset
select tests.create_property(:'agent2_id', true, 'Bureau publié au Plateau', 'rent', 'office', 1200000) as office_id \gset

-- ---------------------------------------------------------------------------
-- Les fonctions de soumission ne sont pas appelables par les clients
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok($$select public.submit_inquiry('Robot', 'r@x.sn')$$, '42501', null, 'anon : submit_inquiry interdit (Edge Function obligatoire)');
select throws_ok($$select public.submit_viewing_request('Robot', gen_random_uuid(), null, '+221770000000')$$, '42501', null, 'anon : submit_viewing_request interdit');
reset role;
select tests.authenticate_as(:'agent1_id');
select throws_ok($$select public.submit_inquiry('Interne', 'i@x.sn')$$, '42501', null, 'authenticated : submit_inquiry interdit');
reset role;

-- ---------------------------------------------------------------------------
-- Soumissions (service_role, comme l'Edge Function)
-- ---------------------------------------------------------------------------
select tests.authenticate_as_service_role();
select public.submit_inquiry(p_full_name => '  Moussa   Ndiaye ', p_phone => '77 555 44 33', p_email => 'Moussa@Mail.SN',
                             p_message => 'Je souhaite plus d''informations.', p_property_id => :'pub_id',
                             p_inquiry_type => 'property_info', p_ip_hash => 'ip-hash-1') as r1 \gset
select is((:'r1'::jsonb ->> 'duplicate')::boolean, false, 'Première demande créée');
reset role;

select :'r1'::jsonb ->> 'lead_id' as lead1 \gset
select :'r1'::jsonb ->> 'inquiry_id' as inquiry1 \gset
select is((select full_name from public.leads where id = :'lead1'), 'Moussa Ndiaye', 'Nom nettoyé');
select is((select phone from public.leads where id = :'lead1'), '+221775554433', 'Téléphone normalisé');
select is((select email from public.leads where id = :'lead1'), 'moussa@mail.sn', 'E-mail normalisé');
select is((select assigned_agent_id from public.leads where id = :'lead1'), :'agent1_id'::uuid, 'Prospect affecté à l''agent du bien');
select is((select assigned_agent_id from public.inquiries where id = :'inquiry1'), :'agent1_id'::uuid, 'Demande affectée à l''agent du bien');
select is((select submission_meta ->> 'ip_hash' from public.inquiries where id = :'inquiry1'), 'ip-hash-1', 'Empreinte IP stockée (jamais l''IP brute)');
select ok(exists (select 1 from public.lead_activities where lead_id = :'lead1' and activity_type = 'inquiry_received'),
  'Historique : réception journalisée');

-- Doublon exact (< 24 h)
select tests.authenticate_as_service_role();
select public.submit_inquiry(p_full_name => 'Moussa Ndiaye', p_phone => '+221775554433', p_message => 'Relance',
                             p_property_id => :'pub_id', p_inquiry_type => 'property_info', p_ip_hash => 'ip-hash-1') as r2 \gset
reset role;
select is((:'r2'::jsonb ->> 'duplicate')::boolean, true, 'Doublon détecté');
select is((:'r2'::jsonb ->> 'inquiry_id'), :'inquiry1', 'Doublon : demande existante renvoyée');
select is((select count(*)::int from public.inquiries where lead_id = :'lead1'), 1, 'Doublon : pas de nouvelle demande');
select ok(exists (select 1 from public.lead_activities where lead_id = :'lead1' and content = 'Relance'),
  'Doublon : message ajouté à l''historique');

-- Même personne, autre bien -> même prospect, nouvelle demande
select tests.authenticate_as_service_role();
select public.submit_inquiry(p_full_name => 'Moussa N.', p_email => 'moussa@mail.sn', p_property_id => :'office_id',
                             p_ip_hash => 'ip-hash-1') as r3 \gset
reset role;
select is((:'r3'::jsonb ->> 'lead_id'), :'lead1', 'Prospect dédoublonné par e-mail');
select is((select assigned_agent_id from public.inquiries where id = (:'r3'::jsonb ->> 'inquiry_id')::uuid), :'agent2_id'::uuid,
  'Demande sur le bien d''agent 2 affectée à agent 2');

-- Validations
select tests.authenticate_as_service_role();
select throws_ok($$select public.submit_inquiry(p_full_name => 'X', p_email => 'x@y.sn', p_message => 'm')$$, 'AB422', null, 'Nom trop court');
select throws_ok($$select public.submit_inquiry(p_full_name => 'Sans Contact', p_message => 'm')$$, 'AB422', null, 'Contact requis');
select throws_ok($$select public.submit_inquiry(p_full_name => 'Mauvais Mail', p_email => 'pas-un-mail', p_message => 'm')$$, 'AB422', null, 'E-mail invalide');
select throws_ok(format($$select public.submit_inquiry(p_full_name => 'Curieux', p_email => 'c@y.sn', p_property_id => %L)$$, :'draft_id'),
  'AB404', null, 'Demande sur un brouillon refusée');
select throws_ok(format($$select public.submit_viewing_request(p_full_name => 'Visiteur', p_property_id => %L, p_email => 'v@y.sn')$$, :'pub_id'),
  'AB422', null, 'Visite : téléphone obligatoire');
select throws_ok(format($$select public.submit_viewing_request(p_full_name => 'Visiteur', p_property_id => %L, p_phone => '+221770001111', p_preferred_date => current_date - 1)$$, :'pub_id'),
  'AB422', null, 'Visite : date passée refusée');
select throws_ok(format($$select public.submit_viewing_request(p_full_name => 'Visiteur', p_property_id => %L, p_phone => '+221770001111')$$, :'draft_id'),
  'AB404', null, 'Visite : brouillon refusé');

-- Demande de visite valide puis doublon
select public.submit_viewing_request(p_full_name => 'Awa Fall', p_property_id => :'pub_id', p_phone => '+221781112233',
                                     p_preferred_date => current_date + 3, p_preferred_time_slot => 'morning',
                                     p_ip_hash => 'ip-hash-2') as v1 \gset
select public.submit_viewing_request(p_full_name => 'Awa Fall', p_property_id => :'pub_id', p_phone => '78 111 22 33',
                                     p_ip_hash => 'ip-hash-2') as v2 \gset
reset role;
select is((:'v1'::jsonb ->> 'duplicate')::boolean, false, 'Visite créée');
select is((:'v2'::jsonb ->> 'duplicate')::boolean, true, 'Visite en double détectée');
select :'v1'::jsonb ->> 'viewing_request_id' as viewing1 \gset
select :'v1'::jsonb ->> 'lead_id' as lead2 \gset

-- Limitation de débit (5 / 10 min par empreinte IP et par formulaire)
select tests.authenticate_as_service_role();
select public.submit_inquiry(p_full_name => 'Spammeur ' || i, p_email => 'spam' || i || '@x.sn', p_message => 'spam', p_ip_hash => 'ip-spam')
  from generate_series(1, 5) i;
select throws_ok($$select public.submit_inquiry(p_full_name => 'Spammeur 6', p_email => 'spam6@x.sn', p_message => 'spam', p_ip_hash => 'ip-spam')$$,
  'AB429', null, '6e soumission en 10 min depuis la même IP : refusée');
select lives_ok($$select public.submit_inquiry(p_full_name => 'Autre Personne', p_email => 'autre@x.sn', p_message => 'ok', p_ip_hash => 'ip-autre')$$,
  'Autre IP : acceptée');
reset role;

-- ---------------------------------------------------------------------------
-- Cloisonnement entre agents
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent2_id');
select is((select count(*)::int from public.leads where id = :'lead2'), 0, 'Agent 2 : ne voit pas le prospect d''agent 1');
select is((select count(*)::int from public.viewing_requests where id = :'viewing1'), 0, 'Agent 2 : ne voit pas la visite d''agent 1');
select is((select count(*)::int from public.lead_activities where lead_id = :'lead2'), 0, 'Agent 2 : ne voit pas l''historique d''agent 1');
-- Agent 2 voit le prospect 1 car une demande lui est affectée (bien d'agent 2)
select is((select count(*)::int from public.leads where id = :'lead1'), 1, 'Agent 2 : voit le prospect dont une demande lui est affectée');
select is((select count(*)::int from public.inquiries where lead_id = :'lead1'), 1, 'Agent 2 : ne voit que SA demande de ce prospect');
update public.leads set status = 'lost' where id = :'lead2';
select throws_ok(format($$insert into public.lead_activities (lead_id, activity_type, content) values (%L, 'note', 'intrusion')$$, :'lead2'),
  '42501', null, 'Agent 2 : ne peut pas annoter le prospect d''agent 1');
reset role;
select is((select status::text from public.leads where id = :'lead2'), 'new', 'Agent 2 : modification du prospect d''agent 1 sans effet');

select tests.authenticate_as(:'agent1_id');
select is((select count(*)::int from public.leads where id in (:'lead1', :'lead2')), 2, 'Agent 1 : voit ses prospects');
select lives_ok(format($$update public.leads set status = 'contacted' where id = %L$$, :'lead2'), 'Agent 1 : fait progresser son prospect');
select lives_ok(format($$insert into public.lead_activities (lead_id, activity_type, content) values (%L, 'call', 'Appel : intéressée')$$, :'lead2'),
  'Agent 1 : ajoute une note d''appel');
select throws_ok(format($$insert into public.lead_activities (lead_id, activity_type, content) values (%L, 'status_change', 'faux')$$, :'lead2'),
  '42501', null, 'Agent 1 : ne peut pas forger une activité système');
select throws_ok(format($$update public.leads set assigned_agent_id = %L where id = %L$$, :'agent2_id', :'lead2'),
  '42501', null, 'Agent 1 : ne peut pas réaffecter un prospect');
select throws_ok(format($$select public.assign_lead(%L, %L)$$, :'lead2', :'agent2_id'), '42501', null, 'Agent 1 : assign_lead interdit');
select lives_ok(format($$update public.viewing_requests set status = 'confirmed', scheduled_at = now() + interval '3 days' where id = %L$$, :'viewing1'),
  'Agent 1 : confirme une visite');
select throws_ok($$update public.lead_activities set content = 'modifié'$$, '42501', null, 'Historique non modifiable');
reset role;
select is((select status::text from public.leads where id = :'lead2'), 'visit_scheduled', 'Visite confirmée : prospect en « visite planifiée »');
select ok(exists (select 1 from public.lead_activities where lead_id = :'lead2' and activity_type = 'status_change'
                    and actor_id = :'agent1_id' and metadata ->> 'to' = 'contacted'),
  'Changement de statut journalisé avec son auteur');
select isnt((select actor_id from public.lead_activities where lead_id = :'lead2' and activity_type = 'call'), null, 'Auteur de la note forcé');

-- Saisie manuelle par un agent (prospect venu en agence)
select tests.authenticate_as(:'agent1_id');
select lives_ok($$insert into public.leads (full_name, phone, source) values ('Client Agence', '+221760000001', 'walk_in')$$,
  'Agent : saisit un prospect venu en agence');
select is((select assigned_agent_id from public.leads where full_name = 'Client Agence'), :'agent1_id'::uuid, 'Prospect saisi affecté à son auteur');
reset role;

-- ---------------------------------------------------------------------------
-- Responsable : vision globale et affectation
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'manager_id');
select ok((select count(*)::int from public.leads) >= 8, 'Responsable : voit tous les prospects');
select lives_ok(format($$select public.assign_lead(%L, %L)$$, :'lead2', :'agent2_id'), 'Responsable : réaffecte un prospect et ses demandes ouvertes');
select throws_ok(format($$select public.assign_lead(%L, %L)$$, :'lead2', :'admin_id'), '23514', null, 'Affectation à un non-agent refusée');
delete from public.leads where id = :'lead2';   -- pas de leads.delete : 0 ligne
reset role;
select is((select count(*)::int from public.leads where id = :'lead2'), 1, 'Responsable : ne peut pas supprimer un prospect');
select is((select assigned_agent_id from public.viewing_requests where id = :'viewing1'), :'agent2_id'::uuid, 'Visite ouverte réaffectée');
select ok(exists (select 1 from public.lead_activities where lead_id = :'lead2' and activity_type = 'assignment'), 'Réaffectation journalisée');

select tests.authenticate_as(:'agent2_id');
select is((select count(*)::int from public.leads where id = :'lead2'), 1, 'Agent 2 : voit désormais le prospect réaffecté');
reset role;

-- Effacement (droit à l'oubli) : admin uniquement
select tests.authenticate_as(:'admin_id');
select lives_ok(format($$delete from public.leads where id = %L$$, :'lead2'), 'Admin : supprime un prospect');
reset role;
select is((select count(*)::int from public.viewing_requests where lead_id = :'lead2'), 0, 'Suppression du prospect : visites supprimées');

select * from finish();
rollback;
