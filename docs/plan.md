# Rencana Kerja — Smart Dashboard & Backend Supabase

| | |
|---|---|
| Acuan | `prd.md` **v0.5** (sumber kebenaran) |
| Lingkup sesi | M0, M1, M2 (sisi server + dashboard), M3, simulator check-in |
| Status | **M0, M1, dan M2 selesai** (lihat `docs/progress.md`); menunggu konfirmasi sebelum M3. |
| Tanggal | 18 Oktober 2026 |

Semua keputusan yang mengubah perilaku ada di `prd.md` v0.5. Dokumen ini hanya berisi cara mengerjakannya: urutan kerja, struktur teknis, arah UI/UX, dan bukti test.

---

## 1. Ringkasan pendekatan

- **Backend lebih dulu, diuji dengan pgTAP.** Seluruh skema M0–M3 dibuat di M0 supaya tes keamanan mencakup semua tabel sejak awal.
- **Dashboard = SPA statis** (SvelteKit `adapter-static`, `ssr = false`) di Cloudflare Pages. Data lewat PostgREST + RLS untuk CRUD sederhana, dan lewat RPC untuk operasi sensitif yang wajib diaudit.
- **Aksi sensitif hanya lewat RPC.** `check_ins`, `ushers`, `devices`, `audit_logs`, `usher_login_tokens`, dan `auth_attempts` tidak bisa ditulis langsung.
- **Usher tidak punya hak tabel sama sekali**, hanya `pull_snapshot` dan `push_outbox`. Perangkat yang dicabut hanya bisa memanggil `push_outbox`. Edge Function `usher-login` adalah satu-satunya pintu masuk usher.
- **Satu sumber konfigurasi:** `packages/shared/src/config.ts`. Nilai yang juga dipakai di dalam database disalin ke `private.config()` lewat migration, dan **tes paritas** gagal bila keduanya berbeda.

## 2. Prasyarat lingkungan

| Alat | Status | Tindakan |
|---|---|---|
| Docker Desktop + WSL2 | sedang dipasang oleh Anda | Wajib untuk `supabase start` dan `supabase test db` |
| Node.js | v25.2.1 (sudah EOL; disarankan pindah ke 24 LTS) | `engines: ">=22"`; CI memakai Node 24 LTS (T-025) |
| pnpm | belum ada | `corepack enable`; versi dikunci lewat `packageManager` |
| Supabase CLI | belum ada | devDependency dengan versi dipin persis (tanpa `^`); dijalankan via `pnpm supabase …` |
| gitleaks | belum ada | Binary versi dipin + checksum SHA-256, diunduh ke `.tools/` (di-ignore); dipakai di pre-commit dan CI |
| git | ada; folder belum repo | `git init` di langkah pertama M0 |

## 3. Daftar konflik dan keputusan

| # | Keputusan | Bagian `prd.md` | Status |
|---|---|---|---|
| K1 | Usaha penuh pada alur, state, teks, dan aksesibilitas; visual dikunci pada sistem token kecil | — | Disetujui |
| K2 | Usher Check-Out bisa dibuat; push-nya ditolak (`mode_mismatch`) sampai mode Check-Out app (P1) tersedia | FR-R-01, 12.2 | Disetujui |
| K3 | Hadiah ditunda ke M5 tanpa stub; relasi lewat `gifts.check_in_id` | FR-R-03, FR-R-04, 12.1–12.3, D16 | Disetujui (Q5) |
| K4 | Label UI Bahasa Indonesia; enum tetap Inggris | §5, FR-G-09, FR-A-01, FR-RW-01/02, D15 | Disetujui (Q7) |
| K5 | `GuestSnapshot` mendapat satu field baru `checkIn { status, ticketNumber, checkedInAt, usherName }` | FR-HM-01, 12.2, 12.3 | Disetujui |
| K6 | Daftar perangkat minimal jadi P0 untuk pencabutan | FR-R-08 | Disetujui |
| K7 | Status `quarantined` | §5, FR-R-08, FR-RW-05, 11.5, 12.x, §16, D13 | Disetujui (Q6), diperketat oleh K14 dan K31 |
| K8 | `repeat` tidak menambah jumlah orang | §5, 7.5, FR-A-02, 12.3, D11 | Disetujui (Q3) |
| K9 | Batas jumlah hadir opsional; bila kosong, Σ `invited_pax` | FR-S-01, 12.1, D14 | Disetujui (Q4) |
| K10 | Salin link di M4; `/i/{token}` dikunci di `config.ts` | FR-G-07, D17 | Disetujui (Q8) |
| K11 | Foto pop-up: unggah + pratinjau Admin; akses perangkat diputuskan nanti | FR-P-01, Q11 | Disetujui |
| K12 | Login Kode Acara + PIN | FR-R-02, FR-R-09, 10.4, 11.x, D12 | Disetujui (Q2), lihat K30 |
| K13 | Zona waktu dan arsip per event | FR-R-10, 12.1 | Disetujui |
| K14 | Dua tingkat pencabutan. **Cabut**: sesi tetap hidup, hanya push, semua item dikarantina sampai `session_expires_at`. **Cabut & putus total**: sesi Auth diakhiri, semua push ditolak. `pull_snapshot` membalas `revoked` tanpa data apa pun, termasuk delta | FR-R-08, 11.5, 12.2, 12.3, D13 | Disetujui dengan syarat (sudah diterapkan) |
| K15 | Sign-up publik mati; akun Admin dibuat operator | 10.4, 11.1 | Disetujui |
| K16 | Unggah outbox di dashboard dan cetak ulang ikut app usher | — | Disetujui |
| K17 | Item tidak valid dibalas `error` dan tetap di outbox perangkat | 12.2, 12.3, FR-HM-09 | Disetujui |
| K18 | Check-in untuk tamu yang sudah dihapus tetap disimpan dan ditandai | 12.3, FR-RW-05 | Disetujui |
| K19 | Tinjauan `duplicate`/`conflict` | FR-RW-05, 12.1 | Disetujui |
| K20 | Maksimal 702 kode perangkat per event | FR-C-06 | Disetujui |
| K21 | Normalisasi ke huruf besar | FR-C-02 | Disetujui |
| K22 | Tandai hadir manual oleh Admin: `ticket_number` = nomor khusus tamu bila ada, selain itu `null`; penanganan `null` dan tesnya di 10.4 | FR-A-02, 12.1, 12.3 (15), §16 | Disetujui |
| K23 | Indeks tambahan | 12.4 | Disetujui |
| K24 | QR Login bebas blokir; percobaan QR tidak valid tetap dicatat; blokir PIN per (IP + Kode Acara), 10 gagal / 15 menit | FR-R-09, 12.1, 12.4, 14, §16 | Disetujui dengan syarat (sudah diterapkan) |
| K25 | `newGuest` dari item karantina disimpan di `pending_guest` | 12.1, 12.3, FR-RW-05 | Disetujui |
| K26 | Pembersihan user Auth perangkat **otomatis** (`pg_cron`) setelah `session_expires_at` + masa tenggang; batas 500 item karantina per perangkat, kelebihannya ditolak dan memicu peringatan | FR-R-08, 11.5 (7), 12.3, 14 | Disetujui dengan syarat (sudah diterapkan) |
| K27 | `.env.example` hanya berisi placeholder; tes CI gagal bila ada nilai yang bukan placeholder; gitleaks di pre-commit dan CI | — (repo) | Disetujui dengan syarat |
| K28 | Label: Sah / Masuk ulang / Ganda — tinjau / Nomor bentrok — tinjau / Karantina — tinjau / Dibatalkan; penanda visual yang sama untuk status "— tinjau" | §5 | Disetujui (label Anda) |
| K29 | Unggahan outbox Admin diproses normal (`source = 'outbox_upload'`) | FR-HM-08, 12.3 | Disetujui |
| K30 | ~~bcrypt ke semua usher~~ **diganti** *selector + verifier*: PIN `AB-XXXX-XXXX`; lookup (Kode Acara, ID usher); tepat satu bcrypt; bcrypt dummy; respons gagal identik; syarat "PIN unik per event" dihapus | FR-R-02, 10.4, 11.5, 12.1, 12.4, 14, §16, D12 | Ditolak → diganti sesuai arahan Anda |
| K31 | **Event diarsipkan** → push ditolak. **Sesi habis wajar** (tidak dicabut) → karantina (`session_expired`) selama masa tenggang 72 jam; `pull_snapshot` tetap `expired` tanpa data. Perangkat yang **dicabut** tetap memakai jendela sampai `session_expires_at` (tanpa masa tenggang). Masa tenggang = konstanta yang sama dengan jeda penghapusan user Auth | FR-R-08, FR-R-10, FR-HM-09, 11.5, 12.1, 12.2, 12.3, §16, D13 | Disetujui sebagian → diterapkan sesuai arahan Anda |
| K32 | Setelah ditinjau, akhiran "— tinjau" diganti "· ditinjau" | §5 | Disetujui |
| K33 | Blokir global per IP (tanpa Kode Acara), 50 gagal / 15 menit, diperiksa sebelum bcrypt | FR-R-09, 12.4, 14, §16, D12 | Disetujui (arahan Anda) |
| K34 | Penghapusan user Auth hanya lewat Edge Function `device-cleanup` (`auth.admin.deleteUser`): dipanggil dashboard saat putus total dan oleh `pg_cron` + `pg_net` secara berkala. Job diautentikasi dengan secret khusus di Vault, bukan service role key. Tidak ada SQL ke `auth.users` | FR-R-08, 10.4, 11.1, 11.2, 11.4, 11.5, D13 | Disetujui (arahan Anda) |

