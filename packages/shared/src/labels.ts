/** Label UI Bahasa Indonesia untuk enum (prd.md bagian 5, D15). */
import type {
  AttendanceStatus,
  Category,
  CheckInStatus,
  QuarantineReason,
  RevokeMode,
  RsvpStatus,
  UsherMode,
} from './enums.ts';
import { REVIEW_STATUSES, type ReviewStatus } from './enums.ts';
import type { GreetingLayout } from './schemas/greeting.ts';
import type { PrintTicketField } from './schemas/settings.ts';

export const CATEGORY_LABEL: Record<Category, string> = {
  regular: 'Regular',
  vip: 'VIP',
  vvip: 'VVIP',
};

export function rsvpLabel(status: RsvpStatus, pax: number | null): string {
  switch (status) {
    case 'going':
      return pax == null ? 'Akan hadir' : `Akan hadir (${pax} orang)`;
    case 'not_going':
      return 'Tidak hadir';
    case 'unconfirmed':
      return 'Belum konfirmasi';
  }
}

/** `checked_out` tetap "Hadir"; waktu keluar ditampilkan sebagai keterangan terpisah. */
export const ATTENDANCE_LABEL: Record<AttendanceStatus, string> = {
  not_arrived: 'Belum hadir',
  checked_in: 'Hadir',
  checked_out: 'Hadir',
};

const STATUS_LABEL: Record<CheckInStatus, string> = {
  accepted: 'Sah',
  repeat: 'Masuk ulang',
  duplicate: 'Ganda — tinjau',
  conflict: 'Nomor bentrok — tinjau',
  quarantined: 'Karantina — tinjau',
};

const REVIEWED_LABEL: Record<ReviewStatus, string> = {
  duplicate: 'Ganda · ditinjau',
  conflict: 'Nomor bentrok · ditinjau',
  quarantined: 'Karantina · ditinjau',
};

export const VOIDED_LABEL = 'Dibatalkan';

export function isReviewStatus(status: CheckInStatus): status is ReviewStatus {
  return (REVIEW_STATUSES as readonly CheckInStatus[]).includes(status);
}

export interface CheckInBadge {
  text: string;
  /** true = tampilkan penanda tinjauan (ikon dan gaya badge yang sama untuk ketiga status). */
  needsReview: boolean;
  voided: boolean;
}

export function checkInBadge(input: {
  status: CheckInStatus;
  reviewedAt: string | null;
  voidedAt: string | null;
}): CheckInBadge {
  if (input.voidedAt) return { text: VOIDED_LABEL, needsReview: false, voided: true };
  if (isReviewStatus(input.status)) {
    return input.reviewedAt
      ? { text: REVIEWED_LABEL[input.status], needsReview: false, voided: false }
      : { text: STATUS_LABEL[input.status], needsReview: true, voided: false };
  }
  return { text: STATUS_LABEL[input.status], needsReview: false, voided: false };
}

export const QUARANTINE_REASON_LABEL: Record<QuarantineReason, string> = {
  device_revoked: 'Perangkat dicabut',
  session_expired: 'Sesi berakhir',
};

export const REVOKE_MODE_LABEL: Record<RevokeMode, string> = {
  quarantine: 'Cabut',
  terminate: 'Cabut & putus total',
};

export const USHER_MODE_LABEL: Record<UsherMode, string> = {
  check_in: 'Check-In',
  check_out: 'Check-Out',
};

/** Keadaan perangkat di daftar perangkat (FR-R-08). Urutannya sama dengan pemeriksaan server (11.5 langkah 5). */
export type DeviceState = 'active' | 'revoked' | 'terminated' | 'expired';

export const DEVICE_STATE_LABEL: Record<DeviceState, string> = {
  active: 'Aktif',
  revoked: 'Dicabut',
  terminated: 'Diputus total',
  expired: 'Sesi berakhir',
};

export function deviceState(
  device: { revoke_mode: RevokeMode | null; session_expires_at: string },
  eventArchived: boolean,
  now: Date = new Date(),
): DeviceState {
  if (device.revoke_mode === 'terminate') return 'terminated';
  if (device.revoke_mode === 'quarantine') return 'revoked';
  if (eventArchived || new Date(device.session_expires_at) <= now) return 'expired';
  return 'active';
}

export const PRINT_TICKET_FIELD_LABEL: Record<PrintTicketField, string> = {
  event_name: 'Nama acara',
  couple_names: 'Nama mempelai',
  event_date: 'Tanggal acara',
  guest_name: 'Nama tamu',
  category: 'Kategori',
  group_name: 'Grup',
  ticket_number: 'Nomor tiket',
  pax: 'Jumlah orang',
  checked_in_at: 'Jam masuk',
};

export const GREETING_LAYOUT_LABEL: Record<GreetingLayout, string> = {
  text: 'Teks saja',
  photo_wide: 'Foto lebar',
  photo_round: 'Foto bulat',
};
