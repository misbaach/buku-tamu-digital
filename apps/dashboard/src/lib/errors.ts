/** Galat database/RPC → pesan Indonesia yang bisa ditindaklanjuti. Pesan dari RPC kita sudah berbahasa Indonesia. */

const CONSTRAINT_MESSAGES: Record<string, string> = {
  guests_special_number_rule:
    'Nomor Urut tidak sah: gunakan huruf besar, angka, atau tanda hubung, dan jangan berpola nomor perangkat (mis. A-017).',
  guests_event_special_number_key: 'Nomor Urut sudah dipakai tamu lain di acara ini.',
  guests_name_len: 'Nama wajib diisi, maksimal 120 karakter.',
  guests_phone_format: 'Format nomor telepon tidak valid.',
  guests_invited_pax_range: 'Jumlah undangan harus 1–50.',
  guests_rsvp_pax_range: 'Jumlah konfirmasi harus 0–50.',
  guests_rsvp_pax_only_if_going: 'Jumlah konfirmasi hanya diisi bila status Akan hadir.',
  guests_notes_len: 'Catatan maksimal 500 karakter.',
  guest_groups_event_name_key: 'Nama grup sudah dipakai di acara ini.',
  guest_groups_name_len: 'Nama grup wajib diisi, maksimal 80 karakter.',
  ticket_number_settings_prefix_rule:
    'Prefix dan jumlah digit menghasilkan nomor yang tidak sah (berpola nomor perangkat/kode hadiah, atau lebih dari 20 karakter).',
  events_name_len: 'Nama acara wajib diisi, maksimal 120 karakter.',
  events_attendance_limit_positive: 'Batas jumlah hadir harus lebih dari 0.',
  check_ins_ticket_number_format: 'Nomor tiket hanya boleh berisi huruf besar, angka, dan tanda hubung (maks. 20).',
};

interface DbErrorLike {
  code?: string;
  message?: string;
  name?: string;
}

const OUR_CODES = new Set(['P0001', 'P0002', '22023', '40001']);

export function dbErrorMessage(error: unknown): string {
  const e = (error ?? {}) as DbErrorLike;
  const message = e.message ?? '';

  if (e.name === 'TypeError' || /fetch|network|Failed to fetch/i.test(message)) {
    return 'Tidak dapat terhubung ke server. Periksa koneksi internet, lalu coba lagi.';
  }

  const constraint = Object.keys(CONSTRAINT_MESSAGES).find((c) => message.includes(c));
  const row = /^Baris (\d+|\?):/.exec(message)?.[1];
  const prefix = row ? `Baris ${row}: ` : '';
  if (constraint) return prefix + CONSTRAINT_MESSAGES[constraint];
  if (/invalid input value for enum/i.test(message)) return `${prefix}Ada nilai pilihan yang tidak dikenal.`;

  if (e.code && OUR_CODES.has(e.code)) return message;
  if (e.code === '42501') {
    return /^(Anda|Hanya)/.test(message) ? message : 'Anda tidak punya izin untuk tindakan ini.';
  }
  if (e.code === '23505') return message.startsWith('Nomor') ? message : 'Data yang sama sudah ada.';
  if (e.code === '23514') return 'Data tidak memenuhi aturan. Periksa kembali isian.';
  if (e.code === 'PGRST116') return 'Data tidak ditemukan.';
  return 'Terjadi kesalahan. Coba lagi; bila terus terjadi, hubungi operator.';
}
