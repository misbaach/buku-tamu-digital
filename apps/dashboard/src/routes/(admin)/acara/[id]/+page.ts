import { redirect } from '@sveltejs/kit';

// Halaman utama acara adalah Tamu sampai Statistik dibuat di M3.
export function load({ params }) {
  redirect(307, `/acara/${params.id}/tamu`);
}
