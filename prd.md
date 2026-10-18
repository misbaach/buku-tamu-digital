# PRD — Sistem Buku Tamu Digital (Digital Guestbook)

| | |
|---|---|
| **Nama kerja** | GuestBook (nama final menyusul) |
| **Versi** | 0.5 (Draft untuk review) |
| **Tanggal** | 18 Oktober 2026 |
| **Penulis** | Paka |
| **Acuan alur & UI/UX** | Dokumentasi Digital Guestbook Katsudoto — https://panduan.katsudoto.id/digital-guestbook |
| **Stack utama** | TypeScript end-to-end + Supabase (Postgres + Storage) |

**Legenda prioritas:** **P0** = wajib di MVP · **P1** = segera setelah MVP · **P2** = backlog.
Poin bertanda **(Asumsi)** belum dikonfirmasi dan perlu divalidasi (lihat bagian 15).

### Perubahan v0.5 — Keputusan sesi perencanaan

- **Login usher memakai Kode Acara + PIN Akses berpola *selector + verifier*.** Kode Acara (6 karakter, tidak rahasia) dipakai untuk mencari event. PIN `AB-XXXX-XXXX` terdiri dari 2 karakter ID usher (tidak rahasia) dan 8 karakter rahasia, sehingga server menjalankan **tepat satu bcrypt** per percobaan. Respons gagal identik dan waktunya diseragamkan. Blokir PIN memakai kunci **(IP + Kode Acara)** dengan ambang 10 gagal per 15 menit, ditambah **blokir global per IP** (50 gagal per 15 menit) untuk serangan yang mengganti-ganti Kode Acara palsu; per event hanya **peringatan**. QR Login tidak terkena blokir, tetapi percobaan yang tidak valid tetap dicatat (FR-R-02, FR-R-09, 11.5, D12).
- **Status check-in kelima `quarantined` dan dua tingkat pencabutan.**
  - **Cabut** (bawaan): sesi Auth perangkat tetap hidup, tetapi hanya untuk `push_outbox`. Semua item masuk karantina (tidak dihitung; disetujui atau ditolak Admin lewat FR-RW-05) sampai `session_expires_at`, maksimal 500 item per perangkat.
  - **Cabut & putus total** (HP hilang/dicuri): user Auth perangkat langsung dihapus lewat Edge Function `device-cleanup` dan semua push ditolak.
  - **Sesi habis wajar** (perangkat tidak dicabut): push masih diterima ke karantina selama masa tenggang 72 jam.
  - **Event diarsipkan**: push ditolak. Data yang ditolak hanya masuk lewat ekspor outbox darurat yang diunggah Admin (diproses normal).
  - Jam perangkat tidak dipakai sebagai bukti.
  - User Auth perangkat dihapus lewat Edge Function `device-cleanup` (`auth.admin.deleteUser`). Fungsi ini dipanggil langsung saat putus total dan berkala oleh `pg_cron` + `pg_net`. Tidak ada penghapusan lewat SQL ke `auth.users`.
  - Terkait: 12.3, FR-R-08, FR-R-10, FR-HM-08, FR-HM-09, 11.5, D13.
- **Check-in `repeat` tidak menambah jumlah orang hadir.** Koreksi jumlah lewat Ubah Detail Kehadiran pada check-in `accepted` (menjawab Q10, D11).
- **Batas jumlah hadir** per event (opsional). Bila kosong, batasnya total jumlah undangan tamu undangan. Dashboard menampilkan batas mana yang dipakai (FR-S-01, D14).
- **Snapshot perangkat** mendapat satu field baru `checkIn` (status, nomor tiket, waktu check-in, nama usher) (FR-HM-01, 12.2).
- **Label UI Bahasa Indonesia** untuk status RSVP, kehadiran, dan check-in; enum di DB dan kode tetap bahasa Inggris (bagian 5, D15).
- **Hadiah Titipan** (toggle di FR-R-03, kode hadiah di tiket, field `gift` di outbox) ikut fase Hadiah (P1). Relasi hadiah ke check-in disimpan di `gifts.check_in_id`, sehingga `check_ins` tidak perlu diubah nanti (D16).
- **"Salin link" QR** aktif bersama halaman `/i/{token}` (M4); format URL dikunci sekarang (FR-G-07, D17).
- Tambahan kecil: nomor khusus dinormalisasi ke huruf besar; maksimal 702 kode perangkat per event; zona waktu dan arsip per event; Admin dapat menandai hadir manual; tinjauan check-in bermasalah (FR-RW-05); daftar perangkat minimal masuk P0 untuk pencabutan; item outbox yang tidak valid dibalas galat per item; sign-up publik dimatikan.

### Perubahan v0.4 — Hardening keamanan & keandalan

- **Istilah "Passkey" diganti menjadi "PIN Akses"** agar tidak tertukar dengan WebAuthn passkey. PIN minimal 8 karakter alfanumerik, dibuat server, di-hash, dan dilindungi rate limit. **QR login sekali pakai** dengan masa berlaku 5 menit.
- **Usher tidak pernah mengakses tabel secara langsung.** Semua baca/tulis usher lewat dua RPC (`pull_snapshot`, `push_outbox`). Klaim otorisasi hanya dari `app_metadata` atau tabel server, tidak pernah dari `user_metadata`.
- **Snapshot offline di perangkat usher dibuat minimal:** tanpa nomor telepon, dan QR disimpan sebagai **hash SHA-256**, bukan token mentah. Data lokal dihapus saat perangkat dicabut atau sesi berakhir.
- **Realtime memakai Broadcast di channel privat**, bukan Postgres Changes. Layar Sapa dan halaman publik masuk lewat Edge Function yang menerbitkan token sempit; role `anon` tidak punya akses tabel.
- **Aturan status check-in dan nomor tiket diperjelas:** status `accepted` / `repeat` / `duplicate` / `conflict` ditentukan server; unique index nomor tiket hanya berlaku untuk check-in `accepted`. Nomor khusus dilarang memakai pola nomor perangkat.
- **Outbox benar-benar durable:** `navigator.storage.persist()`, logout diblokir selama outbox belum kosong, ekspor outbox darurat, tombstone pada delta sync, dan `received_at` dari server.
- **Verifikasi selalu aktif untuk VIP/VVIP** (lihat D9).
- **RawBT menjadi jalur cetak utama di Android**; `window.print()` menjadi cadangan.
- Tambahan: escape CSV injection pada export, sumber library XLSX yang aman, bucket Storage privat dengan signed URL dan whitelist MIME, serta kriteria penerimaan keamanan.

### Perubahan v0.3

- **Selfie Check-In ditunda ke iterasi berikutnya** (belum dikembangkan sekarang). Seluruh referensinya dikeluarkan dari alur, skema data, dan kriteria MVP.
- **Keputusan Nomor Urut VIP/VVIP: pendekatan hybrid.** Nomor khusus yang ditetapkan admin (sesuai referensi, dengan fitur *Terapkan Nomor Urut*) + nomor tiket otomatis berbasis kode perangkat untuk tamu lainnya. Counter atomik dan blok nomor dari server dihapus karena terlalu kompleks untuk kebutuhan ini (lihat 15.1).
- Pertanyaan terbuka yang sudah terjawab dipindah ke bagian Keputusan.

### Perubahan dari v0.1

- **Dikeluarkan dari lingkup:** Table Management, Souvenir Management, Doorprize, WO Tracking (beserta statistiknya).
- **E-Invitation didefinisikan ulang** mengikuti referensi: kartu undangan yang dibuat per tamu (berisi nama, info acara, dan QR) dan dapat diunduh. Bukan halaman web RSVP. File disimpan di Supabase Storage.
- **Halaman undangan web publik dan form RSVP** tidak dibuat di versi ini. Status RSVP diisi/diubah manual oleh admin atau lewat impor.
- Alur check-in, pengaturan Penerima Tamu, hadiah, riwayat, pop-up/layar sapa, dan statistik diselaraskan dengan referensi.
- Mode usher hanya **Check-In** dan **Check-Out** (mode *Tracking* untuk WO dihapus).

---

## 1. Ringkasan Produk

Platform buku tamu digital untuk acara (pernikahan dan sejenisnya), terdiri dari:

1. **Smart Dashboard** — panel admin: kelola tamu, kategori, penerima tamu (usher), E-Invitation, statistik, riwayat, hadiah, pop-up/layar sapa, dan pesan terima kasih.
2. **App Penerima Tamu** — PWA untuk petugas di lokasi: check-in lewat scan QR, cari tamu, atau tambah tamu; cetak tiket ke printer thermal; tetap berjalan saat internet tidak stabil (Hybrid Mode).
3. **E-Invitation** — kartu undangan per tamu dengan QR unik yang dapat diunduh dan dibagikan.

**Prinsip utama:** *cepat* dan *andal di lapangan*. Tampilan visual belum menjadi prioritas.

## 2. Tujuan & Batasan

### 2.1 Tujuan

| # | Tujuan | Ukuran keberhasilan |
|---|---|---|
| G1 | Check-in tamu sangat cepat | Scan → tiket mulai tercetak ≤ 3 detik (p95) di HP Android kelas menengah |
| G2 | Tetap berjalan tanpa internet | 100% check-in offline tersinkron tanpa data hilang atau ganda |
| G3 | Nomor tiket tidak pernah ganda | 0 nomor ganda per event pada uji multi-perangkat, termasuk skenario offline |
| G4 | Data kehadiran terlihat langsung | Statistik dashboard terbarui ≤ 3 detik setelah check-in (saat online) |
| G5 | Operasional sederhana | Admin menyiapkan satu event lengkap (impor tamu → QR/E-Invitation → akses usher) tanpa bantuan developer |

### 2.2 Di Luar Lingkup (Out of Scope)

| Fitur | Keterangan |
|---|---|
| **Table Management** | Tidak dikerjakan. Termasuk Statistik Table Management. Tidak ada data meja di tamu, tiket, maupun sapaan |
| **Souvenir Management** | Tidak dikerjakan. Termasuk Statistik Souvenir. Tiket hanya memuat nomor sebagai arahan pengambilan souvenir; stok dan klaim souvenir tidak dilacak |
| **Doorprize** | Tidak dikerjakan (dashboard maupun app) |
| **WO Tracking** | Tidak dikerjakan; mode usher *Tracking* tidak ada |
| Undangan Website & form RSVP publik | Tidak di versi ini. RSVP diisi manual oleh admin atau impor |
| Self-service klien, pembayaran/billing, paket langganan | Semua dikelola manual oleh admin |
| **Selfie Check-In** | Ditunda ke **iterasi berikutnya**; tidak dibangun sekarang |
| Wedding Planner, aplikasi native iOS/Android, chatbot WhatsApp dua arah | Tidak dikerjakan |

## 3. Referensi & Prinsip UI/UX

**Sumber:** dokumentasi publik Digital Guestbook Katsudoto. Dipakai hanya sebagai **acuan alur dan pola UX**; teks, gambar, aset, dan branding dibuat sendiri.

> **Catatan keterbatasan:** acuan yang dianalisis berupa teks dokumentasi. Tangkapan layar tidak ikut dianalisis, sehingga detail tata letak visual perlu dikonfirmasi lewat demo/akun uji bila diperlukan.

### 3.1 Pola dari referensi yang diadopsi

- **Dashboard Penerima Tamu adalah pusat pengaturan.** Perubahan di sana langsung berlaku di App Penerima Tamu.
- **Registrasi bertahap seperti wizard**: sapaan → verifikasi (opsional untuk Regular; selalu aktif untuk VIP/VVIP) → konfirmasi → tiket. Setiap langkah opsional bisa dinyalakan/dimatikan.
- **Kategori tamu ditandai ikon**: VVIP mahkota, VIP bintang, Regular tanpa ikon.
- **Statistik selalu dibandingkan dengan jumlah konfirmasi RSVP** dan memberi peringatan bila jumlah hadir melebihi batas.
- **Riwayat dengan tab** Check-In / Check-Out / All, dan penanda perbedaan antara RSVP dan kehadiran aktual.
- **Menu titik tiga (⋮) per baris** riwayat tamu: Ubah Detail Kehadiran dan Print.
- **Pop-up sapaan** dengan teks dan foto yang dapat diatur, tiga tampilan berbeda per kategori, dan **pratinjau langsung** di dashboard.
- **Hybrid Mode aktif secara default** tanpa pengaturan tambahan.
- **QR Umum** untuk tamu yang tidak terdata, mengarah ke "Tambah Tamu On The Spot".

### 3.2 Prinsip tambahan (karena prioritas performa dan desain belum utama)

- **App Penerima Tamu mobile-first**: tombol besar (≥ 48 px), bisa dipakai satu tangan, aksi kritis (check-in, cetak) maksimal 2 ketukan.
- **Optimistic UI**: hasil scan dan check-in tampil seketika dari data lokal; sinkronisasi berjalan di latar belakang.
- **Indikator sinkronisasi selalu terlihat** (online/offline, jumlah antrean).
- **Dashboard**: tabel dengan paginasi server, filter cepat, skeleton loading, tanpa animasi berat.
- **Tampilan polos dan kontras tinggi**; tema terang; komponen seminimal mungkin.
- **Bahasa Indonesia** untuk seluruh antarmuka.

---

## 4. Persona & Peran

| Peran | Deskripsi | Akses |
|---|---|---|
| **Admin** | Operator yang menyiapkan dan memantau event | Penuh ke Smart Dashboard |
| **Penerima Tamu (Usher)** | Petugas di pintu | App Penerima Tamu pada event yang di-assign; mode **Check-In** atau **Check-Out** |
| **Tamu** | Penerima undangan | Menerima E-Invitation dan menunjukkan QR |

