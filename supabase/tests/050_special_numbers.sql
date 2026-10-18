-- Nomor Urut khusus: unik per acara, Terapkan dengan pratinjau, hapus massal (FR-C-02..05).
begin;
select plan(18);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Nomor', :'admin_id') as ev \gset
select tests.create_event('Acara Lain', :'other_id') as ev2 \gset

-- Urutan input: Citra lebih dulu, lalu Andi. Budi sudah VIP-001; tamu Regular memakai VIP-002.
insert into public.guests (event_id, name, category, created_at) values (:'ev', 'Citra', 'vip', now() - interval '3 minutes');
insert into public.guests (event_id, name, category, created_at) values (:'ev', 'Andi', 'vip', now() - interval '2 minutes');
insert into public.guests (event_id, name, category, special_number) values (:'ev', 'Budi', 'vip', 'VIP-001');
insert into public.guests (event_id, name, category, special_number) values (:'ev', 'Reguler', 'regular', 'VIP-002');
insert into public.guests (event_id, name, category, special_number) values (:'ev', 'Raja', 'vvip', 'VVIP-001');

-- Unik per acara; nomor tamu yang sudah dihapus boleh dipakai lagi.
select throws_ok(format($$ insert into public.guests (event_id, name, special_number) values (%L, 'Kembar', 'VIP-001') $$, :'ev'),
                 '23505', null, 'nomor khusus ganda dalam satu acara ditolak');
select lives_ok(format($$ insert into public.guests (event_id, name, special_number) values (%L, 'Beda acara', 'VIP-001') $$, :'ev2'),
                'nomor yang sama boleh di acara lain');
update public.guests set deleted_at = now() where event_id = :'ev2' and name = 'Beda acara';
select lives_ok(format($$ insert into public.guests (event_id, name, special_number) values (%L, 'Pengganti', 'VIP-001') $$, :'ev2'),
                'nomor tamu yang sudah dihapus boleh dipakai lagi');

select tests.authenticate_as(:'admin_id');
select results_eq(
  format($$ select r->>'guest_name', r->>'new_number' from jsonb_array_elements(public.admin_preview_special_numbers(%L, 'vip', 'name') -> 'rows') r $$, :'ev'),
  $$ values ('Andi', 'VIP-003'), ('Citra', 'VIP-004') $$,
  'pratinjau urut nama: hanya yang belum bernomor, nomor yang sudah dipakai (lintas kategori) dilewati');
select results_eq(
  format($$ select r->>'guest_name', r->>'new_number' from jsonb_array_elements(public.admin_preview_special_numbers(%L, 'vip', 'input') -> 'rows') r $$, :'ev'),
  $$ values ('Citra', 'VIP-003'), ('Andi', 'VIP-004') $$, 'pratinjau urut input');
select throws_ok(format($$ select public.admin_apply_special_numbers(%L, 'vip', 'name', false, 'hash-basi') $$, :'ev'),
                 '40001', null, 'hash pratinjau yang berbeda ditolak');
select public.admin_preview_special_numbers(:'ev', 'vip', 'name') ->> 'hash' as h \gset
select is(public.admin_apply_special_numbers(:'ev', 'vip', 'name', false, :'h'), 2, 'Terapkan menyimpan 2 nomor');
reset role;

select results_eq(format($$ select name, special_number from public.guests where event_id = %L and category = 'vip' order by name $$, :'ev'),
                  $$ values ('Andi'::text, 'VIP-003'::text), ('Budi', 'VIP-001'), ('Citra', 'VIP-004') $$, 'nomor tersimpan');
select is((select (after ->> 'count')::int from public.audit_logs where event_id = :'ev' and action = 'special_numbers_applied'), 2,
          'Terapkan Nomor Urut diaudit');

-- Overwrite: semua tamu VIP diberi nomor ulang; nomor bertukar pemilik tanpa melanggar unique index.
select tests.authenticate_as(:'admin_id');
select public.admin_preview_special_numbers(:'ev', 'vip', 'name', true) ->> 'hash' as h2 \gset
select is(public.admin_apply_special_numbers(:'ev', 'vip', 'name', true, :'h2'), 3, 'overwrite menomori ulang 3 tamu');
reset role;
select results_eq(format($$ select name, special_number from public.guests where event_id = %L and category = 'vip' order by name $$, :'ev'),
                  $$ values ('Andi'::text, 'VIP-001'::text), ('Budi', 'VIP-003'), ('Citra', 'VIP-004') $$,
                  'overwrite: mulai dari awal, VIP-002 milik tamu lain tetap dilewati');

-- Digit tidak memotong angka; nomor > 20 karakter ditolak sebelum disimpan.
update public.ticket_number_settings set start_number = 999, digits = 3 where event_id = :'ev' and category = 'vip';
update public.guests set special_number = null where event_id = :'ev' and category = 'vip';
select tests.authenticate_as(:'admin_id');
select results_eq(
  format($$ select r->>'new_number' from jsonb_array_elements(public.admin_preview_special_numbers(%L, 'vip', 'name') -> 'rows') r $$, :'ev'),
  $$ values ('VIP-999'), ('VIP-1000'), ('VIP-1001') $$, 'angka melebihi jumlah digit tidak dipotong');
reset role;
select throws_ok(format($$ update public.ticket_number_settings set prefix = 'A-' where event_id = %L and category = 'vip' $$, :'ev'),
                 '23514', null, 'prefix yang menghasilkan pola nomor perangkat ditolak DB');
update public.ticket_number_settings set prefix = 'ABCDEFGHIJKLMNOP-', start_number = 999 where event_id = :'ev' and category = 'vip';
select tests.authenticate_as(:'admin_id');
select throws_ok(format($$ select public.admin_preview_special_numbers(%L, 'vip', 'name') $$, :'ev'), '22023', null,
                 'nomor yang melebihi 20 karakter ditolak saat pratinjau');

select results_eq(format($$ select special_number, guest_name from public.admin_check_special_numbers(%L, array['VVIP-001', 'TIDAK-ADA']) $$, :'ev'),
                  $$ values ('VVIP-001'::text, 'Raja'::text) $$, 'cek nomor untuk Tinjau Tamu mengembalikan yang sudah dipakai');

select is(public.admin_clear_special_numbers(:'ev', array(select id from public.guests where event_id = :'ev' and name in ('Raja', 'Andi'))), 1,
          'hapus massal hanya menghitung tamu yang punya nomor');
reset role;
select ok(exists (select 1 from public.audit_logs where event_id = :'ev' and action = 'special_numbers_cleared'),
          'hapus massal Nomor Urut diaudit');

select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.admin_preview_special_numbers(%L, 'vip', 'name') $$, :'ev'), '42501', null,
                 'Admin acara lain tidak bisa melihat pratinjau');
reset role;

select * from finish();
rollback;
