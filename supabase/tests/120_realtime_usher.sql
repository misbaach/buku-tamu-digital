-- Realtime usher (aturan 9, FR-R-06): Broadcast privat `event:{id}:usher` dipicu trigger DB, satu sinyal per
-- transaksi, dan hanya perangkat SAH event tersebut yang lolos policy realtime.messages.
begin;
select plan(11);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Sinyal', :'admin_id') as ev \gset
select tests.create_event('Acara Lain', :'admin_id') as ev2 \gset
select tests.create_usher(:'ev', 'Usher Satu', 'AB') as usher \gset
select tests.create_usher(:'ev2', 'Usher Lain', 'AB') as usher2 \gset
select tests.create_device(:'ev', :'usher', 'A') as dev_ok \gset
select tests.create_device(:'ev', :'usher', 'B') as dev_rev \gset
select tests.create_device(:'ev', :'usher', 'C', now() - interval '1 hour') as dev_exp \gset
select tests.create_device(:'ev2', :'usher2', 'A') as dev_other \gset
update public.devices set revoked_at = now(), revoke_mode = 'quarantine' where id = :'dev_rev';
select 'event:' || :'ev' || ':usher' as topic \gset

-- Trigger: beberapa perubahan dalam satu transaksi → satu sinyal (T-014).
select count(*) as before from realtime.messages where topic = :'topic' \gset
update public.checkin_settings set allow_multi_checkin = true where event_id = :'ev';
update public.greeting_configs set popup = '{"title": "Halo {{nama}}"}' where event_id = :'ev' and category = 'vip';
insert into public.guests (event_id, name) select :'ev', 'Tamu ' || i from generate_series(1, 50) i;
select is((select count(*)::integer from realtime.messages where topic = :'topic') - :before, 1,
          'pengaturan, sapaan, dan 50 tamu baru dalam satu transaksi → satu sinyal');
select results_eq(
  format($$ select event, private, payload - 'id' from realtime.messages where topic = %L $$, :'topic'),
  $$ values ('sync'::text, true, '{"kind": "sync"}'::jsonb) $$,
  'sinyal privat tanpa data tamu (perangkat lalu memanggil pull_snapshot)');

-- Policy: dibaca sebagai masing-masing pemanggil dengan realtime.topic() = topik acara.
create function pg_temp.visible(p_topic text) returns integer language plpgsql as $$
declare n integer;
begin
  perform set_config('realtime.topic', p_topic, true);
  select count(*) into n from realtime.messages where topic = p_topic;
  return n;
end;
$$;
grant execute on function pg_temp.visible(text) to authenticated, anon;

select tests.authenticate_as_device(:'dev_ok');
select is(pg_temp.visible(:'topic'), 1, 'perangkat sah acara ini menerima sinyal');
reset role;
select tests.authenticate_as_device(:'dev_rev');
select is(pg_temp.visible(:'topic'), 0, 'perangkat yang dicabut tidak menerima sinyal');
reset role;
select tests.authenticate_as_device(:'dev_exp');
select is(pg_temp.visible(:'topic'), 0, 'perangkat dengan sesi berakhir tidak menerima sinyal');
reset role;
select tests.authenticate_as_device(:'dev_other');
select is(pg_temp.visible(:'topic'), 0, 'perangkat acara lain tidak bisa mendengarkan topik acara ini');
reset role;
select tests.authenticate_as(:'admin_id');
select is(pg_temp.visible(:'topic'), 0, 'Admin tidak mendengarkan topik usher');
reset role;
select tests.authenticate_as_anon();
select is(pg_temp.visible(:'topic'), 0, 'anon tidak menerima sinyal (RLS tanpa policy untuk anon)');
reset role;

update public.events set archived_at = now() where id = :'ev';
select tests.authenticate_as_device(:'dev_ok');
select is(pg_temp.visible(:'topic'), 0, 'setelah acara diarsipkan, perangkat tidak menerima sinyal lagi');
reset role;

-- Postgres Changes tidak dipakai: tidak ada tabel public di publikasi supabase_realtime.
select is_empty($$ select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' $$,
                'tidak ada tabel public di publikasi supabase_realtime (tanpa Postgres Changes)');
select ok(not exists (select 1 from pg_policies where schemaname = 'realtime' and tablename = 'messages'
                      and cmd in ('INSERT', 'ALL') and 'authenticated' = any (roles)),
          'klien tidak bisa mengirim Broadcast; sinyal hanya dari trigger DB');

select * from finish();
rollback;
