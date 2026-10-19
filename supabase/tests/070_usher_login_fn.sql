-- Login usher sisi DB (FR-R-02, FR-R-09, FR-R-10, 11.5): selector + verifier, tepat satu bcrypt per percobaan,
-- respons gagal identik, blokir (IP + Kode Acara) dan per IP sebelum bcrypt, peringatan per event, QR Login.
begin;
select plan(51);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Login', :'admin_id') as ev \gset
select code as ev_code from public.events where id = :'ev' \gset
select tests.create_event('Acara Lain', :'admin_id') as ev2 \gset
select code as ev2_code from public.events where id = :'ev2' \gset
select tests.create_usher(:'ev', 'Usher Satu', 'AB', 'ABCDEFGH') as usher \gset
select tests.create_usher(:'ev', 'Usher Nonaktif', 'CD', 'ABCDEFGH') as usher_off \gset
update public.ushers set is_active = false where id = :'usher_off';
select tests.create_usher(:'ev2', 'Usher Lain', 'AB', 'ABCDEFGH') as usher2 \gset

-- Semua verifikasi bcrypt lewat private.verify_secret. Di dalam transaksi tes ini fungsinya diganti versi yang
-- mencatat setiap panggilan (di-rollback di akhir), sehingga jumlah bcrypt per percobaan bisa dihitung.
create temp table bcrypt_calls (n integer);
create or replace function private.verify_secret(p_secret text, p_hash text)
returns boolean language plpgsql volatile set search_path = ''
as $$
begin
  insert into pg_temp.bcrypt_calls values (1);
  return extensions.crypt(coalesce(p_secret, ''), p_hash) = p_hash;
end;
$$;
create function pg_temp.take_calls() returns integer language plpgsql as $$
declare n integer;
begin
  select count(*) into n from pg_temp.bcrypt_calls;
  delete from pg_temp.bcrypt_calls;
  return n;
end;
$$;
create function pg_temp.pin(p_ip text, p_code text, p_selector text, p_secret text) returns jsonb language sql as $$
  select public.svc_usher_login('pin', p_ip, p_code, p_selector, p_secret, null, 'HP Uji', '0.1.0');
$$;
create function pg_temp.qr(p_ip text, p_token text) returns jsonb language sql as $$
  select public.svc_usher_login('qr', p_ip, null, null, null, p_token, 'HP QR', '0.1.0');
$$;

-- ---------------------------------------------------------------------------------------------
-- Login sah
-- ---------------------------------------------------------------------------------------------
select pg_temp.pin('10.0.0.1', :'ev_code', 'AB', 'ABCDEFGH') as r1 \gset
select is(:'r1'::jsonb ->> 'outcome', 'ok', 'login PIN sah');
select is(pg_temp.take_calls(), 1, 'login sah: tepat satu bcrypt');
select is(:'r1'::jsonb ->> 'device_code', 'A', 'perangkat pertama mendapat kode A');
select is((:'r1'::jsonb ->> 'session_expires_at')::timestamptz,
          ((current_date + 1) + time '06:00') at time zone 'Asia/Jakarta',
          'sesi berakhir H+1 pukul 06.00 waktu lokal acara');
select results_eq(
  format($$ select usher_id, name, app_version, auth_user_id is null, revoked_at is null from public.devices where id = %L $$,
         :'r1'::jsonb ->> 'device_id'),
  format($$ values (%L::uuid, 'HP Uji'::text, '0.1.0'::text, true, true) $$, :'usher'),
  'baris perangkat tercatat untuk usher yang benar; user Auth ditautkan Edge Function setelahnya');
select is(pg_temp.pin('10.0.0.1', lower(:'ev_code'), 'ab', 'ABCDEFGH') ->> 'device_code', 'B',
          'Kode Acara dan ID usher tidak peka huruf besar/kecil; perangkat berikutnya B');
select pg_temp.take_calls();

