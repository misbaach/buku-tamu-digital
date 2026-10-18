-- user_metadata bisa diubah pengguna sendiri, jadi tidak pernah dipakai untuk otorisasi (prd.md 10.4, aturan 3).
begin;
select plan(5);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Meta', :'admin_id') as event_id \gset
insert into public.guests (event_id, name) values (:'event_id', 'Tamu');

-- Anggota event yang hanya punya role admin di user_metadata.
select tests.create_user('palsu@test.local', '{}', '{"role": "admin"}') as fake_admin \gset
insert into public.event_members (event_id, user_id) values (:'event_id', :'fake_admin');
select tests.authenticate_as(:'fake_admin');
select is_empty('select 1 from public.guests', 'role admin di user_metadata tidak memberi akses');
select ok(not private.is_event_admin(:'event_id'), 'is_event_admin mengabaikan user_metadata');
reset role;

-- Usher yang menulis role admin ke user_metadata.
select tests.create_user('usher@test.local', jsonb_build_object('role', 'usher', 'event_id', :'event_id'),
                         '{"role": "admin"}') as usher_id \gset
insert into public.event_members (event_id, user_id) values (:'event_id', :'usher_id');
select tests.authenticate_as(:'usher_id');
select is_empty('select 1 from public.guests', 'usher dengan user_metadata.role admin tetap tidak punya akses');
reset role;

-- Admin sah dengan user_metadata role usher tetap Admin (user_metadata diabaikan ke dua arah).
update auth.users set raw_user_meta_data = '{"role": "usher"}' where id = :'admin_id';
select tests.authenticate_as(:'admin_id');
select results_eq('select count(*)::int from public.guests', 'values (1)', 'Admin tetap Admin walau user_metadata berisi role lain');
reset role;

-- Klaim JWT tanpa app_metadata (mis. token buatan sendiri) tidak memberi akses.
select tests.authenticate_with_claims(jsonb_build_object('sub', :'admin_id', 'user_metadata', '{"role": "admin"}'::jsonb));
select is_empty('select 1 from public.guests', 'klaim tanpa app_metadata.role admin tidak memberi akses');
reset role;

select * from finish();
rollback;