**Aturan kerja (berlaku sejak 18 Oktober 2026):**
- Keputusan yang tidak mengubah skema DB, kontrak RPC/Edge Function, atau aturan keamanan di 10.4/11.4 saya ambil sendiri, dicatat satu baris di `docs/decisions.md`, lalu pekerjaan berlanjut.
- Saya berhenti dan bertanya hanya bila keputusan mengubah skema, kontrak, atau keamanan, atau bila tes wajib tidak bisa lulus tanpa melonggarkan aturan.
- Laporan akhir milestone berisi: apa yang selesai, hasil tes, entri baru `decisions.md`, dan cara menguji secara lokal.

## 4. Struktur repo

```
.
├─ apps/
│  └─ dashboard/                 SvelteKit SPA (adapter-static) → Cloudflare Pages
│     ├─ src/lib/ui/             komponen dasar (elemen native `<dialog>`/`<select>`, T-037)
│     ├─ src/lib/features/       events, guests, import, numbering, ushers, greeting, stats, history
│     ├─ src/lib/supabase.ts     klien bertipe Database (publishable key saja)
│     ├─ src/routes/             lihat 13.6
│     ├─ static/_headers         header keamanan Cloudflare Pages
│     └─ e2e/                    Playwright + axe
├─ packages/
│  └─ shared/src/
│     ├─ config.ts               semua konstanta (bagian 16)
│     ├─ patterns.ts             DEVICE_TICKET_PATTERN, GIFT_CODE_PATTERN, validator nomor khusus, parser PIN
│     ├─ enums.ts / labels.ts    enum Inggris + label UI Indonesia
│     ├─ schemas/                Zod: guest, import-row, numbering, usher, settings, greeting, sync
│     ├─ sync.ts                 GuestSnapshot, PushItemResult, PushResponse (+ Zod)
│     └─ database.types.ts       hasil `supabase gen types typescript`
├─ supabase/
│  ├─ config.toml
│  ├─ migrations/                satu-satunya jalur perubahan skema
│  ├─ functions/
│  │  ├─ _shared/                SALINAN hasil generate dari packages/shared (jangan diedit)
│  │  ├─ usher-login/
│  │  └─ device-cleanup/         putus total (JWT Admin) + pembersihan berkala (secret job dari pg_net)
│  ├─ tests/                     pgTAP
│  ├─ snippets/grant-admin.sql
│  └─ seed.sql                   data lokal saja
├─ scripts/
│  ├─ simulate-checkins.ts
│  ├─ sync-shared-to-functions.ts
│  └─ install-gitleaks.mjs       unduh binary versi dipin + verifikasi SHA-256 ke .tools/
├─ tests/
│  ├─ integration/               Vitest → Supabase lokal (Edge Function, RPC, paritas config ↔ DB, Zod ↔ DB)
│  └─ repo/                      Vitest: .env.example hanya placeholder, salinan _shared tidak basi
├─ docs/                         plan.md, progress.md, decisions.md (satu baris per keputusan)
├─ .github/workflows/ci.yml
├─ .env.example                  hanya placeholder berbentuk `<NAMA_VARIABEL>`
├─ .gitignore                    .env* + !.env.example, supabase/.temp, supabase/.branches, .tools/, node_modules, build
├─ .gitleaks.toml
├─ lefthook.yml                  pre-commit: gitleaks pada perubahan yang di-stage
└─ pnpm-workspace.yaml
```

URL dan kunci Supabase lokal tidak pernah ditulis ke file yang di-commit. Skrip dan tes membacanya saat dijalankan dari `supabase status -o env`.

## 5. Keputusan teknis (tidak mengubah perilaku produk)

