-- pull_snapshot (FR-HM-01, FR-R-08, FR-R-10, 12.2, 12.3 poin 8 & 17; plan.md 10.1): kunci persis, tanpa
-- telepon/catatan/token QR mentah, ringkasan checkIn, paginasi, delta + tombstone, dan revoked/expired tanpa data.
begin;
select plan(39);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Snapshot', :'admin_id') as ev \gset
select tests.create_usher(:'ev', 'Usher Satu', 'AB') as usher \gset
select tests.create_device(:'ev', :'usher', 'A') as dev_a \gset

insert into public.guest_groups (id, event_id, name) values
  ('00000000-0000-4000-8000-0000000000f1', :'ev', 'Keluarga'),
  ('00000000-0000-4000-8000-0000000000f2', :'ev', 'Teman');
insert into public.guests (id, event_id, name, phone, category, special_number, group_id, notes) values
  ('00000000-0000-4000-8000-000000000001', :'ev', 'Ani', '0812000111', 'vip', 'VIP-001', '00000000-0000-4000-8000-0000000000f1', 'Catatan rahasia'),
  ('00000000-0000-4000-8000-000000000002', :'ev', 'Bayu', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000003', :'ev', 'Citra', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000004', :'ev', 'Dodi', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000005', :'ev', 'Eko', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000006', :'ev', 'Fani', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000007', :'ev', 'Gita', null, 'regular', null, null, null),
  ('00000000-0000-4000-8000-000000000008', :'ev', 'Hadi', null, 'regular', null, '00000000-0000-4000-8000-0000000000f2', null),
  ('00000000-0000-4000-8000-000000000009', :'ev', 'Ina', null, 'vvip', null, null, null);
update public.guests set deleted_at = now() where id = '00000000-0000-4000-8000-000000000005';

-- Bayu: check-in perangkat; Citra: tandai hadir manual Admin tanpa nomor; Dodi: hanya karantina; Fani: dibatalkan.
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, device_id, usher_id, checked_in_at) values
  ('00000000-0000-4000-8000-0000000000c2', :'ev', '00000000-0000-4000-8000-000000000002', 2, 'A-001', 'accepted', 'device', :'dev_a', :'usher', '2026-10-18T19:00:00+07:00');
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, quarantine_reason, source, device_id, usher_id, checked_in_at) values
  ('00000000-0000-4000-8000-0000000000c4', :'ev', '00000000-0000-4000-8000-000000000004', 1, 'A-002', 'quarantined', 'device_revoked', 'device', :'dev_a', :'usher', now());
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, device_id, usher_id, checked_in_at, voided_at, void_reason) values
  ('00000000-0000-4000-8000-0000000000c6', :'ev', '00000000-0000-4000-8000-000000000006', 1, 'A-003', 'accepted', 'device', :'dev_a', :'usher', now(), now(), 'salah tamu');
select tests.authenticate_as(:'admin_id');
select public.admin_manual_check_in('00000000-0000-4000-8000-000000000003', 1);
reset role;

-- Semua baris dibuat "satu jam lalu" agar delta bisa dibedakan di dalam satu transaksi tes (now() tetap).
alter table public.guests disable trigger guests_set_updated_at;
alter table public.guest_groups disable trigger guest_groups_set_updated_at;
update public.guests set updated_at = now() - interval '1 hour' where event_id = :'ev';
update public.guest_groups set updated_at = now() - interval '1 hour' where event_id = :'ev';
alter table public.guests enable trigger guests_set_updated_at;
alter table public.guest_groups enable trigger guest_groups_set_updated_at;

-- ---------------------------------------------------------------------------------------------
-- Snapshot penuh
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as_device(:'dev_a');
select public.pull_snapshot(p_client_now => now() + interval '3 seconds') as full \gset
reset role;

select is(:'full'::jsonb ->> 'status', 'ok', 'perangkat sah menerima snapshot');
select is((select array_agg(k order by k) from jsonb_object_keys(:'full'::jsonb) k),
          array['device', 'event', 'greetings', 'groups', 'guests', 'hasMore', 'nextCursor', 'serverTime', 'settings', 'status'],
          'kunci tingkat atas persis');
select is((select array_agg(k order by k) from jsonb_object_keys(:'full'::jsonb -> 'guests' -> 0) k),
          array['attendanceStatus', 'category', 'checkIn', 'deletedAt', 'groupId', 'id', 'invitedPax', 'isAdditional',
                'name', 'qrTokenHash', 'rsvpPax', 'rsvpStatus', 'specialNumber', 'updatedAt'],
          'GuestSnapshot: 14 kunci persis (13 kunci v0.4 + checkIn)');
select is((select array_agg(k order by k) from jsonb_object_keys(:'full'::jsonb -> 'event') k),
          array['coupleNames', 'eventDate', 'id', 'name', 'sessionExpiresAt', 'timezone'], 'kunci event persis');
