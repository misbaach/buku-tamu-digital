import { STATS_TIMELINE_BUCKET_MIN } from '@guestbook/shared';
import type { EventStats, TimelineBucket } from '$lib/features/stats/types';
import { supabase } from '$lib/supabase';

export async function load({ params, depends }) {
  depends('app:stats');
  const [stats, timeline] = await Promise.all([
    supabase.rpc('get_event_stats', { p_event_id: params.id }),
    supabase.rpc('get_arrival_timeline', { p_event_id: params.id, p_bucket_min: STATS_TIMELINE_BUCKET_MIN }),
  ]);
  if (stats.error) throw stats.error;
  if (timeline.error) throw timeline.error;
  return { stats: stats.data as unknown as EventStats, timeline: timeline.data as TimelineBucket[] };
}