| Topik | Keputusan |
|---|---|
| Mode render dashboard | SPA (`adapter-static`, fallback `index.html`) |
| CSP | `kit.csp` mode `hash` + `static/_headers` (`frame-ancestors 'none'`, `nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy: camera=()`). `connect-src` hanya `'self'` + domain project Supabase. Tanpa `unsafe-eval` |
| Komponen UI | Tailwind CSS v4 dengan token sendiri; dialog dan pilihan memakai elemen native (T-037) |
| Ikon | `@lucide/svelte`; VVIP `Crown`, VIP `Star`, penanda tinjauan `TriangleAlert` |
| Validasi | Zod 4 di `packages/shared`; Edge Function memakai salinan hasil generate di `_shared`, diperiksa tes `tests/repo` |
| Hash PIN | `extensions.crypt(rahasia, extensions.gen_salt('bf', 10))`; hash dummy dengan biaya yang sama disimpan di `private.config()` |
| Penyeragaman waktu gagal | Satu bcrypt di setiap jalur, lalu Edge Function menahan respons gagal sampai minimal `USHER_LOGIN_FAIL_MIN_MS` |
| Kode Acara, ID usher, rahasia PIN | Alfabet 31 karakter `ABCDEFGHJKMNPQRSTUVWXYZ23456789`; input usher tidak peka huruf besar/kecil dan boleh dengan atau tanpa tanda hubung |
| Konfigurasi di DB | `private.config()` (jsonb) dari migration. Tes paritas membandingkan setiap kunci dengan `config.ts`; mengubah `config.ts` tanpa migration baru membuat CI gagal |
| Hapus user Auth perangkat | Hanya Edge Function `device-cleanup` lewat `auth.admin.deleteUser`; tidak ada SQL ke `auth.users`. Dua mode masukan: (1) **terminate**: JWT Admin + `deviceId` + alasan; fungsi memanggil RPC `admin_revoke_device(…, 'terminate')` dengan JWT Admin itu (keanggotaan + audit di DB), lalu menghapus user. (2) **sweep**: header `x-cron-secret`; fungsi meminta daftar perangkat jatuh tempo lewat `svc_devices_due_for_cleanup`, menghapus user satu per satu, lalu `svc_mark_auth_user_deleted`. Idempoten: user yang sudah tidak ada dianggap berhasil |
| Job terjadwal | `pg_cron` tiap 15 menit menjalankan `net.http_post` ke URL `device-cleanup`. URL dan secret diambil dari Supabase Vault (`vault.decrypted_secrets`), sehingga tidak ada nilai rahasia di migration. Secret yang sama ada di env Edge Function `DEVICE_CLEANUP_CRON_SECRET`. Lokal: URL mengarah ke gateway Supabase di jaringan Docker |
| Logika jatuh tempo | `private.devices_due_for_cleanup(p_now)` mengembalikan perangkat `terminate` yang user-nya belum terhapus, atau yang `least(session_expires_at, archived_at) + SESSION_GRACE_HOURS < p_now`. Karena menerima parameter waktu, fungsi ini bisa diuji pgTAP |
| Token QR tamu | 18 byte acak base64url (144 bit), `qr_token_hash` = generated column SHA-256 hex |
| Konkurensi `push_outbox` | `pg_advisory_xact_lock` per event |
| Sinyal Realtime | Satu Broadcast per transaksi per topik |
| GraphQL | Dikeluarkan dari schema yang diekspos |
| Secret scan | `lefthook` (devDependency dipin) menjalankan `gitleaks git --pre-commit --staged --redact`; CI memindai seluruh riwayat dengan binary versi yang sama |

## 6. Model data

Mengikuti `prd.md` v0.5 bagian 12.1 dan 12.4. Ringkasan constraint penting:

| Tabel | Constraint utama |
|---|---|
| `events` | unique `code`; `attendance_limit > 0` bila terisi |
| `guests` | `CHECK` nomor khusus (huruf besar, ≤ 20, `[A-Z0-9-]`, bukan pola nomor perangkat atau kode hadiah); `rsvp_pax` hanya bila `going`; trigram nama |
| `ticket_number_settings` | `prefix + angka` tidak cocok dengan kedua pola; panjang ≤ 20; digits 1–6 |
| `ushers` | unique `(event_id, pin_selector)` termasuk usher yang dihapus; `pin_selector ~ '^[A-HJ-KM-NP-Z2-9]{2}$'`; `pin_hash` tidak terbaca role API mana pun |
| `devices` | unique `(event_id, code)`; `revoke_mode` hanya terisi bila `revoked_at` terisi; `revoke_mode` hanya bisa naik dari `quarantine` ke `terminate` (trigger) |
| `check_ins` | `guest_id` null hanya bila `quarantined` dan `pending_guest` terisi; `ticket_number` null hanya bila `source = 'admin'`; `quarantine_reason` wajib bila `quarantined`; unique parsial nomor tiket dan "satu `accepted` per tamu" |
| `auth_attempts` | indeks `(kind, ip, event_code, created_at desc)` dan `(kind, event_id, created_at desc)` |

**Tidak dibuat di sesi ini:** `gifts`, `screen_tokens`, `invitation_*`, `message_*`.

**Storage:** bucket privat `greeting-photos` (png/jpeg/webp, maksimal 5 MB) dengan policy khusus Admin event.

## 7. Matriks hak akses

Kolom usher menunjukkan keadaan perangkat saat RPC dipanggil.

| Objek | `anon` | Admin (anggota event) | Usher sah | Dicabut (Cabut), sebelum `session_expires_at` | Sesi habis wajar, dalam masa tenggang 72 jam | Putus total / event diarsipkan / jendela habis |
|---|---|---|---|---|---|---|
| Semua tabel `public` | tidak ada | sesuai RLS + column grant | tidak ada | tidak ada | tidak ada | tidak ada |
| RPC admin | — | EXECUTE | ditolak | ditolak | ditolak | ditolak |
| `pull_snapshot` | — | ditolak | data | `revoked`, tanpa data | `expired`, tanpa data | `revoked`/`expired`, tanpa data |
| `push_outbox` | — | ditolak | normal | `quarantined` (`device_revoked`, ≤ 500) | `quarantined` (`session_expired`, ≤ 500) | `rejected` |
| `realtime.messages` | — | topik `stats` event-nya | topik `usher` event-nya | tidak ada | tidak ada | tidak ada |
| Edge Function `device-cleanup` | — | mode terminate untuk perangkat event-nya | — | — | — | — |

Semua fungsi `SECURITY DEFINER` berada di `private` dengan `search_path = ''`, diverifikasi pgTAP.

## 8. Fungsi database

### 8.1 RPC Admin

Semua RPC Admin berada di schema `public`, dengan `REVOKE … FROM public, anon` dan `GRANT … TO authenticated`.

| Fungsi | Kegunaan | FR | Audit |
|---|---|---|---|
| `admin_create_event` / `admin_update_event` / `admin_archive_event` | Buat (dengan Kode Acara), ubah, arsipkan. Arsip mengakhiri semua sesi usher | FR-R-10 | arsip |
| `admin_import_guests`, `admin_check_special_numbers` (edit kategori/grup massal lewat `update` + RLS, T-038) | Impor, cek nomor di Tinjau Tamu | FR-G-03, G-05, C-02 | impor |
| `admin_preview_special_numbers` / `admin_apply_special_numbers` / `admin_clear_special_numbers` | Terapkan dan hapus Nomor Urut | FR-C-04, C-05 | ya |
| `admin_manual_check_in(guest, pax)` | Tandai hadir manual (lihat 10.4) | FR-A-02 | ya |
| `admin_update_check_in` (termasuk check-out, T-047), `admin_void_check_in` | Ubah detail dan check-out manual, undo | FR-A-02, RW-03, RW-04 | ya |
| `admin_review_check_in` | Tandai `duplicate`/`conflict` sudah ditinjau | FR-RW-05 | ya |
| `admin_decide_quarantine(ids[] \| device_id, decision, reason?)` | Setujui atau tolak, per baris maupun per perangkat | FR-RW-05 | ya |
| `admin_create_usher` → `{usher, pin: 'AB-XXXX-XXXX'}` | ID usher + rahasia dibuat server; PIN dikembalikan sekali | FR-R-01, R-02 | ya |
| `admin_reset_usher_pin` → `{pin}` | Rahasia baru, ID usher tetap | FR-R-02 | ya |
| `admin_update_usher` / `admin_delete_usher` | Nonaktif atau hapus berarti Cabut (tingkat `quarantine`) untuk semua perangkatnya | FR-R-02 | ya |
| `admin_create_login_qr` | Token sekali pakai, 5 menit | FR-R-02 | ya |
| `admin_revoke_device(device, mode, reason?)` | `quarantine` dipanggil langsung oleh dashboard. `terminate` hanya dipanggil oleh Edge Function `device-cleanup` dengan JWT Admin, lalu user Auth dihapus. Tingkat bisa dinaikkan, tidak bisa diturunkan | FR-R-08 | ya |
| `get_alerts(event)` | Kunci (IP + Kode Acara) yang sedang diblokir beserta sisa waktunya, kegagalan per event 15 menit terakhir, perangkat yang mencapai batas karantina | FR-R-08, R-09 | — |
| `get_event_stats` / `get_arrival_timeline` | Statistik P0 | FR-S-01..05 | — |

