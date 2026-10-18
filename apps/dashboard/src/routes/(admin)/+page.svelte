<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { formatEventDate } from '$lib/format';
  import Button from '$lib/ui/Button.svelte';
  import DelayedSkeleton from '$lib/ui/DelayedSkeleton.svelte';

  let { data } = $props();
</script>

<svelte:head>
  <title>Acara · Buku Tamu Digital</title>
</svelte:head>

<h1 class="text-2xl font-semibold">Acara</h1>
<p class="mt-1 text-ink-muted">Acara tempat Anda terdaftar sebagai Admin.</p>

<div class="mt-6">
  {#await data.events}
    <DelayedSkeleton label="Memuat daftar acara…">
      <div class="divide-y divide-line rounded-dialog border border-line">
        {#each [1, 2, 3] as row (row)}
          <div class="flex h-12 items-center gap-6 px-4">
            <div class="h-3 w-48 rounded-control bg-surface-2"></div>
            <div class="h-3 w-24 rounded-control bg-surface-2"></div>
          </div>
        {/each}
      </div>
    </DelayedSkeleton>
  {:then events}
    {#if events.length === 0}
      <div class="rounded-dialog border border-line px-6 py-10">
        <p class="font-medium">Belum ada acara.</p>
        <p class="mt-1 text-ink-muted">Anda belum terdaftar sebagai Admin di acara mana pun.</p>
      </div>
    {:else}
      <div class="overflow-x-auto rounded-dialog border border-line">
        <table class="w-full min-w-xl text-left text-sm">
          <thead class="bg-surface text-ink-muted">
            <tr>
              <th scope="col" class="px-4 py-2.5 font-medium">Nama acara</th>
              <th scope="col" class="px-4 py-2.5 font-medium">Tanggal</th>
              <th scope="col" class="px-4 py-2.5 font-medium">Kode Acara</th>
              <th scope="col" class="px-4 py-2.5 font-medium">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-line">
            {#each events as event (event.id)}
              <tr>
                <td class="px-4 py-3 font-medium">{event.name}</td>
                <td class="tabular px-4 py-3">{formatEventDate(event.event_date)}</td>
                <td class="px-4 py-3 font-mono tracking-wider">{event.code}</td>
                <td class="px-4 py-3">{event.archived_at ? 'Diarsipkan' : 'Aktif'}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {:catch}
    <div class="rounded-dialog border border-danger bg-danger-bg px-6 py-6" role="alert">
      <p class="font-medium">Daftar acara gagal dimuat.</p>
      <p class="mt-1 text-sm">Periksa koneksi internet, lalu coba lagi.</p>
      <Button variant="secondary" size="sm" class="mt-4" onclick={() => invalidateAll()}>Coba lagi</Button>
    </div>
  {/await}
</div>
