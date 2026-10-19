import { fetchGroups, fetchGuests, parseFilters } from '$lib/features/guests/query';
import { supabase } from '$lib/supabase';

export async function load({ params, url, depends }) {
  depends('app:guests');
  const filters = parseFilters(url);
  return {
    filters,
    groups: await fetchGroups(params.id),
    // Total undangan untuk petunjuk batas jumlah hadir (D14). Tidak di-await.
    invitedTotal: supabase
      .rpc('get_event_stats', { p_event_id: params.id })
      .then(({ data }) => (data as { invitedTotal?: number } | null)?.invitedTotal ?? null),
    // Tidak di-await: halaman langsung tampil, skeleton muncul bila lambat.
    result: fetchGuests(params.id, filters),
  };
}
