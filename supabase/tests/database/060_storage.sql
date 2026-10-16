-- Buckets et politiques Storage.
begin;
select no_plan();
select tests.reset_business_data();

select tests.create_user('agent.st1@test.sn', array['agent'], true) as agent1_id \gset
select tests.create_user('agent.st2@test.sn', array['agent'], true) as agent2_id \gset
select tests.create_user('admin.st@test.sn', array['admin']) as admin_id \gset
select tests.create_property(:'agent1_id', true, 'Villa publiée stockage') as pub_id \gset
select tests.create_property(:'agent1_id', false, 'Villa brouillon stockage') as draft_id \gset

-- ---------------------------------------------------------------------------
-- Configuration des buckets
-- ---------------------------------------------------------------------------
select is((select public from storage.buckets where id = 'property-images'), false, 'property-images est privé');
select is((select public from storage.buckets where id = 'property-documents'), false, 'property-documents est privé');
select is((select public from storage.buckets where id = 'agent-photos'), true, 'agent-photos est public');
select is((select public from storage.buckets where id = 'site-assets'), true, 'site-assets est public');
select ok(not exists (select 1 from storage.buckets where 'image/svg+xml' = any (allowed_mime_types)), 'SVG refusé dans tous les buckets (risque XSS)');
select is((select file_size_limit from storage.buckets where id = 'property-images'), 10485760::bigint, 'Photos : 10 Mo max');

-- Objets (insérés en tant que postgres pour simuler des fichiers existants)
insert into storage.objects (bucket_id, name) values
  ('property-images', :'pub_id' || '/cover.jpg'),          -- référencée par une photo publiée
  ('property-images', :'pub_id' || '/orphelin.jpg'),       -- non référencée
  ('property-images', :'draft_id' || '/brouillon.jpg'),
  ('property-documents', :'pub_id' || '/titre-foncier.pdf');
insert into public.property_media (property_id, storage_path) values (:'draft_id', :'draft_id' || '/brouillon.jpg');

-- ---------------------------------------------------------------------------
-- Lecture anonyme
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select is((select count(*)::int from storage.objects where name = :'pub_id' || '/cover.jpg'), 1, 'anon : photo d''une annonce publiée lisible');
select is((select count(*)::int from storage.objects where name = :'pub_id' || '/orphelin.jpg'), 0, 'anon : fichier non référencé illisible');
select is((select count(*)::int from storage.objects where name = :'draft_id' || '/brouillon.jpg'), 0, 'anon : photo de brouillon illisible');
select is((select count(*)::int from storage.objects where bucket_id = 'property-documents'), 0, 'anon : documents internes illisibles');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('property-images', %L)$$, :'pub_id' || '/pirate.jpg'),
  '42501', null, 'anon : téléversement interdit');
reset role;

-- ---------------------------------------------------------------------------
-- Agent 1 (responsable des biens)
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent1_id');
select is((select count(*)::int from storage.objects where name = :'draft_id' || '/brouillon.jpg'), 1, 'Agent : voit les photos de ses brouillons');
select is((select count(*)::int from storage.objects where bucket_id = 'property-documents'), 1, 'Agent : voit les documents de ses biens');
select lives_ok(format($$insert into storage.objects (bucket_id, name, owner) values ('property-images', %L, auth.uid())$$, :'draft_id' || '/nouvelle.webp'),
  'Agent : téléverse une photo pour son bien');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('property-images', %L)$$, :'draft_id' || '/script.php'),
  '42501', null, 'Agent : extension non autorisée refusée');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('property-images', %L)$$, :'draft_id' || '/sous/dossier.jpg'),
  '42501', null, 'Agent : sous-dossier refusé');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('property-images', 'pas-un-uuid/photo.jpg')$$,
  '42501', null, 'Agent : dossier hors convention refusé');
select lives_ok(format($$insert into storage.objects (bucket_id, name, owner) values ('agent-photos', %L, auth.uid())$$, :'agent1_id' || '/portrait.jpg'),
  'Agent : téléverse sa photo de profil');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('agent-photos', %L)$$, :'agent2_id' || '/portrait.jpg'),
  '42501', null, 'Agent : ne peut pas remplacer la photo d''un collègue');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('site-assets', 'logo/logo.png')$$,
  '42501', null, 'Agent : ne peut pas modifier les visuels du site');
reset role;

-- ---------------------------------------------------------------------------
-- Agent 2 (pas responsable)
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'agent2_id');
select throws_ok(format($$insert into storage.objects (bucket_id, name) values ('property-images', %L)$$, :'draft_id' || '/intrus.jpg'),
  '42501', null, 'Agent 2 : ne peut pas téléverser sur le bien d''un collègue');
select is((select count(*)::int from storage.objects where bucket_id = 'property-documents'), 0, 'Agent 2 : documents du collègue invisibles');
select is((select count(*)::int from storage.objects where name = :'draft_id' || '/brouillon.jpg'), 1,
  'Agent 2 : voit les photos du catalogue interne (properties.read_all)');
reset role;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select lives_ok($$insert into storage.objects (bucket_id, name, owner) values ('site-assets', 'logo/logo.png', auth.uid())$$, 'Admin : téléverse le logo');
select lives_ok(format($$insert into storage.objects (bucket_id, name, owner) values ('property-documents', %L, auth.uid())$$, :'draft_id' || '/mandat.pdf'),
  'Admin : téléverse un document interne');
reset role;

select * from finish();
rollback;
