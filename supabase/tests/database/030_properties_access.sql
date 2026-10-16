-- Accès aux biens : public (vues/RPC), agents, responsables. Workflow de publication.
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('manager.x@test.sn', array['sales_manager'], true) as manager_id \gset
select tests.create_user('agent.one@test.sn', array['agent'], true) as agent1_id \gset
select tests.create_user('agent.two@test.sn', array['agent'], true) as agent2_id \gset
select tests.create_user('superadm@test.sn', array['super_admin']) as super_id \gset
select id as almadies from public.localities where slug = 'almadies' \gset

select tests.create_property(:'agent1_id', true, 'Villa publiée avec piscine aux Almadies') as pub_id \gset
select tests.create_property(:'agent1_id', false, 'Villa brouillon secrète') as draft_id \gset
select tests.create_property(:'agent2_id', true, 'Appartement meublé à louer', 'rent', 'apartment', 850000) as rent_id \gset
update public.properties set address_visibility = 'exact' where id = :'rent_id';
select slug as draft_slug from public.properties where id = :'draft_id' \gset

-- ---------------------------------------------------------------------------
-- Public (anon)
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok('select * from public.properties', '42501', null, 'anon : lecture directe de properties interdite');
select throws_ok('select * from public.property_media', '42501', null, 'anon : lecture directe de property_media interdite');
select throws_ok('select * from public.leads', '42501', null, 'anon : lecture de leads interdite');
select throws_ok(
  format($$insert into public.properties (title, property_type, transaction_type, price_amount, locality_id) values ('Pirate annonce', 'villa', 'sale', 1, %L)$$, :'almadies'),
  '42501', null, 'anon : création de bien interdite');

select is((select count(*)::int from public.public_properties), 2, 'anon : ne voit que les 2 annonces publiées');
select is((select count(*)::int from public.public_properties where id = :'draft_id'), 0, 'anon : brouillon invisible');
select ok(not exists (select 1 from information_schema.columns where table_name = 'public_properties' and column_name in ('internal_notes', 'created_by', 'agent_id')),
  'Vue publique : aucune colonne interne (internal_notes, created_by, agent_id)');
select is((select address_line from public.public_properties where id = :'pub_id'), null, 'Adresse masquée (visibilité approximative)');
select is((select latitude from public.public_properties where id = :'pub_id'), 14.75::numeric, 'Latitude arrondie à ~1 km');
select is((select address_line from public.public_properties where id = :'rent_id'), '12 rue secrète', 'Adresse exacte si autorisée');
select is((select latitude from public.public_properties where id = :'rent_id'), 14.745678::numeric, 'Coordonnées exactes si autorisées');
select isnt((select cover_image_path from public.public_properties where id = :'pub_id'), null, 'Couverture exposée');
select is((select agent ->> 'display_name' from public.public_properties where id = :'pub_id'), 'agent.one', 'Agent public exposé');
select is((select count(*)::int from public.public_property_media where property_id = :'draft_id'), 0, 'Photos de brouillon invisibles');

-- Détail
select is((public.get_public_property(p_slug => (select slug from public.public_properties where id = :'pub_id')) ->> 'id')::uuid, :'pub_id'::uuid,
  'get_public_property par slug');
select is(public.get_public_property(p_slug => :'draft_slug'), null,
  'get_public_property : brouillon introuvable');
select ok(not (public.get_public_property(p_slug => (select slug from public.public_properties where id = :'pub_id')) ? 'internal_notes'),
  'Détail : pas de notes internes');
select is(jsonb_array_length(public.get_public_property(p_slug => (select slug from public.public_properties where id = :'pub_id')) -> 'images'), 1,
  'Détail : photos incluses');

-- Recherche
select is((select count(*)::int from public.search_properties(p_transaction_type => 'rent')), 1, 'Filtre transaction');
select is((select count(*)::int from public.search_properties(p_property_types => array['villa'])), 1, 'Filtre type');
select is((select count(*)::int from public.search_properties(p_max_price => 1000000)), 1, 'Filtre budget max');
select is((select count(*)::int from public.search_properties(p_min_price => 1000000)), 1, 'Filtre budget min');
select is((select count(*)::int from public.search_properties(p_neighborhood_id => :'almadies')), 2, 'Filtre quartier');
select is((select count(*)::int from public.search_properties(p_query => 'piscine')), 1, 'Recherche plein texte');
select is((select count(*)::int from public.search_properties(p_query => 'meuble')), 1, 'Recherche insensible aux accents (meuble → meublé)');
select is((select count(*)::int from public.search_properties(p_query => 'secrète')), 0, 'Recherche : brouillons exclus');
select is((select price_amount from public.search_properties(p_sort => 'price_asc') limit 1), 850000::bigint, 'Tri prix croissant');
select is((select count(*)::int from (select * from public.search_properties() limit 1 offset 1) s), 1, 'Pagination (limit/offset)');
select throws_ok($$select * from public.search_properties(p_sort => 'drop table')$$, '22023', null, 'Tri invalide refusé');
select throws_ok($$select * from public.search_properties(p_min_price => 10, p_max_price => 5)$$, '22023', null, 'Budget incohérent refusé');
select is((public.get_public_filters() -> 'price_ranges' -> 'rent' ->> 'min')::bigint, 850000::bigint, 'Filtres disponibles calculés');
select is((select count(*)::int from public.public_agents), 3, 'Agents publics listés (fiches actives et publiques)');
select is((select count(*)::int from public.agency_settings), 1, 'Paramètres publics lisibles');
reset role;

