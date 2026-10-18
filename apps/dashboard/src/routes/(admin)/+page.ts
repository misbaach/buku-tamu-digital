import { supabase } from '$lib/supabase';

export interface EventRow {
  id: string;
  name: string;
  event_date: string;
  code: string;
  archived_at: string | null;
}

async function fetchEvents(): Promise<EventRow[]> {
  const { data, error } = await supabase
    .from('events')
    .select('id, name, event_date, code, archived_at')
    .order('event_date', { ascending: false });
  if (error) throw new Error(error.message);
  return data;
}

// Promise sengaja tidak di-await agar halaman langsung tampil dan memakai skeleton bila lambat.
export function load() {
  return { events: fetchEvents() };
}