### 8.2 RPC Usher

`pull_snapshot(p_cursor, p_limit, p_client_now)` dan `push_outbox(p_items, p_client_now)`. Detailnya di bagian 10.

### 8.3 Khusus `service_role`

Untuk `usher-login`: `svc_usher_login(...)`, `svc_attach_device_user(...)`, `svc_abort_device(...)`. Untuk `device-cleanup`: `svc_devices_due_for_cleanup(p_limit)` dan `svc_mark_auth_user_deleted(device_id)`.

### 8.4 Helper `private`

`config()`, `is_event_admin`, `usher_context(p_now)` (mengembalikan juga `access_state`: `active` / `quarantine:device_revoked` / `quarantine:session_expired` / `rejected:<alasan>`), `audit`, `recompute_attendance`, `evaluate_check_in_status`, `signal`, `gen_code`, `next_device_code`, `session_expiry`, `devices_due_for_cleanup(p_now)`.

### 8.5 Trigger dan job

- **Trigger:** `set_updated_at`; `check_ins` → hitung ulang kehadiran tamu (memperbarui `guests.updated_at`) + sinyal; `guests`/`guest_groups`/`checkin_settings`/`greeting_configs` → sinyal; `devices` → `revoke_mode` tidak bisa turun.
- **Job `pg_cron`:** `device-cleanup-sweep` tiap 15 menit → `net.http_post` ke Edge Function `device-cleanup` (mode sweep).

## 9. Edge Function `usher-login`

`verify_jwt = false`. CORS hanya untuk origin app usher (env).

1. Validasi body dengan Zod: `{ method: 'pin', eventCode, pin } | { method: 'qr', token }`, ditambah `device: { name, appVersion }`. PIN diurai menjadi `selector` (2) + `secret` (8); format apa pun yang tidak bisa diurai tetap diproses sampai langkah bcrypt dummy, sehingga waktunya sama.
2. Ambil IP dari `cf-connecting-ip` atau `x-forwarded-for`.
3. `svc_usher_login` dalam satu transaksi:
   - **PIN:**
     - Bila IP sudah mencapai 50 kegagalan PIN dalam 15 menit (Kode Acara apa pun), **atau** kunci (IP + Kode Acara yang dikirim) sudah mencapai 10 → `429` + `retryAfter`, tanpa bcrypt.
     - Cari usher aktif lewat (Kode Acara, ID usher), lalu jalankan **tepat satu** bcrypt: terhadap `pin_hash` usher itu, atau terhadap hash dummy bila tidak ditemukan.
     - Catat percobaan beserta `event_code`. Bila kegagalan per event mencapai 20 dalam 15 menit → audit `usher_login_burst` (sekali per jendela) dan peringatan, **tanpa** mengunci.
   - **QR:** tandai token terpakai secara atomik; catat percobaan (termasuk yang tidak valid); tidak pernah diblokir.
   - Setelah kredensial sah: periksa event tidak diarsipkan dan kapasitas 702 kode; alokasikan kode perangkat; sisipkan `devices` beserta `session_expires_at`.
4. Buat user Auth perangkat (email sintetis, password acak yang tidak pernah keluar dari fungsi, `app_metadata` berisi peran dan id).
5. `svc_attach_device_user` → `signInWithPassword` → kembalikan sesi, kode perangkat, nama event, nama usher, mode, dan `sessionExpiresAt`.
6. Bila langkah 4–5 gagal → `svc_abort_device`.

Respons gagal kredensial **identik** (`401`, isi yang sama, waktu minimal `USHER_LOGIN_FAIL_MIN_MS`) untuk Kode Acara tidak ada, ID usher tidak ada, usher nonaktif, rahasia salah, maupun QR tidak valid. Respons berbeda hanya muncul **setelah** kredensial terbukti sah (`403` acara diarsipkan atau kapasitas kode penuh) atau saat blokir (`429`).

## 10. Kontrak sinkronisasi

### 10.1 `pull_snapshot`

- Perangkat dicabut (tingkat apa pun) → `{ status: 'revoked' }`. Sesi berakhir atau event diarsipkan → `{ status: 'expired' }`. **Tanpa data apa pun, termasuk delta.**
- Bila sah: `{ status: 'ok', serverTime, nextCursor, hasMore, event, device, settings, greetings, groups, guests }`.

**`GuestSnapshot`:** 13 field v0.4 tidak berubah (`id`, `name`, `category`, `groupId`, `invitedPax`, `specialNumber`, `qrTokenHash`, `rsvpStatus`, `rsvpPax`, `attendanceStatus`, `isAdditional`, `updatedAt`, `deletedAt`), ditambah satu field:

```ts
checkIn: {
  status: 'accepted' | 'repeat' | 'duplicate' | 'conflict';
  ticketNumber: string | null;   // null hanya untuk tandai hadir manual Admin tanpa nomor khusus
  checkedInAt: string;
  usherName: string | null;      // null untuk tandai hadir manual Admin
} | null
```

- `checkIn` diisi check-in `accepted` aktif. Bila tidak ada, diisi check-in terbaru yang tidak dibatalkan dan bukan `quarantined`. Bila tidak ada keduanya, `null`.
- `phone`, `notes`, `qr_token`, id usher/perangkat, `actual_pax`, dan `void_reason` tidak pernah dikirim. pgTAP memeriksa daftar kunci JSON secara persis.

**Isi snapshot di luar `GuestSnapshot`:**

| Bagian | Field |
|---|---|
| `event` | `id`, `name`, `coupleNames`, `eventDate`, `timezone`, `sessionExpiresAt` |
| `device` | `code` |
| `settings` | `showVerification`, `allowMultiCheckin`, `printTicket { enabled, fields, categories, copies }` |
| `greetings[]` | `category`, `title`, `body`, `layout`, `photoPath`, `photoVersion` |
| `groups[]` | `id`, `name`, `updatedAt`, `deletedAt` |

Paginasi keyset `(updated_at, id)`. Kursor = jam server dikurangi `SYNC_CURSOR_OVERLAP_MS`.

### 10.2 `push_outbox` → `PushResponse`

| Langkah | Kondisi | Hasil |
|---|---|---|
| 0 | Bukan usher, atau perangkat tidak ditemukan | Exception `42501` |
| 1 | Putus total (`terminated`); dicabut dan `session_expires_at` lewat, atau tidak dicabut dan masa tenggang 72 jam habis (`quarantine_window_closed`); event diarsipkan (`event_archived`); mode Check-Out (`mode_mismatch`) | `{ status: 'rejected', reason }`, tidak ada item yang disimpan |
| 2 | **Per item:** `id` sudah ada | `stored` + status tersimpan (idempoten) |
| 3 | Item tidak valid | `error` + `code` |
| 4 | Dicabut (Cabut) sebelum `session_expires_at` → `device_revoked`, status top-level `revoked`; atau tidak dicabut, sesi habis, masih dalam masa tenggang → `session_expired`, status top-level `expired` | `quarantined` (`newGuest` → `pending_guest`). Item ke-501 per perangkat dan seterusnya → `error: quarantine_limit` + peringatan + audit (sekali per perangkat) |
| 5 | Ada `newGuest` | Buat tamu `is_additional = true` |
| 6 | Tamu punya `accepted` aktif | `repeat` / `duplicate` |
| 7 | `ticket_number` **terisi** dan dipakai `accepted` aktif lain | `conflict` |
| 8 | Selain itu | `accepted` |