## 5. Istilah & Model Status

Antarmuka memakai **label Bahasa Indonesia**. Enum di database dan kode tetap bahasa Inggris. Istilah referensi (Going, Presence, dan sebagainya) hanya dipakai sebagai pemetaan (D15).

**Status RSVP** (diisi admin/impor, karena RSVP publik tidak dibuat):

| Enum | Label UI | Arti |
|---|---|---|
| `going` | **Akan hadir (X orang)** | Tamu menjawab akan hadir, jumlah X orang |
| `not_going` | **Tidak hadir** | Tamu menjawab tidak hadir. Jika di hari H tetap datang, tetap bisa check-in dan ditandai pada Riwayat |
| `unconfirmed` | **Belum konfirmasi** | Tamu belum memberi konfirmasi |

**Kehadiran** (hari H): **Hadir** / **Belum hadir**. Secara default otomatis menjadi *Hadir* saat tamu check-in. Secara teknis dilacak sebagai `not_arrived` (Belum hadir) → `checked_in` (Hadir) → `checked_out` (Hadir, disertai keterangan waktu keluar).

**Status check-in** (ditetapkan server, lihat 12.3):

| Enum | Label UI | Dihitung di statistik |
|---|---|---|
| `accepted` | **Sah** | Ya |
| `repeat` | **Masuk ulang** | Tamu tidak dihitung dua kali; jumlah orang tidak ditambah (D11) |
| `duplicate` | **Ganda — tinjau** | Tidak |
| `conflict` | **Nomor bentrok — tinjau** | Ya |
| `quarantined` | **Karantina — tinjau** | Tidak (D13) |
| *(`voided_at` terisi)* | **Dibatalkan** | Tidak |

Semua status berakhiran "— tinjau" memakai **penanda visual yang sama** (ikon dan gaya badge identik) agar mudah dikenali di hari H. Setelah Admin menandainya sudah ditinjau, akhiran dan penandanya diganti keterangan "· ditinjau" (mis. "Ganda · ditinjau").

**Kategori tamu:** Regular, VIP (ikon bintang), VVIP (ikon mahkota).

**Tamu tambahan** = tamu di luar daftar Kelola Tamu (ditambahkan lewat Tambah Tamu atau QR Umum), serta orang yang dibawa tamu undangan di luar jumlah yang tercatat.

## 6. Ruang Lingkup per Fase

| Fase | Isi |
|---|---|
| **MVP (P0)** | Kelola Tamu (manual, impor, grup, edit massal), Kategori + Nomor Urut VIP/VVIP + nomor tiket otomatis per perangkat, Detail Kehadiran, Kelola Akses Usher + pengaturan check-in, App Penerima Tamu (scan, cari, tambah, verifikasi, cetak tiket, pop-up sapaan, Hybrid Mode), Riwayat Check-In/Out, Statistik Buku Tamu, QR tamu yang dapat diunduh |
| **Fase 2 (P1)** | E-Invitation (kartu + unduh), Hadiah (hadir + titipan), Layar Sapa, Auto Thank You Message, mode Check-Out di app, export, manajemen perangkat |
| **Fase 3 (P2)** | Form link pendataan tamu, sesi acara, ESC/POS langsung ke printer |
| **Iterasi berikutnya** | Selfie Check-In (belum dikembangkan sekarang) |

---

## 7. Kebutuhan Fungsional — Smart Dashboard

### 7.1 Kelola Tamu

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-G-01 | CRUD tamu: nama, telepon, kategori, grup, jumlah undangan (pax), Nomor Urut khusus (opsional), catatan | P0 |
| FR-G-02 | **Tambah manual** lewat modal form; kategori dipilih dari 3 pilihan | P0 |
| FR-G-03 | **Impor tamu** (.xlsx/.xls/.csv): unduh template contoh → unggah → validasi → halaman **Tinjau Tamu** (error per baris) → **Proses Tamu**; kolom Nomor Urut opsional, nomor ganda atau nomor berpola nomor perangkat (FR-C-02) ditandai di Tinjau Tamu. Parsing di browser admin; batas ukuran file 5 MB *(Asumsi)*; library XLSX diambil dari distribusi resmi SheetJS, bukan paket `xlsx` lama di registry npm | P0 |
| FR-G-04 | **Grup Tamu**: CRUD grup (nama + deskripsi opsional) | P0 |
| FR-G-05 | **Edit massal**: pilih beberapa tamu → ubah grup atau kategori sekaligus | P0 |
| FR-G-06 | **Edit detail tamu** (klik nama → modal), termasuk **ubah status RSVP manual** | P0 |
| FR-G-07 | QR unik per tamu (token acak ≥ 128 bit, tidak berurutan); unduh QR dan salin link. Token mentah hanya ada di server dan di E-Invitation; perangkat usher hanya menyimpan hash-nya (FR-HM-01). Tombol **salin link** aktif bersama halaman `/i/{token}` (M4); format URL `/i/{token}` sudah dikunci di konfigurasi bersama sejak MVP (D17) | P0 |
| FR-G-08 | Pencarian, filter (nama, kategori, grup, RSVP, kehadiran), paginasi di sisi server | P0 |
| FR-G-09 | Kolom **kehadiran Hadir/Belum hadir**; otomatis *Hadir* saat check-in (check-in `quarantined` tidak mengubah kehadiran sampai disetujui) | P0 |
| FR-G-10 | Export daftar tamu dan kehadiran ke CSV. Setiap sel yang diawali `=`, `+`, `-`, `@`, tab, atau carriage return diberi awalan `'` untuk mencegah CSV/formula injection | P1 |
| FR-G-11 | Deteksi duplikat (nama + telepon) saat impor/tambah | P1 |
| FR-G-12 | Form link pendataan tamu mandiri (butuh halaman publik) | P2 |
| FR-G-13 | Sesi acara (mis. akad/resepsi) dan acara utama per tamu | P2 |

### 7.2 Kategori Tamu & Setting Nomor Urut VIP/VVIP

Pendekatan **hybrid**: **Nomor Urut khusus** yang ditetapkan admin untuk VIP/VVIP (sesuai referensi), ditambah **nomor tiket otomatis berbasis kode perangkat** untuk tamu lainnya. Alasan dan alternatif yang dipertimbangkan ada di 15.1 (D2).

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-C-01 | Tiga kategori tetap: **Regular**, **VIP** (ikon bintang), **VVIP** (ikon mahkota); ikon tampil di semua daftar nama | P0 |
| FR-C-02 | **Nomor Urut khusus** per tamu (kolom di Kelola Tamu), terutama untuk VIP/VVIP: maksimal 20 karakter (huruf, angka, `-`; mis. `VVIP-007`), **unik per event** (nomor ganda ditolak). Nilai **dinormalisasi ke huruf besar** sebelum divalidasi dan disimpan (mis. `a-017` diperlakukan sebagai `A-017`). **Tidak boleh cocok dengan pola nomor perangkat** `^[A-Z]{1,2}-\d+$` maupun pola kode hadiah, agar tidak bertabrakan dengan nomor otomatis (divalidasi di klien, di Tinjau Tamu, dan oleh constraint DB). Prefix dari FR-C-03 juga divalidasi dengan aturan yang sama. Hanya tampil saat Digital Guestbook dipakai (app dan tiket) | P0 |
| FR-C-03 | **Setting Nomor Urut** per kategori VIP dan VVIP: prefix, angka awal, jumlah digit (mis. prefix `VVIP-`, mulai 1, 3 digit → `VVIP-001`) | P0 |
| FR-C-04 | **Terapkan Nomor Urut**: isi nomor massal untuk tamu VIP/VVIP yang belum bernomor. Pilih urutan (nama A–Z, grup lalu nama, atau urutan input), tampilkan **pratinjau** sebelum disimpan, jangan menimpa nomor yang sudah ada kecuali dikonfirmasi, catat di audit log | P0 |
| FR-C-05 | Nomor khusus dapat diubah manual per tamu, diimpor lewat kolom opsional, dan dihapus massal oleh Admin dengan konfirmasi | P0 |
| FR-C-06 | **Nomor tiket otomatis** untuk tamu tanpa nomor khusus (Regular, tamu tambahan, VIP/VVIP tanpa nomor): format `{KodePerangkat}-{urut 3 digit}`, mis. `A-017`. Kode perangkat diterbitkan server saat usher pertama kali login di perangkat; counter disimpan lokal. Tidak butuh koordinasi server sehingga berjalan penuh saat offline. Kapasitas maksimal **702 kode per event** (`A`–`ZZ`, mengikuti pola); login yang membutuhkan kode ke-703 ditolak dengan pesan jelas | P0 |
| FR-C-07 | Nomor yang tercetak disimpan sebagai **snapshot** di data check-in. Mengubah nomor khusus setelah check-in tidak mengubah tiket lama; cetak ulang memakai nomor yang tercatat. Admin dapat menetapkan ulang nomor tiket lewat Ubah Detail Kehadiran (tercatat di audit log) | P0 |
| FR-C-08 | **Check-in ulang tamu yang sama** (saat **Tamu Check-In Lebih 1 Kali** aktif): bila perangkat sudah mengetahui check-in sebelumnya, tiket memakai nomor yang sama (setara cetak ulang). Bila belum tahu (mis. check-in pertama ada di perangkat lain yang belum sinkron), perangkat memakai aturan nomor biasa; server lalu menandainya `repeat` sehingga tidak bentrok dengan unique index (lihat 12.3) | P0 |

### 7.3 Detail Kehadiran Tamu

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-A-01 | Tampilkan per tamu: status RSVP, pax RSVP, kehadiran (Hadir/Belum hadir), waktu check-in/out, nomor urut, jumlah hadir aktual, penanda tamu tambahan, usher dan perangkat yang memproses | P0 |
| FR-A-02 | Admin dapat mengubah detail kehadiran manual (jumlah hadir, nomor tiket, check-out) dan **menandai hadir manual** tamu yang belum check-in (check-in tanpa perangkat, `source = 'admin'`, nomor tiket opsional). Koreksi jumlah orang untuk tamu yang masuk ulang dilakukan pada check-in `accepted` (D11). Setiap perubahan masuk audit log | P0 |

