import { z } from '../zod.ts';
import { PRINT_TICKET_FIELDS, PRINT_TICKET_MAX_COPIES } from '../config.ts';
import { CATEGORIES } from '../enums.ts';

export type PrintTicketField = (typeof PRINT_TICKET_FIELDS)[number];

const unique = <T>(values: T[]) => new Set(values).size === values.length;

/** Print Tiket Penomoran (FR-R-04). Disimpan apa adanya di checkin_settings.print_ticket. */
export const printTicketSchema = z
  .object({
    enabled: z.boolean(),
    fields: z.array(z.enum(PRINT_TICKET_FIELDS)).refine(unique, 'Informasi tiket tidak boleh ganda.'),
    categories: z.array(z.enum(CATEGORIES)).refine(unique, 'Kategori tidak boleh ganda.'),
    copies: z
      .number({ message: 'Jumlah salinan harus angka.' })
      .int('Jumlah salinan harus bilangan bulat.')
      .min(1, 'Minimal 1 salinan.')
      .max(PRINT_TICKET_MAX_COPIES, `Maksimal ${PRINT_TICKET_MAX_COPIES} salinan.`),
  })
  .superRefine((v, ctx) => {
    if (!v.enabled) return;
    if (v.fields.length === 0)
      ctx.addIssue({ code: 'custom', path: ['fields'], message: 'Pilih minimal satu informasi.' });
    if (v.categories.length === 0) {
      ctx.addIssue({ code: 'custom', path: ['categories'], message: 'Pilih minimal satu kategori.' });
    }
  });
export type PrintTicket = z.infer<typeof printTicketSchema>;

/** Pengaturan Proses Check-In (FR-R-03). Print Hadiah Titipan menyusul bersama fitur Hadiah (P1, D16). */
export const checkinSettingsSchema = z.object({
  show_verification: z.boolean(),
  allow_multi_checkin: z.boolean(),
  print_ticket: printTicketSchema,
});
export type CheckinSettings = z.infer<typeof checkinSettingsSchema>;
