import type { AuthError, Session } from '@supabase/supabase-js';
import { supabase } from './supabase';

export async function currentSession(): Promise<Session | null> {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

/**
 * Hanya untuk UX (menolak masuk lebih awal dengan pesan yang jelas). Penegak sebenarnya adalah RLS di
 * database, yang membaca app_metadata dari JWT; user_metadata tidak pernah dipakai (prd.md 10.4).
 */
export function isAdminSession(session: Session | null): boolean {
  return session?.user.app_metadata?.role === 'admin';
}

/** Tujuan setelah login dari `?ke=`. Hanya path internal; URL lain jatuh ke beranda (cegah open redirect). */
export function safeNextPath(raw: string | null): string {
  if (!raw || !raw.startsWith('/') || raw.startsWith('//') || raw.includes('\\') || raw.startsWith('/masuk')) {
    return '/';
  }
  return raw;
}

export function loginErrorMessage(error: AuthError): string {
  if (error.code === 'invalid_credentials') return 'Email atau kata sandi salah.';
  if (error.status === 429 || error.code === 'over_request_rate_limit') {
    return 'Terlalu banyak percobaan masuk. Tunggu beberapa menit, lalu coba lagi.';
  }
  if (error.name === 'AuthRetryableFetchError' || error.status === 0) {
    return 'Tidak dapat terhubung ke server. Periksa koneksi internet, lalu coba lagi.';
  }
  return 'Gagal masuk. Coba lagi; bila terus terjadi, hubungi operator.';
}
