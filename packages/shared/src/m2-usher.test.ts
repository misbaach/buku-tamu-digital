import { describe, expect, it } from 'vitest';
import { MAX_DEVICE_CODES } from './config.ts';
import { deviceState } from './labels.ts';
import { deviceCode, deviceCodeIndex, ticketDeviceCode } from './patterns.ts';
import { detectImageMime, greetingFormSchema, renderGreeting, unknownGreetingVariables } from './schemas/greeting.ts';
import { printTicketSchema } from './schemas/settings.ts';
import { deviceEmail, revokeRequestSchema, usherLoginRequestSchema } from './schemas/usher.ts';
import { GUEST_SNAPSHOT_KEYS } from './sync.ts';

const bytes = (text: string) => Uint8Array.from(text, (c) => c.charCodeAt(0));

describe('kode perangkat (FR-C-06)', () => {
  it('A..Z lalu AA..ZZ, total 702, dan bolak-balik dengan indeks', () => {
    expect([0, 25, 26, 27, 51, 52, 701].map(deviceCode)).toEqual(['A', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ']);
    expect(() => deviceCode(MAX_DEVICE_CODES)).toThrow(RangeError);
    for (let i = 0; i < MAX_DEVICE_CODES; i++) expect(deviceCodeIndex(deviceCode(i))).toBe(i);
    expect(deviceCodeIndex('A1')).toBeNull();
  });

  it('kode perangkat diambil dari nomor tiket otomatis saja', () => {
    expect(ticketDeviceCode('AB-017')).toBe('AB');
    expect(ticketDeviceCode('VVIP-007')).toBeNull();
    expect(ticketDeviceCode('A-H012')).toBeNull();
  });
});

describe('pop-up sapaan (FR-P-01, FR-P-02)', () => {
  it('variabel {{nama}} dan {{kategori}} diganti; spasi di dalam kurung diizinkan', () => {
    expect(renderGreeting('Halo {{ nama }} ({{kategori}})', { nama: 'Ani', kategori: 'VIP' })).toBe('Halo Ani (VIP)');
  });

  it('variabel yang salah ketik ditolak sebelum disimpan', () => {
    expect(unknownGreetingVariables('Halo {{namaa}} dan {{nama}}')).toEqual(['namaa']);
    const r = greetingFormSchema.safeParse({ title: 'Halo {{Nama}}', body: '', layout: 'text' });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.message).toContain('{{Nama}}');
  });

  it('judul wajib; panjang dibatasi', () => {
    expect(greetingFormSchema.safeParse({ title: '  ', body: '', layout: 'text' }).success).toBe(false);
    expect(greetingFormSchema.safeParse({ title: 'a'.repeat(81), body: '', layout: 'text' }).success).toBe(false);
  });

  it('jenis gambar dari isi berkas: PNG, JPEG, WebP diterima; SVG ditolak walau bernama .png', () => {
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);
    const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
    const webp = bytes('RIFF\0\0\0\0WEBPVP8 ');
    const svg = bytes('<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>');
    expect([png, jpg, webp, svg].map(detectImageMime)).toEqual(['image/png', 'image/jpeg', 'image/webp', null]);
  });
});

describe('Print Tiket Penomoran (FR-R-04)', () => {
  const base = { enabled: true, fields: ['guest_name', 'ticket_number'], categories: ['vip'], copies: 1 };
  it('pengaturan sah diterima', () => expect(printTicketSchema.safeParse(base).success).toBe(true));
  it('saat aktif, minimal satu informasi dan satu kategori', () => {
    expect(printTicketSchema.safeParse({ ...base, fields: [] }).success).toBe(false);
    expect(printTicketSchema.safeParse({ ...base, categories: [] }).success).toBe(false);
    expect(printTicketSchema.safeParse({ ...base, enabled: false, categories: [] }).success).toBe(true);
  });
  it('salinan 1–3; informasi di luar daftar ditolak', () => {
    expect(printTicketSchema.safeParse({ ...base, copies: 4 }).success).toBe(false);
    expect(printTicketSchema.safeParse({ ...base, fields: ['phone'] }).success).toBe(false);
  });
});

describe('usher dan perangkat', () => {
  it('body login: format PIN tidak divalidasi (tetap ke bcrypt dummy), tetapi bentuk body divalidasi', () => {
    expect(usherLoginRequestSchema.safeParse({ method: 'pin', eventCode: '?', pin: '1' }).success).toBe(true);
    expect(usherLoginRequestSchema.safeParse({ method: 'pin', eventCode: 'K7PM2X' }).success).toBe(false);
    expect(usherLoginRequestSchema.safeParse({ method: 'qr', token: 'x'.repeat(257) }).success).toBe(false);
  });

  it('putus total wajib beralasan; Cabut tidak', () => {
    expect(revokeRequestSchema.safeParse({ mode: 'quarantine' }).success).toBe(true);
    expect(revokeRequestSchema.safeParse({ mode: 'terminate', reason: ' ' }).success).toBe(false);
    expect(revokeRequestSchema.safeParse({ mode: 'terminate', reason: 'HP hilang' }).success).toBe(true);
  });

  it('email sintetis perangkat memakai TLD .invalid', () => {
    expect(deviceEmail('abc')).toBe('abc@device.buku-tamu.invalid');
  });

  it('keadaan perangkat mengikuti urutan pemeriksaan server', () => {
    const later = new Date(Date.now() + 3_600_000).toISOString();
    const earlier = new Date(Date.now() - 3_600_000).toISOString();
    expect(deviceState({ revoke_mode: null, session_expires_at: later }, false)).toBe('active');
    expect(deviceState({ revoke_mode: null, session_expires_at: earlier }, false)).toBe('expired');
    expect(deviceState({ revoke_mode: null, session_expires_at: later }, true)).toBe('expired');
    expect(deviceState({ revoke_mode: 'quarantine', session_expires_at: later }, true)).toBe('revoked');
    expect(deviceState({ revoke_mode: 'terminate', session_expires_at: later }, false)).toBe('terminated');
  });

  it('GuestSnapshot berisi 14 kunci tanpa telepon, catatan, dan token QR mentah', () => {
    expect(GUEST_SNAPSHOT_KEYS).toHaveLength(14);
    expect(GUEST_SNAPSHOT_KEYS).not.toContain('phone');
    expect(GUEST_SNAPSHOT_KEYS).not.toContain('notes');
    expect(GUEST_SNAPSHOT_KEYS).not.toContain('qrToken');
  });
});