Persetujuan karantina menjalankan langkah 5–8 pada saat disetujui. `received_at` tetap waktu item pertama kali diterima server.

### 10.3 Kehadiran dan jumlah orang

- **Hadir** = ada check-in yang tidak dibatalkan dan bukan `quarantined`.
- **Jumlah orang** dihitung dari `accepted` dan `conflict`. `repeat`, `duplicate`, `quarantined`, dan yang dibatalkan tidak dihitung.
- **Jumlah tercatat per tamu** = `rsvp_pax` bila *Akan hadir*, selain itu `invited_pax`.

### 10.4 Tandai hadir manual oleh Admin (K22, menunggu persetujuan)

**Jalur.** `admin_manual_check_in` memanggil fungsi penyimpanan dan evaluasi status **yang sama** dengan `push_outbox` (langkah 5–8), dengan `source = 'admin'`, `device_id`/`usher_id` null, `created_by` = Admin, `checked_in_at` = `received_at` = waktu server. Status ditetapkan server, dan setiap panggilan menulis audit log. Tidak ada jalur tulis lain ke `check_ins`.

**Nomor tiket.**

| Kondisi tamu | `ticket_number` | Alasan |
|---|---|---|
| Punya nomor khusus | nomor khusus tamu | Sama dengan aturan perangkat (12.3 poin 2a); bentrok tetap terdeteksi |
| Tidak punya | `null` | Tidak ada tiket yang dicetak dari dashboard; mengarang nomor justru membuat nomor yang tidak pernah dipegang tamu |

Admin bisa mengisi nomor belakangan lewat Ubah Detail Kehadiran (FR-C-07). Nomor itu divalidasi dan dievaluasi ulang seperti biasa.

**Penanganan `null`:**
- **DB:** `CHECK (ticket_number IS NOT NULL OR source = 'admin')`. Unique index parsial memakai perilaku bawaan Postgres `NULLS DISTINCT`, sehingga banyak baris `null` tidak saling melanggar. Ini ditulis eksplisit di migration agar tidak berubah diam-diam.
- **Evaluasi `conflict`:** hanya dijalankan bila `ticket_number IS NOT NULL`.
- **Statistik:** tidak membaca `ticket_number` sama sekali.
- **Snapshot:** `checkIn.ticketNumber = null` dan `usherName = null`. Perangkat yang meng-check-in ulang tamu itu memakai aturan nomor biasa.
- **UI:** kolom nomor menampilkan "—" dengan keterangan "Ditandai hadir oleh Admin, tanpa tiket".

**Tes pgTAP `105_manual_check_in`:**
1. Dua tamu tanpa nomor khusus ditandai hadir manual → keduanya `accepted` dengan `ticket_number` null, tanpa pelanggaran unique index.
2. Tamu bernomor khusus ditandai hadir manual → `ticket_number` = nomor khusus. Check-in perangkat untuk tamu lain dengan nomor yang sama → `conflict`.
3. Check-in perangkat bernomor `A-001` saat ada banyak baris admin `null` → `accepted` (null tidak dianggap bentrok).
4. Insert langsung (sebagai `postgres`) baris `source = 'device'` atau `'outbox_upload'` dengan `ticket_number` null → ditolak `CHECK`.
5. Tandai hadir manual untuk tamu yang sudah punya `accepted` → `repeat` atau `duplicate` sesuai pengaturan (jalur status sama).
6. Statistik S-01..S-03 menghitung check-in manual tanpa nomor sama dengan check-in biasa (tamu dan jumlah orang).
7. `pull_snapshot` untuk tamu tersebut → `checkIn = { status: 'accepted', ticketNumber: null, usherName: null, … }`.
8. Setiap pemanggilan menghasilkan tepat satu baris `audit_logs` dengan `action = 'manual_check_in'`.
9. Non-anggota event dan JWT usher tidak bisa memanggil `admin_manual_check_in`.

## 11. Realtime (Broadcast privat, tanpa Postgres Changes)

| Topik | Penerima |
|---|---|
| `event:{id}:stats` | Admin anggota event |
| `event:{id}:usher` | perangkat **sah** event tersebut (yang dicabut tidak menerima apa pun) |

Debounce 1 detik, lalu `get_event_stats`. Bila channel tidak `SUBSCRIBED`, dashboard beralih ke polling 10 detik. Policy diuji pgTAP.

## 12. Definisi statistik

| FR | Angka utama | Pembanding |
|---|---|---|
| FR-S-01 | Total orang hadir | Σ pax *Akan hadir*. Peringatan bila melebihi batas; teks menyebut sumbernya ("diatur manual" atau "total undangan") |
| FR-S-02 | Hadir per kategori | *Akan hadir* per kategori |
| FR-S-03 | Tamu undangan yang pernah check-in + linimasa | Jumlah tamu *Akan hadir* |
| FR-S-04 | Tamu yang sudah check-out | Tamu yang hadir |
| FR-S-05 | Tamu tambahan + orang di luar jumlah tercatat | — |
| (info) | Perlu ditinjau: Karantina, Ganda, Nomor bentrok | Tautan ke Riwayat |

## 13. UI/UX

Arah ini disusun dengan skill `ui-ux-pro-max` (gaya *Swiss minimalism*, padat, gerak minimal) dan `ui-styling` (komponen aksesibel berbasis primitif headless). Pola landing page, animasi GSAP, dan palet biru generik dari rekomendasi skill tidak dipakai.

### 13.1 Prinsip

1. Data dulu, dekorasi nol.
2. Satu warna aksi (hitam tinta). Warna status selalu disertai teks atau ikon.
3. Angka Statistik memakai digit tabular dan bentuk "X dari Y".
4. URL adalah state.
5. State lengkap: skeleton (> 300 ms), kosong dengan aksi, galat dengan tombol coba lagi, indikator realtime.
6. Aksi berbahaya menyebut objek dan jumlahnya. Undo, tolak karantina, dan putus total wajib memakai alasan.
7. Keyboard dulu.

### 13.2 Larangan (anti AI slop)

Gradien, glassmorphism, ilustrasi dekoratif, emoji sebagai ikon, ungu/indigo "default AI", kartu `rounded-2xl` berbayang besar, sapaan "Selamat datang kembali 👋", grafik hiasan, placeholder sebagai label, tombol "Submit", spinner layar penuh, dan animasi di luar menu atau dialog.

### 13.3 Token

| Token | Nilai |
|---|---|
| `--bg` / `--surface` / `--surface-2` | `#FFFFFF` / `#F6F6F4` / `#EDEDEA` |
| `--ink` / `--ink-muted` | `#121212` / `#52524E` |
| `--line` / `--line-strong` | `#DADAD5` / `#7A7A74` |
| `--primary` / `--on-primary` | `#121212` / `#FFFFFF` |
| `--focus` | `#1A56DB` (cincin 2 px, offset 2 px) |
| `--ok` / `--warn` / `--danger` / `--info` | `#146C2E` / `#8A4B00` / `#B3261E` / `#1F4FB8`, masing-masing dengan latar pucat |

- **Tipografi:** IBM Plex Sans + IBM Plex Mono (nomor tiket, PIN, Kode Acara, kode perangkat), di-host sendiri, `tabular-nums`. Skala 12 / 14 / 16 / 20 / 24 / 40.
- **Jarak** basis 4 px; **radius** 4/6 px; **bayangan** hanya dialog dan menu.
- **Gerak** 120–160 ms hanya di menu dan dialog; `prefers-reduced-motion` menjadi 0 ms.
- **Format** `id-ID`.

