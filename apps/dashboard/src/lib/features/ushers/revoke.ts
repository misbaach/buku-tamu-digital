import { FunctionsHttpError } from '@supabase/supabase-js';
import { dbErrorMessage } from '$lib/errors';
import { supabase } from '$lib/supabase';

type Result = { ok: true; message: string } | { ok: false; message: string };

/** Cabut: sesi tetap hidup, data berikutnya dari perangkat masuk karantina (FR-R-08 a). */
export async function quarantineDevice(deviceId: string): Promise<Result> {
  const { error } = await supabase.rpc('admin_revoke_device', { p_device_id: deviceId, p_mode: 'quarantine' });
  return error ? { ok: false, message: dbErrorMessage(error) } : { ok: true, message: 'Perangkat dicabut.' };
}

/**
 * Cabut & putus total lewat Edge Function device-cleanup dengan JWT Admin (FR-R-08 b): status terminate tercatat
 * di DB, lalu user Auth perangkat dihapus. Bila penghapusan tertunda, job berkala mengulanginya.
 */
export async function terminateDevice(deviceId: string, reason: string): Promise<Result> {
  const { data, error } = await supabase.functions.invoke<{ authUserDeleted: boolean }>('device-cleanup', {
    body: { mode: 'terminate', deviceId, reason },
  });
  if (!error) {
    return {
      ok: true,
      message: data?.authUserDeleted
        ? 'Perangkat diputus total. Sesinya sudah diakhiri.'
        : 'Perangkat diputus total. Semua data darinya ditolak; akun perangkat dihapus otomatis sebentar lagi.',
    };
  }
  if (error instanceof FunctionsHttpError) {
    const status = (error.context as Response).status;
    const body = (await (error.context as Response).json().catch(() => ({}))) as { message?: string };
    if (status === 403) return { ok: false, message: 'Anda bukan Admin acara ini.' };
    if (status === 404) return { ok: false, message: 'Perangkat tidak ditemukan.' };
    if (status === 400 && body.message) return { ok: false, message: body.message };
  }
  return { ok: false, message: 'Perangkat gagal diputus. Periksa koneksi, lalu coba lagi.' };
}
