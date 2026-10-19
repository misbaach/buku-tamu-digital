import { invalidate } from '$app/navigation';
import { STATS_DEBOUNCE_MS, STATS_POLL_FALLBACK_MS } from '@guestbook/shared';
import { supabase } from '$lib/supabase';

export type LiveMode = 'connecting' | 'live' | 'polling';

/**
 * Pembaruan statistik (FR-S-07): Broadcast privat `event:{id}:stats` dari trigger DB → debounce → muat ulang
 * lewat RPC agregat. Bila channel tidak SUBSCRIBED, beralih ke polling; kembali ke langsung saat tersambung.
 */
export function liveStats(eventId: string, dependency: string) {
  const state = $state<{ mode: LiveMode; updatedAt: number }>({ mode: 'connecting', updatedAt: Date.now() });
  let debounce: ReturnType<typeof setTimeout> | undefined;
  let poll: ReturnType<typeof setInterval> | undefined;

  const refresh = async () => {
    await invalidate(dependency);
    state.updatedAt = Date.now();
  };
  const schedule = () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => void refresh(), STATS_DEBOUNCE_MS);
  };
  const startPolling = () => {
    state.mode = 'polling';
    poll ??= setInterval(() => void refresh(), STATS_POLL_FALLBACK_MS);
  };
  const stopPolling = () => {
    clearInterval(poll);
    poll = undefined;
  };

  const channel = supabase.channel(`event:${eventId}:stats`, { config: { private: true } });
  channel.on('broadcast', { event: 'stats' }, schedule);
  void supabase.realtime.setAuth().then(() =>
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        state.mode = 'live';
        stopPolling();
        void refresh(); // perubahan selama menyambung tidak terlewat
      } else {
        startPolling();
      }
    }),
  );
  const guard = setTimeout(() => {
    if (state.mode === 'connecting') startPolling();
  }, 5000);

  return {
    state,
    stop() {
      clearTimeout(debounce);
      clearTimeout(guard);
      stopPolling();
      void supabase.removeChannel(channel);
    },
  };
}
