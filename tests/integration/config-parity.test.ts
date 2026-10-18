import { afterAll, describe, expect, it } from 'vitest';
import { DB_MIRRORED_CONFIG } from '@guestbook/shared/config';
import { db } from './setup.ts';

// config.ts adalah satu-satunya sumber nilai. private.config() adalah salinannya untuk dipakai di dalam DB.
// Mengubah config.ts tanpa migration baru (atau sebaliknya) membuat tes ini gagal.
describe('paritas config.ts ↔ private.config()', () => {
  const sql = db();
  afterAll(() => sql.end());

  it('setiap nilai sama persis, dan tidak ada kunci yang hanya ada di salah satu sisi', async () => {
    const [row] = await sql<[{ config: Record<string, unknown> }]>`select private.config() as config`;
    expect(row.config).toEqual(DB_MIRRORED_CONFIG);
  });
});
