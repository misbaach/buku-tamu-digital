-- Pencabutan perangkat dan pembersihan user Auth (FR-R-08, FR-R-10, 11.5 langkah 6–7, K26, K34).
begin;
select plan(23);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_user('lain@test.local', '{"role": "admin"}') as other_id \gset
select tests.create_event('Acara Cabut', :'admin_id') as ev \gset
select tests.create_event('Acara Arsip', :'admin_id') as ev_arc \gset
select tests.create_usher(:'ev', 'Usher Satu', 'AB') as usher \gset
select tests.create_usher(:'ev_arc', 'Usher Arsip', 'AB') as usher_arc \gset

-- ---------------------------------------------------------------------------------------------
-- admin_revoke_device: Cabut, lalu naik ke putus total; tidak bisa turun
-- ---------------------------------------------------------------------------------------------
select tests.create_device(:'ev', :'usher', 'A') as dev \gset
select tests.authenticate_as(:'other_id');
select throws_ok(format($$ select public.admin_revoke_device(%L, 'quarantine') $$, :'dev'), '42501', null,
                 'Admin acara lain tidak bisa mencabut perangkat');
reset role;
select tests.authenticate_as(:'admin_id');
select is(public.admin_revoke_device(:'dev', 'quarantine') ->> 'changed', 'true', 'Cabut (alasan opsional)');
select is(public.admin_revoke_device(:'dev', 'quarantine') ->> 'changed', 'false', 'Cabut ulang tidak mengubah apa pun');
select throws_ok(format($$ select public.admin_revoke_device(%L, 'terminate') $$, :'dev'), '22023', null,
                 'putus total tanpa alasan ditolak');
select is(public.admin_revoke_device(:'dev', 'terminate', 'HP hilang') ->> 'revoke_mode', 'terminate',
          'Cabut bisa dinaikkan ke putus total');
select throws_ok(format($$ select public.admin_revoke_device(%L, 'quarantine') $$, :'dev'), '22023', null,
                 'putus total tidak bisa diturunkan lewat RPC');
reset role;
select results_eq(
  format($$ select after ->> 'mode', after ->> 'reason' from public.audit_logs
            where action = 'device_revoked' and entity_id = %L order by id $$, :'dev'),
  $$ values ('quarantine'::text, null::text), ('terminate', 'HP hilang') $$,
  'kedua tingkat pencabutan diaudit beserta alasannya');
select is((select revoked_by from public.devices where id = :'dev'), :'admin_id'::uuid, 'pencabut tercatat');

-- Trigger menjaga aturan yang sama untuk jalur tulis mana pun.
select throws_ok(format($$ update public.devices set revoke_mode = 'quarantine' where id = %L $$, :'dev'), '22023', null,
                 'trigger: terminate tidak bisa turun ke quarantine');
select throws_ok(format($$ update public.devices set revoked_at = null, revoke_mode = null where id = %L $$, :'dev'), '22023', null,
                 'trigger: pencabutan tidak bisa dibatalkan');

-- svc_terminated_device_user hanya menjawab untuk perangkat bertingkat terminate.
select tests.create_device(:'ev', :'usher', 'B') as dev_b \gset
select is(public.svc_terminated_device_user(:'dev_b'), null::uuid, 'perangkat aktif: tidak ada user yang boleh dihapus');
select is(public.svc_terminated_device_user(:'dev'), (select auth_user_id from public.devices where id = :'dev'),
          'perangkat terminate: user Auth-nya dikembalikan untuk dihapus');

-- ---------------------------------------------------------------------------------------------
-- devices_due_for_cleanup(p_now): tepat perangkat yang jatuh tempo
-- ---------------------------------------------------------------------------------------------
select tests.create_device(:'ev', :'usher', 'C', now() - interval '73 hours') as dev_old \gset
select tests.create_device(:'ev', :'usher', 'D', now() - interval '71 hours') as dev_grace \gset
select tests.create_device(:'ev', :'usher', 'E') as dev_term_done \gset
update public.devices set revoked_at = now(), revoke_mode = 'terminate', auth_user_deleted_at = now() where id = :'dev_term_done';
select tests.create_device(:'ev_arc', :'usher_arc', 'A', now() + interval '10 days') as dev_arc \gset
update public.events set archived_at = now() - interval '73 hours' where id = :'ev_arc';

select set_eq(
  $$ select device_id from private.devices_due_for_cleanup(now()) $$,
  format($$ values (%L::uuid), (%L::uuid), (%L::uuid) $$, :'dev', :'dev_old', :'dev_arc'),
  'jatuh tempo: terminate yang belum dibersihkan, sesi habis > 72 jam, dan acara diarsipkan > 72 jam');
select ok(not exists (select 1 from private.devices_due_for_cleanup(now()) where device_id = :'dev_grace'),
          'sesi habis 71 jam lalu masih dalam masa tenggang');
select ok(exists (select 1 from private.devices_due_for_cleanup(now() + interval '2 hours') where device_id = :'dev_grace'),
          'dua jam kemudian perangkat itu jatuh tempo (fungsi menerima waktu sebagai parameter)');
select is((select count(*)::integer from public.svc_devices_due_for_cleanup(2)), 2, 'svc_devices_due_for_cleanup menghormati limit');

select public.svc_mark_auth_user_deleted(:'dev_old');
select ok((select auth_user_deleted_at is not null from public.devices where id = :'dev_old'), 'penghapusan user Auth dicatat');
select lives_ok(format($$ select public.svc_mark_auth_user_deleted(%L) $$, :'dev_old'), 'menandai ulang aman (idempoten)');
select ok(not exists (select 1 from private.devices_due_for_cleanup(now()) where device_id = :'dev_old'),
          'perangkat yang sudah dibersihkan tidak muncul lagi');

-- ---------------------------------------------------------------------------------------------
-- Job terjadwal dan larangan SQL ke auth.users
-- ---------------------------------------------------------------------------------------------
select results_eq(
  $$ select schedule, command from cron.job where jobname = 'device-cleanup-sweep' $$,
  $$ values ((private.config() ->> 'device_cleanup_schedule')::text, 'select private.invoke_device_cleanup()'::text) $$,
  'job pg_cron device-cleanup-sweep terdaftar dengan jadwal dari konfigurasi');
select ok((select prosrc from pg_proc where oid = 'private.invoke_device_cleanup()'::regprocedure) ~ 'vault\.decrypted_secrets'
          and (select prosrc from pg_proc where oid = 'private.invoke_device_cleanup()'::regprocedure) !~* 'service_role',
          'job membaca URL dan secret dari Vault, bukan service role key');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ~* 'auth\.users'
$$, 'tidak ada fungsi di public/private yang menyentuh auth.users (penghapusan hanya lewat Admin API)');
select ok(not has_function_privilege('authenticated', 'public.svc_terminated_device_user(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'public.svc_mark_auth_user_deleted(uuid)', 'execute')
          and not has_function_privilege('authenticated', 'public.svc_devices_due_for_cleanup(integer)', 'execute'),
          'fungsi pembersihan hanya untuk service_role');

select * from finish();
rollback;
