-- push_outbox (12.2, 12.3, FR-C-06, FR-C-08, FR-R-08, FR-R-10, D11, D13; plan.md 10.2): semua cabang status,
-- idempotensi, validasi per item, karantina dua alasan + batas 500, dan penolakan seluruh batch.
begin;
select plan(43);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Push', :'admin_id') as ev \gset
select tests.create_event('Acara Arsip', :'admin_id') as ev2 \gset
select tests.create_usher(:'ev', 'Usher Satu', 'AB') as u1 \gset
select tests.create_usher(:'ev', 'Usher Dua', 'CD') as u2 \gset
select tests.create_usher(:'ev', 'Usher Keluar', 'EF', p_mode => 'check_out') as u_out \gset
select tests.create_usher(:'ev2', 'Usher Arsip', 'AB') as u_arc \gset

select tests.create_device(:'ev', :'u1', 'A') as dev_a \gset
select tests.create_device(:'ev', :'u2', 'B') as dev_b \gset
select tests.create_device(:'ev', :'u1', 'C') as dev_c \gset
select tests.create_device(:'ev', :'u1', 'D', now() - interval '1 hour') as dev_d \gset
select tests.create_device(:'ev', :'u1', 'E', now() - interval '73 hours') as dev_e \gset
select tests.create_device(:'ev', :'u1', 'F', now() - interval '1 hour') as dev_f \gset
select tests.create_device(:'ev', :'u1', 'G') as dev_g \gset
select tests.create_device(:'ev', :'u_out', 'H') as dev_h \gset
select tests.create_device(:'ev2', :'u_arc', 'A') as dev_i \gset
update public.devices set revoked_at = now(), revoke_mode = 'quarantine' where id in (:'dev_c', :'dev_f');
update public.devices set revoked_at = now(), revoke_mode = 'terminate' where id = :'dev_g';
update public.events set archived_at = now() where id = :'ev2';

insert into public.guests (id, event_id, name, category, special_number) values
  ('00000000-0000-4000-8000-000000000001', :'ev', 'Satu', 'regular', null),
  ('00000000-0000-4000-8000-000000000002', :'ev', 'Dua', 'regular', null),
  ('00000000-0000-4000-8000-000000000003', :'ev', 'Tiga', 'regular', null),
  ('00000000-0000-4000-8000-000000000004', :'ev', 'Empat', 'regular', null),
  ('00000000-0000-4000-8000-000000000071', :'ev', 'Raja', 'vvip', 'VVIP-007'),
  ('00000000-0000-4000-8000-000000000072', :'ev', 'Ratu', 'vvip', 'VVIP-008'),
  ('00000000-0000-4000-8000-000000000099', :'ev2', 'Tamu Acara Lain', 'regular', null);

create function pg_temp.push(p_device uuid, p_items jsonb) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform tests.authenticate_as_device(p_device);
  r := public.push_outbox(p_items);
  reset role;
  return r;
end;
$$;
create function pg_temp.outcomes(p jsonb) returns text[] language sql as $$
  select array_agg(coalesce(r ->> 'code', r ->> 'status') order by n) from jsonb_array_elements(p -> 'results') with ordinality t(r, n);
$$;

-- ---------------------------------------------------------------------------------------------
-- accepted, idempotensi
-- ---------------------------------------------------------------------------------------------
select pg_temp.push(:'dev_a', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000a001', :'dev_a',
  '00000000-0000-4000-8000-000000000001', 'A-001', 2))) as r1 \gset
select is(:'r1'::jsonb ->> 'status', 'ok', 'perangkat sah: status ok');
select is((:'r1'::jsonb -> 'results' -> 0) - 'receivedAt',
          '{"id": "00000000-0000-4000-8000-00000000a001", "outcome": "stored", "status": "accepted",
            "guestId": "00000000-0000-4000-8000-000000000001", "ticketNumber": "A-001"}'::jsonb,
          'check-in pertama → accepted');
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-000000000001'), 'checked_in',
          'tamu otomatis Hadir (FR-G-09)');
select is(pg_temp.push(:'dev_a', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000a001', :'dev_a',
  '00000000-0000-4000-8000-000000000001', 'A-001', 2))), :'r1'::jsonb, 'retry dengan id sama → hasil identik');
select is((select count(*)::integer from public.check_ins where guest_id = '00000000-0000-4000-8000-000000000001'), 1,
          'retry tidak membuat baris baru (ON CONFLICT id)');

