# Progres

## M3 — Statistik dan Riwayat · selesai, menunggu konfirmasi

Branch: `m3-statistik-riwayat` (dari `m2-usher-server`).

### Yang selesai

- **Statistik** (`/acara/[id]/statistik`):
  - Orang hadir "X dari Y orang Akan hadir" dengan meter terhadap batas jumlah hadir. Teksnya menyebut sumber batas (diatur manual / total undangan).
  - Peringatan overcapacity (`role="alert"`).
  - Kartu: tamu undangan masuk, sudah check-out, tamu tambahan, orang di luar jumlah tercatat.
  - Tabel per kategori dan grafik linimasa kedatangan per 15 menit (dengan tampilan tabel).
  - Baris "Perlu ditinjau: 1 karantina · 1 ganda" yang menautkan ke Riwayat.
  - **Pembaruan langsung:** Broadcast privat `event:{id}:stats` → debounce 1 detik → RPC agregat. Indikator Langsung / Diperbarui tiap 10 detik; polling otomatis bila Realtime tidak tersedia.
- **Riwayat** (`/acara/[id]/riwayat`):
  - Tab Check-In / Check-Out / Semua, chip Perlu ditinjau (n) / Karantina / Ganda / Nomor bentrok / Dibatalkan, dan pencarian nama. Semua tersimpan di URL, dengan paginasi server.
  - Penanda RSVP vs kehadiran aktual dan sorotan "Lebih N dari tercatat".
  - Nomor kosong tampil "—" dengan keterangan "Ditandai hadir oleh Admin, tanpa tiket". Penanda tamu tambahan dan tamu yang sudah dihapus.
  - **Undo** dengan alasan wajib, **check-out manual**, **tandai ditinjau**, dan **ubah nomor** (status bentrok dievaluasi ulang).
  - **Karantina:** dikelompokkan per perangkat, Setujui / Tolak… per baris, serta Setujui semua / Tolak semua dari perangkat.
  - Ketiga status "— tinjau" memakai badge yang identik.
- **RPC:**
  - `get_event_stats`, `get_arrival_timeline`;
  - `admin_void_check_in`, `admin_review_check_in`;
  - `admin_decide_quarantine`: evaluasi ulang 12.3 pada saat disetujui, tamu tambahan baru dibuat saat itu, `received_at` dan alasan karantina tetap sebagai jejak. Semua diaudit.
- **Pelengkap milestone sebelumnya:**
  - Langkah 11 simulator (setujui dan tolak karantina; statistik +1 orang).
  - Kasus 6 tes `105` (tandai hadir manual tanpa nomor dihitung di statistik).
  - Angka total undangan di isian batas jumlah hadir.

### FR dan bukti tes

| FR | Bukti |
|---|---|
| S-01 Kehadiran seluruh tamu + batas | pgTAP `110` (definisi orang, batas manual vs total undangan); E2E `stats.spec` (peringatan menyebut sumber batas) |
| S-02 Per kategori | pgTAP `110`; E2E `stats.spec` |
| S-03 Tamu check-in + linimasa | pgTAP `110` (termasuk linimasa); E2E (grafik + tabel, axe) |
| S-04 Check-out | pgTAP `110`; E2E `history.spec` (tab Check-Out) |
| S-05 Tamu tambahan / di luar tercatat | pgTAP `110`; E2E `stats.spec` |
| S-07 Realtime + polling | pgTAP `121`; E2E `stats.spec`: berubah ≤ 3 detik (terukur **1,37–1,55 detik**), polling saat WebSocket diblokir, dan tidak ada muat ulang saat data tidak berubah |
| RW-01 Tab | E2E `history.spec` |
| RW-02 RSVP vs aktual, overcapacity | E2E `history.spec` ("Lebih 1 dari tercatat") |
| RW-03 Undo dengan alasan | pgTAP `115`; E2E `history.spec` |
| RW-04 Check-out manual | pgTAP `100`; E2E `history.spec` |
| RW-05 Tinjauan, setujui/tolak karantina per baris dan per perangkat | pgTAP `115`; E2E `history.spec` (badge identik untuk tiga status); simulator langkah 11 |

