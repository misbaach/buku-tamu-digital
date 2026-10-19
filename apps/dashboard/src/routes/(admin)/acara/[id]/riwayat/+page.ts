import { fetchHistory, parseHistoryParams } from '$lib/features/history/query';
import type { EventStats } from '$lib/features/stats/types';
import { supabase } from '$lib/supabase';

export async function load({ params, url, depends }) {
  depends('app:history');
  const filters = parseHistoryParams(url);
  const [history, stats] = await Promise.all([
    fetchHistory(params.id, filters),
    supabase.rpc('get_event_stats', { p_event_id: params.id }),
  ]);
  if (stats.error) throw stats.error;
  return { filters, ...history, review: (stats.data as unknown as EventStats).review };
}
