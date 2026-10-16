-- Contraintes, relations, suppressions, valeurs dérivées.
begin;
select no_plan();
select tests.reset_business_data();

-- ---------------------------------------------------------------------------
-- RLS activé sur TOUTES les tables du schéma public
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0,
  'RLS est activé sur toutes les tables du schéma public'
);
select is(
  (select array_agg(tablename::text order by tablename) from pg_tables where schemaname = 'public' and not rowsecurity),
  null,
  'Aucune table publique sans RLS (liste vide)'
);

-- Aucun droit implicite d'anon sur les tables métier sensibles
select ok(not has_table_privilege('anon', 'public.properties', 'select'), 'anon : pas de SELECT sur properties');
select ok(not has_table_privilege('anon', 'public.leads', 'select'), 'anon : pas de SELECT sur leads');
select ok(not has_table_privilege('anon', 'public.leads', 'insert'), 'anon : pas d''INSERT sur leads');
select ok(not has_table_privilege('anon', 'public.inquiries', 'insert'), 'anon : pas d''INSERT sur inquiries');
select ok(not has_table_privilege('anon', 'public.lead_activities', 'select'), 'anon : pas de SELECT sur lead_activities');
select ok(not has_table_privilege('anon', 'public.audit_logs', 'select'), 'anon : pas de SELECT sur audit_logs');
select ok(not has_table_privilege('anon', 'public.profiles', 'select'), 'anon : pas de SELECT sur profiles');
select ok(not has_table_privilege('authenticated', 'public.audit_logs', 'insert'), 'authenticated : pas d''INSERT sur audit_logs');
select ok(not has_table_privilege('authenticated', 'public.user_roles', 'insert'), 'authenticated : pas d''INSERT direct sur user_roles');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'is_active', 'update'), 'authenticated : pas d''UPDATE de profiles.is_active');
select ok(not has_function_privilege('anon', 'public.submit_inquiry(text, text, text, text, uuid, public.inquiry_type, public.contact_method, boolean, text, jsonb)', 'execute'),
  'anon ne peut pas appeler submit_inquiry directement');
select ok(not has_function_privilege('authenticated', 'private.bootstrap_super_admin(text, text)', 'execute'),
  'authenticated ne peut pas appeler bootstrap_super_admin');
select ok(has_function_privilege('anon', 'public.search_properties(text, public.transaction_type, text[], uuid, uuid, uuid, uuid, bigint, bigint, smallint, smallint, numeric, numeric, text[], public.commercial_status[], boolean, boolean, text)', 'execute'),
  'anon peut appeler search_properties');

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
select tests.create_user('agent.c@test.sn', array['agent'], true) as agent_id \gset
select id as almadies from public.localities where slug = 'almadies' \gset
select id as dakar_city from public.localities where slug = 'dakar' and level = 'city' \gset
select id as dakar_region from public.localities where slug = 'dakar' and level = 'region' \gset
select id as ngor from public.localities where slug = 'ngor' and level = 'commune' \gset

-- ---------------------------------------------------------------------------
-- Référentiels
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public.localities where level = 'region' and country_code = 'SN'), 14, '14 régions du Sénégal');
select is((select count(*)::int from public.roles), 4, '4 rôles');
select throws_ok(
  format($$insert into public.localities (country_code, parent_id, level, name) values ('SN', %L, 'region', 'X')$$, :'dakar_city'),
  '23514', null, 'Une région ne peut pas avoir de parent');
select throws_ok(
  format($$insert into public.localities (country_code, parent_id, level, name) values ('SN', %L, 'commune', 'Commune invalide')$$, :'dakar_region'),
  '23514', null, 'Une commune doit dépendre d''une ville');
select lives_ok(
  format($$insert into public.localities (country_code, parent_id, level, name) values ('SN', %L, 'neighborhood', 'Quartier Test')$$, :'dakar_city'),
  'Un quartier peut dépendre directement d''une ville');
