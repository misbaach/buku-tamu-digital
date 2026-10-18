/**
 * Aturan impor tamu (FR-G-03): kolom templat, validasi per baris, dan pemeriksaan antarbaris.
 * Parsing berkas (SheetJS) dilakukan di dashboard; modul ini hanya menerima nilai sel berupa teks.
 */
import { z } from './zod.ts';
import type { Category, RsvpStatus } from './enums.ts';
import { guestNameSchema, optionalSpecialNumberSchema, phoneSchema } from './schemas/guest.ts';

export interface ImportColumn {
  key: ImportField;
  header: string;
  aliases: readonly string[];
  required?: boolean;
  example: string;
  hint: string;
}

export type ImportField =
  'name' | 'phone' | 'category' | 'group' | 'invited_pax' | 'special_number' | 'rsvp_status' | 'rsvp_pax' | 'notes';

/** Urutan kolom templat. Header dicocokkan tanpa peka huruf besar/kecil, spasi, dan tanda baca. */
export const IMPORT_COLUMNS: readonly ImportColumn[] = [
  {
    key: 'name',
    header: 'Nama',
    aliases: ['nama tamu'],
    required: true,
    example: 'Budi Santoso',
    hint: 'Wajib diisi.',
  },
  {
    key: 'phone',
    header: 'Telepon',
    aliases: ['no hp', 'hp', 'nomor telepon', 'whatsapp', 'wa'],
    example: '+62 812-3456-7890',
    hint: 'Opsional.',
  },
  {
    key: 'category',
    header: 'Kategori',
    aliases: [],
    example: 'VIP',
    hint: 'Regular, VIP, atau VVIP. Kosong = Regular.',
  },
  {
    key: 'group',
    header: 'Grup',
    aliases: ['group'],
    example: 'Keluarga Mempelai Pria',
    hint: 'Grup baru dibuat otomatis.',
  },
  {
    key: 'invited_pax',
    header: 'Jumlah Undangan',
    aliases: ['pax', 'jumlah'],
    example: '2',
    hint: 'Angka 1–50. Kosong = 1.',
  },
  {
    key: 'special_number',
    header: 'Nomor Urut',
    aliases: ['no urut', 'nomor khusus'],
    example: 'VIP-001',
    hint: 'Opsional, unik. Tidak boleh berpola seperti A-017.',
  },
  {
    key: 'rsvp_status',
    header: 'Status RSVP',
    aliases: ['rsvp', 'konfirmasi'],
    example: 'Akan hadir',
    hint: 'Akan hadir, Tidak hadir, atau Belum konfirmasi. Kosong = Belum konfirmasi.',
  },
  {
    key: 'rsvp_pax',
    header: 'Jumlah Konfirmasi',
    aliases: ['pax rsvp', 'jumlah hadir'],
    example: '2',
    hint: 'Diisi bila Akan hadir. Angka 0–50.',
  },
  { key: 'notes', header: 'Catatan', aliases: ['keterangan'], example: '', hint: 'Opsional, maksimal 500 karakter.' },
];

const normalizeHeader = (h: string) =>
  h
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();

/** Memetakan header berkas ke kunci kolom. Header yang tidak dikenal diabaikan. */
export function mapImportHeaders(headers: readonly string[]): {
  map: Map<number, ImportField>;
  missing: ImportField[];
} {
  const lookup = new Map<string, ImportField>();
  for (const c of IMPORT_COLUMNS) {
    for (const h of [c.header, ...c.aliases]) lookup.set(normalizeHeader(h), c.key);
  }
  const map = new Map<number, ImportField>();
  headers.forEach((h, i) => {
    const key = lookup.get(normalizeHeader(String(h ?? '')));
    if (key && ![...map.values()].includes(key)) map.set(i, key);
  });
  const missing = IMPORT_COLUMNS.filter((c) => c.required && ![...map.values()].includes(c.key)).map((c) => c.key);
  return { map, missing };
}

const CATEGORY_ALIASES: Record<string, Category> = { regular: 'regular', reguler: 'regular', vip: 'vip', vvip: 'vvip' };
const RSVP_ALIASES: Record<string, RsvpStatus> = {
  'akan hadir': 'going',
  hadir: 'going',
  going: 'going',
  ya: 'going',
  'tidak hadir': 'not_going',
  'not going': 'not_going',
  not_going: 'not_going',
  tidak: 'not_going',
  'belum konfirmasi': 'unconfirmed',
  unconfirmed: 'unconfirmed',
  "haven't confirmed": 'unconfirmed',
  belum: 'unconfirmed',
};

const optionalInt = (label: string, min: number) =>
  z
    .string()
    .trim()
    .transform((v, ctx) => {
      if (v === '') return null;
      const n = Number(v.replace(',', '.'));
      if (!Number.isInteger(n) || n < min || n > 50) {
        ctx.addIssue({ code: 'custom', message: `${label} harus angka bulat ${min}–50.` });
        return z.NEVER;
      }
      return n;
    });

