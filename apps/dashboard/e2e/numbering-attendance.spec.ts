import { expect, test } from '@playwright/test';
import { createEvent, uniqueName } from './api';

test('Nomor Urut: prefix berpola perangkat ditolak; Terapkan dengan pratinjau lalu simpan', async ({ page }) => {
  const id = await createEvent(uniqueName('Nomor Uji'), [
    { name: 'Budi VIP', category: 'vip' },
    { name: 'Ani VIP', category: 'vip' },
    { name: 'Cici VIP', category: 'vip', special_number: 'VIP-001' },
  ]);
  await page.goto(`/acara/${id}/nomor-urut`);
  const vip = page.getByRole('region', { name: 'VIP', exact: true });
  await expect(vip).toContainText('3 tamu · 2 belum bernomor');

  await vip.getByLabel('Prefix').fill('A-');
  await expect(vip).toContainText('pola nomor perangkat');
  await vip.getByLabel('Prefix').fill('VIP-');
  await expect(vip).toContainText('Contoh: VIP-001, VIP-002, …');

  await vip.getByRole('button', { name: 'Terapkan Nomor Urut…' }).click();
  const dialog = page.getByRole('dialog', { name: 'Terapkan Nomor Urut VIP' });
  await dialog.getByRole('button', { name: 'Lihat pratinjau' }).click();
  const preview = dialog.getByRole('table', { name: 'Pratinjau Nomor Urut' });
  await expect(preview.getByRole('row', { name: /Ani VIP/ })).toContainText('VIP-002');
  await expect(preview.getByRole('row', { name: /Budi VIP/ })).toContainText('VIP-003');
  await dialog.getByRole('button', { name: 'Simpan 2 nomor' }).click();
  await expect(page.getByText('2 Nomor Urut VIP disimpan.')).toBeVisible();
  await expect(vip).toContainText('3 tamu · 0 belum bernomor');

  // Menimpa nomor lama membutuhkan konfirmasi tambahan (FR-C-04).
  await vip.getByRole('button', { name: 'Terapkan Nomor Urut…' }).click();
  await dialog.getByLabel(/Timpa nomor yang sudah ada/).check();
  await dialog.getByRole('button', { name: 'Lihat pratinjau' }).click();
  const save = dialog.getByRole('button', { name: 'Simpan 3 nomor' });
  await expect(save).toBeDisabled();
  await dialog.getByLabel(/nomor lama akan diganti/).check();
  await expect(save).toBeEnabled();
  await dialog.getByRole('button', { name: 'Batal' }).click();
});

test('Kehadiran: tandai hadir manual, ubah jumlah, tandai keluar', async ({ page }) => {
  const id = await createEvent(uniqueName('Hadir Uji'), [
    { name: 'Hadi Santoso', rsvp_status: 'going', rsvp_pax: 2, invited_pax: 2 },
  ]);
  await page.goto(`/acara/${id}/tamu`);
  await page.getByRole('button', { name: 'Hadi Santoso' }).click();
  await page.getByRole('tab', { name: 'Kehadiran' }).click();
  await expect(page.getByText('Belum ada check-in untuk tamu ini.')).toBeVisible();
  await expect(page.getByRole('dialog').getByLabel('Jumlah hadir', { exact: true })).toHaveValue('2');
  await page.getByRole('button', { name: 'Tandai hadir', exact: true }).click();

  const panel = page.getByRole('tabpanel');
  await expect(panel.getByText('Sah', { exact: true })).toBeVisible();
  await expect(panel).toContainText('Ditandai hadir oleh Admin, tanpa tiket.');
  await expect(panel.getByRole('heading', { name: 'Tandai hadir' })).toHaveCount(0);

  await panel.getByRole('button', { name: 'Ubah detail' }).click();
  await panel.getByLabel('Jumlah hadir', { exact: true }).fill('3');
  await panel.getByLabel('Alasan perubahan (opsional)').fill('Membawa anak');
  await panel.getByRole('button', { name: 'Simpan' }).click();
  await expect(panel).toContainText('3 orang');

  await panel.getByRole('button', { name: 'Tandai keluar sekarang' }).click();
  await expect(panel).toContainText('Keluar');
  await page.keyboard.press('Escape');

  await page.locator('#filter-hadir').selectOption('keluar');
  await expect(page.getByRole('row', { name: /Hadi Santoso/ })).toContainText('Hadir');
  await expect(page.getByRole('row', { name: /Hadi Santoso/ })).toContainText('keluar');
});
