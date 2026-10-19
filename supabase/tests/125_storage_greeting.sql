-- Storage foto pop-up sapaan (FR-P-01, prd.md 10.4): bucket privat, MIME raster saja, ≤ 5 MB, path per acara
-- dan kategori, hanya Admin acara tersebut; tanpa akses anon dan tanpa listing publik.
begin;
select plan(10);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Foto', :'admin_id') as ev \gset
select tests.create_usher(:'ev', 'Usher', 'AB') as usher \gset
select tests.create_device(:'ev', :'usher', 'A') as dev \gset
select :'ev' || '/vip/0b8f5f0e-3f43-4f4a-9a59-6f1f1d2b7c11.jpg' as path \gset

select results_eq(
  $$ select public, file_size_limit, allowed_mime_types from storage.buckets where id = 'greeting-photos' $$,
  $$ values (false, 5242880::bigint, array['image/png', 'image/jpeg', 'image/webp']) $$,
  'bucket privat, maksimal 5 MB, tanpa SVG');

select tests.authenticate_as(:'admin_id');
select lives_ok(format($$ insert into storage.objects (bucket_id, name) values ('greeting-photos', %L) $$, :'path'),
                'Admin mengunggah foto ke folder acaranya');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('greeting-photos', %L) $$,
                        :'ev' || '/vip/foto.svg'), '42501', null, 'nama/ekstensi di luar pola ditolak');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('greeting-photos', %L) $$,
                        :'ev' || '/umum/0b8f5f0e-3f43-4f4a-9a59-6f1f1d2b7c12.png'), '42501', null, 'kategori tidak dikenal ditolak');
select is((select count(*)::integer from storage.objects where bucket_id = 'greeting-photos'), 1, 'Admin melihat foto acaranya');
reset role;

select tests.authenticate_as(:'other_id');
select is((select count(*)::integer from storage.objects where bucket_id = 'greeting-photos'), 0, 'Admin acara lain tidak melihatnya');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('greeting-photos', %L) $$,
                        :'ev' || '/vvip/0b8f5f0e-3f43-4f4a-9a59-6f1f1d2b7c13.png'), '42501', null,
                 'Admin acara lain tidak bisa mengunggah ke folder acara ini');
reset role;

select tests.authenticate_as_device(:'dev');
select is((select count(*)::integer from storage.objects where bucket_id = 'greeting-photos'), 0,
          'perangkat usher tidak punya akses langsung (Q11 diputuskan bersama App Penerima Tamu)');
reset role;

select tests.authenticate_as_anon();
select is((select count(*)::integer from storage.objects where bucket_id = 'greeting-photos'), 0, 'anon tidak melihat apa pun');
select is((select count(*)::integer from storage.buckets), 0, 'anon tidak bisa me-list bucket');
reset role;

select * from finish();
rollback;