-- ---------------------------------------------------------------------------------------------
-- Setiap penyebab gagal: respons identik dan tepat satu bcrypt
-- ---------------------------------------------------------------------------------------------
select is(pg_temp.pin('10.0.0.9', 'ZZZZZZ', 'AB', 'ABCDEFGH'), '{"outcome": "invalid"}'::jsonb, 'Kode Acara tidak ada → invalid');
select is(pg_temp.take_calls(), 1, 'Kode Acara tidak ada: tetap satu bcrypt (dummy)');
select is(pg_temp.pin('10.0.0.9', :'ev_code', 'XY', 'ABCDEFGH'), '{"outcome": "invalid"}'::jsonb, 'ID usher tidak ada → invalid');
select is(pg_temp.take_calls(), 1, 'ID usher tidak ada: tetap satu bcrypt');
select is(pg_temp.pin('10.0.0.9', :'ev_code', 'CD', 'ABCDEFGH'), '{"outcome": "invalid"}'::jsonb,
          'usher nonaktif dengan rahasia benar → invalid');
select is(pg_temp.take_calls(), 1, 'usher nonaktif: tetap satu bcrypt (dummy, bukan hash usher)');
select is(pg_temp.pin('10.0.0.9', :'ev_code', 'AB', 'HGFEDCBA'), '{"outcome": "invalid"}'::jsonb, 'rahasia salah → invalid');
select is(pg_temp.take_calls(), 1, 'rahasia salah: tepat satu bcrypt');
select is(pg_temp.pin('10.0.0.9', '', '', ''), '{"outcome": "invalid"}'::jsonb, 'masukan kosong → invalid');
select is(pg_temp.take_calls(), 1, 'masukan kosong: tetap satu bcrypt');
select results_eq(
  $$ select reason, success, event_id is not null from public.auth_attempts where ip = '10.0.0.9' order by id $$,
  $$ values ('unknown_event'::text, false, false), ('unknown_usher', false, true), ('inactive_usher', false, true),
            ('bad_secret', false, true), ('unknown_event', false, false) $$,
  'setiap percobaan tercatat di auth_attempts beserta penyebab internalnya');

-- ---------------------------------------------------------------------------------------------
-- Blokir per (IP + Kode Acara): 10 gagal dalam 15 menit
-- ---------------------------------------------------------------------------------------------
select count(*) from (select pg_temp.pin('10.0.0.2', :'ev_code', 'AB', 'HGFEDCBA') from generate_series(1, 9)) s;
select is(pg_temp.pin('10.0.0.2', :'ev_code', 'AB', 'HGFEDCBA') ->> 'outcome', 'invalid', 'gagal ke-10 masih dijawab invalid');
select is(pg_temp.take_calls(), 10, '10 percobaan = 10 bcrypt');
select pg_temp.pin('10.0.0.2', :'ev_code', 'AB', 'ABCDEFGH') as blocked \gset
select is(:'blocked'::jsonb ->> 'outcome', 'blocked', 'percobaan ke-11, bahkan dengan PIN benar, diblokir');
select ok((:'blocked'::jsonb ->> 'retry_after')::integer between 1 and 900, 'retry_after dalam detik, ≤ 15 menit');
select is(pg_temp.take_calls(), 0, 'percobaan yang diblokir tidak menjalankan bcrypt');
select is((select reason from public.auth_attempts where ip = '10.0.0.2' order by id desc limit 1), 'blocked_key',
          'percobaan yang diblokir tercatat sebagai blocked_key');
select is((select count(*)::integer from private.login_failures(now() - interval '15 minutes')
           where ip = '10.0.0.2' and event_code = :'ev_code'), 10,
          'percobaan yang diblokir tidak ikut dihitung (blokir tidak diperpanjang)');
select is((select count(*)::integer from public.audit_logs
           where event_id = :'ev' and action = 'usher_login_blocked' and after ->> 'scope' = 'key'), 1,
          'blokir (IP + Kode Acara) tercatat di audit log sekali');
select is(pg_temp.pin('10.0.0.2', :'ev2_code', 'AB', 'ABCDEFGH') ->> 'outcome', 'ok',
          'IP yang sama dengan Kode Acara lain tidak terpengaruh');
select pg_temp.take_calls();

