import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@guestbook/shared/database.types';
import { ADMIN } from './helpers';

type GuestInsert = Database['public']['Tables']['guests']['Insert'];

let client: Promise<SupabaseClient<Database>> | undefined;

/** Klien Supabase sebagai Admin seed (publishable key + login), sekali per proses tes. Bukan service role. */
export function adminApi(): Promise<SupabaseClient<Database>> {
  client ??= (async () => {
    const url = process.env.PUBLIC_SUPABASE_URL;
    const key = process.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) throw new Error('Jalankan tes lewat `pnpm test:e2e` agar env Supabase lokal terisi.');
    const sb = createClient<Database>(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { error } = await sb.auth.signInWithPassword(ADMIN);
    if (error) throw error;
    return sb;
  })();
  return client;
}

/** Acara baru milik Admin seed, terisolasi dari tes lain. */
export async function createEvent(name: string, guests: Omit<GuestInsert, 'event_id'>[] = []): Promise<string> {
  const sb = await adminApi();
  const today = new Date().toISOString().slice(0, 10);
  const { data: id, error } = await sb.rpc('admin_create_event', { p_name: name, p_event_date: today });
  if (error) throw error;
  if (guests.length > 0) {
    const { error: insertError } = await sb.from('guests').insert(
      guests.map((g) => ({ ...g, event_id: id })),
      // Kolom yang tidak disebut memakai DEFAULT, bukan NULL (bawaan PostgREST untuk insert banyak baris).
      { defaultToNull: false },
    );
    if (insertError) throw insertError;
  }
  return id;
}

export const uniqueName = (prefix: string) => `${prefix} ${Date.now().toString(36)}`;