### Hasil tes

| Rangkaian | Hasil |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `svelte-check` | bersih |
| `pnpm test:unit` | 76 lulus |
| `node scripts/gen-db-types.mjs --check` | tipe DB sesuai skema |
| `pnpm db:test` (pgTAP) | 410 lulus (22 file), juga saat DB berisi data sisa simulator |
| `pnpm test:integration` | 61 lulus |
| `pnpm sim -- --scenario quarantine-limit` | 25/25 pemeriksaan sesuai |
| `pnpm test:e2e` (Playwright + axe) | 50 lulus |
| `pnpm secrets:scan` | tidak ada kebocoran |

**Uji mutasi:**
- statistik ikut menghitung `repeat` → `110` gagal 3;
- policy Realtime statistik dibuka → `121` gagal 2 dan `120` gagal 5 (topik usher ikut terbuka).

Setelah `db:reset`, semua kembali lulus.

### Temuan selama M3

1. **Loop muat ulang di halaman Statistik.** Efek Realtime bergantung pada objek `data`, jadi setiap muat ulang menyambung ulang channel dan memicu muat ulang lagi tanpa henti. Masalah ini terlihat karena latensi terukur lebih kecil dari debounce. Sudah diperbaiki (T-074) dan ada tes regresinya.
2. **Tes `115` bergantung pada data sisa.** Hitungan audit global ikut membaca data simulator/E2E yang tersisa di DB lokal. Hitungannya sekarang dibatasi ke acara tes (T-077).

### Ditunda (dengan alasan)

| Item | Alasan |
|---|---|
| Statistik per grup (FR-S-06) | P1 |
| Unggah outbox darurat di dashboard (FR-HM-08) | Di luar lingkup sesi (plan bagian 18) |

### Cara menguji secara lokal

```powershell
pnpm install
pnpm db:reset
pnpm db:test; pnpm test:integration
pnpm sim -- --scenario quarantine-limit
pnpm --filter @guestbook/dashboard test:e2e
```

Mencoba manual (`pnpm --filter @guestbook/dashboard dev`):

1. Buka acara → **Statistik**, lalu jalankan di terminal lain `pnpm sim -- --live --rate 1 --duration 120 --event <id acara>`. Angka dan grafik berubah sekitar 1–2 detik setelah setiap check-in, dan indikator menunjukkan **Langsung**.
2. Jalankan `pnpm sim` (skenario lengkap). Buka acara "Simulasi …" yang dibuatnya → **Riwayat** → chip **Perlu ditinjau** untuk melihat Ganda, Nomor bentrok, dan Karantina dengan penanda yang sama.
3. Coba **Setujui** / **Tolak…** (alasan wajib), **Setujui semua dari B**, **Tandai ditinjau**, **Ubah nomor…**, **Tandai keluar**, dan **Batalkan…**.
4. Untuk melihat polling: hentikan layanan Realtime (`docker stop supabase_realtime_buku-tamu-digital`). Indikator berubah menjadi "Diperbarui tiap 10 detik". Hidupkan lagi dengan `docker start supabase_realtime_buku-tamu-digital`.

### Entri baru `docs/decisions.md`

T-068 s.d. T-078:
- definisi statistik (T-068);
- linimasa memakai jam perangkat (T-069);
- persetujuan karantina tidak menandai ditinjau (T-070);
- signature `admin_decide_quarantine` (T-071);
- undo hanya untuk non-karantina (T-072);
- sinyal statistik (T-073);
- efek Realtime bergantung pada id (T-074);
- grafik tanpa library dan tanpa style inline (T-075);
- Riwayat berbasis URL (T-076);
- isolasi tes audit (T-077);
- urutan tab (T-078).

