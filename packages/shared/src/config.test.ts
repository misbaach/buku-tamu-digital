import { describe, expect, it } from 'vitest';
import {
  CODE_ALPHABET,
  DB_MIRRORED_CONFIG,
  invitationPath,
  MAX_DEVICE_CODES,
  PIN_DISPLAY_FORMAT,
  PIN_SECRET_LENGTH,
  QR_TOKEN_BYTES,
  USHER_LOGIN_IP_BLOCK_FAILS,
  USHER_LOGIN_PIN_BLOCK_FAILS,
  USHER_SELECTOR_LENGTH,
} from './config.ts';

describe('config', () => {
  it('alfabet kode: 31 karakter unik tanpa karakter yang mirip', () => {
    expect(CODE_ALPHABET).toHaveLength(31);
    expect(new Set(CODE_ALPHABET).size).toBe(31);
    for (const ambiguous of ['0', 'O', '1', 'I', 'L']) expect(CODE_ALPHABET).not.toContain(ambiguous);
  });

  it('kapasitas kode perangkat = A..Z + AA..ZZ', () => {
    expect(MAX_DEVICE_CODES).toBe(26 + 26 * 26);
  });

  it('token QR tamu ≥ 128 bit (FR-G-07)', () => {
    expect(QR_TOKEN_BYTES * 8).toBeGreaterThanOrEqual(128);
  });

  it('format tampilan PIN cocok dengan panjang ID usher + rahasia', () => {
    expect(PIN_DISPLAY_FORMAT.replace(/-/g, '')).toHaveLength(USHER_SELECTOR_LENGTH + PIN_SECRET_LENGTH);
  });

  it('blokir global per IP lebih longgar daripada blokir per (IP + Kode Acara)', () => {
    expect(USHER_LOGIN_IP_BLOCK_FAILS).toBeGreaterThan(USHER_LOGIN_PIN_BLOCK_FAILS);
  });

  it('format URL kartu tamu dikunci sebagai /i/{token} (D17)', () => {
    expect(invitationPath('abc_DEF-123')).toBe('/i/abc_DEF-123');
  });

  it('konfigurasi yang dicerminkan ke DB hanya berisi nilai primitif', () => {
    for (const v of Object.values(DB_MIRRORED_CONFIG)) expect(['string', 'number']).toContain(typeof v);
  });
});
