// Edge Function usher-login ujung ke ujung (FR-R-02, FR-R-09, plan.md bagian 9 & 14).
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { USHER_LOGIN_FAIL_MIN_MS, pullResponseSchema } from '@guestbook/shared';
import { db } from './setup.ts';
import { createEventWithUsher, login, randomIp, rpc, type Sql } from './usher-helpers.ts';

describe('usher-login', () => {
  let sql: Sql;
  let ctx: Awaited<ReturnType<typeof createEventWithUsher>>;

  beforeAll(async () => {
    sql = db();
    ctx = await createEventWithUsher(sql, { name: 'Acara Login Integrasi' });
    await sql`insert into public.ushers (event_id, name, pin_selector, pin_hash, is_active)
              values (${ctx.eventId}, 'Usher Nonaktif', 'CD', private.hash_secret('ABCDEFGH'), false)`;
    await sql`insert into public.guests (event_id, name, phone, notes) values (${ctx.eventId}, 'Tamu Rahasia', '0812999888', 'jangan bocor')`;
  });
  afterAll(() => sql.end());

  it('PIN sah: sesi perangkat dengan klaim di app_metadata, lalu pull_snapshot tanpa data sensitif', async () => {
    const r = await login({
      method: 'pin',
      eventCode: ctx.code.toLowerCase(),
      pin: ctx.pin.toLowerCase(),
      device: { name: 'HP A' },
    });
    expect(r.status).toBe(200);
    expect(r.json.device.code).toBe('A');
    const claims = JSON.parse(Buffer.from(r.json.session.accessToken.split('.')[1], 'base64url').toString());
    expect(claims.app_metadata).toMatchObject({ role: 'usher', event_id: ctx.eventId, device_id: r.json.device.id });
    expect(claims.user_metadata ?? {}).not.toHaveProperty('role');

    const pull = await rpc(r.json.session.accessToken, 'pull_snapshot');
    expect(pull.status).toBe(200);
    const parsed = pullResponseSchema.parse(pull.data); // .strict(): kunci tambahan membuat parse gagal
    expect(parsed.status).toBe('ok');
    expect(JSON.stringify(pull.data)).not.toMatch(/0812999888|jangan bocor/);
  });

  it('semua penyebab gagal kredensial menghasilkan 401 identik dengan waktu yang diseragamkan', async () => {
    const ip = randomIp();
    const cases = [
      { method: 'pin', eventCode: 'ZZZZZZ', pin: ctx.pin },
      { method: 'pin', eventCode: ctx.code, pin: 'XY-ABCD-EFGH' },
      { method: 'pin', eventCode: ctx.code, pin: 'CD-ABCD-EFGH' },
      { method: 'pin', eventCode: ctx.code, pin: 'AB-ABCD-EFGX' },
      { method: 'pin', eventCode: ctx.code, pin: '12' },
      { method: 'qr', token: 'token-yang-tidak-ada' },
    ];
    const results = [];
    for (const body of cases) results.push(await login(body, ip));
    for (const r of results) {
      expect(r.status).toBe(401);
      expect(r.text).toBe(results[0]?.text);
      expect(r.ms).toBeGreaterThanOrEqual(USHER_LOGIN_FAIL_MIN_MS - 5);
    }
    expect(results[0]?.json).toEqual({ error: 'invalid_credentials' });
    const times = results.map((r) => r.ms);
    expect(Math.max(...times) - Math.min(...times)).toBeLessThan(250);
  });

  it('10 gagal dari (IP + Kode Acara) → 429 dengan retryAfter, Kode Acara lain dari IP itu tetap bisa', async () => {
    const ip = randomIp();
    for (let i = 0; i < 10; i++) {
      expect((await login({ method: 'pin', eventCode: ctx.code, pin: 'AB-ABCD-EFGX' }, ip)).status).toBe(401);
    }
    const blocked = await login({ method: 'pin', eventCode: ctx.code, pin: ctx.pin }, ip);
    expect(blocked.status).toBe(429);
    expect(blocked.json.error).toBe('too_many_attempts');
    expect(blocked.json.retryAfter).toBeGreaterThan(0);
    expect(Number(blocked.headers.get('retry-after'))).toBe(blocked.json.retryAfter);

    const other = await createEventWithUsher(sql, { name: 'Acara Tetangga' });
    expect((await login({ method: 'pin', eventCode: other.code, pin: other.pin }, ip)).status).toBe(200);
  });

  it('body tidak valid → 400; acara diarsipkan → 403 hanya setelah kredensial sah', async () => {
    expect((await login({ method: 'sms' })).status).toBe(400);
    const archived = await createEventWithUsher(sql, { name: 'Acara Diarsipkan' });
    await sql`update public.events set archived_at = now() where id = ${archived.eventId}`;
    expect((await login({ method: 'pin', eventCode: archived.code, pin: 'AB-ABCD-EFGX' })).status).toBe(401);
    const r = await login({ method: 'pin', eventCode: archived.code, pin: archived.pin });
    expect(r.status).toBe(403);
    expect(r.json).toEqual({ error: 'event_archived' });
  });
});
