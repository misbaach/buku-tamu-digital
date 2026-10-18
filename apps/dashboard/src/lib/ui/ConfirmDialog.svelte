<script lang="ts">
  import type { Snippet } from 'svelte';
  import Button from './Button.svelte';
  import Dialog from './Dialog.svelte';

  // Konfirmasi aksi berbahaya: judul menyebut objeknya, tombol menyebut aksinya, alasan bisa diwajibkan.
  interface Props {
    open: boolean;
    title: string;
    confirmLabel: string;
    variant?: 'danger' | 'primary';
    /** Bila diisi, alasan wajib diketik sebelum tombol aktif (mis. undo, putus total). */
    reasonLabel?: string;
    busy?: boolean;
    error?: string | null;
    onconfirm: (reason: string) => void | Promise<void>;
    children: Snippet;
  }

  let {
    open = $bindable(false),
    title,
    confirmLabel,
    variant = 'danger',
    reasonLabel,
    busy = false,
    error = null,
    onconfirm,
    children,
  }: Props = $props();
  const uid = $props.id();
  let reason = $state('');

  $effect(() => {
    if (!open) reason = '';
  });
</script>

<Dialog bind:open {title} size="sm">
  <div class="space-y-3 text-[0.9375rem]">
    {@render children()}
    {#if reasonLabel}
      <div class="space-y-1.5">
        <label for="{uid}-reason" class="block text-sm font-medium">{reasonLabel}</label>
        <textarea
          id="{uid}-reason"
          bind:value={reason}
          rows="2"
          maxlength="300"
          class="block w-full rounded-control border border-line-strong bg-bg px-3 py-2 text-base"></textarea>
      </div>
    {/if}
    {#if error}
      <p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-sm">{error}</p>
    {/if}
  </div>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (open = false)} disabled={busy}>Batal</Button>
    <Button
      {variant}
      {busy}
      disabled={!!reasonLabel && reason.trim().length === 0}
      onclick={() => onconfirm(reason.trim())}
    >
      {busy ? 'Memproses…' : confirmLabel}
    </Button>
  {/snippet}
</Dialog>
