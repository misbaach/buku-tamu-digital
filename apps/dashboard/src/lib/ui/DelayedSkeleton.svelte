<script lang="ts">
  import type { Snippet } from 'svelte';

  // Skeleton baru tampil bila memuat lebih lama dari `delay`, supaya tampilan tidak berkedip saat cepat.
  let { delay = 300, label = 'Memuat…', children }: { delay?: number; label?: string; children: Snippet } = $props();
  let visible = $state(false);

  $effect(() => {
    const timer = setTimeout(() => (visible = true), delay);
    return () => clearTimeout(timer);
  });
</script>

<div aria-busy="true" aria-live="polite">
  <span class="sr-only">{label}</span>
  {#if visible}
    <div aria-hidden="true">{@render children()}</div>
  {/if}
</div>
