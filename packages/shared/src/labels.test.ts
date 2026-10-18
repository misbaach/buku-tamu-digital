import { describe, expect, it } from 'vitest';
import { ATTENDANCE_LABEL, checkInBadge, rsvpLabel } from './labels.ts';

describe('label UI (prd.md bagian 5)', () => {
  it('RSVP', () => {
    expect(rsvpLabel('going', 3)).toBe('Akan hadir (3 orang)');
    expect(rsvpLabel('not_going', null)).toBe('Tidak hadir');
    expect(rsvpLabel('unconfirmed', null)).toBe('Belum konfirmasi');
  });

  it('kehadiran', () => {
    expect(ATTENDANCE_LABEL.not_arrived).toBe('Belum hadir');
    expect(ATTENDANCE_LABEL.checked_in).toBe('Hadir');
    expect(ATTENDANCE_LABEL.checked_out).toBe('Hadir');
  });

  it('status yang perlu ditinjau memakai penanda yang sama', () => {
    const base = { reviewedAt: null, voidedAt: null };
    expect(checkInBadge({ ...base, status: 'duplicate' })).toEqual({
      text: 'Ganda — tinjau',
      needsReview: true,
      voided: false,
    });
    expect(checkInBadge({ ...base, status: 'conflict' })).toEqual({
      text: 'Nomor bentrok — tinjau',
      needsReview: true,
      voided: false,
    });
    expect(checkInBadge({ ...base, status: 'quarantined' })).toEqual({
      text: 'Karantina — tinjau',
      needsReview: true,
      voided: false,
    });
  });

  it('status biasa tanpa penanda', () => {
    const base = { reviewedAt: null, voidedAt: null };
    expect(checkInBadge({ ...base, status: 'accepted' })).toEqual({ text: 'Sah', needsReview: false, voided: false });
    expect(checkInBadge({ ...base, status: 'repeat' })).toEqual({
      text: 'Masuk ulang',
      needsReview: false,
      voided: false,
    });
  });

  it('setelah ditinjau: "· ditinjau" tanpa penanda (K32); dibatalkan menang atas status apa pun', () => {
    expect(checkInBadge({ status: 'duplicate', reviewedAt: '2026-10-18T10:00:00Z', voidedAt: null })).toEqual({
      text: 'Ganda · ditinjau',
      needsReview: false,
      voided: false,
    });
    expect(checkInBadge({ status: 'conflict', reviewedAt: null, voidedAt: '2026-10-18T10:00:00Z' })).toEqual({
      text: 'Dibatalkan',
      needsReview: false,
      voided: true,
    });
  });
});
