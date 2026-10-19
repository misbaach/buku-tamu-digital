import type { Category, GreetingPopup } from '@guestbook/shared';
import { supabase } from '$lib/supabase';

export async function load({ params, depends }) {
  depends('app:greetings');
  const { data, error } = await supabase.from('greeting_configs').select('category, popup').eq('event_id', params.id);
  if (error) throw error;
  const popups = Object.fromEntries(data.map((r) => [r.category, (r.popup ?? {}) as GreetingPopup])) as Partial<
    Record<Category, GreetingPopup>
  >;
  return { popups };
}
