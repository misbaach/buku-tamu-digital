import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      { test: { name: 'shared', include: ['packages/shared/src/**/*.test.ts'] } },
      { test: { name: 'repo', include: ['tests/repo/**/*.test.ts'] } },
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
