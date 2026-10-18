import { describe, expect, it } from 'vitest';
import { SPECIAL_NUMBER_CASES } from './fixtures/special-numbers.ts';
import {
  checkSpecialNumber,
  checkTicketNumberSetting,
  DEVICE_TICKET_PATTERN,
  formatPin,
  formatSpecialNumber,
  GIFT_CODE_PATTERN,
  isValidEventCode,
  normalizeEventCode,
  normalizeSpecialNumber,
  parsePin,
} from './patterns.ts';
import { eventCodeSchema, pinSchema, specialNumberSchema } from './schemas/common.ts';

describe('nomor khusus (FR-C-02)', () => {
  it.each(SPECIAL_NUMBER_CASES)('$value → $issue', ({ value, issue }) => {
    expect(checkSpecialNumber(value)).toBe(issue);
  });

  it('dinormalisasi ke huruf besar sebelum divalidasi, sehingga a-017 tetap ditolak', () => {
    expect(normalizeSpecialNumber('  a-017 ')).toBe('A-017');
    const r = specialNumberSchema.safeParse('a-017');
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.message).toContain('pola nomor perangkat');
  });

  it('skema mengembalikan nilai ternormalisasi', () => {
    expect(specialNumberSchema.parse('vvip-007')).toBe('VVIP-007');
  });

  it('pola nomor perangkat dan kode hadiah sesuai 12.2', () => {
    expect(DEVICE_TICKET_PATTERN.test('A-017')).toBe(true);
    expect(DEVICE_TICKET_PATTERN.test('AA-1')).toBe(true);
    expect(DEVICE_TICKET_PATTERN.test('AAA-1')).toBe(false);
    expect(GIFT_CODE_PATTERN.test('A-H012')).toBe(true);
    expect(DEVICE_TICKET_PATTERN.test('A-H012')).toBe(false);
  });
});

describe('setting Nomor Urut (FR-C-03)', () => {
  it('format prefix + angka dengan digit tetap', () => {
    expect(formatSpecialNumber('vvip-', 7, 3)).toBe('VVIP-007');
    expect(formatSpecialNumber('VIP-', 1234, 3)).toBe('VIP-1234');
  });

  it('prefix yang menghasilkan pola perangkat atau kode hadiah ditolak', () => {
    expect(checkTicketNumberSetting('VVIP-', 3)).toBeNull();
    expect(checkTicketNumberSetting('A-', 3)).toBe('device_pattern');
    expect(checkTicketNumberSetting('ab-', 2)).toBe('device_pattern');
    expect(checkTicketNumberSetting('A-H', 3)).toBe('gift_pattern');
    expect(checkTicketNumberSetting('V P-', 3)).toBe('invalid_chars');
    expect(checkTicketNumberSetting(' vip- ', 3)).toBeNull(); // spasi di tepi di-trim
    expect(checkTicketNumberSetting('X'.repeat(18), 3)).toBe('too_long');
    expect(checkTicketNumberSetting('VIP-', 0)).toBe('invalid_chars');
  });
});

describe('Kode Acara dan PIN Akses (FR-R-02)', () => {
  it('Kode Acara tidak peka huruf besar/kecil dan mengabaikan spasi/tanda hubung', () => {
    expect(normalizeEventCode(' k7p-m2x ')).toBe('K7PM2X');
    expect(isValidEventCode('K7PM2X')).toBe(true);
    expect(isValidEventCode('K7PM2')).toBe(false);
    expect(isValidEventCode('K7PM2O')).toBe(false); // O tidak ada di alfabet
    expect(eventCodeSchema.parse('k7pm2x')).toBe('K7PM2X');
  });

  it('PIN diurai menjadi ID usher + rahasia dari berbagai bentuk masukan', () => {
    const expected = { selector: 'AB', secret: 'CDEFGH23' };
    expect(parsePin('AB-CDEF-GH23')).toEqual(expected);
    expect(parsePin('abcdefgh23')).toEqual(expected);
    expect(parsePin('ab cdef gh23')).toEqual(expected);
  });

  it('PIN dengan panjang atau karakter salah tidak bisa diurai', () => {
    expect(parsePin('AB-CDEF-GH2')).toBeNull();
    expect(parsePin('AB-CDEF-GH234')).toBeNull();
    expect(parsePin('AB-CDEF-GH20')).toBeNull(); // 0 tidak ada di alfabet
    expect(parsePin('AB-CDEF-GHI2')).toBeNull(); // I tidak ada di alfabet
    expect(pinSchema.safeParse('salah').success).toBe(false);
  });

  it('format tampilan PIN mengikuti AB-XXXX-XXXX', () => {
    expect(formatPin('AB', 'CDEFGH23')).toBe('AB-CDEF-GH23');
  });
});