select is((select slug from public.localities where name = 'Quartier Test'), 'quartier-test', 'Slug de localité généré');

-- ---------------------------------------------------------------------------
-- Biens : contraintes et valeurs dérivées
-- ---------------------------------------------------------------------------
select tests.create_property(:'agent_id') as prop \gset

select matches((select reference from public.properties where id = :'prop'), '^ABS-V-[0-9]{7}$', 'Référence lisible générée (ABS-V-AA#####)');
select matches((select slug from public.properties where id = :'prop'), '^villa-de-test-aux-almadies-abs-v-[0-9]{7}$', 'Slug SEO généré et unique');
select is((select neighborhood_id from public.properties where id = :'prop'), :'almadies'::uuid, 'Quartier déduit');
select is((select commune_id from public.properties where id = :'prop'), :'ngor'::uuid, 'Commune déduite');
select is((select city_id from public.properties where id = :'prop'), :'dakar_city'::uuid, 'Ville déduite');
select is((select region_id from public.properties where id = :'prop'), :'dakar_region'::uuid, 'Région déduite');
select is((select publication_status::text from public.properties where id = :'prop'), 'draft', 'Brouillon par défaut');
select is((select commercial_status::text from public.properties where id = :'prop'), 'available', 'Disponible par défaut');
select ok((select search_vector @@ websearch_to_tsquery('public.french_unaccent', 'almadies') from public.properties where id = :'prop'),
  'Vecteur de recherche contient le quartier');

select throws_ok(
  format($$update public.properties set commercial_status = 'rented' where id = %L$$, :'prop'),
  '23514', null, 'Un bien en vente ne peut pas être « loué »');
select throws_ok(
  format($$update public.properties set transaction_type = 'rent' where id = %L$$, :'prop'),
  '23514', null, 'Location sans période de loyer refusée');
select throws_ok(
  format($$update public.properties set price_amount = null where id = %L$$, :'prop'),
  '23514', null, 'Prix requis sauf « prix sur demande »');
select lives_ok(
  format($$update public.properties set price_amount = null, price_on_request = true where id = %L$$, :'prop'),
  'Prix sur demande accepté');
select throws_ok(
  format($$update public.properties set latitude = null where id = %L$$, :'prop'),
  '23514', null, 'Latitude et longitude vont de pair');
select throws_ok(
  format($$update public.properties set price_amount = -5, price_on_request = false where id = %L$$, :'prop'),
  '23514', null, 'Prix négatif refusé');
select throws_ok(
  format($$insert into public.properties (title, property_type, transaction_type, price_amount, locality_id, slug) select 'Autre villa test', 'villa', 'sale', 1000, %L, slug from public.properties where id = %L$$, :'almadies', :'prop'),
  '23505', null, 'Slug unique');

-- Terrain : pièces neutralisées
select tests.create_property(:'agent_id', false, 'Terrain de test à Saly', 'sale', 'land', 25000000) as land \gset
select is((select bedrooms from public.properties where id = :'land'), null::smallint, 'Terrain : chambres neutralisées');

-- Publication impossible sans photo de couverture
select throws_ok(
  format($$update public.properties set publication_status = 'published' where id = %L$$, :'prop'),
  '23514', 'Publication impossible : le bien doit avoir au moins une photo de couverture.',
  'Publication refusée sans couverture');

-- ---------------------------------------------------------------------------
-- Photos : couverture unique et automatique, chemin contrôlé
-- ---------------------------------------------------------------------------
insert into public.property_media (property_id, storage_path) values (:'prop', :'prop' || '/a.jpg');
insert into public.property_media (property_id, storage_path, sort_order) values (:'prop', :'prop' || '/b.jpg', 1);
select is((select storage_path from public.property_media where property_id = :'prop' and is_cover), :'prop' || '/a.jpg',
  'La première photo devient automatiquement la couverture');
