import { afterAll, describe, expect, it } from 'vitest';
import { MAX_DEVICE_CODES, deviceCode } from '@guestbook/shared';
import { db } from './setup.ts';

// deviceCode() di TypeScript dan private.device_code() di DB harus menghasilkan kode yang sama untuk ke-702 indeks.
describe('paritas kode perangkat TS ↔ DB', () => {
  const sql = db();
  afterAll(() => sql.end());

  it('A..ZZ identik', async () => {
    const rows = await sql<{ i: number; code: string; back: number }[]>`
      select i, private.device_code(i) as code, private.device_code_index(private.device_code(i)) as back
      from generate_series(0, ${MAX_DEVICE_CODES - 1}) i order by i`;
    expect(rows.map((r) => r.code)).toEqual(Array.from({ length: MAX_DEVICE_CODES }, (_, i) => deviceCode(i)));
    expect(rows.every((r) => r.back === r.i)).toBe(true);
  });
});
