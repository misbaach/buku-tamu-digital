import { expect, test } from '@playwright/test';
import { ADMIN, login, loginAsAdmin, NOT_ADMIN } from './helpers';

test.describe('masuk dan keluar Admin', () => {
  test('rute Admin tanpa sesi dialihkan ke /masuk dan tujuannya disimpan', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveURL(/\/masuk\?ke=%2F$/);
    await expect(page.getByRole('heading', { name: 'Masuk', level: 1 })).toBeVisible();
  });

  test('isian kosong: galat di field, ringkasan galat menerima fokus', async ({ page }) => {
    await page.goto('/masuk');
    await page.getByRole('button', { name: 'Masuk' }).click();
    const summary = page.getByRole('alert');
    await expect(summary).toBeFocused();
    await expect(summary.getByRole('link', { name: 'Isi email.' })).toHaveAttribute('href', '#email');
    await expect(page.getByLabel('Email')).toHaveAttribute('aria-invalid', 'true');
    await expect(page.getByLabel('Email')).toHaveAccessibleDescription('Isi email.');
    await expect(page.getByLabel('Kata sandi')).toHaveAccessibleDescription('Isi kata sandi.');
  });

  test('kata sandi salah: pesan jelas tanpa membocorkan apakah email terdaftar', async ({ page }) => {
    await login(page, { email: ADMIN.email, password: 'salah-sekali-1' });
    await expect(page.getByRole('alert')).toHaveText('Email atau kata sandi salah.');
    await expect(page).toHaveURL(/\/masuk/);
  });

  test('akun tanpa app_metadata.role admin ditolak walau user_metadata berisi admin', async ({ page }) => {
    await login(page, NOT_ADMIN);
    await expect(page.getByRole('alert')).toContainText('bukan akun Admin');
    await expect(page).toHaveURL(/\/masuk/);
    await page.goto('/');
    await expect(page).toHaveURL(/\/masuk/);
  });

  test('masuk berhasil: daftar acara milik Admin tampil', async ({ page }) => {
    await loginAsAdmin(page);
    await expect(page).toHaveURL('/');
    const row = page.getByRole('row', { name: /Resepsi Rina & Bayu/ });
    await expect(row).toContainText('K7PM2X');
    await expect(row).toContainText('Aktif');
    await expect(page.getByText(ADMIN.email)).toBeVisible();
  });

  for (const target of ['https%3A%2F%2Fevil.example%2F', '%2F%2Fevil.example', '%2F%5Cevil.example']) {
    test(`?ke=${target} ke situs luar diabaikan (cegah open redirect)`, async ({ page }) => {
      await login(page, ADMIN, `/masuk?ke=${target}`);
      await expect(page).toHaveURL('/');
    });
  }

  test('keluar: sesi dihapus dan rute Admin kembali terkunci', async ({ page }) => {
    await loginAsAdmin(page);
    await page.getByRole('button', { name: 'Keluar' }).click();
    await expect(page).toHaveURL(/\/masuk$/);
    await page.goto('/');
    await expect(page).toHaveURL(/\/masuk\?ke=/);
  });

  test('tautan "Lewati ke konten" tersedia untuk pengguna keyboard', async ({ page }) => {
    await loginAsAdmin(page);
    await page.keyboard.press('Tab');
    await expect(page.getByRole('link', { name: 'Lewati ke konten' })).toBeFocused();
  });
});
