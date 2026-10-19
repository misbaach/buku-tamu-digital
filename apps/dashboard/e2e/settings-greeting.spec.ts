import { expect, test } from '@playwright/test';
import { createEvent, uniqueName } from './api';

// PNG 1×1 dan "SVG" yang menyamar sebagai .png.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);
const SVG = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');

test.describe('Pengaturan check-in dan sapaan', () => {
  let eventId = '';
  test.beforeAll(async () => {
    eventId = await createEvent(uniqueName('Pengaturan Uji'));
  });

  test('pengaturan check-in tersimpan; tiket aktif wajib punya kategori', async ({ page }) => {
    await page.goto(`/acara/${eventId}/penerima-tamu/pengaturan`);
    await expect(page.getByText('Selalu aktif', { exact: true })).toBeVisible();
    await page.getByRole('switch', { name: 'Tamu Check-In Lebih 1 Kali' }).check();

    const ticket = page.getByRole('complementary', { name: 'Pratinjau tiket' });
    await page.getByRole('checkbox', { name: 'Jumlah orang' }).check();
    await expect(ticket).toContainText('2 orang');
    for (const c of ['Regular', 'VIP', 'VVIP']) await page.getByRole('checkbox', { name: c, exact: true }).uncheck();
    await page.getByRole('button', { name: 'Simpan pengaturan' }).click();
    await expect(page.getByText('Pilih minimal satu kategori.')).toBeVisible();

    await page.getByRole('checkbox', { name: 'VIP', exact: true }).check();
    await page.getByLabel('Jumlah salinan').selectOption('2');
    await page.getByRole('button', { name: 'Simpan pengaturan' }).click();
    await expect(page.getByText(/Pengaturan check-in disimpan/)).toBeVisible();

    await page.reload();
    await expect(page.getByRole('switch', { name: 'Tamu Check-In Lebih 1 Kali' })).toBeChecked();
    await expect(page.getByRole('checkbox', { name: 'Jumlah orang' })).toBeChecked();
    await expect(page.getByRole('checkbox', { name: 'Regular', exact: true })).not.toBeChecked();
    await expect(page.getByLabel('Jumlah salinan')).toHaveValue('2');
  });

  test('sapaan: pratinjau mengikuti teks, variabel salah ditolak, foto PNG diterima dan SVG ditolak', async ({
    page,
  }) => {
    await page.goto(`/acara/${eventId}/sapaan`);
    await page.getByRole('tab', { name: 'VIP', exact: true }).click();
    const preview = page.getByRole('figure');
    await page.getByLabel('Nama contoh').fill('Rina Kartika');
    await page.getByLabel('Judul').fill('Halo {{namaa}}');
    await page.getByRole('button', { name: 'Simpan sapaan VIP' }).click();
    await expect(page.getByText(/Variabel tidak dikenal: \{\{namaa\}\}/)).toBeVisible();

    await page.getByLabel('Judul').fill('Selamat datang, {{nama}}!');
    await expect(preview).toContainText('Selamat datang, Rina Kartika!');
    await expect(page.getByText('Perubahan belum disimpan')).toBeVisible();

    const upload = page.locator('input[type="file"]');
    await upload.setInputFiles({ name: 'foto.png', mimeType: 'image/png', buffer: SVG });
    await expect(page.getByText('Format foto harus PNG, JPEG, atau WebP.')).toBeVisible();
    await upload.setInputFiles({ name: 'foto.png', mimeType: 'image/png', buffer: PNG });
    await expect(page.getByText('Foto sapaan VIP disimpan.')).toBeVisible();
    await expect(preview.locator('img')).toBeVisible();

    await page.getByRole('button', { name: 'Simpan sapaan VIP' }).click();
    await expect(page.getByText('Sapaan VIP disimpan.')).toBeVisible();
    await page.reload();
    await page.getByRole('tab', { name: 'VIP', exact: true }).click();
    await expect(page.getByLabel('Judul')).toHaveValue('Selamat datang, {{nama}}!');
    await expect(page.getByRole('button', { name: 'Hapus foto' })).toBeVisible();
  });
});
