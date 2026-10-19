// Secret KHUSUS Supabase lokal untuk job device-cleanup (docs/plan.md bagian 5; prd.md 11.4).
//   --env    membuat/melengkapi supabase/functions/.env (di-gitignore): secret job acar + origin CORS lokal.
//            Edge runtime membaca file ini saat `supabase start`, jadi jalankan sebelum start.
//   --vault  menulis URL fungsi dan secret job yang sama ke Supabase Vault lokal (hilang setiap db reset).
// Produksi tidak memakai skrip ini: operator mengisi Vault dan secret Edge Function (docs/progress.md).
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
export const FUNCTIONS_ENV = join(root, 'supabase/functions/.env');
const LOCAL_FUNCTION_URL = 'http://kong:8000/functions/v1/device-cleanup';

const DEFAULTS = {
  DEVICE_CLEANUP_CRON_SECRET: () => randomBytes(32).toString('hex'),
  USHER_APP_ORIGINS: () => 'http://localhost:5174,http://127.0.0.1:5174',
  DASHBOARD_ORIGINS: () =>
    'http://localhost:5173,http://127.0.0.1:5173,http://localhost:8788,http://127.0.0.1:8788,http://localhost:4173,http://127.0.0.1:4173',
};

/** @returns {Record<string, string>} */
export function readFunctionsEnv() {
  if (!existsSync(FUNCTIONS_ENV)) return {};
  const env = {};
  for (const line of readFileSync(FUNCTIONS_ENV, 'utf8').split(/\r?\n/)) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (m) env[m[1]] = m[2];
  }
  return env;
}

function ensureEnvFile() {
  const env = readFunctionsEnv();
  const missing = Object.keys(DEFAULTS).filter((k) => !env[k]);
  if (missing.length === 0) return false;
  for (const k of missing) env[k] = DEFAULTS[k]();
  const lines = Object.keys(DEFAULTS).map((k) => `${k}=${env[k]}`);
  writeFileSync(
    FUNCTIONS_ENV,
    `# Dibuat scripts/local-secrets.mjs. HANYA untuk Supabase lokal; di-gitignore, jangan disalin ke produksi.\n${lines.join('\n')}\n`,
  );
  return true;
}

async function writeVault() {
  const { default: postgres } = await import('postgres');
  const { localSupabaseEnv } = await import('./local-supabase-env.mjs');
  const secret = readFunctionsEnv().DEVICE_CLEANUP_CRON_SECRET;
  if (!secret) throw new Error('supabase/functions/.env belum ada. Jalankan `pnpm db:start`.');
  const sql = postgres(localSupabaseEnv().DB_URL, { onnotice: () => {}, max: 1 });
  try {
    for (const [name, value] of [
      ['device_cleanup_url', LOCAL_FUNCTION_URL],
      ['device_cleanup_cron_secret', secret],
    ]) {
      const [row] = await sql`select id from vault.secrets where name = ${name}`;
      if (row) await sql`select vault.update_secret(${row.id}, ${value})`;
      else await sql`select vault.create_secret(${value}, ${name}, 'Job device-cleanup (lokal)')`;
    }
  } finally {
    await sql.end();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--env') && ensureEnvFile()) {
    console.log(
      'supabase/functions/.env dibuat. Bila Supabase sedang berjalan, jalankan `pnpm db:stop` lalu `pnpm db:start`.',
    );
  }
  if (process.argv.includes('--vault')) {
    await writeVault();
    console.log('Secret Vault job device-cleanup (lokal) terisi.');
  }
}
