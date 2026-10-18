<script lang="ts">
  import CircleCheck from '@lucide/svelte/icons/circle-check';
  import CircleAlert from '@lucide/svelte/icons/circle-alert';
  import X from '@lucide/svelte/icons/x';
  import { dismiss, toasts } from '$lib/toast.svelte';
</script>

<!-- Region live selalu ada di DOM agar pembaca layar mengumumkan pesan yang masuk. -->
<div class="pointer-events-none fixed right-4 bottom-4 z-50 flex w-[min(24rem,calc(100%-2rem))] flex-col gap-2">
  <div role="status" aria-live="polite" class="contents">
    {#each toasts.filter((t) => t.kind === 'success') as t (t.id)}
      {@render item(t.id, t.message, false)}
    {/each}
  </div>
  <div role="alert" aria-live="assertive" class="contents">
    {#each toasts.filter((t) => t.kind === 'error') as t (t.id)}
      {@render item(t.id, t.message, true)}
    {/each}
  </div>
</div>

{#snippet item(id: number, message: string, error: boolean)}
  <div
    class={[
      'pointer-events-auto flex items-start gap-2 rounded-control border bg-bg px-3 py-2.5 text-sm shadow-lg',
      error ? 'border-danger' : 'border-line-strong',
    ]}
  >
    {#if error}
      <CircleAlert size={18} class="mt-px shrink-0 text-danger" aria-hidden="true" />
    {:else}
      <CircleCheck size={18} class="mt-px shrink-0 text-ok" aria-hidden="true" />
    {/if}
    <p class="min-w-0 flex-1">{message}</p>
    <button
      type="button"
      class="-m-1 grid size-6 shrink-0 cursor-pointer place-items-center rounded-control text-ink-muted hover:text-ink"
      aria-label="Tutup pesan"
      onclick={() => dismiss(id)}
    >
      <X size={14} aria-hidden="true" />
    </button>
  </div>
{/snippet}
