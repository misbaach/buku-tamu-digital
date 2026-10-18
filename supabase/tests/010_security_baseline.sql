-- Baseline keamanan (prd.md 10.4, aturan 1, 2, 5): diperiksa dari katalog sehingga objek baru yang lupa
-- di-REVOKE atau lupa diberi RLS langsung membuat tes gagal.
begin;
select plan(14);

-- anon tidak punya hak apa pun di schema public (dan private).
select ok(not has_schema_privilege('anon', 'public', 'USAGE'), 'anon tidak punya USAGE di schema public');
select ok(not has_schema_privilege('anon', 'private', 'USAGE'), 'anon tidak punya USAGE di schema private');
select ok(not has_schema_privilege('public', 'public', 'USAGE'), 'PUBLIC tidak punya USAGE di schema public');

select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm', 'f')
    and case when c.relkind in ('r', 'p', 'v', 'm', 'f') then
          has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
          or has_any_column_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, REFERENCES') else false end
$$, 'anon tidak punya hak tabel/view/kolom apa pun');

select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind = 'S'
    and case when c.relkind = 'S' then has_sequence_privilege('anon', c.oid, 'USAGE, SELECT, UPDATE') else false end
$$, 'anon tidak punya hak sequence apa pun');

select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'EXECUTE')
$$, 'anon tidak bisa mengeksekusi fungsi apa pun di public/private');

select is_empty($$
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
       aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  where n.nspname in ('public', 'private') and a.grantee = 0 and a.privilege_type = 'EXECUTE'
$$, 'tidak ada fungsi di public/private yang bisa dieksekusi PUBLIC (REVOKE eksplisit, aturan 5)');

select is_empty($$
  select a.privilege_type
  from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace, aclexplode(d.defaclacl) a
  where n.nspname = 'public' and a.grantee = 'anon'::regrole and d.defaclrole = 'postgres'::regrole
$$, 'default privileges postgres di schema public tidak memberi apa pun ke anon');
-- Default privileges milik supabase_admin (platform) tidak bisa diubah role postgres; objek apa pun di public
-- tetap tidak terjangkau anon karena anon tidak punya USAGE pada schema public (tes pertama di atas).

-- Uji langsung: query sebagai anon ditolak di level schema.
select tests.authenticate_as_anon();
select throws_ok('select count(*) from public.guests', '42501', null, 'query anon ke tabel public ditolak');
reset role;

-- RLS aktif di semua tabel public (aturan 1).
select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
$$, 'RLS aktif di semua tabel public');

-- Semua view public memakai security_invoker (RLS tabel dasar tetap berlaku).
select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'v'
    and not coalesce(c.reloptions @> array['security_invoker=true'], false)
$$, 'semua view public memakai security_invoker = true');

-- SECURITY DEFINER hanya di schema private (aturan 5).
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.prosecdef and n.nspname = 'public'
$$, 'tidak ada fungsi SECURITY DEFINER di schema public');

select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and not coalesce(p.proconfig @> array['search_path=""'], false)
$$, 'semua fungsi di public/private memakai search_path kosong');

-- service_role tidak punya hak tabel langsung; Edge Function bekerja lewat fungsi svc_*.
select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v')
    and case when c.relkind in ('r', 'p', 'v') then
          has_table_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')
          or has_any_column_privilege('service_role', c.oid, 'SELECT, INSERT, UPDATE') else false end
$$, 'service_role tidak punya hak tabel langsung di public');

select * from finish();
rollback;
