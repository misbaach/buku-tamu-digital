<script lang="ts">
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import ArrowLeft from '@lucide/svelte/icons/arrow-left';
  import { formatEventDate } from '$lib/format';
  import Badge from '$lib/ui/Badge.svelte';

  let { data, children } = $props();

  const links = $derived([
    { path: `/acara/${data.event.id}/tamu`, label: 'Tamu' },
    { path: `/acara/${data.event.id}/grup`, label: 'Grup' },
    { path: `/acara/${data.event.id}/nomor-urut`, label: 'Nomor Urut' },
    { path: `/acara/${data.event.id}/penerima-tamu`, label: 'Penerima Tamu' },
    { path: `/acara/${data.event.id}/sapaan`, label: 'Sapaan' },
    { path: `/acara/${data.event.id}/pengaturan`, label: 'Pengaturan' },
  ] as const);
</script>

<div class="border-b border-line">
  <a href={resolve('/')} class="inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink">
    <ArrowLeft size={14} aria-hidden="true" />Semua acara
  </a>
  <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
    <h1 class="text-2xl font-semibold">{data.event.name}</h1>
    {#if data.event.archived_at}<Badge variant="muted">Diarsipkan</Badge>{/if}
  </div>
  <p class="mt-1 text-sm text-ink-muted">
    <span class="tabular">{formatEventDate(data.event.event_date)}</span>
    · Kode Acara <span class="font-mono font-medium tracking-wider text-ink">{data.event.code}</span>
  </p>
  <nav aria-label="Menu acara" class="mt-4 -mb-px flex gap-1 overflow-x-auto">
    {#each links as link (link.path)}
      {@const current = page.url.pathname.startsWith(resolve(link.path))}
      <a
        href={resolve(link.path)}
        aria-current={current ? 'page' : undefined}
        class={[
          'border-b-2 px-3 py-2 text-sm font-medium whitespace-nowrap',
          current ? 'border-ink text-ink' : 'border-transparent text-ink-muted hover:text-ink',
        ]}>{link.label}</a
      >
    {/each}
  </nav>
</div>

<div class="pt-6">
  {@render children()}
</div>
