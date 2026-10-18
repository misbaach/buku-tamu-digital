<script lang="ts">
  import { goto, invalidate } from '$app/navigation';
  import { resolve } from '$app/paths';
  import Plus from '@lucide/svelte/icons/plus';
  import Search from '@lucide/svelte/icons/search';
  import Upload from '@lucide/svelte/icons/upload';
  import { SvelteSet } from 'svelte/reactivity';
  import { ATTENDANCE_LABEL, CATEGORY_LABEL, rsvpLabel } from '@guestbook/shared';
  import AttendanceLimitForm from '$lib/features/guests/AttendanceLimitForm.svelte';
  import BulkBar from '$lib/features/guests/BulkBar.svelte';
  import GuestDialog from '$lib/features/guests/GuestDialog.svelte';
  import { filtersToSearch, hasActiveFilters, type GuestFilters, type GuestListRow } from '$lib/features/guests/query';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import CategoryIcon from '$lib/ui/CategoryIcon.svelte';
  import DelayedSkeleton from '$lib/ui/DelayedSkeleton.svelte';
  import EmptyState from '$lib/ui/EmptyState.svelte';
  import LinkButton from '$lib/ui/LinkButton.svelte';
  import Pagination from '$lib/ui/Pagination.svelte';

  let { data } = $props();
  const eventId = $derived(data.event.id);
  const basePath = $derived(resolve(`/acara/${data.event.id}/tamu`));

  // Ikut URL saat filter berubah; ditimpa ketikan pengguna sampai navigasi berikutnya.
  let search = $derived(data.filters.q);

  const selected = new SvelteSet<string>();
  let dialogOpen = $state(false);
  let dialogGuest = $state<GuestListRow | null>(null);
  let dialogTab = $state<'data' | 'kehadiran' | 'qr'>('data');

  function navigate(patch: Partial<GuestFilters>) {
    selected.clear();
    const next = { ...data.filters, ...patch };
    // eslint-disable-next-line svelte/no-navigation-without-resolve -- basePath sudah lewat resolve()
    void goto(basePath + filtersToSearch(next), { keepFocus: true, noScroll: true });
  }

  let searchTimer: ReturnType<typeof setTimeout> | undefined;
  function onSearchInput() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => navigate({ q: search.trim(), hal: 1 }), 300);
  }

  function openGuest(guest: GuestListRow | null, tab: 'data' | 'kehadiran' | 'qr' = 'data') {
    dialogGuest = guest;
    dialogTab = tab;
    dialogOpen = true;
  }

  function refresh() {
    selected.clear();
    void invalidate('app:guests');
  }

  const filterSelect =
    'h-10 cursor-pointer rounded-control border border-line-strong bg-bg px-2.5 text-[0.9375rem] text-ink';
</script>

<svelte:head>
  <title>Tamu · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Tamu</h2>
    <p class="mt-1 text-sm text-ink-muted">Daftar tamu undangan dan tamu tambahan acara ini.</p>
  </div>
  <div class="flex flex-wrap gap-2">
    <LinkButton href={resolve(`/acara/${data.event.id}/tamu/impor`)}>
      <Upload size={16} aria-hidden="true" />Impor dari Excel/CSV
    </LinkButton>
    <Button onclick={() => openGuest(null)}><Plus size={16} aria-hidden="true" />Tambah tamu</Button>
  </div>
</div>

<div class="mt-5 rounded-dialog border border-line bg-surface px-4 py-2.5">
  <AttendanceLimitForm eventId={data.event.id} limit={data.event.attendance_limit} />
</div>

