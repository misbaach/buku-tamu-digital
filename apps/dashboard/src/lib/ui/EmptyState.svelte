<script lang="ts">
  import type { Snippet } from 'svelte';

  let { title, children, actions }: { title: string; children?: Snippet; actions?: Snippet } = $props();
</script>

<div class="rounded-dialog border border-line px-6 py-10">
  <p class="font-medium">{title}</p>
  {#if children}<div class="mt-1 text-ink-muted">{@render children()}</div>{/if}
  {#if actions}<div class="mt-4 flex flex-wrap gap-2">{@render actions()}</div>{/if}
</div>
