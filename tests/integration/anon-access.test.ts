import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { env } from './setup.ts';

/** Galat PostgREST / GoTrue: cukup kode yang diperiksa tes. */
async function errorBody(res: Response): Promise<{ code?: string; error_code?: string }> {
  return (await res.json()) as { code?: string; error_code?: string };
}

// Kriteria penerimaan (prd.md 16): dengan anon/publishable key saja, tidak ada tabel, RPC, maupun schema lain
// yang bisa dijangkau lewat API.
describe('akses anon lewat HTTP', () => {
  const headers = () => ({ apikey: env().PUBLISHABLE_KEY, 'content-type': 'application/json' });

  it.each(['events', 'guests', 'check_ins', 'ushers', 'devices', 'audit_logs', 'auth_attempts'])(
    'GET /rest/v1/%s ditolak',
    async (table) => {
      const res = await fetch(`${env().API_URL}/rest/v1/${table}?select=*`, { headers: headers() });
      expect(res.status).toBe(401);
      expect((await errorBody(res)).code).toBe('42501');
    },
  );

  it('menulis tabel ditolak', async () => {
    const res = await fetch(`${env().API_URL}/rest/v1/guests`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ name: 'Penyusup' }),
    });
    expect(res.status).toBe(401);
  });

  it('schema private tidak bisa dipanggil lewat API', async () => {
    const res = await fetch(`${env().API_URL}/rest/v1/rpc/config`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Profile': 'private' },
      body: '{}',
    });
    expect(res.status).toBe(406);
    expect((await errorBody(res)).code).toBe('PGRST106');
  });

  it('schema net (pg_net) tidak bisa dipanggil lewat API (T-028)', async () => {
    const res = await fetch(`${env().API_URL}/rest/v1/rpc/http_post`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Profile': 'net' },
      body: JSON.stringify({ url: 'https://example.com' }),
    });
    expect(res.status).toBe(406);
    expect((await errorBody(res)).code).toBe('PGRST106');
  });

  it('GraphQL tidak diekspos', async () => {
    const res = await fetch(`${env().API_URL}/graphql/v1`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ query: '{ __typename }' }),
    });
    expect(res.status).toBe(406);
  });

  it('pendaftaran akun publik ditolak (sign-up dimatikan)', async () => {
    const res = await fetch(`${env().API_URL}/auth/v1/signup`, {
      method: 'POST',
      headers: headers(),
      // Kata sandi acak saat runtime: tidak ada literal mirip rahasia di repo.
      body: JSON.stringify({ email: 'penyusup@test.local', password: `P${randomUUID()}` }),
    });
    expect(res.status).toBe(422);
    expect((await errorBody(res)).error_code).toBe('signup_disabled');
  });

  it('login anonim (anonymous sign-in) ditolak', async () => {
    const res = await fetch(`${env().API_URL}/auth/v1/signup`, {
      method: 'POST',
      headers: headers(),
      body: '{}',
    });
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});