### 13.4 Label (sesuai `prd.md` bagian 5)

| Hal | Label |
|---|---|
| RSVP | Akan hadir (X orang) / Tidak hadir / Belum konfirmasi |
| Kehadiran | Hadir / Belum hadir (sudah keluar: "Hadir" + "keluar 21.10") |
| Status check-in | **Sah** (badge `--ok`), **Masuk ulang** (badge netral), **Dibatalkan** (teks dicoret, netral) |
| Status yang perlu ditinjau | **Ganda — tinjau**, **Nomor bentrok — tinjau**, **Karantina — tinjau**. Ketiganya memakai **badge yang sama persis**: ikon `TriangleAlert`, latar `--warn` pucat, garis `--warn`, teks tebal. Hanya teksnya yang berbeda |
| Setelah ditinjau (K32) | "Ganda · ditinjau", "Nomor bentrok · ditinjau" (badge netral, tanpa ikon) |
| Pencabutan perangkat | **Cabut** / **Cabut & putus total** |

### 13.5 Komponen

Button, Input, Textarea, Select, Checkbox, Switch, Dialog, AlertDialog, DropdownMenu (⋮), Tabs, Badge (termasuk varian `review`), Table, Pagination, Toast, Skeleton, EmptyState, Stepper, FileDrop, QrCode, CategoryIcon, RealtimeIndicator.

### 13.6 Rute dan isi halaman

| Rute | Isi dan interaksi kunci |
|---|---|
| `/masuk` | Email dan password, galat di bawah field |
| `/` | Tabel acara dan "Buat acara" |
| `/acara/[id]/statistik` | Angka "X dari Y"; banner overcapacity yang menyebut sumber batas; tabel per kategori; linimasa; baris "Perlu ditinjau: 3 karantina · 2 ganda" (badge `review`) yang menautkan ke Riwayat |
| `/acara/[id]/riwayat` | Tab Check-In / Check-Out / Semua; chip filter **Perlu ditinjau (n)** yang menggabungkan ketiga status "— tinjau", plus chip per status. Di filter Karantina, baris dikelompokkan per perangkat: "Setujui" / "Tolak…" per baris, dan "Setujui semua dari B" / "Tolak semua dari B" per kelompok. Jam perangkat ditampilkan dengan label "tidak terverifikasi". Nomor kosong tampil sebagai "—" dengan keterangan |
| `/acara/[id]/tamu` | Tabel dengan filter, aksi massal, paginasi; isian **Batas jumlah hadir** dengan teks bantu "Kosongkan untuk memakai total undangan (520 orang)" |
| Dialog detail tamu | Tab Data, Kehadiran (termasuk "Tandai hadir"), QR (unduh PNG) |
| `/acara/[id]/tamu/impor` | Stepper Unggah → Tinjau → Proses |
| `/acara/[id]/grup` | Tabel grup (nama, deskripsi, jumlah anggota) dan dialog tambah/ubah |
| `/acara/[id]/nomor-urut` | Panel VIP dan VVIP (prefix, angka awal, digit) dengan contoh langsung "VVIP-001" dan validasi pola. Dialog Terapkan: kategori, urutan (nama A–Z / grup lalu nama / urutan input), opsi "Timpa nomor yang sudah ada" (default mati; konfirmasi tambahan bila dinyalakan), pratinjau lama → baru, lalu "Simpan 42 nomor" |
| `/acara/[id]/penerima-tamu` | **Kode Acara** besar (mono, tombol salin, catatan "tidak rahasia"). Tabel usher (ID usher, nama, mode, status, perangkat aktif, ⋮). **Dialog PIN**: `AB-XXXX-XXXX` dalam huruf mono besar; teks "Usher memasukkan Kode Acara **K7PM2X** dan PIN ini. PIN hanya ditampilkan sekali."; baru bisa ditutup setelah mencentang "Saya sudah mencatat PIN". **Daftar perangkat** per usher: kode, nama, login, terakhir terlihat, sesi berakhir, jumlah karantina, selisih jam, serta dua tombol: **Cabut** (sekunder; dialog: "Perangkat tidak lagi menerima data. Data yang masih dikirim masuk karantina untuk Anda tinjau.") dan **Cabut & putus total** (destruktif; dialog: "Untuk HP hilang atau dicuri. Sesi langsung diakhiri dan semua data dari perangkat ini ditolak. Data yang belum terkirim hanya bisa masuk lewat file ekspor."; alasan wajib). **Banner** blokir PIN dengan sisa waktu dan saran QR login; peringatan kegagalan per event; peringatan batas karantina per perangkat |
| `/acara/[id]/penerima-tamu/pengaturan` | Switch dengan deskripsi; baris terkunci "Verifikasi VIP & VVIP: selalu aktif"; bagian Print Tiket |
| `/acara/[id]/sapaan` | Editor per kategori + pratinjau langsung seukuran HP |
| `/acara/[id]/pengaturan` | Nama, tanggal, zona waktu, venue. **Arsipkan acara** dengan dialog: "Setelah diarsipkan, perangkat usher tidak bisa mengirim data lagi. Data yang belum terkirim hanya bisa masuk lewat file ekspor." |

### 13.7 Aksesibilitas (diuji)

`@axe-core/playwright` di setiap halaman E2E; target klik ≥ 24 px; badge `review` punya teks yang sama untuk pembaca layar (bukan hanya ikon); `aria-live` untuk statistik; `role="alert"` untuk overcapacity dan banner blokir.

## 14. Rencana per milestone

Setiap milestone ditutup dengan: semua tes lulus, `docs/progress.md` diperbarui, cara menjalankan dan menguji ditampilkan, lalu **berhenti menunggu konfirmasi Anda**.

### M0 — Fondasi

Dimulai setelah diff disetujui **dan** Docker terpasang.

1. **Repo dan pengaman rahasia (sebelum commit pertama):**
   - `git init`.
   - `.gitignore` (`.env*`, `!.env.example`, `supabase/.temp`, `supabase/.branches`, `.tools/`, …).
   - `.env.example` berisi placeholder saja.
   - `.gitleaks.toml`, `scripts/install-gitleaks.mjs`, `lefthook.yml`.
   - Commit pertama dibuat setelah hook aktif.
2. **Alat:** corepack, `packageManager`, Supabase CLI dipin persis.
3. **Monorepo:** workspace, `tsconfig` strict, ESLint, Prettier.
4. **`packages/shared`:** `config.ts`, `patterns.ts` (termasuk parser PIN), `enums.ts`, `labels.ts`, Zod awal.
5. **Supabase:** `supabase init`; `config.toml` (sign-up mati, anonymous mati, API hanya `public`).
6. **Migration:**
   - `0001_security_baseline`.
   - `0002_schema`.
   - `0003_rls`.
   - `0004_private_helpers` (termasuk `private.config()`).
   - `0005_extensions` (`pg_cron`, `pg_net`; job didaftarkan di M2).
7. **`docs/decisions.md`** dibuat dan diisi sejak langkah pertama.
8. **`seed.sql` lokal.**
9. **Dashboard:** SPA, token, font, komponen dasar, `/masuk`, penjaga rute, keluar.
10. **Header keamanan.**
11. **CI:** gitleaks (seluruh riwayat) → tes `tests/repo` → supabase start → test db → vitest → playwright.

