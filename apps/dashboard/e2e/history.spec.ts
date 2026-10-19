import { expect, test } from '@playwright/test';
import {
  adminApi,
  createEvent,
  createUsher,
  eventCode,
  guestIds,
  loginDevice,
  pushCheckIns,
  uniqueName,
  type Device,
} from './api';

// FR-RW-01..05: tab, penanda tinjau identik untuk ketiga status, setujui/tolak karantina per baris dan per
// perangkat, undo dengan alasan, tandai ditinjau, check-out manual.
test.describe('Riwayat', () => {
  let eventId = '';
  let a: Device;
  let b: Device;
  let c: Device;
  let ids: Record<string, string> = {};

  test.beforeAll(async () => {
    eventId = await createEvent(uniqueName('Riwayat Uji'), [
      { name: 'Ani' },
      { name: 'Bayu' },
      { name: 'Raja', category: 'vvip', special_number: 'VVIP-001' },
      { name: 'Ratu', category: 'vvip', special_number: 'VVIP-002' },
      { name: 'Karin' },
      { name: 'Kurnia' },
      { name: 'Kamal' },
    ]);
    ids = await guestIds(eventId);
    const code = await eventCode(eventId);
    a = await loginDevice(code, (await createUsher(eventId, 'Usher A')).pin);
    b = await loginDevice(code, (await createUsher(eventId, 'Usher B')).pin);
    c = await loginDevice(code, (await createUsher(eventId, 'Usher C')).pin);

    expect(await pushCheckIns(a, [{ guestId: ids['Ani']!, ticket: `${a.code}-001` }])).toEqual(['accepted']);
    expect(await pushCheckIns(b, [{ guestId: ids['Ani']!, ticket: `${b.code}-001` }])).toEqual(['duplicate']);
    expect(await pushCheckIns(a, [{ guestId: ids['Raja']!, ticket: 'VVIP-001' }])).toEqual(['accepted']);
    expect(await pushCheckIns(b, [{ guestId: ids['Ratu']!, ticket: 'VVIP-001' }])).toEqual(['conflict']);
    expect(await pushCheckIns(a, [{ guestId: ids['Bayu']!, ticket: `${a.code}-002`, pax: 2 }])).toEqual(['accepted']);

    const sb = await adminApi();
    await sb.rpc('admin_revoke_device', { p_device_id: c.id, p_mode: 'quarantine' });
    expect(
      await pushCheckIns(c, [
        { guestId: ids['Karin']!, ticket: `${c.code}-001` },
        { guestId: ids['Kurnia']!, ticket: `${c.code}-002` },
        { guestId: ids['Kamal']!, ticket: `${c.code}-003` },
      ]),
    ).toEqual(['quarantined', 'quarantined', 'quarantined']);
  });

  test('Perlu ditinjau: Ganda, Nomor bentrok, dan Karantina memakai penanda yang sama persis', async ({ page }) => {
    await page.goto(`/acara/${eventId}/riwayat`);
    await page.getByRole('link', { name: /Perlu ditinjau \(5\)/ }).click();
    await expect(page).toHaveURL(/status=tinjau/);
    const badges = page.getByRole('row').locator('span', { hasText: /— tinjau$/ });
    await expect(badges).toHaveCount(5);
    const texts = await badges.allTextContents();
    expect(new Set(texts.map((t) => t.trim()))).toEqual(
      new Set(['Ganda — tinjau', 'Nomor bentrok — tinjau', 'Karantina — tinjau']),
    );
    const classes = new Set(await badges.evaluateAll((els) => els.map((e) => e.className)));
    expect(classes.size).toBe(1);
    for (const badge of await badges.all()) await expect(badge.locator('svg')).toHaveCount(1);
  });

  test('tandai ditinjau, ubah nomor bentrok, dan undo dengan alasan', async ({ page }) => {
    await page.goto(`/acara/${eventId}/riwayat?status=tinjau`);
    await page.getByRole('button', { name: 'Tandai ditinjau Ani' }).click();
    await expect(page.getByText('Ditandai sudah ditinjau.')).toBeVisible();
    await page.goto(`/acara/${eventId}/riwayat`);
    await expect(page.getByRole('row', { name: /Ani/ }).filter({ hasText: 'Ganda · ditinjau' })).toBeVisible();

    await page.getByRole('button', { name: 'Ubah nomor Ratu' }).click();
    const dialog = page.getByRole('dialog', { name: /Ubah nomor tiket Ratu/ });
    await dialog.getByLabel('Nomor tiket').fill('VVIP-002');
    await dialog.getByRole('button', { name: 'Simpan nomor' }).click();
    await expect(page.getByRole('row', { name: /Ratu/ })).toContainText('Sah');

    // FR-RW-02: datang 2 orang padahal undangan 1 → disorot.
    await expect(page.getByRole('row', { name: /Bayu/ })).toContainText('Lebih 1 dari tercatat');
    await page.getByRole('button', { name: 'Batalkan check-in Bayu' }).click();
    const undo = page.getByRole('dialog', { name: 'Batalkan check-in Bayu?' });
    await expect(undo.getByRole('button', { name: 'Batalkan check-in' })).toBeDisabled();
    await undo.getByLabel('Alasan (wajib)').fill('Salah pindai');
    await undo.getByRole('button', { name: 'Batalkan check-in' }).click();
    const bayu = page.getByRole('row', { name: /Bayu/ });
    await expect(bayu).toContainText('Dibatalkan');
    await expect(bayu).toContainText('Salah pindai');
  });

  test('karantina: setujui per baris, tolak dengan alasan, lalu setujui semua dari satu perangkat', async ({
    page,
  }) => {
    await page.goto(`/acara/${eventId}/riwayat?status=karantina`);
    await expect(page.getByRole('heading', { name: new RegExp(`Perangkat ${c.code}`) })).toBeVisible();
    await page.getByRole('button', { name: 'Setujui Karin' }).click();
    await expect(page.getByText('Karantina disetujui.')).toBeVisible();

    await page.getByRole('button', { name: 'Tolak Kurnia' }).click();
    const reject = page.getByRole('dialog', { name: 'Tolak karantina Kurnia?' });
    await reject.getByLabel('Alasan (wajib)').fill('Bukan tamu acara ini');
    await reject.getByRole('button', { name: 'Tolak' }).click();
    await expect(page.getByText('Karantina ditolak.')).toBeVisible();

    await page.getByRole('button', { name: `Setujui semua dari ${c.code}` }).click();
    await page
      .getByRole('dialog', { name: /Setujui semua karantina/ })
      .getByRole('button', { name: 'Setujui semua' })
      .click();
    await expect(page.getByText(`Semua karantina dari perangkat ${c.code} disetujui.`)).toBeVisible();
    await expect(page.getByText('Tidak ada riwayat yang cocok.')).toBeVisible();

    await page.goto(`/acara/${eventId}/riwayat`);
    await expect(page.getByRole('row', { name: /Karin/ })).toContainText('Sah');
    await expect(page.getByRole('row', { name: /Kamal/ })).toContainText('Sah');
    await expect(page.getByRole('row', { name: /Kurnia/ })).toContainText('Bukan tamu acara ini');
  });

  test('check-out manual tampil di tab Check-Out', async ({ page }) => {
    await page.goto(`/acara/${eventId}/riwayat`);
    await page.getByRole('button', { name: 'Tandai keluar Raja' }).click();
    await expect(page.getByText('Check-out dicatat.')).toBeVisible();
    await page.getByRole('link', { name: 'Check-Out' }).click();
    await expect(page).toHaveURL(/tab=keluar/);
    await expect(page.getByRole('row', { name: /Raja/ })).toContainText('keluar');
    await expect(page.getByRole('row')).toHaveCount(2);
  });
});
