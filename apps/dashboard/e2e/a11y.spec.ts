import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import {
  createEvent,
  createUsher,
  eventCode,
  guestIds,
  loginDevice,
  pushCheckIns,
  uniqueName,
  usherLogin,
} from './api';

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

  test('Penerima Tamu (dengan perangkat), dialog PIN dan QR Login, Pengaturan check-in, Sapaan', async ({ page }) => {
    const usher = await createUsher(eventId, 'Usher Aksesibel');
    await usherLogin(await eventCode(eventId), usher.pin);
    await page.goto(`/acara/${eventId}/penerima-tamu`);
    await expect(page.getByRole('heading', { name: 'Perangkat' })).toBeVisible();
    await expectNoViolations(page);

    await page.getByRole('button', { name: 'Tambah penerima tamu' }).first().click();
    await page.getByLabel('Nama').fill('Usher Kedua');
    await page.getByRole('button', { name: 'Tambah dan buat PIN' }).click();
    await expect(page.getByRole('dialog', { name: 'PIN untuk Usher Kedua' })).toBeVisible();
    await expectNoViolations(page);
    await page.getByLabel('Saya sudah mencatat PIN').check();
    await page.getByRole('button', { name: 'Tutup' }).click();

    await page.getByRole('button', { name: 'QR Login untuk Usher Aksesibel' }).click();
    await expect(page.getByRole('img', { name: 'QR Login untuk Usher Aksesibel' })).toBeVisible();
    await expectNoViolations(page);
    await page.getByRole('button', { name: 'Selesai' }).click();

    for (const [path, heading] of [
      ['penerima-tamu/pengaturan', 'Pengaturan check-in'],
      ['sapaan', 'Pop-up sapaan'],
    ] as const) {
      await page.goto(`/acara/${eventId}/${path}`);
      await expect(page.getByRole('heading', { name: heading })).toBeVisible();
      await expectNoViolations(page);
    }
  });

  test('Statistik (dengan grafik) dan Riwayat (dengan baris perlu ditinjau)', async ({ page }) => {
    const ids = await guestIds(eventId);
    const code = await eventCode(eventId);
    const d1 = await loginDevice(code, (await createUsher(eventId, 'Usher Grafik 1')).pin);
    const d2 = await loginDevice(code, (await createUsher(eventId, 'Usher Grafik 2')).pin);
    await pushCheckIns(d1, [{ guestId: ids['Raja Uji']!, ticket: 'VVIP-001', pax: 2 }]);
    await pushCheckIns(d2, [{ guestId: ids['Raja Uji']!, ticket: 'VVIP-001' }]);

    await page.goto(`/acara/${eventId}/statistik`);
    await expect(page.getByRole('heading', { name: 'Statistik' })).toBeVisible();
    await expect(page.getByRole('heading', { name: /Kedatangan per/ })).toBeVisible();
    await expectNoViolations(page);
    await page.getByRole('button', { name: 'Tampilkan sebagai tabel' }).click();
    await expectNoViolations(page);

    await page.goto(`/acara/${eventId}/riwayat?status=tinjau`);
    await expect(page.getByText('Ganda — tinjau')).toBeVisible();
    await expectNoViolations(page);
  });
});
