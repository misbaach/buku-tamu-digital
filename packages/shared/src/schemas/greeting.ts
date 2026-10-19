import { z } from '../zod.ts';
import { GREETING_BODY_MAX, GREETING_LAYOUTS, GREETING_TITLE_MAX, UPLOAD_MIME } from '../config.ts';
import type { Category } from '../enums.ts';

export type GreetingLayout = (typeof GREETING_LAYOUTS)[number];

/** Variabel teks sapaan (FR-P-02). Ditulis `{{nama}}` atau `{{ nama }}`. */
export const GREETING_VARIABLES = ['nama', 'kategori'] as const;
export type GreetingVariable = (typeof GREETING_VARIABLES)[number];

const VARIABLE = /\{\{\s*([^{}]*?)\s*\}\}/g;

/** Variabel yang tidak dikenal, mis. `{{namaa}}`; dipakai untuk menolak teks sebelum disimpan. */
export function unknownGreetingVariables(text: string): string[] {
  const found = [...text.matchAll(VARIABLE)].map((m) => m[1] ?? '');
  return [...new Set(found.filter((v) => !(GREETING_VARIABLES as readonly string[]).includes(v)))];
}

/** Mengganti variabel dengan nilainya. Hasilnya teks biasa: tampilkan sebagai teks, jangan sebagai HTML. */
export function renderGreeting(text: string, values: Record<GreetingVariable, string>): string {
  return text.replace(VARIABLE, (whole, name: string) =>
    (GREETING_VARIABLES as readonly string[]).includes(name) ? values[name as GreetingVariable] : whole,
  );
}

function greetingText(max: number, label: string) {
  return z
    .string()
    .trim()
    .max(max, `${label} maksimal ${max} karakter.`)
    .superRefine((value, ctx) => {
      const unknown = unknownGreetingVariables(value);
      if (unknown.length > 0) {
        ctx.addIssue({
          code: 'custom',
          message: `Variabel tidak dikenal: ${unknown.map((v) => `{{${v}}}`).join(', ')}. Yang tersedia: {{nama}} dan {{kategori}}.`,
        });
      }
    });
}

/** Isian editor pop-up sapaan (FR-P-01). Foto diunggah terpisah lalu path-nya disimpan. */
export const greetingFormSchema = z.object({
  title: greetingText(GREETING_TITLE_MAX, 'Judul').pipe(z.string().min(1, 'Judul wajib diisi.')),
  body: greetingText(GREETING_BODY_MAX, 'Teks'),
  layout: z.enum(GREETING_LAYOUTS),
});
export type GreetingForm = z.infer<typeof greetingFormSchema>;

/** Isi kolom greeting_configs.popup. Kosong (`{}`) berarti memakai GREETING_DEFAULTS. */
export interface GreetingPopup {
  title?: string;
  body?: string;
  layout?: GreetingLayout;
  photo_path?: string | null;
  photo_version?: number;
}

/** Sapaan bawaan per kategori; dipakai pratinjau dashboard dan App Penerima Tamu bila Admin belum mengatur. */
export const GREETING_DEFAULTS: Record<Category, GreetingForm> = {
  regular: { title: 'Selamat datang', body: 'Terima kasih atas kehadiran {{nama}}.', layout: 'text' },
  vip: {
    title: 'Selamat datang, {{nama}}',
    body: 'Terima kasih telah hadir sebagai tamu {{kategori}} kami.',
    layout: 'photo_wide',
  },
  vvip: { title: 'Selamat datang, {{nama}}', body: 'Suatu kehormatan atas kehadiran Anda.', layout: 'photo_round' },
};

export type UploadMime = (typeof UPLOAD_MIME)[number];

/**
 * Jenis gambar dari isi berkas (bukan dari nama atau tipe yang dilaporkan browser). SVG dan format lain
 * menghasilkan `null` dan ditolak sebelum diunggah (prd.md 10.4).
 */
export function detectImageMime(bytes: Uint8Array): UploadMime | null {
  const at = (i: number) => bytes[i] ?? -1;
  if ([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((b, i) => at(i) === b)) return 'image/png';
  if (at(0) === 0xff && at(1) === 0xd8 && at(2) === 0xff) return 'image/jpeg';
  const ascii = (from: number, to: number) => String.fromCharCode(...bytes.slice(from, to));
  if (bytes.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WEBP') return 'image/webp';
  return null;
}

export const IMAGE_EXTENSION: Record<UploadMime, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
};
