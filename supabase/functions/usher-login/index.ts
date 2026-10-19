// Edge Function usher-login (prd.md 11.5 langkah 3–4, FR-R-02, FR-R-09; docs/plan.md bagian 9).
// Satu-satunya pintu masuk usher. verify_jwt = false: kredensialnya Kode Acara + PIN atau token QR.
import { createClient } from '../_shared/deps.ts';
import { clientIp, corsHeaders, json, padUntil, randomPassword, requireEnv } from '../_shared/http.ts';
import { USHER_LOGIN_FAIL_MIN_MS } from '../_shared/shared/config.ts';
import { normalizeEventCode, parsePin } from '../_shared/shared/patterns.ts';
import {
  deviceEmail,
  usherLoginRequestSchema,
  type UsherLoginError,
  type UsherLoginSuccess,
} from '../_shared/shared/schemas/usher.ts';

const SUPABASE_URL = requireEnv('SUPABASE_URL');
const service = createClient(SUPABASE_URL, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false, autoRefreshToken: false },
});
const ANON_KEY = requireEnv('SUPABASE_ANON_KEY');

interface LoginOutcome {
  outcome: 'ok' | 'invalid' | 'blocked' | 'archived' | 'session_ended' | 'capacity';
  retry_after?: number;
  device_id?: string;
  device_code?: string;
  event_id?: string;
  event_name?: string;
  usher_id?: string;
  usher_name?: string;
  usher_mode?: 'check_in' | 'check_out';
  session_expires_at?: string;
}

Deno.serve(async (req) => {
  const cors = corsHeaders(req, 'USHER_APP_ORIGINS');
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  const started = performance.now();

  // Semua respons gagal ditahan sampai waktu minimal yang sama (FR-R-02: waktu diseragamkan).
  const fail = async (status: number, body: UsherLoginError, extra: Record<string, string> = {}) => {
    await padUntil(started, USHER_LOGIN_FAIL_MIN_MS);
    return json(body, status, cors, extra);
  };
  if (req.method !== 'POST') return fail(405, { error: 'invalid_request' });

  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return fail(400, { error: 'invalid_request' });
  }
  const parsed = usherLoginRequestSchema.safeParse(raw);
  if (!parsed.success) return fail(400, { error: 'invalid_request' });
  const input = parsed.data;
  const ip = clientIp(req);

  // PIN yang formatnya tidak bisa diurai tetap dikirim ke DB sebagai selector/rahasia kosong: DB tetap
  // menjalankan bcrypt dummy sehingga respons dan waktunya identik dengan PIN salah.
  const pin = input.method === 'pin' ? parsePin(input.pin) : null;
  const { data, error } = await service.rpc('svc_usher_login', {
    p_method: input.method,
    p_ip: ip,
    p_event_code: input.method === 'pin' ? normalizeEventCode(input.eventCode) : null,
    p_selector: pin?.selector ?? '',
    p_secret: pin?.secret ?? '',
    p_token: input.method === 'qr' ? input.token : null,
    p_device_name: input.device.name,
    p_app_version: input.device.appVersion,
  });
  if (error || !data) {
    console.error('usher-login: svc_usher_login gagal', error?.code ?? 'tanpa data');
    return fail(500, { error: 'server_error' });
  }
  const result = data as LoginOutcome;

  switch (result.outcome) {
    case 'invalid':
      return fail(401, { error: 'invalid_credentials' });
    case 'blocked':
      return fail(429, { error: 'too_many_attempts', retryAfter: result.retry_after }, {
        'Retry-After': String(result.retry_after ?? 60),
      });
    case 'archived':
      return fail(403, { error: 'event_archived' });
    case 'session_ended':
      return fail(403, { error: 'session_ended' });
    case 'capacity':
      return fail(403, { error: 'device_capacity' });
    case 'ok':
      break;
    default:
      return fail(500, { error: 'server_error' });
  }

  // (4) User Auth khusus perangkat. app_metadata hanya bisa ditulis service role (aturan 3).
  const deviceId = result.device_id!;
  const email = deviceEmail(deviceId);
  const password = randomPassword();
  let authUserId: string | undefined;
  try {
    const created = await service.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { role: 'usher', event_id: result.event_id, usher_id: result.usher_id, device_id: deviceId },
    });
    if (created.error || !created.data.user) throw new Error(`createUser: ${created.error?.status ?? '?'}`);
    authUserId = created.data.user.id;

    const attached = await service.rpc('svc_attach_device_user', { p_device_id: deviceId, p_auth_user_id: authUserId });
    if (attached.error) throw new Error(`attach: ${attached.error.code}`);

    const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const signed = await client.auth.signInWithPassword({ email, password });
    if (signed.error || !signed.data.session) throw new Error(`signIn: ${signed.error?.status ?? '?'}`);
    const s = signed.data.session;

    const body: UsherLoginSuccess = {
      session: {
        accessToken: s.access_token,
        refreshToken: s.refresh_token,
        expiresAt: s.expires_at ?? 0,
        expiresIn: s.expires_in,
      },
      device: { id: deviceId, code: result.device_code! },
      event: { id: result.event_id!, name: result.event_name! },
      usher: { name: result.usher_name!, mode: result.usher_mode! },
      sessionExpiresAt: result.session_expires_at!,
    };
    return json(body, 200, cors);
  } catch (e) {
    // (6) Gagal setelah perangkat terdaftar: hapus user Auth yang sempat dibuat dan batalkan perangkat.
    console.error('usher-login: pendaftaran perangkat dibatalkan', e instanceof Error ? e.message : 'galat');
    if (authUserId) await service.auth.admin.deleteUser(authUserId);
    await service.rpc('svc_abort_device', { p_device_id: deviceId });
    return fail(500, { error: 'server_error' });
  }
});
