import { expect, type Page } from '@playwright/test';

/** Akun dari supabase/seed.sql (hanya lokal/CI). */
export const ADMIN = { email: 'admin@buku-tamu.test', password: 'admin-lokal-2026' };
export const NOT_ADMIN = { email: 'bukan-admin@buku-tamu.test', password: 'bukan-admin-2026' };

export async function login(page: Page, account = ADMIN, path = '/masuk') {
  await page.goto(path);
  await page.getByLabel('Email').fill(account.email);
  await page.getByLabel('Kata sandi').fill(account.password);
  await page.getByRole('button', { name: 'Masuk' }).click();
}

export async function loginAsAdmin(page: Page) {
  await login(page);
  await expect(page.getByRole('heading', { name: 'Acara', level: 1 })).toBeVisible();
}
