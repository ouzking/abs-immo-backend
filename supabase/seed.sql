-- =============================================================================
-- Données de DÉMONSTRATION — environnement LOCAL uniquement.
-- Exécuté par `supabase start` / `supabase db reset`. JAMAIS poussé en
-- production (`supabase db push` n'inclut pas le seed).
--
-- Comptes (mot de passe commun : AbsImmo-Local-2026) :
--   superadmin@abs-immo.test  super_admin
--   admin@abs-immo.test       admin
--   manager@abs-immo.test     sales_manager (+ fiche agent)
--   agent1@abs-immo.test      agent (+ fiche agent)
--   agent2@abs-immo.test      agent (+ fiche agent)
-- =============================================================================

do $$
declare
  v_pwd text := extensions.crypt('AbsImmo-Local-2026', extensions.gen_salt('bf'));
  u record;
begin
  for u in select * from (values
    ('00000000-0000-4000-a000-000000000001'::uuid, 'superadmin@abs-immo.test', 'Aminata Sow',   'super_admin',   false),
    ('00000000-0000-4000-a000-000000000002'::uuid, 'admin@abs-immo.test',      'Ibrahima Diallo','admin',        false),
    ('00000000-0000-4000-a000-000000000003'::uuid, 'manager@abs-immo.test',    'Khady Ndiaye',  'sales_manager', true),
    ('00000000-0000-4000-a000-000000000004'::uuid, 'agent1@abs-immo.test',     'Ousmane Faye',  'agent',         true),
    ('00000000-0000-4000-a000-000000000005'::uuid, 'agent2@abs-immo.test',     'Mariama Ba',    'agent',         true)
  ) as t(id, email, full_name, role, is_agent) loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change, email_change_token_new)
    values ('00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email, v_pwd, now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', u.full_name),
            now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), u.id, u.id::text, 'email',
            jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true), now(), now(), now());
    insert into public.user_roles (user_id, role_code) values (u.id, u.role);
    if u.is_agent then
      insert into public.agents (profile_id, slug, display_name, job_title, public_phone, whatsapp_phone, public_email, bio)
      values (u.id, private.slugify(u.full_name), u.full_name,
              case u.role when 'sales_manager' then 'Responsable commerciale' else 'Conseiller immobilier' end,
              '+22177' || lpad((abs(hashtext(u.email)) % 10000000)::text, 7, '0'),
              '+22177' || lpad((abs(hashtext(u.email)) % 10000000)::text, 7, '0'),
              u.email, 'Conseiller ABS IMMO & SERVICES.');
    end if;
  end loop;
end $$;

update public.agency_settings set
  legal_name = 'ABS IMMO & SERVICES SARL',
  phone = '+221338001122',
  whatsapp_phone = '+221770001122',
  email = 'contact@abs-immo.test',
  address_line = 'Route des Almadies, Dakar',
  social_links = '{"facebook":"https://facebook.com/","instagram":"https://instagram.com/"}';

-- Biens de démonstration
do $$
declare
  r record;
  v_id uuid;
