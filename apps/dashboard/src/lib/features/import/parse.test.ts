import { describe, expect, it } from 'vitest';
import { cellText, ImportFileError, rowsToResults } from './parse';

describe('parsing berkas impor', () => {
  it('angka bulat besar (telepon) tidak berubah menjadi notasi ilmiah', () => {
    expect(cellText(6281234567890)).toBe('6281234567890');
    expect(cellText(2.5)).toBe('2.5');
    expect(cellText('  Ani  ')).toBe('Ani');
    expect(cellText(null)).toBe('');
  });

  it('nomor baris mengikuti Excel; baris kosong dilewati tanpa menggeser nomor', () => {
    const results = rowsToResults([
      ['Nama', 'Kategori'],
      ['Ani', 'VIP'],
      ['', ''],
      ['Bayu', ''],
    ]);
    expect(results.map((r) => [r.row, r.ok])).toEqual([
      [2, true],
      [4, true],
    ]);
  });

  it('tanpa kolom Nama, atau tanpa data, berkas ditolak', () => {
    expect(() => rowsToResults([['Telepon'], ['0812']])).toThrow(ImportFileError);
    expect(() => rowsToResults([['Nama'], ['', '']])).toThrow('tidak berisi data');
  });
});
