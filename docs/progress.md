# Progres

## M1 — Admin inti · selesai, menunggu konfirmasi

Branch: `m1-admin-inti` (dari `m0-fondasi`; belum di-merge ke `main`).

### Yang selesai

- **Acara:**
  - Buat acara; Kode Acara dibuat server.
  - Ubah detail dan arsipkan dengan konfirmasi.
  - Acara milik Admin lain atau id acak tampil sebagai "tidak ditemukan".
- **Kelola Tamu:**
  - Tabel dengan paginasi di server.
  - Cari nama/Nomor Urut; filter kategori, grup, RSVP, dan kehadiran, tersimpan di URL.
  - Tambah, ubah, dan hapus lewat dialog, termasuk ubah RSVP manual.
  - Ikon kategori di daftar.
- **Pilih massal:** ubah kategori atau grup; hapus Nomor Urut terpilih dengan konfirmasi.
- **Impor .xlsx/.xls/.csv:**
  - Unduh templat.
  - Tinjau Tamu menampilkan galat per baris, termasuk nomor ganda di berkas maupun di DB dan nomor berpola nomor perangkat.
  - Proses dalam satu transaksi; grup baru dibuat otomatis.
- **Grup:** tambah, ubah, hapus. Menghapus grup melepas anggotanya; tamunya tidak ikut terhapus.
- **QR tamu:** pratinjau dan unduh PNG.
- **Nomor Urut:**
  - Setting prefix, angka awal, dan digit untuk VIP dan VVIP.
  - Terapkan dengan pratinjau, urut nama / grup lalu nama / urutan input.
  - Nomor lama hanya ditimpa bila dikonfirmasi; pratinjau yang sudah basi ditolak.
  - Hapus semua nomor.
- **Kehadiran per tamu (FR-A-01):** panel Kehadiran berisi status, waktu, jumlah, nomor tiket, usher, dan perangkat.
- **Ubah Detail Kehadiran (FR-A-02):**
  - Tandai hadir manual (`source = 'admin'`, K22).
  - Ubah jumlah hadir atau nomor tiket dengan alasan.
  - Check-out dan pembatalannya.
- **Batas jumlah hadir opsional** (D14).
- **Audit log:** buat/ubah/arsip acara, Terapkan/hapus Nomor Urut, impor, tandai hadir manual, ubah detail kehadiran (termasuk nomor tiket dan check-out).
- **Konstanta baru:** `IMPORT_MAX_ROWS` di `config.ts`, dicerminkan ke `private.config()` lewat migration 0007.

### FR dan bukti tes

| FR | Bukti |
|---|---|
| G-01 CRUD tamu | E2E `guests.spec` (tambah, ubah, hapus); pgTAP `065` (kolom dan constraint) |
| G-02 Tambah manual | E2E `guests.spec` |
| G-03 Impor | Vitest `import.test`, `parse.test`; pgTAP `060` (satu transaksi, nomor baris di galat, batas baris dari config); E2E `import.spec` (1.000 baris, 3 bermasalah) |
| G-04 Grup | pgTAP `045`; E2E `bulk-groups.spec` |
| G-05 Edit massal | E2E `bulk-groups.spec` |
| G-06 Edit detail + RSVP | E2E `guests.spec`; Vitest `guest.test` (aturan jumlah konfirmasi) |
| G-07 QR unik, unduh | pgTAP `065` (token 144 bit, tidak berulang, hash = SHA-256, tidak bisa diubah Admin); E2E `guests.spec` (unduh PNG). *Salin link di M4 (D17).* |
| G-08 Cari, filter, paginasi server | E2E `guests.spec` (URL dan Back), `import.spec` (1.000 tamu: halaman 1 dan 2) |
| G-09 Kehadiran | pgTAP `100` (Hadir, Sudah keluar, dibatalkan, karantina tidak membuat Hadir), `105` |
| C-01 Kategori + ikon | E2E `guests.spec` (mahkota/bintang/tanpa ikon), `bulk-groups.spec` |
| C-02 Nomor Urut | Vitest `patterns.test`, `guest.test`; integrasi `special-number-parity`; pgTAP `050`, `065`; E2E `guests.spec` (pola perangkat dan nomor ganda ditolak, huruf kecil dinormalisasi) |
| C-03 Setting Nomor Urut | pgTAP `050` (prefix berpola perangkat ditolak DB); E2E `numbering-attendance.spec` |
| C-04 Terapkan | pgTAP `050` (urutan, tanpa timpa, pratinjau basi ditolak, audit); E2E `numbering-attendance.spec` |
| C-05 Ubah, impor, hapus massal | pgTAP `050`, `060`; E2E `bulk-groups.spec` |
| C-07 Snapshot + tetapkan ulang tiket | pgTAP `100`, `105` |
| A-01 Kehadiran per tamu | E2E `numbering-attendance.spec` |
| A-02 Ubah detail + hadir manual | pgTAP `100`, `105`; E2E `numbering-attendance.spec` |

