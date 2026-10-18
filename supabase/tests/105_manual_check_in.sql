-- Tandai hadir manual oleh Admin (docs/plan.md 10.4, prd.md 12.3 poin 15).
-- Kasus 6 (statistik) dan 7 (bentuk checkIn di pull_snapshot) ditambahkan di M3 dan M2 bersama fungsinya.
begin;
select plan(13);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_user('usher@test.local', '{"role": "usher"}') as usher_id \gset
select tests.create_event('Acara Manual', :'admin_id') as ev \gset
insert into public.guests (id, event_id, name, special_number) values
  ('00000000-0000-4000-8000-00000000b001', :'ev', 'Tanpa Nomor 1', null),
  ('00000000-0000-4000-8000-00000000b002', :'ev', 'Tanpa Nomor 2', null),
  ('00000000-0000-4000-8000-00000000b003', :'ev', 'VIP Bernomor', 'VIP-007'),
  ('00000000-0000-4000-8000-00000000b004', :'ev', 'Penumpang', null),
  ('00000000-0000-4000-8000-00000000b005', :'ev', 'Perangkat', null);

-- 1. Dua tamu tanpa nomor khusus → keduanya accepted dengan nomor tiket NULL, tanpa pelanggaran unique index.
select tests.authenticate_as(:'admin_id');
select is(public.admin_manual_check_in('00000000-0000-4000-8000-00000000b001', 1) ->> 'status', 'accepted', 'kasus 1a: accepted');
select is(public.admin_manual_check_in('00000000-0000-4000-8000-00000000b002', 2) ->> 'status', 'accepted', 'kasus 1b: accepted juga');
reset role;
select is((select count(*)::int from public.check_ins where event_id = :'ev' and source = 'admin' and ticket_number is null and status = 'accepted'), 2,
          'kasus 1: dua check-in manual tanpa nomor tersimpan berdampingan');

-- 2. Tamu bernomor khusus → nomor tiket = nomor khusus; check-in lain dengan nomor itu menjadi conflict.
select tests.authenticate_as(:'admin_id');
select is(public.admin_manual_check_in('00000000-0000-4000-8000-00000000b003', 1) ->> 'ticket_number', 'VIP-007',
          'kasus 2a: nomor tiket = Nomor Urut khusus tamu');
reset role;
select is(private.store_check_in(gen_random_uuid(), :'ev', '00000000-0000-4000-8000-00000000b004', 1, 'VIP-007',
                                 'outbox_upload', null, null, null, now())::text,
          'conflict', 'kasus 2b: nomor yang sama milik tamu lain → conflict');

-- 3. Nomor perangkat biasa tidak dianggap bentrok dengan baris ber-nomor NULL.
select is(private.store_check_in(gen_random_uuid(), :'ev', '00000000-0000-4000-8000-00000000b005', 1, 'A-001',
                                 'outbox_upload', null, null, null, now())::text,
          'accepted', 'kasus 3: A-001 diterima walau ada banyak baris tanpa nomor');

-- 4. Nomor tiket NULL hanya untuk source admin.
select throws_ok(format($$ insert into public.check_ins (id, event_id, guest_id, actual_pax, status, source, checked_in_at)
                           values (gen_random_uuid(), %L, '00000000-0000-4000-8000-00000000b005', 1, 'accepted', 'outbox_upload', now()) $$, :'ev'),
                 '23514', null, 'kasus 4: nomor tiket NULL dari selain Admin ditolak constraint');

-- 5. Tandai hadir untuk tamu yang sudah accepted mengikuti pengaturan Check-In Lebih 1 Kali.
select tests.authenticate_as(:'admin_id');
select is(public.admin_manual_check_in('00000000-0000-4000-8000-00000000b001', 1) ->> 'status', 'duplicate',
          'kasus 5a: Check-In Lebih 1 Kali nonaktif → duplicate');
reset role;
update public.checkin_settings set allow_multi_checkin = true where event_id = :'ev';
select tests.authenticate_as(:'admin_id');
select is(public.admin_manual_check_in('00000000-0000-4000-8000-00000000b001', 1) ->> 'status', 'repeat',
          'kasus 5b: Check-In Lebih 1 Kali aktif → repeat');
reset role;

-- 6 (sementara, sampai statistik ada di M3): tamu tanpa nomor tetap tercatat Hadir.
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-00000000b002'), 'checked_in',
          'kasus 6 (M1): check-in manual tanpa nomor membuat tamu Hadir');

-- 8. Tepat satu baris audit per panggilan.
select is((select count(*)::int from public.audit_logs where event_id = :'ev' and action = 'manual_check_in'), 5,
          'kasus 8: lima panggilan → lima baris audit manual_check_in');

-- 9. Bukan Admin acara ini → ditolak.
select tests.authenticate_as(:'other_id');
select throws_ok($$ select public.admin_manual_check_in('00000000-0000-4000-8000-00000000b004', 1) $$, '42501', null,
                 'kasus 9a: Admin acara lain ditolak');
reset role;
select tests.authenticate_as(:'usher_id');
select throws_ok($$ select public.admin_manual_check_in('00000000-0000-4000-8000-00000000b004', 1) $$, '42501', null,
                 'kasus 9b: JWT usher ditolak');
reset role;

select * from finish();
rollback;
