import { expect, test } from '@playwright/test';
import { createEvent, uniqueName } from './api';

test.describe('Kelola Tamu', () => {
  let eventId = '';
  test.beforeAll(async () => {
    eventId = await createEvent(uniqueName('Tamu Uji'), [
      { name: 'Ani Wijaya', category: 'vip', special_number: 'VIP-001', rsvp_status: 'going', rsvp_pax: 2 },
      { name: 'Bayu Pratama' },
      { name: 'Citra Lestari', category: 'vvip' },
      { name: 'Eko Hidayat', rsvp_status: 'not_going' },
    ]);
  });

  test('tambah tamu: Nomor Urut berpola perangkat dan nomor ganda ditolak, lalu tersimpan', async ({ page }) => {
    await page.goto(`/acara/${eventId}/tamu`);
    await page.getByRole('button', { name: 'Tambah tamu' }).click();
    const dialog = page.getByRole('dialog', { name: 'Tambah tamu' });
    const number = dialog.getByLabel('Nomor Urut (opsional)');

    await dialog.getByLabel('Nama', { exact: true }).fill('Dewi Rahayu');
    await number.fill('a-017');
    await dialog.getByRole('button', { name: 'Simpan tamu' }).click();
    await expect(number).toHaveAttribute('aria-invalid', 'true');
    await expect(dialog.getByRole('alert')).toContainText('pola nomor perangkat');

    await number.fill('VIP-001');
    await dialog.getByRole('button', { name: 'Simpan tamu' }).click();
    await expect(number).toHaveAccessibleDescription(/sudah dipakai tamu lain/);

    await number.fill('vip-002');
    await dialog.getByText('VIP', { exact: true }).click();
    await dialog.getByText('Akan hadir', { exact: true }).click();
    await dialog.getByLabel('Jumlah orang yang akan hadir').fill('2');
    await dialog.getByRole('button', { name: 'Simpan tamu' }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByText('Dewi Rahayu ditambahkan.')).toBeVisible();

    const row = page.getByRole('row', { name: /Dewi Rahayu/ });
    await expect(row).toContainText('VIP-002');
    await expect(row).toContainText('Akan hadir (2 orang)');
    await expect(row).toContainText('VIP');
  });

  test('cari dan filter tersimpan di URL; Back mengembalikan hasil sebelumnya', async ({ page }) => {
    await page.goto(`/acara/${eventId}/tamu`);
    await page.getByRole('searchbox', { name: 'Cari nama atau Nomor Urut' }).fill('citra');
    await expect(page).toHaveURL(/\?q=citra$/);
    await expect(page.getByRole('row', { name: /Citra Lestari/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Bayu Pratama/ })).toHaveCount(0);

    await page.getByRole('searchbox', { name: 'Cari nama atau Nomor Urut' }).fill('vip-001');
    await expect(page.getByRole('row', { name: /Ani Wijaya/ })).toBeVisible();

    await page.getByRole('button', { name: 'Hapus filter' }).click();
    await page.locator('#filter-rsvp').selectOption('not_going');
    await expect(page).toHaveURL(/rsvp=not_going/);
    await expect(page.getByRole('row', { name: /Eko Hidayat/ })).toBeVisible();
    await expect(page.getByRole('row', { name: /Ani Wijaya/ })).toHaveCount(0);

    await page.goBack();
    await expect(page.getByRole('row', { name: /Ani Wijaya/ })).toBeVisible();
  });

  test('ikon kategori di daftar: VVIP mahkota, VIP bintang, Regular tanpa ikon', async ({ page }) => {
    await page.goto(`/acara/${eventId}/tamu`);
    const icons = (name: RegExp, selector: string) => page.getByRole('row', { name }).locator(selector);
    await expect(icons(/Citra Lestari/, 'svg.lucide-crown')).toHaveCount(1);
    await expect(icons(/Citra Lestari/, 'svg.lucide-star')).toHaveCount(0);
    await expect(icons(/Ani Wijaya/, 'svg.lucide-star')).toHaveCount(1);
    await expect(icons(/Ani Wijaya/, 'svg.lucide-crown')).toHaveCount(0);
    await expect(icons(/Eko Hidayat/, 'svg.lucide-crown, svg.lucide-star')).toHaveCount(0);
  });

  test('ubah data tamu, lihat QR dan unduh PNG, lalu hapus dengan konfirmasi', async ({ page }) => {
    await page.goto(`/acara/${eventId}/tamu`);
    await page.getByRole('button', { name: 'Bayu Pratama' }).click();
    const dialog = page.getByRole('dialog', { name: 'Bayu Pratama' });
    await dialog.getByLabel('Jumlah undangan').fill('3');
    await dialog.getByRole('button', { name: 'Simpan perubahan' }).click();
    await expect(
      page
        .getByRole('row', { name: /Bayu Pratama/ })
        .getByRole('cell')
        .nth(4),
    ).toHaveText('3');

    await page.getByRole('button', { name: 'Bayu Pratama' }).click();
    await page.getByRole('tab', { name: 'QR' }).click();
    await expect(page.getByRole('img', { name: 'QR check-in untuk Bayu Pratama' })).toBeVisible();
    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('button', { name: 'Unduh PNG' }).click(),
    ]);
    expect(download.suggestedFilename()).toBe('QR-Bayu-Pratama.png');

    await page.getByRole('tab', { name: 'Data' }).click();
    await page.getByRole('button', { name: 'Hapus tamu' }).click();
    await page.getByRole('dialog', { name: 'Hapus Bayu Pratama?' }).getByRole('button', { name: 'Hapus tamu' }).click();
    await expect(page.getByRole('row', { name: /Bayu Pratama/ })).toHaveCount(0);
  });
});