### 7.4 Penerima Tamu — Kelola Akses & Pengaturan

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-R-01 | **Tambah Penerima Tamu**: nama usher + mode **Check-In** (registrasi di pintu masuk) atau **Check-Out** (device di pintu keluar). Mode *Tracking* tidak dibuat. Usher mode Check-Out sudah dapat dibuat, tetapi baru dapat mengirim data setelah mode Check-Out di app tersedia (P1); sebelum itu server membalas `mode_mismatch` | P0 |
| FR-R-02 | **Akses app** lewat **Kode Acara + PIN Akses** atau **Scan QR Login** yang tersedia di dashboard; admin dapat menonaktifkan/menghapus usher dan mereset PIN. **Kode Acara**: 6 karakter dari alfabet tanpa karakter mirip, dibuat server saat event dibuat, unik, **tidak rahasia**, dan hanya dipakai untuk mencari event. **PIN Akses** memakai pola *selector + verifier* dan ditampilkan sebagai `AB-XXXX-XXXX`: 2 karakter pertama adalah **ID usher** (dibuat server, unik dalam event, tidak rahasia, hanya untuk lookup), 8 karakter berikutnya adalah **rahasia** (alfanumerik tanpa karakter mirip seperti `0/O`, `1/l`). Hanya bagian rahasia yang di-hash dengan hash lambat (bcrypt); PIN lengkap hanya ditampilkan sekali. Server mencari usher lewat (Kode Acara, ID usher), lalu menjalankan **tepat satu** verifikasi bcrypt. Bila Kode Acara atau ID usher tidak ditemukan, atau usher nonaktif, server tetap menjalankan satu bcrypt dummy. Respons gagal **identik** untuk semua penyebab, baik status, isi, maupun waktu yang diseragamkan. Reset PIN membuat rahasia baru (ID usher tetap) dan langsung membatalkan PIN lama. Menonaktifkan atau menghapus usher mencabut semua perangkatnya dengan tingkat **Cabut** (FR-R-08). QR Login **sekali pakai**, berlaku **5 menit**, dan dibuat baru setiap kali admin menekan tombol tampilkan | P0 |
| FR-R-03 | **Pengaturan Proses Check-In** (toggle): **Tampilkan Verifikasi Tamu** (berlaku untuk Regular; untuk VIP/VVIP selalu aktif, lihat D9), **Tamu Check-In Lebih 1 Kali**, **Print Tiket Penomoran**, **Print Hadiah Titipan**. Toggle Print Hadiah Titipan tampil bersama fitur Hadiah (P1, FR-R-05); sampai saat itu nilainya nonaktif (D16) | P0 |
| FR-R-04 | **Print Tiket Penomoran**: pilih informasi yang tampil di tiket, kategori yang boleh mencetak (Regular/VIP/VVIP), dan jumlah salinan cetak. Pilihan "kode hadiah" tersedia bersama fitur Hadiah (P1) | P0 |
| FR-R-05 | **Print Hadiah Titipan**: aktif/nonaktif, kategori, dan jumlah salinan | P1 |
| FR-R-06 | Perubahan pengaturan langsung berlaku di App Penerima Tamu (lewat sync/Realtime) | P0 |
| FR-R-07 | Daftar perangkat aktif (last sync, antrean belum tersinkron, versi app) | P1 |
| FR-R-08 | **Cabut akses perangkat/usher**, dua tingkat. Pada kedua tingkat, `pull_snapshot` langsung membalas `revoked` **tanpa data apa pun**, termasuk delta. **(a) Cabut** (bawaan, mis. usher diganti): sesi Auth perangkat tetap hidup, tetapi perangkat **hanya** dapat memanggil `push_outbox`, dan setiap item yang valid disimpan sebagai `quarantined` (tidak dihitung, menunggu keputusan Admin, FR-RW-05). Untuk perangkat yang dicabut, jendela karantina berakhir pada `session_expires_at` (FR-R-10) dan tidak diperpanjang masa tenggang; setelah itu push ditolak. Jumlah item karantina dibatasi **500 per perangkat** (konfigurasi); item di atas batas ditolak dan memicu peringatan di dashboard. **(b) Cabut & putus total** (HP hilang atau dicuri): dashboard memanggil Edge Function `device-cleanup`, yang langsung menghapus user Auth perangkat (`auth.admin.deleteUser`), dan **semua push ditolak**; data yang belum terkirim hanya dapat masuk lewat ekspor outbox darurat yang diunggah Admin (FR-HM-08). Tingkat (a) dapat dinaikkan ke (b), tidak sebaliknya. Saat perangkat terhubung berikutnya, app menjalankan FR-HM-09. Perangkat yang tetap offline tidak bisa dipaksa; risiko ini diterima dan dicatat. User Auth perangkat dihapus **otomatis** oleh job terjadwal (`pg_cron` → `pg_net` → Edge Function `device-cleanup`) setelah sesi berakhir ditambah masa tenggang 72 jam (FR-R-10). **Daftar perangkat minimal** (kode, nama, waktu login, terakhir terlihat, sesi berakhir, tingkat pencabutan, jumlah item karantina, selisih jam > 2 menit) termasuk P0 untuk keperluan pencabutan; kolom lain di FR-R-07 tetap P1 | P0 |
| FR-R-09 | **Rate limit login usher**: percobaan PIN gagal dihitung per kunci **(IP + Kode Acara yang dikirim)**; setelah **10 gagal dalam 15 menit**, login PIN untuk kunci itu **diblokir** sementara. Selain itu ada **blokir global per IP** (tanpa memandang Kode Acara) setelah **50 gagal dalam 15 menit**. Blokir ini menutup serangan yang mengganti-ganti Kode Acara palsu agar kunci (IP + kode) selalu baru, padahal setiap percobaan tetap memakan satu bcrypt dummy; usher sungguhan di satu Wi-Fi tidak akan mencapai angka itu. Kedua blokir diperiksa **sebelum** bcrypt dijalankan. Kunci gabungan dipakai karena perangkat di satu Wi-Fi lokasi biasanya berbagi satu IP publik, sehingga kegagalan di satu acara tidak memblokir acara lain di jaringan yang sama (mis. gedung dengan beberapa resepsi). Usher dari acara yang sama di lokasi yang sama tetap berbagi kunci; karena itu ambangnya 10 dan tersedia jalur QR Login. Kode Acara yang tidak ada dihitung dengan cara yang sama dan mendapat respons identik, sehingga tidak dapat dipakai untuk menebak kode. Per event: bila percobaan gagal dari semua IP mencapai 20 dalam 15 menit *(Asumsi)*, Admin melihat **peringatan** di dashboard dan peristiwa itu dicatat di audit log, **tanpa** mengunci login, agar penyerang yang mengetahui Kode Acara tidak dapat mengunci semua usher di hari H. **QR Login tidak terkena blokir**, karena tokennya ≥ 128 bit, sekali pakai, berlaku 5 menit, dan dibuat Admin yang sudah login; QR Login menjadi jalur cadangan saat login PIN diblokir. Setiap percobaan, termasuk QR yang tidak valid, dicatat di `auth_attempts`. Semua ambang disimpan di konfigurasi bersama | P0 |
| FR-R-10 | Sesi usher berakhir otomatis pada H+1 pukul 06.00 waktu lokal event *(Asumsi)*, atau saat event diarsipkan. Zona waktu disimpan per event (default `Asia/Jakarta`). Setelah sesi berakhir, `pull_snapshot` membalas `expired` **tanpa data**. **Sesi habis wajar** (perangkat tidak dicabut, mis. HP offline semalaman lalu baru tersambung lewat pukul 06.00): `push_outbox` masih diterima selama **masa tenggang 72 jam** *(Asumsi; konstanta yang sama dengan jeda penghapusan user Auth perangkat)*, dan setiap item disimpan sebagai `quarantined` dengan `quarantine_reason = 'session_expired'`; setelah masa tenggang, push ditolak. **Event diarsipkan**: push langsung ditolak; data yang belum terkirim hanya dapat masuk lewat ekspor outbox darurat yang diunggah Admin (FR-HM-08). Dialog arsip memperingatkan hal ini | P0 |

### 7.5 Statistik Buku Tamu

Setiap statistik dibandingkan dengan jumlah tamu yang **sudah konfirmasi hadir (RSVP)**. Check-in `quarantined`, `duplicate`, dan yang dibatalkan tidak dihitung; check-in `repeat` tidak menambah jumlah orang (D11).

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-S-01 | **Statistik Kehadiran Seluruh Tamu**: total hadir, termasuk tamu undangan dan orang yang dibawa. Tampilkan **peringatan** bila jumlah hadir melebihi **batas jumlah hadir**: isian opsional per event di Kelola Tamu; bila kosong, batasnya total jumlah undangan (Σ `invited_pax` tamu undangan, tidak termasuk tamu tambahan dan tamu yang dihapus). Dashboard menampilkan batas mana yang sedang dipakai (D14) | P0 |
| FR-S-02 | **Kategori Tamu**: jumlah hadir per VVIP/VIP/Regular | P0 |
| FR-S-03 | **Statistik Tamu Check-In**: tamu undangan yang sudah masuk, dari awal sampai akhir acara | P0 |
| FR-S-04 | **Statistik Tamu Check-Out**: yang sudah keluar; hanya terisi bila check-out dipakai | P0 |
| FR-S-05 | **Statistik Tamu Tambahan**: tamu di luar daftar Kelola Tamu | P0 |
| FR-S-06 | **Statistik Grup**: hadir per grup, dibandingkan dengan jumlah anggota grup | P1 |
| FR-S-07 | Pembaruan realtime: trigger DB mengirim sinyal ringan lewat **Supabase Realtime Broadcast** di channel privat per event; dashboard lalu memanggil RPC agregat statistik (debounce ±1 detik). Fallback polling tiap 10 detik bila koneksi Realtime terputus. Postgres Changes tidak dipakai | P0 |

### 7.6 Hadiah dari Tamu untuk Pengantin

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-H-01 | **Hadiah Tamu Hadir**: terdata saat registrasi (konfirmasi kehadiran). Jenis: **Amplop**, **Kado**, **Transfer** | P1 |
| FR-H-02 | **Hadiah Titipan**: didata terpisah oleh usher dengan jenis yang sama (lihat 8.5) | P1 |
| FR-H-03 | **Penomoran Hadiah**: kode unik per hadiah untuk ditulis di amplop/kado agar mudah dicocokkan dengan data | P1 |
| FR-H-04 | **Riwayat Hadiah** di dashboard: daftar hadiah, jenis, nomor, tamu, waktu, usher; export | P1 |
| FR-H-05 | Tampilkan catatan bahwa statistik hadiah mungkin tidak 100% akurat karena tamu dapat memberi langsung ke keluarga | P1 |

### 7.7 Riwayat

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-RW-01 | Tab **Check-In** (hanya tamu yang masuk), **Check-Out** (hanya yang keluar), dan **Semua** | P0 |
| FR-RW-02 | **Penanda RSVP vs kehadiran aktual**: *Akan hadir (X orang)*, *Tidak hadir* (tapi hadir), *Belum konfirmasi* (tapi hadir); sorot kondisi **overcapacity**, yaitu jumlah hadir tamu melebihi jumlah tercatatnya (`rsvp_pax` bila *Akan hadir*, selain itu `invited_pax`) | P0 |
| FR-RW-03 | Admin dapat membatalkan (undo) check-in yang salah dengan alasan; tercatat di audit log | P0 |
| FR-RW-04 | Admin dapat mencatat check-out manual | P0 |
| FR-RW-05 | **Tinjau check-in bermasalah**: `duplicate` dan `conflict` dapat ditandai sudah ditinjau atau diselesaikan (ubah nomor tiket lalu status dievaluasi ulang, atau batalkan). `quarantined` dapat **disetujui** (status dievaluasi ulang dengan aturan 12.3 pada saat disetujui; tamu tambahan baru dibuat saat itu) atau **ditolak** (alasan wajib; data tetap tersimpan). Tersedia aksi massal per perangkat. Check-in untuk tamu yang sudah dihapus diberi penanda. Semua keputusan masuk audit log | P0 |

### 7.8 Pop-Up & Layar Sapa

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-P-01 | **Pop-Up Sapaan**: teks dan foto dapat diatur; **tiga tampilan berbeda** (Regular/VIP/VVIP); pratinjau langsung di dashboard. Foto disimpan di bucket privat; cara perangkat usher mengambil foto ditetapkan bersama App Penerima Tamu (Q11) | P0 |
| FR-P-02 | Variabel teks sapaan (`{{nama}}`, `{{kategori}}`) | P0 |
| FR-P-03 | **Layar Sapa** untuk Smart TV (target ≥ 42 inci), dua mode: **Default** (nama mempelai + detail acara, tampil saat tidak ada check-in) dan **Sapaan** (sapaan personal + nama tamu setelah check-in). Tiga pilihan layout dan warna latar per kategori | P1 |
| FR-P-04 | Layar Sapa dibuka lewat URL bertoken (tanpa login). Token ditukar lewat Edge Function menjadi JWT berumur pendek yang **hanya** boleh mendengarkan channel Broadcast sapaan event tersebut. Payload hanya berisi nama tampilan, kategori, dan teks sapaan, tanpa telepon, token QR, atau data lain. Token dapat dicabut dan dibuat ulang oleh Admin. Role `anon` tidak diberi akses baca tabel apa pun | P1 |

### 7.9 Auto Thank You Message

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-M-01 | Template pesan terima kasih dengan variabel (`{{nama}}`, `{{nama_acara}}`) yang diatur sebelum hari acara | P1 |
| FR-M-02 | **Otomatis**: data tamu masuk ke halaman **Schedule Thank You** setelah berhasil check-in, lalu pesan dikirim lewat antrean dengan jeda antar pesan | P1 |
| FR-M-03 | Admin dapat menonaktifkan fitur ini per event | P1 |
| FR-M-04 | Abstraksi `WhatsAppProvider` agar gateway dapat diganti (tidak resmi atau WhatsApp Cloud API resmi) | P1 |
| FR-M-05 | Log per pesan (pending/terkirim/gagal) dan kirim ulang | P1 |

### 7.10 E-Invitation

E-Invitation adalah **kartu undangan per tamu** (gambar) berisi ringkasan acara, nama tamu, dan **QR unik** untuk check-in. Dapat diunduh/dibagikan atau dicetak untuk disisipkan ke undangan cetak.

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-E-01 | **Atur tampilan**: Teks Atas, **Judul E-Invitation (wajib)**, Teks Bawah, Background (unggah sendiri atau gambar default), Deskripsi, Sapaan, Himbauan | P1 |
| FR-E-02 | Warna (latar dan teks) dan **Typography** (font) dapat disesuaikan; pratinjau langsung | P1 |
| FR-E-03 | **Update E-Invitation**: kartu dibuat ulang setelah ada perubahan data atau tampilan; tombol **Update** menampilkan progres, dan unduhan dinonaktifkan sampai proses update selesai | P1 |
| FR-E-04 | **QR Code Umum** (toggle): QR tanpa kode unik untuk tamu yang tidak terdata. Jika dipindai di App Penerima Tamu, usher diarahkan ke **Tambah Tamu On The Spot** | P1 |
| FR-E-05 | Toggle **Tampilkan Link Undangan** (bila ada link undangan eksternal; jika nonaktif, link tidak tampil di kartu/barcode) | P1 |
| FR-E-06 | **Self Download**: unduh untuk semua tamu, per kategori, per grup, atau per tamu (ZIP untuk banyak file); **riwayat unduhan** tercatat | P1 |
| FR-E-07 | Halaman publik minimal per tamu (`/i/{token}`) untuk melihat dan mengunduh kartu miliknya. Halaman memanggil Edge Function yang memvalidasi token lalu mengembalikan **signed URL berumur pendek** (±10 menit). Edge Function ini juga dibatasi rate limit | P1 |
| FR-E-08 | Penyimpanan di **Supabase Storage** dalam bucket **privat** tanpa policy list untuk publik; pembuatan kartu massal di latar belakang (lihat 11.3). Upload gambar (background, foto pop-up) dibatasi MIME `image/png`, `image/jpeg`, `image/webp` (tanpa SVG) dan ukuran maksimal 5 MB | P1 |

### 7.11 Selfie Check-In — Iterasi Berikutnya

**Tidak dikembangkan pada iterasi ini.** Tidak ada tabel, bucket, toggle, maupun langkah UI untuk selfie di MVP dan fase 2. Alur registrasi bersifat bertahap, sehingga langkah selfie nantinya dapat disisipkan antara Verifikasi dan Cetak Tiket tanpa mengubah alur inti. Saat dikembangkan, perlu diperhatikan: bucket privat dengan signed URL, persetujuan/pemberitahuan kepada tamu (UU PDP), dan kebijakan retensi foto.

