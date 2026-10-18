-- Acara: buat, ubah, arsipkan (alur 9, FR-R-10, K15).
begin;
select plan(16);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('admin.lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_user('usher@test.local', '{"role": "usher"}') as usher_id \gset
select tests.create_user('meta@test.local', '{}', '{"role": "admin"}') as meta_id \gset

select tests.authenticate_as(:'usher_id');
select throws_ok($$ select public.admin_create_event('X', current_date) $$, '42501', null, 'usher tidak bisa membuat acara');
reset role;
select tests.authenticate_as(:'meta_id');
select throws_ok($$ select public.admin_create_event('X', current_date) $$, '42501', null,
                 'role admin di user_metadata tidak cukup untuk membuat acara');
reset role;

select tests.authenticate_as(:'admin_id');
select lives_ok($$ select public.admin_create_event('Resepsi Uji', current_date, 'Ana & Budi', 'Gedung', 'Asia/Makassar') $$,
                'Admin membuat acara');
select throws_ok($$ select public.admin_create_event('Y', current_date, null, null, 'Mars/Olympus') $$, '22023', null,
                 'zona waktu tidak dikenal ditolak');
reset role;

select id as ev from public.events where name = 'Resepsi Uji' \gset
select matches((select code from public.events where id = :'ev'), '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$',
               'Kode Acara 6 karakter dari alfabet tanpa karakter mirip');
select is((select timezone from public.events where id = :'ev'), 'Asia/Makassar', 'zona waktu tersimpan');
select is((select count(*)::int from public.event_members where event_id = :'ev' and user_id = :'admin_id'), 1,
          'pembuat otomatis menjadi anggota');
select is((select count(*)::int from public.checkin_settings where event_id = :'ev'), 1, 'pengaturan check-in default dibuat');
select results_eq(format('select category::text, prefix from public.ticket_number_settings where event_id = %L order by 1', :'ev'),
                  $$ values ('vip', 'VIP-'), ('vvip', 'VVIP-') $$, 'setting Nomor Urut default VIP- dan VVIP-');
select is((select count(*)::int from public.greeting_configs where event_id = :'ev'), 3, 'konfigurasi sapaan per kategori');
select is((select action from public.audit_logs where event_id = :'ev' order by id limit 1), 'event_created', 'pembuatan acara diaudit');

select tests.authenticate_as(:'admin_id');
select lives_ok(format($$ select public.admin_update_event(%L, '{"name": "Resepsi Baru", "attendance_limit": 450}') $$, :'ev'),
                'Admin mengubah nama dan batas jumlah hadir');
select throws_ok(format($$ select public.admin_update_event(%L, '{"code": "AAAAAA"}') $$, :'ev'), '22023', null,
                 'Kode Acara tidak bisa diubah');
reset role;
select results_eq(format('select name, attendance_limit from public.events where id = %L', :'ev'),
                  $$ values ('Resepsi Baru'::text, 450) $$, 'perubahan tersimpan');

select tests.authenticate_as(:'other_id');
select throws_ok(format('select public.admin_archive_event(%L)', :'ev'), '42501', null, 'Admin acara lain tidak bisa mengarsipkan');
reset role;

select tests.authenticate_as(:'admin_id');
select public.admin_archive_event(:'ev');
reset role;
select ok((select archived_at is not null from public.events where id = :'ev')
          and exists (select 1 from public.audit_logs where event_id = :'ev' and action = 'event_archived'),
          'acara diarsipkan dan diaudit');

select * from finish();
rollback;
