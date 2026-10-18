import { describe, expect, it } from 'vitest';
import { crossCheckImport, mapImportHeaders, validateImportRow } from './import.ts';

describe('impor tamu: header (FR-G-03)', () => {
  it('header templat dan alias dikenali tanpa peka huruf besar/kecil; kolom tak dikenal diabaikan', () => {
    const { map, missing } = mapImportHeaders([
      'NAMA',
      'No. HP',
      'kategori',
      'Kolom Lain',
      'Nomor Urut',
      'status rsvp',
    ]);
    expect([...map.entries()]).toEqual([
      [0, 'name'],
      [1, 'phone'],
      [2, 'category'],
      [4, 'special_number'],
      [5, 'rsvp_status'],
    ]);
    expect(missing).toEqual([]);
  });

  it('kolom Nama wajib ada', () => {
    expect(mapImportHeaders(['Telepon']).missing).toEqual(['name']);
  });
});

describe('impor tamu: baris', () => {
  it('baris lengkap dengan label Indonesia', () => {
    const r = validateImportRow(2, {
      name: ' Ani ',
      category: 'vvip',
      group: 'Keluarga',
      invited_pax: '2',
      special_number: 'vvip-001',
      rsvp_status: 'Akan hadir',
      rsvp_pax: '2',
    });
    expect(r.ok && r.value).toEqual({
      row: 2,
      name: 'Ani',
      phone: null,
      category: 'vvip',
      group: 'Keluarga',
      invited_pax: 2,
      special_number: 'VVIP-001',
      rsvp_status: 'going',
      rsvp_pax: 2,
      notes: null,
    });
  });

  it('nilai kosong memakai default: Regular, 1 undangan, Belum konfirmasi', () => {
    const r = validateImportRow(3, { name: 'Bayu' });
    expect(r.ok && [r.value.category, r.value.invited_pax, r.value.rsvp_status]).toEqual(['regular', 1, 'unconfirmed']);
  });

  it('galat dilaporkan per kolom dengan pesan yang bisa ditindaklanjuti', () => {
    const r = validateImportRow(4, {
      name: '',
      category: 'Raja',
      special_number: 'A-017',
      rsvp_status: 'Tidak hadir',
      rsvp_pax: '3',
      invited_pax: 'dua',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.issues.map((i) => i.field).sort()).toEqual([
        'category',
        'invited_pax',
        'name',
        'rsvp_pax',
        'special_number',
      ]);
      expect(r.issues.find((i) => i.field === 'category')?.message).toContain('Regular, VIP, atau VVIP');
    }
  });
});

describe('impor tamu: pemeriksaan antarbaris', () => {
  it('Nomor Urut ganda di berkas dan yang sudah dipakai di DB ditandai', () => {
    const rows = [
      validateImportRow(2, { name: 'A', special_number: 'VIP-001' }),
      validateImportRow(3, { name: 'B', special_number: 'vip-001' }),
      validateImportRow(4, { name: 'C', special_number: 'VIP-009' }),
      validateImportRow(5, { name: 'D' }),
    ];
    const checked = crossCheckImport(rows, new Map([['VIP-009', 'Tamu Lama']]));
    expect(checked.map((r) => r.ok)).toEqual([true, false, false, true]);
    expect(!checked[1]!.ok && checked[1]!.issues[0]!.message).toContain('baris 2');
    expect(!checked[2]!.ok && checked[2]!.issues[0]!.message).toContain('Tamu Lama');
  });
});
