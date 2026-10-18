import type { Database } from '@guestbook/shared/database.types';

type Tables = Database['public']['Tables'];
export type EventRow = Tables['events']['Row'];
export type GuestRow = Tables['guests']['Row'];
export type GroupRow = Tables['guest_groups']['Row'];
export type CheckInRow = Tables['check_ins']['Row'];
export type TicketNumberSettingRow = Tables['ticket_number_settings']['Row'];
