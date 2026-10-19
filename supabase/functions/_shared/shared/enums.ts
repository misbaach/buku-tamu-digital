// SALINAN OTOMATIS dari packages/shared/src/enums.ts. Jangan diedit; jalankan `pnpm functions:sync`.
/** Enum bersama. Nilainya bahasa Inggris dan sama persis dengan enum di database (prd.md 12.2). */

export const CATEGORIES = ['regular', 'vip', 'vvip'] as const;
export type Category = (typeof CATEGORIES)[number];

export const RSVP_STATUSES = ['going', 'not_going', 'unconfirmed'] as const;
export type RsvpStatus = (typeof RSVP_STATUSES)[number];

export const ATTENDANCE_STATUSES = ['not_arrived', 'checked_in', 'checked_out'] as const;
export type AttendanceStatus = (typeof ATTENDANCE_STATUSES)[number];

export const USHER_MODES = ['check_in', 'check_out'] as const;
export type UsherMode = (typeof USHER_MODES)[number];

export const CHECK_IN_STATUSES = ['accepted', 'repeat', 'duplicate', 'conflict', 'quarantined'] as const;
export type CheckInStatus = (typeof CHECK_IN_STATUSES)[number];

/** Status yang perlu ditinjau Admin; ditampilkan dengan penanda visual yang sama (prd.md bagian 5). */
export const REVIEW_STATUSES = ['duplicate', 'conflict', 'quarantined'] as const satisfies readonly CheckInStatus[];
export type ReviewStatus = (typeof REVIEW_STATUSES)[number];

export const CHECK_IN_SOURCES = ['device', 'admin', 'outbox_upload'] as const;
export type CheckInSource = (typeof CHECK_IN_SOURCES)[number];

export const QUARANTINE_REASONS = ['device_revoked', 'session_expired'] as const;
export type QuarantineReason = (typeof QUARANTINE_REASONS)[number];

export const REVOKE_MODES = ['quarantine', 'terminate'] as const;
export type RevokeMode = (typeof REVOKE_MODES)[number];

export const GIFT_KINDS = ['envelope', 'present', 'transfer'] as const;
export type GiftKind = (typeof GIFT_KINDS)[number];