-- ---------------------------------------------------------------------------------------------
-- VVIP bernomor di dua perangkat (12.3 poin 7)
-- ---------------------------------------------------------------------------------------------
select is(pg_temp.outcomes(pg_temp.push(:'dev_a', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000a071',
  :'dev_a', '00000000-0000-4000-8000-000000000071', 'VVIP-007')))), array['accepted'], 'VVIP-007 di A → accepted');
select is(pg_temp.outcomes(pg_temp.push(:'dev_b', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000b071',
  :'dev_b', '00000000-0000-4000-8000-000000000071', 'VVIP-007')))), array['duplicate'],
  'VVIP-007 di B, Check-In Lebih 1 Kali nonaktif → duplicate');
update public.checkin_settings set allow_multi_checkin = true where event_id = :'ev';
select is(pg_temp.outcomes(pg_temp.push(:'dev_a', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000a072',
  :'dev_a', '00000000-0000-4000-8000-000000000072', 'VVIP-008', 2)))), array['accepted'], 'VVIP-008 di A → accepted');
select is(pg_temp.outcomes(pg_temp.push(:'dev_b', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000b072',
  :'dev_b', '00000000-0000-4000-8000-000000000072', 'VVIP-008', 3)))), array['repeat'],
  'VVIP-008 di B, Check-In Lebih 1 Kali aktif → repeat (nomor sama tidak melanggar unique index)');
select is((select sum(actual_pax)::integer from public.check_ins
           where guest_id = '00000000-0000-4000-8000-000000000072' and status in ('accepted', 'conflict') and voided_at is null), 2,
          'repeat tidak menambah jumlah orang (D11)');
select is((select ticket_number from public.check_ins where id = '00000000-0000-4000-8000-00000000b072'), 'VVIP-008',
          'nomor tiket repeat = nomor khusus yang sama (FR-C-08)');

-- ---------------------------------------------------------------------------------------------
-- conflict dan tamu tambahan
-- ---------------------------------------------------------------------------------------------
select is(pg_temp.outcomes(pg_temp.push(:'dev_a', jsonb_build_array(tests.push_item('00000000-0000-4000-8000-00000000a002',
  :'dev_a', '00000000-0000-4000-8000-000000000002', 'A-001')))), array['conflict'],
  'nomor tiket yang sudah dipakai accepted lain → conflict');
select pg_temp.push(:'dev_a', jsonb_build_array(jsonb_build_object(
  'id', '00000000-0000-4000-8000-00000000a0a1', 'guestId', null, 'actualPax', 2, 'ticketNumber', 'a-004',
  'deviceId', :'dev_a', 'checkedInAt', '2026-10-18T19:05:00+07:00',
  'newGuest', jsonb_build_object('name', '  Tamu Baru  ', 'phone', null, 'category', 'regular', 'invitedPax', 2, 'notes', null)))) as r_new \gset
select is(:'r_new'::jsonb -> 'results' -> 0 ->> 'status', 'accepted', 'newGuest → accepted');
select results_eq(
  format($$ select name, is_additional, created_device_id, attendance_status::text from public.guests where id = %L $$,
         :'r_new'::jsonb -> 'results' -> 0 ->> 'guestId'),
  format($$ values ('Tamu Baru'::text, true, %L::uuid, 'checked_in'::text) $$, :'dev_a'),
  'tamu tambahan dibuat (is_additional, asal perangkat) dan langsung Hadir');
select is(:'r_new'::jsonb -> 'results' -> 0 ->> 'ticketNumber', 'A-004', 'nomor tiket dinormalisasi ke huruf besar');

