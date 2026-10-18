-- Impor tamu (FR-G-03): satu transaksi, grup dibuat bila belum ada, galat menyebut nomor baris.
begin;
select plan(10);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Impor', :'admin_id') as ev \gset
insert into public.guest_groups (event_id, name) values (:'ev', 'Keluarga');
insert into public.guests (event_id, name, special_number) values (:'ev', 'Lama', 'VVIP-009');
select (private.config() ->> 'import_max_rows')::int as max_rows \gset

select tests.authenticate_as(:'admin_id');
select is(
  public.admin_import_guests(:'ev', $$[
    {"row": 2, "name": " Ani ", "phone": "+62811111111", "category": "vvip", "group": "keluarga", "invited_pax": 2,
     "special_number": "VVIP-001", "rsvp_status": "going", "rsvp_pax": 2, "notes": "Meja depan"},
    {"row": 3, "name": "Bayu", "group": "Teman Kantor"},
    {"row": 4, "name": "Cici", "group": "teman kantor", "category": "vip", "rsvp_status": "not_going"}
  ]$$::jsonb),
  '{"inserted": 3, "groups_created": 1}'::jsonb,
  'impor 3 baris; grup dicocokkan tanpa peka huruf besar/kecil, grup baru dibuat sekali');
reset role;

select results_eq(format($$
  select g.name, g.category::text, gg.name, g.invited_pax::int, g.special_number, g.rsvp_status::text, g.rsvp_pax::int
  from public.guests g left join public.guest_groups gg on gg.id = g.group_id
  where g.event_id = %L and g.name in ('Ani', 'Bayu', 'Cici') order by g.name $$, :'ev'),
  $$ values ('Ani'::text, 'vvip'::text, 'Keluarga'::text, 2, 'VVIP-001'::text, 'going'::text, 2),
            ('Bayu', 'regular', 'Teman Kantor', 1, null, 'unconfirmed', null),
            ('Cici', 'vip', 'Teman Kantor', 1, null, 'not_going', null) $$,
  'nilai baris dan default tersimpan benar');
select is((select (after ->> 'inserted')::int from public.audit_logs where event_id = :'ev' and action = 'guests_imported'), 3,
          'impor diaudit');

select count(*)::int as before_count from public.guests where event_id = :'ev' \gset

select tests.authenticate_as(:'admin_id');
select throws_like(format($$ select public.admin_import_guests(%L, '[{"row": 2, "name": "Oke"}, {"row": 5, "name": "Salah", "special_number": "A-017"}]') $$, :'ev'),
                   'Baris 5:%', 'nomor berpola nomor perangkat ditolak dengan nomor baris');
select throws_like(format($$ select public.admin_import_guests(%L, '[{"row": 7, "name": "Kembar", "special_number": "VVIP-009"}]') $$, :'ev'),
                   'Baris 7:%', 'nomor yang sudah dipakai di DB ditolak dengan nomor baris');
select throws_like(format($$ select public.admin_import_guests(%L, '[{"row": 3, "name": "X", "category": "raja"}]') $$, :'ev'),
                   'Baris 3:%', 'kategori tidak dikenal ditolak');
select throws_ok(format($$ select public.admin_import_guests(%L, (select jsonb_agg(jsonb_build_object('row', i, 'name', 'T' || i)) from generate_series(1, %s) i)) $$, :'ev', :max_rows + 1),
                 '22023', null, 'lebih dari import_max_rows baris ditolak');
reset role;

select is((select count(*)::int from public.guests where event_id = :'ev'), :before_count,
          'impor yang gagal tidak menyisakan baris apa pun (satu transaksi)');
select is((select count(*)::int from public.guest_groups where event_id = :'ev'), 2, 'impor yang gagal tidak menyisakan grup baru');

select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.admin_import_guests(%L, '[{"row": 2, "name": "Penyusup"}]') $$, :'ev'), '42501', null,
                 'Admin acara lain tidak bisa mengimpor');
reset role;

select * from finish();
rollback;
