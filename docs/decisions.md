# Log Keputusan Teknis

Keputusan yang **tidak** mengubah skema DB, kontrak RPC/Edge Function, atau aturan keamanan (`prd.md` 10.4/11.4). Keputusan yang mengubah hal-hal tersebut ditulis di `prd.md`. Satu baris per keputusan; yang terbaru di bawah.

| # | Tanggal | Keputusan | Alasan |
|---|---|---|---|
| T-001 | 2026-10-18 | Dashboard berupa SPA statis (SvelteKit `adapter-static`, `ssr = false`) | Auth Supabase cukup di browser; tidak ada server yang perlu diamankan |
| T-002 | 2026-10-18 | UI: Tailwind CSS v4 + bits-ui (pola copy-paste shadcn-svelte), di-restyle memakai token sendiri | Primitif aksesibel untuk dialog, menu, dan tab dengan bundle kecil |
| T-003 | 2026-10-18 | Font IBM Plex Sans + IBM Plex Mono, di-host sendiri via `@fontsource` | Angka tabular dan kode mudah dibaca; tidak perlu domain font di CSP |
| T-004 | 2026-10-18 | Ikon `@lucide/svelte`; penanda tinjauan memakai `TriangleAlert` | SVG yang tree-shaken; satu ikon untuk semua status "— tinjau" |
| T-005 | 2026-10-18 | CSP lewat `kit.csp` mode `hash` + `static/_headers` | Hash skrip dibuat otomatis saat build; header lain lewat Cloudflare Pages |
| T-006 | 2026-10-18 | Zod 4 di `packages/shared`; Edge Function memakai salinan hasil generate di `supabase/functions/_shared`, dan salinan basi membuat tes gagal | Bundler Edge Function tidak dijamin bisa mengimpor dari luar `functions/` |
| T-007 | 2026-10-18 | Nilai konfigurasi yang dipakai DB disalin ke `private.config()` lewat migration; tes paritas membandingkannya dengan `config.ts` | Satu sumber nilai tanpa membuat migration lama ikut berubah |
| T-008 | 2026-10-18 | Helper pgTAP ditulis sendiri (`supabase/tests/000_helpers.sql`) | Tanpa dependensi pihak ketiga |
| T-009 | 2026-10-18 | Jumlah bcrypt per percobaan login diuji dengan mengganti sementara `private.verify_secret` di dalam transaksi tes (versi yang mencatat panggilan, lalu di-rollback) | `pg_stat_user_functions` butuh `track_functions` yang hanya bisa diubah superuser |
| T-010 | 2026-10-18 | Secret scan: `lefthook` (devDependency dipin) + binary gitleaks dipin dengan checksum di `.tools/`; CI memakai binary yang sama, bukan `gitleaks-action` | `gitleaks-action` butuh lisensi untuk akun organisasi; versi lokal dan CI sama |
| T-011 | 2026-10-18 | `.env.example` hanya boleh berisi `NAMA=<NAMA>` atau `NAMA=`; diperiksa tes `tests/repo/env-example.test.ts` | Arahan K27; aturannya cukup ketat untuk dicek mesin |
| T-012 | 2026-10-18 | Kunci Supabase lokal dibaca saat runtime dari `supabase status -o env`, tidak pernah ditulis ke file | Tidak ada kunci di repo, termasuk kunci lokal |
| T-013 | 2026-10-18 | `push_outbox` diserialkan per event dengan `pg_advisory_xact_lock` | Status deterministik; skala 10 perangkat |
| T-014 | 2026-10-18 | Broadcast Realtime dikirim sekali per transaksi per topik (penanda `set_config(..., true)`) | Satu batch 200 item hanya menghasilkan satu sinyal |
| T-015 | 2026-10-18 | Respons gagal `usher-login` ditahan sampai minimal `USHER_LOGIN_FAIL_MIN_MS` (500 ms) | Melengkapi bcrypt dummy agar perbedaan waktu lookup tidak terlihat |
| T-016 | 2026-10-18 | `device-cleanup` idempoten: user Auth yang sudah tidak ada dianggap berhasil dihapus | Job dan putus total bisa berjalan bersamaan atau diulang tanpa galat |
| T-017 | 2026-10-18 | Job `device-cleanup-sweep` berjalan tiap 15 menit (`DEVICE_CLEANUP_SCHEDULE`) | Cukup cepat untuk mengulang putus total yang gagal; beban kecil |
| T-018 | 2026-10-18 | Diff persetujuan `prd.md` dibuat terhadap v0.4 (salinan di scratchpad sesi), bukan terhadap draf v0.5 sebelumnya | Teks draf pertama belum pernah dibaca utuh oleh pemilik produk |
| T-019 | 2026-10-18 | `packageManager: pnpm@10.34.7` (cabang 10.x yang masih dirawat), bukan 12.x | Perilaku dan format konfigurasi pnpm 10 sudah pasti; risiko kejutan lebih kecil |
| T-020 | 2026-10-18 | corepack 0.36.0 dipasang ke prefix npm pengguna, karena Node 25 tidak lagi membawa corepack. Node sistem (v25) tidak diubah | Instruksi memakai corepack; mengganti Node sistem bisa memengaruhi proyek lain di mesin ini |
| T-021 | 2026-10-18 | `minimumReleaseAge: 10080` (7 hari) di `pnpm-workspace.yaml`; semua versi dipin ke rilis berumur ≥ 7 hari | Mitigasi paket npm yang dibajak tepat setelah terbit |
| T-022 | 2026-10-18 | Hanya `lefthook` dan `supabase` yang boleh menjalankan skrip install (`onlyBuiltDependencies`); daftar ditambah per kebutuhan | Default pnpm 10 memblokir skrip install; daftar eksplisit lebih aman |
| T-023 | 2026-10-18 | Skrip gitleaks digabung menjadi `scripts/gitleaks.mjs` (unduh + verifikasi SHA-256 + jalankan), bukan `install-gitleaks.mjs` terpisah | Satu pintu untuk hook, CI, dan pemakaian manual |
| T-024 | 2026-10-18 | `.gitattributes` `* text=auto eol=lf` | Berkas SQL dan skrip harus LF, termasuk saat diedit di Windows |
| T-025 | 2026-10-18 | CI memakai Node 24 LTS (bukan 22 seperti di rencana awal) | Node 24 adalah LTS aktif per Oktober 2026 |
