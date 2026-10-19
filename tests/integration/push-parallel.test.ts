// Dua perangkat mengirim check-in tamu yang sama secara bersamaan → tepat satu accepted (12.3 poin 7, T-013).
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { pushResponseSchema } from '@guestbook/shared';
import { db } from './setup.ts';
import { createEventWithUsher, loginDevice, rpc, type DeviceLogin, type Sql } from './usher-helpers.ts';

describe('push_outbox paralel', () => {
  let sql: Sql;
  let a: DeviceLogin;
  let b: DeviceLogin;
  let guests: string[];

  beforeAll(async () => {
    sql = db();
    const ctx = await createEventWithUsher(sql, { name: 'Acara Paralel' });
    a = await loginDevice(ctx.code, ctx.pin, 'HP A');
    b = await loginDevice(ctx.code, ctx.pin, 'HP B');
    const rows = await sql<{ id: string }[]>`
      insert into public.guests (event_id, name, category, special_number)
      select ${ctx.eventId}, 'VVIP ' || i, 'vvip', 'VVIP-' || lpad(i::text, 3, '0') from generate_series(1, 20) i returning id`;
    guests = rows.map((r) => r.id);
  });
  afterAll(() => sql.end());

  it('20 tamu VVIP dikirim serentak dari dua perangkat: setiap tamu tepat satu accepted dan satu duplicate', async () => {
    const item = (d: DeviceLogin, guestId: string, i: number) => ({
      id: randomUUID(),
      guestId,
      actualPax: 1,
      ticketNumber: `VVIP-${String(i + 1).padStart(3, '0')}`,
      deviceId: d.device.id,
      checkedInAt: new Date().toISOString(),
    });
    const [ra, rb] = await Promise.all([
      rpc(a.session.accessToken, 'push_outbox', { p_items: guests.map((g, i) => item(a, g, i)) }),
      rpc(b.session.accessToken, 'push_outbox', { p_items: guests.map((g, i) => item(b, g, i)) }),
    ]);
    const pa = pushResponseSchema.parse(ra.data);
    const pb = pushResponseSchema.parse(rb.data);
    for (let i = 0; i < guests.length; i++) {
      const statuses = [pa.results[i], pb.results[i]].map((r) => (r && 'status' in r ? r.status : r?.code)).sort();
      expect(statuses).toEqual(['accepted', 'duplicate']);
    }
    const [{ n }] = await sql<[{ n: number }]>`
      select count(*)::int as n from public.check_ins where guest_id = any(${guests}) and status = 'accepted'`;
    expect(n).toBe(guests.length);
  });
});