### 7.12 Cetak Tiket Thermal

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-TK-01 | Tiket memuat nomor urut besar, nama tamu, kategori, dan informasi lain sesuai pengaturan FR-R-04 (nama acara, kode hadiah). Ukuran kertas 58/80 mm | P0 |
| FR-TK-02 | **Android: RawBT sebagai jalur utama** (tanpa dialog cetak, sehingga target G1 tercapai). **Cadangan:** `window.print()` dengan CSS kertas thermal (dipakai di iOS atau bila RawBT tidak ada). Target G1 diukur memakai RawBT | P0 |
| FR-TK-03 | Cetak ulang dari riwayat tamu lewat menu ⋮ → **Print** (tercatat) | P0 |
| FR-TK-04 | Tiket Hadiah Titipan (penanda untuk usher) | P1 |
| FR-TK-05 | Cetak langsung ESC/POS via Web Bluetooth/WebUSB (hanya Chrome Android) | P2 |

---

## 8. Kebutuhan Fungsional — App Penerima Tamu (PWA)

### 8.1 Akses

- Login dengan **Kode Acara + PIN Akses** (dari dashboard) atau **Scan QR Login** yang ditampilkan di dashboard; setelah QR berhasil dipindai, usher masuk tanpa mengetik PIN. QR Login sekali pakai dan berlaku 5 menit. *(P0)*
- **Login pertama di sebuah perangkat wajib online**, karena server menerbitkan kode perangkat dan snapshot awal. App menampilkan pesan jelas bila dicoba saat offline. *(P0)*
- Setelah login, app memanggil `navigator.storage.persist()` dan menampilkan peringatan bila browser menolak (data lokal berisiko dihapus browser). *(P0)*
- Aplikasi dapat dipasang sebagai PWA (Add to Home Screen), mode layar penuh. *(P0)*

### 8.2 Beranda

Tombol utama **Scan** dan **Tamu**, indikator online/offline, jumlah antrean sinkronisasi. *(P0)*

### 8.3 Proses Registrasi (tiga cara)

Langkah yang opsional mengikuti pengaturan di Smart Dashboard Penerima Tamu.

**A. Scan QR Code** *(P0)*

1. Dari beranda, tekan **Scan** untuk membuka halaman scan.
2. Arahkan QR yang dibawa tamu ke layar perangkat untuk proses Check-In.
3. Jika scan berhasil, tampil **Pop-Up Sapaan**; pilih **Lanjutkan**.
4. Jika **Verifikasi** diaktifkan, tampil halaman Verifikasi.
5. Jika **Print Tiket Penomoran** aktif, tekan **Lanjutkan**; modal menampilkan informasi sesuai isian verifikasi, lalu tiket tercetak.

**B. Cari Tamu** *(P0)*

1. Dari beranda, tekan **Tamu**, lalu ketik nama di kolom pencarian (pencarian lokal).
2. Jika ditemukan, tekan **Check-In** untuk melanjutkan registrasi masuk.
3. Jika **Verifikasi** aktif, tampil halaman Verifikasi.
4. **Print Tiket Penomoran**: tekan **Lanjutkan**; modal menampilkan informasi sesuai isian verifikasi.
5. Setelah tiket tercetak, tampil **Pop-Up Sapaan** (jika digunakan) berisi informasi sesuai konfirmasi kehadiran.

**C. Tambah Tamu** *(P0)*

1. Dari halaman **Tamu**, tekan **Tambah Tamu**. (Jalur yang sama dipakai saat QR Umum dipindai: *Tambah Tamu On The Spot*.)
2. Lengkapi detail tamu, lalu tekan **Check-In**.
3. Lanjut ke Verifikasi (jika aktif), cetak tiket, lalu Pop-Up Sapaan. Tamu ditandai sebagai **tamu tambahan**.

### 8.4 Halaman Tamu

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-RA-01 | Statistik ringkas tamu yang sudah check-in, dan **Riwayat Tamu** (daftar kehadiran) | P0 |
| FR-RA-02 | Menu ⋮ per baris → **Ubah Detail Kehadiran** (jumlah kehadiran, hadiah yang dibawa) | P0 |
| FR-RA-03 | Menu ⋮ per baris → **Print Tiket Penomoran** (cetak ulang) | P0 |
| FR-RA-04 | Cegah check-in ganda: QR yang sudah check-in menampilkan peringatan (waktu dan usher sebelumnya). Bila pengaturan **Tamu Check-In Lebih 1 Kali** aktif, check-in ulang diizinkan (aturan nomor di FR-C-08). Check-in ganda yang baru ketahuan setelah sync (dua perangkat offline) ditandai `duplicate` atau `repeat` dan tampil di Riwayat untuk ditinjau Admin | P0 |
| FR-RA-05 | Tombol **Hadiah Titipan** dan **Tambah Tamu** | P0 / P1 |

### 8.5 Hadiah di App

- **Hadiah Tamu Hadir** terdata saat registrasi pada langkah konfirmasi kehadiran (pilih Amplop, Kado, atau Transfer). Halaman konfirmasi menampilkan **kode unik** untuk ditulis di amplop/kado (Penomoran Hadiah). Untuk **Tambah Tamu**, kode muncul setelah registrasi selesai dan dapat dilihat di Riwayat Tamu. *(P1)*
- **Hadiah Titipan** didata terpisah oleh usher: menu **Tamu** → **Hadiah Titipan** → lengkapi data konfirmasi → **Simpan** → modal cetak tiket agar usher dapat menandai hadiahnya. *(P1)*

### 8.6 Mode Check-Out

Usher dengan mode **Check-Out** mencatat tamu keluar lewat scan QR atau cari nama. *(P1)*

### 8.7 Hybrid Mode (Online & Offline)

Aktif secara **default** tanpa pengaturan tambahan. Proses check-in tetap lancar walau koneksi internet di lokasi tidak stabil; antrean tamu tetap terjaga.

| ID | Kebutuhan | Prio |
|---|---|---|
| FR-HM-01 | Saat login/online, app mengunduh **snapshot minimal** tamu dan konfigurasi event ke IndexedDB lewat RPC `pull_snapshot`: id, nama, kategori, grup, pax, nomor khusus, status RSVP/kehadiran, **`qr_token_hash` (SHA-256)**, dan ringkasan check-in aktif tamu (`checkIn`: status, nomor tiket, waktu check-in, nama usher) untuk peringatan check-in ganda (FR-RA-04) dan nomor yang sama saat check-in ulang (FR-C-08). **Nomor telepon, catatan, dan token QR mentah tidak pernah dikirim ke perangkat usher.** Saat scan, app meng-hash isi QR (Web Crypto) lalu mencocokkannya dengan hash lokal | P0 |
| FR-HM-02 | Semua pembacaan (scan, cari) memakai data lokal; fungsi inti berjalan penuh tanpa internet | P0 |
| FR-HM-03 | Setiap check-in ditulis ke **outbox** lokal dan disinkronkan otomatis di latar belakang (batch, retry) | P0 |
| FR-HM-04 | Indikator online/offline, jumlah item belum tersinkron, waktu sinkron terakhir | P0 |
| FR-HM-05 | Delta sync periodik (tiap 15 detik saat online) memakai kursor `updated_at` dari server untuk menarik perubahan dari admin dan perangkat lain. Penghapusan dikirim sebagai **tombstone** (`deleted_at`) agar tamu yang dihapus admin tidak bisa check-in di perangkat lain | P0 |
| FR-HM-06 | Nomor tiket saat offline: **Nomor Urut khusus** tamu (sudah ada di data lokal) atau **kode perangkat + counter lokal** (lihat 12.3) | P0 |
| FR-HM-07 | **Logout dan ganti akun diblokir selama outbox belum kosong.** Bila dipaksa, app meminta konfirmasi dua langkah dan menawarkan ekspor outbox lebih dulu | P0 |
| FR-HM-08 | **Ekspor outbox darurat**: tombol di menu pengaturan app untuk menyimpan item yang belum tersinkron ke file JSON. Admin dapat mengunggah file itu di dashboard; file diproses dengan aturan yang sama (idempoten) dan **diproses normal, tidak dikarantina**, karena diunggah Admin yang sudah login (`source = 'outbox_upload'`). Urutan resmi memakai waktu unggah (`received_at`), bukan jam perangkat | P0 |
| FR-HM-09 | **Penghapusan data lokal**: bila server menyatakan perangkat **dicabut** (tingkat Cabut) atau **sesi berakhir** (masih dalam masa tenggang), app mengirim sisa outbox (server menyimpannya sebagai `quarantined`, lihat 12.3), lalu menghapus IndexedDB, cache, dan kredensial. Bila push **ditolak** (putus total, event diarsipkan, jendela karantina atau masa tenggang sudah habis, atau sesi Auth tidak lagi valid) atau ada item yang dibalas galat, app **tidak** menghapus item tersebut sebelum usher mengekspornya (FR-HM-08). Setelah ekspor berhasil, data lokal dihapus | P0 |
| FR-HM-10 | Setiap item check-in mencatat jam perangkat (`checked_in_at`); server menambahkan `received_at`. Selisih jam perangkat dengan server dicatat saat sync dan ditampilkan di daftar perangkat bila lebih dari 2 menit | P0 |

---

## 9. Alur Pengguna Utama (Admin)

1. Admin membuat **event** dan mengatur format **Nomor Urut VIP/VVIP** (prefix, angka awal, jumlah digit).
2. Admin menambah **tamu** (manual atau impor, lewat Tinjau Tamu) dan **grup**; QR otomatis dibuat. Untuk VIP/VVIP, admin menjalankan **Terapkan Nomor Urut** atau mengisi nomor manual.
3. Admin menambah **Penerima Tamu** (mode Check-In/Check-Out) dan mengatur proses check-in (verifikasi, tiket, check-in ulang).
4. Admin mengatur **Pop-Up Sapaan** (dan Layar Sapa pada fase 2).
5. *(P1)* Admin menyusun **E-Invitation**, menekan **Update**, lalu mengunduh/membagikan kartu ke tamu.
6. Hari H: usher check-in; Admin memantau **Statistik** dan **Riwayat** secara realtime.
7. Setelah/selama acara: Auto Thank You berjalan; Admin meninjau **Riwayat Hadiah** dan mengekspor laporan.

---

## 10. Kebutuhan Non-Fungsional

### 10.1 Performa (target awal, perlu divalidasi dengan perangkat nyata)

| Metrik | Target |
|---|---|
| Scan terdeteksi → data tamu tampil | ≤ 500 ms (p95), tanpa request jaringan |
| Pencarian nama (5.000 tamu) | ≤ 100 ms |
| Konfirmasi check-in → tiket mulai tercetak | ≤ 1 detik (jalur RawBT; `window.print()` tidak memenuhi target karena ada dialog cetak) |
| Update statistik dashboard (online) | ≤ 3 detik |
| Ukuran bundle awal PWA (gzip) | ≤ 150 KB, **tidak termasuk** chunk scanner QR yang di-lazy-load saat halaman Scan pertama dibuka (lalu di-precache Service Worker) |
| Pembuatan E-Invitation 1.000 tamu | ≤ 5 menit di laptop kelas menengah *(Asumsi)* |

### 10.2 Skala *(Asumsi)*

- Hingga **5.000 tamu per event**.
- Hingga **10 perangkat usher** dan **20 sesi dashboard/Layar Sapa** bersamaan.
- Beberapa event aktif paralel, terisolasi lewat `event_id`.

### 10.3 Keandalan

- Tidak ada kehilangan data check-in: outbox di IndexedDB dengan `storage.persist()`, logout diblokir selama outbox belum kosong, ekspor outbox darurat (FR-HM-07, FR-HM-08), dan sinkronisasi idempoten.
- Backup database otomatis (butuh plan berbayar Supabase) dan export manual sebelum hari H.
- Project Supabase **tidak boleh di plan gratis untuk event nyata** karena dapat ter-pause saat tidak aktif.

### 10.4 Keamanan & Privasi

Model kepercayaan dan jalur akses per aktor dirinci di 11.4. Ringkasan kebutuhannya:

**Otorisasi dan database**

- **RLS** aktif di semua tabel; policy per peran dan per event; gunakan `(select auth.uid())` di policy.
- Klaim otorisasi (peran, `event_id`, `usher_id`, `device_id`) hanya dibaca dari **`app_metadata`** (hanya bisa ditulis service role) atau dari tabel server (`event_members`, `devices`). **`user_metadata` tidak pernah dipakai untuk otorisasi** karena dapat diubah pengguna sendiri.
- **Usher tidak punya hak SELECT/INSERT/UPDATE/DELETE langsung** pada tabel mana pun. Akses usher hanya lewat RPC `pull_snapshot` dan `push_outbox`, yang memeriksa perangkat tidak dicabut, sesi belum berakhir, event cocok, dan mode usher sesuai.
- Role **`anon` tidak punya hak apa pun** pada tabel di schema `public`. Akses publik (Layar Sapa, halaman `/i/{token}`) hanya lewat Edge Function.
- Fungsi `SECURITY DEFINER` ditempatkan di schema privat (mis. `private`) yang tidak diekspos API, memakai `set search_path = ''`, dan dibungkus fungsi publik yang aman. Setiap fungsi di `public` diberi `REVOKE EXECUTE ... FROM public, anon` lalu `GRANT` hanya ke role yang perlu.
- Service role key hanya ada di Edge Functions, tidak pernah di bundle frontend maupun repo.
- Job terjadwal (`pg_cron` + `pg_net`) memanggil Edge Function dengan **secret khusus job** yang disimpan di Supabase Vault, **bukan** service role key. User Auth hanya dihapus lewat Admin API Auth (`auth.admin.deleteUser`) di Edge Function, tidak pernah dengan SQL langsung ke `auth.users`.

**Kredensial dan token**

