<script lang="ts">
  import type { Snippet } from 'svelte';
  import X from '@lucide/svelte/icons/x';

  // Dialog modal native: fokus terjebak di dalam, latar inert, Esc menutup, fokus kembali ke pemicu.
  interface Props {
    open: boolean;
    title: string;
    description?: string;
    size?: 'sm' | 'md' | 'lg' | 'xl';
    onclose?: () => void;
    /** false: tidak bisa ditutup lewat Esc atau tombol X (mis. PIN yang harus dicatat dulu). */
    dismissible?: boolean;
    children: Snippet;
    footer?: Snippet;
  }

  let {
    open = $bindable(false),
    title,
    description,
    size = 'md',
    onclose,
    dismissible = true,
    children,
    footer,
  }: Props = $props();
  const uid = $props.id();
  let el = $state<HTMLDialogElement>();

  const widths = { sm: 'max-w-md', md: 'max-w-xl', lg: 'max-w-3xl', xl: 'max-w-5xl' };

  $effect(() => {
    if (!el) return;
    if (open && !el.open) el.showModal();
    else if (!open && el.open) el.close();
  });
</script>

<dialog
  bind:this={el}
  aria-labelledby="{uid}-title"
  aria-describedby={description ? `${uid}-desc` : undefined}
  oncancel={(e) => {
    if (!dismissible) e.preventDefault();
  }}
  onclose={() => {
    open = false;
    onclose?.();
  }}
  class={[
    'm-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] flex-col overflow-hidden rounded-dialog border border-line bg-bg p-0 text-ink shadow-xl open:flex',
    'backdrop:bg-ink/45',
    widths[size],
  ]}
>
  <header class="flex items-start justify-between gap-4 border-b border-line px-5 py-4">
    <div class="min-w-0">
      <h2 id="{uid}-title" class="text-lg font-semibold">{title}</h2>
      {#if description}
        <p id="{uid}-desc" class="mt-0.5 text-sm text-ink-muted">{description}</p>
      {/if}
    </div>
    {#if dismissible}<button
        type="button"
        class="-mr-1 grid size-8 shrink-0 cursor-pointer place-items-center rounded-control text-ink-muted hover:bg-surface-2 hover:text-ink"
        aria-label="Tutup"
        onclick={() => (open = false)}
      >
        <X size={18} aria-hidden="true" />
      </button>{/if}
  </header>
  <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4">
    {@render children()}
  </div>
  {#if footer}
    <footer class="flex flex-wrap justify-end gap-2 border-t border-line bg-surface px-5 py-3">
      {@render footer()}
    </footer>
  {/if}
</dialog>