## M2 — Usher: sisi server dan dashboard · selesai

Branch: `m2-usher-server` (dari `main`).

### Yang selesai

- **Penerima Tamu (dashboard):**
  - Kode Acara besar dengan tombol salin dan catatan "tidak rahasia".
  - Tambah, ubah, nonaktifkan, dan hapus usher. Mode Check-In/Check-Out.
  - **Dialog PIN** `AB-XXXX-XXXX`: tampil sekali, tidak bisa ditutup (Esc maupun X) sebelum "Saya sudah mencatat PIN" dicentang.
  - Reset PIN (ID usher tetap, PIN lama langsung tidak berlaku).
  - **QR Login** dengan hitung mundur 5 menit; QR baru membatalkan QR lama.
  - **Daftar perangkat minimal:** kode, usher, nama/versi, masuk, terakhir terlihat, selisih jam > 2 menit, sesi berakhir, status, jumlah karantina.
  - **Cabut** dan **Cabut & putus total** (alasan wajib, lewat Edge Function).
  - **Banner peringatan:** blokir PIN beserta sisa waktunya dan saran QR Login, kegagalan per acara, dan batas karantina per perangkat.
- **Pengaturan check-in:** Tampilkan Verifikasi Tamu, baris terkunci "Verifikasi VIP & VVIP: selalu aktif", Tamu Check-In Lebih 1 Kali, dan Print Tiket (informasi, kategori, 1–3 salinan) dengan pratinjau tiket.
- **Pop-up sapaan:** editor per kategori, variabel `{{nama}}`/`{{kategori}}` (variabel salah ditolak), tiga tampilan, unggah foto ke bucket privat (jenis dicek dari isi berkas), dan pratinjau seukuran HP.
- **Edge Function `usher-login`:**
  - Selector + verifier dengan tepat satu bcrypt per percobaan (dummy bila usher tidak ditemukan atau nonaktif).
  - 401 identik untuk semua penyebab, minimal 500 ms.
  - Blokir (IP + Kode Acara) 10/15 menit dan per IP 50/15 menit, keduanya sebelum bcrypt; peringatan per acara 20/15 menit tanpa mengunci.
  - QR Login bebas blokir.
  - User Auth perangkat dengan klaim di `app_metadata`; pendaftaran dibatalkan bila sesi gagal dibuat.
- **Edge Function `device-cleanup`:**
  - Mode terminate memakai JWT Admin; keanggotaan dan audit diperiksa DB.
  - Mode sweep memakai secret job dari Vault.
  - `auth.admin.deleteUser` saja (tidak ada SQL ke `auth.users`), idempoten.
  - Job `pg_cron` tiap 15 menit lewat `pg_net`.
- **RPC usher:**
  - `pull_snapshot`: 14 kunci GuestSnapshot persis, paginasi keyset, delta + tombstone. `revoked`/`expired` tanpa data, termasuk saat kursor dikirim.
  - `push_outbox`: semua cabang 12.3, idempoten, galat per item, karantina dua alasan + batas 500, dan penolakan seluruh batch.
  - Keduanya memeriksa ulang `devices` dan `events` di setiap panggilan.
- **Realtime:** Broadcast privat `event:{id}:usher` dari trigger DB, satu sinyal per transaksi, hanya untuk perangkat sah. Postgres Changes tidak dipakai.
- **Simulator** `pnpm sim`: 14 langkah plan bagian 17, `--scenario quarantine-limit`, dan mode `--live`.

### FR dan bukti tes

