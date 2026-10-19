<script lang="ts">
  /* eslint-disable svelte/no-navigation-without-resolve -- semua tautan dibangun dari `base` (hasil resolve()) ditambah query */
  import { goto, invalidate } from '$app/navigation';
  import { resolve } from '$app/paths';
  import Search from '@lucide/svelte/icons/search';
  import {
    QUARANTINE_REASON_LABEL,
    REVIEW_STATUSES,
    checkInBadge,
    rsvpLabel,
    type CheckInStatus,
  } from '@guestbook/shared';
  import {
    HISTORY_PAGE_SIZE,
    historySearch,
    recordedPax,
    type HistoryFilter,
    type HistoryParams,
    type HistoryRow,
    type HistoryTab,
  } from '$lib/features/history/query';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import CategoryIcon from '$lib/ui/CategoryIcon.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import EmptyState from '$lib/ui/EmptyState.svelte';
  import Field from '$lib/ui/Field.svelte';
  import Pagination from '$lib/ui/Pagination.svelte';

  let { data } = $props();
  const base = $derived(resolve(`/acara/${data.event.id}/riwayat`));
  const time = $derived(
    new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit', timeZone: data.event.timezone }),
  );
  const reviewTotal = $derived(data.review.quarantined + data.review.duplicate + data.review.conflict);

  const tabs: { id: HistoryTab; label: string }[] = [
    { id: 'masuk', label: 'Check-In' },
    { id: 'keluar', label: 'Check-Out' },
    { id: 'semua', label: 'Semua' },
  ];
  const chips = $derived<{ id: HistoryFilter | null; label: string; count?: number }[]>([
    { id: null, label: 'Semua status' },
    { id: 'tinjau', label: 'Perlu ditinjau', count: reviewTotal },
    { id: 'karantina', label: 'Karantina', count: data.review.quarantined },
    { id: 'ganda', label: 'Ganda', count: data.review.duplicate },
    { id: 'bentrok', label: 'Nomor bentrok', count: data.review.conflict },
    { id: 'dibatalkan', label: 'Dibatalkan' },
  ]);

  function href(patch: Partial<HistoryParams>) {
    return base + historySearch({ ...data.filters, hal: 1, ...patch });
  }

  // Ikut URL; ditimpa ketikan pengguna sampai navigasi berikutnya.
  let search = $derived(data.filters.q);
  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  function onSearchInput() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(
      () => void goto(href({ q: search.trim() }), { keepFocus: true, noScroll: true, replaceState: true }),
      300,
    );
  }

  // Karantina dikelompokkan per perangkat untuk aksi massal (FR-RW-05).
  const groups = $derived.by(() => {
    if (data.filters.status !== 'karantina') return [];
    // eslint-disable-next-line svelte/prefer-svelte-reactivity -- Map sementara di dalam $derived, bukan state
    const map = new Map<string, { deviceId: string; code: string; rows: HistoryRow[] }>();
    for (const r of data.rows) {
      const key = r.device_id ?? 'tanpa-perangkat';
      const g = map.get(key) ?? { deviceId: key, code: r.devices?.code ?? '—', rows: [] };
      g.rows.push(r);
      map.set(key, g);
    }
    return [...map.values()];
  });

  function guestName(r: HistoryRow) {
    return r.guests?.name ?? r.pending_guest?.name ?? 'Tamu tidak dikenal';
  }
  function over(r: HistoryRow): number {
    if (!r.guests || r.guests.is_additional || r.voided_at || !['accepted', 'conflict'].includes(r.status)) return 0;
    return Math.max(0, r.actual_pax - recordedPax(r.guests));
  }
  const isReview = (s: CheckInStatus) => (REVIEW_STATUSES as readonly CheckInStatus[]).includes(s);
  const refresh = () => invalidate('app:history');

  // --- Aksi ---
  let busy = $state(false);
  let error = $state<string | null>(null);
  let target = $state<HistoryRow | null>(null);
  let device = $state<{ deviceId: string; code: string; count: number } | null>(null);
  let voidOpen = $state(false);
  let rejectOpen = $state(false);
  let approveAllOpen = $state(false);
  let rejectAllOpen = $state(false);
  let ticketOpen = $state(false);
  let ticket = $state('');

  async function run(
    action: () => PromiseLike<{ error: unknown; data?: unknown }>,
    message: string,
    close?: () => void,
  ) {
    busy = true;
    error = null;
    const { error: e, data: result } = await action();
    busy = false;
    if (e) {
      error = dbErrorMessage(e);
      if (!close) toast.error(error);
      return null;
    }
    close?.();
    toast.success(message);
    await refresh();
    return result;
  }

  function open(row: HistoryRow, which: 'void' | 'reject' | 'ticket') {
    target = row;
    error = null;
    if (which === 'void') voidOpen = true;
    else if (which === 'reject') rejectOpen = true;
    else {
      ticket = row.ticket_number ?? '';
      ticketOpen = true;
    }
  }

  function openDevice(group: { deviceId: string; code: string; rows: HistoryRow[] }, which: 'approve' | 'reject') {
    device = { deviceId: group.deviceId, code: group.code, count: group.rows.length };
    error = null;
    if (which === 'approve') approveAllOpen = true;
    else rejectAllOpen = true;
  }

  async function approve(row: HistoryRow) {
    const result = (await run(
      () =>
        supabase.rpc('admin_decide_quarantine', { p_event_id: data.event.id, p_decision: 'approve', p_ids: [row.id] }),
      'Karantina disetujui.',
    )) as { results: { status: string }[] } | null;
    const status = result?.results[0]?.status;
    if (status === 'duplicate' || status === 'conflict')
      toast.error('Hasilnya perlu ditinjau: lihat status baris tersebut.');
  }

  async function saveTicket(event: SubmitEvent) {
    event.preventDefault();
    if (!target) return;
    const t = target;
    await run(
      () =>
        supabase.rpc('admin_update_check_in', {
          p_check_in_id: t.id,
          p_patch: { ticket_number: ticket },
          p_reason: 'Ubah nomor dari Riwayat',
        }),
      'Nomor tiket diubah; status dievaluasi ulang.',
      () => (ticketOpen = false),
    );
  }