<form role="search" class="mt-5 flex flex-wrap items-end gap-3" onsubmit={(e) => e.preventDefault()}>
  <div class="relative min-w-56 flex-1">
    <label for="guest-search" class="sr-only">Cari nama atau Nomor Urut</label>
    <Search size={16} class="pointer-events-none absolute top-3 left-3 text-ink-muted" aria-hidden="true" />
    <input
      id="guest-search"
      type="search"
      placeholder="Cari nama atau Nomor Urut"
      bind:value={search}
      oninput={onSearchInput}
      class="h-10 w-full rounded-control border border-line-strong bg-bg pr-3 pl-9 text-base"
      autocomplete="off"
    />
  </div>
  <label class="sr-only" for="filter-kategori">Kategori</label>
  <select
    id="filter-kategori"
    class={filterSelect}
    value={data.filters.kategori}
    onchange={(e) => navigate({ kategori: e.currentTarget.value as GuestFilters['kategori'], hal: 1 })}
  >
    <option value="">Semua kategori</option>
    <option value="regular">{CATEGORY_LABEL.regular}</option>
    <option value="vip">{CATEGORY_LABEL.vip}</option>
    <option value="vvip">{CATEGORY_LABEL.vvip}</option>
  </select>
  <label class="sr-only" for="filter-grup">Grup</label>
  <select
    id="filter-grup"
    class={filterSelect}
    value={data.filters.grup}
    onchange={(e) => navigate({ grup: e.currentTarget.value, hal: 1 })}
  >
    <option value="">Semua grup</option>
    <option value="tanpa">Tanpa grup</option>
    {#each data.groups as g (g.id)}<option value={g.id}>{g.name}</option>{/each}
  </select>
  <label class="sr-only" for="filter-rsvp">Status RSVP</label>
  <select
    id="filter-rsvp"
    class={filterSelect}
    value={data.filters.rsvp}
    onchange={(e) => navigate({ rsvp: e.currentTarget.value as GuestFilters['rsvp'], hal: 1 })}
  >
    <option value="">Semua RSVP</option>
    <option value="going">Akan hadir</option>
    <option value="not_going">Tidak hadir</option>
    <option value="unconfirmed">Belum konfirmasi</option>
  </select>
  <label class="sr-only" for="filter-hadir">Kehadiran</label>
  <select
    id="filter-hadir"
    class={filterSelect}
    value={data.filters.hadir}
    onchange={(e) => navigate({ hadir: e.currentTarget.value as GuestFilters['hadir'], hal: 1 })}
  >
    <option value="">Semua kehadiran</option>
    <option value="hadir">Hadir</option>
    <option value="belum">Belum hadir</option>
    <option value="keluar">Sudah keluar</option>
  </select>
  {#if hasActiveFilters(data.filters)}
    <Button
      variant="ghost"
      onclick={() => {
        search = '';
        navigate({ q: '', kategori: '', grup: '', rsvp: '', hadir: '', hal: 1 });
      }}>Hapus filter</Button
    >
  {/if}
</form>

<div class="mt-4">
  {#await data.result}
    <DelayedSkeleton label="Memuat daftar tamu…">
      <div class="divide-y divide-line rounded-dialog border border-line">
        {#each [1, 2, 3, 4, 5, 6] as row (row)}
          <div class="flex h-12 items-center gap-6 px-4">
            <div class="h-3 w-4 rounded-control bg-surface-2"></div>
            <div class="h-3 w-56 rounded-control bg-surface-2"></div>
            <div class="h-3 w-20 rounded-control bg-surface-2"></div>
          </div>
        {/each}
      </div>
    </DelayedSkeleton>
  {:then result}
    {@const allOnPage = result.rows.length > 0 && result.rows.every((r) => selected.has(r.id))}
    {@const someOnPage = result.rows.some((r) => selected.has(r.id))}
    {#if result.total === 0 && !hasActiveFilters(data.filters)}
      <EmptyState title="Belum ada tamu.">
        Tambahkan tamu satu per satu, atau impor sekaligus dari berkas Excel/CSV.
        {#snippet actions()}
          <Button onclick={() => openGuest(null)}><Plus size={16} aria-hidden="true" />Tambah tamu</Button>
          <LinkButton href={resolve(`/acara/${data.event.id}/tamu/impor`)}>Impor dari Excel/CSV</LinkButton>
        {/snippet}
      </EmptyState>
    {:else if result.total === 0}
      <EmptyState title="Tidak ada tamu yang cocok.">Ubah kata kunci atau hapus filter.</EmptyState>
    {:else}
      <div class="overflow-x-auto rounded-dialog border border-line">
        <table class="w-full min-w-4xl text-left text-sm">
          <caption class="sr-only">Daftar tamu, {formatNumber(result.total)} hasil</caption>
          <thead class="bg-surface text-ink-muted">
            <tr>
              <th scope="col" class="w-10 px-4 py-2.5">
                <input
                  type="checkbox"
                  class="size-4 cursor-pointer accent-ink"
                  aria-label="Pilih semua tamu di halaman ini"
                  checked={allOnPage}
                  indeterminate={someOnPage && !allOnPage}
                  onchange={(e) => {
                    for (const r of result.rows) {
                      if (e.currentTarget.checked) selected.add(r.id);
                      else selected.delete(r.id);
                    }
                  }}
                />
              </th>
              <th scope="col" class="px-3 py-2.5 font-medium">Nama</th>
              <th scope="col" class="px-3 py-2.5 font-medium">Kategori</th>
              <th scope="col" class="px-3 py-2.5 font-medium">Grup</th>
              <th scope="col" class="px-3 py-2.5 text-right font-medium">Undangan</th>
              <th scope="col" class="px-3 py-2.5 font-medium">RSVP</th>
              <th scope="col" class="px-3 py-2.5 font-medium">Kehadiran</th>
              <th scope="col" class="px-3 py-2.5 font-medium">Nomor Urut</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each result.rows as guest (guest.id)}
              <tr class={selected.has(guest.id) ? 'bg-surface' : 'hover:bg-surface'}>
                <td class="px-4 py-2.5">
                  <input
                    type="checkbox"
                    class="size-4 cursor-pointer accent-ink"
                    aria-label="Pilih {guest.name}"
                    checked={selected.has(guest.id)}
                    onchange={(e) => (e.currentTarget.checked ? selected.add(guest.id) : selected.delete(guest.id))}
                  />
                </td>
                <td class="px-3 py-2.5">
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      class="cursor-pointer text-left font-medium underline-offset-2 hover:underline"
                      onclick={() => openGuest(guest)}>{guest.name}</button
                    >
                    {#if guest.is_additional}<Badge variant="info">Tambahan</Badge>{/if}
                  </div>
                </td>
                <td class="px-3 py-2.5">
                  <span class="inline-flex items-center gap-1.5"
                    ><CategoryIcon category={guest.category} withText />{CATEGORY_LABEL[guest.category]}</span
                  >
                </td>
                <td class="px-3 py-2.5 text-ink-muted">{guest.guest_groups?.name ?? '—'}</td>
                <td class="tabular px-3 py-2.5 text-right">{guest.invited_pax}</td>
                <td class="px-3 py-2.5">{rsvpLabel(guest.rsvp_status, guest.rsvp_pax)}</td>
                <td class="px-3 py-2.5">
                  {#if guest.attendance_status === 'not_arrived'}
                    <span class="text-ink-muted">{ATTENDANCE_LABEL.not_arrived}</span>
                  {:else}
                    <button
                      type="button"
                      class="cursor-pointer underline-offset-2 hover:underline"
                      onclick={() => openGuest(guest, 'kehadiran')}
                    >
                      <Badge variant="ok">{ATTENDANCE_LABEL[guest.attendance_status]}</Badge>
                      {#if guest.attendance_status === 'checked_out'}<span class="ml-1 text-ink-muted">keluar</span
                        >{/if}
                    </button>
                  {/if}
                </td>
                <td class="px-3 py-2.5 font-mono">{guest.special_number ?? ''}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
      <div class="mt-3">
        <Pagination
          total={result.total}
          page={data.filters.hal}
          perPage={data.filters.per}
          onpage={(hal) => navigate({ hal })}
          onperpage={(per) => navigate({ per, hal: 1 })}
        />
      </div>
    {/if}
  {:catch error}
    <div class="rounded-dialog border border-danger bg-danger-bg px-6 py-6" role="alert">
      <p class="font-medium">Daftar tamu gagal dimuat.</p>
      <p class="mt-1 text-sm">{dbErrorMessage(error)}</p>
      <Button variant="secondary" size="sm" class="mt-4" onclick={refresh}>Coba lagi</Button>
    </div>
  {/await}
</div>

{#if selected.size > 0}
  <BulkBar {eventId} ids={[...selected]} groups={data.groups} onchanged={refresh} onclear={() => selected.clear()} />
{/if}

<GuestDialog
  bind:open={dialogOpen}
  {eventId}
  guest={dialogGuest}
  groups={data.groups}
  initialTab={dialogTab}
  onchanged={() => void invalidate('app:guests')}
/>
