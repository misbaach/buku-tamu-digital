// `pnpm db:types`: tipe TypeScript dari skema DB lokal → packages/shared/src/database.types.ts.
// Dengan --check, skrip gagal bila berkas yang di-commit sudah tidak sama dengan skema (dipakai CI).
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const target = join(root, 'packages', 'shared', 'src', 'database.types.ts');
const cli = createRequire(join(root, 'package.json')).resolve('supabase/dist/supabase.js');

const generated = execFileSync(process.execPath, [cli, 'gen', 'types', 'typescript', '--local', '--schema', 'public'], {
  cwd: root,
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'inherit'],
});
const content = `// BERKAS HASIL GENERATE — jangan diedit. Jalankan \`pnpm db:types\` setelah mengubah migration.\n${generated.replace(/\r\n/g, '\n')}`;

if (process.argv.includes('--check')) {
  let current = '';
  try {
    current = readFileSync(target, 'utf8');
  } catch {
    // Berkas belum ada: dianggap tidak sesuai.
  }
  if (current !== content) {
    console.error('database.types.ts tidak sesuai skema. Jalankan `pnpm db:types` lalu commit hasilnya.');
    process.exit(1);
  }
  console.log('database.types.ts sesuai skema.');
} else {
  writeFileSync(target, content);
  console.log(`Tipe DB ditulis ke ${target}`);
}
