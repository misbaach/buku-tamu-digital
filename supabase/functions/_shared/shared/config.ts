// SALINAN OTOMATIS dari packages/shared/src/config.ts. Jangan diedit; jalankan `pnpm functions:sync`.
/**
 * Satu-satunya sumber konstanta proyek.
 *
 * - Angka bertanda (Asumsi) berasal dari prd.md dan masih perlu divalidasi.
 * - (Asumsi-teknis) adalah angka teknis yang dipilih saat implementasi.
 * - Nilai di DB_MIRRORED_CONFIG juga dipakai database lewat private.config(); tes
 *   tests/integration/config-parity.test.ts gagal bila keduanya berbeda.
 */

/** Ukuran maksimal file impor tamu. FR-G-03 (Asumsi) */
export const IMPORT_MAX_FILE_BYTES = 5 * 1024 * 1024;
/** Baris maksimal per impor; sama dengan skala tamu per acara. (Asumsi-teknis) */
export const IMPORT_MAX_ROWS = 5000;

// --- Login usher (FR-R-02, FR-R-09) -------------------------------------------------------------

/** Alfabet Kode Acara, ID usher, dan rahasia PIN: tanpa karakter mirip (0/O, 1/I/L). */
export const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const EVENT_CODE_LENGTH = 6;
export const USHER_SELECTOR_LENGTH = 2;
export const PIN_SECRET_LENGTH = 8;
/** Bentuk tampilan PIN Akses: ID usher + rahasia 8 karakter dalam dua kelompok. */
export const PIN_DISPLAY_FORMAT = 'AB-XXXX-XXXX';

/** Blokir login PIN per kunci (IP + Kode Acara yang dikirim). FR-R-09 */
export const USHER_LOGIN_PIN_BLOCK_FAILS = 10;
/** Blokir global login PIN per IP, Kode Acara apa pun. FR-R-09 */
export const USHER_LOGIN_IP_BLOCK_FAILS = 50;
/** Ambang peringatan kegagalan per event, tanpa mengunci. FR-R-09 (Asumsi) */
export const USHER_LOGIN_EVENT_WARN_FAILS = 20;
/** Jendela hitung kegagalan login, dalam menit. FR-R-09 (Asumsi) */
export const USHER_LOGIN_WINDOW_MIN = 15;
/** Durasi minimal respons login gagal agar waktunya seragam. (Asumsi-teknis) */
export const USHER_LOGIN_FAIL_MIN_MS = 500;

/** Biaya bcrypt rahasia PIN (±50–100 ms per verifikasi di server). (Asumsi-teknis) */
export const PIN_BCRYPT_COST = 10;

/** Masa berlaku QR Login. FR-R-02 */
export const QR_LOGIN_TTL_SEC = 300;
/** Panjang acak token QR Login dalam byte (256 bit). FR-R-02 */
export const USHER_LOGIN_QR_TOKEN_BYTES = 32;
/** Domain email sintetis user Auth perangkat. `.invalid` dicadangkan RFC 2606, tidak pernah menerima email. */
export const DEVICE_EMAIL_DOMAIN = 'device.buku-tamu.invalid';

// --- Sesi dan perangkat usher (FR-R-08, FR-R-10, FR-C-06) ----------------------------------------

/** Sesi usher berakhir H+1 pukul 06.00 waktu lokal event. FR-R-10 (Asumsi) */
export const USHER_SESSION_END = { dayOffset: 1, localTime: '06:00' } as const;
/** Masa tenggang karantina sesi habis wajar DAN jeda penghapusan user Auth perangkat. FR-R-10 (Asumsi) */
export const SESSION_GRACE_HOURS = 72;
/** Batas item karantina per perangkat. FR-R-08 */
export const QUARANTINE_MAX_ITEMS_PER_DEVICE = 500;
/** Jadwal job device-cleanup (sintaks cron). (Asumsi-teknis) */
export const DEVICE_CLEANUP_SCHEDULE = '*/15 * * * *';
/** Kode perangkat A..Z, AA..ZZ sesuai pola nomor perangkat. FR-C-06 */
export const MAX_DEVICE_CODES = 702;

// --- Tamu, nomor, dan QR (FR-C-02, FR-G-07) ------------------------------------------------------

export const SPECIAL_NUMBER_MAX_LENGTH = 20;
/** Panjang acak token QR tamu dalam byte (144 bit). FR-G-07 */
export const QR_TOKEN_BYTES = 18;
/** Format URL halaman kartu tamu, dikunci sejak MVP. Halamannya dibangun di M4. FR-G-07, D17 */
export const INVITATION_PATH = '/i/{token}';

export function invitationPath(token: string): string {
  return INVITATION_PATH.replace('{token}', encodeURIComponent(token));
}

// --- Sinkronisasi (12.3) -------------------------------------------------------------------------

