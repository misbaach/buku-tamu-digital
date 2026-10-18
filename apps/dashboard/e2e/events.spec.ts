import { expect, test } from '@playwright/test';
import { createEvent, uniqueName } from './api';

test('buat acara: galat ditampilkan, lalu acara baru terbuka di halaman Tamu', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Buat acara' }).click();
  const dialog = page.getByRole('dialog', { name: 'Buat acara' });
  await dialog.getByRole('button', { name: 'Buat acara' }).click();
  await expect(dialog.getByRole('alert')).toBeFocused();
  await expect(dialog.getByLabel('Nama acara')).toHaveAccessibleDescription('Isi nama acara.');

  const name = uniqueName('Akad Uji');
  await dialog.getByLabel('Nama acara').fill(name);
  await dialog.getByLabel('Tanggal acara').fill('2026-12-20');
  await dialog.getByLabel('Zona waktu').selectOption('Asia/Makassar');
  await dialog.getByRole('button', { name: 'Buat acara' }).click();

  await expect(page.getByRole('heading', { name, level: 1 })).toBeVisible();
  await expect(page).toHaveURL(/\/acara\/[0-9a-f-]{36}\/tamu$/);
  await expect(page.getByText('Belum ada tamu.')).toBeVisible();
  await expect(page.getByText(/Kode Acara [A-HJ-KM-NP-Z2-9]{6}/)).toBeVisible();
});

test('pengaturan: ubah nama, lalu arsipkan dengan konfirmasi', async ({ page }) => {
  const id = await createEvent(uniqueName('Ubah Uji'));
  await page.goto(`/acara/${id}/pengaturan`);
  const newName = uniqueName('Resepsi Diubah');
  await page.getByLabel('Nama acara').fill(newName);
  await page.getByRole('button', { name: 'Simpan pengaturan' }).click();
  await expect(page.getByRole('heading', { name: newName, level: 1 })).toBeVisible();

  await page.getByRole('button', { name: 'Arsipkan acara…' }).click();
  const confirm = page.getByRole('dialog', { name: `Arsipkan ${newName}?` });
  await expect(confirm).toContainText('check-in yang belum terkirim');
  await confirm.getByRole('button', { name: 'Arsipkan acara' }).click();
  await expect(page.getByText('Acara ini sudah diarsipkan.')).toBeVisible();
  await page.goto('/');
  await expect(page.getByRole('row', { name: new RegExp(newName) })).toContainText('Diarsipkan');
});

test('acara milik Admin lain atau id acak tampil sebagai "tidak ditemukan"', async ({ page }) => {
  await page.goto('/acara/00000000-0000-4000-8000-000000000999/tamu');
  await expect(page.getByRole('heading', { name: 'Acara tidak ditemukan.' })).toBeVisible();
});