select is((select array_agg(k order by k) from jsonb_object_keys(:'full'::jsonb -> 'settings') k),
          array['allowMultiCheckin', 'printTicket', 'showVerification'], 'kunci settings persis');
select is((select array_agg(k order by k) from jsonb_object_keys(:'full'::jsonb -> 'greetings' -> 0) k),
          array['body', 'category', 'layout', 'photoPath', 'photoVersion', 'title'], 'kunci greetings persis');
select is(jsonb_array_length(:'full'::jsonb -> 'guests'), 8, 'snapshot penuh tanpa tamu yang sudah dihapus');
select ok(:'full' !~ '0812000111', 'nomor telepon tidak dikirim');
select ok(:'full' !~ 'Catatan rahasia', 'catatan tidak dikirim');
select ok(position((select qr_token from public.guests where id = '00000000-0000-4000-8000-000000000001') in :'full') = 0,
          'token QR mentah tidak dikirim');
select is((select g ->> 'qrTokenHash' from jsonb_array_elements(:'full'::jsonb -> 'guests') g where g ->> 'name' = 'Ani'),
          (select qr_token_hash from public.guests where id = '00000000-0000-4000-8000-000000000001'),
          'qrTokenHash = hash SHA-256 token');
select ok(:'full' !~ (:'usher')::text and :'full' !~ (:'dev_a')::text, 'id usher dan id perangkat tidak dikirim');
select is((select (g -> 'checkIn') - 'checkedInAt' from jsonb_array_elements(:'full'::jsonb -> 'guests') g where g ->> 'name' = 'Bayu'),
          '{"status": "accepted", "ticketNumber": "A-001", "usherName": "Usher Satu"}'::jsonb,
          'checkIn check-in perangkat: status, nomor tiket, nama usher');
select is((select (g -> 'checkIn') - 'checkedInAt' from jsonb_array_elements(:'full'::jsonb -> 'guests') g where g ->> 'name' = 'Citra'),
          '{"status": "accepted", "ticketNumber": null, "usherName": null}'::jsonb,
          'tandai hadir manual tanpa nomor: ticketNumber dan usherName null (105 kasus 7)');
select is((select g -> 'checkIn' from jsonb_array_elements(:'full'::jsonb -> 'guests') g where g ->> 'name' = 'Dodi'),
          'null'::jsonb, 'check-in karantina tidak muncul sebagai checkIn');
select is((select g -> 'checkIn' from jsonb_array_elements(:'full'::jsonb -> 'guests') g where g ->> 'name' = 'Fani'),
          'null'::jsonb, 'check-in yang dibatalkan tidak muncul sebagai checkIn');
select is(:'full'::jsonb -> 'device' ->> 'code', 'A', 'kode perangkat dikirim');
select is(jsonb_array_length(:'full'::jsonb -> 'greetings'), 3, 'sapaan tiga kategori');
select is(jsonb_array_length(:'full'::jsonb -> 'groups'), 2, 'grup dikirim di halaman pertama');
select is((:'full'::jsonb ->> 'hasMore')::boolean, false, 'satu halaman cukup');
select is((select clock_offset_ms from public.devices where id = :'dev_a'), 3000, 'selisih jam perangkat dicatat');
select ok((select last_seen_at = now() from public.devices where id = :'dev_a'), 'terakhir terlihat diperbarui');

-- ---------------------------------------------------------------------------------------------
-- Paginasi keyset
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as_device(:'dev_a');
select public.pull_snapshot(null, 3) as p1 \gset
select public.pull_snapshot(:'p1'::jsonb ->> 'nextCursor', 3) as p2 \gset
select public.pull_snapshot(:'p2'::jsonb ->> 'nextCursor', 3) as p3 \gset
reset role;
select is(array[(:'p1'::jsonb ->> 'hasMore')::boolean, (:'p2'::jsonb ->> 'hasMore')::boolean, (:'p3'::jsonb ->> 'hasMore')::boolean],
          array[true, true, false], 'tiga halaman: hasMore benar');
select is((select count(distinct g ->> 'id')::integer from (
             select jsonb_array_elements(:'p1'::jsonb -> 'guests') g union all
             select jsonb_array_elements(:'p2'::jsonb -> 'guests') union all
             select jsonb_array_elements(:'p3'::jsonb -> 'guests')) s), 8,
          'tiga halaman memuat 8 tamu berbeda, tanpa ganda');
select is(jsonb_array_length(:'p2'::jsonb -> 'groups'), 0, 'grup tidak diulang di halaman berikutnya');

