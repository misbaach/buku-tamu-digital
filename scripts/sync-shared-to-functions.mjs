// Menyalin bagian packages/shared yang dipakai Edge Function ke supabase/functions/_shared/shared
// (docs/decisions.md T-006). Bundler Edge Function tidak dijamin bisa mengimpor dari luar folder functions.
//   node scripts/sync-shared-to-functions.mjs           tulis salinan
//   node scripts/sync-shared-to-functions.mjs --check   gagal bila salinan basi (dipakai tests/repo)
import { mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'packages/shared/src');
const dest = join(root, 'supabase/functions/_shared/shared');

/** File yang disalin. Hanya boleh saling mengimpor di antara file-file ini (dan 'zod'). */
export const FILES = ['config.ts', 'enums.ts', 'patterns.ts', 'zod.ts', 'schemas/usher.ts'];

const zodVersion = JSON.parse(readFileSync(join(root, 'packages/shared/package.json'), 'utf8')).dependencies.zod;

export function expectedFiles() {
  return FILES.map((file) => {
    let text = readFileSync(join(src, file), 'utf8');
    for (const m of text.matchAll(/from '(\.[^']+)'/g)) {
      const target = join(dirname(file), m[1]).replaceAll('\\', '/');
      if (!FILES.includes(target)) throw new Error(`${file} mengimpor ${m[1]} yang tidak ikut disalin.`);
    }
    text = text.replaceAll("from 'zod'", `from 'npm:zod@${zodVersion}'`);
    const header = `// SALINAN OTOMATIS dari packages/shared/src/${file}. Jangan diedit; jalankan \`pnpm functions:sync\`.\n`;
    return { file, text: header + text };
  });
}

function listCopied(dir = dest) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? listCopied(join(dir, e.name)) : [relative(dest, join(dir, e.name)).replaceAll('\\', '/')],
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const files = expectedFiles();
  if (process.argv.includes('--check')) {
    const stale = files.filter(({ file, text }) => {
      const p = join(dest, file);
      return !existsSync(p) || readFileSync(p, 'utf8') !== text;
    });
    const extra = listCopied().filter((f) => !FILES.includes(f));
    if (stale.length || extra.length) {
      console.error(
        `Salinan _shared basi: ${[...stale.map((s) => s.file), ...extra].join(', ')}. Jalankan \`pnpm functions:sync\`.`,
      );
      process.exit(1);
    }
    console.log('Salinan _shared sesuai packages/shared.');
  } else {
    rmSync(dest, { recursive: true, force: true });
    for (const { file, text } of files) {
      mkdirSync(dirname(join(dest, file)), { recursive: true });
      writeFileSync(join(dest, file), text);
    }
    console.log(`${files.length} file disalin ke ${relative(root, dest)}.`);
  }
}