- Token QR acak dengan entropi ≥ 128 bit, tidak berurutan. Perangkat usher hanya menyimpan hash SHA-256-nya.
- Login usher memakai Kode Acara + PIN Akses `AB-XXXX-XXXX` (ID usher tidak rahasia + 8 karakter rahasia yang dibuat server dan disimpan sebagai hash lambat). Setiap percobaan menjalankan tepat satu bcrypt, respons gagal identik, dan blokir berlaku per (IP + Kode Acara) (FR-R-02, FR-R-09). QR Login sekali pakai, berlaku 5 menit, dan tidak terkena blokir.
- Sign-up publik Supabase Auth dimatikan. Akun Admin dibuat oleh operator, dan hanya user dengan `app_metadata.role = 'admin'` yang dapat membuat event.
- Token Layar Sapa dan token halaman `/i/{token}` dapat dicabut; JWT yang diterbitkan Edge Function berumur pendek dan dibatasi ke satu channel/resource.
- Sesi usher berakhir otomatis (FR-R-10); perangkat yang dicabut menghapus data lokal saat terhubung kembali (FR-HM-09).

**Data dan file**

- Perangkat usher tidak menerima nomor telepon, catatan, maupun token QR mentah (FR-HM-01).
- Bucket Storage **privat**, tanpa policy list publik; akses file lewat signed URL berumur pendek. Upload dibatasi MIME gambar raster (tanpa SVG) dan ukuran maksimal.
- Validasi semua input dengan skema (Zod/Valibot) di klien dan server (RPC/Edge Function memvalidasi ulang, tidak mempercayai klien).
- Export CSV di-escape terhadap formula injection (FR-G-10). Library XLSX diambil dari distribusi resmi SheetJS.
- Header keamanan di Cloudflare Pages: `Content-Security-Policy` ketat (tanpa `unsafe-eval`, `connect-src` hanya ke domain Supabase project), `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` yang hanya mengizinkan kamera di app usher.

**Audit dan privasi**

- **Audit log** untuk perubahan sensitif (ubah kehadiran, tandai hadir manual, undo check-in, Terapkan/hapus massal Nomor Urut, ubah nomor tiket, ubah akses, cabut perangkat (kedua tingkat), reset PIN, login usher gagal beruntun per (IP + Kode Acara) maupun per event, unggah outbox darurat, setujui/tolak karantina, batas karantina per perangkat terlampaui, tinjauan check-in bermasalah, arsip event).
- Data pribadi tamu (nama, telepon) diperlakukan sesuai **UU PDP**: akses terbatas, kebijakan retensi, penghapusan atas permintaan. Gateway WhatsApp pihak ketiga diperlakukan sebagai pemroses data; pilihan gateway dicatat (Q6).
- HTTPS wajib (kamera, Service Worker, dan Web Crypto membutuhkannya).

### 10.5 Kompatibilitas

- Android Chrome (utama untuk usher), versi terbaru dan 2 mayor sebelumnya.
- iOS Safari didukung untuk scan, cari, check-in; cetak lewat `window.print()`. Web Bluetooth/WebUSB tidak tersedia di iOS.
- Dashboard Admin: desktop dan tablet. Layar Sapa: browser Smart TV/Chromecast/HDMI (target ≥ 42 inci).

---

## 11. Arsitektur & Stack Teknologi

### 11.1 Stack (TypeScript end-to-end)

| Lapisan | Pilihan | Catatan |
|---|---|---|
| Bahasa | **TypeScript** (`strict: true`) | Frontend, PWA, dan Edge Functions |
| Framework web | **SvelteKit** *(usulan; Next.js/Nuxt dimungkinkan)* | Bundle kecil, cocok untuk HP kelas bawah |
| Struktur repo | **Monorepo** (pnpm workspaces): `apps/dashboard`, `apps/usher`, `packages/shared` (skema Zod, tipe DB, aturan nomor tiket) | App usher dan dashboard dibangun dan di-deploy terpisah |
| Mode build app usher | SvelteKit `adapter-static` (SPA murni, tanpa SSR) | Perilaku offline sederhana dan dapat diprediksi |
| PWA / offline | `vite-plugin-pwa` (Workbox) + **Dexie.js** (IndexedDB) | Service Worker, cache aset, outbox |
| Database | **Supabase Postgres** | RLS, RPC, trigger |
| Auth | **Supabase Auth** | Admin: email+password (sign-up publik dimatikan; akun dibuat operator). Usher: Kode Acara + PIN Akses atau QR Login ditukar menjadi sesi lewat Edge Function; klaim di `app_metadata` (lihat 11.5) |
| Realtime | **Supabase Realtime — Broadcast** di channel privat | Sinyal statistik dan sapaan Layar Sapa; Postgres Changes tidak dipakai |
| File | **Supabase Storage** | E-Invitation, background, foto pop-up |
| Logika server | **Supabase Edge Functions** (TS/Deno) | Tukar PIN/QR Login + terbitkan kode perangkat, hapus user Auth perangkat (`device-cleanup`), token Layar Sapa, signed URL `/i/{token}`, antrean WhatsApp |
| Rate limit | Tabel `auth_attempts` di Postgres (cukup untuk skala ini) | Dipakai Edge Function login usher dan `/i/{token}` |
| Antrean/jadwal | `pg_cron` + `pg_net` + tabel antrean (atau `pgmq`) | Pembersihan user Auth perangkat (memanggil `device-cleanup`), Auto Thank You |
| Scan QR | `BarcodeDetector` bila tersedia (Chrome Android); fallback `@zxing/browser` | Di-lazy-load, tidak masuk bundle awal |
| Hash QR di perangkat | Web Crypto `crypto.subtle.digest('SHA-256')` | Tanpa library tambahan |
| Parsing impor | SheetJS dari distribusi resmi (bukan paket `xlsx` lama di registry npm) | Parsing di browser admin |
| Generate QR | `qrcode` (npm) | QR di dashboard dan E-Invitation |
| Render kartu E-Invitation | Web Worker + `OffscreenCanvas` di browser admin | Lihat 11.3 |
| Validasi | Zod atau Valibot | Skema bersama klien dan server |
| Tipe DB | `supabase gen types typescript` | Tipe otomatis |
| Hosting | **Cloudflare Pages** | Frontend statis lewat CDN |
| Region Supabase | Singapura *(Asumsi: terdekat dari Indonesia; cek di dashboard)* | Region sulit diubah setelahnya |
| Testing | Vitest, Playwright (termasuk skenario offline) | |

### 11.2 Diagram Arsitektur

```
 ┌────────────────────┐   ┌────────────────────┐   ┌──────────────┐   ┌──────────────┐
 │ App Penerima Tamu  │   │  Smart Dashboard   │   │  Layar Sapa  │   │ /i/{token}   │
 │ (SPA + IndexedDB)  │   │      (Admin)       │   │  (Smart TV)  │   │ (tamu)       │
 └───┬────────────┬───┘   └─────────┬──────────┘   └──────┬───────┘   └──────┬───────┘
     │ login      │ RPC only        │ PostgREST (RLS)     │ token            │ token
     │ PIN/QR     │ pull_snapshot   │ + upload + RPC      │                  │
     │            │ push_outbox     │                     ▼                  ▼
     │            │                 │            ┌──────────────────────────────────┐
     ▼            │                 │            │  Edge Functions (gerbang publik) │
 ┌──────────────┐ │                 │            │  usher-login · screen-token ·    │
 │ Edge Function│ │                 │            │  invitation-url  (rate limited)  │
 │ usher-login  │ │                 │            │  device-cleanup (admin/pg_cron)  │
 │              │ │                 │            └───────────────┬──────────────────┘
 └──────┬───────┘ │                 │                            │
        ▼         ▼                 ▼                            ▼
 ┌────────────────────────────────────────────────────────────────────────────────┐
 │                                   SUPABASE                                     │
 │ Postgres (RLS, RPC di schema privat, trigger) │ Auth │ Realtime Broadcast       │
 │ Storage (bucket privat, signed URL)           │ pg_cron / antrean pesan         │
 └──────────────────────────────────────┬─────────────────────────────────────────┘
                                        │ antrean pesan
                               ┌────────▼─────────┐
                               │ WhatsAppProvider │
                               └──────────────────┘

 Realtime: trigger DB → Broadcast privat per event
   • channel statistik  → Dashboard (sinyal "berubah", lalu RPC agregat)
   • channel sapaan     → Layar Sapa (payload minimal)
```

### 11.3 Pembuatan E-Invitation Massal (usulan)

1. Admin menekan **Update** → browser admin membuat daftar kartu yang perlu dibuat ulang (berdasarkan hash konfigurasi + data tamu).
2. **Web Worker + OffscreenCanvas** merender kartu (PNG/WebP) dengan konkurensi terbatas (4–6), menyusun QR dari `qr_token`.
3. Hasil diunggah ke bucket privat `invitations` di path `{event_id}/{guest_id}/{config_hash}.png` (path tidak memuat token QR); tabel `invitation_files` mencatat versi dan hash. Proses dapat dilanjutkan bila tab tertutup: kartu yang hash-nya sudah tercatat tidak dirender ulang.
4. UI menampilkan progres; **unduhan baru aktif setelah selesai** (FR-E-03).
5. Self Download banyak file dibuat ZIP di sisi klien; setiap unduhan dicatat di `invitation_downloads`.
6. Pilihan lain bila beban admin terlalu berat: render di server (mis. `satori` + `resvg-wasm`), dengan catatan batas CPU/waktu Edge Function.

### 11.4 Batas Kepercayaan & Jalur Akses

Prinsip: **perangkat usher, QR tamu, dan URL publik dianggap dapat bocor.** Server tidak mempercayai klien mana pun; setiap aktor hanya mendapat jalur sesempit mungkin.

| Aktor | Kredensial | Jalur akses | Tidak boleh |
|---|---|---|---|
| Admin | Email + password (Supabase Auth) | PostgREST dengan RLS berbasis `event_members`, RPC admin, upload Storage, Edge Function `device-cleanup` (putus total) | Mengakses event yang bukan miliknya |
| Usher (per perangkat) | Sesi hasil tukar Kode Acara + PIN Akses atau QR Login; klaim di `app_metadata` | **Hanya** RPC `pull_snapshot` dan `push_outbox` | Membaca/menulis tabel langsung; melihat telepon, catatan, token QR mentah; mengakses event lain atau halaman Admin |
| Layar Sapa | Token URL → JWT pendek dari Edge Function `screen-token` | Mendengarkan satu channel Broadcast sapaan | Membaca tabel apa pun; channel event lain |
| Tamu (`/i/{token}`) | Token QR di URL | Edge Function `invitation-url` → signed URL kartu miliknya | Melihat atau me-list kartu tamu lain |
| Job terjadwal (`pg_cron` + `pg_net`) | Secret khusus job di Supabase Vault (bukan service role key) | Hanya memanggil Edge Function `device-cleanup` (mode pembersihan berkala) | Memanggil fungsi lain; membaca atau mengubah data selain yang dikerjakan `device-cleanup` |
| `anon` (siapa pun yang memegang anon key) | — | Tidak ada akses tabel atau RPC | Semua |

### 11.5 Alur Sesi Usher

1. Saat event dibuat, server membuat **Kode Acara** (tidak rahasia). Admin menambah usher; server membuat **ID usher** 2 karakter (tidak rahasia) dan **rahasia** 8 karakter, menampilkan PIN lengkap `AB-XXXX-XXXX` sekali, lalu hanya menyimpan hash bcrypt dari rahasianya.
2. Untuk login via QR, Admin menekan **Tampilkan QR Login**; server membuat token sekali pakai (yang disimpan hanya hash-nya) dengan masa berlaku 5 menit.
3. App mengirim Kode Acara + PIN, atau token QR, ke Edge Function `usher-login`.
   - **PIN:** fungsi memeriksa blokir per (IP + Kode Acara yang dikirim) (FR-R-09). Usher dicari lewat (Kode Acara, ID usher), lalu dijalankan **tepat satu** bcrypt: terhadap hash usher itu, atau terhadap hash dummy bila Kode Acara/ID usher tidak ditemukan atau usher nonaktif. Semua kegagalan menghasilkan respons yang identik dengan waktu yang diseragamkan. Bila kegagalan per event mencapai ambang, Admin mendapat peringatan tanpa login dikunci.
   - **QR:** token ditandai terpakai secara atomik (hanya bila belum terpakai dan belum kedaluwarsa); tidak ada blokir.
   - Setiap percobaan, berhasil maupun gagal, dicatat di `auth_attempts`.
4. Edge Function mendaftarkan perangkat (`devices`), menerbitkan **kode perangkat**, membuat user Auth khusus perangkat dengan `app_metadata = { role: 'usher', event_id, usher_id, device_id }` (email sintetis dan password acak yang tidak pernah keluar dari Edge Function), lalu mengembalikan sesi. Anonymous sign-in Supabase **tidak diaktifkan**.
5. Setiap pemanggilan `pull_snapshot` dan `push_outbox` memeriksa ulang tabel `devices` dan `events`, karena JWT tetap valid sampai kedaluwarsa:
   - Perangkat sah → layani normal.
   - Dicabut tingkat **Cabut** dan `session_expires_at` belum lewat → `pull_snapshot` membalas `revoked` tanpa data; `push_outbox` menyimpan item sebagai `quarantined` (`device_revoked`).
   - Tidak dicabut, `session_expires_at` sudah lewat, tetapi masih dalam masa tenggang 72 jam → `pull_snapshot` membalas `expired` tanpa data; `push_outbox` menyimpan item sebagai `quarantined` (`session_expired`).
   - Dicabut tingkat **Cabut & putus total**, dicabut (Cabut) setelah `session_expires_at` lewat, masa tenggang habis, atau event diarsipkan → `pull_snapshot` membalas `revoked`/`expired` tanpa data; `push_outbox` ditolak seluruhnya.
   - Batas 500 item karantina per perangkat berlaku untuk kedua alasan karantina.
