-- Statistik (FR-S-01..05, plan.md 10.3 & 12, D11, D14): hanya accepted + conflict yang menambah jumlah orang;
-- repeat, duplicate, karantina, dan yang dibatalkan tidak dihitung; batas manual vs total undangan.
-- Termasuk 105 kasus 6: tandai hadir manual tanpa nomor dihitung sama dengan check-in biasa.
begin;
select plan(24);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Statistik', :'admin_id') as ev \gset

insert into public.guests (id, event_id, name, category, invited_pax, rsvp_status, rsvp_pax, is_additional) values
  ('00000000-0000-4000-8000-000000000001', :'ev', 'G1 datang lebih', 'regular', 2, 'going', 2, false),
  ('00000000-0000-4000-8000-000000000002', :'ev', 'G2 masuk ulang', 'vip', 1, 'unconfirmed', null, false),
  ('00000000-0000-4000-8000-000000000003', :'ev', 'G3 bentrok', 'vvip', 2, 'going', 2, false),
  ('00000000-0000-4000-8000-000000000004', :'ev', 'G4 manual', 'regular', 1, 'going', 1, false),
  ('00000000-0000-4000-8000-000000000005', :'ev', 'G5 karantina', 'regular', 3, 'going', 3, false),
  ('00000000-0000-4000-8000-000000000006', :'ev', 'G6 dibatalkan', 'regular', 4, 'not_going', null, false),
  ('00000000-0000-4000-8000-000000000007', :'ev', 'G7 tambahan', 'regular', 1, 'unconfirmed', null, true),
  ('00000000-0000-4000-8000-000000000008', :'ev', 'G8 belum datang', 'regular', 2, 'going', 2, false),
  ('00000000-0000-4000-8000-000000000009', :'ev', 'G9 dihapus', 'regular', 5, 'going', 5, false);
update public.guests set deleted_at = now() where id = '00000000-0000-4000-8000-000000000009';

insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, checked_in_at) values
  ('00000000-0000-4000-8000-0000000000c1', :'ev', '00000000-0000-4000-8000-000000000001', 3, 'A-001', 'accepted', 'outbox_upload', '2026-10-18T12:01:00Z'),
  ('00000000-0000-4000-8000-0000000000c2', :'ev', '00000000-0000-4000-8000-000000000002', 1, 'A-002', 'accepted', 'outbox_upload', '2026-10-18T12:05:00Z'),
  ('00000000-0000-4000-8000-0000000000c3', :'ev', '00000000-0000-4000-8000-000000000002', 2, 'A-003', 'repeat', 'outbox_upload', '2026-10-18T12:40:00Z'),
  ('00000000-0000-4000-8000-0000000000c4', :'ev', '00000000-0000-4000-8000-000000000002', 5, 'A-004', 'duplicate', 'outbox_upload', '2026-10-18T12:41:00Z'),
  ('00000000-0000-4000-8000-0000000000c5', :'ev', '00000000-0000-4000-8000-000000000003', 2, 'A-001', 'conflict', 'outbox_upload', '2026-10-18T12:20:00Z'),
  ('00000000-0000-4000-8000-0000000000c7', :'ev', '00000000-0000-4000-8000-000000000007', 2, 'A-007', 'accepted', 'outbox_upload', '2026-10-18T12:31:00Z');
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, quarantine_reason, source, checked_in_at) values
  ('00000000-0000-4000-8000-0000000000c8', :'ev', '00000000-0000-4000-8000-000000000005', 3, 'A-008', 'quarantined', 'device_revoked', 'outbox_upload', '2026-10-18T12:10:00Z');
insert into public.check_ins (id, event_id, guest_id, actual_pax, ticket_number, status, source, checked_in_at, voided_at, void_reason) values
  ('00000000-0000-4000-8000-0000000000c9', :'ev', '00000000-0000-4000-8000-000000000006', 4, 'A-006', 'accepted', 'outbox_upload', '2026-10-18T12:12:00Z', now(), 'salah tamu');
update public.check_ins set checked_out_at = now() where id = '00000000-0000-4000-8000-0000000000c1';

select tests.authenticate_as(:'admin_id');
select public.admin_manual_check_in('00000000-0000-4000-8000-000000000004', 1);
select public.get_event_stats(:'ev') as s \gset
reset role;

