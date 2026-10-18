-- Token QR tamu dan kolom yang dilindungi (FR-G-07, FR-HM-01, prd.md 10.4).
begin;
select plan(11);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Kolom', :'admin_id') as ev \gset
insert into public.guests (event_id, name) select :'ev', 'Tamu ' || i from generate_series(1, 200) i;
select id as gid from public.guests where event_id = :'ev' and name = 'Tamu 1' \gset

select is_empty(format($$ select qr_token from public.guests where event_id = %L and qr_token !~ '^[A-Za-z0-9_-]{24}$' $$, :'ev'),
                'token QR 24 karakter base64url (18 byte = 144 bit)');
select is((select count(distinct qr_token)::int from public.guests where event_id = :'ev'), 200, 'token QR tidak berulang');
select is_empty(format($$ select 1 from public.guests where event_id = %L and qr_token_hash <> encode(sha256(convert_to(qr_token, 'UTF8')), 'hex') $$, :'ev'),
                'qr_token_hash = SHA-256 hex dari token (sama dengan Web Crypto di perangkat)');

select tests.authenticate_as(:'admin_id');
select throws_ok(format($$ update public.guests set qr_token = 'x' where id = %L $$, :'gid'), '42501', null, 'qr_token tidak bisa diubah Admin');
select throws_ok(format($$ update public.guests set attendance_status = 'checked_in' where id = %L $$, :'gid'), '42501', null,
                 'kehadiran tidak bisa diubah langsung (hanya lewat check-in)');
select throws_ok(format($$ update public.guests set is_additional = true where id = %L $$, :'gid'), '42501', null,
                 'penanda tamu tambahan tidak bisa diubah langsung');
select throws_ok(format($$ insert into public.guests (event_id, name, qr_token) values (%L, 'Token sendiri', 'aaaaaaaaaaaaaaaaaaaaaaaa') $$, :'ev'),
                 '42501', null, 'token QR tidak bisa ditentukan sendiri saat menambah tamu');
select lives_ok(format($$ update public.guests set name = 'Nama Baru', rsvp_status = 'going', rsvp_pax = 2, phone = '+62 812-3456-7890' where id = %L $$, :'gid'),
                'kolom data tamu biasa bisa diubah');
select throws_ok(format($$ update public.guests set rsvp_status = 'not_going', rsvp_pax = 2 where id = %L $$, :'gid'), '23514', null,
                 'pax RSVP hanya boleh diisi bila Akan hadir');
select throws_ok(format($$ update public.guests set phone = 'telepon saya' where id = %L $$, :'gid'), '23514', null,
                 'format telepon divalidasi DB');
select lives_ok(format($$ update public.guests set deleted_at = now() where id = %L $$, :'gid'), 'hapus tamu = soft delete');
reset role;

select * from finish();
rollback;
