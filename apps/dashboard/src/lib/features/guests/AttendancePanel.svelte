<script lang="ts">
  import type { Json } from '@guestbook/shared/database.types';
  import {
    ATTENDANCE_LABEL,
    checkInBadge,
    QUARANTINE_REASON_LABEL,
    rsvpLabel,
    type CheckInStatus,
  } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { formatDateTime } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import Field from '$lib/ui/Field.svelte';
  import type { GuestListRow } from './query';

  let { guest, onchanged }: { guest: GuestListRow; onchanged: () => void } = $props();

  interface CheckInView {
    id: string;
    actual_pax: number;
    ticket_number: string | null;
    status: CheckInStatus;
    source: 'device' | 'admin' | 'outbox_upload';
    quarantine_reason: 'device_revoked' | 'session_expired' | null;
    checked_in_at: string;
    received_at: string;
    checked_out_at: string | null;
    voided_at: string | null;
    void_reason: string | null;
    reviewed_at: string | null;
    ushers: { name: string } | null;
    devices: { code: string } | null;
  }

  let rows = $state<CheckInView[] | null>(null);
  let loadError = $state<string | null>(null);
  // Panel dipasang ulang per tamu ({#key} di GuestDialog), jadi cukup nilai awal.
  // svelte-ignore state_referenced_locally
  let attendance = $state(guest.attendance_status);

  async function load() {
    const { data, error } = await supabase
      .from('check_ins')
      .select(
        'id, actual_pax, ticket_number, status, source, quarantine_reason, checked_in_at, received_at, checked_out_at, voided_at, void_reason, reviewed_at, ushers(name), devices(code)',
      )
      .eq('guest_id', guest.id)
      .order('received_at', { ascending: true });
    if (error) {
      loadError = dbErrorMessage(error);
      return;
    }
    rows = data as unknown as CheckInView[];
    const { data: g } = await supabase.from('guests').select('attendance_status').eq('id', guest.id).single();
    if (g) attendance = g.attendance_status;
  }

  $effect(() => {
    void load();
  });

  const active = $derived((rows ?? []).filter((r) => !r.voided_at && r.status !== 'quarantined'));

  // --- Tandai hadir manual ---
  // Nilai awal saja; panel dipasang ulang per tamu.
  // svelte-ignore state_referenced_locally
  let manualPax = $state(String(guest.rsvp_status === 'going' && guest.rsvp_pax ? guest.rsvp_pax : guest.invited_pax));
  let manualBusy = $state(false);
  let manualError = $state<string | null>(null);

  async function markPresent(event: SubmitEvent) {
    event.preventDefault();
    const pax = Number(manualPax);
    if (!Number.isInteger(pax) || pax < 0 || pax > 50) {
      manualError = 'Jumlah hadir harus angka bulat 0–50.';
      return;
    }
    manualBusy = true;
    manualError = null;
    const { error } = await supabase.rpc('admin_manual_check_in', { p_guest_id: guest.id, p_actual_pax: pax });
    manualBusy = false;
    if (error) {
      manualError = dbErrorMessage(error);
      return;
    }
    toast.success(`${guest.name} ditandai hadir.`);
    await load();
    onchanged();
  }

  // --- Ubah detail satu check-in ---
  let editing = $state<string | null>(null);
  let edit = $state({ pax: '', ticket: '', reason: '' });
  let editBusy = $state(false);
  let editError = $state<string | null>(null);

  function startEdit(r: CheckInView) {
    editing = r.id;
    edit = { pax: String(r.actual_pax), ticket: r.ticket_number ?? '', reason: '' };
    editError = null;
  }

  async function update(id: string, patch: { [key: string]: Json }, successMessage: string) {
    editBusy = true;
    editError = null;
    const { error } = await supabase.rpc('admin_update_check_in', {
      p_check_in_id: id,
      p_patch: patch,
      p_reason: edit.reason.trim() || undefined,
    });
    editBusy = false;
    if (error) {
      editError = dbErrorMessage(error);
      return false;
    }
    toast.success(successMessage);
    await load();
    onchanged();
    return true;
  }

  async function saveEdit(event: SubmitEvent, r: CheckInView) {
    event.preventDefault();
    const pax = Number(edit.pax);
    if (!Number.isInteger(pax) || pax < 0 || pax > 50) {
      editError = 'Jumlah hadir harus angka bulat 0–50.';
      return;
    }
    const patch: { [key: string]: Json } = {};
    if (pax !== r.actual_pax) patch.actual_pax = pax;
    const ticket = edit.ticket.trim().toUpperCase();
    if (ticket !== (r.ticket_number ?? '')) patch.ticket_number = ticket || null;
    if (Object.keys(patch).length === 0) {
      editing = null;
      return;
    }
    if (await update(r.id, patch, 'Detail kehadiran disimpan.')) editing = null;
  }

  function sourceLabel(r: CheckInView): string {
    if (r.source === 'admin') return 'Ditandai Admin';
    if (r.source === 'outbox_upload') return 'Unggahan outbox darurat';
    return [r.ushers?.name, r.devices ? `perangkat ${r.devices.code}` : null].filter(Boolean).join(' · ');
  }
</script>