-- QR Login tetap berhasil saat kunci PIN terblokir.
select tests.authenticate_as(:'admin_id');
select public.admin_create_login_qr(:'usher') ->> 'token' as qr_token \gset
reset role;
select is(pg_temp.qr('10.0.0.2', :'qr_token') ->> 'outcome', 'ok', 'QR Login berhasil walau login PIN dari IP ini diblokir');
select is(pg_temp.take_calls(), 0, 'QR Login tidak memakai bcrypt');
select is(pg_temp.qr('10.0.0.2', :'qr_token'), '{"outcome": "invalid"}'::jsonb, 'QR yang sudah terpakai → invalid');
insert into public.usher_login_tokens (usher_id, token_hash, expires_at, created_by)
values (:'usher', private.sha256_hex('token-kedaluwarsa'), now() - interval '1 second', :'admin_id');
select is(pg_temp.qr('10.0.0.2', 'token-kedaluwarsa'), '{"outcome": "invalid"}'::jsonb, 'QR kedaluwarsa → invalid');
select is(pg_temp.qr('10.0.0.2', 'token-ngawur'), '{"outcome": "invalid"}'::jsonb, 'QR tidak dikenal → invalid');
select results_eq(
  $$ select reason, success from public.auth_attempts where ip = '10.0.0.2' and method = 'qr' order by id $$,
  $$ values ('ok'::text, true), ('invalid_token', false), ('invalid_token', false), ('invalid_token', false) $$,
  'setiap percobaan QR, termasuk yang tidak valid, tercatat');
select is((select count(*)::integer from private.login_failures(now() - interval '15 minutes') where ip = '10.0.0.2'), 10,
          'QR yang tidak valid tidak dihitung untuk blokir PIN');

-- ---------------------------------------------------------------------------------------------
-- Blokir global per IP: 50 gagal dengan Kode Acara apa pun
-- ---------------------------------------------------------------------------------------------
insert into public.auth_attempts (kind, method, ip, event_code, success, reason)
select 'usher_login', 'pin', '10.0.0.3', 'K' || lpad(i::text, 5, '0'), false, 'unknown_event' from generate_series(1, 49) i;
select is(pg_temp.pin('10.0.0.3', 'ZZZZZZ', 'AB', 'ABCDEFGH') ->> 'outcome', 'invalid',
          'gagal ke-50 (Kode Acara acak, masing-masing < 10) masih diproses');
select is(pg_temp.take_calls(), 1, 'gagal ke-50 masih menjalankan satu bcrypt');
select is(pg_temp.pin('10.0.0.3', :'ev_code', 'AB', 'ABCDEFGH') ->> 'outcome', 'blocked',
          'setelah 50 gagal, IP diblokir untuk Kode Acara apa pun');
select is(pg_temp.take_calls(), 0, 'blokir per IP diperiksa sebelum bcrypt');
select is((select count(*)::integer from public.audit_logs
           where action = 'usher_login_blocked' and after ->> 'scope' = 'ip' and after ->> 'ip' = '10.0.0.3'), 1,
          'blokir per IP tercatat di audit log');

-- ---------------------------------------------------------------------------------------------
-- Peringatan per event: 20 gagal dari semua IP, tanpa mengunci
-- ---------------------------------------------------------------------------------------------
select tests.create_event('Acara Diserang', :'admin_id') as ev3 \gset
select code as ev3_code from public.events where id = :'ev3' \gset
select tests.create_usher(:'ev3', 'Usher Tiga', 'EF', 'ABCDEFGH') as usher3 \gset
select count(*) from (select pg_temp.pin('10.1.0.' || (i % 2), :'ev3_code', 'EF', 'HGFEDCBA') from generate_series(1, 19) i) s;
select is((select count(*)::integer from public.audit_logs where event_id = :'ev3' and action = 'usher_login_burst'), 0,
          '19 gagal: belum ada peringatan');
