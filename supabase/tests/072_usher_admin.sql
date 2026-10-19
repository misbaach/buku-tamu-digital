-- Kelola Penerima Tamu (FR-R-01, FR-R-02): PIN sekali tampil, reset PIN, QR Login, nonaktif/hapus = Cabut
-- semua perangkat, audit; validasi isi pengaturan check-in dan pop-up sapaan (FR-R-03, FR-R-04, FR-P-01).
begin;
select plan(38);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Usher', :'admin_id') as ev \gset
select code as ev_code from public.events where id = :'ev' \gset
select tests.create_event('Acara Lain', :'admin_id') as ev2 \gset

-- ---------------------------------------------------------------------------------------------
-- Tambah usher: PIN AB-XXXX-XXXX hanya dikembalikan sekali, yang tersimpan hanya bcrypt rahasianya
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select public.admin_create_usher(:'ev', '  Budi  ', 'check_in') as created \gset
reset role;
select :'created'::jsonb ->> 'usher_id' as usher, :'created'::jsonb ->> 'pin' as pin \gset

select matches(:'pin'::text, '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{2}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$',
               'PIN berbentuk AB-XXXX-XXXX dari alfabet tanpa karakter mirip');
select is((select name from public.ushers where id = :'usher'), 'Budi', 'nama dirapikan');
select is((select pin_selector from public.ushers where id = :'usher'), split_part(:'pin', '-', 1), 'ID usher = 2 karakter pertama PIN');
select matches((select pin_hash from public.ushers where id = :'usher'), '^\$2[aby]\$10\$', 'yang tersimpan hash bcrypt biaya 10');
select ok((select pin_hash from public.ushers where id = :'usher') !~ replace(substr(:'pin', 4), '-', ''),
          'rahasia tidak tersimpan sebagai teks');
select ok(private.verify_secret(replace(substr(:'pin', 4), '-', ''), (select pin_hash from public.ushers where id = :'usher')),
          'hash cocok dengan 8 karakter rahasia PIN');
select is((select count(*)::integer from public.audit_logs where action = 'usher_created' and entity_id = :'usher'), 1,
          'tambah usher diaudit');
select ok((select after::text from public.audit_logs where action = 'usher_created' and entity_id = :'usher')
            !~ replace(substr(:'pin', 4), '-', ''), 'audit tidak memuat rahasia PIN');
select is(public.svc_usher_login('pin', '10.9.0.1', :'ev_code', split_part(:'pin', '-', 1),
                                 replace(substr(:'pin', 4), '-', '')) ->> 'outcome', 'ok',
          'PIN dari admin_create_usher bisa dipakai login');
select ok(not has_column_privilege('authenticated', 'public.ushers', 'pin_hash', 'select'),
          'pin_hash tidak bisa dibaca role API');

-- ---------------------------------------------------------------------------------------------
-- Reset PIN: ID usher tetap, PIN lama langsung tidak berlaku
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select public.admin_reset_usher_pin(:'usher') ->> 'pin' as pin2 \gset
reset role;
select is(split_part(:'pin2', '-', 1), split_part(:'pin', '-', 1), 'reset PIN mempertahankan ID usher');
select isnt(:'pin2'::text, :'pin'::text, 'reset PIN menghasilkan rahasia baru');
select is(public.svc_usher_login('pin', '10.9.0.2', :'ev_code', split_part(:'pin', '-', 1),
                                 replace(substr(:'pin', 4), '-', '')), '{"outcome": "invalid"}'::jsonb,
          'PIN lama ditolak setelah reset');
select is(public.svc_usher_login('pin', '10.9.0.2', :'ev_code', split_part(:'pin2', '-', 1),
                                 replace(substr(:'pin2', 4), '-', '')) ->> 'outcome', 'ok', 'PIN baru berlaku');
select is((select count(*)::integer from public.audit_logs where action = 'usher_pin_reset' and entity_id = :'usher'), 1,
          'reset PIN diaudit');

-- ---------------------------------------------------------------------------------------------
-- QR Login: token ≥ 128 bit, hanya hash yang disimpan, berlaku 5 menit, QR baru membatalkan yang lama
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select public.admin_create_login_qr(:'usher') as qr1 \gset
select public.admin_create_login_qr(:'usher') as qr2 \gset
reset role;
select ok(length(:'qr1'::jsonb ->> 'token') >= 43, 'token QR Login 32 byte (256 bit) base64url');
select is((select count(*)::integer from public.usher_login_tokens where token_hash = private.sha256_hex(:'qr2'::jsonb ->> 'token')), 1,
          'yang disimpan hash SHA-256 token');
select is((select count(*)::integer from public.usher_login_tokens where token_hash = :'qr2'::jsonb ->> 'token'), 0,
          'token mentah tidak disimpan');
select ok((:'qr2'::jsonb ->> 'expires_at')::timestamptz between now() + interval '299 seconds' and now() + interval '301 seconds',
          'QR Login berlaku 5 menit');
select is(public.svc_usher_login('qr', '10.9.0.3', p_token => :'qr1'::jsonb ->> 'token'), '{"outcome": "invalid"}'::jsonb,
          'QR sebelumnya tidak berlaku setelah QR baru ditampilkan');
select is(public.svc_usher_login('qr', '10.9.0.3', p_token => :'qr2'::jsonb ->> 'token') ->> 'outcome', 'ok', 'QR terbaru berlaku');