const rowSchema = z.object({
  name: guestNameSchema,
  phone: phoneSchema,
  category: z
    .string()
    .trim()
    .transform((v, ctx) => {
      if (v === '') return 'regular' as Category;
      const c = CATEGORY_ALIASES[v.toLowerCase()];
      if (!c) {
        ctx.addIssue({ code: 'custom', message: `Kategori "${v}" tidak dikenal. Pakai Regular, VIP, atau VVIP.` });
        return z.NEVER;
      }
      return c;
    }),
  group: z
    .string()
    .trim()
    .max(80, 'Nama grup maksimal 80 karakter.')
    .transform((v) => (v === '' ? null : v)),
  invited_pax: optionalInt('Jumlah undangan', 1).transform((v) => v ?? 1),
  special_number: optionalSpecialNumberSchema,
  rsvp_status: z
    .string()
    .trim()
    .transform((v, ctx) => {
      if (v === '') return 'unconfirmed' as RsvpStatus;
      const s = RSVP_ALIASES[v.toLowerCase()];
      if (!s) {
        ctx.addIssue({
          code: 'custom',
          message: `Status RSVP "${v}" tidak dikenal. Pakai Akan hadir, Tidak hadir, atau Belum konfirmasi.`,
        });
        return z.NEVER;
      }
      return s;
    }),
  rsvp_pax: optionalInt('Jumlah konfirmasi', 0),
  notes: z
    .string()
    .trim()
    .max(500, 'Catatan maksimal 500 karakter.')
    .transform((v) => (v === '' ? null : v)),
});

/**
 * Aturan antarkolom diperiksa di luar skema: Zod melewati refinement objek bila ada kolom lain yang gagal,
 * padahal Tinjau Tamu harus menampilkan semua galat satu baris sekaligus.
 */
function rsvpPaxIssue(raw: Record<ImportField, string>): ImportIssue | null {
  const status = raw.rsvp_status.trim() === '' ? 'unconfirmed' : RSVP_ALIASES[raw.rsvp_status.trim().toLowerCase()];
  if (raw.rsvp_pax.trim() !== '' && status !== undefined && status !== 'going') {
    return { field: 'rsvp_pax', message: 'Jumlah konfirmasi hanya diisi bila status Akan hadir.' };
  }
  return null;
}

export type ImportRow = z.output<typeof rowSchema> & { row: number };

export interface ImportIssue {
  field: ImportField | null;
  message: string;
}

export type ImportRowResult =
  | { row: number; ok: true; value: ImportRow; raw: Record<ImportField, string> }
  | { row: number; ok: false; issues: ImportIssue[]; raw: Record<ImportField, string> };

/** Validasi satu baris. `cells` berisi teks per kolom (kunci yang tidak ada dianggap kosong). */
export function validateImportRow(row: number, cells: Partial<Record<ImportField, string>>): ImportRowResult {
  const raw = Object.fromEntries(IMPORT_COLUMNS.map((c) => [c.key, String(cells[c.key] ?? '')])) as Record<
    ImportField,
    string
  >;
  const parsed = rowSchema.safeParse(raw);
  const crossIssue = rsvpPaxIssue(raw);
  if (parsed.success && !crossIssue) return { row, ok: true, value: { ...parsed.data, row }, raw };
  const issues: ImportIssue[] = parsed.success
    ? []
    : parsed.error.issues.map((i) => ({ field: (i.path[0] as ImportField | undefined) ?? null, message: i.message }));
  if (crossIssue) issues.push(crossIssue);
  return { row, ok: false, raw, issues };
}

/**
 * Pemeriksaan antarbaris dan terhadap database: Nomor Urut ganda di dalam berkas, atau sudah dipakai tamu lain.
 * Mengembalikan hasil baru; baris yang sebelumnya valid bisa menjadi bermasalah.
 */
export function crossCheckImport(results: ImportRowResult[], usedInDb: ReadonlyMap<string, string>): ImportRowResult[] {
  const seen = new Map<string, number>();
  for (const r of results) {
    if (r.ok && r.value.special_number) {
      const n = r.value.special_number;
      if (!seen.has(n)) seen.set(n, r.row);
    }
  }
  return results.map((r) => {
    if (!r.ok || !r.value.special_number) return r;
    const n = r.value.special_number;
    const issues: ImportIssue[] = [];
    const first = seen.get(n);
    if (first !== undefined && first !== r.row) {
      issues.push({
        field: 'special_number',
        message: `Nomor Urut "${n}" sudah dipakai baris ${first} di berkas ini.`,
      });
    }
    const owner = usedInDb.get(n);
    if (owner !== undefined) {
      issues.push({ field: 'special_number', message: `Nomor Urut "${n}" sudah dipakai tamu "${owner}".` });
    }
    return issues.length ? { row: r.row, ok: false, raw: r.raw, issues } : r;
  });
}
