<script lang="ts">
  import { invalidate } from '$app/navigation';
  import { resolve } from '$app/paths';
  import Copy from '@lucide/svelte/icons/copy';
  import Plus from '@lucide/svelte/icons/plus';
  import Settings from '@lucide/svelte/icons/settings-2';
  import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
  import {
    CLOCK_SKEW_WARN_MS,
    DEVICE_STATE_LABEL,
    QUARANTINE_MAX_ITEMS_PER_DEVICE,
    USHER_MODE_LABEL,
    deviceState,
    type DeviceState,
    type UsherMode,
  } from '@guestbook/shared';
  import LoginQrDialog from '$lib/features/ushers/LoginQrDialog.svelte';
  import PinDialog from '$lib/features/ushers/PinDialog.svelte';
  import UsherFormDialog from '$lib/features/ushers/UsherFormDialog.svelte';
  import { quarantineDevice, terminateDevice } from '$lib/features/ushers/revoke';
  import { formatSkew, formatWait } from '$lib/features/ushers/types';
  import { dbErrorMessage } from '$lib/errors';
  import { formatDateTime, formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import EmptyState from '$lib/ui/EmptyState.svelte';
  import LinkButton from '$lib/ui/LinkButton.svelte';

  let { data } = $props();
  type Usher = (typeof data.ushers)[number];
  type Device = (typeof data.devices)[number];

  const archived = $derived(!!data.event.archived_at);
  const now = $derived(new Date());
  const states = $derived(new Map(data.devices.map((d) => [d.id, deviceState(d, archived, now)] as const)));
  const activeCount = $derived(
    new Map(
      data.ushers.map((u) => [
        u.id,
        data.devices.filter((d) => d.usher_id === u.id && states.get(d.id) === 'active').length,
      ]),
    ),
  );
  const stateVariant: Record<DeviceState, 'ok' | 'muted' | 'danger'> = {
    active: 'ok',
    revoked: 'muted',
    terminated: 'danger',
    expired: 'muted',
  };

  function refresh() {
    return invalidate('app:ushers');
  }

  async function copyCode() {
    try {
      await navigator.clipboard.writeText(data.event.code);
      toast.success('Kode Acara disalin.');
    } catch {
      toast.error('Kode Acara tidak bisa disalin otomatis. Salin manual dari layar.');
    }
  }

  // --- Tambah / ubah, PIN, QR Login ---
  let formOpen = $state(false);
  let editing = $state<Usher | null>(null);
  let pinOpen = $state(false);
  let pin = $state({ value: '', name: '' });
  let qrOpen = $state(false);

  function openForm(usher: Usher | null) {
    editing = usher;
    formOpen = true;
  }

  async function onsaved(result: { name: string; pin?: string; revokedDevices?: number }) {
    if (result.pin) {
      pin = { value: result.pin, name: result.name };
      pinOpen = true;
    } else {
      toast.success(
        result.revokedDevices
          ? `${result.name} disimpan. ${result.revokedDevices} perangkat dicabut.`
          : `${result.name} disimpan.`,
      );
    }
    await refresh();
  }

  // --- Reset PIN dan hapus ---
  let target = $state<Usher | null>(null);
  let resetOpen = $state(false);
  let deleteOpen = $state(false);
  let actionBusy = $state(false);
  let actionError = $state<string | null>(null);

  async function resetPin() {
    if (!target) return;
    actionBusy = true;
    actionError = null;
    const { data: result, error } = await supabase.rpc('admin_reset_usher_pin', { p_usher_id: target.id });
    actionBusy = false;
    if (error) return void (actionError = dbErrorMessage(error));
    resetOpen = false;
    pin = { value: (result as { pin: string }).pin, name: target.name };
    pinOpen = true;
  }

  async function removeUsher() {
    if (!target) return;
    actionBusy = true;
    actionError = null;
    const { data: result, error } = await supabase.rpc('admin_delete_usher', { p_usher_id: target.id });
    actionBusy = false;
    if (error) return void (actionError = dbErrorMessage(error));
    deleteOpen = false;
    const revoked = (result as { revoked_devices: number }).revoked_devices;
    toast.success(revoked ? `${target.name} dihapus. ${revoked} perangkat dicabut.` : `${target.name} dihapus.`);
    await refresh();
  }

  // --- Cabut perangkat (FR-R-08) ---
  let device = $state<Device | null>(null);
  let quarantineOpen = $state(false);
  let terminateOpen = $state(false);

  async function runRevoke(action: () => ReturnType<typeof quarantineDevice>, close: () => void) {
    actionBusy = true;
    actionError = null;
    const result = await action();
    actionBusy = false;
    if (!result.ok) return void (actionError = result.message);
    close();
    toast.success(result.message);
    await refresh();
  }

  function openUsherAction(usher: Usher, action: 'qr' | 'reset' | 'delete') {
    target = usher;
    actionError = null;
    if (action === 'qr') qrOpen = true;
    else if (action === 'reset') resetOpen = true;
    else deleteOpen = true;
  }

  function openDeviceAction(d: Device, action: 'quarantine' | 'terminate') {
    device = d;
    actionError = null;
    if (action === 'quarantine') quarantineOpen = true;
    else terminateOpen = true;
  }
</script>

<svelte:head>
  <title>Penerima Tamu · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Penerima Tamu</h2>
    <p class="mt-1 text-sm text-ink-muted">Akun usher, PIN Akses, QR Login, dan perangkat yang sedang dipakai.</p>
  </div>
  <div class="flex flex-wrap gap-2">
    <LinkButton href={resolve(`/acara/${data.event.id}/penerima-tamu/pengaturan`)}
      ><Settings size={16} aria-hidden="true" />Pengaturan check-in</LinkButton
    >
    <Button onclick={() => openForm(null)} disabled={archived}
      ><Plus size={16} aria-hidden="true" />Tambah penerima tamu</Button
    >
  </div>
</div>

<!-- Peringatan keamanan (FR-R-08, FR-R-09) -->
{#if data.alerts.blocked.length || data.alerts.loginFailures.warning || data.alerts.quarantineFull.length}
  <div class="mt-5 space-y-2">
    {#each data.alerts.blocked as block (block.ip + block.scope)}
      <div role="alert" class="flex gap-3 rounded-dialog border border-warn bg-warn-bg px-4 py-3 text-[0.9375rem]">
        <TriangleAlert size={18} class="mt-0.5 shrink-0 text-warn" aria-hidden="true" />
        <p>
          <strong>Login PIN diblokir sementara</strong> untuk jaringan
          <span class="font-mono">{block.ip}</span>{block.scope === 'ip' ? ' (semua Kode Acara)' : ''}, sisa
          {formatWait(block.retryAfterSec)}. Usher di jaringan itu tetap bisa masuk lewat <strong>QR Login</strong>.
        </p>
      </div>
    {/each}
    {#if data.alerts.loginFailures.warning}
      <div role="alert" class="flex gap-3 rounded-dialog border border-warn bg-warn-bg px-4 py-3 text-[0.9375rem]">
        <TriangleAlert size={18} class="mt-0.5 shrink-0 text-warn" aria-hidden="true" />
        <p>
          <strong>{formatNumber(data.alerts.loginFailures.count)} percobaan PIN gagal</strong> dalam
          {data.alerts.loginFailures.windowMin} menit terakhir. Login tidak dikunci; bila bukan dari usher Anda, reset PIN
          usher yang terlibat.
        </p>
      </div>
    {/if}
    {#each data.alerts.quarantineFull as full (full.deviceId)}
      <div role="alert" class="flex gap-3 rounded-dialog border border-warn bg-warn-bg px-4 py-3 text-[0.9375rem]">
        <TriangleAlert size={18} class="mt-0.5 shrink-0 text-warn" aria-hidden="true" />
        <p>
          <strong
            >Perangkat {full.code} mencapai batas {formatNumber(QUARANTINE_MAX_ITEMS_PER_DEVICE)} data karantina.</strong
          >
          Data berikutnya dari perangkat ini ditolak. Pertimbangkan Cabut & putus total.
        </p>
      </div>
    {/each}
  </div>
{/if}

<!-- Kode Acara (tidak rahasia) -->
<section
  class="mt-6 flex flex-wrap items-center justify-between gap-4 rounded-dialog border border-line bg-surface px-5 py-4"
>
  <div>
    <h3 class="text-sm font-medium text-ink-muted">Kode Acara</h3>
    <p class="font-mono text-3xl font-semibold tracking-[0.15em]">{data.event.code}</p>
    <p class="mt-1 text-sm text-ink-muted">Tidak rahasia. Usher memasukkan kode ini bersama PIN masing-masing.</p>
  </div>
  <Button variant="secondary" onclick={copyCode}><Copy size={16} aria-hidden="true" />Salin kode</Button>
</section>

<!-- Daftar usher -->
<section class="mt-8" aria-labelledby="usher-heading">
  <h3 id="usher-heading" class="text-lg font-semibold">Usher</h3>
  {#if data.ushers.length === 0}
    <div class="mt-3">
      <EmptyState title="Belum ada penerima tamu.">
        Tambahkan usher untuk membuat PIN Akses. PIN hanya ditampilkan sekali.
        {#snippet actions()}
          <Button onclick={() => openForm(null)} disabled={archived}
            ><Plus size={16} aria-hidden="true" />Tambah penerima tamu</Button
          >
        {/snippet}
      </EmptyState>
    </div>
  {:else}
    <div class="mt-3 overflow-x-auto rounded-dialog border border-line">
      <table class="w-full min-w-3xl text-left text-sm">
        <thead class="bg-surface text-ink-muted">
          <tr>
            <th scope="col" class="px-4 py-2.5 font-medium">ID usher</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Nama</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Mode</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Status</th>
            <th scope="col" class="px-4 py-2.5 text-right font-medium">Perangkat aktif</th>
            <th scope="col" class="px-4 py-2.5"><span class="sr-only">Aksi</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each data.ushers as usher (usher.id)}
            <tr class="hover:bg-surface">
              <td class="px-4 py-3 font-mono font-semibold">{usher.pin_selector}</td>
              <td class="px-4 py-3 font-medium">{usher.name}</td>
              <td class="px-4 py-3 whitespace-nowrap">{USHER_MODE_LABEL[usher.mode as UsherMode]}</td>
              <td class="px-4 py-3">
                {#if usher.is_active}<Badge variant="ok">Aktif</Badge>{:else}<Badge variant="muted">Nonaktif</Badge
                  >{/if}
              </td>
              <td class="tabular px-4 py-3 text-right">{formatNumber(activeCount.get(usher.id) ?? 0)}</td>
              <td class="px-4 py-2">
                <div class="flex justify-end gap-1">
                  <Button
                    size="sm"
                    variant="ghost"
                    disabled={!usher.is_active || archived}
                    aria-label="QR Login untuk {usher.name}"
                    onclick={() => openUsherAction(usher, 'qr')}>QR Login</Button
                  >
                  <Button
                    size="sm"
                    variant="ghost"
                    aria-label="Reset PIN {usher.name}"
                    onclick={() => openUsherAction(usher, 'reset')}>Reset PIN</Button
                  >
                  <Button size="sm" variant="ghost" aria-label="Ubah {usher.name}" onclick={() => openForm(usher)}
                    >Ubah</Button
                  >
                  <Button
                    size="sm"
                    variant="danger-ghost"
                    aria-label="Hapus {usher.name}"
                    onclick={() => openUsherAction(usher, 'delete')}>Hapus</Button
                  >
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>

<!-- Daftar perangkat minimal (FR-R-08) -->
<section class="mt-8" aria-labelledby="device-heading">
  <h3 id="device-heading" class="text-lg font-semibold">Perangkat</h3>
  <p class="mt-1 text-sm text-ink-muted">
    Kode perangkat menjadi awalan nomor tiket otomatis (mis. A-017). Jam perangkat tidak dipakai sebagai bukti.
  </p>
  {#if data.devices.length === 0}
    <p class="mt-3 rounded-dialog border border-line px-4 py-6 text-ink-muted">
      Belum ada perangkat yang masuk. Perangkat muncul di sini setelah usher login di App Penerima Tamu.
    </p>
  {:else}
    <div class="mt-3 overflow-x-auto rounded-dialog border border-line">
      <table class="w-full min-w-5xl text-left text-sm">
        <thead class="bg-surface text-ink-muted">
          <tr>
            <th scope="col" class="px-4 py-2.5 font-medium">Kode</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Usher · perangkat</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Masuk</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Terakhir terlihat</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Sesi berakhir</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Status</th>
            <th scope="col" class="px-4 py-2.5 text-right font-medium">Karantina</th>
            <th scope="col" class="px-4 py-2.5"><span class="sr-only">Aksi</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each data.devices as d (d.id)}
            {@const state = states.get(d.id) ?? 'active'}
            <tr class="hover:bg-surface">
              <td class="px-4 py-3 font-mono text-base font-semibold">{d.code}</td>
              <td class="px-4 py-3">
                <span class="font-medium">{d.usher_name}</span>
                <span class="block text-ink-muted"
                  >{d.name ?? 'Tanpa nama'}{d.app_version ? ` · v${d.app_version}` : ''}</span
                >
              </td>
              <td class="tabular px-4 py-3">{formatDateTime(d.created_at)}</td>
              <td class="tabular px-4 py-3">
                {d.last_seen_at ? formatDateTime(d.last_seen_at) : '—'}
                {#if d.clock_offset_ms !== null && Math.abs(d.clock_offset_ms) > CLOCK_SKEW_WARN_MS}
                  <span class="block text-warn">Jam perangkat {formatSkew(d.clock_offset_ms)}</span>
                {/if}
              </td>
              <td class="tabular px-4 py-3">{formatDateTime(d.session_expires_at)}</td>
              <td class="px-4 py-3">
                <Badge variant={stateVariant[state]}>{DEVICE_STATE_LABEL[state]}</Badge>
                {#if d.revoke_reason}<span class="mt-1 block max-w-48 text-ink-muted">{d.revoke_reason}</span>{/if}
              </td>
              <td class="tabular px-4 py-3 text-right">
                {#if d.quarantined > 0}<Badge variant="review">{formatNumber(d.quarantined)}</Badge>{:else}0{/if}
              </td>
              <td class="px-4 py-2">
                <div class="flex justify-end gap-1">
                  {#if !d.revoke_mode}
                    <Button
                      size="sm"
                      variant="secondary"
                      aria-label="Cabut perangkat {d.code}"
                      onclick={() => openDeviceAction(d, 'quarantine')}>Cabut</Button
                    >
                  {/if}
                  {#if d.revoke_mode !== 'terminate'}
                    <Button
                      size="sm"
                      variant="danger-ghost"
                      aria-label="Cabut & putus total perangkat {d.code}"
                      onclick={() => openDeviceAction(d, 'terminate')}>Cabut & putus total</Button
                    >
                  {/if}
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</section>

<UsherFormDialog bind:open={formOpen} eventId={data.event.id} usher={editing} {onsaved} />
<PinDialog bind:open={pinOpen} pin={pin.value} usherName={pin.name} eventCode={data.event.code} />
<LoginQrDialog bind:open={qrOpen} usher={target} />

<ConfirmDialog
  bind:open={resetOpen}
  title="Reset PIN {target?.name ?? ''}?"
  confirmLabel="Buat PIN baru"
  variant="primary"
  busy={actionBusy}
  error={actionError}
  onconfirm={resetPin}
>
  <p>
    PIN lama langsung tidak berlaku. ID usher <span class="font-mono">{target?.pin_selector}</span> tetap sama. Perangkat
    yang sudah masuk tidak terpengaruh.
  </p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={deleteOpen}
  title="Hapus {target?.name ?? ''}?"
  confirmLabel="Hapus penerima tamu"
  busy={actionBusy}
  error={actionError}
  onconfirm={removeUsher}
>
  <p>Semua perangkat usher ini dicabut (tingkat Cabut). Data yang masih dikirim masuk karantina untuk Anda tinjau.</p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={quarantineOpen}
  title="Cabut perangkat {device?.code ?? ''}?"
  confirmLabel="Cabut"
  variant="primary"
  busy={actionBusy}
  error={actionError}
  onconfirm={() =>
    runRevoke(
      () => quarantineDevice(device!.id),
      () => (quarantineOpen = false),
    )}
>
  <p>Perangkat tidak lagi menerima data. Data yang masih dikirim masuk karantina untuk Anda tinjau.</p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={terminateOpen}
  title="Cabut & putus total perangkat {device?.code ?? ''}?"
  confirmLabel="Cabut & putus total"
  reasonLabel="Alasan (wajib)"
  busy={actionBusy}
  error={actionError}
  onconfirm={(reason) =>
    runRevoke(
      () => terminateDevice(device!.id, reason),
      () => (terminateOpen = false),
    )}
>
  <p>
    Untuk HP hilang atau dicuri. Sesi langsung diakhiri dan semua data dari perangkat ini ditolak. Data yang belum
    terkirim hanya bisa masuk lewat file ekspor.
  </p>
</ConfirmDialog>