</script>

<svelte:head>
  <title>Riwayat · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Riwayat</h2>
    <p class="mt-1 text-sm text-ink-muted">
      Diurutkan menurut waktu diterima server. Jam check-in berasal dari perangkat dan tidak terverifikasi.
    </p>
  </div>
  <form role="search" class="relative w-full max-w-xs" onsubmit={(e) => e.preventDefault()}>
    <label for="history-search" class="sr-only">Cari nama tamu</label>
    <Search size={16} class="pointer-events-none absolute top-3 left-3 text-ink-muted" aria-hidden="true" />
    <input
      id="history-search"
      type="search"
      bind:value={search}
      oninput={onSearchInput}
      placeholder="Cari nama tamu"
      class="h-10 w-full rounded-control border border-line-strong bg-bg pr-3 pl-9 text-base"
    />
  </form>
</div>

<nav aria-label="Jenis riwayat" class="mt-5 flex gap-1 border-b border-line">
  {#each tabs as t (t.id)}
    <a
      href={href({ tab: t.id })}
      aria-current={data.filters.tab === t.id ? 'page' : undefined}
      class={[
        '-mb-px border-b-2 px-3 py-2 text-sm font-medium',
        data.filters.tab === t.id ? 'border-ink text-ink' : 'border-transparent text-ink-muted hover:text-ink',
      ]}>{t.label}</a
    >
  {/each}
</nav>

<nav aria-label="Saring status" class="mt-3 flex flex-wrap gap-2">
  {#each chips as c (c.id ?? 'semua')}
    <a
      href={href({ status: c.id })}
      aria-current={data.filters.status === c.id ? 'true' : undefined}
      class={[
        'inline-flex h-8 items-center gap-1.5 rounded-control border px-3 text-sm',
        data.filters.status === c.id
          ? 'border-ink bg-ink text-on-primary'
          : c.id === 'tinjau' && reviewTotal > 0
            ? 'border-warn bg-warn-bg font-semibold text-warn'
            : 'border-line-strong bg-bg hover:bg-surface',
      ]}
    >
      {c.label}{#if c.count !== undefined}<span class="tabular">({formatNumber(c.count)})</span>{/if}
    </a>
  {/each}
</nav>

{#snippet row(r: HistoryRow)}
  {@const badge = checkInBadge({ status: r.status, reviewedAt: r.reviewed_at, voidedAt: r.voided_at })}
  {@const extra = over(r)}
  <tr class={['align-top hover:bg-surface', r.voided_at && 'text-ink-muted']}>
    <td class="tabular px-4 py-3 whitespace-nowrap">
      {time.format(new Date(r.checked_in_at))}
      {#if r.checked_out_at}<span class="block text-ink-muted">keluar {time.format(new Date(r.checked_out_at))}</span
        >{/if}
    </td>
    <td class="px-4 py-3">
      <span class={['inline-flex items-center gap-1.5 font-medium', r.voided_at && 'line-through']}>
        {#if r.guests}<CategoryIcon category={r.guests.category} />{/if}{guestName(r)}
      </span>
      <span class="mt-1 flex flex-wrap gap-1">
        {#if !r.guest_id && r.pending_guest}<Badge variant="info">Tamu baru, menunggu persetujuan</Badge>{/if}
        {#if r.guests?.is_additional}<Badge variant="info">Tamu tambahan</Badge>{/if}
        {#if r.guests?.deleted_at}<Badge variant="muted">Tamu sudah dihapus</Badge>{/if}
      </span>
    </td>
    <td class="px-4 py-3">
      <span class="block text-ink-muted">{r.guests ? rsvpLabel(r.guests.rsvp_status, r.guests.rsvp_pax) : '—'}</span>
      <span class="tabular">Datang {formatNumber(r.actual_pax)} orang</span>
      {#if extra > 0}<span class="mt-1 block"><Badge variant="danger">Lebih {extra} dari tercatat</Badge></span>{/if}
    </td>
    <td class="px-4 py-3 font-mono whitespace-nowrap">
      {#if r.ticket_number}{r.ticket_number}{:else}<span title="Ditandai hadir oleh Admin, tanpa tiket">—</span><span
          class="sr-only">Ditandai hadir oleh Admin, tanpa tiket</span
        >{/if}
    </td>
    <td class="px-4 py-3">
      {#if badge.needsReview}<Badge variant="review">{badge.text}</Badge>
      {:else if badge.voided}<Badge variant="muted"><s>{badge.text}</s></Badge>
      {:else if r.status === 'accepted'}<Badge variant="ok">{badge.text}</Badge>
      {:else}<Badge>{badge.text}</Badge>{/if}
      {#if r.quarantine_reason}<span class="mt-1 block text-ink-muted"
          >{QUARANTINE_REASON_LABEL[r.quarantine_reason]}</span
        >{/if}
      {#if r.void_reason}<span class="mt-1 block max-w-48 text-ink-muted">{r.void_reason}</span>{/if}
    </td>
    <td class="px-4 py-3">
      {#if r.source === 'admin'}Admin{:else}{r.ushers?.name ?? '—'}{#if r.devices}<span class="text-ink-muted"
            >&nbsp;· {r.devices.code}</span
          >{/if}{/if}
      {#if r.source === 'outbox_upload'}<span class="block text-ink-muted">Unggahan outbox</span>{/if}
    </td>
    <td class="px-4 py-2">
      <div class="flex flex-wrap justify-end gap-1">
        {#if !r.voided_at && r.status === 'quarantined'}
          <Button
            size="sm"
            variant="secondary"
            disabled={busy}
            aria-label="Setujui {guestName(r)}"
            onclick={() => approve(r)}>Setujui</Button
          >
          <Button size="sm" variant="danger-ghost" aria-label="Tolak {guestName(r)}" onclick={() => open(r, 'reject')}
            >Tolak…</Button
          >
        {:else if !r.voided_at}
          {#if isReview(r.status) && !r.reviewed_at}
            <Button
              size="sm"
              variant="secondary"
              disabled={busy}
              aria-label="Tandai ditinjau {guestName(r)}"
              onclick={() =>
                run(() => supabase.rpc('admin_review_check_in', { p_check_in_id: r.id }), 'Ditandai sudah ditinjau.')}
              >Tandai ditinjau</Button
            >
          {/if}
          {#if r.status === 'conflict'}
            <Button size="sm" variant="ghost" aria-label="Ubah nomor {guestName(r)}" onclick={() => open(r, 'ticket')}
              >Ubah nomor…</Button
            >
          {/if}
          <Button
            size="sm"
            variant="ghost"
            disabled={busy}
            aria-label="{r.checked_out_at ? 'Batalkan keluar' : 'Tandai keluar'} {guestName(r)}"
            onclick={() =>
              run(
                () =>
                  supabase.rpc('admin_update_check_in', {
                    p_check_in_id: r.id,
                    p_patch: { checked_out_at: r.checked_out_at ? null : new Date().toISOString() },
                  }),
                r.checked_out_at ? 'Check-out dibatalkan.' : 'Check-out dicatat.',
              )}>{r.checked_out_at ? 'Batalkan keluar' : 'Tandai keluar'}</Button
          >
          <Button
            size="sm"
            variant="danger-ghost"
            aria-label="Batalkan check-in {guestName(r)}"
            onclick={() => open(r, 'void')}>Batalkan…</Button
          >
        {/if}
      </div>
    </td>
  </tr>
{/snippet}

{#snippet head()}
  <thead class="bg-surface text-ink-muted">
    <tr>
      <th scope="col" class="px-4 py-2.5 font-medium">Jam</th>
      <th scope="col" class="px-4 py-2.5 font-medium">Tamu</th>
      <th scope="col" class="px-4 py-2.5 font-medium">RSVP · aktual</th>
      <th scope="col" class="px-4 py-2.5 font-medium">Nomor</th>
      <th scope="col" class="px-4 py-2.5 font-medium">Status</th>
      <th scope="col" class="px-4 py-2.5 font-medium">Oleh</th>
      <th scope="col" class="px-4 py-2.5"><span class="sr-only">Aksi</span></th>
    </tr>
  </thead>
{/snippet}

<div class="mt-4">
  {#if data.rows.length === 0}
    <EmptyState title={data.filters.status || data.filters.q ? 'Tidak ada riwayat yang cocok.' : 'Belum ada check-in.'}>
      {#if data.filters.status === 'tinjau'}Tidak ada yang perlu ditinjau.{/if}
    </EmptyState>
  {:else if data.filters.status === 'karantina'}
    {#each groups as g (g.deviceId)}
      <section class="mb-6" aria-labelledby="group-{g.deviceId}">
        <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h3 id="group-{g.deviceId}" class="font-semibold">
            Perangkat <span class="font-mono">{g.code}</span>
            <span class="font-normal text-ink-muted">· {formatNumber(g.rows.length)} data di halaman ini</span>
          </h3>
          <div class="flex gap-2">
            <Button size="sm" variant="secondary" onclick={() => openDevice(g, 'approve')}
              >Setujui semua dari {g.code}</Button
            >
            <Button size="sm" variant="danger-ghost" onclick={() => openDevice(g, 'reject')}
              >Tolak semua dari {g.code}…</Button
            >
          </div>
        </div>
        <div class="overflow-x-auto rounded-dialog border border-line">
          <table class="w-full min-w-5xl text-left text-sm">
            {@render head()}
            <tbody class="divide-y divide-line">
              {#each g.rows as r (r.id)}{@render row(r)}{/each}
            </tbody>
          </table>
        </div>
      </section>
    {/each}
  {:else}
    <div class="overflow-x-auto rounded-dialog border border-line">
      <table class="w-full min-w-5xl text-left text-sm">
        {@render head()}
        <tbody class="divide-y divide-line">
          {#each data.rows as r (r.id)}{@render row(r)}{/each}
        </tbody>
      </table>
    </div>
  {/if}
  {#if data.total > HISTORY_PAGE_SIZE}
    <div class="mt-4">
      <Pagination
        total={data.total}
        page={data.filters.hal}
        perPage={HISTORY_PAGE_SIZE}
        onpage={(hal) => void goto(base + historySearch({ ...data.filters, hal }), { noScroll: true })}
      />
    </div>
  {/if}
</div>

<ConfirmDialog
  bind:open={voidOpen}
  title="Batalkan check-in {target ? guestName(target) : ''}?"
  confirmLabel="Batalkan check-in"
  reasonLabel="Alasan (wajib)"
  {busy}
  {error}
  onconfirm={(reason) =>
    void run(
      () => supabase.rpc('admin_void_check_in', { p_check_in_id: target!.id, p_reason: reason }),
      'Check-in dibatalkan.',
      () => (voidOpen = false),
    )}
>
  <p>Check-in tetap tersimpan sebagai Dibatalkan dan tidak lagi dihitung. Tindakan ini tercatat di audit log.</p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={rejectOpen}
  title="Tolak karantina {target ? guestName(target) : ''}?"
  confirmLabel="Tolak"
  reasonLabel="Alasan (wajib)"
  {busy}
  {error}
  onconfirm={(reason) =>
    void run(
      () =>
        supabase.rpc('admin_decide_quarantine', {
          p_event_id: data.event.id,
          p_decision: 'reject',
          p_ids: [target!.id],
          p_reason: reason,
        }),
      'Karantina ditolak.',
      () => (rejectOpen = false),
    )}
>
  <p>Data tetap tersimpan sebagai Dibatalkan dan tidak dihitung.</p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={approveAllOpen}
  title="Setujui semua karantina dari perangkat {device?.code ?? ''}?"
  confirmLabel="Setujui semua"
  variant="primary"
  {busy}
  {error}
  onconfirm={() =>
    void run(
      () =>
        supabase.rpc('admin_decide_quarantine', {
          p_event_id: data.event.id,
          p_decision: 'approve',
          p_device_id: device!.deviceId,
        }),
      `Semua karantina dari perangkat ${device?.code} disetujui.`,
      () => (approveAllOpen = false),
    )}
>
  <p>
    Termasuk data perangkat ini di halaman lain. Status setiap data dievaluasi ulang sekarang; tamu baru dibuat saat
    disetujui. Hasil Ganda atau Nomor bentrok tetap perlu ditinjau.
  </p>
</ConfirmDialog>

<ConfirmDialog
  bind:open={rejectAllOpen}
  title="Tolak semua karantina dari perangkat {device?.code ?? ''}?"
  confirmLabel="Tolak semua"
  reasonLabel="Alasan (wajib)"
  {busy}
  {error}
  onconfirm={(reason) =>
    void run(
      () =>
        supabase.rpc('admin_decide_quarantine', {
          p_event_id: data.event.id,
          p_decision: 'reject',
          p_device_id: device!.deviceId,
          p_reason: reason,
        }),
      `Semua karantina dari perangkat ${device?.code} ditolak.`,
      () => (rejectAllOpen = false),
    )}
>
  <p>Termasuk data perangkat ini di halaman lain. Data tetap tersimpan sebagai Dibatalkan.</p>
</ConfirmDialog>

<Dialog bind:open={ticketOpen} title="Ubah nomor tiket {target ? guestName(target) : ''}" size="sm">
  <form id="ticket-form" class="space-y-3" onsubmit={saveTicket} novalidate>
    {#if error}<p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-sm">
        {error}
      </p>{/if}
    <Field
      id="ticket-number"
      label="Nomor tiket"
      bind:value={ticket}
      maxlength={20}
      hint="Status Nomor bentrok dievaluasi ulang setelah disimpan."
    />
  </form>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (ticketOpen = false)} disabled={busy}>Batal</Button>
    <Button type="submit" form="ticket-form" {busy}>Simpan nomor</Button>
  {/snippet}
</Dialog>
