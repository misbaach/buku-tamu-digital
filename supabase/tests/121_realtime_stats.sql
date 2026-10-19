-- Realtime statistik (FR-S-07, aturan 9): check-in memicu satu sinyal per transaksi di `event:{id}:stats`,
-- dan hanya Admin acara tersebut yang lolos policy realtime.messages.
begin;
select plan(7);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Statistik Live', :'admin_id') as ev \gset
select tests.create_event('Acara Lain', :'other_id') as ev2 \gset
select tests.create_usher(:'ev', 'Usher', 'AB') as usher \gset
select tests.create_device(:'ev', :'usher', 'A') as dev \gset
select 'event:' || :'ev' || ':stats' as topic \gset

insert into public.guests (id, event_id, name) values ('00000000-0000-4000-8000-000000000001', :'ev', 'Satu'),
  ('00000000-0000-4000-8000-000000000002', :'ev', 'Dua');
-- Insert tamu di atas sudah memicu sinyal transaksi ini; penandanya dikosongkan agar push diuji seolah transaksi baru.
select set_config('bukutamu.stats_signal_' || replace(:'ev', '-', ''), '', true);
select count(*) as before from realtime.messages where topic = :'topic' \gset
select jsonb_build_array(
  tests.push_item(gen_random_uuid(), :'dev', '00000000-0000-4000-8000-000000000001', 'A-001'),
  tests.push_item(gen_random_uuid(), :'dev', '00000000-0000-4000-8000-000000000002', 'A-002')) as items \gset
select tests.authenticate_as_device(:'dev');
select public.push_outbox(:'items'::jsonb);
reset role;
select is((select count(*)::integer from realtime.messages where topic = :'topic') - :before, 1,
          'dua check-in dalam satu push → satu sinyal statistik');
select results_eq(format($$ select distinct event, private, payload - 'id' from realtime.messages where topic = %L $$, :'topic'),
                  $$ values ('stats'::text, true, '{"kind": "stats"}'::jsonb) $$, 'sinyal privat tanpa data');

create function pg_temp.visible(p_topic text) returns integer language plpgsql as $$
declare n integer;
begin
  perform set_config('realtime.topic', p_topic, true);
  select count(*) into n from realtime.messages where topic = p_topic;
  return n;
end;
$$;
grant execute on function pg_temp.visible(text) to authenticated, anon;

select tests.authenticate_as(:'admin_id');
select is(pg_temp.visible(:'topic'), 2, 'Admin acara ini menerima sinyal statistik (insert tamu dan push)');
reset role;
select tests.authenticate_as(:'other_id');
select is(pg_temp.visible(:'topic'), 0, 'Admin acara lain tidak menerima sinyal statistik');
reset role;
select tests.authenticate_as_device(:'dev');
select is(pg_temp.visible(:'topic'), 0, 'perangkat usher tidak mendengarkan topik statistik');
reset role;
select tests.authenticate_as_anon();
select is(pg_temp.visible(:'topic'), 0, 'anon tidak menerima apa pun');
reset role;
select tests.authenticate_with_claims(jsonb_build_object('sub', :'admin_id', 'app_metadata', '{"role": "admin"}'));
select is(pg_temp.visible('event:bukan-uuid:stats'), 0, 'topik dengan format rusak ditolak tanpa galat');
reset role;

select * from finish();
rollback;
