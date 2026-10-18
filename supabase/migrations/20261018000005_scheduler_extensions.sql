-- Ekstensi untuk job terjadwal (prd.md 11.5 langkah 7). Job device-cleanup didaftarkan di M2.
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- Catatan: event trigger Supabase (grant_pg_net_access) memberi anon/authenticated USAGE pada schema net,
-- dengan grantor supabase_admin. Role postgres tidak bisa mencabut grant milik role lain, sehingga REVOKE di
-- sini tidak berefek. Schema net tidak ada di api.schemas, dan tes integrasi anon-access.test.ts memastikan
-- net tidak bisa dipanggil lewat API (lihat docs/decisions.md T-028).