6. Pencabutan (FR-R-08):
   - **Cabut:** isi `devices.revoked_at` dan `revoke_mode = 'quarantine'`; sesi Auth tetap hidup agar sisa outbox bisa masuk karantina.
   - **Cabut & putus total:** dashboard memanggil Edge Function `device-cleanup` dengan JWT Admin.
     - Fungsi ini lebih dulu mengisi `revoke_mode = 'terminate'` lewat RPC atas nama Admin, sehingga keanggotaan event diperiksa dan audit tercatat.
     - Lalu fungsi menghapus user Auth perangkat dengan `auth.admin.deleteUser`, sehingga refresh token tidak berlaku.
     - Bila penghapusan gagal, status `terminate` sudah berlaku (semua push ditolak), dan job di langkah 7 mengulangi penghapusannya.
     - Access token yang masih tersisa tetap ditolak oleh pemeriksaan langkah 5.
   - App menjalankan FR-HM-09.
7. **Pembersihan otomatis:** `pg_cron` berkala memanggil Edge Function `device-cleanup` lewat `pg_net`, diautentikasi dengan secret khusus job di Supabase Vault (bukan service role key).
   - Fungsi menghapus user Auth (`auth.admin.deleteUser`) untuk perangkat yang (a) bertingkat `terminate` tetapi user-nya belum terhapus, atau (b) sesinya berakhir (`session_expires_at` atau waktu arsip event, mana yang lebih dulu) lebih dari masa tenggang 72 jam.
   - Setelah itu `devices.auth_user_deleted_at` diisi.
   - Penghapusan user Auth tidak pernah dilakukan dengan SQL langsung ke `auth.users`.
   - Baris `devices` dan `check_ins` tetap tersimpan untuk audit.

---

## 12. Model Data

### 12.1 Tabel Utama

| Tabel | Kolom penting |
|---|---|
| `events` | id, **code** (Kode Acara, 6 karakter, unik, tidak rahasia), name, couple_names, event_date, **timezone** (default `Asia/Jakarta`), venue, **attendance_limit** (batas jumlah hadir, nullable), settings (jsonb), **archived_at**, created_by |
| `event_members` | event_id, user_id, role (`admin`) |
| `ushers` | id, event_id, name, mode (`check_in` / `check_out`), **pin_selector** (ID usher 2 karakter; unik per event, termasuk usher yang sudah dihapus; tidak rahasia), pin_hash (bcrypt dari 8 karakter rahasia saja), is_active, deleted_at |
| `usher_login_tokens` | id, usher_id, token_hash, expires_at, used_at, created_by |
| `checkin_settings` | event_id, show_verification, allow_multi_checkin, print_ticket (jsonb: info, kategori, salinan), print_entrusted_gift (jsonb) |
| `guest_groups` | id, event_id, name, description, updated_at, **deleted_at** (tombstone untuk delta sync) |
| `guests` | id, event_id, name, phone, category (`regular` / `vip` / `vvip`), group_id, invited_pax, **special_number** (Nomor Urut khusus VIP/VVIP, nullable, unik per event, `CHECK` tidak cocok pola nomor perangkat), **qr_token** (unique; tidak pernah dikirim ke perangkat usher), **qr_token_hash** (generated column SHA-256 hex), rsvp_status, rsvp_pax, attendance_status, is_additional, created_device_id (asal tamu tambahan, nullable), notes, **updated_at**, **deleted_at** (tombstone) |
| `check_ins` | **id (UUID dari klien = kunci idempotensi)**, event_id, guest_id (null hanya selama `quarantined` dengan tamu baru), **pending_guest** (jsonb: data tamu tambahan yang menunggu persetujuan karantina), actual_pax, ticket_number (snapshot nomor yang dicetak; null hanya untuk check-in manual Admin), **status** (`accepted` / `repeat` / `duplicate` / `conflict` / `quarantined`, ditentukan server), **quarantine_reason** (`device_revoked` / `session_expired`; tetap terisi setelah diputuskan sebagai jejak asal), **source** (`device` / `admin` / `outbox_upload`), device_id, usher_id, created_by, checked_in_at (jam perangkat), **received_at** (jam server), checked_out_at, voided_at, void_reason, reviewed_at, reviewed_by, **updated_at**. Tidak ada kolom hadiah di tabel ini; relasinya ada di `gifts.check_in_id` (D16) |
| `gifts` | id, event_id, check_in_id (nullable; satu-satunya relasi hadiah ↔ check-in), guest_id (nullable), kind (`envelope` / `present` / `transfer`), is_entrusted, giver_name, gift_code, usher_id, created_at |
| `ticket_number_settings` | event_id, category (`vip` / `vvip`), prefix, start_number, digits |
| `devices` | id, event_id, usher_id, **code** (kode perangkat, mis. `A`; unik per event), auth_user_id, name, app_version, last_seen_at, clock_offset_ms, session_expires_at, revoked_at, revoked_by, **revoke_mode** (`quarantine` = Cabut / `terminate` = Cabut & putus total), auth_user_deleted_at |
| `screen_tokens` | id, event_id, token_hash, expires_at, revoked_at |
| `auth_attempts` | id, kind (`usher_login` / `invitation_url` / `screen_token`), method (`pin` / `qr`, untuk `usher_login`), ip, **event_code** (Kode Acara yang dikirim, dinormalisasi; bagian dari kunci blokir), event_id, usher_id, success, reason, created_at |
| `greeting_configs` | event_id, category, popup (jsonb: teks, foto, tampilan), screen (jsonb: layout, warna) |
| `invitation_designs` | event_id, fields (jsonb: teks atas, judul, teks bawah, deskripsi, sapaan, himbauan), background_path, colors, font, show_general_qr, show_link, config_hash, updated_at |
| `invitation_files` | event_id, guest_id (nullable untuk QR umum), storage_path, config_hash, generated_at |
| `invitation_downloads` | id, event_id, scope, actor_id, created_at |
| `message_templates` | event_id, kind (`thank_you`), body, is_enabled |
| `message_queue` | id, event_id, guest_id, body, status, attempts, scheduled_at, sent_at, error |
| `audit_logs` | id, event_id, actor_id, action, entity, entity_id, before, after, created_at |

### 12.2 Tipe Inti (TypeScript)

```ts
export type Category = 'regular' | 'vip' | 'vvip';
export type RsvpStatus = 'going' | 'not_going' | 'unconfirmed';
export type AttendanceStatus = 'not_arrived' | 'checked_in' | 'checked_out';
export type UsherMode = 'check_in' | 'check_out';
export type GiftKind = 'envelope' | 'present' | 'transfer';

export interface Guest {
  id: string;
  eventId: string;
  name: string;
  phone: string | null;
  category: Category;
  groupId: string | null;
  invitedPax: number;
  specialNumber: string | null; // Nomor Urut khusus VIP/VVIP
  qrToken: string;
  rsvpStatus: RsvpStatus;
  rsvpPax: number | null;
  attendanceStatus: AttendanceStatus;
  isAdditional: boolean;
  notes: string | null;
}

export type CheckInStatus = 'accepted' | 'repeat' | 'duplicate' | 'conflict' | 'quarantined';

/**
 * Ringkasan check-in aktif tamu untuk perangkat usher. Dipilih: check-in `accepted` yang tidak
 * dibatalkan; bila tidak ada, check-in terbaru yang tidak dibatalkan dan bukan `quarantined`.
 */
export interface GuestCheckInSummary {
  status: Exclude<CheckInStatus, 'quarantined'>;
  ticketNumber: string | null; // null hanya untuk tandai hadir manual oleh Admin
  checkedInAt: string;         // ISO 8601, jam perangkat saat check-in
  usherName: string | null;    // null bila ditandai hadir manual oleh Admin
}

/** Data tamu yang dikirim ke perangkat usher. Tanpa telepon, catatan, dan token QR mentah. */
export interface GuestSnapshot {
  id: string;
  name: string;
  category: Category;
  groupId: string | null;
  invitedPax: number;
  specialNumber: string | null;
  qrTokenHash: string;   // SHA-256 hex dari qr_token
  rsvpStatus: RsvpStatus;
  rsvpPax: number | null;
  attendanceStatus: AttendanceStatus;
  isAdditional: boolean;
  checkIn: GuestCheckInSummary | null; // FR-RA-04, FR-C-08
  updatedAt: string;     // kursor delta sync; ikut berubah saat check-in tamu berubah
  deletedAt: string | null; // tombstone
}

export interface CheckInOutboxItem {
  id: string;            // UUID dari klien, kunci idempotensi
  guestId: string | null;
  newGuest?: Pick<Guest, 'name' | 'phone' | 'category' | 'invitedPax' | 'notes'>;
  actualPax: number;
  gift?: { kind: GiftKind; code: string }; // diterima mulai fase Hadiah (P1); sebelumnya item dibalas galat
  ticketNumber: string;  // specialNumber tamu, atau `${kodePerangkat}-${urut}` dari perangkat
  deviceId: string;
  checkedInAt: string;   // ISO 8601, jam perangkat
  syncStatus: 'pending' | 'synced' | 'failed';
  serverStatus?: CheckInStatus; // diisi dari hasil push_outbox
}

/** Hasil per item dari push_outbox. `error` = tidak lolos validasi, tidak disimpan, tetap di outbox perangkat. */
export type PushItemResult =
  | { id: string; outcome: 'stored'; status: CheckInStatus; guestId: string | null; ticketNumber: string; receivedAt: string }
  | { id: string; outcome: 'error'; code: string };

/**
 * Respons push_outbox. `revoked` (dicabut tingkat Cabut) dan `expired` (sesi habis wajar, masih dalam
 * masa tenggang): item valid disimpan sebagai `quarantined`.
 */
export type PushResponse =
  | { status: 'ok' | 'revoked' | 'expired'; results: PushItemResult[] }
  | { status: 'rejected'; reason: 'terminated' | 'quarantine_window_closed' | 'event_archived' | 'mode_mismatch'; results: [] };

/** Pola yang dicadangkan untuk nomor otomatis; special_number tidak boleh cocok. */
export const DEVICE_TICKET_PATTERN = /^[A-Z]{1,2}-\d+$/;
export const GIFT_CODE_PATTERN = /^[A-Z]{1,2}-H\d+$/;
```

### 12.3 Desain Sinkronisasi & Nomor Tiket

1. **Idempotensi:** setiap check-in membawa `id` UUID dari klien; server memakai `INSERT ... ON CONFLICT (id) DO NOTHING`, sehingga retry aman. Item yang sudah ada mengembalikan status yang tersimpan.
2. **Sumber nomor tiket:** (a) `special_number` milik tamu bila ada. Ini data statis yang sudah diunduh ke perangkat, jadi aman offline dan bebas balapan. (b) Bila tidak ada, nomor otomatis `{KodePerangkat}-{urut}`. Kedua ruang nama tidak dapat bertabrakan karena `special_number` dilarang memakai pola nomor perangkat (FR-C-02, constraint DB).
3. **Kode perangkat:** diterbitkan server saat usher login di perangkat baru (`A`, `B`, … `Z`, `AA`, …), unik per event. Jika penyimpanan browser terhapus, login ulang menerbitkan **kode baru**, sehingga counter yang mulai dari 001 tidak bertabrakan dengan nomor lama. Login pertama wajib online.
4. **Counter lokal:** disimpan di IndexedDB dan dinaikkan **dalam transaksi yang sama** dengan penulisan outbox, sehingga tidak ada nomor dobel atau terlewat karena crash/refresh.
5. **Sinkronisasi:** RPC `push_outbox` menerima array check-in dan mengembalikan `PushResponse` beserta hasil per item (`PushItemResult`).

   **Push ditolak seluruhnya** (`status: 'rejected'`, tidak ada item yang disimpan) bila:
   - perangkat dicabut dengan tingkat **Cabut & putus total** (`terminated`);
   - perangkat dicabut (Cabut) dan `session_expires_at` sudah lewat, atau perangkat tidak dicabut tetapi masa tenggang 72 jam setelah `session_expires_at` sudah habis (`quarantine_window_closed`);
   - event diarsipkan (`event_archived`);
   - usher bermode Check-Out (`mode_mismatch`).

   Perangkat mempertahankan outbox-nya untuk diekspor (FR-HM-08, FR-HM-09).

   Selain itu, semua item yang valid **selalu disimpan** (tidak ada data yang dibuang), dan server menetapkan `status`:
   - `quarantined` — dievaluasi **lebih dulu**, untuk dua kasus:
     - perangkat dicabut dengan tingkat **Cabut** (FR-R-08) dan `session_expires_at` belum lewat → `quarantine_reason = 'device_revoked'`, respons top-level `status: 'revoked'`;
     - perangkat **tidak** dicabut, `session_expires_at` sudah lewat, dan masih dalam masa tenggang (FR-R-10) → `quarantine_reason = 'session_expired'`, respons top-level `status: 'expired'`.
     - Disimpan apa adanya beserta `quarantine_reason`.
     - **Tidak dihitung** di statistik maupun kehadiran, tidak tercakup unique index, dan tidak membuat tamu tambahan (data `newGuest` disimpan di `pending_guest`).
     - Maksimal 500 item karantina per perangkat (konfigurasi). Item berikutnya dibalas galat `quarantine_limit` dan memicu peringatan di dashboard.
     - Admin **menyetujui** (status dievaluasi ulang dengan aturan di bawah pada saat persetujuan, dan tamu tambahan baru dibuat saat itu) atau **menolak** (alasan wajib; baris tetap tersimpan sebagai dibatalkan).
     - Jam perangkat tidak dipakai sebagai bukti apa pun. Lihat FR-RW-05.
   - `accepted` — check-in pertama yang sah untuk tamu tersebut.
   - `repeat` — tamu sudah punya check-in `accepted` dan **Tamu Check-In Lebih 1 Kali** aktif. Tidak dihitung ganda di statistik tamu undangan dan **tidak menambah jumlah orang hadir** (D11). Bila tamu memang membawa orang tambahan, jumlahnya dikoreksi lewat Ubah Detail Kehadiran pada check-in `accepted`.
   - `duplicate` — tamu sudah punya check-in `accepted` dan check-in ulang **tidak** diizinkan. Ditandai untuk ditinjau Admin di Riwayat.
   - `conflict` — `ticket_number` sudah dipakai check-in `accepted` lain (jaring pengaman terakhir). Ditandai untuk ditinjau Admin.

   Item yang **tidak lolos validasi** (mis. tamu milik event lain, `deviceId` tidak sama dengan perangkat pemanggil, nomor otomatis dengan kode perangkat lain, atau membawa `gift` sebelum fase Hadiah) tidak dapat disimpan. Server membalas `outcome: 'error'` beserta kodenya, dan perangkat mempertahankan item itu di outbox sebagai `failed` sehingga tetap bisa diekspor (FR-HM-08). Check-in untuk tamu yang sudah dihapus Admin tetap disimpan dengan aturan biasa dan diberi penanda di Riwayat.
