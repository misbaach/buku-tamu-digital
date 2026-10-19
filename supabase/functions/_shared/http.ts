// Helper HTTP bersama Edge Function. Tidak pernah mencatat token, PIN, atau kunci ke log.

/** CORS hanya untuk origin yang terdaftar di env (dipisah koma). Tanpa daftar = tidak ada header CORS. */
export function corsHeaders(req: Request, envName: string): Headers {
  const headers = new Headers({ Vary: 'Origin' });
  const origin = req.headers.get('origin');
  const allowed = (Deno.env.get(envName) ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  if (origin && allowed.includes(origin)) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'authorization, apikey, content-type, x-client-info');
    headers.set('Access-Control-Max-Age', '600');
  }
  return headers;
}

export function json(body: unknown, status: number, base: Headers, extra: Record<string, string> = {}): Response {
  const headers = new Headers(base);
  headers.set('Content-Type', 'application/json; charset=utf-8');
  headers.set('Cache-Control', 'no-store');
  for (const [k, v] of Object.entries(extra)) headers.set(k, v);
  return new Response(JSON.stringify(body), { status, headers });
}

/**
 * IP klien untuk rate limit (FR-R-09). `cf-connecting-ip` ditulis ulang Cloudflare di depan Supabase sehingga
 * tidak bisa dipalsukan klien; bila tidak ada, dipakai entri PALING KANAN `x-forwarded-for` (ditambahkan
 * gateway), bukan entri pertama yang bisa diisi klien. Diverifikasi ulang di lingkungan produksi (M6).
 */
export function clientIp(req: Request): string {
  const cf = req.headers.get('cf-connecting-ip')?.trim();
  if (cf) return cf;
  const parts = (req.headers.get('x-forwarded-for') ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  return parts.at(-1) ?? 'unknown';
}

/** Menahan respons sampai minimal `minMs` sejak `startedAt`, agar waktu semua respons gagal seragam. */
export async function padUntil(startedAt: number, minMs: number): Promise<void> {
  const wait = minMs - (performance.now() - startedAt);
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
}

/** Perbandingan string waktu-konstan (secret job). */
export function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

/** Password acak user Auth perangkat; tidak pernah keluar dari Edge Function. */
export function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/[+/=]/g, (c) => ({ '+': '-', '/': '_', '=': '' })[c] ?? '');
}

export function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Env ${name} belum diatur.`);
  return value;
}
