import { z } from '../zod.ts';
import { DEVICE_EMAIL_DOMAIN } from '../config.ts';
import { USHER_MODES, type UsherMode } from '../enums.ts';

// File ini juga disalin ke supabase/functions/_shared (scripts/sync-shared-to-functions.mjs), jadi hanya
// boleh mengimpor zod.ts, config.ts, enums.ts, dan patterns.ts.

/** Tambah/ubah Penerima Tamu (FR-R-01). */
export const usherFormSchema = z.object({
  name: z.string().trim().min(1, 'Nama penerima tamu wajib diisi.').max(60, 'Nama maksimal 60 karakter.'),
  mode: z.enum(USHER_MODES),
});
export type UsherForm = z.infer<typeof usherFormSchema>;

const reason = z.string().trim().max(300, 'Alasan maksimal 300 karakter.');

/** Cabut (alasan opsional) atau Cabut & putus total (alasan wajib, prd.md 13.1 poin 6). FR-R-08 */
export const revokeRequestSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('quarantine'), reason: reason.optional() }),
  z.object({ mode: z.literal('terminate'), reason: reason.min(1, 'Alasan wajib diisi.') }),
]);

// --- Edge Function usher-login (docs/plan.md bagian 9) -------------------------------------------

const deviceInfoSchema = z
  .object({
    name: z.string().trim().max(80).default(''),
    appVersion: z.string().trim().max(40).default(''),
  })
  .default({ name: '', appVersion: '' });

/**
 * Bentuk body login. Isi `eventCode` dan `pin` sengaja tidak divalidasi formatnya di sini: format yang salah
 * tetap diproses sampai bcrypt dummy agar respons gagalnya identik (FR-R-02). Batas panjang hanya mencegah
 * body raksasa.
 */
export const usherLoginRequestSchema = z.discriminatedUnion('method', [
  z.object({
    method: z.literal('pin'),
    eventCode: z.string().max(64),
    pin: z.string().max(64),
    device: deviceInfoSchema,
  }),
  z.object({ method: z.literal('qr'), token: z.string().max(256), device: deviceInfoSchema }),
]);
export type UsherLoginRequest = z.input<typeof usherLoginRequestSchema>;

export interface UsherLoginSuccess {
  session: { accessToken: string; refreshToken: string; expiresAt: number; expiresIn: number };
  device: { id: string; code: string };
  event: { id: string; name: string };
  usher: { name: string; mode: UsherMode };
  sessionExpiresAt: string;
}

/**
 * Galat login. `invalid_credentials` identik untuk semua penyebab (status, isi, dan waktu). Galat 403 hanya
 * muncul setelah kredensial terbukti sah; `too_many_attempts` (429) membawa `retryAfter` dalam detik.
 */
export type UsherLoginErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'too_many_attempts'
  | 'event_archived'
  | 'session_ended'
  | 'device_capacity'
  | 'server_error';

export interface UsherLoginError {
  error: UsherLoginErrorCode;
  retryAfter?: number;
}

/** Email sintetis user Auth perangkat; tidak pernah dipakai untuk mengirim email. */
export function deviceEmail(deviceId: string): string {
  return `${deviceId}@${DEVICE_EMAIL_DOMAIN}`;
}

// --- Edge Function device-cleanup ----------------------------------------------------------------

export const deviceCleanupRequestSchema = z.discriminatedUnion('mode', [
  z.object({ mode: z.literal('terminate'), deviceId: z.uuid(), reason: reason.min(1) }),
  z.object({ mode: z.literal('sweep') }),
]);
export type DeviceCleanupRequest = z.infer<typeof deviceCleanupRequestSchema>;
