-- =============================================================================
-- ABS IMMO & SERVICES — Migration 0900 : Supabase Storage
-- -----------------------------------------------------------------------------
-- Bucket              Public  Chemin                          Lecture                         Écriture
-- property-images     NON     <property_id>/<fichier>         anon : photos d'annonces        can_edit_property
--                                                             publiées uniquement (URL signée)
--                                                             staff : can_read_property
-- property-documents  NON     <property_id>/<fichier>         can_edit_property               can_edit_property
-- agent-photos        OUI     <profile_id>/<fichier>          publique                        soi-même ou agents.manage
-- site-assets         OUI     <dossier>/<fichier>             publique                        settings.manage
--
-- property-images est volontairement PRIVÉ : un bucket public rendrait
-- accessibles les photos des brouillons à quiconque connaît le chemin.
-- Le site public obtient des URL signées (createSignedUrls) qui ne sont
-- délivrées que pour les photos d'annonces publiées (politique ci-dessous).
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('property-images',    'property-images',    false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'image/avif']),
  ('property-documents', 'property-documents', false, 20971520, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp',
                                                                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('agent-photos',       'agent-photos',       true,  3145728,  array['image/jpeg', 'image/png', 'image/webp']),
  ('site-assets',        'site-assets',        true,  5242880,  array['image/jpeg', 'image/png', 'image/webp', 'image/x-icon', 'image/vnd.microsoft.icon'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Le fichier est-il une photo référencée d'une annonce publiée ?
create or replace function private.is_public_property_image(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.property_media m
    join public.properties p on p.id = m.property_id
    where m.storage_path = p_name and p.publication_status = 'published'
  );
$$;

-- Extension de fichier autorisée (défense en profondeur, en plus des types MIME du bucket).
create or replace function private.has_allowed_extension(p_name text, p_extensions text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(substring(p_name from '\.([A-Za-z0-9]+)$')) = any (p_extensions);
$$;

grant execute on function private.is_public_property_image(text) to anon, authenticated;
grant execute on function private.has_allowed_extension(text, text[]) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- property-images
-- -----------------------------------------------------------------------------
create policy "property_images_public_read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'property-images' and private.is_public_property_image(name));

create policy "property_images_staff_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'property-images'
         and private.can_read_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_images_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'property-images'
              and array_length(storage.foldername(name), 1) = 1
              and private.has_allowed_extension(name, array['jpg', 'jpeg', 'png', 'webp', 'avif'])
              and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_images_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'property-images'
         and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])))
  with check (bucket_id = 'property-images'
              and private.has_allowed_extension(name, array['jpg', 'jpeg', 'png', 'webp', 'avif'])
              and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_images_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'property-images'
         and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

-- -----------------------------------------------------------------------------
-- property-documents (strictement interne)
-- -----------------------------------------------------------------------------
create policy "property_documents_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'property-documents'
         and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_documents_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'property-documents'
              and array_length(storage.foldername(name), 1) = 1
              and private.has_allowed_extension(name, array['pdf', 'jpg', 'jpeg', 'png', 'webp', 'docx'])
              and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_documents_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'property-documents'
         and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])))
  with check (bucket_id = 'property-documents'
              and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

create policy "property_documents_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'property-documents'
         and private.can_edit_property(private.try_uuid((storage.foldername(name))[1])));

-- -----------------------------------------------------------------------------
-- agent-photos (bucket public : lecture par URL publique sans politique)
-- -----------------------------------------------------------------------------
create policy "agent_photos_staff_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'agent-photos' and (select private.is_active_staff()));

create policy "agent_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'agent-photos'
              and private.has_allowed_extension(name, array['jpg', 'jpeg', 'png', 'webp'])
              and (((storage.foldername(name))[1] = (select auth.uid())::text and (select private.is_active_staff()))
                   or (select private.has_permission('agents.manage'))));

create policy "agent_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'agent-photos'
         and (((storage.foldername(name))[1] = (select auth.uid())::text and (select private.is_active_staff()))
              or (select private.has_permission('agents.manage'))))
  with check (bucket_id = 'agent-photos'
              and (((storage.foldername(name))[1] = (select auth.uid())::text and (select private.is_active_staff()))
                   or (select private.has_permission('agents.manage'))));

create policy "agent_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'agent-photos'
         and (((storage.foldername(name))[1] = (select auth.uid())::text and (select private.is_active_staff()))
              or (select private.has_permission('agents.manage'))));

-- -----------------------------------------------------------------------------
-- site-assets (logo, visuels du site)
-- -----------------------------------------------------------------------------
create policy "site_assets_staff_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'site-assets' and (select private.is_active_staff()));

create policy "site_assets_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'site-assets'
              and private.has_allowed_extension(name, array['jpg', 'jpeg', 'png', 'webp', 'ico'])
              and (select private.has_permission('settings.manage')));

create policy "site_assets_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'site-assets' and (select private.has_permission('settings.manage')))
  with check (bucket_id = 'site-assets' and (select private.has_permission('settings.manage')));

create policy "site_assets_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'site-assets' and (select private.has_permission('settings.manage')));
