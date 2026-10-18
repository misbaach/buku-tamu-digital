import { CATEGORIES, RSVP_STATUSES, type Category, type RsvpStatus } from '@guestbook/shared';
import { supabase } from '$lib/supabase';
import type { GuestRow } from '$lib/types';

export type AttendanceFilter = '' | 'hadir' | 'belum' | 'keluar';

/** Filter Kelola Tamu (FR-G-08). Semua tersimpan di query string agar bisa di-bookmark dan Back bekerja. */
export interface GuestFilters {
  q: string;
  kategori: Category | '';
  /** uuid grup, 'tanpa' = tanpa grup, '' = semua */
  grup: string;
  rsvp: RsvpStatus | '';
  hadir: AttendanceFilter;
  hal: number;
  per: number;
}

const PER_PAGE = [25, 50, 100];

export function parseFilters(url: URL): GuestFilters {
  const p = url.searchParams;
  const kategori = p.get('kategori') ?? '';
  const rsvp = p.get('rsvp') ?? '';
  const hadir = p.get('hadir') ?? '';
  const per = Number(p.get('per'));
  const hal = Number(p.get('hal'));
  return {
    q: (p.get('q') ?? '').slice(0, 100),
    kategori: (CATEGORIES as readonly string[]).includes(kategori) ? (kategori as Category) : '',
    grup: p.get('grup') ?? '',
    rsvp: (RSVP_STATUSES as readonly string[]).includes(rsvp) ? (rsvp as RsvpStatus) : '',
    hadir: ['hadir', 'belum', 'keluar'].includes(hadir) ? (hadir as AttendanceFilter) : '',
    hal: Number.isInteger(hal) && hal > 0 ? hal : 1,
    per: PER_PAGE.includes(per) ? per : 50,
  };
}

export function filtersToSearch(f: GuestFilters): string {
  const p = new URLSearchParams();
  if (f.q) p.set('q', f.q);
  if (f.kategori) p.set('kategori', f.kategori);
  if (f.grup) p.set('grup', f.grup);
  if (f.rsvp) p.set('rsvp', f.rsvp);
  if (f.hadir) p.set('hadir', f.hadir);
  if (f.hal > 1) p.set('hal', String(f.hal));
  if (f.per !== 50) p.set('per', String(f.per));
  const s = p.toString();
  return s ? `?${s}` : '';
}

export function hasActiveFilters(f: GuestFilters): boolean {
  return !!(f.q || f.kategori || f.grup || f.rsvp || f.hadir);
}

export type GuestListRow = Pick<
  GuestRow,
  | 'id'
  | 'name'
  | 'phone'
  | 'category'
  | 'group_id'
  | 'invited_pax'
  | 'special_number'
  | 'rsvp_status'
  | 'rsvp_pax'
  | 'attendance_status'
  | 'is_additional'
  | 'notes'
> & { guest_groups: { name: string } | null };

/** Karakter yang punya arti khusus di filter PostgREST dibuang dari kata kunci. */
function sanitizeSearch(q: string): string {
  return q.replace(/[,()*"\\%_]/g, ' ').trim();
}

export async function fetchGuests(eventId: string, f: GuestFilters): Promise<{ rows: GuestListRow[]; total: number }> {
  let query = supabase
    .from('guests')
    .select(
      'id, name, phone, category, group_id, invited_pax, special_number, rsvp_status, rsvp_pax, attendance_status, is_additional, notes, guest_groups(name)',
      { count: 'exact' },
    )
    .eq('event_id', eventId)
    .is('deleted_at', null);

  const q = sanitizeSearch(f.q);
  if (q) query = query.or(`name.ilike.*${q}*,special_number.ilike.*${q}*`);
  if (f.kategori) query = query.eq('category', f.kategori);
  if (f.grup === 'tanpa') query = query.is('group_id', null);
  else if (f.grup) query = query.eq('group_id', f.grup);
  if (f.rsvp) query = query.eq('rsvp_status', f.rsvp);
  if (f.hadir === 'hadir') query = query.in('attendance_status', ['checked_in', 'checked_out']);
  else if (f.hadir === 'belum') query = query.eq('attendance_status', 'not_arrived');
  else if (f.hadir === 'keluar') query = query.eq('attendance_status', 'checked_out');

  const from = (f.hal - 1) * f.per;
  const { data, count, error } = await query
    .order('name', { ascending: true })
    .order('id', { ascending: true })
    .range(from, from + f.per - 1);
  if (error) throw error;
  return { rows: (data ?? []) as unknown as GuestListRow[], total: count ?? 0 };
}

export async function fetchGroups(eventId: string) {
  const { data, error } = await supabase
    .from('guest_groups')
    .select('id, name')
    .eq('event_id', eventId)
    .is('deleted_at', null)
    .order('name');
  if (error) throw error;
  return data;
}
