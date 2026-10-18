#!/usr/bin/env node
// Menjalankan gitleaks versi yang dipin. Binary diunduh sekali ke .tools/, diverifikasi dengan
// SHA-256 resmi (disalin dari gitleaks_<versi>_checksums.txt), lalu dipakai oleh hook pre-commit dan CI.
// Pemakaian: node scripts/gitleaks.mjs <argumen gitleaks...>
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const VERSION = '8.30.1';
const ASSETS = {
  'win32-x64': { file: `gitleaks_${VERSION}_windows_x64.zip`, sha256: 'd29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e' },
  'linux-x64': { file: `gitleaks_${VERSION}_linux_x64.tar.gz`, sha256: '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb' },
  'darwin-x64': { file: `gitleaks_${VERSION}_darwin_x64.tar.gz`, sha256: 'dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709' },
  'darwin-arm64': { file: `gitleaks_${VERSION}_darwin_arm64.tar.gz`, sha256: 'b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5' },
};

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const toolDir = join(root, '.tools', `gitleaks-${VERSION}`);
const binary = join(toolDir, process.platform === 'win32' ? 'gitleaks.exe' : 'gitleaks');

async function install() {
  const key = `${process.platform}-${process.arch}`;
  const asset = ASSETS[key];
  if (!asset) throw new Error(`gitleaks: platform ${key} belum didukung skrip ini`);

  const url = `https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${asset.file}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`gitleaks: gagal mengunduh ${url} (${res.status})`);
  const data = Buffer.from(await res.arrayBuffer());

  const actual = createHash('sha256').update(data).digest('hex');
  if (actual !== asset.sha256) {
    throw new Error(`gitleaks: checksum tidak cocok untuk ${asset.file}\n  diharapkan ${asset.sha256}\n  didapat    ${actual}`);
  }

  mkdirSync(toolDir, { recursive: true });
  const archive = join(toolDir, asset.file);
  writeFileSync(archive, data);
  // tar bawaan Windows (bsdtar) bisa membuka .zip; tar GNU di Git Bash tidak, jadi pakai path System32.
  const tar = process.platform === 'win32' ? join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'tar.exe') : 'tar';
  const out = spawnSync(tar, ['-xf', archive, '-C', toolDir], { stdio: 'inherit' });
  rmSync(archive);
  if (out.status !== 0 || !existsSync(binary)) throw new Error('gitleaks: gagal mengekstrak arsip');
}

if (!existsSync(binary)) {
  await install();
}

const result = spawnSync(binary, process.argv.slice(2), { stdio: 'inherit', cwd: root });
process.exit(result.status ?? 1);
