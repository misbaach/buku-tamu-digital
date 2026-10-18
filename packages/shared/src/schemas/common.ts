import { z } from 'zod';
import {
  checkSpecialNumber,
  isValidEventCode,
  normalizeEventCode,
  normalizeSpecialNumber,
  parsePin,
  type SpecialNumberIssue,
} from '../patterns.ts';
import { SPECIAL_NUMBER_MAX_LENGTH } from '../config.ts';

export function specialNumberMessage(issue: SpecialNumberIssue, value: string): string {
  switch (issue) {
    case 'empty':
      return 'Nomor urut tidak boleh kosong.';
    case 'too_long':
      return `Nomor urut maksimal ${SPECIAL_NUMBER_MAX_LENGTH} karakter.`;
    case 'invalid_chars':
      return 'Nomor urut hanya boleh berisi huruf, angka, dan tanda hubung (-).';
    case 'device_pattern':
      return `“${value}” memakai pola nomor perangkat (1–2 huruf, tanda hubung, angka). Pakai awalan lain, misalnya “VIP-${value.split('-')[1] ?? '001'}”.`;
    case 'gift_pattern':
      return `“${value}” memakai pola kode hadiah. Pakai awalan lain.`;
  }
}

/** Nomor Urut khusus (FR-C-02): dinormalisasi ke huruf besar, lalu divalidasi. */
export const specialNumberSchema = z
  .string()
  .transform(normalizeSpecialNumber)
  .superRefine((value, ctx) => {
    const issue = checkSpecialNumber(value);
    if (issue) ctx.addIssue({ code: 'custom', message: specialNumberMessage(issue, value), params: { issue } });
  });

/** Kode Acara (FR-R-02): tidak peka huruf besar/kecil; spasi dan tanda hubung diabaikan. */
export const eventCodeSchema = z
  .string()
  .transform(normalizeEventCode)
  .refine(isValidEventCode, { message: 'Kode Acara terdiri dari 6 huruf/angka.' });

/**
 * PIN Akses untuk validasi di sisi klien. Edge Function usher-login TIDAK memakai skema ini untuk
 * menolak masukan, karena PIN yang formatnya salah tetap harus melewati bcrypt dummy (respons identik).
 */
export const pinSchema = z.string().transform((value, ctx) => {
  const parsed = parsePin(value);
  if (!parsed) {
    ctx.addIssue({ code: 'custom', message: 'PIN terdiri dari 10 huruf/angka, misalnya AB-XXXX-XXXX.' });
    return z.NEVER;
  }
  return parsed;
});
