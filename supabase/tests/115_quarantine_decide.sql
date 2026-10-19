-- Riwayat (FR-RW-03, FR-RW-05, 12.3): setujui karantina (evaluasi ulang saat disetujui, tamu tambahan dibuat
-- saat itu), tolak (alasan wajib, data tetap), per baris dan per perangkat; undo; tandai ditinjau; audit.
begin;
select plan(27);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Karantina', :'admin_id') as ev \gset
select tests.create_usher(:'ev', 'Usher', 'AB') as usher \gset
select tests.create_device(:'ev', :'usher', 'B') as dev_b \gset
select tests.create_device(:'ev', :'usher', 'C') as dev_c \gset
update public.devices set revoked_at = now(), revoke_mode = 'quarantine' where id in (:'dev_b', :'dev_c');

insert into public.guests (id, event_id, name) values
  ('00000000-0000-4000-8000-000000000001', :'ev', 'Satu'),
  ('00000000-0000-4000-8000-000000000002', :'ev', 'Dua'),
  ('00000000-0000-4000-8000-000000000003', :'ev', 'Tiga'),
  ('00000000-0000-4000-8000-000000000004', :'ev', 'Empat');
-- Dua sudah check-in sah lewat jalur lain.
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, checked_in_at) values
  ('00000000-0000-4000-8000-0000000000a2', :'ev', '00000000-0000-4000-8000-000000000002', 1, 'X-001', 'accepted', 'outbox_upload', now());

create function pg_temp.q(p_id uuid, p_device uuid, p_guest uuid, p_ticket text, p_pending jsonb default null) returns void
language sql as $$
  insert into public.check_ins (id, event_id, guest_id, pending_guest, actual_pax, ticket_number, status, quarantine_reason,
                                source, device_id, usher_id, checked_in_at, received_at)
  select p_id, d.event_id, p_guest, p_pending, 2, p_ticket, 'quarantined', 'device_revoked', 'device', d.id, d.usher_id,
         now(), clock_timestamp()
  from public.devices d where d.id = p_device;
$$;
select pg_temp.q('00000000-0000-4000-8000-0000000000b1', :'dev_b', '00000000-0000-4000-8000-000000000001', 'B-001');
select pg_temp.q('00000000-0000-4000-8000-0000000000b2', :'dev_b', '00000000-0000-4000-8000-000000000002', 'B-002');
select pg_temp.q('00000000-0000-4000-8000-0000000000b3', :'dev_b', null, 'B-003',
                 '{"name": "Tamu Baru", "phone": null, "category": "vip", "invitedPax": 2, "notes": null}');
select pg_temp.q('00000000-0000-4000-8000-0000000000b4', :'dev_b', '00000000-0000-4000-8000-000000000001', 'B-004');
select pg_temp.q('00000000-0000-4000-8000-0000000000b5', :'dev_b', '00000000-0000-4000-8000-000000000004', 'B-001');
select pg_temp.q('00000000-0000-4000-8000-0000000000c1', :'dev_c', '00000000-0000-4000-8000-000000000003', 'C-001');
select pg_temp.q('00000000-0000-4000-8000-0000000000c2', :'dev_c', '00000000-0000-4000-8000-000000000003', 'C-002');

select received_at as b3_received from public.check_ins where id = '00000000-0000-4000-8000-0000000000b3' \gset

-- ---------------------------------------------------------------------------------------------
-- Setujui per baris: evaluasi ulang pada saat persetujuan
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select is(public.admin_decide_quarantine(:'ev', 'approve', array['00000000-0000-4000-8000-0000000000b1']::uuid[]) -> 'results',
          '[{"id": "00000000-0000-4000-8000-0000000000b1", "status": "accepted"}]'::jsonb, 'setujui → accepted');
select is(public.admin_decide_quarantine(:'ev', 'approve', array['00000000-0000-4000-8000-0000000000b2']::uuid[]) -> 'results' -> 0 ->> 'status',
          'duplicate', 'tamu yang sudah punya accepted → duplicate (Lebih 1 Kali nonaktif)');
select is(public.admin_decide_quarantine(:'ev', 'approve', array['00000000-0000-4000-8000-0000000000b5']::uuid[]) -> 'results' -> 0 ->> 'status',
          'conflict', 'nomor tiket yang sudah dipakai accepted lain → conflict');
select is(public.admin_decide_quarantine(:'ev', 'approve', array['00000000-0000-4000-8000-0000000000b3']::uuid[]) -> 'results' -> 0 ->> 'status',
          'accepted', 'karantina dengan tamu baru disetujui → accepted');
reset role;
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-000000000001'), 'checked_in',
          'tamu menjadi Hadir setelah karantina disetujui');
select results_eq(
  $$ select g.name, g.category::text, g.invited_pax::integer, g.is_additional, g.created_device_id = c.device_id
     from public.check_ins c join public.guests g on g.id = c.guest_id where c.id = '00000000-0000-4000-8000-0000000000b3' $$,
  $$ values ('Tamu Baru'::text, 'vip'::text, 2, true, true) $$,
  'tamu tambahan baru dibuat saat disetujui, dari pending_guest');
