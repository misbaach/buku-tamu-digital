import { describe, expect, it } from 'vitest';
import { guestFormSchema } from './guest.ts';

const base = {
  name: '  Budi Santoso ',
  phone: '',
  category: 'vip',
  group_id: '',
  invited_pax: '2',
  special_number: '',
  rsvp_status: 'going',
  rsvp_pax: '2',
  notes: '',
};

describe('form tamu (FR-G-01, FR-G-02)', () => {
  it('nilai kosong menjadi null, angka dari input teks dikonversi, nama di-trim', () => {
    expect(guestFormSchema.parse(base)).toEqual({
      name: 'Budi Santoso',
      phone: null,
      category: 'vip',
      group_id: null,
      invited_pax: 2,
      special_number: null,
      rsvp_status: 'going',
      rsvp_pax: 2,
      notes: null,
    });
  });

  it('Nomor Urut dinormalisasi; pola nomor perangkat ditolak (FR-C-02)', () => {
    expect(guestFormSchema.parse({ ...base, special_number: ' vip-007 ' }).special_number).toBe('VIP-007');
    const r = guestFormSchema.safeParse({ ...base, special_number: 'a-017' });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.path).toEqual(['special_number']);
  });

  it('jumlah konfirmasi dikosongkan bila status bukan Akan hadir', () => {
    expect(guestFormSchema.parse({ ...base, rsvp_status: 'not_going', rsvp_pax: '3' }).rsvp_pax).toBeNull();
  });

  it('validasi nama, telepon, pax', () => {
    const r = guestFormSchema.safeParse({ ...base, name: ' ', phone: 'nomor saya', invited_pax: '0' });
    expect(r.success).toBe(false);
    expect(r.error?.issues.map((i) => i.path[0]).sort()).toEqual(['invited_pax', 'name', 'phone']);
  });

  it('telepon dengan spasi dan tanda hubung diterima, spasi ganda dirapikan', () => {
    expect(guestFormSchema.parse({ ...base, phone: '+62  812-3456-7890' }).phone).toBe('+62 812-3456-7890');
  });
});
