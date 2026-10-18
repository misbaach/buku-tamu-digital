import { fetchGroups, fetchGuests, parseFilters } from '$lib/features/guests/query';

export async function load({ params, url, depends }) {
  depends('app:guests');
  const filters = parseFilters(url);
  return {
    filters,
    groups: await fetchGroups(params.id),
    // Tidak di-await: halaman langsung tampil, skeleton muncul bila lambat.
    result: fetchGuests(params.id, filters),
  };
}
