import type { Category } from '@guestbook/shared';

/** Hasil RPC get_event_stats (FR-S-01..05; definisi di docs/plan.md 10.3 dan 12). */
export interface EventStats {
  serverTime: string;
  peoplePresent: number;
  rsvpGoingGuests: number;
  rsvpGoingPax: number;
  invitedTotal: number;
  limit: number;
  limitSource: 'manual' | 'invited_total';
  overLimit: boolean;
  categories: { category: Category; people: number; rsvpPax: number; guestsPresent: number }[];
  invitedCheckedIn: number;
  guestsPresent: number;
  guestsCheckedOut: number;
  additionalGuests: number;
  additionalPeople: number;
  beyondRecorded: number;
  review: { quarantined: number; duplicate: number; conflict: number };
}

export interface TimelineBucket {
  bucket_start: string;
  guests: number;
  people: number;
}

export const LIMIT_SOURCE_LABEL: Record<EventStats['limitSource'], string> = {
  manual: 'diatur manual',
  invited_total: 'total undangan',
};

/** Ringkasan "3 karantina · 2 ganda · 1 nomor bentrok" (hanya bagian yang tidak nol). */
export function reviewSummary(r: EventStats['review']): string {
  return [
    r.quarantined && `${r.quarantined} karantina`,
    r.duplicate && `${r.duplicate} ganda`,
    r.conflict && `${r.conflict} nomor bentrok`,
  ]
    .filter(Boolean)
    .join(' · ');
}
