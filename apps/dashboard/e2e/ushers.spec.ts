import { expect, test } from '@playwright/test';
import { createEvent, createUsher, eventCode, uniqueName, usherLogin } from './api';

test.describe('Penerima Tamu', () => {
  let eventId = '';
  let code = '';
  test.beforeAll(async () => {
    eventId = await createEvent(uniqueName('Usher Uji'));
    code = await eventCode(eventId);
  });

  test('tambah usher: PIN tampil sekali dan dialog baru bisa ditutup setelah dicatat', async ({ page }) => {
    await page.goto(`/acara/${eventId}/penerima-tamu`);
    await expect(page.getByText(code, { exact: true }).first()).toBeVisible();
    await page.getByRole('button', { name: 'Tambah penerima tamu' }).first().click();
    const form = page.getByRole('dialog', { name: 'Tambah penerima tamu' });
    await form.getByRole('button', { name: 'Tambah dan buat PIN' }).click();
    await expect(form.getByText('Nama penerima tamu wajib diisi.')).toBeVisible();
    await form.getByLabel('Nama').fill('Sari');
    await form.getByRole('button', { name: 'Tambah dan buat PIN' }).click();

    const pinDialog = page.getByRole('dialog', { name: 'PIN untuk Sari' });
    await expect(pinDialog).toBeVisible();
    const pin = (await pinDialog.locator('p.font-mono').textContent())?.trim() ?? '';
    expect(pin).toMatch(/^[A-HJ-NP-Z2-9]{2}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
    await expect(pinDialog.getByText(code)).toBeVisible();
    await expect(pinDialog.getByRole('button', { name: 'Tutup' })).toBeDisabled();
    await expect(pinDialog.getByRole('button', { name: 'Tutup', exact: false })).toHaveCount(1); // tanpa tombol X
    await page.keyboard.press('Escape');
    await expect(pinDialog).toBeVisible();
    await pinDialog.getByLabel('Saya sudah mencatat PIN').check();
    await pinDialog.getByRole('button', { name: 'Tutup' }).click();
    await expect(pinDialog).toBeHidden();

    const row = page.getByRole('row', { name: /Sari/ });
    await expect(row).toContainText(pin.slice(0, 2));
    await expect(row).toContainText('Aktif');

    // PIN yang ditampilkan benar-benar bisa dipakai login lewat usher-login.
    const login = await usherLogin(code, pin);
    expect(login.status).toBe(200);
    await page.reload();
    await expect(page.getByRole('row', { name: /^A Sari/ })).toContainText('Aktif');
  });

  test('QR Login: tampil dengan hitung mundur 5 menit dan bisa dibuat ulang', async ({ page }) => {
    await createUsher(eventId, 'Tono');
    await page.goto(`/acara/${eventId}/penerima-tamu`);
    await page.getByRole('button', { name: 'QR Login untuk Tono' }).click();
    const dialog = page.getByRole('dialog', { name: 'QR Login · Tono' });
    await expect(dialog.getByRole('img', { name: 'QR Login untuk Tono' })).toBeVisible();
    await expect(dialog).toContainText(/Berlaku [45]:\d{2} lagi/);
    await dialog.getByRole('button', { name: 'Buat QR baru' }).click();
    await expect(dialog).toContainText(/Berlaku 4:5\d|Berlaku 5:00/);
    await dialog.getByRole('button', { name: 'Selesai' }).click();
  });

  test('Cabut lalu Cabut & putus total (alasan wajib); status perangkat berubah', async ({ page }) => {
    const usher = await createUsher(eventId, 'Wawan');
    expect((await usherLogin(code, usher.pin)).status).toBe(200);
    await page.goto(`/acara/${eventId}/penerima-tamu`);
    const row = page.getByRole('row', { name: /Wawan/ }).filter({ hasText: 'HP Uji E2E' });
    await expect(row).toContainText('Aktif');

    await row.getByRole('button', { name: /^Cabut perangkat/ }).click();
    const cabut = page.getByRole('dialog', { name: /^Cabut perangkat/ });
    await expect(cabut).toContainText('masuk karantina');
    await cabut.getByRole('button', { name: 'Cabut' }).click();
    await expect(page.getByText('Perangkat dicabut.')).toBeVisible();
    await expect(row).toContainText('Dicabut');

    await row.getByRole('button', { name: /^Cabut & putus total/ }).click();
    const total = page.getByRole('dialog', { name: /^Cabut & putus total/ });
    await expect(total).toContainText('HP hilang atau dicuri');
    const confirm = total.getByRole('button', { name: 'Cabut & putus total' });
    await expect(confirm).toBeDisabled();
    await total.getByLabel('Alasan (wajib)').fill('HP tertinggal di taksi');
    await confirm.click();
    await expect(page.getByText(/Perangkat diputus total/)).toBeVisible();
    await expect(row).toContainText('Diputus total');
    await expect(row).toContainText('HP tertinggal di taksi');
    await expect(row.getByRole('button')).toHaveCount(0);
  });

  test('reset PIN menghasilkan PIN baru; menonaktifkan usher mencabut perangkatnya', async ({ page }) => {
    const usher = await createUsher(eventId, 'Yanti');
    expect((await usherLogin(code, usher.pin)).status).toBe(200);
    await page.goto(`/acara/${eventId}/penerima-tamu`);

    await page.getByRole('button', { name: 'Reset PIN Yanti' }).click();
    await page.getByRole('dialog', { name: 'Reset PIN Yanti?' }).getByRole('button', { name: 'Buat PIN baru' }).click();
    const pinDialog = page.getByRole('dialog', { name: 'PIN untuk Yanti' });
    const pin = (await pinDialog.locator('p.font-mono').textContent())?.trim() ?? '';
    expect(pin.slice(0, 2)).toBe(usher.pin.slice(0, 2));
    expect(pin).not.toBe(usher.pin);
    await pinDialog.getByLabel('Saya sudah mencatat PIN').check();
    await pinDialog.getByRole('button', { name: 'Tutup' }).click();
    expect((await usherLogin(code, usher.pin)).status).toBe(401);

    await page.getByRole('button', { name: 'Ubah Yanti' }).click();
    const edit = page.getByRole('dialog', { name: 'Ubah Yanti' });
    await edit.getByLabel('Aktif').uncheck();
    await edit.getByRole('button', { name: 'Simpan perubahan' }).click();
    await expect(page.getByText('Yanti disimpan. 1 perangkat dicabut.')).toBeVisible();
    await expect(page.getByRole('row', { name: /Yanti/ }).first()).toContainText('Nonaktif');
  });

  test('banner blokir muncul setelah 10 PIN salah dari satu jaringan', async ({ page }) => {
    const ip = '10.250.0.77';
    for (let i = 0; i < 10; i++) expect((await usherLogin(code, 'ZZ-ZZZZ-ZZZZ', ip)).status).toBe(401);
    expect((await usherLogin(code, 'ZZ-ZZZZ-ZZZZ', ip)).status).toBe(429);
    await page.goto(`/acara/${eventId}/penerima-tamu`);
    const banner = page.getByRole('alert').filter({ hasText: 'Login PIN diblokir sementara' });
    await expect(banner).toContainText('10.250.0.77');
    await expect(banner).toContainText('QR Login');
  });
});
