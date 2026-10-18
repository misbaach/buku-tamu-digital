import { writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import * as XLSX from 'xlsx';
import { IMPORT_COLUMNS } from '@guestbook/shared';
import { createEvent, uniqueName } from './api';

// Kriteria penerimaan MVP: impor 1.000 tamu, tinjau hasil di Tinjau Tamu, lalu proses.
test('impor 1.000 tamu dengan 3 baris bermasalah: tinjau, proses, lalu tampil di daftar', async ({
  page,
}, testInfo) => {
  test.setTimeout(120_000);
  const id = await createEvent(uniqueName('Impor Uji'));

  const rows: string[][] = [IMPORT_COLUMNS.map((c) => c.header)];
  for (let i = 1; i <= 1000; i++) {
    const going = i % 3 === 0;
    rows.push([
      `Tamu Impor ${String(i).padStart(4, '0')}`,
      i % 4 === 0 ? '' : `+62812${String(i).padStart(7, '0')}`,
      i % 50 === 0 ? 'VIP' : 'Regular',
      i % 2 === 0 ? 'Keluarga' : 'Teman Kantor',
      String(1 + (i % 3)),
      i <= 5 ? `IMP-${i}` : '',
      going ? 'Akan hadir' : i % 3 === 1 ? 'Belum konfirmasi' : 'Tidak hadir',
      going ? '2' : '',
      '',
    ]);
  }
  rows.splice(11, 0, ['', '', 'VIP', '', '', '', '', '', '']); // baris 12: nama kosong
  rows.splice(21, 0, ['Nomor Salah', '', '', '', '', 'A-017', '', '', '']); // baris 22: pola nomor perangkat
  rows.splice(31, 0, ['Nomor Kembar', '', '', '', '', 'imp-1', '', '', '']); // baris 32: sama dengan baris 2
  rows.splice(41, 0, ['', '', '', '', '', '', '', '', '']); // baris kosong: dilewati, nomor baris tetap

  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, XLSX.utils.aoa_to_sheet(rows), 'Tamu');
  const file = testInfo.outputPath('tamu-1000.xlsx');
  writeFileSync(file, XLSX.write(book, { type: 'buffer', bookType: 'xlsx' }));

  await page.goto(`/acara/${id}/tamu/impor`);
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Unduh templat (.xlsx)' }).click(),
  ]);
  expect(download.suggestedFilename()).toBe('templat-impor-tamu.xlsx');

  await page.locator('#import-file').setInputFiles(file);
  await expect(page.getByText('1.003 baris')).toBeVisible();
  await expect(page.getByText('1.000 siap')).toBeVisible();
  await expect(page.getByText('3 bermasalah')).toBeVisible();
  await expect(page.getByText('Grup baru: Teman Kantor, Keluarga')).toBeVisible();

  await page.getByLabel('Tampilkan hanya baris bermasalah').check();
  const table = page.getByRole('table', { name: 'Hasil pemeriksaan berkas impor' });
  await expect(table.getByRole('row')).toHaveCount(4);
  await expect(table.getByRole('row', { name: /^12 / })).toContainText('Isi nama tamu.');
  await expect(table.getByRole('row', { name: /^22 / })).toContainText('pola nomor perangkat');
  await expect(table.getByRole('row', { name: /^32 / })).toContainText('sudah dipakai baris 2');

  await page.getByRole('button', { name: 'Proses 1.000 tamu' }).click();
  await expect(page.getByText('1.000 tamu ditambahkan.')).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText('2 grup baru dibuat.')).toBeVisible();

  await page.getByRole('link', { name: 'Lihat daftar tamu' }).click();
  await expect(page.getByText('1–50 dari 1.000')).toBeVisible();
  await page.getByRole('button', { name: 'Halaman berikutnya' }).click();
  await expect(page).toHaveURL(/hal=2/);
  await expect(page.getByText('51–100 dari 1.000')).toBeVisible();
  await page.getByRole('searchbox', { name: 'Cari nama atau Nomor Urut' }).fill('IMP-3');
  await expect(page.getByRole('row', { name: /Tamu Impor 0003/ })).toContainText('Akan hadir (2 orang)');
});

test('berkas tanpa kolom Nama dan berkas berformat lain ditolak dengan pesan jelas', async ({ page }, testInfo) => {
  const id = await createEvent(uniqueName('Impor Salah'));
  await page.goto(`/acara/${id}/tamu/impor`);

  const csv = testInfo.outputPath('tanpa-nama.csv');
  writeFileSync(csv, 'Telepon,Kategori\n+628123456789,VIP\n');
  await page.locator('#import-file').setInputFiles(csv);
  await expect(page.getByRole('alert')).toContainText('Kolom "Nama" tidak ditemukan');

  const txt = testInfo.outputPath('catatan.txt');
  writeFileSync(txt, 'bukan spreadsheet');
  await page.locator('#import-file').setInputFiles(txt);
  await expect(page.getByRole('alert')).toContainText('Format berkas harus .xlsx, .xls, atau .csv.');
});