**Tes M0:**
- pgTAP `010_security_baseline`, `020_admin_isolation`, `030_usher_no_table_access`, `035_user_metadata`.
- Vitest: pola, parser PIN, konfigurasi; `tests/repo/env-example.test.ts` (setiap baris berbentuk `NAMA=<NAMA>` atau kosong; selain itu gagal); `tests/integration/config-parity.test.ts`.
- Playwright: login/keluar, header keamanan, axe.
- Hook: commit percobaan berisi string mirip kunci ditolak gitleaks (dijalankan dan dilaporkan).

### M1 — Admin inti

1. Acara: buat (Kode Acara terbentuk), ubah, arsipkan, pilih.
2. Grup tamu (FR-G-04).
3. Kelola Tamu: tabel, cari, filter, paginasi server, URL state, kolom kehadiran, ikon kategori, isian batas jumlah hadir (FR-G-08, G-09, C-01).
4. Tambah/ubah tamu + RSVP manual + validasi nomor khusus; hapus = soft delete (FR-G-01, G-02, G-06, C-02, C-05).
5. Edit massal dan hapus nomor urut massal (FR-G-05, C-05).
6. Impor: template, parsing SheetJS (tarball resmi `cdn.sheetjs.com`, versi dikunci), Tinjau Tamu, Proses (FR-G-03).
7. QR tamu: render dan unduh PNG (FR-G-07, tanpa salin link).
8. Pengaturan Nomor Urut + Terapkan dengan pratinjau (FR-C-03, C-04).
9. Tab Kehadiran: tampil, ubah, tandai hadir manual bila K22 disetujui, dengan audit (FR-A-01, A-02, C-07).

**Tes M1:** pgTAP `040_special_number`, `050_apply_numbers`, `060_import`, `065_guest_columns`, `100_attendance_admin`, `105_manual_check_in` (10.4), `130_audit`. Vitest: impor, format nomor, paritas regex Zod ↔ DB, `invitationPath`. Playwright: tambah tamu (menolak `A-017` dan `a-017`), impor 1.000 baris, edit massal, Terapkan Nomor Urut, unduh QR, batas jumlah hadir, tandai hadir manual.

### M2 — Usher: sisi server dan dashboard

1. Penerima Tamu: Kode Acara, tambah usher (`AB-XXXX-XXXX` sekali tampil), ubah, nonaktifkan, hapus, reset PIN.
2. QR Login.
3. `usher-login`: *selector + verifier*, bcrypt dummy, penyeragaman waktu, blokir (IP + Kode Acara), peringatan per event, QR bebas blokir.
4. Perangkat: kode, sesi, **Cabut**, karantina sesi habis wajar (masa tenggang), batas karantina, Edge Function `device-cleanup` (mode terminate dan sweep), job `pg_cron` + `pg_net` + secret di Vault.
5. `pull_snapshot` dan `push_outbox`.
6. Pengaturan proses check-in + print tiket + sinyal usher.
7. Pop-up sapaan.
8. Simulator.

**Tes M2:**
- pgTAP `070_usher_login_fn`:
  - Login sah lewat Kode Acara + PIN dan lewat QR.
  - QR terpakai atau kedaluwarsa ditolak.
  - Setiap jalur gagal (kode tidak ada, ID usher tidak ada, usher nonaktif, rahasia salah) menjalankan tepat **satu** bcrypt dan menghasilkan baris respons yang identik. Semua bcrypt melewati satu pembungkus `private.verify_secret`; di dalam transaksi tes, pembungkus ini diganti sementara (`create or replace`, lalu di-rollback) dengan versi yang mencatat setiap panggilan ke tabel sementara, kemudian jumlah panggilannya diperiksa.
  - Kunci (IP + kode) terblokir setelah 10 gagal, sementara kode lain dari IP yang sama tidak terpengaruh.
  - 50 gagal dari satu IP dengan Kode Acara acak (masing-masing < 10) → IP terblokir, dan percobaan yang diblokir tidak menjalankan bcrypt (dicatat lewat pembungkus `private.verify_secret`).
  - 20 gagal per event memunculkan peringatan tanpa blokir.
  - QR berhasil saat kunci PIN terblokir; QR tidak valid tercatat di `auth_attempts`.
  - Acara diarsipkan → `403` hanya setelah kredensial sah.
- pgTAP `080_pull_snapshot`: daftar kunci persis, `checkIn`, delta, tombstone; `revoked` dan `expired` tanpa data **termasuk saat kursor delta dikirim**.
- pgTAP `090_push_outbox`: semua cabang; VVIP di dua perangkat dengan Check-In Lebih 1 Kali aktif → `accepted` + `repeat`, nonaktif → `accepted` + `duplicate`; Cabut → `quarantined` (`device_revoked`) + `pending_guest`; sesi habis wajar dalam masa tenggang → `quarantined` (`session_expired`), lewat masa tenggang → `rejected`; Cabut setelah `session_expires_at` → `rejected` (tanpa masa tenggang); item ke-501 → `quarantine_limit` + peringatan + audit; putus total, arsip, mode Check-Out → `rejected` tanpa baris tersimpan; `repeat` tidak menambah jumlah orang.
- pgTAP `095_revoke_and_cleanup`: `revoke_mode` tidak bisa turun; `devices_due_for_cleanup(p_now)` mengembalikan tepat perangkat `terminate` yang belum dibersihkan dan perangkat yang melewati `least(session_expires_at, archived_at)` + 72 jam; job `pg_cron` terdaftar dan perintahnya membaca URL/secret dari Vault; tidak ada fungsi di schema `public`/`private` yang menulis ke `auth.users`.
- pgTAP `120_realtime_usher`: perangkat yang dicabut tidak menerima sinyal.
- Vitest integrasi:
  - Edge Function end-to-end: `401` identik untuk semua penyebab kegagalan, waktu respons gagal ≥ `USHER_LOGIN_FAIL_MIN_MS` dengan sebaran sempit, `429` dengan `retryAfter`.
  - Push paralel dua perangkat menghasilkan tepat satu `accepted`.
  - `device-cleanup` mode terminate: Admin event lain ditolak; Admin event sendiri → `revoke_mode = 'terminate'`, audit tertulis, user Auth hilang, refresh token gagal, push `rejected`.
  - `device-cleanup` mode sweep: tanpa secret atau dengan secret salah → `401`; dengan secret → hanya perangkat jatuh tempo yang dihapus; dipanggil dua kali tetap aman (idempoten).
  - Job `pg_cron` benar-benar memanggil fungsi lewat `pg_net` di lingkungan lokal (dibuktikan lewat `net._http_response` dan `devices.auth_user_deleted_at`).
- Playwright: dialog PIN, hitung mundur QR, banner blokir dan karantina, Cabut dan Cabut & putus total (alasan wajib), pengaturan, pratinjau sapaan.

### M3 — Statistik dan Riwayat

Statistik, Broadcast, Riwayat, undo, check-out manual, tinjauan, setujui/tolak karantina per baris dan per perangkat.

**Tes M3:** pgTAP `110_stats` (termasuk check-in manual tanpa nomor; batas manual vs bawaan), `115_quarantine_decide`, `120_realtime_stats`. Playwright: simulator live → angka berubah ≤ 3 detik (diukur); badge `review` identik untuk ketiga status; setujui dan tolak karantina; polling cadangan.

## 15. Matriks FR → bukti

