import { z } from '../zod.ts';
import { CATEGORIES, RSVP_STATUSES } from '../enums.ts';
import { checkSpecialNumber, normalizeSpecialNumber } from '../patterns.ts';
import { specialNumberMessage } from './common.ts';

/** Sama dengan constraint guests_phone_format di database. */
export const PHONE_PATTERN = /^\+?[0-9][0-9 ().-]{4,22}$/;

const blankToNull = (v: unknown) => (typeof v === 'string' && v.trim() === '' ? null : v);

export const guestNameSchema = z.string().trim().min(1, 'Isi nama tamu.').max(120, 'Nama maksimal 120 karakter.');

export const phoneSchema = z.preprocess(
  blankToNull,
  z
    .string()
    .trim()
    .transform((v) => v.replace(/\s+/g, ' '))
    .refine((v) => PHONE_PATTERN.test(v), 'Format nomor telepon tidak valid. Contoh: +62 812-3456-7890.')
    .nullable(),
);

/** Nomor Urut opsional: kosong → null; selain itu dinormalisasi lalu divalidasi (FR-C-02). */
export const optionalSpecialNumberSchema = z.preprocess(
  blankToNull,
  z
    .string()
    .transform(normalizeSpecialNumber)
    .superRefine((value, ctx) => {
      const issue = checkSpecialNumber(value);
      if (issue) ctx.addIssue({ code: 'custom', message: specialNumberMessage(issue, value) });
    })
    .nullable(),
);

const paxSchema = (min: number, label: string) =>
  z.coerce
    .number({ error: `${label} harus berupa angka.` })
    .int(`${label} harus bilangan bulat.`)
    .min(min, `${label} minimal ${min}.`)
    .max(50, `${label} maksimal 50.`);

/** Form tambah/ubah tamu (FR-G-01, FR-G-02, FR-G-06). Nilainya siap dikirim ke tabel guests. */
export const guestFormSchema = z
  .object({
    name: guestNameSchema,
    phone: phoneSchema,
    category: z.enum(CATEGORIES, { error: 'Pilih kategori.' }),
    group_id: z.preprocess(blankToNull, z.uuid().nullable()),
    invited_pax: paxSchema(1, 'Jumlah undangan'),
    special_number: optionalSpecialNumberSchema,
    rsvp_status: z.enum(RSVP_STATUSES, { error: 'Pilih status RSVP.' }),
    rsvp_pax: z.preprocess(blankToNull, paxSchema(0, 'Jumlah konfirmasi').nullable()),
    notes: z.preprocess(blankToNull, z.string().trim().max(500, 'Catatan maksimal 500 karakter.').nullable()),
  })
  // Jumlah konfirmasi hanya bermakna bila Akan hadir (constraint guests_rsvp_pax_only_if_going).
  .transform((v) => (v.rsvp_status === 'going' ? v : { ...v, rsvp_pax: null }));

export type GuestFormValues = z.output<typeof guestFormSchema>;