select results_eq(
  format($$ select quarantine_reason::text, pending_guest is not null, received_at = %L::timestamptz from public.check_ins
     where id = '00000000-0000-4000-8000-0000000000b3' $$, :'b3_received'),
  $$ values ('device_revoked'::text, true, true) $$,
  'alasan karantina, data asli, dan received_at tetap tersimpan sebagai jejak');
select is((select reviewed_at from public.check_ins where id = '00000000-0000-4000-8000-0000000000b2'), null,
          'hasil Ganda dari persetujuan tetap perlu ditinjau');

-- ---------------------------------------------------------------------------------------------
-- Tolak: alasan wajib, data tetap
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select throws_ok(format($$ select public.admin_decide_quarantine(%L, 'reject', array['00000000-0000-4000-8000-0000000000b4']::uuid[]) $$, :'ev'),
                 '22023', null, 'tolak tanpa alasan ditolak');
select is(public.admin_decide_quarantine(:'ev', 'reject', array['00000000-0000-4000-8000-0000000000b4']::uuid[], null, 'Bukan dari usher kami') ->> 'decided',
          '1', 'tolak dengan alasan');
reset role;
select results_eq(
  $$ select status::text, voided_at is not null, void_reason, reviewed_at is not null from public.check_ins
     where id = '00000000-0000-4000-8000-0000000000b4' $$,
  $$ values ('quarantined'::text, true, 'Bukan dari usher kami'::text, true) $$,
  'karantina ditolak: tetap tersimpan sebagai dibatalkan beserta alasannya');

-- ---------------------------------------------------------------------------------------------
-- Per perangkat dan batas
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select is(public.admin_decide_quarantine(:'ev', 'approve', null, :'dev_c') -> 'results',
          '[{"id": "00000000-0000-4000-8000-0000000000c1", "status": "accepted"},
            {"id": "00000000-0000-4000-8000-0000000000c2", "status": "duplicate"}]'::jsonb,
          'setujui semua dari perangkat C, berurutan menurut waktu diterima');
select is(public.admin_decide_quarantine(:'ev', 'approve', null, :'dev_c') ->> 'decided', '0',
          'memutuskan ulang tidak mengubah apa pun');
select throws_ok(format($$ select public.admin_decide_quarantine(%L, 'approve', array[gen_random_uuid()], %L) $$, :'ev', :'dev_c'),
                 '22023', null, 'baris dan perangkat sekaligus ditolak');
select throws_ok(format($$ select public.admin_decide_quarantine(%L, 'hapus', null, %L) $$, :'ev', :'dev_c'),
                 '22023', null, 'keputusan selain approve/reject ditolak');
reset role;
select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.admin_decide_quarantine(%L, 'approve', null, %L) $$, :'ev', :'dev_b'),
                 '42501', null, 'Admin acara lain tidak bisa memutuskan karantina');
reset role;
select results_eq(
  format($$ select action, count(*)::integer from public.audit_logs where event_id = %L and action like 'quarantine_%%'
            group by action order by action $$, :'ev'),
  $$ values ('quarantine_approved'::text, 6), ('quarantine_rejected', 1) $$,
  'setiap keputusan karantina diaudit');

-- ---------------------------------------------------------------------------------------------
-- Undo (FR-RW-03) dan tandai ditinjau (FR-RW-05)
-- ---------------------------------------------------------------------------------------------
select tests.authenticate_as(:'admin_id');
select throws_ok($$ select public.admin_void_check_in('00000000-0000-4000-8000-0000000000a2', ' ') $$, '22023', null,
                 'undo tanpa alasan ditolak');
select lives_ok($$ select public.admin_void_check_in('00000000-0000-4000-8000-0000000000a2', 'Salah pindai') $$, 'undo dengan alasan');
select throws_ok($$ select public.admin_void_check_in('00000000-0000-4000-8000-0000000000a2', 'lagi') $$, '22023', null,
                 'check-in yang sudah dibatalkan tidak bisa dibatalkan lagi');
select throws_ok($$ select public.admin_void_check_in('00000000-0000-4000-8000-0000000000b4', 'x') $$, '22023', null,
                 'karantina tidak dibatalkan lewat undo');
reset role;
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-000000000002'), 'checked_in',
          'Dua tetap Hadir karena masih punya check-in Ganda yang aktif');
select is((select count(*)::integer from public.audit_logs where event_id = :'ev' and action = 'check_in_voided'), 1, 'undo diaudit');

select tests.authenticate_as(:'admin_id');
select is(public.admin_review_check_in('00000000-0000-4000-8000-0000000000b2') ->> 'changed', 'true', 'Ganda ditandai ditinjau');
select is(public.admin_review_check_in('00000000-0000-4000-8000-0000000000b2') ->> 'changed', 'false', 'menandai ulang tidak mengubah apa pun');
select throws_ok($$ select public.admin_review_check_in('00000000-0000-4000-8000-0000000000b1') $$, '22023', null,
                 'check-in Sah tidak perlu ditinjau');
reset role;
select is((select count(*)::integer from public.audit_logs where event_id = :'ev' and action = 'check_in_reviewed'), 1,
          'tinjauan diaudit sekali');

select * from finish();
rollback;
