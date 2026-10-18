-- Admin hanya melihat dan mengubah event tempat ia menjadi anggota (prd.md 11.4).
begin;
select plan(15);

select tests.create_user('admin.a@test.local', '{"role": "admin"}') as admin_a \gset
select tests.create_user('admin.b@test.local', '{"role": "admin"}') as admin_b \gset
select tests.create_user('admin.tanpa.event@test.local', '{"role": "admin"}') as admin_none \gset
select tests.create_user('anggota.bukan.admin@test.local', '{}') as member_no_role \gset

select tests.create_event('Acara A', :'admin_a') as event_a \gset
select tests.create_event('Acara B', :'admin_b') as event_b \gset
insert into public.event_members (event_id, user_id) values (:'event_a', :'member_no_role');

insert into public.guests (event_id, name) values (:'event_a', 'Tamu A1'), (:'event_a', 'Tamu A2'), (:'event_b', 'Tamu B1');
insert into public.ushers (event_id, name, pin_selector, pin_hash) values (:'event_b', 'Usher B', 'AB', 'x');
insert into public.audit_logs (event_id, actor_kind, action, entity) values (:'event_b', 'system', 'uji', 'events');

-- Admin A
select tests.authenticate_as(:'admin_a');
select results_eq('select id from public.events', format('values (%L::uuid)', :'event_a'), 'Admin A hanya melihat Acara A');
select results_eq('select count(*)::int from public.guests', 'values (2)', 'Admin A hanya melihat 2 tamu Acara A');
select is_empty(format('select 1 from public.guests where event_id = %L', :'event_b'), 'Admin A tidak melihat tamu Acara B');
select is_empty('select 1 from public.ushers', 'Admin A tidak melihat usher Acara B');
select is_empty('select 1 from public.audit_logs', 'Admin A tidak melihat audit log Acara B');
select lives_ok(format('insert into public.guests (event_id, name) values (%L, %L)', :'event_a', 'Tamu A3'),
                'Admin A bisa menambah tamu di Acara A');
select throws_ok(format('insert into public.guests (event_id, name) values (%L, %L)', :'event_b', 'Penyusup'),
                 '42501', null, 'Admin A tidak bisa menambah tamu di Acara B');
select is_empty(format('update public.guests set name = %L where event_id = %L returning 1', 'Diubah', :'event_b'),
                'Admin A tidak bisa mengubah tamu Acara B');
select throws_ok(format('update public.guests set event_id = %L where event_id = %L', :'event_b', :'event_a'),
                 '42501', null, 'event_id tamu tidak bisa diubah langsung (tidak ada column grant)');
select throws_ok('delete from public.guests', '42501', null, 'tamu tidak bisa dihapus permanen (hapus = soft delete)');
select throws_ok('select pin_hash from public.ushers', '42501', null, 'pin_hash tidak bisa dibaca Admin');
reset role;

-- Admin tanpa keanggotaan tidak melihat apa pun.
select tests.authenticate_as(:'admin_none');
select is_empty('select 1 from public.events', 'admin tanpa keanggotaan tidak melihat event apa pun');
select is_empty('select 1 from public.guests', 'admin tanpa keanggotaan tidak melihat tamu apa pun');
reset role;

-- Anggota event tanpa app_metadata.role = admin tetap tidak lolos (policy restrictive).
select tests.authenticate_as(:'member_no_role');
select is_empty('select 1 from public.events', 'anggota tanpa role admin tidak melihat event');
select is_empty('select 1 from public.guests', 'anggota tanpa role admin tidak melihat tamu');
reset role;

select * from finish();
rollback;
