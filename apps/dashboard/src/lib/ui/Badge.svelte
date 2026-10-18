<script lang="ts">
  import type { Snippet } from 'svelte';
  import TriangleAlert from '@lucide/svelte/icons/triangle-alert';

  // Warna selalu disertai teks. Varian `review` dipakai identik untuk semua status "— tinjau" (prd.md bagian 5).
  type Variant = 'neutral' | 'ok' | 'review' | 'danger' | 'info' | 'muted';
  let { variant = 'neutral', children }: { variant?: Variant; children: Snippet } = $props();

  const styles: Record<Variant, string> = {
    neutral: 'border-line-strong bg-bg text-ink',
    ok: 'border-ok/40 bg-ok-bg text-ok',
    review: 'border-warn bg-warn-bg text-warn font-semibold',
    danger: 'border-danger/40 bg-danger-bg text-danger',
    info: 'border-info/40 bg-info-bg text-info',
    muted: 'border-line bg-surface text-ink-muted',
  };
</script>

<span
  class={[
    'inline-flex items-center gap-1 rounded-control border px-1.5 py-0.5 text-xs leading-4 whitespace-nowrap',
    styles[variant],
  ]}
>
  {#if variant === 'review'}<TriangleAlert size={12} aria-hidden="true" />{/if}
  {@render children()}
</span>