-- ---------------------------------------------------------------------------
-- Agent 1
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent1_id');
select is((select count(*)::int from public.properties), 3, 'Agent : lit le catalogue interne (properties.read_all)');
select lives_ok(format($$insert into public.properties (title, property_type, transaction_type, price_amount, locality_id) values ('Maison familiale à Ngor', 'house', 'sale', 90000000, %L)$$, :'almadies'),
  'Agent : crée un bien');
select is((select agent_id from public.properties where title = 'Maison familiale à Ngor'), :'agent1_id'::uuid, 'Agent : devient automatiquement responsable');
select is((select created_by from public.properties where title = 'Maison familiale à Ngor'), :'agent1_id'::uuid, 'created_by forcé');
select throws_ok(format($$insert into public.properties (title, property_type, transaction_type, price_amount, locality_id, agent_id) values ('Bien pour autrui', 'house', 'sale', 1000, %L, %L)$$, :'almadies', :'agent2_id'),
  '42501', null, 'Agent : ne peut pas créer un bien pour un autre agent');
select throws_ok(format($$insert into public.properties (title, property_type, transaction_type, price_amount, locality_id, publication_status) values ('Publié direct', 'house', 'sale', 1000, %L, 'published')$$, :'almadies'),
  '42501', null, 'Agent : ne peut pas créer un bien publié');
select lives_ok(format($$update public.properties set price_amount = 95000000, commercial_status = 'reserved' where id = %L$$, :'draft_id'),
  'Agent : modifie son bien (prix, statut commercial)');
select lives_ok(format($$update public.properties set publication_status = 'pending_review' where id = %L$$, :'draft_id'),
  'Agent : soumet son bien à validation');
select throws_ok(format($$update public.properties set publication_status = 'published' where id = %L$$, :'draft_id'),
  '42501', null, 'Agent : ne peut pas publier');
select throws_ok(format($$update public.properties set publication_status = 'archived' where id = %L$$, :'pub_id'),
  '42501', null, 'Agent : ne peut pas archiver');
select throws_ok(format($$update public.properties set is_featured = true where id = %L$$, :'draft_id'),
  '42501', null, 'Agent : ne peut pas mettre en avant');
select throws_ok(format($$update public.properties set agent_id = %L where id = %L$$, :'agent2_id', :'draft_id'),
  '42501', null, 'Agent : ne peut pas céder son bien');
select throws_ok(format($$update public.properties set reference = 'HACK-1' where id = %L$$, :'draft_id'),
  '42501', null, 'Référence non modifiable (droit de colonne)');
update public.properties set price_amount = 1 where id = :'rent_id';
-- DELETE sans politique correspondante : 0 ligne affectée (vérifié plus bas)
delete from public.properties where id = :'draft_id';
reset role;
select is((select price_amount from public.properties where id = :'rent_id'), 850000::bigint, 'Agent : le bien d''un collègue n''est pas modifié');
select is((select count(*)::int from public.properties where id = :'draft_id'), 1, 'Agent : suppression sans effet');

-- Photos : agent 1 sur bien d'agent 2
select tests.authenticate_as(:'agent1_id');
select throws_ok(format($$insert into public.property_media (property_id, storage_path) values (%L, %L)$$, :'rent_id', :'rent_id' || '/x.jpg'),
  '42501', null, 'Agent : ne peut pas ajouter de photo au bien d''un collègue');
select lives_ok(format($$insert into public.property_media (property_id, storage_path) values (%L, %L)$$, :'draft_id', :'draft_id' || '/d.jpg'),
  'Agent : ajoute une photo à son bien');
select lives_ok(format($$select public.set_property_amenities(%L, array['swimming_pool', 'garden'])$$, :'draft_id'), 'Agent : définit les équipements');
select throws_ok(format($$select public.set_property_amenities(%L, array['garden'])$$, :'rent_id'), '42501', null,
  'Agent : ne peut pas modifier les équipements d''un collègue');
reset role;

-- ---------------------------------------------------------------------------
-- Responsable commercial : publication
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'manager_id');
update public.properties set short_description = 'Villa lumineuse avec jardin et piscine.' where id = :'draft_id';
select lives_ok(format($$update public.properties set publication_status = 'published', is_featured = true where id = %L$$, :'draft_id'),
  'Responsable : publie et met en avant');
select lives_ok(format($$update public.properties set agent_id = %L where id = %L$$, :'agent2_id', :'draft_id'), 'Responsable : réaffecte un bien');
select lives_ok(format($$update public.properties set publication_status = 'unpublished' where id = %L$$, :'pub_id'), 'Responsable : retire une annonce');
delete from public.properties where id = :'pub_id';
reset role;
select is((select count(*)::int from public.properties where id = :'pub_id'), 1, 'Responsable : suppression sans effet');
select isnt((select unpublished_at from public.properties where id = :'pub_id'), null, 'unpublished_at renseigné');

select tests.authenticate_as_anon();
select is((select count(*)::int from public.public_properties where id = :'pub_id'), 0, 'Annonce retirée : invisible publiquement');
select is((select count(*)::int from public.public_properties where id = :'draft_id'), 1, 'Annonce publiée par le responsable : visible');
reset role;

-- Super admin : suppression définitive
select tests.authenticate_as(:'super_id');
select lives_ok(format($$delete from public.properties where id = %L$$, :'pub_id'), 'Super admin : suppression définitive');
reset role;
select is((select count(*)::int from public.properties where id = :'pub_id'), 0, 'Bien supprimé');

-- Audit des changements de statut
select ok(exists (select 1 from public.audit_logs where table_name = 'properties' and record_id = :'draft_id'
                    and new_data ->> 'publication_status' = 'published' and actor_id = :'manager_id'),
  'Publication journalisée avec son auteur');

select * from finish();
rollback;