select is((:'s'::jsonb ->> 'peoplePresent')::integer, 9,
          'jumlah orang = accepted + conflict (3 + 1 + 2 + 1 + 2); repeat, duplicate, karantina, dibatalkan tidak dihitung');
select is((:'s'::jsonb ->> 'rsvpGoingGuests')::integer, 5, 'pembanding: tamu Akan hadir (tanpa tamu dihapus/tambahan)');
select is((:'s'::jsonb ->> 'rsvpGoingPax')::integer, 10, 'pembanding: Σ jumlah Akan hadir');
select is((:'s'::jsonb ->> 'invitedTotal')::integer, 15, 'total undangan: tanpa tamu tambahan dan tamu dihapus');
select is(:'s'::jsonb ->> 'limitSource', 'invited_total', 'batas kosong → memakai total undangan (D14)');
select is((:'s'::jsonb ->> 'limit')::integer, 15, 'nilai batas = total undangan');
select is((:'s'::jsonb ->> 'overLimit')::boolean, false, 'belum melebihi batas');
select is(:'s'::jsonb -> 'categories',
  '[{"category": "vvip", "people": 2, "rsvpPax": 2, "guestsPresent": 1},
    {"category": "vip", "people": 1, "rsvpPax": 0, "guestsPresent": 1},
    {"category": "regular", "people": 6, "rsvpPax": 8, "guestsPresent": 3}]'::jsonb,
  'hadir per kategori VVIP/VIP/Regular dengan pembanding Akan hadir (FR-S-02)');
select is((:'s'::jsonb ->> 'invitedCheckedIn')::integer, 4, 'tamu undangan yang sudah masuk (FR-S-03)');
select is((:'s'::jsonb ->> 'guestsPresent')::integer, 5, 'tamu hadir');
select is((:'s'::jsonb ->> 'guestsCheckedOut')::integer, 1, 'tamu sudah check-out (FR-S-04)');
select is((:'s'::jsonb ->> 'additionalGuests')::integer, 1, 'tamu tambahan (FR-S-05)');
select is((:'s'::jsonb ->> 'additionalPeople')::integer, 2, 'orang dari tamu tambahan');
select is((:'s'::jsonb ->> 'beyondRecorded')::integer, 1, 'orang di luar jumlah tercatat (G1: 3 dari 2)');
select is(:'s'::jsonb -> 'review', '{"quarantined": 1, "duplicate": 1, "conflict": 1}'::jsonb,
          'perlu ditinjau: karantina, ganda, bentrok');

-- 105 kasus 6: tandai hadir manual tanpa nomor ikut dihitung sebagai tamu dan orang.
select is((select attendance_status::text from public.guests where id = '00000000-0000-4000-8000-000000000004'), 'checked_in',
          'tandai hadir manual tanpa nomor: tamu Hadir');
select is((select ticket_number from public.check_ins where guest_id = '00000000-0000-4000-8000-000000000004'), null,
          'check-in manual itu memang tanpa nomor tiket');

-- Batas manual.
update public.events set attendance_limit = 8 where id = :'ev';
select tests.authenticate_as(:'admin_id');
select public.get_event_stats(:'ev') as s2 \gset
reset role;
select is(:'s2'::jsonb ->> 'limitSource', 'manual', 'batas diatur manual → sumber manual');
select is((:'s2'::jsonb ->> 'overLimit')::boolean, true, '9 orang melebihi batas 8 → peringatan');

-- Linimasa.
select tests.authenticate_as(:'admin_id');
select is((select sum(people)::integer from public.get_arrival_timeline(:'ev', 15)), 9, 'linimasa menjumlahkan orang yang sama');
select is((select guests from public.get_arrival_timeline(:'ev', 15)
           where bucket_start = '2026-10-18T12:00:00Z'), 2, 'interval 12.00–12.15 berisi G1 dan G2');
select is((select count(*)::integer from public.get_arrival_timeline(:'ev', 15)
           where bucket_start between '2026-10-18T12:15:00Z' and '2026-10-18T12:45:00Z'), 2,
          'repeat/duplicate (12.40) tidak membuat interval baru; 12.15 dan 12.30 terisi');
reset role;

-- Hanya Admin acara ini.
select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.get_event_stats(%L) $$, :'ev'), '42501', null, 'Admin acara lain tidak bisa melihat statistik');
select throws_ok(format($$ select * from public.get_arrival_timeline(%L) $$, :'ev'), '42501', null, 'linimasa juga terlindungi');
reset role;

select * from finish();
rollback;
