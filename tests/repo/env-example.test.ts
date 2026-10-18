import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// K27: .env.example hanya boleh berisi placeholder. Nilai lain (termasuk kunci "contoh") membuat CI gagal.
const PLACEHOLDER_LINE = /^([A-Z][A-Z0-9_]*)=(?:<([A-Z][A-Z0-9_]*)>)?$/;

describe('.env.example', () => {
  const lines = readFileSync(new URL('../../.env.example', import.meta.url), 'utf8')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l !== '' && !l.startsWith('#'));

  it('punya minimal satu variabel', () => {
    expect(lines.length).toBeGreaterThan(0);
  });

  it.each(lines)('%s berbentuk NAMA=<NAMA> atau NAMA=', (line) => {
    const m = PLACEHOLDER_LINE.exec(line);
    expect(m, `bukan placeholder: ${line}`).not.toBeNull();
    if (m?.[2] !== undefined) expect(m[2]).toBe(m[1]);
  });
});
