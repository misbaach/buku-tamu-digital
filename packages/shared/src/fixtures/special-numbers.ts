import type { SpecialNumberIssue } from '../patterns.ts';

/**
 * Kasus uji nomor khusus (FR-C-02). Dipakai oleh tes unit (Zod/validator) DAN tes integrasi yang
 * mengirim nilai yang sama ke constraint CHECK di database, sehingga keduanya tidak bisa berbeda diam-diam.
 * `value` sudah dalam bentuk ternormalisasi (huruf besar), seperti yang disimpan DB.
 */
export const SPECIAL_NUMBER_CASES: ReadonlyArray<{ value: string; issue: SpecialNumberIssue | null }> = [
  { value: 'VVIP-007', issue: null },
  { value: 'VIP-001', issue: null },
  { value: 'MEJA1', issue: null },
  { value: '007', issue: null },
  { value: 'ABC-12', issue: null },
  { value: 'A-B-1', issue: null },
  { value: '-', issue: null },
  { value: 'X'.repeat(20), issue: null },
  { value: '', issue: 'empty' },
  { value: 'X'.repeat(21), issue: 'too_long' },
  { value: 'VIP 001', issue: 'invalid_chars' },
  { value: 'VIP_001', issue: 'invalid_chars' },
  { value: 'VİP-001', issue: 'invalid_chars' },
  { value: 'A-017', issue: 'device_pattern' },
  { value: 'AB-1', issue: 'device_pattern' },
  { value: 'Z-0', issue: 'device_pattern' },
  { value: 'A-H012', issue: 'gift_pattern' },
  { value: 'ZZ-H1', issue: 'gift_pattern' },
];
