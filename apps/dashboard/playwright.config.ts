import { existsSync } from 'node:fs';
import { defineConfig, devices } from '@playwright/test';

// Lokal di Windows: pakai Microsoft Edge bawaan sistem (docs/decisions.md T-034). CI: Chromium bawaan Playwright.
const edge = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const channel =
  process.env.PW_CHANNEL ??
  (!process.env.CI && process.platform === 'win32' && existsSync(edge) ? 'msedge' : undefined);
const browser = { ...devices['Desktop Chrome'], ...(channel ? { channel } : {}) };

export const ADMIN_STATE = 'e2e/.auth/admin.json';

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    // wrangler pages dev menerapkan static/_headers persis seperti Cloudflare Pages.
    baseURL: 'http://127.0.0.1:8788',
    locale: 'id-ID',
    trace: 'retain-on-failure',
  },
  projects: [
    // Login Admin sekali, sesinya dipakai ulang (batas login GoTrue: 30 per 5 menit per IP).
    { name: 'setup', testMatch: /auth\.setup\.ts/, use: browser },
    // Alur masuk/keluar dan header diuji tanpa sesi tersimpan.
    { name: 'public', testMatch: /(auth|headers)\.spec\.ts/, use: browser },
    {
      name: 'admin',
      testIgnore: /(auth|headers)\.spec\.ts|auth\.setup\.ts/,
      dependencies: ['setup'],
      use: { ...browser, storageState: ADMIN_STATE },
    },
  ],
  webServer: {
    command: 'pnpm build && pnpm preview:pages',
    url: 'http://127.0.0.1:8788/masuk',
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    env: { WRANGLER_SEND_METRICS: 'false' },
  },
});
