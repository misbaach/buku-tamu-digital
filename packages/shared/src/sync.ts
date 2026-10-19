/**
 * Kontrak sinkronisasi usher (prd.md 12.2, 12.3; docs/plan.md bagian 10). Skema memakai `.strict()` sehingga
 * kunci tambahan (mis. `phone`, `notes`, `qr_token`) membuat validasi gagal.
 */
import { z } from './zod.ts';
import { GREETING_LAYOUTS, PRINT_TICKET_FIELDS } from './config.ts';
import { ATTENDANCE_STATUSES, CATEGORIES, CHECK_IN_STATUSES, RSVP_STATUSES } from './enums.ts';

const iso = z.string().min(1);

export const guestCheckInSummarySchema = z
  .object({
    status: z.enum(['accepted', 'repeat', 'duplicate', 'conflict']),
    ticketNumber: z.string().nullable(),
    checkedInAt: iso,
    usherName: z.string().nullable(),
  })
  .strict();
export type GuestCheckInSummary = z.infer<typeof guestCheckInSummarySchema>;

export const guestSnapshotSchema = z
  .object({
    id: z.uuid(),
    name: z.string(),
    category: z.enum(CATEGORIES),
    groupId: z.uuid().nullable(),
    invitedPax: z.number().int(),
    specialNumber: z.string().nullable(),
    qrTokenHash: z.string().regex(/^[0-9a-f]{64}$/),
    rsvpStatus: z.enum(RSVP_STATUSES),
    rsvpPax: z.number().int().nullable(),
    attendanceStatus: z.enum(ATTENDANCE_STATUSES),
    isAdditional: z.boolean(),
    checkIn: guestCheckInSummarySchema.nullable(),
    updatedAt: iso,
    deletedAt: iso.nullable(),
  })
  .strict();
export type GuestSnapshot = z.infer<typeof guestSnapshotSchema>;

/** Urutan kunci GuestSnapshot; pgTAP 080 memeriksa daftar yang sama secara persis. */
export const GUEST_SNAPSHOT_KEYS = Object.keys(guestSnapshotSchema.shape);

const snapshotOkSchema = z
  .object({
    status: z.literal('ok'),
    serverTime: iso,
    nextCursor: z.string().min(1),
    hasMore: z.boolean(),
    event: z
      .object({
        id: z.uuid(),
        name: z.string(),
        coupleNames: z.string().nullable(),
        eventDate: iso,
        timezone: z.string(),
        sessionExpiresAt: iso,
      })
      .strict(),
    device: z.object({ code: z.string() }).strict(),
    settings: z
      .object({
        showVerification: z.boolean(),
        allowMultiCheckin: z.boolean(),
        printTicket: z
          .object({
            enabled: z.boolean(),
            fields: z.array(z.enum(PRINT_TICKET_FIELDS)),
            categories: z.array(z.enum(CATEGORIES)),
            copies: z.number().int(),
          })
          .strict(),
      })
      .strict(),
    greetings: z.array(
      z
        .object({
          category: z.enum(CATEGORIES),
          title: z.string().nullable(),
          body: z.string().nullable(),
          layout: z.enum(GREETING_LAYOUTS).nullable(),
          photoPath: z.string().nullable(),
          photoVersion: z.number().int(),
        })
        .strict(),
    ),
    groups: z.array(z.object({ id: z.uuid(), name: z.string(), updatedAt: iso, deletedAt: iso.nullable() }).strict()),
    guests: z.array(guestSnapshotSchema),
  })
  .strict();

/** Perangkat dicabut → `revoked`; sesi berakhir atau acara diarsipkan → `expired`. Keduanya tanpa data. */
export const pullResponseSchema = z.discriminatedUnion('status', [
  snapshotOkSchema,
  z.object({ status: z.literal('revoked') }).strict(),
  z.object({ status: z.literal('expired') }).strict(),
]);
export type PullResponse = z.infer<typeof pullResponseSchema>;
export type SnapshotOk = z.infer<typeof snapshotOkSchema>;

// --- push_outbox ---------------------------------------------------------------------------------

export interface NewGuestInput {
  name: string;
  phone: string | null;
  category: (typeof CATEGORIES)[number];
  invitedPax: number;
  notes: string | null;
}

/** Item outbox yang dikirim perangkat (subset CheckInOutboxItem di prd.md 12.2). */
export interface PushItem {
  id: string;
  guestId: string | null;
  newGuest?: NewGuestInput;
  actualPax: number;
  ticketNumber: string;
  deviceId: string;
  checkedInAt: string;
  gift?: unknown;
}

/** Kode galat per item. Item yang galat tidak disimpan dan tetap di outbox perangkat (12.3 poin 5). */
export const PUSH_ERROR_CODES = [
  'invalid_item',
  'id_conflict',
  'device_mismatch',
  'guest_not_found',
  'invalid_new_guest',
  'invalid_ticket_number',
  'ticket_device_mismatch',
  'gift_not_supported',
  'quarantine_limit',
] as const;
export type PushErrorCode = (typeof PUSH_ERROR_CODES)[number];

export const PUSH_REJECT_REASONS = [
  'terminated',
  'quarantine_window_closed',
  'event_archived',
  'mode_mismatch',
] as const;
export type PushRejectReason = (typeof PUSH_REJECT_REASONS)[number];

export const pushItemResultSchema = z.union([
  z
    .object({
      id: z.uuid(),
      outcome: z.literal('stored'),
      status: z.enum(CHECK_IN_STATUSES),
      guestId: z.uuid().nullable(),
      ticketNumber: z.string(),
      receivedAt: iso,
    })
    .strict(),
  z.object({ id: z.string(), outcome: z.literal('error'), code: z.enum(PUSH_ERROR_CODES) }).strict(),
]);
export type PushItemResult = z.infer<typeof pushItemResultSchema>;

export const pushResponseSchema = z.discriminatedUnion('status', [
  z.object({ status: z.literal('ok'), results: z.array(pushItemResultSchema) }).strict(),
  z.object({ status: z.literal('revoked'), results: z.array(pushItemResultSchema) }).strict(),
  z.object({ status: z.literal('expired'), results: z.array(pushItemResultSchema) }).strict(),
  z.object({ status: z.literal('rejected'), reason: z.enum(PUSH_REJECT_REASONS), results: z.tuple([]) }).strict(),
]);
export type PushResponse = z.infer<typeof pushResponseSchema>;
