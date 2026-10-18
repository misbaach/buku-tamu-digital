import { redirect } from '@sveltejs/kit';
import { currentSession, isAdminSession } from '$lib/auth';
import { supabase } from '$lib/supabase';

// Penjaga rute. Ini hanya UX: tanpa sesi Admin, RLS di database tetap menolak semua data.
export async function load({ url }) {
  const session = await currentSession();
  if (!session) {
    redirect(307, `/masuk?ke=${encodeURIComponent(url.pathname + url.search)}`);
  }
  if (!isAdminSession(session)) {
    await supabase.auth.signOut();
    redirect(307, '/masuk?alasan=bukan-admin');
  }
  return { email: session.user.email ?? '' };
}