**FR-C-06 dan C-08** adalah aturan server di `push_outbox`, jadi ditandai selesai di M2 bersama tes sinkronisasinya. Fungsi penentu status (`private.evaluate_check_in_status`, `private.store_check_in`) sudah dibuat di M1 dan dipakai bersama.

### Hasil tes

| Rangkaian | Hasil |
|---|---|
| `pnpm lint` (ESLint + Prettier) | bersih |
| `pnpm typecheck` | bersih |
| `pnpm test:unit` (Vitest: shared, repo, dashboard) | 59 lulus |
| `node scripts/gen-db-types.mjs --check` | tipe DB sesuai skema |
| `pnpm db:test` (pgTAP) | 137 lulus |
| `pnpm test:integration` (termasuk paritas `config.ts` ↔ `private.config()`) | 52 lulus |
| `svelte-check` | 0 galat, 0 peringatan |
| `pnpm test:e2e` (Playwright + axe WCAG 2.2 AA) | 34 lulus |
| `pnpm secrets:scan` | tidak ada kebocoran |

**Uji mutasi:** `private.evaluate_check_in_status` dipaksa selalu `accepted` → `105` gagal 9 dari 13 tes. Setelah `db:reset`, semua kembali lulus.

### Ditunda (dengan alasan)

| Item | Alasan |
|---|---|
| Salin link `/i/{token}` | M4 bersama halamannya (D17); format URL sudah dikunci di `config.ts` |
| pgTAP `105` kasus 6 (statistik) dan 7 (`checkIn` di `pull_snapshot`) | Ditulis bersama fungsinya: `get_event_stats` (M3) dan `pull_snapshot` (M2) |
| Arsip acara menolak pull/push usher | Diperiksa di `pull_snapshot`/`push_outbox` (M2); di M1 belum ada perangkat |
| Angka total undangan di samping batas jumlah hadir | Tampil di Statistik M3 (T-044) |

### Temuan selama M1

1. Zod 4 mencoba mode JIT (`new Function`) dan memicu pelanggaran CSP. Diatasi dengan `jitless`, CSP tidak dilonggarkan (T-042).
2. `xlsx` di npm tertahan di versi lama yang punya celah keamanan. SheetJS resmi disimpan di `vendor/` (T-036).
3. PostgREST membatasi 1.000 baris per permintaan, jadi "hapus semua Nomor Urut" mengambil id per halaman.

### Cara menguji secara lokal

Persiapan sama seperti M0. Setelah menarik perubahan, jalankan `pnpm install` lalu `pnpm db:reset`, karena ada migration 0006 dan 0007.

```powershell
pnpm lint
pnpm typecheck
pnpm test:unit
pnpm db:test
pnpm test:integration
pnpm --filter @guestbook/dashboard test:e2e
```

Mencoba manual (`pnpm --filter @guestbook/dashboard dev`, masuk dengan `admin@buku-tamu.test` / `admin-lokal-2026`):