begin
  for r in select * from (values
    ('Villa contemporaine avec piscine aux Almadies', 'villa', 'sale', 450000000::bigint, null, 'almadies', 5, 4, 600,
     'Villa d''architecte avec piscine, jardin paysager et vue dégagée.', '00000000-0000-4000-a000-000000000004'::uuid, true, 'available', true),
    ('Appartement F4 meublé à Mermoz', 'apartment', 'rent', 850000, 'month', 'mermoz', 3, 2, 140,
     'Appartement lumineux entièrement meublé, proche VDN.', '00000000-0000-4000-a000-000000000004'::uuid, true, 'available', false),
    ('Terrain titré de 500 m² à Saly', 'land', 'sale', 35000000, null, 'saly', null, null, 500,
     'Terrain avec titre foncier, idéal résidence secondaire.', '00000000-0000-4000-a000-000000000005'::uuid, true, 'available', false),
    ('Bureaux climatisés au Plateau', 'office', 'rent', 2500000, 'month', 'plateau', null, 2, 220,
     'Plateau de bureaux cloisonné au cœur du quartier d''affaires.', '00000000-0000-4000-a000-000000000005'::uuid, true, 'reserved', false),
    ('Local commercial au Point E', 'commercial', 'rent', 1200000, 'month', 'point-e', null, 1, 90,
     'Local en rez-de-chaussée avec vitrine sur rue passante.', '00000000-0000-4000-a000-000000000003'::uuid, true, 'available', false),
    ('Maison familiale vendue à Ouakam', 'house', 'sale', 120000000, null, 'ouakam', 4, 3, 300,
     'Maison R+1 sur 300 m², quartier calme.', '00000000-0000-4000-a000-000000000004'::uuid, true, 'sold', false),
    ('Villa en préparation à Ngor', 'villa', 'sale', 300000000, null, 'ngor-village', 4, 3, 400,
     'Fiche en cours de rédaction.', '00000000-0000-4000-a000-000000000005'::uuid, false, 'available', false)
  ) as t(title, ptype, trans, price, period, loc, beds, baths, surface, short_desc, agent, publish, cstatus, featured) loop
    insert into public.properties (title, short_description, description, property_type, transaction_type, price_amount,
                                   rent_period, bedrooms, bathrooms, surface_area, locality_id, agent_id,
                                   latitude, longitude, address_visibility, legal_status)
    values (r.title, r.short_desc, r.short_desc || ' Contactez ABS IMMO & SERVICES pour une visite.', r.ptype,
            r.trans::public.transaction_type, r.price, r.period::public.rent_period, r.beds, r.baths, r.surface,
            (select id from public.localities where slug = r.loc order by level desc limit 1), r.agent,
            14.70 + random() * 0.08, -17.50 + random() * 0.05, 'approximate',
            case when r.ptype in ('land', 'villa', 'house') then 'titre_foncier'::public.property_legal_status end)
    returning id into v_id;

    insert into public.property_media (property_id, storage_path, alt_text, sort_order)
    values (v_id, v_id || '/demo-1.jpg', r.title, 0), (v_id, v_id || '/demo-2.jpg', r.title || ' — intérieur', 1);

    insert into public.property_amenities (property_id, amenity_code)
    select v_id, unnest(case r.ptype
      when 'villa' then array['swimming_pool', 'garden', 'air_conditioning', 'security_guard', 'parking']
      when 'apartment' then array['air_conditioning', 'elevator', 'furnished_kitchen', 'internet']
      when 'office' then array['air_conditioning', 'internet', 'elevator', 'parking']
      else array['parking'] end);

    if r.publish then
      update public.properties
         set publication_status = 'published', commercial_status = r.cstatus::public.commercial_status, is_featured = r.featured
       where id = v_id;
    end if;
  end loop;
end $$;

-- Quelques prospects
select public.submit_inquiry(p_full_name => 'Cheikh Mbaye', p_phone => '77 123 45 67', p_email => 'cheikh@example.sn',
  p_message => 'Bonjour, la villa est-elle toujours disponible ?',
  p_property_id => (select id from public.properties where title like 'Villa contemporaine%'), p_inquiry_type => 'availability',
  p_ip_hash => 'seed');
select public.submit_viewing_request(p_full_name => 'Ndeye Sarr', p_phone => '78 987 65 43',
  p_property_id => (select id from public.properties where title like 'Appartement F4%'),
  p_preferred_date => current_date + 2, p_preferred_time_slot => 'afternoon', p_ip_hash => 'seed');
select public.submit_inquiry(p_full_name => 'Jean Dupont', p_email => 'jean.dupont@example.fr', p_phone => '+33 6 12 34 56 78',
  p_message => 'Je cherche un terrain sur la Petite Côte.', p_inquiry_type => 'general', p_ip_hash => 'seed');
