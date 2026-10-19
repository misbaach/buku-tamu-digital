import { error } from '@sveltejs/kit';
import type { PrintTicket } from '@guestbook/shared';
import { supabase } from '$lib/supabase';

export async function load({ params, depends }) {
  depends('app:checkin-settings');
  const { data, error: dbError } = await supabase
    .from('checkin_settings')
    .select('show_verification, allow_multi_checkin, print_ticket')
    .eq('event_id', params.id)
    .maybeSingle();
  if (dbError) throw dbError;
  if (!data) error(404, 'Pengaturan acara tidak ditemukan.');
  return { settings: { ...data, print_ticket: data.print_ticket as unknown as PrintTicket } };
}
