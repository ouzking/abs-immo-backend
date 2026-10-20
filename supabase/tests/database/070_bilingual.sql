-- Annonces bilingues FR/EN (contrat 1.1.0).
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('agent.en@test.sn', array['agent'], true) as agent_id \gset
select tests.create_user('agent.en2@test.sn', array['agent'], true) as agent2_id \gset
select tests.create_property(:'agent_id', true, 'Villa avec piscine aux Almadies') as villa \gset
select tests.create_property(:'agent_id', true, 'Appartement meublé', 'rent', 'apartment', 900000) as appart \gset
select tests.create_property(:'agent_id', false, 'Brouillon bilingue') as draft \gset

-- ---------------------------------------------------------------------------
-- Saisie des traductions
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent_id');
select lives_ok(format($$update public.properties
  set title_en = 'Villa with swimming pool in Almadies',
      short_description_en = 'Bright villa with a large garden and a private pool.',
      description_en = 'Spacious family home close to the beach.',
      seo_title_en = 'Villa for sale in Almadies, Dakar'
  where id = %L$$, :'villa'), 'Agent : saisit la version anglaise de son annonce');
select throws_ok(format($$update public.properties set title_en = 'Zut' where id = %L$$, :'villa'),
  '23514', null, 'Titre anglais : 5 caractères minimum');
update public.properties set title_en = 'Hacked title' where id = :'draft';
reset role;
select tests.authenticate_as(:'agent2_id');
update public.properties set title_en = 'Hijacked listing' where id = :'villa';
reset role;
select is((select title_en from public.properties where id = :'villa'), 'Villa with swimming pool in Almadies',
  'Agent 2 : ne peut pas modifier la traduction d''un collègue (RLS)');
select isnt((select updated_at from public.properties where id = :'villa'), null, 'updated_at maintenu');

-- ---------------------------------------------------------------------------
-- Exposition publique
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select is((select title_en from public.public_properties where id = :'villa'), 'Villa with swimming pool in Almadies', 'Vue publique : title_en');
select is((select has_english from public.public_properties where id = :'villa'), true, 'Vue publique : has_english vrai');
select is((select has_english from public.public_properties where id = :'appart'), false, 'Sans traduction : has_english faux (repli FR)');
select is((select property_type_label_en from public.public_properties where id = :'appart'), 'Apartment', 'Libellé anglais du type');
select is((public.get_public_property(p_slug => (select slug from public.public_properties where id = :'villa')) ->> 'title_en'),
  'Villa with swimming pool in Almadies', 'Détail : title_en');
select ok(not (public.get_public_property(p_slug => (select slug from public.public_properties where id = :'villa')) ? 'search_vector_en'),
  'Détail : vecteur anglais non exposé');
select is((public.get_public_filters() #>> '{property_types,0,label_en}'), 'Apartment', 'Filtres : libellé anglais des types');

-- ---------------------------------------------------------------------------
-- Recherche bilingue (même RPC, même signature)
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.search_properties(p_query => 'swimming pool')), 1, 'Recherche EN sur le contenu traduit');
select is((select count(*)::int from public.search_properties(p_query => 'pools')), 1, 'Recherche EN avec racinisation (pools → pool)');
select is((select count(*)::int from public.search_properties(p_query => 'apartment')), 1, 'Recherche EN par type même sans traduction');
select is((select count(*)::int from public.search_properties(p_query => 'piscine')), 1, 'Recherche FR inchangée');
select is((select count(*)::int from public.search_properties(p_query => 'almadies')), 2, 'Nom de lieu trouvé dans les deux langues');
select is((select count(*)::int from public.search_properties(p_query => 'hacked')), 0, 'Brouillon jamais trouvé');
select is((select id from public.search_properties(p_query => 'swimming pool', p_sort => 'relevance') limit 1), :'villa'::uuid,
  'Tri par pertinence avec requête anglaise');
reset role;

-- Le vecteur anglais suit les changements de localité
update public.properties set locality_id = (select id from public.localities where slug = 'saly' and level = 'city')
 where id = :'appart';
select ok((select search_vector_en @@ websearch_to_tsquery('public.english_unaccent', 'saly') from public.properties where id = :'appart'),
  'Vecteur anglais recalculé après changement de localité');

select * from finish();
rollback;