update public.property_media set is_cover = true where storage_path = :'prop' || '/b.jpg';
select is((select count(*)::int from public.property_media where property_id = :'prop' and is_cover), 1, 'Une seule couverture');
select is((select storage_path from public.property_media where property_id = :'prop' and is_cover), :'prop' || '/b.jpg', 'Nouvelle couverture appliquée');
select throws_ok(
  format($$insert into public.property_media (property_id, storage_path) values (%L, 'autre-dossier/x.jpg')$$, :'prop'),
  '23514', null, 'Le chemin doit commencer par l''identifiant du bien');
delete from public.property_media where storage_path = :'prop' || '/b.jpg';
select is((select storage_path from public.property_media where property_id = :'prop' and is_cover), :'prop' || '/a.jpg',
  'Suppression de la couverture : la photo suivante est promue');

update public.properties set publication_status = 'published', price_on_request = false, price_amount = 120000000 where id = :'prop';
select isnt((select published_at from public.properties where id = :'prop'), null, 'published_at renseigné à la publication');
select throws_ok(
  format($$delete from public.property_media where property_id = %L$$, :'prop'),
  '23514', null, 'Impossible de supprimer la dernière photo d''un bien publié');

-- ---------------------------------------------------------------------------
-- Prospects : contraintes
-- ---------------------------------------------------------------------------
select throws_ok($$insert into public.leads (full_name) values ('Sans Contact')$$, '23514', null, 'Prospect : e-mail ou téléphone requis');
select throws_ok($$insert into public.leads (full_name, phone) values ('Mauvais Tel', '12345')$$, '23514', null, 'Téléphone non E.164 refusé');
insert into public.leads (full_name, phone, email) values ('Fatou Diop', '77 123 45 67', 'Fatou@Example.SN');
select is((select phone from public.leads where full_name = 'Fatou Diop'), '+221771234567', 'Téléphone sénégalais normalisé en E.164');
select is((select email from public.leads where full_name = 'Fatou Diop'), 'fatou@example.sn', 'E-mail normalisé en minuscules');
select throws_ok($$insert into public.leads (full_name, phone, budget_min, budget_max) values ('Budget', '+221770000001', 10, 5)$$,
  '23514', null, 'Budget min ≤ max');

-- ---------------------------------------------------------------------------
-- Suppressions : cascades et SET NULL
-- ---------------------------------------------------------------------------
select id as lead_id from public.leads where full_name = 'Fatou Diop' \gset
insert into public.inquiries (lead_id, property_id, message) values (:'lead_id', :'land', 'Intéressée');
insert into public.lead_activities (lead_id, activity_type, content) values (:'lead_id', 'note', 'note');

delete from public.properties where id = :'land';
select is((select property_id from public.inquiries where lead_id = :'lead_id' limit 1), null::uuid,
  'Suppression d''un bien : la demande est conservée (property_id = NULL)');

select is((select count(*)::int from public.property_media where property_id = :'prop'), 1, 'Photos présentes avant suppression');
update public.properties set publication_status = 'archived' where id = :'prop';
delete from public.properties where id = :'prop';
select is((select count(*)::int from public.property_media where property_id = :'prop'), 0, 'Suppression d''un bien : photos supprimées en cascade');

delete from public.leads where id = :'lead_id';
select is((select count(*)::int from public.inquiries where lead_id = :'lead_id'), 0, 'Suppression d''un prospect : demandes supprimées');
select is((select count(*)::int from public.lead_activities where lead_id = :'lead_id'), 0, 'Suppression d''un prospect : historique supprimé');

-- Normalisation téléphone
select is(private.normalize_phone('00221 77 000 11 22'), '+221770001122', 'Préfixe 00 converti');
select is(private.normalize_phone('+33 6 12 34 56 78'), '+33612345678', 'Numéro international conservé');
select is(private.normalize_phone('abc'), null, 'Numéro invalide -> NULL');
select is(private.slugify('Villa à Saly — 4 ch.'), 'villa-a-saly-4-ch', 'slugify retire accents et ponctuation');

select * from finish();
rollback;
