import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { createEvent, uniqueName } from './api';

const WCAG = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function expectNoViolations(page: Page) {
  const result = await new AxeBuilder({ page }).withTags(WCAG).analyze();
  const summary = result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`);
  expect(summary).toEqual([]);
}

test.describe('aksesibilitas halaman masuk (tanpa sesi)', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test('halaman masuk', async ({ page }) => {
    await page.goto('/masuk');
    await expect(page.getByRole('heading', { name: 'Masuk', level: 1 })).toBeVisible();
    await expectNoViolations(page);
  });

  test('halaman masuk dengan galat', async ({ page }) => {
    await page.goto('/masuk');
    await page.getByRole('button', { name: 'Masuk' }).click();
    await expect(page.getByRole('alert')).toBeVisible();
    await expectNoViolations(page);
  });
});

test.describe('aksesibilitas halaman Admin (axe, WCAG 2.2 AA)', () => {
  let eventId = '';
  test.beforeAll(async () => {
    eventId = await createEvent(uniqueName('Aksesibilitas'), [
      { name: 'Raja Uji', category: 'vvip', special_number: 'VVIP-001' },
      { name: 'Ratu Uji', category: 'vip' },
      { name: 'Rakyat Uji' },
    ]);
  });

  test('daftar acara dan dialog Buat acara', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByRole('row', { name: /Resepsi Rina & Bayu/ })).toBeVisible();
    await expectNoViolations(page);
    await page.getByRole('button', { name: 'Buat acara' }).click();
    await page.getByRole('dialog', { name: 'Buat acara' }).getByRole('button', { name: 'Buat acara' }).click();
    await expect(page.getByRole('dialog').getByRole('alert')).toBeVisible();
    await expectNoViolations(page);
  });

  test('Kelola Tamu, pilihan massal, dan dialog detail tamu', async ({ page }) => {
    await page.goto(`/acara/${eventId}/tamu`);
    await expect(page.getByRole('row', { name: /Raja Uji/ })).toBeVisible();
    await expectNoViolations(page);
    await page.getByRole('checkbox', { name: 'Pilih Ratu Uji' }).check();
    await expect(page.getByRole('region', { name: 'Aksi untuk tamu terpilih' })).toBeVisible();
    await expectNoViolations(page);
    await page.getByRole('button', { name: 'Raja Uji' }).click();
    for (const tab of ['Data', 'Kehadiran', 'QR']) {
      await page.getByRole('tab', { name: tab }).click();
      await expect(page.getByRole('tabpanel')).toBeVisible();
      await expectNoViolations(page);
    }
  });

  test('Impor, Grup, Nomor Urut, Pengaturan', async ({ page }) => {
    for (const [path, heading] of [
      ['tamu/impor', 'Impor tamu'],
      ['grup', 'Grup tamu'],
      ['nomor-urut', 'Nomor Urut VIP & VVIP'],
      ['pengaturan', 'Pengaturan acara'],
    ] as const) {
      await page.goto(`/acara/${eventId}/${path}`);
      await expect(page.getByRole('heading', { name: heading })).toBeVisible();
      await expectNoViolations(page);
    }
  });
});
