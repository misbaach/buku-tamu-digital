import { expect, test } from '@playwright/test';
import { loginAsAdmin } from './helpers';

// prd.md 10.4: CSP ketat (tanpa unsafe-eval, connect-src hanya ke Supabase), nosniff, referrer policy,
// Permissions-Policy tanpa kamera untuk dashboard.
const supabaseOrigin = new URL(process.env.PUBLIC_SUPABASE_URL ?? 'http://127.0.0.1:54321').origin;

test.describe('header keamanan Cloudflare Pages', () => {
  for (const path of ['/', '/masuk', '/acara/tidak-ada']) {
    test(`header pada ${path}`, async ({ request }) => {
      const res = await request.get(path);
      expect(res.status()).toBe(200);
      const h = res.headers();
      expect(h['content-security-policy']).toContain("frame-ancestors 'none'");
      expect(h['content-security-policy']).toContain("object-src 'none'");
      expect(h['x-content-type-options']).toBe('nosniff');
      expect(h['referrer-policy']).toBe('strict-origin-when-cross-origin');
      expect(h['permissions-policy']).toContain('camera=()');
      expect(h['x-frame-options']).toBe('DENY');
    });
  }

  test('CSP meta: skrip lewat hash, tanpa unsafe-eval/unsafe-inline, koneksi hanya ke Supabase', async ({
    request,
  }) => {
    const html = await (await request.get('/masuk')).text();
    const csp = /<meta http-equiv="content-security-policy" content="([^"]+)"/.exec(html)?.[1];
    expect(csp, 'meta CSP harus ada').toBeTruthy();
    expect(csp).toContain("default-src 'none'");
    expect(csp).toMatch(/script-src 'self' 'sha256-[A-Za-z0-9+/=]+'/);
    expect(csp).not.toContain('unsafe-eval');
    expect(csp).not.toContain('unsafe-inline');
    const connect =
      /connect-src ([^;]+)/
        .exec(csp ?? '')?.[1]
        ?.trim()
        .split(/\s+/) ?? [];
    expect(connect.sort()).toEqual(["'self'", supabaseOrigin, supabaseOrigin.replace(/^http/, 'ws')].sort());
  });

  test('tidak ada pelanggaran CSP dari kode aplikasi selama alur masuk dan memuat data', async ({ page }) => {
    await page.addInitScript(() => {
      (window as unknown as { __csp: string[] }).__csp = [];
      document.addEventListener('securitypolicyviolation', (e) => {
        (window as unknown as { __csp: string[] }).__csp.push(
          `${e.violatedDirective} ${e.blockedURI} ${e.sourceFile}:${e.lineNumber}`,
        );
      });
    });
    await loginAsAdmin(page);
    await expect(page.getByRole('row', { name: /Resepsi Rina & Bayu/ })).toBeVisible();
    const violations = await page.evaluate(() => (window as unknown as { __csp: string[] }).__csp);

    // Satu-satunya pengecualian yang diketahui (docs/decisions.md T-033): elemen pengumum rute bawaan
    // SvelteKit punya atribut style di template-nya; browser melaporkannya saat template di-parse. CSP tidak
    // dilonggarkan. Selain itu, tidak boleh ada elemen lain ber-atribut style, dan tidak boleh ada jenis
    // pelanggaran lain (skrip, koneksi, font, gambar).
    expect(violations.filter((v) => !v.startsWith('style-src-attr '))).toEqual([]);
    const styled = await page.evaluate(() =>
      [...document.querySelectorAll('[style]')].map((el) => el.id || el.tagName),
    );
    expect(styled.filter((id) => id !== 'svelte-announcer')).toEqual([]);
    const announcer = await page.locator('#svelte-announcer').boundingBox();
    expect(announcer === null || (announcer.width <= 1 && announcer.height <= 1)).toBe(true);
  });
});
