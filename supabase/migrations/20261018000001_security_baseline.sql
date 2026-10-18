-- Baseline keamanan (prd.md 10.4, 11.4)
-- 1. Role anon tidak punya hak apa pun di schema public, termasuk USAGE.
-- 2. Tidak ada objek baru di public yang otomatis bisa diakses role API; setiap GRANT ditulis eksplisit.
-- 3. Schema private (tidak diekspos API) untuk semua fungsi SECURITY DEFINER.
--
-- Catatan: ALTER DEFAULT PRIVILEGES ... IN SCHEMA hanya bisa menambah hak di atas default global, jadi
-- tidak mencabut EXECUTE bawaan PUBLIC pada fungsi baru. Karena itu setiap migration yang membuat fungsi
-- diakhiri REVOKE ... FROM public, anon secara eksplisit (aturan 5), dan tes 010 memeriksa hasilnya.

-- USAGE pada schema public diberikan ke PUBLIC secara bawaan, sehingga anon mewarisinya.
-- Cabut dari PUBLIC, lalu berikan kembali hanya ke role yang membutuhkannya.
revoke all on schema public from public;
revoke all on schema public from anon;
grant usage on schema public to authenticated, service_role;

revoke all on all tables in schema public from anon, authenticated, service_role;
revoke all on all sequences in schema public from anon, authenticated, service_role;
revoke all on all functions in schema public from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated, service_role;

create schema if not exists private;
revoke all on schema private from public, anon;
-- authenticated dan service_role perlu USAGE untuk memanggil fungsi private yang dipakai policy RLS dan
-- pembungkus RPC. Schema ini tidak ada di api.schemas, jadi tidak pernah bisa dipanggil lewat API.
grant usage on schema private to authenticated, service_role;
alter default privileges for role postgres in schema private revoke execute on functions from public, anon, authenticated, service_role;

-- Ekstensi untuk pencarian nama tamu (FR-G-08).
create extension if not exists pg_trgm with schema extensions;
