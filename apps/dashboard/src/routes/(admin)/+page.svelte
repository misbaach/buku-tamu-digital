<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import { resolve } from '$app/paths';
  import Plus from '@lucide/svelte/icons/plus';
  import CreateEventDialog from '$lib/features/events/CreateEventDialog.svelte';
  import { formatEventDate } from '$lib/format';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import DelayedSkeleton from '$lib/ui/DelayedSkeleton.svelte';
  import EmptyState from '$lib/ui/EmptyState.svelte';

  let { data } = $props();
  let creating = $state(false);
</script>

<svelte:head>
  <title>Acara · Buku Tamu Digital</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h1 class="text-2xl font-semibold">Acara</h1>
    <p class="mt-1 text-ink-muted">Acara tempat Anda terdaftar sebagai Admin.</p>
  </div>
  <Button onclick={() => (creating = true)}><Plus size={16} aria-hidden="true" />Buat acara</Button>
</div>

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
      <EmptyState title="Belum ada acara.">
        Buat acara pertama untuk mulai menambah tamu dan penerima tamu.
        {#snippet actions()}
          <Button onclick={() => (creating = true)}><Plus size={16} aria-hidden="true" />Buat acara</Button>
        {/snippet}
      </EmptyState>
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
              <tr class="hover:bg-surface">
                <td class="px-4 py-3">
                  <a href={resolve(`/acara/${event.id}/tamu`)} class="font-medium underline-offset-2 hover:underline">
                    {event.name}
                  </a>
                </td>
                <td class="tabular px-4 py-3">{formatEventDate(event.event_date)}</td>
                <td class="px-4 py-3 font-mono tracking-wider">{event.code}</td>
                <td class="px-4 py-3">
                  {#if event.archived_at}<Badge variant="muted">Diarsipkan</Badge>{:else}<Badge variant="ok"
                      >Aktif</Badge
                    >{/if}
                </td>
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

<CreateEventDialog bind:open={creating} />
