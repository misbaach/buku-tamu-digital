import { expect, test } from '@playwright/test';
import { adminApi, createEvent, uniqueName } from './api';

test('edit massal: ubah kategori dan grup, lalu hapus Nomor Urut terpilih', async ({ page }) => {
  const id = await createEvent(uniqueName('Massal Uji'), [
    { name: 'Massal Satu', special_number: 'MSL-1' },
    { name: 'Massal Dua', special_number: 'MSL-2' },
    { name: 'Massal Tiga' },
  ]);
  const sb = await adminApi();
  await sb.from('guest_groups').insert({ event_id: id, name: 'Rombongan' });

  await page.goto(`/acara/${id}/tamu`);
  await page.getByRole('checkbox', { name: 'Pilih Massal Satu' }).check();
  await page.getByRole('checkbox', { name: 'Pilih Massal Dua' }).check();
  const bar = page.getByRole('region', { name: 'Aksi untuk tamu terpilih' });
  await expect(bar).toContainText('2 dipilih');

  await bar.getByLabel('Kategori baru').selectOption('vvip');
  await bar.getByRole('button', { name: 'Terapkan' }).nth(1).click();
  await expect(page.getByRole('row', { name: /Massal Satu/ })).toContainText('VVIP');
  await expect(page.getByRole('row', { name: /Massal Dua/ })).toContainText('VVIP');
  await expect(page.getByRole('row', { name: /Massal Tiga/ })).toContainText('Regular');

  await page.getByRole('checkbox', { name: 'Pilih semua tamu di halaman ini' }).check();
  await bar.getByLabel('Grup baru').selectOption({ label: 'Rombongan' });
  await bar.getByRole('button', { name: 'Terapkan' }).first().click();
  await expect(page.getByRole('row', { name: /Massal Tiga/ })).toContainText('Rombongan');

  await page.getByRole('checkbox', { name: 'Pilih semua tamu di halaman ini' }).check();
  await bar.getByRole('button', { name: 'Hapus Nomor Urut' }).click();
  await page
    .getByRole('dialog', { name: 'Hapus Nomor Urut 3 tamu?' })
    .getByRole('button', { name: 'Hapus Nomor Urut' })
    .click();
  await expect(page.getByText('2 Nomor Urut dihapus.')).toBeVisible();
  await expect(page.getByRole('row', { name: /Massal Satu/ })).not.toContainText('MSL-1');
});

test('grup: tambah, nama ganda ditolak, hapus melepas anggota', async ({ page }) => {
  const id = await createEvent(uniqueName('Grup Uji'));
  await page.goto(`/acara/${id}/grup`);
  await page.getByRole('button', { name: 'Tambah grup' }).first().click();
  let dialog = page.getByRole('dialog', { name: 'Tambah grup' });
  await dialog.getByLabel('Nama grup').fill('Keluarga Besar');
  await dialog.getByRole('button', { name: 'Simpan grup' }).click();
  await expect(page.getByRole('row', { name: /Keluarga Besar/ })).toBeVisible();

  await page.getByRole('button', { name: 'Tambah grup' }).first().click();
  dialog = page.getByRole('dialog', { name: 'Tambah grup' });
  await dialog.getByLabel('Nama grup').fill('  keluarga besar ');
  await dialog.getByRole('button', { name: 'Simpan grup' }).click();
  await expect(dialog.getByLabel('Nama grup')).toHaveAccessibleDescription('Nama grup sudah dipakai di acara ini.');
  await dialog.getByRole('button', { name: 'Batal' }).click();

  const sb = await adminApi();
  const { data: group } = await sb.from('guest_groups').select('id').eq('event_id', id).single();
  await sb.from('guests').insert({ event_id: id, name: 'Anggota Grup', group_id: group!.id });
  await page.reload();
  await expect(page.getByRole('row', { name: /Keluarga Besar/ })).toContainText('1');

  await page.getByRole('button', { name: 'Hapus grup Keluarga Besar' }).click();
  const confirm = page.getByRole('dialog', { name: 'Hapus grup Keluarga Besar?' });
  await expect(confirm).toContainText('1 tamu di grup ini akan menjadi tanpa grup');
  await confirm.getByRole('button', { name: 'Hapus grup' }).click();
  await expect(page.getByText('Belum ada grup.')).toBeVisible();

  await page.goto(`/acara/${id}/tamu`);
  await expect(
    page
      .getByRole('row', { name: /Anggota Grup/ })
      .getByRole('cell')
      .nth(3),
  ).toHaveText('—');
});