-- ---------------------------------------------------------------------------------------------
-- Validasi per item: galat tidak disimpan, item lain di batch yang sama tetap diproses
-- ---------------------------------------------------------------------------------------------
select count(*) as before_count from public.check_ins where event_id = :'ev' \gset
select pg_temp.push(:'dev_a', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_b', '00000000-0000-4000-8000-000000000003', 'A-010'),
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000099', 'A-011'),
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A_012'),
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-H013'),
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'B-014'),
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-015')
    || '{"gift": {"kind": "envelope", "code": "A-H001"}}',
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-016')
    || '{"newGuest": {"name": "X", "category": "regular", "invitedPax": 1}}',
  tests.push_item(gen_random_uuid(), :'dev_a', null, 'A-017'),
  tests.push_item(gen_random_uuid(), :'dev_a', null, 'A-018') || '{"newGuest": {"name": " ", "category": "regular", "invitedPax": 1}}',
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-019') || '{"id": "bukan-uuid"}',
  tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-020') || '{"actualPax": 51}',
  tests.push_item('00000000-0000-4000-8000-00000000b071', :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-021'),
  tests.push_item('00000000-0000-4000-8000-00000000a003', :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-005')
)) as r_err \gset
select is(pg_temp.outcomes(:'r_err'::jsonb), array[
  'device_mismatch', 'guest_not_found', 'invalid_ticket_number', 'invalid_ticket_number', 'ticket_device_mismatch',
  'gift_not_supported', 'invalid_item', 'invalid_item', 'invalid_new_guest', 'invalid_item', 'invalid_item', 'id_conflict',
  'accepted'], 'setiap jenis item tidak valid mendapat kode galatnya; item sah di batch yang sama tetap disimpan');
select is((select count(*)::integer from public.check_ins where event_id = :'ev') - :before_count, 1,
          'item yang galat tidak disimpan');
select is(:'r_err'::jsonb -> 'results' -> 9 ->> 'id', 'bukan-uuid', 'galat menyertakan id item apa adanya');

-- ---------------------------------------------------------------------------------------------
-- Karantina: Cabut sebelum session_expires_at (device_revoked)
-- ---------------------------------------------------------------------------------------------
select pg_temp.push(:'dev_c', jsonb_build_array(
  tests.push_item('00000000-0000-4000-8000-00000000c001', :'dev_c', '00000000-0000-4000-8000-000000000004', 'C-001'),
  jsonb_build_object('id', '00000000-0000-4000-8000-00000000c002', 'guestId', null, 'actualPax', 1, 'ticketNumber', 'C-002',
    'deviceId', :'dev_c', 'checkedInAt', '2026-10-18T19:10:00+07:00',
    'newGuest', jsonb_build_object('name', 'Penyusup', 'category', 'vvip', 'invitedPax', 5))
)) as r_c \gset
select is(:'r_c'::jsonb ->> 'status', 'revoked', 'perangkat dicabut (Cabut): status revoked');
select is(pg_temp.outcomes(:'r_c'::jsonb), array['quarantined', 'quarantined'], 'semua item valid disimpan sebagai quarantined');
select results_eq(
  $$ select quarantine_reason::text, guest_id is null, pending_guest ->> 'name' from public.check_ins
     where id in ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000c002') order by id $$,
  $$ values ('device_revoked'::text, false, null::text), ('device_revoked', true, 'Penyusup') $$,
  'alasan device_revoked; data tamu baru disimpan di pending_guest');
select is((select count(*)::integer from public.guests where name = 'Penyusup'), 0, 'karantina tidak membuat tamu tambahan');
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-000000000004'), 'not_arrived',
          'karantina tidak mengubah kehadiran');

-- Sesi habis wajar, masih dalam masa tenggang 72 jam (session_expired).
select pg_temp.push(:'dev_d', jsonb_build_array(
  tests.push_item('00000000-0000-4000-8000-00000000d001', :'dev_d', '00000000-0000-4000-8000-000000000004', 'D-001'))) as r_d \gset
select is(:'r_d'::jsonb ->> 'status', 'expired', 'sesi habis dalam masa tenggang: status expired');
select is((select status::text || '/' || quarantine_reason::text from public.check_ins where id = '00000000-0000-4000-8000-00000000d001'),
          'quarantined/session_expired', 'item disimpan sebagai quarantined (session_expired)');

