import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      { test: { name: 'shared', include: ['packages/shared/src/**/*.test.ts'] } },
      { test: { name: 'repo', include: ['tests/repo/**/*.test.ts'] } },
      // Logika murni dashboard (tanpa DOM); komponen diuji lewat Playwright.
      { test: { name: 'dashboard', include: ['apps/dashboard/src/lib/**/*.test.ts'] } },
      {
        // Butuh Supabase lokal yang sedang berjalan (`pnpm db:start`).
        test: {
          name: 'integration',
          include: ['tests/integration/**/*.test.ts'],
          testTimeout: 30_000,
          fileParallelism: false,
        },
      },
    ],
  },
});
