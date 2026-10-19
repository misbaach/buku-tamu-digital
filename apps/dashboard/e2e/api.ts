import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@guestbook/shared/database.types';
import { ADMIN } from './helpers';

type GuestInsert = Database['public']['Tables']['guests']['Insert'];

let client: Promise<SupabaseClient<Database>> | undefined;

/** Klien Supabase sebagai Admin seed (publishable key + login), sekali per proses tes. Bukan service role. */
export function adminApi(): Promise<SupabaseClient<Database>> {
  client ??= (async () => {
    const url = process.env.PUBLIC_SUPABASE_URL;
    const key = process.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) throw new Error('Jalankan tes lewat `pnpm test:e2e` agar env Supabase lokal terisi.');
    const sb = createClient<Database>(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { error } = await sb.auth.signInWithPassword(ADMIN);
    if (error) throw error;
    return sb;
  })();
  return client;
}

/** Acara baru milik Admin seed, terisolasi dari tes lain. */
export async function createEvent(name: string, guests: Omit<GuestInsert, 'event_id'>[] = []): Promise<string> {
  const sb = await adminApi();
  const today = new Date().toISOString().slice(0, 10);
  const { data: id, error } = await sb.rpc('admin_create_event', { p_name: name, p_event_date: today });
  if (error) throw error;
  if (guests.length > 0) {
    const { error: insertError } = await sb.from('guests').insert(
      guests.map((g) => ({ ...g, event_id: id })),
      // Kolom yang tidak disebut memakai DEFAULT, bukan NULL (bawaan PostgREST untuk insert banyak baris).
      { defaultToNull: false },
    );
    if (insertError) throw insertError;
  }
  return id;
}

export const uniqueName = (prefix: string) => `${prefix} ${Date.now().toString(36)}`;

/** Usher baru lewat RPC Admin; PIN dikembalikan sekali seperti di dashboard. */
export async function createUsher(eventId: string, name: string): Promise<{ id: string; pin: string }> {
  const sb = await adminApi();
  const { data, error } = await sb.rpc('admin_create_usher', { p_event_id: eventId, p_name: name });
  if (error) throw error;
  const r = data as { usher_id: string; pin: string };
  return { id: r.usher_id, pin: r.pin };
}

export async function eventCode(eventId: string): Promise<string> {
  const sb = await adminApi();
  const { data, error } = await sb.from('events').select('code').eq('id', eventId).single();
  if (error) throw error;
  return data.code;
}

/** Login perangkat lewat Edge Function usher-login, persis seperti App Penerima Tamu. */
export async function usherLogin(
  code: string,
  pin: string,
  ip = `10.200.${Date.now() % 250}.${Math.floor(Math.random() * 250)}`,
) {
  const res = await fetch(`${process.env.PUBLIC_SUPABASE_URL}/functions/v1/usher-login`, {
    method: 'POST',
    headers: {
      apikey: process.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? '',
      'content-type': 'application/json',
      'cf-connecting-ip': ip,
    },
    body: JSON.stringify({ method: 'pin', eventCode: code, pin, device: { name: 'HP Uji E2E', appVersion: '0.1.0' } }),
  });
  return {
    status: res.status,
    body: (await res.json()) as { device?: { id: string; code: string }; session?: { accessToken: string } },
  };
}

export interface Device {
  id: string;
  code: string;
  token: string;
}

/** Login perangkat yang harus berhasil. */
export async function loginDevice(code: string, pin: string): Promise<Device> {
  const r = await usherLogin(code, pin);
  if (r.status !== 200 || !r.body.device || !r.body.session) throw new Error(`login perangkat gagal: ${r.status}`);
  return { id: r.body.device.id, code: r.body.device.code, token: r.body.session.accessToken };
}

/** push_outbox sebagai perangkat; mengembalikan status per item. */
export async function pushCheckIns(device: Device, items: { guestId: string; ticket: string; pax?: number }[]) {
  const res = await fetch(`${process.env.PUBLIC_SUPABASE_URL}/rest/v1/rpc/push_outbox`, {
    method: 'POST',
    headers: {
      apikey: process.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? '',
      authorization: `Bearer ${device.token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      p_items: items.map((it) => ({
        id: crypto.randomUUID(),
        guestId: it.guestId,
        actualPax: it.pax ?? 1,
        ticketNumber: it.ticket,
        deviceId: device.id,
        checkedInAt: new Date().toISOString(),
      })),
    }),
  });
  const body = (await res.json()) as { status: string; results: { status?: string; code?: string }[] };
  return body.results.map((r) => r.status ?? r.code);
}

/** Id tamu menurut nama (acara milik Admin seed). */
export async function guestIds(eventId: string): Promise<Record<string, string>> {
  const sb = await adminApi();
  const { data, error } = await sb.from('guests').select('id, name').eq('event_id', eventId);
  if (error) throw error;
  return Object.fromEntries(data.map((g) => [g.name, g.id]));
}