select pg_temp.pin('10.1.0.7', :'ev3_code', 'EF', 'HGFEDCBA');
select pg_temp.pin('10.1.0.8', :'ev3_code', 'EF', 'HGFEDCBA');
select is((select count(*)::integer from public.audit_logs where event_id = :'ev3' and action = 'usher_login_burst'), 1,
          '≥ 20 gagal per event: peringatan tercatat sekali per jendela');
select is(pg_temp.pin('10.1.0.9', :'ev3_code', 'EF', 'ABCDEFGH') ->> 'outcome', 'ok',
          'peringatan per event tidak mengunci login usher sungguhan');
select tests.authenticate_as(:'admin_id');
select is((public.get_alerts(:'ev3') -> 'loginFailures' ->> 'warning')::boolean, true, 'dashboard menerima peringatan per event');
select is(public.get_alerts(:'ev3') -> 'blocked' -> 0 ->> 'ip', '10.1.0.1',
          'kunci (10.1.0.1 + Kode Acara) yang mencapai 10 gagal tampil di peringatan');
select is(jsonb_array_length(public.get_alerts(:'ev') -> 'blocked'), 2,
          'Acara Login: blokir (IP + Kode Acara) 10.0.0.2 dan blokir IP 10.0.0.3 tampil di peringatan');
reset role;
select pg_temp.take_calls();

-- ---------------------------------------------------------------------------------------------
-- Respons 403 hanya setelah kredensial sah
-- ---------------------------------------------------------------------------------------------
select tests.create_event('Acara Arsip', :'admin_id') as ev4 \gset
select code as ev4_code from public.events where id = :'ev4' \gset
select tests.create_usher(:'ev4', 'Usher Empat', 'GH', 'ABCDEFGH') as usher4 \gset
update public.events set archived_at = now() where id = :'ev4';
select is(pg_temp.pin('10.2.0.1', :'ev4_code', 'GH', 'HGFEDCBA'), '{"outcome": "invalid"}'::jsonb,
          'acara diarsipkan + rahasia salah → invalid (arsip tidak bocor)');
select is(pg_temp.pin('10.2.0.1', :'ev4_code', 'GH', 'ABCDEFGH'), '{"outcome": "archived"}'::jsonb,
          'acara diarsipkan + kredensial sah → archived');

select tests.create_event('Acara Lewat', :'admin_id') as ev5 \gset
select code as ev5_code from public.events where id = :'ev5' \gset
select tests.create_usher(:'ev5', 'Usher Lima', 'JK', 'ABCDEFGH') as usher5 \gset
update public.events set event_date = current_date - 2 where id = :'ev5';
select is(pg_temp.pin('10.2.0.1', :'ev5_code', 'JK', 'ABCDEFGH'), '{"outcome": "session_ended"}'::jsonb,
          'jendela sesi acara sudah lewat → session_ended (FR-R-10)');

select tests.create_event('Acara Penuh', :'admin_id') as ev6 \gset
select code as ev6_code from public.events where id = :'ev6' \gset
select tests.create_usher(:'ev6', 'Usher Enam', 'MN', 'ABCDEFGH') as usher6 \gset
insert into public.devices (id, event_id, usher_id, code, session_expires_at)
select gen_random_uuid(), :'ev6', :'usher6', private.device_code(i), now() + interval '1 day' from generate_series(0, 701) i;
select is(pg_temp.pin('10.2.0.1', :'ev6_code', 'MN', 'ABCDEFGH'), '{"outcome": "capacity"}'::jsonb,
          '702 kode perangkat sudah terpakai → capacity');
select is(private.device_code(701), 'ZZ', 'kode perangkat terakhir ZZ');

-- ---------------------------------------------------------------------------------------------
-- Hanya service_role (Edge Function) yang bisa memanggil fungsi login
-- ---------------------------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated',
  'public.svc_usher_login(public.login_method, text, text, text, text, text, text, text)', 'execute'),
  'authenticated tidak bisa memanggil svc_usher_login');
select ok(has_function_privilege('service_role',
  'public.svc_usher_login(public.login_method, text, text, text, text, text, text, text)', 'execute'),
  'service_role bisa memanggil svc_usher_login');

select * from finish();
rollback;
