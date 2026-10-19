import { expect, test } from '@playwright/test';
import { adminApi, createEvent, createUsher, eventCode, guestIds, loginDevice, pushCheckIns, uniqueName } from './api';

// FR-S-01..05, FR-S-07: angka berubah ≤ 3 detik lewat Broadcast; polling 10 detik bila Realtime tidak tersedia.
test.describe('Statistik', () => {
  test('check-in baru tampil di Statistik dalam ≤ 3 detik (Realtime Broadcast)', async ({ page }) => {
    const eventId = await createEvent(uniqueName('Statistik Live'), [
      { name: 'Ani', rsvp_status: 'going', rsvp_pax: 2, invited_pax: 2 },
      { name: 'Bayu', category: 'vip', invited_pax: 1 },
    ]);
    const ids = await guestIds(eventId);
    const usher = await createUsher(eventId, 'Usher Live');
    const device = await loginDevice(await eventCode(eventId), usher.pin);

    let statsCalls = 0;
    page.on('response', (r) => {
      if (r.url().includes('/rpc/get_event_stats')) statsCalls++;
    });
    await page.goto(`/acara/${eventId}/statistik`);
    const status = page.getByRole('status').filter({ hasText: /Langsung|Diperbarui|Menyambung/ });
    await expect(status).toContainText('Langsung', { timeout: 15_000 });
    const hero = page.getByRole('region', { name: 'Orang hadir' });
    await expect(hero).toContainText('0');
    await expect(hero).toContainText('dari 2 orang Akan hadir');
    // Muat ulang otomatis saat channel tersambung harus selesai dulu, agar yang diukur benar-benar jalur
    // Broadcast → debounce → RPC, bukan muat ulang yang kebetulan bersamaan.
    await expect.poll(() => statsCalls).toBeGreaterThanOrEqual(2);
    // Tanpa perubahan data, tidak ada muat ulang tambahan (regresi: loop sambung ulang channel).
    const settled = statsCalls;
    await page.waitForTimeout(3_000);
    expect(statsCalls).toBe(settled);

    const started = Date.now();
    expect(await pushCheckIns(device, [{ guestId: ids['Ani']!, ticket: `${device.code}-001`, pax: 3 }])).toEqual([
      'accepted',
    ]);
    await expect(hero.locator('.text-5xl')).toHaveText('3', { timeout: 3_000 });
    const elapsed = Date.now() - started;
    test.info().annotations.push({ type: 'latensi', description: `${elapsed} ms` });
    console.log(`Latensi statistik: ${elapsed} ms`);
    expect(elapsed).toBeLessThanOrEqual(3_000);

    await expect(page.getByText('Tamu undangan masuk')).toBeVisible();
    await expect(page.getByRole('row', { name: /Regular/ })).toContainText('3 orang');
    await expect(page.getByText('Di luar jumlah tercatat').locator('..')).toContainText('1');
  });

  test('tanpa Realtime, dashboard beralih ke polling tiap 10 detik', async ({ page }) => {
    const eventId = await createEvent(uniqueName('Statistik Polling'), [{ name: 'Citra' }]);
    const ids = await guestIds(eventId);
    const usher = await createUsher(eventId, 'Usher Polling');
    const device = await loginDevice(await eventCode(eventId), usher.pin);
    await page.routeWebSocket(/realtime/, (ws) => ws.close());

    await page.goto(`/acara/${eventId}/statistik`);
    await expect(page.getByText('Diperbarui tiap 10 detik')).toBeVisible({ timeout: 15_000 });
    await pushCheckIns(device, [{ guestId: ids['Citra']!, ticket: `${device.code}-001`, pax: 2 }]);
    await expect(page.getByRole('region', { name: 'Orang hadir' }).locator('.text-5xl')).toHaveText('2', {
      timeout: 15_000,
    });
  });

  test('melebihi batas manual memunculkan peringatan yang menyebut sumber batas', async ({ page }) => {
    const eventId = await createEvent(uniqueName('Statistik Batas'), [{ name: 'Dodi', invited_pax: 5 }]);
    const ids = await guestIds(eventId);
    const sb = await adminApi();
    await sb.rpc('admin_update_event', { p_event_id: eventId, p_patch: { attendance_limit: 2 } });
    await sb.rpc('admin_manual_check_in', { p_guest_id: ids['Dodi']!, p_actual_pax: 4 });

    await page.goto(`/acara/${eventId}/statistik`);
    const alert = page.getByRole('alert').filter({ hasText: 'melebihi batas' });
    await expect(alert).toContainText('Jumlah hadir 4 orang melebihi batas 2 orang');
    await expect(alert).toContainText('diatur manual');
  });
});
