// Edge Function device-cleanup dan job pg_cron (FR-R-08, 11.5 langkah 6–7, K26, K34).
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { readFunctionsEnv } from '../../scripts/local-secrets.mjs';
import { db, env } from './setup.ts';
import { adminToken, callFunction, createEventWithUsher, loginDevice, rpc, type Sql } from './usher-helpers.ts';

async function refresh(refreshToken: string) {
  const res = await fetch(`${env().API_URL}/auth/v1/token?grant_type=refresh_token`, {
    method: 'POST',
    headers: { apikey: env().PUBLISHABLE_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  return res.status;
}

async function authUserExists(sql: Sql, deviceId: string): Promise<boolean> {
  const [row] = await sql<[{ n: number }]>`
    select count(*)::int as n from auth.users u join public.devices d on d.auth_user_id = u.id where d.id = ${deviceId}`;
  return row.n === 1;
}

describe('device-cleanup', () => {
  let sql: Sql;
  let token: string;
  let ctx: Awaited<ReturnType<typeof createEventWithUsher>>;
  const cronSecret = () => readFunctionsEnv().DEVICE_CLEANUP_CRON_SECRET ?? '';

  beforeAll(async () => {
    sql = db();
    token = await adminToken();
    ctx = await createEventWithUsher(sql, { name: 'Acara Cleanup' });
  });
  afterAll(() => sql.end());

  it('terminate: Admin acara lain ditolak; Admin acara sendiri → terminate, audit, user Auth hilang, refresh gagal, push ditolak', async () => {
    const dev = await loginDevice(ctx.code, ctx.pin, 'HP Hilang');

    // Admin seed dicabut keanggotaannya sementara agar berperan sebagai "Admin acara lain".
    await sql`delete from public.event_members where event_id = ${ctx.eventId}`;
    const denied = await callFunction(
      'device-cleanup',
      { mode: 'terminate', deviceId: dev.device.id, reason: 'uji' },
      { authorization: `Bearer ${token}` },
    );
    expect(denied.status).toBe(403);
    expect(await authUserExists(sql, dev.device.id)).toBe(true);
    await sql`insert into public.event_members (event_id, user_id) select ${ctx.eventId}, id from auth.users where email = 'admin@buku-tamu.test'`;

    const noJwt = await callFunction('device-cleanup', { mode: 'terminate', deviceId: dev.device.id, reason: 'uji' });
    expect(noJwt.status).toBe(401);

    const r = await callFunction(
      'device-cleanup',
      { mode: 'terminate', deviceId: dev.device.id, reason: 'HP hilang di parkiran' },
      { authorization: `Bearer ${token}` },
    );
    expect(r.status).toBe(200);
    expect(r.json).toEqual({ status: 'terminated', authUserDeleted: true });

    const [device] = await sql<[{ revoke_mode: string; auth_user_deleted_at: Date | null }]>`
      select revoke_mode, auth_user_deleted_at from public.devices where id = ${dev.device.id}`;
    expect(device.revoke_mode).toBe('terminate');
    expect(device.auth_user_deleted_at).not.toBeNull();
    const audit =
      await sql`select after from public.audit_logs where action = 'device_revoked' and entity_id = ${dev.device.id}`;
    expect(audit.map((a) => a.after.mode)).toEqual(['terminate']);
    expect(await authUserExists(sql, dev.device.id)).toBe(false);
    expect(await refresh(dev.session.refreshToken)).toBeGreaterThanOrEqual(400);

    // Access token lama masih lolos verifikasi JWT, tetapi DB menolak setiap push (11.5 langkah 5).
    const push = await rpc(dev.session.accessToken, 'push_outbox', {
      p_items: [
        {
          id: randomUUID(),
          guestId: randomUUID(),
          actualPax: 1,
          ticketNumber: `${dev.device.code}-001`,
          deviceId: dev.device.id,
          checkedInAt: new Date().toISOString(),
        },
      ],
    });
    expect(push.data).toEqual({ status: 'rejected', reason: 'terminated', results: [] });
  });

  it('sweep: tanpa/dengan secret salah → 401; dengan secret hanya perangkat jatuh tempo yang dibersihkan; idempoten', async () => {
    const due = await loginDevice(ctx.code, ctx.pin, 'HP Kemarin');
    const active = await loginDevice(ctx.code, ctx.pin, 'HP Aktif');
    await sql`update public.devices set session_expires_at = now() - interval '73 hours' where id = ${due.device.id}`;

    expect((await callFunction('device-cleanup', { mode: 'sweep' })).status).toBe(401);
    expect((await callFunction('device-cleanup', { mode: 'sweep' }, { 'x-cron-secret': 'x'.repeat(64) })).status).toBe(
      401,
    );

    const first = await callFunction('device-cleanup', { mode: 'sweep' }, { 'x-cron-secret': cronSecret() });
    expect(first.status).toBe(200);
    expect(first.json.failed).toBe(0);
    expect(await authUserExists(sql, due.device.id)).toBe(false);
    expect(await authUserExists(sql, active.device.id)).toBe(true);

    const second = await callFunction('device-cleanup', { mode: 'sweep' }, { 'x-cron-secret': cronSecret() });
    expect(second.json).toEqual({ deleted: 0, failed: 0 });
  });

  it('pg_cron benar-benar memanggil fungsi lewat pg_net dengan secret dari Vault', async () => {
    const dev = await loginDevice(ctx.code, ctx.pin, 'HP Cron');
    await sql`update public.devices set session_expires_at = now() - interval '73 hours' where id = ${dev.device.id}`;
    const job = `uji-cleanup-${randomUUID().slice(0, 8)}`;
    // Perintah yang sama dengan job device-cleanup-sweep, dijadwalkan tiap 2 detik hanya selama tes.
    const [{ command }] = await sql<
      [{ command: string }]
    >`select command from cron.job where jobname = 'device-cleanup-sweep'`;
    await sql`select cron.schedule(${job}, '2 seconds', ${command})`;
    try {
      let deletedAt: Date | null = null;
      for (let i = 0; i < 30 && !deletedAt; i++) {
        await new Promise((r) => setTimeout(r, 1000));
        [{ auth_user_deleted_at: deletedAt }] = await sql<[{ auth_user_deleted_at: Date | null }]>`
          select auth_user_deleted_at from public.devices where id = ${dev.device.id}`;
      }
      expect(deletedAt).not.toBeNull();
      const [{ n }] = await sql<[{ n: number }]>`
        select count(*)::int as n from net._http_response where status_code = 200 and created > now() - interval '1 minute'`;
      expect(n).toBeGreaterThan(0);
    } finally {
      await sql`select cron.unschedule(${job})`;
    }
  }, 60_000);
});
