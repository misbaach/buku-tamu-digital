import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { loginAsAdmin } from './helpers';

const WCAG = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];

async function expectNoViolations(page: Page) {
  const result = await new AxeBuilder({ page }).withTags(WCAG).analyze();
  const summary = result.violations.map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(', ')}`);
  expect(summary).toEqual([]);
}

test.describe('aksesibilitas (axe, WCAG 2.2 AA)', () => {
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

  test('daftar acara', async ({ page }) => {
    await loginAsAdmin(page);
    await expect(page.getByRole('row', { name: /Resepsi Rina & Bayu/ })).toBeVisible();
    await expectNoViolations(page);
  });
});