<dl class="grid grid-cols-2 gap-x-6 gap-y-3 text-sm sm:grid-cols-4">
  <div>
    <dt class="text-ink-muted">Kehadiran</dt>
    <dd class="mt-0.5 font-medium">{ATTENDANCE_LABEL[attendance]}</dd>
  </div>
  <div>
    <dt class="text-ink-muted">RSVP</dt>
    <dd class="mt-0.5 font-medium">{rsvpLabel(guest.rsvp_status, guest.rsvp_pax)}</dd>
  </div>
  <div>
    <dt class="text-ink-muted">Jumlah undangan</dt>
    <dd class="tabular mt-0.5 font-medium">{guest.invited_pax} orang</dd>
  </div>
  <div>
    <dt class="text-ink-muted">Nomor Urut</dt>
    <dd class="mt-0.5 font-mono font-medium">{guest.special_number ?? '—'}</dd>
  </div>
  {#if guest.is_additional}
    <div class="col-span-full"><Badge variant="info">Tamu tambahan</Badge></div>
  {/if}
</dl>

<h3 class="mt-6 text-sm font-semibold">Riwayat check-in</h3>
{#if loadError}
  <p role="alert" class="mt-2 text-sm text-danger">{loadError}</p>
{:else if rows === null}
  <p class="mt-2 text-sm text-ink-muted" aria-busy="true">Memuat…</p>
{:else if rows.length === 0}
  <p class="mt-2 text-sm text-ink-muted">Belum ada check-in untuk tamu ini.</p>
{:else}
  <ul class="mt-2 divide-y divide-line rounded-dialog border border-line">
    {#each rows as r (r.id)}
      {@const badge = checkInBadge({ status: r.status, reviewedAt: r.reviewed_at, voidedAt: r.voided_at })}
      <li class="px-4 py-3 text-sm">
        <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <Badge
            variant={badge.voided ? 'muted' : badge.needsReview ? 'review' : r.status === 'accepted' ? 'ok' : 'neutral'}
          >
            {badge.text}
          </Badge>
          <span class="font-mono font-medium">{r.ticket_number ?? '—'}</span>
          <span class="tabular">{r.actual_pax} orang</span>
          <span class="text-ink-muted">{sourceLabel(r)}</span>
        </div>
        <p class="tabular mt-1 text-ink-muted">
          Masuk {formatDateTime(r.received_at)}{#if r.checked_out_at}
            · Keluar {formatDateTime(r.checked_out_at)}{/if}
          {#if r.quarantine_reason}· {QUARANTINE_REASON_LABEL[r.quarantine_reason]}{/if}
          {#if r.voided_at}· Dibatalkan: {r.void_reason}{/if}
        </p>
        {#if !r.ticket_number && r.source === 'admin'}
          <p class="mt-1 text-ink-muted">Ditandai hadir oleh Admin, tanpa tiket.</p>
        {/if}

        {#if !r.voided_at && r.status !== 'quarantined'}
          {#if editing === r.id}
            <form class="mt-3 space-y-3 rounded-control bg-surface p-3" onsubmit={(e) => saveEdit(e, r)} novalidate>
              <div class="grid gap-3 sm:grid-cols-2">
                <Field id="edit-pax-{r.id}" label="Jumlah hadir" type="number" min={0} max={50} bind:value={edit.pax} />
                <Field
                  id="edit-ticket-{r.id}"
                  label="Nomor tiket"
                  class="[&_input]:font-mono [&_input]:uppercase"
                  maxlength={20}
                  bind:value={edit.ticket}
                />
              </div>
              <Field
                id="edit-reason-{r.id}"
                label="Alasan perubahan (opsional)"
                maxlength={300}
                bind:value={edit.reason}
              />
              {#if editError}<p role="alert" class="text-sm text-danger">{editError}</p>{/if}
              <div class="flex flex-wrap gap-2">
                <Button type="submit" size="sm" busy={editBusy}>Simpan</Button>
                <Button size="sm" variant="secondary" onclick={() => (editing = null)} disabled={editBusy}>Batal</Button
                >
              </div>
            </form>
          {:else}
            <div class="mt-2 flex flex-wrap gap-2">
              <Button size="sm" variant="secondary" onclick={() => startEdit(r)}>Ubah detail</Button>
              {#if r.checked_out_at}
                <Button
                  size="sm"
                  variant="ghost"
                  busy={editBusy}
                  onclick={() => update(r.id, { checked_out_at: null }, 'Check-out dibatalkan.')}
                  >Batalkan keluar</Button
                >
              {:else}
                <Button
                  size="sm"
                  variant="ghost"
                  busy={editBusy}
                  onclick={() => update(r.id, { checked_out_at: new Date().toISOString() }, 'Check-out dicatat.')}
                  >Tandai keluar sekarang</Button
                >
              {/if}
            </div>
          {/if}
        {/if}
      </li>
    {/each}
  </ul>
{/if}

{#if rows !== null && active.length === 0}
  <form class="mt-6 rounded-dialog border border-line p-4" onsubmit={markPresent} novalidate>
    <h3 class="text-sm font-semibold">Tandai hadir</h3>
    <p class="mt-1 text-sm text-ink-muted">
      Untuk tamu yang sudah datang tetapi belum tercatat. Tidak ada tiket yang dicetak; nomor tiket memakai Nomor Urut
      tamu bila ada.
    </p>
    <div class="mt-3 flex flex-wrap items-end gap-3">
      <Field id="manual-pax" label="Jumlah hadir" type="number" min={0} max={50} class="w-32" bind:value={manualPax} />
      <Button type="submit" busy={manualBusy}>Tandai hadir</Button>
    </div>
    {#if manualError}<p role="alert" class="mt-2 text-sm text-danger">{manualError}</p>{/if}
  </form>
{/if}
