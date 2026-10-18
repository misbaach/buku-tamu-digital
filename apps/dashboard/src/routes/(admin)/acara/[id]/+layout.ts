import { error } from '@sveltejs/kit';
import { supabase } from '$lib/supabase';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function load({ params, depends }) {
  depends('app:event');
  if (!UUID.test(params.id)) error(404, 'Acara tidak ditemukan.');
  const { data, error: dbError } = await supabase
    .from('events')
    .select('id, name, code, couple_names, event_date, timezone, venue, attendance_limit, archived_at')
    .eq('id', params.id)
    .maybeSingle();
  if (dbError) error(500, 'Acara gagal dimuat.');
  // RLS menyembunyikan acara milik Admin lain, jadi "tidak ada" dan "bukan milik Anda" tampak sama.
  if (!data) error(404, 'Acara tidak ditemukan.');
  return { event: data };
}
