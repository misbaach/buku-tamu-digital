import { describe, expect, it } from 'vitest';
import { dbErrorMessage } from './errors';

describe('pesan galat database', () => {
  it('pelanggaran constraint dipetakan ke pesan Indonesia, termasuk nomor baris impor', () => {
    expect(
      dbErrorMessage({
        code: '23505',
        message: 'duplicate key value violates unique constraint "guests_event_special_number_key"',
      }),
    ).toBe('Nomor Urut sudah dipakai tamu lain di acara ini.');
    expect(
      dbErrorMessage({
        code: '23514',
        message: 'Baris 7: new row for relation "guests" violates check constraint "guests_special_number_rule"',
      }),
    ).toMatch(/^Baris 7: Nomor Urut tidak sah/);
  });

  it('pesan RPC kita (sudah berbahasa Indonesia) diteruskan apa adanya', () => {
    expect(
      dbErrorMessage({ code: '40001', message: 'Data tamu berubah sejak pratinjau dibuat. Buat pratinjau ulang.' }),
    ).toBe('Data tamu berubah sejak pratinjau dibuat. Buat pratinjau ulang.');
    expect(dbErrorMessage({ code: '42501', message: 'Anda bukan Admin acara ini.' })).toBe(
      'Anda bukan Admin acara ini.',
    );
  });

  it('pesan Postgres mentah tidak bocor ke pengguna', () => {
    expect(dbErrorMessage({ code: '42501', message: 'permission denied for table guests' })).toBe(
      'Anda tidak punya izin untuk tindakan ini.',
    );
    expect(dbErrorMessage({ code: 'XX000', message: 'internal error' })).toMatch(/^Terjadi kesalahan/);
    expect(dbErrorMessage({ name: 'TypeError', message: 'Failed to fetch' })).toMatch(/^Tidak dapat terhubung/);
  });
});