/** Item maksimal per panggilan push_outbox. (Asumsi-teknis) */
export const PUSH_BATCH_MAX = 200;
/** Baris maksimal per halaman pull_snapshot. (Asumsi-teknis) */
export const SNAPSHOT_PAGE_SIZE = 1000;
/** Tumpang tindih kursor delta sync agar transaksi yang commit terlambat tidak terlewat. (Asumsi-teknis) */
export const SYNC_CURSOR_OVERLAP_MS = 5000;
/** Selisih jam perangkat yang ditampilkan di daftar perangkat. FR-HM-10 */
export const CLOCK_SKEW_WARN_MS = 120_000;

// --- Dashboard (FR-S-07) -------------------------------------------------------------------------

export const STATS_DEBOUNCE_MS = 1000;
export const STATS_POLL_FALLBACK_MS = 10_000;

// --- Upload gambar (FR-E-08, dipakai foto pop-up sapaan) ----------------------------------------

export const UPLOAD_MAX_BYTES = 5 * 1024 * 1024;
export const UPLOAD_MIME = ['image/png', 'image/jpeg', 'image/webp'] as const;
/** Bucket privat foto pop-up sapaan. Path: `{event_id}/{kategori}/{uuid}.{ext}`. FR-P-01 */
export const GREETING_PHOTO_BUCKET = 'greeting-photos';
/** Masa berlaku signed URL pratinjau foto di dashboard. (Asumsi-teknis) */
export const SIGNED_URL_TTL_SEC = 300;

// --- Pengaturan check-in dan sapaan (FR-R-03, FR-R-04, FR-P-01) ---------------------------------

/** Informasi yang bisa dipilih untuk tiket penomoran. "Kode hadiah" menyusul bersama fitur Hadiah (P1). */
export const PRINT_TICKET_FIELDS = [
  'event_name',
  'couple_names',
  'event_date',
  'guest_name',
  'category',
  'group_name',
  'ticket_number',
  'pax',
  'checked_in_at',
] as const;
export const PRINT_TICKET_MAX_COPIES = 3;
export const GREETING_TITLE_MAX = 80;
export const GREETING_BODY_MAX = 300;
export const GREETING_LAYOUTS = ['text', 'photo_wide', 'photo_round'] as const;

// --- Skala dan infrastruktur (10.2, 11.1) -------------------------------------------------------

/** (Asumsi) dipakai untuk seed dan uji beban, bukan batas keras. */
export const SCALE = { maxGuests: 5000, maxDevices: 10, maxDashboardSessions: 20 } as const;
/** Region project Supabase produksi. (Asumsi) */
export const SUPABASE_REGION = 'ap-southeast-1';

/**
 * Nilai yang juga dipakai di dalam database. Migration menyalinnya ke private.config();
 * mengubah nilai di sini tanpa migration baru membuat tes paritas gagal.
 */
export const DB_MIRRORED_CONFIG = {
  code_alphabet: CODE_ALPHABET,
  event_code_length: EVENT_CODE_LENGTH,
  usher_selector_length: USHER_SELECTOR_LENGTH,
  pin_secret_length: PIN_SECRET_LENGTH,
  usher_login_pin_block_fails: USHER_LOGIN_PIN_BLOCK_FAILS,
  usher_login_ip_block_fails: USHER_LOGIN_IP_BLOCK_FAILS,
  usher_login_event_warn_fails: USHER_LOGIN_EVENT_WARN_FAILS,
  usher_login_window_min: USHER_LOGIN_WINDOW_MIN,
  usher_session_end_day_offset: USHER_SESSION_END.dayOffset,
  usher_session_end_local_time: USHER_SESSION_END.localTime,
  session_grace_hours: SESSION_GRACE_HOURS,
  quarantine_max_items_per_device: QUARANTINE_MAX_ITEMS_PER_DEVICE,
  device_cleanup_schedule: DEVICE_CLEANUP_SCHEDULE,
  max_device_codes: MAX_DEVICE_CODES,
  qr_login_ttl_sec: QR_LOGIN_TTL_SEC,
  qr_token_bytes: QR_TOKEN_BYTES,
  special_number_max_length: SPECIAL_NUMBER_MAX_LENGTH,
  push_batch_max: PUSH_BATCH_MAX,
  snapshot_page_size: SNAPSHOT_PAGE_SIZE,
  sync_cursor_overlap_ms: SYNC_CURSOR_OVERLAP_MS,
  upload_max_bytes: UPLOAD_MAX_BYTES,
  import_max_rows: IMPORT_MAX_ROWS,
  pin_bcrypt_cost: PIN_BCRYPT_COST,
  usher_login_qr_token_bytes: USHER_LOGIN_QR_TOKEN_BYTES,
  upload_mime: UPLOAD_MIME,
  greeting_photo_bucket: GREETING_PHOTO_BUCKET,
  print_ticket_fields: PRINT_TICKET_FIELDS,
  print_ticket_max_copies: PRINT_TICKET_MAX_COPIES,
  greeting_title_max: GREETING_TITLE_MAX,
  greeting_body_max: GREETING_BODY_MAX,
  greeting_layouts: GREETING_LAYOUTS,
} as const;
