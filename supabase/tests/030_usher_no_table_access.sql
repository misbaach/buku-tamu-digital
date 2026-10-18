-- Usher tidak punya hak SELECT/INSERT/UPDATE/DELETE langsung pada tabel mana pun (prd.md 10.4, D5, aturan 4).
-- Usher bahkan dijadikan anggota event_members agar terbukti bahwa yang menolak adalah policy restrictive
-- berbasis app_metadata, bukan sekadar ketiadaan keanggotaan.
begin;
select plan(13);

select tests.create_user('admin@test.local', '{"role": "admin"}') as admin_id \gset
select tests.create_event('Acara Usher', :'admin_id') as event_id \gset
insert into public.ushers (id, event_id, name, pin_selector, pin_hash)
values ('00000000-0000-4000-8000-0000000000a1', :'event_id', 'Usher Satu', 'AB', 'x');
select tests.create_user('device@test.local', jsonb_build_object(
  'role', 'usher', 'event_id', :'event_id', 'usher_id', '00000000-0000-4000-8000-0000000000a1',
  'device_id', '00000000-0000-4000-8000-0000000000d1')) as usher_user \gset
insert into public.event_members (event_id, user_id) values (:'event_id', :'usher_user');
insert into public.devices (id, event_id, usher_id, code, auth_user_id, session_expires_at)
values ('00000000-0000-4000-8000-0000000000d1', :'event_id', '00000000-0000-4000-8000-0000000000a1', 'A', :'usher_user', now() + interval '1 day');
insert into public.guests (event_id, name) values (:'event_id', 'Tamu Satu');
insert into public.guest_groups (event_id, name) values (:'event_id', 'Keluarga');
insert into public.audit_logs (event_id, actor_kind, action, entity) values (:'event_id', 'system', 'uji', 'events');
insert into public.auth_attempts (kind, method, ip, event_id, success) values ('usher_login', 'pin', '10.0.0.1', :'event_id', false);

-- Batas hak menurut katalog: authenticated tidak punya DELETE/TRUNCATE di mana pun, dan INSERT/UPDATE
-- hanya pada daftar tabel yang ditulis Admin lewat PostgREST.
select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
    and case when c.relkind in ('r', 'p') then has_table_privilege('authenticated', c.oid, 'DELETE, TRUNCATE') else false end
$$, 'authenticated tidak punya DELETE/TRUNCATE di tabel mana pun');
select results_eq($$
  select c.relname::text collate "default" from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and case when c.relkind in ('r', 'p') then has_any_column_privilege('authenticated', c.oid, 'INSERT') else false end
  order by 1
$$, $$ values ('guest_groups'), ('guests') $$, 'INSERT langsung hanya pada guest_groups dan guests');
select results_eq($$
  select c.relname::text collate "default" from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and case when c.relkind in ('r', 'p') then has_any_column_privilege('authenticated', c.oid, 'UPDATE') else false end
  order by 1
$$, $$ values ('checkin_settings'), ('greeting_configs'), ('guest_groups'), ('guests'), ('ticket_number_settings') $$,
'UPDATE langsung hanya pada tabel pengaturan, grup, dan tamu');

-- Sebagai usher: SELECT ke setiap tabel menghasilkan 0 baris atau ditolak.
create temp table usher_reads (tbl text, outcome text);
grant insert on usher_reads to authenticated;
select tests.authenticate_as(:'usher_user');
do $$
declare
  t record;
  n bigint;
begin
  for t in select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
           where ns.nspname = 'public' and c.relkind in ('r', 'p') loop
    begin
      execute format('select count(*) from (select 1 from public.%I) s', t.relname) into n;
      insert into usher_reads values (t.relname, case when n = 0 then 'kosong' else n || ' baris' end);
    exception when insufficient_privilege then
      insert into usher_reads values (t.relname, 'ditolak');
    end;
  end loop;
end;
$$;
reset role;
select is_empty($$ select tbl || ': ' || outcome from usher_reads where outcome not in ('kosong', 'ditolak') $$,
                'usher tidak bisa membaca baris dari tabel mana pun');
select ok((select count(*) from usher_reads) >= 13, 'semua tabel public ikut diuji');

select tests.authenticate_as(:'usher_user');
select throws_ok(format('insert into public.guests (event_id, name) values (%L, %L)', :'event_id', 'Tamu Palsu'),
                 '42501', null, 'usher tidak bisa menambah tamu');
select throws_ok(format('insert into public.guest_groups (event_id, name) values (%L, %L)', :'event_id', 'Grup Palsu'),
                 '42501', null, 'usher tidak bisa menambah grup');
select is_empty('update public.guests set name = name returning 1', 'usher tidak bisa mengubah tamu');
select is_empty('update public.guest_groups set name = name returning 1', 'usher tidak bisa mengubah grup');
select is_empty('update public.checkin_settings set show_verification = show_verification returning 1',
                'usher tidak bisa mengubah pengaturan check-in');
select is_empty('update public.ticket_number_settings set digits = digits returning 1',
                'usher tidak bisa mengubah setting Nomor Urut');
select is_empty('update public.greeting_configs set popup = popup returning 1', 'usher tidak bisa mengubah sapaan');
select ok(not private.is_event_admin(:'event_id'), 'usher tidak dianggap Admin event');
reset role;

select * from finish();
rollback;