6. **Unique index** `(event_id, ticket_number)` hanya berlaku untuk baris `status = 'accepted'` dan `voided_at IS NULL`. Check-in `repeat` dengan nomor khusus yang sama (mis. VVIP-007 masuk dua kali) tidak pernah melanggar index.
7. **Tamu yang sama di dua perangkat offline:** check-in yang diterima server lebih dulu menjadi `accepted`; yang kedua menjadi `repeat` atau `duplicate` sesuai pengaturan. Hasilnya dikirim balik ke perangkat dan tampil di Riwayat.
8. **Delta sync:** `pull_snapshot` menerima kursor `updated_at` terakhir dan mengembalikan baris yang berubah, termasuk tombstone (`deleted_at`). Perangkat menghapus tamu bertombstone dari data lokal. Kursor memakai jam server, bukan jam perangkat.
9. **Jam:** `checked_in_at` dari perangkat dipakai untuk tampilan; urutan resmi dan audit memakai `received_at` dari server. Selisih jam perangkat dicatat di `devices.clock_offset_ms`.
10. **Durabilitas lokal:** `navigator.storage.persist()` saat login; logout diblokir selama outbox belum kosong; ekspor outbox darurat (FR-HM-07, FR-HM-08).
11. **Trade-off yang diterima:** nomor otomatis berurutan **per perangkat**, bukan menurut urutan kedatangan global. Nomor tetap unik dan cukup untuk mengarahkan pengambilan souvenir. Bila kelak dibutuhkan urutan global, alokasi blok nomor dari server dapat ditambahkan tanpa mengubah format data.
12. **Kode hadiah:** memakai pola yang sama dengan kode perangkat dengan counter hadiah terpisah (mis. `A-H012`), sehingga unik dan dapat dibuat offline.
13. **Batas yang diterima:** QR yang diteruskan (screenshot) dapat dipakai dua orang berbeda di dua perangkat yang sama-sama offline; hal ini baru terdeteksi setelah sync. Pertahanan di lokasi adalah langkah Verifikasi (nama, kategori, pax), yang selalu aktif untuk VIP/VVIP (D9).
14. **Unggahan Admin:** file ekspor outbox darurat (FR-HM-08) yang diunggah Admin yang sudah login diproses dengan aturan 5–7 secara normal, **tidak dikarantina**, meskipun perangkat asalnya sudah dicabut. `source = 'outbox_upload'`; `received_at` = waktu unggah.
15. **Check-in manual Admin** (FR-A-02): baris `check_ins` dengan `source = 'admin'`, tanpa perangkat, status ditetapkan server dengan aturan 5–7 yang sama, dan dicatat di audit log.
    - `ticket_number` = `special_number` tamu bila ada; bila tidak ada, `null` (tidak ada tiket yang dicetak). `null` hanya diizinkan untuk `source = 'admin'` (constraint DB).
    - `null` tidak pernah dianggap bentrok: unique index memperlakukan `null` sebagai berbeda, dan pemeriksaan `conflict` hanya berjalan bila `ticket_number` terisi.
    - Statistik tidak bergantung pada `ticket_number`.
    - Di `GuestSnapshot.checkIn`, `ticketNumber` dan `usherName` bernilai `null`. Perangkat yang meng-check-in ulang tamu itu memakai aturan nomor biasa (poin 2).
16. **Hadiah (fase P1):** relasi hadiah ke check-in disimpan di `gifts.check_in_id`. Menambahkan fitur Hadiah tidak mengubah tabel `check_ins` maupun kunci idempotensinya; item yang dulu dibalas galat karena membawa `gift` dapat dikirim ulang dengan `id` yang sama.
17. **Snapshot dan check-in:** setiap perubahan check-in memperbarui `guests.updated_at`, sehingga ringkasan `checkIn` di `GuestSnapshot` ikut terkirim lewat delta sync tanpa tombstone terpisah untuk check-in.

### 12.4 Indeks yang Diperlukan

- `guests (event_id, qr_token)` — unique
- `guests (event_id, qr_token_hash)` — unique
- `guests (event_id, updated_at)` — kursor delta sync
- `guests (event_id, category, attendance_status)`
- `guests (event_id, group_id)`
- `guests (event_id, rsvp_status)`
- `guests (event_id, special_number)` — unique (parsial, hanya bila nomor tidak null dan `deleted_at` null)
- `check_ins (event_id, checked_in_at desc)`, `check_ins (event_id, guest_id)`, dan `check_ins (event_id, updated_at)`
- `check_ins (event_id, ticket_number)` — unique (parsial, hanya bila `status = 'accepted'` dan `voided_at` null)
- `check_ins (event_id, guest_id)` — unique (parsial, syarat sama): jaring pengaman "satu `accepted` aktif per tamu"
- `check_ins (event_id, status)` — parsial untuk `duplicate` / `conflict` / `quarantined` (daftar tinjauan)
- `events (code)` — unique
- `gifts (event_id, gift_code)` — unique
- `devices (event_id, code)` — unique
- `usher_login_tokens (token_hash)` — unique
- `screen_tokens (token_hash)` — unique
- `auth_attempts (kind, ip, event_code, created_at desc)` (blokir per IP + Kode Acara), `auth_attempts (kind, ip, created_at desc)` (blokir global per IP), dan `auth_attempts (kind, event_id, created_at desc)` (peringatan per event)
- `ushers (event_id, pin_selector)` — unique (termasuk usher yang sudah dihapus)
- `devices (session_expires_at)` — parsial, hanya bila `auth_user_deleted_at` null (job pembersihan)

---

## 13. Rencana Rilis

| Milestone | Isi | Hasil |
|---|---|---|
| **M0 — Fondasi** | Monorepo TypeScript, CI, project Supabase, skema + RLS, auth admin, **baseline keamanan** (revoke hak `anon`, schema privat untuk `SECURITY DEFINER`, header keamanan Cloudflare Pages), **tes RLS otomatis di CI** | Login admin, skema stabil, tes akses lulus |
| **M1 — Admin inti** | Kelola Tamu (manual, impor + Tinjau Tamu, grup, edit massal), kategori + Nomor Urut VIP/VVIP (setting + Terapkan Nomor Urut), QR, detail kehadiran | Admin dapat menyiapkan event |
| **M2 — Usher & App** | Tambah usher (Kode Acara + PIN Akses *selector + verifier*, QR Login sekali pakai, blokir per (IP + Kode Acara) + peringatan per event, kode perangkat, pencabutan dua tingkat + karantina + pembersihan otomatis), RPC `pull_snapshot`/`push_outbox`, pengaturan check-in, App: scan (hash lokal), cari, tambah, verifikasi, tiket (RawBT), pop-up sapaan, Hybrid Mode (persist, penjaga logout, ekspor outbox, tombstone) | Check-in lengkap online/offline |
| **M3 — Statistik & Riwayat** | Statistik P0, Realtime Broadcast + RPC agregat, Riwayat tab, penanda RSVP vs aktual, tinjauan `duplicate`/`conflict`, persetujuan karantina, undo | Pemantauan hari H |
| **M4 — E-Invitation** | Editor kartu, render massal, Storage (bucket privat + signed URL), halaman `/i/{token}`, Self Download, QR Umum | Kartu undangan siap dibagikan |
| **M5 — Pelengkap** | Hadiah (hadir + titipan), Layar Sapa, Auto Thank You, mode Check-Out | Fitur P1 lengkap |
| **M6 — Hardening** | Uji beban, uji offline, uji printer nyata, audit RLS, **uji keamanan** (akses langsung dengan JWT usher, akses `anon`, brute force PIN, reuse QR Login, dump IndexedDB, CSV injection, list bucket), UAT di event percobaan | Siap produksi |

## 14. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Kompatibilitas printer thermal beragam | Tiket gagal cetak | Uji model printer target sejak M2; RawBT sebagai jalur utama Android, `window.print()` sebagai cadangan |
| Konflik/duplikasi saat offline | Nomor/data ganda | Idempotensi, kode perangkat unik, unique index nomor tiket, tinjauan duplikat oleh Admin |
| Pembuatan E-Invitation massal lambat/gagal | Admin menunggu lama | Worker + konkurensi terbatas, progres, hash agar hanya yang berubah dibuat ulang |
| Web Bluetooth tidak ada di iOS | Cetak langsung tidak tersedia | `window.print()` di iOS (target G1 tidak berlaku untuk iOS); ESC/POS hanya P2 |
| Gateway WhatsApp tidak resmi diblokir | Pesan gagal | Abstraksi provider; opsi Cloud API resmi |
| Supabase gratis ter-pause / tanpa backup | Sistem mati saat acara | Plan berbayar untuk event nyata; export manual sebelum hari H |
| Kamera butuh izin dan HTTPS | Scan tidak berfungsi | Panduan setup perangkat; cek izin saat login usher |
| Kebocoran data tamu | Risiko privasi dan hukum | RLS ketat, usher hanya lewat RPC, `anon` tanpa akses, audit log, retensi dan penghapusan data |
| HP usher hilang, dipinjam, atau dipakai ulang untuk event lain | Data tamu dan QR bocor; check-in palsu | Snapshot minimal tanpa telepon; QR disimpan sebagai hash; **Cabut & putus total** (user Auth dihapus lewat `device-cleanup`, semua push ditolak) + hapus data lokal; sesi berakhir H+1 |
| PIN Akses dibagikan di grup kru atau di-brute-force; QR Login di-screenshot | Orang luar masuk sebagai usher | Rahasia PIN 8 karakter + blokir per (IP + Kode Acara) + peringatan per event; QR Login sekali pakai 5 menit; daftar perangkat dan pencabutan |
| Penyerang membanjiri login dengan PIN salah agar server menjalankan banyak bcrypt | Server lambat (DoS) | Pola *selector + verifier*: tepat satu bcrypt per percobaan, termasuk saat usher tidak ditemukan; blokir per (IP + Kode Acara); blokir global per IP (50 gagal per 15 menit) untuk serangan yang mengganti-ganti Kode Acara palsu; pemeriksaan blokir sebelum bcrypt |
| Penyerang yang mengetahui Kode Acara sengaja salah PIN berulang kali | Semua usher terkunci di hari H | Tidak ada kunci per event (hanya peringatan); blokir per (IP + Kode Acara), sehingga penyerang dari jaringan lain tidak memengaruhi lokasi; QR Login tidak terkena blokir. **Sisa risiko:** penyerang yang berada di Wi-Fi lokasi yang sama dapat memblokir login PIN acara itu selama 15 menit; usher memakai QR Login |
| Satu IP publik dipakai bersama oleh semua perangkat di Wi-Fi lokasi | Salah ketik PIN beberapa usher acara yang sama memblokir login PIN acara itu di lokasi tersebut | Kunci (IP + Kode Acara) dengan ambang 10, sehingga acara lain di jaringan yang sama tidak ikut terblokir; QR Login sebagai jalur cadangan; dashboard menampilkan status blokir dan sisa waktunya |
| Perangkat yang dicabut (tingkat Cabut) terus mengirim data | Riwayat dipenuhi data palsu | Semua masuk karantina dan tidak dihitung; maksimal 500 item per perangkat, lalu peringatan; jendela berakhir di `session_expires_at`; tolak massal per perangkat; naikkan ke Cabut & putus total; user Auth perangkat dihapus otomatis oleh job terjadwal |
| QR undangan diteruskan/di-screenshot ke orang lain | Orang tak diundang masuk; kursi/souvenir terpakai | Verifikasi selalu aktif untuk VIP/VVIP; peringatan check-in ganda; tinjauan `duplicate` setelah sync. Tidak dapat dicegah sepenuhnya saat dua perangkat offline (diterima) |
| Usher menghapus data browser atau logout saat app macet | Check-in belum tersinkron hilang | `storage.persist()`, logout diblokir saat outbox berisi, ekspor outbox darurat, panduan "jangan clear data" di briefing usher |
| Nomor khusus yang diisi admin/impor menabrak nomor otomatis | Nomor tiket ganda | Pola nomor perangkat dicadangkan; validasi klien, Tinjau Tamu, dan constraint DB |
| Formula injection pada file export | Perintah berbahaya jalan di Excel admin | Escape sel export (FR-G-10) |
| Salah konfigurasi RLS/Storage/fungsi `SECURITY DEFINER` | Kebocoran seluruh data event | Tes RLS otomatis di CI, revoke default, schema privat, uji keamanan di M6 |
| Jaringan venue buruk | Sinkronisasi tertunda | Hybrid Mode default, indikator antrean, sinkron otomatis |
| Fitur meniru produk lain | Risiko IP | Hanya mengacu alur/pola UX; teks, aset, branding dibuat sendiri |