1. Buka "Resepsi Rina & Bayu" (300 tamu). Coba cari, filter, dan pindah halaman.
2. **Tambah tamu** dengan Nomor Urut `A-017`: harus ditolak karena berpola nomor perangkat. Coba juga `vip-010`: tersimpan sebagai `VIP-010`.
3. **Impor tamu → Unduh templat**. Isi beberapa baris, termasuk satu nomor ganda, lalu unggah dan lihat Tinjau Tamu.
4. **Nomor Urut:** atur prefix, Terapkan, lihat pratinjau, lalu simpan.
5. Klik nama tamu → tab **Kehadiran** → Tandai hadir. Ubah jumlah dengan alasan, lalu Tandai keluar.
6. Jejak audit dapat dilihat di Supabase Studio (http://127.0.0.1:54323) → tabel `audit_logs`.

### Entri baru `docs/decisions.md`

T-036 s.d. T-047:
- SheetJS di-vendor (T-036);
- dialog/select native, bukan bits-ui (T-037);
- edit kategori/grup massal tanpa RPC khusus (T-038);
- hapus grup melepas anggota lewat trigger (T-039);
- isi QR = `qr_token` (T-040);
- tab menu acara (T-041);
- Zod `jitless` (T-042);
- sesi E2E bersama (T-043);
- petunjuk batas jumlah hadir (T-044);
- `IMPORT_MAX_ROWS` (T-045);
- unit test dashboard (T-046);
- check-out lewat `admin_update_check_in` (T-047).

## M0 — Fondasi · selesai

Branch: `m0-fondasi` (belum di-merge ke `main`).

### Yang selesai

- **Repo dan pengaman rahasia:**
  - `git init`.
  - `.gitignore` (`.env*` kecuali `.env.example`, `supabase/.temp`, `supabase/.branches`, `.tools/`).
  - `.gitattributes` (LF).
  - gitleaks 8.30.1 (dipin + SHA-256) di pre-commit via lefthook; terbukti memblokir token palsu.
  - CI memindai seluruh riwayat.
- **Monorepo:**
  - pnpm 10.34.7 (corepack), Node 24.21.0 khusus proyek (`use-node-version`).
  - `minimumReleaseAge` 7 hari; semua dependensi dipin persis.
  - TypeScript 6 strict, ESLint, Prettier.
- **`packages/shared`:**
  - `config.ts` sebagai satu-satunya sumber konstanta (Asumsi).
  - Pola nomor khusus/nomor perangkat/kode hadiah, parser PIN `AB-XXXX-XXXX`, Kode Acara.
  - Enum dan label UI Indonesia, skema Zod awal.
  - Fixture nomor khusus yang dipakai bersama oleh tes TypeScript dan tes DB.
  - `database.types.ts` hasil generate.
- **Supabase:**
  - `config.toml`: API hanya `public`, `auto_expose_new_tables = false`, sign-up publik mati, anonymous sign-in mati, layanan yang tidak dipakai dimatikan.
  - Lima migration:
    - baseline keamanan;
    - fungsi `private`;
    - skema lengkap M0–M3 sesuai `prd.md` 12.1/12.4;
    - RLS dan grant;
    - `pg_cron` + `pg_net`.
- **Seed lokal:** 1 Admin, 1 akun bukan admin, 1 acara (Kode Acara `K7PM2X`), 5 grup, 300 tamu.
- **Dashboard:**
  - SvelteKit SPA, Tailwind v4 dengan token desain (palet bawaan dikosongkan), font IBM Plex di-host sendiri.
  - Halaman `/masuk`, penjaga rute, keluar, daftar acara (baca-saja), halaman galat.
- **Header keamanan:** CSP mode hash lewat meta + `_headers` Cloudflare Pages (frame-ancestors, nosniff, referrer policy, Permissions-Policy tanpa kamera).
- **CI:** `.github/workflows/ci.yml`. Action dipin ke commit SHA. Belum dijalankan karena repo belum punya remote.

### Kriteria keamanan `prd.md` §16 yang sudah punya bukti tes

| Kriteria | Bukti |
|---|---|
| Dengan anon key saja, tidak ada tabel/RPC yang bisa dibaca | pgTAP `010` (katalog + query langsung), Vitest `anon-access` (HTTP: REST, schema `private`, `net`, GraphQL, sign-up). *Channel Realtime menyusul di M2/M3 bersama policy-nya.* |
| Mengubah `user_metadata` tidak mengubah hak akses | pgTAP `035`, Playwright `auth.spec` (akun ber-`user_metadata.role = admin` ditolak) |
| JWT usher tidak bisa SELECT/INSERT/UPDATE/DELETE tabel apa pun | pgTAP `030` (klaim usher disimulasikan, bahkan saat usher dijadikan anggota event). *Uji HTTP dengan JWT usher asli menyusul di M2, setelah `usher-login` ada.* |
| `special_number` berpola nomor perangkat ditolak DB | Vitest `special-number-parity` (18 kasus, TS dan DB identik). *Form dan Tinjau Tamu di M1.* |

Belum ada FR yang ditandai selesai; FR mulai dikerjakan di M1.

### Hasil tes

| Rangkaian | Hasil |
|---|---|
| `pnpm lint` (ESLint + Prettier) | bersih |
| `pnpm typecheck` | bersih |
| `pnpm test:unit` (Vitest) | 42 lulus |
| `node scripts/gen-db-types.mjs --check` | tipe DB sesuai skema |
| `pnpm db:test` (pgTAP) | 48 lulus |
| `pnpm test:integration` (Vitest) | 52 lulus |
| `svelte-check` | 0 galat, 0 peringatan |
| `pnpm test:e2e` (Playwright + axe) | 18 lulus |
| `pnpm secrets:scan` (gitleaks, seluruh riwayat) | tidak ada kebocoran |

**Uji mutasi** untuk memastikan tes keamanan tidak lulus karena kosong:
- grant ke `anon` → 3 tes gagal;
- fungsi SECURITY DEFINER di `public` → 4 tes gagal;
- RLS `guests` dimatikan → 8 tes gagal di tiga file.

Setelah dipulihkan, semua kembali lulus.

### Ditunda (dengan alasan)

| Item | Alasan |
|---|---|
| Policy `realtime.messages` | Dibuat bersama channel-nya di M2 (usher) dan M3 (statistik) |
| Job `pg_cron` `device-cleanup-sweep`, secret di Vault | Bergantung pada Edge Function `device-cleanup` (M2) |
| Bucket Storage `greeting-photos` | Dipakai pertama kali di M2 (foto pop-up sapaan) |
| Menjalankan CI di GitHub | Repo belum punya remote |

### Temuan selama M0

1. Hak `anon` pada schema `net` dan default privileges di `public` milik `supabase_admin` tidak bisa dicabut oleh role `postgres` (T-028). Keduanya tetap tidak terjangkau `anon`: `net` tidak diekspos API (dibuktikan tes HTTP), dan `anon` tidak punya USAGE pada `public`.
2. Elemen pengumum rute bawaan SvelteKit memicu laporan CSP `style-src-attr`. CSP tidak dilonggarkan (T-033).
3. Kaspersky Anti-Virus mencegat TLS ke `cdn.playwright.dev`. Playwright lokal memakai Edge sistem (T-034); verifikasi TLS tidak dimatikan.
4. Node 25 di mesin ini sudah EOL. Proyek memakai Node 24 LTS lewat pnpm tanpa mengubah Node sistem (T-026). Disarankan memasang Node 24 LTS di sistem bila memungkinkan.

### Perbaikan setelah uji lokal oleh pemilik produk

- **Bug:** `scripts/local-supabase-env.mjs` mewajibkan `FUNCTIONS_URL` dan `STUDIO_URL`. Bila edge runtime sedang berhenti (mis. tidak ikut hidup lagi setelah Docker di-restart), `pnpm test:integration`, `test:e2e`, dan `dev` gagal semua.
  - **Perbaikan:** hanya `API_URL`, `PUBLISHABLE_KEY`, dan `DB_URL` yang wajib; pesan galatnya menyarankan `pnpm db:stop` lalu `pnpm db:start`.
  - **Verifikasi:** dengan edge runtime dalam keadaan mati, tes integrasi 52 lulus, E2E 18 lulus, dan `dev` menyajikan `/masuk` (HTTP 200).
- **Bug kedua di wrapper yang sama:** di Windows, argumen berisi spasi atau `|` terpecah oleh `cmd.exe`. Sekarang argumen di-quote dan dikirim sebagai satu perintah.
- **Catatan untuk M2:** Edge Function butuh edge runtime yang hidup. Bila `supabase status` menyebut `edge_runtime` di "Stopped services", jalankan `pnpm db:stop` lalu `pnpm db:start`.

### Cara menjalankan dan menguji secara lokal

Prasyarat: Docker Desktop berjalan. Setelah memasang Docker, **restart VS Code/terminal** agar perintah `docker` masuk PATH. Semua perintah dijalankan dari folder repo.

```powershell
corepack enable                 # sekali saja; pnpm 10.34.7 dan Node 24 diunduh otomatis
pnpm install
pnpm db:start                   # Supabase lokal (Docker)
pnpm db:reset                   # terapkan migration + seed
```

Menguji:

```powershell
pnpm lint
pnpm typecheck
pnpm test:unit
pnpm db:test                    # pgTAP
pnpm test:integration           # butuh Supabase lokal
pnpm --filter @guestbook/dashboard test:e2e   # build + wrangler pages dev + Playwright
pnpm secrets:scan               # gitleaks seluruh riwayat
```

Mencoba dashboard:

```powershell
pnpm --filter @guestbook/dashboard dev
```

- Buka http://127.0.0.1:5173 dan masuk dengan `admin@buku-tamu.test` / `admin-lokal-2026`.
- Coba juga `bukan-admin@buku-tamu.test` / `bukan-admin-2026`; harus ditolak.
- Untuk melihat header keamanan seperti di Cloudflare Pages: `pnpm --filter @guestbook/dashboard build:local`, lalu `pnpm --filter @guestbook/dashboard preview:pages` dan buka http://127.0.0.1:8788.
- Supabase Studio lokal: http://127.0.0.1:54323.

### Entri baru `docs/decisions.md`

T-019 s.d. T-035:
- versi alat (pnpm 10, corepack, Node 24 lewat pnpm, Kit 2.70, TS 6);
- `minimumReleaseAge` 7 hari dan `onlyBuiltDependencies`;
- skrip gitleaks dan `.gitattributes`;
- CI Node 24;
- hak `net` milik platform (T-028);
- email provider tetap aktif (T-029);
- layanan lokal yang dimatikan (T-030);
- seed/tes lewat INSERT `auth.users` (T-031);
- bentuk policy RLS (T-032);
- CSP announcer (T-033);
- Edge untuk Playwright lokal (T-034);
- kunci demo lokal (T-035).
