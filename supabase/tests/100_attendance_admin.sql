-- Ubah Detail Kehadiran (FR-A-02, FR-C-07) dan turunan kehadiran tamu (FR-G-09).
begin;
select plan(16);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Hadir', :'admin_id') as ev \gset
insert into public.guests (id, event_id, name) values
  ('00000000-0000-4000-8000-00000000a001', :'ev', 'Satu'),
  ('00000000-0000-4000-8000-00000000a002', :'ev', 'Dua');

-- Check-in sintetis berjalur unggahan Admin (source tanpa perangkat), satu accepted dan satu conflict.
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, checked_in_at) values
  ('00000000-0000-4000-8000-00000000c001', :'ev', '00000000-0000-4000-8000-00000000a001', 2, 'A-001', 'accepted', 'outbox_upload', now()),
  ('00000000-0000-4000-8000-00000000c002', :'ev', '00000000-0000-4000-8000-00000000a002', 1, 'A-001', 'conflict', 'outbox_upload', now());

select is((select attendance_status::text from public.guests where name = 'Satu'), 'checked_in', 'check-in membuat tamu Hadir');

select tests.authenticate_as(:'admin_id');
select is(public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', '{"actual_pax": 3}', 'Membawa satu anak') ->> 'status',
          'accepted', 'jumlah hadir diubah');
select is(public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', jsonb_build_object('checked_out_at', now())) ->> 'status',
          'accepted', 'check-out dicatat');
reset role;
select is((select attendance_status::text from public.guests where name = 'Satu'), 'checked_out', 'tamu menjadi Sudah keluar');
select tests.authenticate_as(:'admin_id');
select lives_ok($$ select public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', '{"checked_out_at": null}') $$,
                'check-out bisa dibatalkan');
reset role;
select is((select attendance_status::text from public.guests where name = 'Satu'), 'checked_in', 'tamu kembali Hadir');

-- Conflict diselesaikan dengan nomor baru → dievaluasi ulang menjadi accepted.
select tests.authenticate_as(:'admin_id');
select is(public.admin_update_check_in('00000000-0000-4000-8000-00000000c002', '{"ticket_number": "a-002"}', 'Nomor ganda') ->> 'status',
          'accepted', 'conflict dengan nomor baru menjadi accepted (nomor dinormalisasi huruf besar)');
select throws_ok($$ select public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', '{"ticket_number": "A-002"}') $$,
                 '23505', null, 'nomor yang sudah dipakai check-in sah lain ditolak dengan pesan jelas');
select throws_ok($$ select public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', '{"status": "accepted"}') $$,
                 '22023', null, 'status tidak bisa diubah langsung');
reset role;

select is((select count(*)::int from public.audit_logs where event_id = :'ev' and action = 'check_in_updated'), 4,
          'setiap perubahan detail kehadiran diaudit');
select is((select after ->> 'reason' from public.audit_logs where event_id = :'ev' and action = 'check_in_updated' order by id limit 1),
          'Membawa satu anak', 'alasan perubahan tersimpan di audit');

update public.check_ins set voided_at = now(), void_reason = 'uji' where id = '00000000-0000-4000-8000-00000000c002';
select is((select attendance_status::text from public.guests where name = 'Dua'), 'not_arrived', 'check-in dibatalkan → Belum hadir');
select tests.authenticate_as(:'admin_id');
select throws_ok($$ select public.admin_update_check_in('00000000-0000-4000-8000-00000000c002', '{"actual_pax": 2}') $$,
                 '22023', null, 'check-in yang dibatalkan tidak bisa diubah');
reset role;

-- Check-in karantina tidak membuat tamu Hadir sampai disetujui (FR-G-09); setelah statusnya sah, tamu Hadir.
insert into public.guests (id, event_id, name) values ('00000000-0000-4000-8000-00000000a003', :'ev', 'Tiga');
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, quarantine_reason, checked_in_at) values
  ('00000000-0000-4000-8000-00000000c003', :'ev', '00000000-0000-4000-8000-00000000a003', 1, 'A-003', 'quarantined', 'outbox_upload', 'device_revoked', now());
select is((select attendance_status::text from public.guests where name = 'Tiga'), 'not_arrived', 'check-in karantina → tetap Belum hadir');
update public.check_ins set status = 'accepted' where id = '00000000-0000-4000-8000-00000000c003';
select is((select attendance_status::text from public.guests where name = 'Tiga'), 'checked_in', 'karantina disahkan → Hadir');

select tests.authenticate_as(:'other_id');
select throws_ok($$ select public.admin_update_check_in('00000000-0000-4000-8000-00000000c001', '{"actual_pax": 9}') $$,
                 '42501', null, 'Admin acara lain tidak bisa mengubah');
reset role;

select * from finish();
rollback;
