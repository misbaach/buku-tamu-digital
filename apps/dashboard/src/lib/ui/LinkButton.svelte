<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLAnchorAttributes } from 'svelte/elements';

  // Tautan bergaya tombol (navigasi), agar tetap bisa dibuka di tab baru dan dibaca sebagai tautan.
  interface Props extends HTMLAnchorAttributes {
    variant?: 'primary' | 'secondary';
    size?: 'sm' | 'md';
    children: Snippet;
  }

  let { variant = 'secondary', size = 'md', class: className = '', children, ...rest }: Props = $props();
</script>

<a
  class={[
    'inline-flex items-center justify-center gap-2 rounded-control font-medium whitespace-nowrap transition-colors duration-150',
    variant === 'primary'
      ? 'bg-primary text-on-primary hover:bg-ink/85'
      : 'border border-line-strong bg-bg text-ink hover:bg-surface',
    size === 'sm' ? 'h-8 px-3 text-sm' : 'h-10 px-4 text-[0.9375rem]',
    className,
  ]}
  {...rest}
>
  {@render children()}
</a>
