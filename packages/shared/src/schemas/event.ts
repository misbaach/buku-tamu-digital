import { z } from '../zod.ts';

/** Zona waktu Indonesia. Disimpan per acara untuk menghitung akhir sesi usher (FR-R-10). */
export const EVENT_TIMEZONES = [
  { value: 'Asia/Jakarta', label: 'WIB (Asia/Jakarta)' },
  { value: 'Asia/Makassar', label: 'WITA (Asia/Makassar)' },
  { value: 'Asia/Jayapura', label: 'WIT (Asia/Jayapura)' },
] as const;

const optionalText = (max: number, label: string) =>
  z
    .string()
    .trim()
    .max(max, `${label} maksimal ${max} karakter.`)
    .transform((v) => (v === '' ? null : v));

export const eventFormSchema = z.object({
  name: z.string().trim().min(1, 'Isi nama acara.').max(120, 'Nama acara maksimal 120 karakter.'),
  couple_names: optionalText(200, 'Nama mempelai'),
  event_date: z.iso.date({ error: 'Isi tanggal acara.' }),
  venue: optionalText(200, 'Tempat'),
  timezone: z.enum(EVENT_TIMEZONES.map((t) => t.value) as [string, ...string[]], { error: 'Pilih zona waktu.' }),
});

export type EventFormValues = z.output<typeof eventFormSchema>;

/** Batas jumlah hadir (FR-S-01): kosong = memakai total jumlah undangan. */
export const attendanceLimitSchema = z
  .string()
  .trim()
  .transform((v, ctx) => {
    if (v === '') return null;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 1 || n > 1_000_000) {
      ctx.addIssue({ code: 'custom', message: 'Isi angka bulat lebih dari 0, atau kosongkan.' });
      return z.NEVER;
    }
    return n;
  });