| FR | Bukti utama |
|---|---|
| G-01, G-02, G-06 | Playwright `guests.spec`, pgTAP `065` |
| G-03 | Vitest `import-*`, pgTAP `060`, Playwright `import.spec` |
| G-04, G-05 | pgTAP `060`, Playwright `groups.spec`, `bulk.spec` |
| G-07 (tanpa salin link) | pgTAP (entropi/format token, hash), Vitest `invitationPath`, Playwright unduh QR |
| G-08, G-09 | Playwright `guests.spec`, pgTAP `100` |
| C-01 | Playwright (ikon + label aksesibel) |
| C-02, C-05 | Vitest + pgTAP `040` + Playwright |
| C-03, C-04 | pgTAP `050`, Playwright `numbering.spec` |
| C-07 | pgTAP `100` |
| A-01, A-02 | pgTAP `100`, `105`, `130`; Playwright `attendance.spec` |
| C-06, C-08 | pgTAP `090` |
| R-01, R-02 | pgTAP `070`, Vitest integrasi, Playwright `ushers.spec` |
| R-03, R-04, R-06 | pgTAP `120_realtime_usher`, Playwright `settings.spec` |
| R-08 | pgTAP `080`, `090`, `095`, Vitest integrasi |
| R-09 | pgTAP `070`, Vitest integrasi |
| R-10 | pgTAP `080`, `090`, `095` |
| P-01, P-02 | Vitest, Playwright `greeting.spec` |
| S-01..05, S-07 | pgTAP `110`, `120_realtime_stats`, Playwright ≤ 3 detik |
| RW-01..05 | pgTAP `100`, `115`, Playwright `history.spec` |
| Kriteria keamanan bagian 16 PRD | pgTAP `010`, `030`, `035`, `070`, `080`, `090`, `095`; Vitest integrasi; tes repo |

## 16. `packages/shared/src/config.ts`

Kolom **DB** menandai nilai yang juga ada di `private.config()` dan dijaga tes paritas.

| Konstanta | Nilai | Sumber | DB |
|---|---|---|---|
| `IMPORT_MAX_FILE_BYTES` | 5 MB | FR-G-03 (Asumsi) | — |
| `USHER_LOGIN_PIN_BLOCK_FAILS` | 10 per (IP + Kode Acara) | FR-R-09 (keputusan Anda) | ya |
| `USHER_LOGIN_EVENT_WARN_FAILS` | 20 per event | FR-R-09 (Asumsi) | ya |
| `USHER_LOGIN_WINDOW_MIN` | 15 | FR-R-09 (Asumsi) | ya |
| `USHER_LOGIN_FAIL_MIN_MS` | 500 | (Asumsi-teknis) penyeragaman waktu | — |
| `USHER_SESSION_END` | `{ dayOffset: 1, localTime: '06:00' }` | FR-R-10 (Asumsi) | ya |
| `USHER_LOGIN_IP_BLOCK_FAILS` | 50 per IP (Kode Acara apa pun) | FR-R-09 (keputusan Anda) | ya |
| `QUARANTINE_MAX_ITEMS_PER_DEVICE` | 500 | FR-R-08 (keputusan Anda) | ya |
| `SESSION_GRACE_HOURS` | 72 | FR-R-10 (Asumsi): masa tenggang karantina sesi habis wajar **dan** jeda penghapusan user Auth (satu konstanta) | ya |
| `DEVICE_CLEANUP_SCHEDULE` | `*/15 * * * *` | (Asumsi-teknis) | ya |
| `SUPABASE_REGION` | `ap-southeast-1` | 11.1 (Asumsi) | — |
| `SCALE_MAX_GUESTS` / `_DEVICES` / `_DASHBOARD_SESSIONS` | 5.000 / 10 / 20 | 10.2 (Asumsi) | — |
| `INVITATION_PATH` + `invitationPath(token)` | `'/i/{token}'` | FR-G-07, D17 | — |
| `CODE_ALPHABET` | `ABCDEFGHJKMNPQRSTUVWXYZ23456789` | FR-R-02 | ya |
| `EVENT_CODE_LENGTH` / `USHER_SELECTOR_LENGTH` / `PIN_SECRET_LENGTH` | 6 / 2 / 8 | FR-R-02 | ya |
| `PIN_DISPLAY_FORMAT` | `AB-XXXX-XXXX` | FR-R-02 | — |
| `QR_LOGIN_TTL_SEC` | 300 | FR-R-02 | ya |
| `QR_TOKEN_BYTES` | 18 | FR-G-07 | ya |
| `MAX_DEVICE_CODES` | 702 | FR-C-06 | ya |
| `STATS_DEBOUNCE_MS` / `STATS_POLL_FALLBACK_MS` | 1.000 / 10.000 | FR-S-07 | — |
| `CLOCK_SKEW_WARN_MS` | 120.000 | FR-HM-10 | — |
| `UPLOAD_MAX_BYTES`, `UPLOAD_MIME` | 5 MB, png/jpeg/webp | FR-E-08 | ya (bucket) |
| `SPECIAL_NUMBER_MAX_LENGTH` | 20 | FR-C-02 | ya |
| `PUSH_BATCH_MAX` / `SNAPSHOT_PAGE_SIZE` / `SYNC_CURSOR_OVERLAP_MS` | 200 / 1.000 / 5.000 | (Asumsi-teknis) | ya |

## 17. Simulator `scripts/simulate-checkins.ts`

Hanya memakai publishable key, login Admin, dan login usher lewat `usher-login`. **Tidak pernah memakai service role.**

1. **Persiapan:** login Admin; baca Kode Acara; buat 4 usher Check-In (PIN disimpan di memori proses saja); buat 1 QR login.
2. **Login:** perangkat A, B, dan D memakai Kode Acara + PIN; perangkat C memakai QR.
3. **Snapshot penuh:** kunci terlarang tidak ada; bentuk `checkIn` sesuai 10.1.
4. **Online:** A mengirim 20 check-in.
5. **Batch offline:** B mengirim 30 item sekaligus.
6. **Retry:** A mengirim ulang 5 item; hasilnya identik.
7. **Tamu sama di dua perangkat:** VVIP bernomor di A dan C, dengan Check-In Lebih 1 Kali aktif dan nonaktif.
8. **Tamu tambahan:** C mengirim 3 item `newGuest`.
9. **Conflict.**
10. **Delta + tombstone.**
11. **Cabut:** Admin mencabut B (tingkat Cabut). Pull B (dengan kursor) → `revoked` tanpa data. Push B (termasuk `newGuest`) → `quarantined`, dan statistik tidak berubah. Admin menyetujui sebagian dan menolak sebagian.
12. **Batas karantina** (`--scenario quarantine-limit`): B mengirim 501 item → item ke-501 `quarantine_limit`, dan peringatan muncul.
13. **Putus total:** Admin memutus total D. Push D → `rejected`, dan refresh token D gagal.
14. **Ringkasan:** tabel per item dan total per status. Exit code ≠ 0 bila ada yang menyimpang dari ekspektasi.

Mode live: `pnpm sim -- --live --rate 2 --duration 120`.

## 18. Di luar lingkup sesi ini

`apps/usher`, scanner, cetak tiket, IndexedDB/outbox klien, E-Invitation (termasuk tombol salin link), Hadiah, Layar Sapa, Auto Thank You, mode Check-Out di app, export, FR-R-05, FR-R-07 (selain daftar minimal), FR-S-06, FR-HM-08 (unggah di dashboard), FR-TK-03, pengambilan foto oleh perangkat (Q11). Tidak ada stub UI.

## 19. Yang masih menunggu

Hanya konfirmasi bahwa Docker Desktop + WSL2 sudah terpasang. Setelah itu M0 dimulai tanpa jeda konfirmasi lain, kecuali ada hal yang mengubah skema, kontrak, atau keamanan.
