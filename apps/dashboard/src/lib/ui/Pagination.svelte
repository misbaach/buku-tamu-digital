<script lang="ts">
  import ChevronLeft from '@lucide/svelte/icons/chevron-left';
  import ChevronRight from '@lucide/svelte/icons/chevron-right';
  import { formatNumber } from '$lib/format';

  interface Props {
    total: number;
    page: number;
    perPage: number;
    onpage: (page: number) => void;
    onperpage?: (perPage: number) => void;
  }

  let { total, page, perPage, onpage, onperpage }: Props = $props();
  const uid = $props.id();
  const pages = $derived(Math.max(1, Math.ceil(total / perPage)));
  const from = $derived(total === 0 ? 0 : (page - 1) * perPage + 1);
  const to = $derived(Math.min(total, page * perPage));
</script>

<nav aria-label="Halaman tabel" class="flex flex-wrap items-center justify-between gap-3 text-sm">
  <p class="tabular text-ink-muted" aria-live="polite">
    {formatNumber(from)}–{formatNumber(to)} dari {formatNumber(total)}
  </p>
  <div class="flex items-center gap-3">
    {#if onperpage}
      <label for="{uid}-per" class="text-ink-muted">Baris per halaman</label>
      <select
        id="{uid}-per"
        class="h-8 cursor-pointer rounded-control border border-line-strong bg-bg px-2"
        value={String(perPage)}
        onchange={(e) => onperpage(Number(e.currentTarget.value))}
      >
        {#each [25, 50, 100] as n (n)}<option value={String(n)}>{n}</option>{/each}
      </select>
    {/if}
    <span class="tabular text-ink-muted">Hal. {page} dari {pages}</span>
    <div class="flex gap-1">
      <button
        type="button"
        class="grid size-8 cursor-pointer place-items-center rounded-control border border-line-strong bg-bg hover:bg-surface disabled:cursor-not-allowed disabled:opacity-40"
        disabled={page <= 1}
        aria-label="Halaman sebelumnya"
        onclick={() => onpage(page - 1)}><ChevronLeft size={16} aria-hidden="true" /></button
      >
      <button
        type="button"
        class="grid size-8 cursor-pointer place-items-center rounded-control border border-line-strong bg-bg hover:bg-surface disabled:cursor-not-allowed disabled:opacity-40"
        disabled={page >= pages}
        aria-label="Halaman berikutnya"
        onclick={() => onpage(page + 1)}><ChevronRight size={16} aria-hidden="true" /></button
      >
    </div>
  </div>
</nav>
