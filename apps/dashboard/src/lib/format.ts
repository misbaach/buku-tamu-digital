const dateFormat = new Intl.DateTimeFormat('id-ID', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
});

/** Kolom `date` Postgres (YYYY-MM-DD) dibaca sebagai tanggal kalender lokal, bukan UTC. */
export function formatEventDate(isoDate: string): string {
  const [y, m, d] = isoDate.split('-').map(Number);
  if (!y || !m || !d) return isoDate;
  return dateFormat.format(new Date(y, m - 1, d));
}

const numberFormat = new Intl.NumberFormat('id-ID');

export function formatNumber(n: number): string {
  return numberFormat.format(n);
}
