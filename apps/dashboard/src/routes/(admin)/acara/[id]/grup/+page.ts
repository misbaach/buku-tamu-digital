import { supabase } from '$lib/supabase';

export async function load({ params, depends }) {
  depends('app:groups');
  const { data, error } = await supabase
    .from('guest_groups')
    .select('id, name, description, guests(count)')
    .eq('event_id', params.id)
    .is('deleted_at', null)
    .is('guests.deleted_at', null)
    .order('name');
  if (error) throw error;
  return {
    groups: data.map((g) => ({
      id: g.id,
      name: g.name,
      description: g.description,
      members: (g.guests as unknown as { count: number }[])[0]?.count ?? 0,
    })),
  };
}
