import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { checkSpecialNumber } from '@guestbook/shared';
import { SPECIAL_NUMBER_CASES } from '@guestbook/shared/fixtures/special-numbers';
import { db } from './setup.ts';

// FR-C-02: aturan nomor khusus harus identik di Zod (klien), Tinjau Tamu, dan constraint DB.
// Fixture yang sama diuji ke validator TypeScript dan ke database.
describe('paritas aturan Nomor Urut khusus: TypeScript ↔ database', () => {
  const sql = db();
  let eventId = '';

  beforeAll(async () => {
    const [ev] = await sql<[{ id: string }]>`
      insert into public.events (name, event_date) values ('Uji paritas nomor', current_date) returning id`;
    eventId = ev.id;
  });

  afterAll(async () => {
    await sql`delete from public.events where id = ${eventId}`;
    await sql.end();
  });

  it.each(SPECIAL_NUMBER_CASES)('private.special_number_issue($value) = $issue', async ({ value, issue }) => {
    const [row] = await sql<[{ issue: string | null }]>`select private.special_number_issue(${value}) as issue`;
    expect(row.issue).toBe(issue);
    expect(checkSpecialNumber(value)).toBe(issue);
  });

  it.each(SPECIAL_NUMBER_CASES)('constraint guests menerima/menolak $value sesuai aturan', async ({ value, issue }) => {
    const insert = sql`insert into public.guests (event_id, name, special_number) values (${eventId}, 'Uji', ${value})`;
    if (issue === null) {
      await expect(insert).resolves.toBeDefined();
      await sql`delete from public.guests where event_id = ${eventId}`;
    } else {
      await expect(insert).rejects.toMatchObject({ code: '23514' });
    }
  });

  it('nilai huruf kecil ditolak DB (wajib dinormalisasi lebih dulu)', async () => {
    await expect(
      sql`insert into public.guests (event_id, name, special_number) values (${eventId}, 'Uji', 'vip-001')`,
    ).rejects.toMatchObject({ code: '23514', constraint_name: 'guests_special_number_rule' });
  });

  it('prefix setting Nomor Urut yang menghasilkan pola perangkat ditolak DB (FR-C-03)', async () => {
    await expect(
      sql`insert into public.ticket_number_settings (event_id, category, prefix, digits) values (${eventId}, 'vip', 'A-', 3)`,
    ).rejects.toMatchObject({ code: '23514', constraint_name: 'ticket_number_settings_prefix_rule' });
  });
});
