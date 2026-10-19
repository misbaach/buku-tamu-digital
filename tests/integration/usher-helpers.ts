// Helper tes integrasi M2: semua panggilan lewat gateway Supabase lokal (Kong) seperti klien sungguhan.
// Tidak memakai service role key; data disiapkan lewat koneksi postgres langsung (setup.ts).
import { randomInt } from 'node:crypto';
import { db, env } from './setup.ts';

export type Sql = ReturnType<typeof db>;

export const ADMIN = { email: 'admin@buku-tamu.test', password: 'admin-lokal-2026' };
export const SECRET = 'ABCDEFGH';

/** IP acak per tes agar blokir (berlaku 15 menit) dari tes lain tidak saling memengaruhi. */
export function randomIp(): string {
  return `10.${randomInt(1, 255)}.${randomInt(1, 255)}.${randomInt(1, 255)}`;
}

function headers(token?: string): Record<string, string> {
  return {
    apikey: env().PUBLISHABLE_KEY,
    'content-type': 'application/json',
    ...(token ? { authorization: `Bearer ${token}` } : {}),
  };
}

export async function callFunction(name: string, body: unknown, extra: Record<string, string> = {}) {
  const started = performance.now();
  const res = await fetch(`${env().API_URL}/functions/v1/${name}`, {
    method: 'POST',
    headers: { ...headers(), ...extra },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return {
    status: res.status,
    text,
    json: text ? JSON.parse(text) : null,
    ms: performance.now() - started,
    headers: res.headers,
  };
}

export function login(body: unknown, ip = randomIp()) {
  return callFunction('usher-login', body, { 'cf-connecting-ip': ip });
}

export async function rpc<T = unknown>(token: string, name: string, args: Record<string, unknown> = {}) {
  const res = await fetch(`${env().API_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: headers(token),
    body: JSON.stringify(args),
  });
  const text = await res.text();
  return { status: res.status, data: (text ? JSON.parse(text) : null) as T };
}

export async function adminToken(): Promise<string> {
  const res = await fetch(`${env().API_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify(ADMIN),
  });
  if (!res.ok) throw new Error(`login Admin gagal: ${res.status}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

/** Acara baru milik Admin seed + satu usher dengan rahasia PIN yang diketahui. */
export async function createEventWithUsher(sql: Sql, opts: { name?: string; selector?: string } = {}) {
  const selector = opts.selector ?? 'AB';
  const [{ id: adminId }] = await sql<[{ id: string }]>`select id from auth.users where email = ${ADMIN.email}`;
  const [event] = await sql<[{ id: string; code: string }]>`
    insert into public.events (name, event_date, created_by)
    values (${opts.name ?? 'Acara Integrasi'}, current_date, ${adminId}) returning id, code`;
  await sql`insert into public.event_members (event_id, user_id) values (${event.id}, ${adminId})`;
  await sql`insert into public.checkin_settings (event_id) values (${event.id})`;
  await sql`insert into public.greeting_configs (event_id, category) values (${event.id}, 'regular'), (${event.id}, 'vip'), (${event.id}, 'vvip')`;
  const [usher] = await sql<[{ id: string }]>`
    insert into public.ushers (event_id, name, pin_selector, pin_hash)
    values (${event.id}, 'Usher Integrasi', ${selector}, private.hash_secret(${SECRET})) returning id`;
  return {
    eventId: event.id,
    code: event.code,
    usherId: usher.id,
    pin: `${selector}-${SECRET.slice(0, 4)}-${SECRET.slice(4)}`,
  };
}

export interface DeviceLogin {
  session: { accessToken: string; refreshToken: string };
  device: { id: string; code: string };
}

export async function loginDevice(code: string, pin: string, name = 'HP Uji'): Promise<DeviceLogin> {
  const r = await login({ method: 'pin', eventCode: code, pin, device: { name, appVersion: '0.0.1' } });
  if (r.status !== 200) throw new Error(`login perangkat gagal: ${r.status} ${r.text}`);
  return r.json as DeviceLogin;
}