-- ---------------------------------------------------------------------------------------------
-- Nonaktif dan hapus usher = Cabut (tingkat quarantine) semua perangkatnya
-- ---------------------------------------------------------------------------------------------
select tests.create_device(:'ev', :'usher', 'X') as dev1 \gset
select tests.create_device(:'ev', :'usher', 'Y') as dev2 \gset
select tests.authenticate_as(:'admin_id');
select is(public.admin_update_usher(:'usher', '{"is_active": false}') ->> 'revoked_devices', '5',
          'menonaktifkan usher mencabut semua perangkatnya (3 dari login di atas + 2)');
reset role;
select is((select count(*)::integer from public.devices where usher_id = :'usher' and revoke_mode = 'quarantine'), 5,
          'semua perangkat usher bertingkat Cabut (quarantine)');
select is((select count(*)::integer from public.audit_logs where action = 'device_revoked' and event_id = :'ev'), 5,
          'setiap pencabutan perangkat diaudit');
select tests.authenticate_as(:'admin_id');
select throws_ok(format($$ select public.admin_create_login_qr(%L) $$, :'usher'), '22023', null,
                 'QR Login tidak bisa dibuat untuk usher nonaktif');
select lives_ok(format($$ select public.admin_update_usher(%L, '{"is_active": true, "name": "Budi S", "mode": "check_out"}') $$, :'usher'),
                'usher bisa diaktifkan lagi dan diubah nama/modenya');
select throws_ok(format($$ select public.admin_update_usher(%L, '{"pin_hash": "x"}') $$, :'usher'), '22023', null,
                 'kolom selain name/mode/is_active ditolak');
select public.admin_create_usher(:'ev', 'Citra') ->> 'usher_id' as usher_c \gset
reset role;
select tests.create_device(:'ev', :'usher_c', 'Z') as dev3 \gset
select tests.authenticate_as(:'admin_id');
select is(public.admin_delete_usher(:'usher_c') ->> 'revoked_devices', '1', 'menghapus usher mencabut perangkatnya');
reset role;
select ok((select deleted_at is not null and not is_active from public.ushers where id = :'usher_c'), 'usher dihapus lunak');
select throws_ok(format($$ insert into public.ushers (event_id, name, pin_selector, pin_hash)
                           values (%L, 'Penyalin', (select pin_selector from public.ushers where id = %L), 'x') $$, :'ev', :'usher_c'),
                 '23505', null, 'ID usher milik usher yang sudah dihapus tidak dipakai ulang');

-- ---------------------------------------------------------------------------------------------
-- Isolasi dan acara diarsipkan
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.admin_create_usher(%L, 'Penyusup') $$, :'ev'), '42501', null,
                 'Admin acara lain tidak bisa menambah usher');
select throws_ok(format($$ select public.admin_reset_usher_pin(%L) $$, :'usher'), '42501', null,
                 'Admin acara lain tidak bisa mereset PIN');
reset role;
update public.events set archived_at = now() where id = :'ev2';
select tests.authenticate_as(:'admin_id');
select throws_ok(format($$ select public.admin_create_usher(%L, 'Telat') $$, :'ev2'), '22023', null,
                 'usher tidak bisa ditambah di acara yang diarsipkan');

-- ---------------------------------------------------------------------------------------------
-- Pengaturan check-in dan pop-up sapaan divalidasi ulang di DB (prd.md 10.4)
-- ---------------------------------------------------------------------------------------------
select lives_ok(format($$ update public.checkin_settings set allow_multi_checkin = true,
  print_ticket = '{"enabled": true, "fields": ["guest_name", "ticket_number", "pax"], "categories": ["vip", "vvip"], "copies": 2}'
  where event_id = %L $$, :'ev'), 'Admin menyimpan pengaturan check-in yang sah');
select throws_ok(format($$ update public.checkin_settings set
  print_ticket = '{"enabled": true, "fields": ["guest_phone"], "categories": ["vip"], "copies": 1}' where event_id = %L $$, :'ev'),
  '23514', null, 'informasi tiket di luar daftar ditolak (telepon tidak boleh dicetak)');
select throws_ok(format($$ update public.checkin_settings set
  print_ticket = '{"enabled": true, "fields": ["guest_name"], "categories": ["vip"], "copies": 4}' where event_id = %L $$, :'ev'),
  '23514', null, 'jumlah salinan di atas 3 ditolak');
select lives_ok(format($$ update public.greeting_configs set popup = jsonb_build_object(
  'title', 'Selamat datang, {{nama}}', 'body', 'Terima kasih.', 'layout', 'photo_round',
  'photo_path', %L || '/vvip/0b8f5f0e-3f43-4f4a-9a59-6f1f1d2b7c11.jpg', 'photo_version', 1)
  where event_id = %L and category = 'vvip' $$, :'ev', :'ev'), 'Admin menyimpan pop-up sapaan yang sah');
select throws_ok(format($$ update public.greeting_configs set popup = jsonb_build_object(
  'title', 'Halo', 'photo_path', %L || '/vvip/0b8f5f0e-3f43-4f4a-9a59-6f1f1d2b7c11.jpg')
  where event_id = %L and category = 'vvip' $$, :'ev2', :'ev'), '23514', null,
  'foto milik acara lain tidak bisa ditautkan ke sapaan');
reset role;

select * from finish();
rollback;
