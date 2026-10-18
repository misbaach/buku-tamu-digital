import postgres from 'postgres';
import { localSupabaseEnv, type LocalSupabaseEnv } from '../../scripts/local-supabase-env.mjs';

let cached: LocalSupabaseEnv | undefined;

export function env(): LocalSupabaseEnv {
  cached ??= localSupabaseEnv();
  return cached;
}

/** Koneksi langsung ke Postgres lokal (role postgres) untuk menyiapkan data dan membaca katalog. */
export function db() {
  return postgres(env().DB_URL, { onnotice: () => {}, max: 1 });
}