| FR | Bukti |
|---|---|
| R-01 Tambah Penerima Tamu (Check-In/Check-Out) | pgTAP `072`, `090` (Check-Out → `mode_mismatch`); E2E `ushers.spec` |
| R-02 Kode Acara + PIN, QR Login, reset, nonaktif | pgTAP `070`, `072`; integrasi `usher-login`; E2E `ushers.spec`; simulator langkah 2 |
| R-03 Pengaturan proses check-in | pgTAP `072` (validasi DB), `090` (Lebih 1 Kali → repeat/duplicate); E2E `settings-greeting.spec` |
| R-04 Print Tiket Penomoran | pgTAP `072`; unit `m2-usher`; E2E `settings-greeting.spec` |
| R-06 Perubahan langsung berlaku di app | pgTAP `120` (trigger → sinyal, satu per transaksi; perangkat menarik lewat delta, `080`) |
| R-08 Cabut / putus total, karantina, batas 500, daftar perangkat | pgTAP `072`, `080`, `090`, `095`; integrasi `device-cleanup`; E2E `ushers.spec`; simulator 11–13 |
| R-09 Rate limit login | pgTAP `070`; integrasi `usher-login`; E2E banner blokir |
| R-10 Sesi berakhir, masa tenggang, arsip | pgTAP `070` (`session_ended`), `080`, `090`, `095` |
| C-06 Nomor tiket otomatis / kode perangkat | pgTAP `070` (A..ZZ, 702), `090` (`ticket_device_mismatch`); integrasi paritas kode perangkat |
| C-08 Check-in ulang memakai nomor yang sama | pgTAP `090` (repeat dengan VVIP-008); simulator langkah 7 |
| P-01 Pop-up sapaan + foto | pgTAP `072`, `125`; unit; E2E `settings-greeting.spec` |
| P-02 Variabel sapaan | unit `m2-usher`; E2E `settings-greeting.spec` |
| HM-01 Snapshot minimal | pgTAP `080`; integrasi `usher-login` (skema `.strict()`); simulator langkah 3 |

### Kriteria keamanan `prd.md` §16 yang bertambah buktinya

| Kriteria | Bukti |
|---|---|
| Usher hanya lewat `pull_snapshot`/`push_outbox`; JWT usher asli tidak bisa membaca tabel | pgTAP `030`, `090` (usher membaca `check_ins` = 0 baris); integrasi `usher-login` |
| Login PIN: tepat satu bcrypt, respons identik, blokir sebelum bcrypt | pgTAP `070` (pembungkus `verify_secret` dihitung); integrasi (401 identik, ≥ 500 ms, sebaran < 250 ms) |
| Perangkat dicabut tidak menerima data apa pun | pgTAP `080`, `120` |
| Putus total: user Auth dihapus lewat Admin API, refresh gagal, push ditolak | integrasi `device-cleanup`; simulator langkah 13 |
| Job terjadwal memakai secret Vault, bukan service role | pgTAP `095`; integrasi (pg_cron → pg_net → fungsi sungguhan) |
| `pull_snapshot` tanpa telepon, catatan, token QR mentah | pgTAP `080`; skema `.strict()` di integrasi dan simulator |
| Bucket privat, tanpa SVG, hanya Admin acara | pgTAP `125`; E2E (SVG menyamar ditolak) |

### Hasil tes

| Rangkaian | Hasil |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `svelte-check` | bersih |
| `pnpm test:unit` (shared, repo, dashboard) | 76 lulus |
| `node scripts/gen-db-types.mjs --check` | tipe DB sesuai skema |
| `pnpm db:test` (pgTAP) | 352 lulus (19 file) |
| `pnpm test:integration` | 61 lulus |
| `pnpm sim -- --scenario quarantine-limit` | 23/23 pemeriksaan sesuai |
| `pnpm test:e2e` (Playwright + axe) | 42 lulus |
| `pnpm secrets:scan` | tidak ada kebocoran |

**Uji mutasi:**
- penghitung gagal login dikosongkan → `070` gagal 14 tes;
- policy Realtime dibuat selalu boleh → `120` gagal 5;
- guard tingkat pencabutan dimatikan → `095` gagal 4.

Setelah `db:reset`, semua kembali lulus.

### Ditunda (dengan alasan)

