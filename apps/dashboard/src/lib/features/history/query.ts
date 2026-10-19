import type { Category, CheckInStatus, QuarantineReason, RsvpStatus } from '@guestbook/shared';
import { supabase } from '$lib/supabase';

export const HISTORY_PAGE_SIZE = 50;

export const HISTORY_TABS = ['masuk', 'keluar', 'semua'] as const;
export type HistoryTab = (typeof HISTORY_TABS)[number];

export const HISTORY_FILTERS = ['tinjau', 'karantina', 'ganda', 'bentrok', 'dibatalkan'] as const;
export type HistoryFilter = (typeof HISTORY_FILTERS)[number];

export interface HistoryParams {
  tab: HistoryTab;
  status: HistoryFilter | null;
  q: string;
  hal: number;
}

export interface HistoryRow {
  id: string;
  guest_id: string | null;
  pending_guest: { name?: string; category?: Category; invitedPax?: number } | null;
  actual_pax: number;
  ticket_number: string | null;
  status: CheckInStatus;
  source: 'device' | 'admin' | 'outbox_upload';
  quarantine_reason: QuarantineReason | null;
  checked_in_at: string;
  received_at: string;
  checked_out_at: string | null;
  voided_at: string | null;
  void_reason: string | null;
  reviewed_at: string | null;
  device_id: string | null;
  guests: {
    name: string;
    category: Category;
    rsvp_status: RsvpStatus;
    rsvp_pax: number | null;
    invited_pax: number;
    is_additional: boolean;
    deleted_at: string | null;
  } | null;
  ushers: { name: string } | null;
  devices: { code: string } | null;
}

export function parseHistoryParams(url: URL): HistoryParams {
  const tab = url.searchParams.get('tab');
  const status = url.searchParams.get('status');
  const hal = Number(url.searchParams.get('hal') ?? '1');
  return {
    tab: (HISTORY_TABS as readonly string[]).includes(tab ?? '') ? (tab as HistoryTab) : 'masuk',
    status: (HISTORY_FILTERS as readonly string[]).includes(status ?? '') ? (status as HistoryFilter) : null,
    q: (url.searchParams.get('q') ?? '').slice(0, 80),
    hal: Number.isInteger(hal) && hal > 0 ? hal : 1,
  };
}

export function historySearch(p: Partial<HistoryParams>): string {
  const s = new URLSearchParams();
  if (p.tab && p.tab !== 'masuk') s.set('tab', p.tab);
  if (p.status) s.set('status', p.status);
  if (p.q) s.set('q', p.q);
  if (p.hal && p.hal > 1) s.set('hal', String(p.hal));
  const text = s.toString();
  return text ? `?${text}` : '';
}

// Karakter sintaks filter PostgREST dibuang dari pencarian (sama dengan Kelola Tamu).
const sanitize = (q: string) => q.replace(/[,()*"\\%_]/g, ' ').trim();

/** Jumlah tercatat per tamu (plan.md 10.3): rsvp_pax bila Akan hadir, selain itu invited_pax. */
export function recordedPax(g: NonNullable<HistoryRow['guests']>): number {
  return g.rsvp_status === 'going' ? (g.rsvp_pax ?? g.invited_pax) : g.invited_pax;
}

export async function fetchHistory(eventId: string, p: HistoryParams) {
  const q = sanitize(p.q);
  // Tanpa pencarian, check-in karantina dengan tamu baru (guest_id kosong) tetap ikut (left join).
  const guestJoin = q
    ? 'guests!inner(name, category, rsvp_status, rsvp_pax, invited_pax, is_additional, deleted_at)'
    : 'guests(name, category, rsvp_status, rsvp_pax, invited_pax, is_additional, deleted_at)';
  let query = supabase
    .from('check_ins')
    .select(
      `id, guest_id, pending_guest, actual_pax, ticket_number, status, source, quarantine_reason, checked_in_at, received_at, checked_out_at, voided_at, void_reason, reviewed_at, device_id, ${guestJoin}, ushers(name), devices(code)`,
      { count: 'exact' },
    )
    .eq('event_id', eventId);

  if (q) query = query.ilike('guests.name', `%${q}%`);
  if (p.tab === 'keluar') query = query.not('checked_out_at', 'is', null);

  switch (p.status) {
    case 'tinjau':
      query = query.or(
        'and(status.eq.quarantined,voided_at.is.null),and(status.in.(duplicate,conflict),reviewed_at.is.null,voided_at.is.null)',
      );
      break;
    case 'karantina':
      query = query.eq('status', 'quarantined').is('voided_at', null);
      break;
    case 'ganda':
      query = query.eq('status', 'duplicate').is('voided_at', null);
      break;
    case 'bentrok':
      query = query.eq('status', 'conflict').is('voided_at', null);
      break;
    case 'dibatalkan':
      query = query.not('voided_at', 'is', null);
      break;
  }

  // Urutan resmi memakai jam server (12.3 poin 9); tab Check-Out diurutkan menurut waktu keluar.
  query =
    p.tab === 'keluar'
      ? query.order('checked_out_at', { ascending: false }).order('id')
      : p.status === 'karantina'
        ? query.order('device_id').order('received_at').order('id')
        : query.order('received_at', { ascending: false }).order('id');

  const from = (p.hal - 1) * HISTORY_PAGE_SIZE;
  const { data, count, error } = await query.range(from, from + HISTORY_PAGE_SIZE - 1);
  if (error) throw error;
  return { rows: data as unknown as HistoryRow[], total: count ?? 0 };
}
