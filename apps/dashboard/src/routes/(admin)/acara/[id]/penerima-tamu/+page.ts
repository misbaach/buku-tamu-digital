import { supabase } from '$lib/supabase';
import type { Alerts } from '$lib/features/ushers/types';

export async function load({ params, depends }) {
  depends('app:ushers');
  const [ushers, devices, alerts] = await Promise.all([
    supabase
      .from('ushers')
      .select('id, name, mode, pin_selector, is_active, created_at')
      .eq('event_id', params.id)
      .is('deleted_at', null)
      .order('created_at'),
    // Jumlah karantina per perangkat (FR-R-08 daftar perangkat minimal).
    supabase
      .from('devices')
      .select(
        'id, usher_id, code, name, app_version, created_at, last_seen_at, clock_offset_ms, session_expires_at, revoked_at, revoke_mode, revoke_reason, auth_user_deleted_at, ushers(name), check_ins(count)',
      )
      .eq('event_id', params.id)
      .eq('check_ins.status', 'quarantined')
      .order('created_at'),
    supabase.rpc('get_alerts', { p_event_id: params.id }),
  ]);
  if (ushers.error) throw ushers.error;
  if (devices.error) throw devices.error;
  if (alerts.error) throw alerts.error;
  return {
    ushers: ushers.data,
    devices: devices.data.map(({ ushers: u, check_ins, ...d }) => ({
      ...d,
      usher_name: (u as { name: string } | null)?.name ?? '—',
      quarantined: (check_ins as unknown as { count: number }[])[0]?.count ?? 0,
    })),
    alerts: alerts.data as unknown as Alerts,
  };
}
