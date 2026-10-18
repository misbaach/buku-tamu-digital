// Membaca URL dan kunci PUBLIK Supabase lokal dari `supabase status` saat runtime (docs/decisions.md T-012).
// Kunci service role / secret sengaja TIDAK diambil: kode di luar Edge Functions tidak boleh memegangnya.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { delimiter, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ALLOWED = ['API_URL', 'PUBLISHABLE_KEY', 'DB_URL', 'FUNCTIONS_URL', 'STUDIO_URL'];

function withDockerOnPath(env) {
  // Docker Desktop di Windows kadang belum ada di PATH sesi yang sudah terbuka sebelum Docker dipasang.
  const dockerBin = 'C:\\Program Files\\Docker\\Docker\\resources\\bin';
  if (process.platform === 'win32' && existsSync(dockerBin) && !(env.PATH ?? env.Path ?? '').includes(dockerBin)) {
    const key = env.Path !== undefined ? 'Path' : 'PATH';
    return { ...env, [key]: `${env[key] ?? ''}${delimiter}${dockerBin}` };
  }
  return env;
}

/** @returns {{ API_URL: string, PUBLISHABLE_KEY: string, DB_URL: string, FUNCTIONS_URL: string, STUDIO_URL: string }} */
export function localSupabaseEnv() {
  const cli = createRequire(join(root, 'package.json')).resolve('supabase/dist/supabase.js');
  let out;
  try {
    out = execFileSync(process.execPath, [cli, 'status', '-o', 'env'], {
      cwd: root,
      env: withDockerOnPath(process.env),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    throw new Error('Supabase lokal belum berjalan. Jalankan `pnpm db:start` lebih dulu.');
  }
  const env = {};
  for (const line of out.split(/\r?\n/)) {
    const m = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim());
    if (m && ALLOWED.includes(m[1])) env[m[1]] = m[2];
  }
  for (const k of ALLOWED) if (!env[k]) throw new Error(`supabase status tidak mengembalikan ${k}`);
  return env;
}

// Pemakaian CLI: `node scripts/local-supabase-env.mjs -- <perintah>` menjalankan perintah dengan
// PUBLIC_SUPABASE_URL dan PUBLIC_SUPABASE_PUBLISHABLE_KEY terisi, tanpa menulis file .env.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const sep = process.argv.indexOf('--');
  const cmd = sep >= 0 ? process.argv.slice(sep + 1) : [];
  if (cmd.length === 0) {
    console.error('Pemakaian: node scripts/local-supabase-env.mjs -- <perintah> [argumen...]');
    process.exit(2);
  }
  const env = localSupabaseEnv();
  const { spawnSync } = await import('node:child_process');
  const r = spawnSync(cmd[0], cmd.slice(1), {
    stdio: 'inherit',
    shell: process.platform === 'win32',
    env: { ...process.env, PUBLIC_SUPABASE_URL: env.API_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY: env.PUBLISHABLE_KEY },
  });
  process.exit(r.status ?? 1);
}
