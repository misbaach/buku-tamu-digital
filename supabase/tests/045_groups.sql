-- Grup tamu (FR-G-04): nama unik per acara (tanpa peka huruf besar/kecil); hapus = soft delete yang
-- melepas anggota dan memperbarui updated_at mereka (delta sync).
begin;
select plan(5);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Grup', :'admin_id') as ev \gset

select tests.authenticate_as(:'admin_id');
insert into public.guest_groups (event_id, name) values (:'ev', 'Keluarga');
select throws_ok(format($$ insert into public.guest_groups (event_id, name) values (%L, ' keluarga ') $$, :'ev'), '23505', null,
                 'nama grup ganda (beda huruf besar/kecil/spasi) ditolak');
reset role;

select id as grp from public.guest_groups where event_id = :'ev' and name = 'Keluarga' \gset
insert into public.guests (event_id, name, group_id, updated_at) values (:'ev', 'Anggota', :'grp', now() - interval '1 hour');

select tests.authenticate_as(:'admin_id');
update public.guest_groups set deleted_at = now() where id = :'grp';
reset role;

select is((select group_id from public.guests where name = 'Anggota'), null, 'tamu dilepas dari grup yang dihapus');
select ok((select updated_at > now() - interval '1 minute' from public.guests where name = 'Anggota'),
          'updated_at tamu ikut diperbarui');

select tests.authenticate_as(:'admin_id');
select lives_ok(format($$ insert into public.guest_groups (event_id, name) values (%L, 'Keluarga') $$, :'ev'),
                'nama grup yang sudah dihapus boleh dipakai lagi');
select throws_ok(format($$ delete from public.guest_groups where event_id = %L $$, :'ev'), '42501', null,
                 'grup tidak bisa dihapus permanen');
reset role;

select * from finish();
rollback;
