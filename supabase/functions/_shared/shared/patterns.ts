// SALINAN OTOMATIS dari packages/shared/src/patterns.ts. Jangan diedit; jalankan `pnpm functions:sync`.
import {
  CODE_ALPHABET,
  EVENT_CODE_LENGTH,
  MAX_DEVICE_CODES,
  PIN_SECRET_LENGTH,
  SPECIAL_NUMBER_MAX_LENGTH,
  USHER_SELECTOR_LENGTH,
} from './config.ts';

/** Pola nomor tiket otomatis perangkat, mis. `A-017`. Dicadangkan; nomor khusus tidak boleh cocok. (12.2) */
export const DEVICE_TICKET_PATTERN = /^[A-Z]{1,2}-\d+$/;
/** Pola kode hadiah, mis. `A-H012`. Dicadangkan; nomor khusus tidak boleh cocok. (12.2) */
export const GIFT_CODE_PATTERN = /^[A-Z]{1,2}-H\d+$/;
const SPECIAL_NUMBER_CHARSET = /^[A-Z0-9-]+$/;

export type SpecialNumberIssue = 'empty' | 'too_long' | 'invalid_chars' | 'device_pattern' | 'gift_pattern';

/** Nomor khusus dan prefix selalu dinormalisasi ke huruf besar sebelum divalidasi (FR-C-02). */
export function normalizeSpecialNumber(raw: string): string {
  return raw.trim().toUpperCase();
}

/** Aturan FR-C-02 untuk nilai yang sudah dinormalisasi. `null` berarti valid. Constraint DB memakai aturan yang sama. */
export function checkSpecialNumber(value: string): SpecialNumberIssue | null {
  if (value.length === 0) return 'empty';
  if (value.length > SPECIAL_NUMBER_MAX_LENGTH) return 'too_long';
  if (!SPECIAL_NUMBER_CHARSET.test(value)) return 'invalid_chars';
  if (DEVICE_TICKET_PATTERN.test(value)) return 'device_pattern';
  if (GIFT_CODE_PATTERN.test(value)) return 'gift_pattern';
  return null;
}

export function formatSpecialNumber(prefix: string, n: number, digits: number): string {
  return `${normalizeSpecialNumber(prefix)}${String(n).padStart(digits, '0')}`;
}

/**
 * Setting Nomor Urut (FR-C-03): prefix dan jumlah digit harus menghasilkan nomor yang lolos FR-C-02.
 * Cukup diuji dengan satu contoh karena bagian angkanya selalu digit.
 */
export function checkTicketNumberSetting(prefix: string, digits: number): SpecialNumberIssue | null {
  if (!Number.isInteger(digits) || digits < 1 || digits > 6) return 'invalid_chars';
  return checkSpecialNumber(formatSpecialNumber(prefix, 1, digits));
}

// --- Kode Acara dan PIN Akses (FR-R-02) ----------------------------------------------------------

const codeChars = new RegExp(`^[${CODE_ALPHABET}]+$`);

/** Masukan usher tidak peka huruf besar/kecil dan boleh berisi spasi atau tanda hubung. */
function compact(raw: string): string {
  return raw.toUpperCase().replace(/[\s-]/g, '');
}

export function normalizeEventCode(raw: string): string {
  return compact(raw);
}

export function isValidEventCode(code: string): boolean {
  return code.length === EVENT_CODE_LENGTH && codeChars.test(code);
}

export interface ParsedPin {
  selector: string;
  secret: string;
}

/** `ab-xxxx-xxxx`, `ABXXXXXXXX`, atau dengan spasi → { selector: 'AB', secret: 'XXXXXXXX' }. */
export function parsePin(raw: string): ParsedPin | null {
  const s = compact(raw);
  if (s.length !== USHER_SELECTOR_LENGTH + PIN_SECRET_LENGTH || !codeChars.test(s)) return null;
  return { selector: s.slice(0, USHER_SELECTOR_LENGTH), secret: s.slice(USHER_SELECTOR_LENGTH) };
}

/** Bentuk tampilan `AB-XXXX-XXXX`. */
export function formatPin(selector: string, secret: string): string {
  return `${selector}-${secret.slice(0, 4)}-${secret.slice(4)}`;
}

// --- Kode perangkat (FR-C-06, 12.3 poin 3) ------------------------------------------------------

/** Kode perangkat urutan ke-`index` (mulai 0): A..Z, lalu AA..ZZ. Sama dengan private.device_code() di DB. */
export function deviceCode(index: number): string {
  if (!Number.isInteger(index) || index < 0 || index >= MAX_DEVICE_CODES) {
    throw new RangeError(`Indeks kode perangkat harus 0..${MAX_DEVICE_CODES - 1}.`);
  }
  if (index < 26) return String.fromCharCode(65 + index);
  const i = index - 26;
  return String.fromCharCode(65 + Math.floor(i / 26), 65 + (i % 26));
}

/** Kebalikan deviceCode(); `null` bila bukan kode perangkat. */
export function deviceCodeIndex(code: string): number | null {
  if (!/^[A-Z]{1,2}$/.test(code)) return null;
  if (code.length === 1) return code.charCodeAt(0) - 65;
  return 26 + (code.charCodeAt(0) - 65) * 26 + (code.charCodeAt(1) - 65);
}

/** Kode perangkat pada nomor tiket otomatis (`B-017` → `B`); `null` bila bukan nomor otomatis. */
export function ticketDeviceCode(ticket: string): string | null {
  return DEVICE_TICKET_PATTERN.test(ticket) ? ticket.slice(0, ticket.indexOf('-')) : null;
}