-- ---------------------------------------------------------------------------------------------
-- Delta + tombstone
-- ---------------------------------------------------------------------------------------------
update public.guests set name = 'Ani Wijaya' where id = '00000000-0000-4000-8000-000000000001';
update public.guests set deleted_at = now() where id = '00000000-0000-4000-8000-000000000007';
update public.guest_groups set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000f2';
select tests.authenticate_as_device(:'dev_a');
select public.pull_snapshot(:'full'::jsonb ->> 'nextCursor') as delta \gset
reset role;
select is((select array_agg(g ->> 'name' order by g ->> 'name') from jsonb_array_elements(:'delta'::jsonb -> 'guests') g),
          array['Ani Wijaya', 'Gita', 'Hadi'],
          'delta hanya berisi tamu yang berubah (Hadi berubah karena grupnya dihapus)');
select ok((select g ->> 'deletedAt' is not null from jsonb_array_elements(:'delta'::jsonb -> 'guests') g where g ->> 'name' = 'Gita'),
          'tamu terhapus dikirim sebagai tombstone');
select is((select g -> 'groupId' from jsonb_array_elements(:'delta'::jsonb -> 'guests') g where g ->> 'name' = 'Hadi'),
          'null'::jsonb, 'anggota grup yang dihapus kehilangan groupId');
select ok((:'delta'::jsonb -> 'groups' -> 0 ->> 'deletedAt') is not null, 'grup terhapus dikirim sebagai tombstone');

-- ---------------------------------------------------------------------------------------------
-- Kursor tidak valid
-- ---------------------------------------------------------------------------------------------
select tests.create_event('Acara Lain', :'admin_id') as ev2 \gset
select tests.create_usher(:'ev2', 'Usher Lain', 'AB') as usher2 \gset
select tests.create_device(:'ev2', :'usher2', 'A') as dev_other \gset
select tests.authenticate_as_device(:'dev_a');
select throws_ok($$ select public.pull_snapshot('bukan-kursor') $$, '22023', null, 'kursor rusak ditolak');
reset role;
select tests.authenticate_as_device(:'dev_other');
select throws_ok(format($$ select public.pull_snapshot(%L) $$, :'full'::jsonb ->> 'nextCursor'), '22023', null,
                 'kursor acara lain ditolak');
reset role;

-- ---------------------------------------------------------------------------------------------
-- Dicabut / sesi berakhir / diarsipkan: tanpa data apa pun, termasuk saat kursor dikirim
-- ---------------------------------------------------------------------------------------------
select tests.create_device(:'ev', :'usher', 'B') as dev_rev \gset
select tests.create_device(:'ev', :'usher', 'C') as dev_term \gset
select tests.create_device(:'ev', :'usher', 'D', now() - interval '1 hour') as dev_exp \gset
update public.devices set revoked_at = now(), revoke_mode = 'quarantine' where id = :'dev_rev';
update public.devices set revoked_at = now(), revoke_mode = 'terminate' where id = :'dev_term';

select tests.authenticate_as_device(:'dev_rev');
select is(public.pull_snapshot(), '{"status": "revoked"}'::jsonb, 'Cabut → revoked tanpa data');
select is(public.pull_snapshot(:'full'::jsonb ->> 'nextCursor'), '{"status": "revoked"}'::jsonb,
          'Cabut + kursor delta → tetap revoked tanpa delta');
reset role;
select tests.authenticate_as_device(:'dev_term');
select is(public.pull_snapshot(), '{"status": "revoked"}'::jsonb, 'Cabut & putus total → revoked tanpa data');
reset role;
select tests.authenticate_as_device(:'dev_exp');
select is(public.pull_snapshot(:'full'::jsonb ->> 'nextCursor'), '{"status": "expired"}'::jsonb,
          'sesi berakhir (walau masih masa tenggang) + kursor → expired tanpa data');
reset role;
update public.events set archived_at = now() where id = :'ev2';
select tests.authenticate_as_device(:'dev_other');
select is(public.pull_snapshot(), '{"status": "expired"}'::jsonb, 'acara diarsipkan → expired tanpa data');
reset role;

-- ---------------------------------------------------------------------------------------------
-- Hanya perangkat usher yang terdaftar
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select throws_ok($$ select public.pull_snapshot() $$, '42501', null, 'Admin tidak bisa memanggil pull_snapshot');
reset role;
select tests.create_user('palsu@test.local', '{}', jsonb_build_object('role', 'usher', 'event_id', :'ev', 'device_id', :'dev_a')) as fake_user \gset
select tests.authenticate_as(:'fake_user');
select throws_ok($$ select public.pull_snapshot() $$, '42501', null, 'klaim usher di user_metadata diabaikan');
reset role;
select tests.authenticate_with_claims(jsonb_build_object('sub', gen_random_uuid(), 'app_metadata',
  jsonb_build_object('role', 'usher', 'event_id', :'ev', 'usher_id', :'usher', 'device_id', :'dev_a')));
select throws_ok($$ select public.pull_snapshot() $$, '42501', null,
                 'JWT yang bukan milik user Auth perangkat ditolak walau device_id benar');
reset role;

select * from finish();
rollback;