-- ---------------------------------------------------------------------------------------------
-- Ditolak seluruhnya: tidak ada baris yang disimpan
-- ---------------------------------------------------------------------------------------------
select is(pg_temp.push(:'dev_e', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_e', '00000000-0000-4000-8000-000000000004', 'E-001'))),
  '{"status": "rejected", "reason": "quarantine_window_closed", "results": []}'::jsonb, 'masa tenggang 72 jam habis → rejected');
select is(pg_temp.push(:'dev_f', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_f', '00000000-0000-4000-8000-000000000004', 'F-001'))),
  '{"status": "rejected", "reason": "quarantine_window_closed", "results": []}'::jsonb,
  'Cabut + session_expires_at lewat → rejected tanpa masa tenggang');
select is(pg_temp.push(:'dev_g', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_g', '00000000-0000-4000-8000-000000000004', 'G-001'))),
  '{"status": "rejected", "reason": "terminated", "results": []}'::jsonb, 'Cabut & putus total → rejected');
select is(pg_temp.push(:'dev_h', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_h', '00000000-0000-4000-8000-000000000004', 'H-001'))),
  '{"status": "rejected", "reason": "mode_mismatch", "results": []}'::jsonb, 'usher Check-Out → rejected mode_mismatch');
select is(pg_temp.push(:'dev_i', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_i', '00000000-0000-4000-8000-000000000099', 'A-001'))),
  '{"status": "rejected", "reason": "event_archived", "results": []}'::jsonb, 'acara diarsipkan → rejected');
select is((select count(*)::integer from public.check_ins where device_id in (:'dev_e', :'dev_f', :'dev_g', :'dev_h', :'dev_i')), 0,
          'push yang ditolak tidak menyimpan baris apa pun');

-- ---------------------------------------------------------------------------------------------
-- Batas karantina 500 per perangkat
-- ---------------------------------------------------------------------------------------------
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, quarantine_reason, source,
                              device_id, usher_id, checked_in_at)
select gen_random_uuid(), :'ev', '00000000-0000-4000-8000-000000000004', 1, 'C-' || (100 + i), 'quarantined',
       'device_revoked', 'device', :'dev_c', :'u1', now()
from generate_series(1, 497) i;
select is((select count(*)::integer from public.check_ins where device_id = :'dev_c' and status = 'quarantined'), 499,
          'perangkat C sudah punya 499 item karantina');
select pg_temp.push(:'dev_c', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_c', '00000000-0000-4000-8000-000000000004', 'C-900'),
  tests.push_item(gen_random_uuid(), :'dev_c', '00000000-0000-4000-8000-000000000004', 'C-901'))) as r_lim \gset
select is(pg_temp.outcomes(:'r_lim'::jsonb), array['quarantined', 'quarantine_limit'],
          'item ke-500 masih dikarantina, item ke-501 ditolak quarantine_limit');
select is((select count(*)::integer from public.audit_logs where action = 'quarantine_limit_reached' and entity_id = :'dev_c'), 1,
          'batas karantina terlampaui diaudit');
select is(pg_temp.outcomes(pg_temp.push(:'dev_c', jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev_c', '00000000-0000-4000-8000-000000000004', 'C-902')))), array['quarantine_limit'],
  'item berikutnya tetap ditolak');
select is((select count(*)::integer from public.audit_logs where action = 'quarantine_limit_reached' and entity_id = :'dev_c'), 1,
          'audit batas karantina hanya sekali per perangkat');
select tests.authenticate_as(:'admin_id');
select is(public.get_alerts(:'ev') -> 'quarantineFull', jsonb_build_array(jsonb_build_object('deviceId', :'dev_c', 'code', 'C', 'count', 500)),
          'dashboard menerima peringatan batas karantina perangkat C');
reset role;
select is((select count(*)::integer from public.check_ins where device_id = :'dev_c' and status = 'quarantined'), 500,
          'jumlah karantina berhenti di 500');

-- ---------------------------------------------------------------------------------------------
-- Batas batch dan pemanggil
-- ---------------------------------------------------------------------------------------------
select jsonb_agg(tests.push_item(gen_random_uuid(), :'dev_a', '00000000-0000-4000-8000-000000000003', 'A-' || (300 + i)))
  as big from generate_series(1, 201) i \gset
select tests.authenticate_as_device(:'dev_a');
select throws_ok(format($$ select public.push_outbox(%L) $$, :'big'), '22023', null, 'lebih dari 200 item per push ditolak');
select throws_ok($$ select public.push_outbox('{"bukan": "array"}') $$, '22023', null, 'body bukan array ditolak');
reset role;
select tests.authenticate_as(:'admin_id');
select throws_ok($$ select public.push_outbox('[]') $$, '42501', null, 'Admin tidak bisa memanggil push_outbox');
reset role;
select ok(not has_function_privilege('anon', 'public.push_outbox(jsonb, timestamptz)', 'execute'), 'anon tidak bisa memanggil push_outbox');

-- Usher tetap tanpa hak tabel walau RPC tersedia (aturan 4).
select tests.authenticate_as_device(:'dev_a');
select is((select count(*)::integer from public.check_ins), 0, 'usher tidak bisa membaca check_ins langsung');
reset role;

select * from finish();
rollback;