## 15. Keputusan & Pertanyaan Terbuka

### 15.1 Keputusan yang sudah diambil

| # | Keputusan | Alasan |
|---|---|---|
| D1 | **Selfie Check-In ditunda** ke iterasi berikutnya | Belum dikembangkan sekarang; menghindari beban privasi (foto tamu) dan Storage privat di MVP |
| D2 | **Nomor Urut VIP/VVIP memakai pendekatan hybrid:** nomor khusus yang ditetapkan admin (dengan *Terapkan Nomor Urut*) + nomor tiket otomatis berbasis kode perangkat untuk tamu lainnya | Sesuai perilaku referensi untuk VIP/VVIP; nomor khusus bersifat statis sehingga aman offline dan tanpa koordinasi server; tamu lain tetap mendapat nomor unik untuk arahan souvenir; paling sederhana dan paling cepat |
| D3 | Table Management, Souvenir Management, Doorprize, dan WO Tracking tidak dikerjakan | Keputusan lingkup dari pemilik produk |
| D4 | Istilah **"Passkey" diganti "PIN Akses"**; QR Login sekali pakai 5 menit | "Passkey" berarti WebAuthn dan dapat menyesatkan implementasi; PIN bersama dan QR statis mudah bocor |
| D5 | **Usher hanya lewat RPC** (`pull_snapshot`, `push_outbox`); klaim hanya dari `app_metadata`/tabel server | Mencegah usher (atau siapa pun yang memegang JWT-nya) mengubah data langsung lewat PostgREST |
| D6 | **Snapshot perangkat minimal**: tanpa telepon, QR sebagai hash SHA-256 | HP usher dianggap dapat hilang/dibongkar; dump data lokal tidak boleh bisa dipakai memalsukan QR atau mengambil nomor telepon |
| D7 | **Realtime memakai Broadcast privat**; akses publik hanya lewat Edge Function | Postgres Changes untuk Layar Sapa tanpa login menuntut akses baca `anon` ke tabel check-in |
| D8 | **Status check-in ditentukan server** (`accepted`/`repeat`/`duplicate`/`conflict`); unique index nomor tiket hanya untuk `accepted`; pola nomor perangkat dicadangkan | Menutup kontradiksi antara "Check-In Lebih 1 Kali" dan unique index, serta tabrakan nomor khusus vs nomor otomatis |
| D9 | **Verifikasi selalu aktif untuk VIP/VVIP**; toggle hanya untuk Regular | QR yang diteruskan tidak dapat dicegah secara teknis saat offline; verifikasi oleh usher adalah satu-satunya pertahanan di lokasi untuk tamu yang paling penting |
| D10 | **RawBT jalur cetak utama di Android**; `window.print()` cadangan | Dialog cetak `window.print()` membuat target G1 tidak tercapai |
| D11 | **Check-in `repeat` tidak menambah jumlah orang hadir.** Koreksi jumlah dilakukan Admin atau usher lewat Ubah Detail Kehadiran pada check-in `accepted` (menjawab Q10) | Check-in ulang umumnya orang yang sama keluar lalu masuk lagi; menambah pax akan menggelembungkan statistik |
| D12 | **Login usher = Kode Acara + PIN Akses berpola *selector + verifier*.** PIN `AB-XXXX-XXXX` terdiri dari ID usher untuk lookup dan rahasia 8 karakter. Tepat satu bcrypt per percobaan; respons gagal identik berkat bcrypt dummy. Blokir per (IP + Kode Acara), 10 gagal per 15 menit, ditambah blokir global per IP, 50 gagal per 15 menit; per event hanya peringatan; QR Login tidak terkena blokir | Mencocokkan bcrypt ke semua usher menjadi penguat DoS yang biayanya naik seiring jumlah usher. Kunci gabungan mencegah satu IP lokasi memblokir acara lain. Kunci per event akan memberi penyerang cara mudah mengunci semua usher di hari H |
| D13 | **Status `quarantined` dan dua tingkat pencabutan.** **Cabut**: hanya push; semua item dikarantina sampai `session_expires_at`, maksimal 500 per perangkat. **Cabut & putus total**: user Auth dihapus dan semua push ditolak. **Sesi habis wajar**: dikarantina selama masa tenggang 72 jam. **Event diarsipkan**: push ditolak. Unggahan outbox darurat oleh Admin diproses normal. User Auth perangkat dihapus lewat Edge Function `device-cleanup` (langsung saat putus total, berkala lewat `pg_cron` + `pg_net`), tidak pernah lewat SQL ke `auth.users` | Data tidak dibuang dan juga tidak diterima begitu saja; jam perangkat dapat dipalsukan sehingga keputusan ada di tangan Admin; HP usher yang offline semalaman bukan perangkat mencurigakan; HP yang hilang atau dicuri harus bisa diputus total; penghapusan user Auth lewat SQL tidak didukung resmi |
| D14 | **Batas jumlah hadir** opsional per event; bila kosong, Σ `invited_pax` tamu undangan | Batas eksplisit untuk kapasitas venue, dengan nilai bawaan yang masuk akal |
| D15 | **Label UI Bahasa Indonesia**; enum DB/kode bahasa Inggris | Konsisten dengan prinsip 3.2 tanpa mengubah kontrak data |
| D16 | **Hadiah Titipan, kode hadiah di tiket, dan field `gift` ikut fase Hadiah (P1)**, tanpa stub. Relasi di `gifts.check_in_id` | `check_ins` dan kunci idempotensinya tidak perlu diubah saat fitur Hadiah ditambahkan |
| D17 | **"Salin link" QR aktif di M4**; format URL `/i/{token}` dikunci sekarang di konfigurasi bersama | Tidak ada link yang mengarah ke halaman yang belum ada, tetapi formatnya stabil sejak awal |

**Alternatif untuk D2 yang dipertimbangkan:** (a) counter atomik global di server — butuh jaringan sehingga tidak jalan saat offline dan menambah latensi di pintu masuk; (b) blok nomor per perangkat — lebih kompleks (lease, blok habis, rekonsiliasi) dengan manfaat yang kecil; (c) hanya nomor manual — tamu Regular dan tamu tambahan tidak akan mendapat nomor untuk arahan souvenir.

### 15.2 Pertanyaan terbuka

| # | Pertanyaan | Dampak |
|---|---|---|
| Q1 | Perkiraan jumlah tamu per event dan jumlah perangkat serentak? | Plan Supabase dan target performa |
| Q2 | Karena Undangan Website tidak dibuat: dari mana status **RSVP** berasal (isi manual admin, impor, atau kelak ada halaman RSVP)? | Cakupan RSVP dan statistik |
| Q3 | Format E-Invitation: PNG saja atau juga PDF? Ukuran/rasio kartu? | Renderer dan Storage |
| Q4 | Apakah perlu **sesi acara** (mis. akad dan resepsi terpisah)? | Skema tamu, statistik |
| Q5 | Model printer thermal target (merek, 58/80 mm, USB/Bluetooth)? | Jalur cetak |
| Q6 | Gateway WhatsApp (tidak resmi atau Cloud API resmi)? | FR-M-04 dan biaya |
| Q7 | Kebijakan retensi data tamu setelah acara? | Kepatuhan UU PDP |
| Q8 | Perangkat usher milik siapa (tim sendiri, kru WO, atau pinjaman)? | Seberapa ketat pencabutan, masa sesi, dan briefing keamanan perangkat |
| Q9 | Apakah D9 (Verifikasi wajib VIP/VVIP) dapat diterima secara operasional, termasuk dampaknya pada kecepatan antrean? | Alur check-in VIP/VVIP dan target G1 |
| Q10 | ~~Untuk check-in `repeat`, apakah `actual_pax` ditambahkan ke total hadir atau menggantikan nilai sebelumnya?~~ **Terjawab (D11):** tidak ditambahkan; koreksi lewat Ubah Detail Kehadiran pada check-in `accepted` | Akurasi statistik kehadiran |
| Q11 | Bagaimana perangkat usher mengambil foto pop-up sapaan dari bucket privat, mengingat usher tidak boleh mengakses tabel/Storage secara langsung? Usulan: Edge Function `usher-asset` yang memeriksa perangkat lalu memberi signed URL berumur pendek | Ditetapkan bersama App Penerima Tamu |

## 16. Kriteria Penerimaan MVP

- [ ] Admin dapat mengimpor 1.000 tamu, meninjau hasil di halaman Tinjau Tamu, lalu memprosesnya; QR terbentuk untuk semua tamu.
- [ ] Admin dapat menambah usher mode Check-In dan usher masuk ke app lewat PIN Akses maupun Scan QR Login.
- [ ] Usher dapat check-in lewat scan, cari nama, dan tambah tamu; tiket tercetak; pop-up sapaan tampil sesuai kategori.
- [ ] Pengaturan Verifikasi, Print Tiket, dan Check-In Lebih 1 Kali di dashboard langsung berlaku di app.
- [ ] Saat internet dimatikan, 100 check-in berurutan berhasil dan seluruhnya tersinkron setelah internet kembali, tanpa data hilang atau ganda.
- [ ] Uji multi-perangkat (≥ 5), termasuk skenario offline dan penyimpanan perangkat terhapus lalu login ulang, menghasilkan 0 nomor tiket ganda per event.
- [ ] Statistik dashboard terbarui ≤ 3 detik setelah check-in saat online, dan peringatan overcapacity muncul saat jumlah hadir melebihi batas.
- [ ] Riwayat menampilkan tab Check-In/Check-Out/All dan penanda RSVP vs kehadiran aktual.
- [ ] Usher tidak dapat mengakses data event lain atau halaman Admin (diuji lewat skenario RLS).
- [ ] Scan → tiket mulai tercetak ≤ 3 detik (p95) di HP Android kelas menengah.
- [ ] Admin dapat menjalankan **Terapkan Nomor Urut** untuk VIP/VVIP dengan pratinjau; nomor ganda ditolak; nomor khusus tercetak di tiket walau check-in dilakukan offline.
- [ ] Semua perubahan sensitif tercatat di audit log.

**Keamanan & keandalan (v0.4)**

- [ ] Dengan JWT usher yang sah, request langsung ke PostgREST (SELECT/INSERT/UPDATE/DELETE ke tabel mana pun) ditolak; hanya `pull_snapshot` dan `push_outbox` yang berhasil.
- [ ] Dengan anon key saja, tidak ada tabel, RPC, maupun channel Realtime yang dapat dibaca.
- [ ] Mengubah `user_metadata` dari klien tidak mengubah hak akses apa pun.
- [ ] Dump IndexedDB perangkat usher tidak memuat nomor telepon, catatan, maupun token QR mentah.
- [ ] QR Login yang sudah dipakai atau lewat 5 menit ditolak. Sepuluh PIN salah dari satu (IP + Kode Acara) dalam 15 menit memblokir login PIN untuk kunci itu tanpa memengaruhi Kode Acara lain dari IP yang sama. Lima puluh PIN salah dari satu IP dengan Kode Acara yang berganti-ganti memblokir login PIN dari IP itu, tanpa ada bcrypt yang dijalankan untuk percobaan yang diblokir. Dua puluh kegagalan per event memunculkan peringatan tanpa mengunci login. QR Login tetap berfungsi saat PIN diblokir. Respons gagal identik untuk Kode Acara, ID usher, maupun rahasia yang salah, dan setiap percobaan menjalankan tepat satu bcrypt (FR-R-02, FR-R-09).
- [ ] Perangkat yang dicabut tidak lagi menerima data apa pun. Pada tingkat **Cabut**, outbox yang dikirimnya tersimpan sebagai `quarantined` (maksimal 500 item, sampai `session_expires_at`), tidak dihitung di statistik, dan dapat disetujui atau ditolak Admin dengan jejak di audit log. Pada tingkat **Cabut & putus total**, user Auth perangkat langsung dihapus lewat `device-cleanup` dan semua push ditolak. User Auth perangkat lainnya terhapus otomatis setelah masa tenggang.
- [ ] Perangkat yang sesinya habis wajar (tidak dicabut) dan baru tersambung setelah pukul 06.00 tidak menerima data, tetapi outbox-nya masuk karantina selama masa tenggang 72 jam; setelah event diarsipkan, push ditolak.
- [ ] Check-in manual Admin tanpa nomor tiket tidak memicu `conflict` maupun pelanggaran unique index, dan tetap dihitung di statistik.
- [ ] Check-in `repeat` tidak menambah total orang hadir.
- [ ] Logout ditolak selama outbox berisi; ekspor outbox darurat dapat diunggah di dashboard dan tersinkron tanpa duplikasi.
- [ ] Tamu yang dihapus Admin tidak dapat di-check-in di perangkat lain setelah delta sync.
- [ ] `special_number` berpola nomor perangkat (mis. `A-017`) ditolak di form, di Tinjau Tamu, dan oleh DB.
- [ ] Dengan **Tamu Check-In Lebih 1 Kali** aktif, tamu VVIP dengan nomor khusus yang check-in dua kali di dua perangkat offline tersinkron tanpa error; check-in kedua berstatus `repeat`.
- [ ] Token Layar Sapa hanya menerima sapaan event-nya dan tidak dapat membaca tabel atau channel lain.
- [ ] Bucket `invitations` tidak dapat di-list tanpa autentikasi; `/i/{token}` hanya mengembalikan kartu milik token itu.
- [ ] File export CSV dengan nama tamu berawalan `=` terbuka di Excel sebagai teks, bukan formula.
