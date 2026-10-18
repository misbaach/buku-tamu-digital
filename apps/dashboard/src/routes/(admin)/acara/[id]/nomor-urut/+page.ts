import { supabase } from '$lib/supabase';

async function countGuests(eventId: string, category: 'vip' | 'vvip', onlyNumbered: boolean) {
  let q = supabase
    .from('guests')
    .select('id', { count: 'exact', head: true })
    .eq('event_id', eventId)
    .eq('category', category)
    .is('deleted_at', null);
  if (onlyNumbered) q = q.not('special_number', 'is', null);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

export async function load({ params, depends }) {
  depends('app:numbering');
  const { data: settings, error } = await supabase
    .from('ticket_number_settings')
    .select('category, prefix, start_number, digits')
    .eq('event_id', params.id);
  if (error) throw error;

  const categories = ['vvip', 'vip'] as const;
  const counts = await Promise.all(
    categories.map(async (c) => ({
      category: c,
      total: await countGuests(params.id, c, false),
      numbered: await countGuests(params.id, c, true),
    })),
  );
  return {
    panels: categories.map((c) => ({
      category: c,
      setting: settings.find((s) => s.category === c) ?? {
        category: c,
        prefix: c === 'vip' ? 'VIP-' : 'VVIP-',
        start_number: 1,
        digits: 3,
      },
      ...(counts.find((x) => x.category === c) ?? { total: 0, numbered: 0 }),
    })),
  };
}
