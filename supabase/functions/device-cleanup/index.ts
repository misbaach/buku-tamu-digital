// Edge Function device-cleanup (prd.md FR-R-08, 11.5 langkah 6–7; docs/plan.md bagian 5, K34).
// Satu-satunya jalur penghapusan user Auth perangkat (auth.admin.deleteUser); tidak pernah SQL ke auth.users.
//   mode terminate: JWT Admin + deviceId + alasan → RPC admin_revoke_device atas nama Admin (keanggotaan dan
//                   audit diperiksa DB), lalu user Auth dihapus.
//   mode sweep:     header x-cron-secret (secret job di Vault, bukan service role key) → hapus user Auth
//                   perangkat yang jatuh tempo. Idempoten.
import { createClient } from '../_shared/deps.ts';
import { corsHeaders, json, requireEnv, timingSafeEqual } from '../_shared/http.ts';
import { deviceCleanupRequestSchema } from '../_shared/shared/schemas/usher.ts';

const SUPABASE_URL = requireEnv('SUPABASE_URL');
const ANON_KEY = requireEnv('SUPABASE_ANON_KEY');
const service = createClient(SUPABASE_URL, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false, autoRefreshToken: false },
});
const SWEEP_BATCH = 100;
const SWEEP_MAX_BATCHES = 5;

/** User yang sudah tidak ada dianggap berhasil dihapus (idempoten). */
async function deleteAuthUser(id: string): Promise<boolean> {
  const { error } = await service.auth.admin.deleteUser(id);
  return !error || error.status === 404;
}

async function markDeleted(deviceId: string): Promise<boolean> {
  const { error } = await service.rpc('svc_mark_auth_user_deleted', { p_device_id: deviceId });
  return !error;
}

async function sweep(): Promise<{ deleted: number; failed: number }> {
  let deleted = 0;
  let failed = 0;
  for (let batch = 0; batch < SWEEP_MAX_BATCHES; batch++) {
    const { data, error } = await service.rpc('svc_devices_due_for_cleanup', { p_limit: SWEEP_BATCH });
    if (error) throw new Error(`due: ${error.code}`);
    const rows = (data ?? []) as { device_id: string; auth_user_id: string | null }[];
    let progressed = 0;
    for (const row of rows) {
      const ok = (row.auth_user_id === null || (await deleteAuthUser(row.auth_user_id))) && (await markDeleted(row.device_id));
      if (ok) {
        deleted++;
        progressed++;
      } else {
        failed++;
      }
    }
    if (rows.length < SWEEP_BATCH || progressed === 0) break;
  }
  return { deleted, failed };
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req, 'DASHBOARD_ORIGINS');
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return json({ error: 'invalid_request' }, 405, cors);

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return json({ error: 'invalid_request' }, 400, cors);
  }
  const parsed = deviceCleanupRequestSchema.safeParse(raw);
  if (!parsed.success) return json({ error: 'invalid_request' }, 400, cors);
  const input = parsed.data;

  if (input.mode === 'sweep') {
    const secret = Deno.env.get('DEVICE_CLEANUP_CRON_SECRET') ?? '';
    const given = req.headers.get('x-cron-secret') ?? '';
    if (secret.length < 32 || !timingSafeEqual(given, secret)) return json({ error: 'unauthorized' }, 401, cors);
    try {
      return json(await sweep(), 200, cors);
    } catch (e) {
      console.error('device-cleanup sweep gagal', e instanceof Error ? e.message : 'galat');
      return json({ error: 'server_error' }, 500, cors);
    }
  }

  // Mode terminate: hanya dengan JWT Admin; PostgREST memvalidasi JWT dan DB memeriksa keanggotaan acara.
  const authorization = req.headers.get('authorization') ?? '';
  if (!/^Bearer\s+\S+$/i.test(authorization)) return json({ error: 'unauthorized' }, 401, cors);
  const asAdmin = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const revoked = await asAdmin.rpc('admin_revoke_device', {
    p_device_id: input.deviceId,
    p_mode: 'terminate',
    p_reason: input.reason,
  });
  if (revoked.error) {
    const code = revoked.error.code;
    if (code === '42501' || code === 'PGRST301' || code === 'PGRST302') return json({ error: 'forbidden' }, 403, cors);
    if (code === 'P0002') return json({ error: 'not_found' }, 404, cors);
    if (code === '22023') return json({ error: 'invalid_request', message: revoked.error.message }, 400, cors);
    console.error('device-cleanup terminate: admin_revoke_device gagal', code);
    return json({ error: 'server_error' }, 500, cors);
  }

  // Status terminate sudah berlaku (semua push ditolak). Bila penghapusan gagal, sweep berikutnya mengulanginya.
  const { data: authUserId, error } = await service.rpc('svc_terminated_device_user', { p_device_id: input.deviceId });
  if (error) return json({ status: 'terminated', authUserDeleted: false }, 202, cors);
  const removed = (authUserId === null || (await deleteAuthUser(authUserId as string))) && (await markDeleted(input.deviceId));
  return json({ status: 'terminated', authUserDeleted: removed }, removed ? 200 : 202, cors);
});