| Item | Alasan |
|---|---|
| Setujui/tolak karantina, tinjau ganda/bentrok (FR-RW-05), dan bagian keputusan di langkah 11 simulator | M3 bersama Riwayat dan `admin_decide_quarantine` |
| Topik Realtime `event:{id}:stats` | M3 bersama statistik |
| Cara perangkat mengambil foto sapaan (Q11) | Diputuskan bersama App Penerima Tamu; snapshot sudah mengirim `photoPath` dan `photoVersion` |
| Verifikasi header IP klien di Supabase produksi (T-051) | M6, butuh project produksi |
| Kolom FR-R-07 lainnya (antrean belum tersinkron) | P1 |

### Penyiapan produksi (untuk operator, sekali per project)

1. **Secret Edge Function** (Dashboard → Edge Functions → Secrets):
   - `DEVICE_CLEANUP_CRON_SECRET`: acak ≥ 32 karakter;
   - `USHER_APP_ORIGINS`: origin App Penerima Tamu;
   - `DASHBOARD_ORIGINS`: origin dashboard Cloudflare Pages.
2. **Vault** (SQL editor):
   - `select vault.create_secret('https://<ref>.supabase.co/functions/v1/device-cleanup', 'device_cleanup_url');`
   - `select vault.create_secret('<secret yang sama>', 'device_cleanup_cron_secret');`
3. **Auth → Rate limits:** login perangkat (lewat `usher-login`) ikut dihitung batas sign-in per IP Edge Function. Naikkan sesuai jumlah perangkat per acara.

### Cara menguji secara lokal

Setelah menarik perubahan, Supabase perlu dihidupkan ulang sekali. Edge Function dan secret lokalnya baru terbaca saat start.

```powershell
pnpm install
pnpm db:stop
pnpm db:start                   # membuat supabase/functions/.env (secret lokal acak) dan mengisi Vault
pnpm db:reset

pnpm lint; pnpm typecheck; pnpm test:unit
pnpm db:test
pnpm test:integration
pnpm sim -- --scenario quarantine-limit
pnpm --filter @guestbook/dashboard test:e2e
```

Mencoba manual (`pnpm --filter @guestbook/dashboard dev`, masuk sebagai `admin@buku-tamu.test` / `admin-lokal-2026`):

1. Buka acara → **Penerima Tamu** → **Tambah penerima tamu**. Catat PIN (dialog tidak bisa ditutup sebelum dicentang).
2. Jalankan `pnpm sim -- --live --rate 1 --duration 60 --event <id acara>`. Dua perangkat login lalu mengirim check-in; muat ulang halaman untuk melihat perangkat A dan B.
3. Klik **Cabut** pada perangkat A, lalu **Cabut & putus total** pada B (alasan wajib). Simulator yang masih berjalan akan menerima `revoked`/`rejected`.
4. **QR Login** pada salah satu usher: QR beserta hitung mundur 5 menit.
5. **Pengaturan check-in** dan **Sapaan**: ubah, lihat pratinjaunya, lalu simpan.
6. Jejak audit ada di Supabase Studio (http://127.0.0.1:54323) → `audit_logs`.

### Entri baru `docs/decisions.md`

T-048 s.d. T-067 (ringkas):
- salinan shared untuk Edge Function (T-048);
- hash dummy dari migration (T-049);
- percobaan diblokir tidak dihitung (T-050);
- sumber IP klien (T-051);
- 403 `session_ended` (T-052);
- alokasi kode perangkat (T-053);
- isi QR Login (T-054);
- format kursor (T-055);
- galat per item (T-056);
- hitungan batas karantina (T-057);
- validasi jsonb pengaturan/sapaan di DB (T-058);
- sinyal Realtime (T-059);
- penyimpanan foto (T-060);
- secret lokal (T-061);
- rate limit lokal (T-062);
- banner blokir IP (T-063);
- audit tambahan (T-064);
- daftar teks di config (T-065);
- tata letak daftar perangkat (T-066);
- simulator (T-067).

## M1 — Admin inti · selesai

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
