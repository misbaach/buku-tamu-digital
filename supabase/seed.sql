-- Data contoh KHUSUS pengembangan lokal (`pnpm db:reset`). Tidak pernah dijalankan di produksi.
-- Admin lokal: admin@buku-tamu.test / admin-lokal-2026
-- Akun tanpa peran admin (untuk uji penolakan): bukan-admin@buku-tamu.test / bukan-admin-2026
-- Kode Acara contoh: K7PM2X

do $$
declare
  v_admin uuid := '00000000-0000-4000-8000-000000000001';
  v_not_admin uuid := '00000000-0000-4000-8000-000000000002';
  v_event uuid := '00000000-0000-4000-8000-0000000000e1';
  v_groups uuid[];
  v_first text[] := array['Budi','Siti','Agus','Dewi','Rina','Andi','Wulan','Hendra','Lestari','Yusuf',
                          'Ratna','Fajar','Indah','Bayu','Putri','Rizky','Maya','Dimas','Sari','Teguh'];
  v_last  text[] := array['Santoso','Rahayu','Wijaya','Pratama','Kusuma','Hidayat','Saputra','Lestari',
                          'Nugroho','Permata','Siregar','Halim','Gunawan','Utami','Setiawan'];
  i integer;
  v_cat public.guest_category;
  v_rsvp public.rsvp_status;
begin
  -- Admin (pola insert auth.users untuk seed lokal; kolom token string kosong wajib diisi, bukan NULL).
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_admin, 'authenticated', 'authenticated', 'admin@buku-tamu.test',
    extensions.crypt('admin-lokal-2026', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"], "role": "admin"}', '{"full_name": "Admin Lokal"}', now(), now(),
    '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_admin, v_admin::text,
          jsonb_build_object('sub', v_admin::text, 'email', 'admin@buku-tamu.test', 'email_verified', true),
          'email', now(), now(), now());

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_not_admin, 'authenticated', 'authenticated', 'bukan-admin@buku-tamu.test',
    extensions.crypt('bukan-admin-2026', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{"role": "admin"}', now(), now(),
    '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_not_admin, v_not_admin::text,
          jsonb_build_object('sub', v_not_admin::text, 'email', 'bukan-admin@buku-tamu.test', 'email_verified', true),
          'email', now(), now(), now());

  insert into public.events (id, code, name, couple_names, event_date, venue, created_by)
  values (v_event, 'K7PM2X', 'Resepsi Rina & Bayu', 'Rina & Bayu', current_date, 'Gedung Serbaguna Melati', v_admin);
  insert into public.event_members (event_id, user_id) values (v_event, v_admin);

  insert into public.ticket_number_settings (event_id, category, prefix, start_number, digits)
  values (v_event, 'vip', 'VIP-', 1, 3), (v_event, 'vvip', 'VVIP-', 1, 3);
  insert into public.checkin_settings (event_id) values (v_event);
  insert into public.greeting_configs (event_id, category, popup)
  values (v_event, 'regular', '{"title": "Selamat datang", "body": "Terima kasih telah hadir, {{nama}}."}'),
         (v_event, 'vip', '{"title": "Selamat datang", "body": "Terima kasih telah hadir, {{nama}}."}'),
         (v_event, 'vvip', '{"title": "Selamat datang", "body": "Terima kasih telah hadir, {{nama}}."}');

  with g as (
    insert into public.guest_groups (event_id, name, description)
    values (v_event, 'Keluarga Mempelai Wanita', null),
           (v_event, 'Keluarga Mempelai Pria', null),
           (v_event, 'Teman Kantor', 'Rekan kerja Rina'),
           (v_event, 'Teman Kuliah', null),
           (v_event, 'Tetangga', null)
    returning id
  )
  select array_agg(id) into v_groups from g;

  for i in 1..300 loop
    v_cat := case when i <= 10 then 'vvip' when i <= 40 then 'vip' else 'regular' end;
    v_rsvp := case when i % 10 in (0, 1) then 'unconfirmed' when i % 10 = 2 then 'not_going' else 'going' end;
    insert into public.guests (event_id, name, phone, category, group_id, invited_pax, special_number, rsvp_status, rsvp_pax)
    values (
      v_event,
      v_first[1 + (i % array_length(v_first, 1))] || ' ' || v_last[1 + ((i * 7) % array_length(v_last, 1))] || ' ' || i,
      case when i % 4 = 0 then null else '+62812' || lpad(i::text, 7, '0') end,
      v_cat,
      v_groups[1 + (i % array_length(v_groups, 1))],
      1 + (i % 3),
      -- VVIP 1-8 dan VIP 11-30 sudah bernomor; sisanya untuk uji "Terapkan Nomor Urut".
      case when i <= 8 then 'VVIP-' || lpad(i::text, 3, '0')
           when i between 11 and 30 then 'VIP-' || lpad((i - 10)::text, 3, '0') end,
      v_rsvp,
      case when v_rsvp = 'going' then 1 + (i % 3) end
    );
  end loop;
end;
$$;
