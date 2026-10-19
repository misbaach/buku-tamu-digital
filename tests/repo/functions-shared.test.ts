// Salinan packages/shared di supabase/functions/_shared tidak boleh basi (docs/decisions.md T-006), dan Edge
// Function tidak boleh memegang kunci apa pun selain dari env runtime.
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = join(import.meta.dirname, '../..');
const functionsDir = join(root, 'supabase/functions');

function tsFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? tsFiles(join(dir, e.name)) : e.name.endsWith('.ts') ? [join(dir, e.name)] : [],
  );
}

describe('Edge Function', () => {
  it('salinan _shared sama dengan packages/shared', () => {
    expect(() =>
      execFileSync(process.execPath, [join(root, 'scripts/sync-shared-to-functions.mjs'), '--check'], {
        stdio: 'pipe',
      }),
    ).not.toThrow();
  });

  it('versi supabase-js Edge Function sama dengan dashboard', () => {
    const dashboard = JSON.parse(readFileSync(join(root, 'apps/dashboard/package.json'), 'utf8'));
    const deps = readFileSync(join(functionsDir, '_shared/deps.ts'), 'utf8');
    expect(deps).toContain(`npm:@supabase/supabase-js@${dashboard.dependencies['@supabase/supabase-js']}'`);
  });

  it('tidak ada kunci atau URL tertanam; kunci hanya dari Deno.env', () => {
    for (const file of tsFiles(functionsDir)) {
      const text = readFileSync(file, 'utf8');
      expect(text, file).not.toMatch(
        /eyJ[A-Za-z0-9_-]{10,}|sb_(secret|publishable)_[A-Za-z0-9_-]+|https?:\/\/[a-z0-9]+\.supabase\.co/,
      );
    }
  });
});
