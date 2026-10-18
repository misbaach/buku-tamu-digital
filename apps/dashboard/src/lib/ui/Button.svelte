<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';

  type Variant = 'primary' | 'secondary' | 'danger' | 'ghost';

  interface Props extends HTMLButtonAttributes {
    variant?: Variant;
    size?: 'sm' | 'md';
    /** Sedang memproses: tombol dinonaktifkan dan diumumkan sebagai sibuk. */
    busy?: boolean;
    full?: boolean;
    children: Snippet;
  }

  let {
    variant = 'primary',
    size = 'md',
    busy = false,
    full = false,
    type = 'button',
    disabled,
    class: className = '',
    children,
    ...rest
  }: Props = $props();

  const variants: Record<Variant, string> = {
    primary: 'bg-primary text-on-primary hover:bg-ink/85',
    secondary: 'border border-line-strong bg-bg text-ink hover:bg-surface',
    danger: 'bg-danger text-on-primary hover:bg-danger/90',
    ghost: 'text-ink hover:bg-surface-2',
  };
  const sizes = { sm: 'h-8 px-3 text-sm', md: 'h-10 px-4 text-[0.9375rem]' };
</script>

<button
  {type}
  disabled={disabled || busy}
  aria-busy={busy || undefined}
  class={[
    'inline-flex cursor-pointer items-center justify-center gap-2 rounded-control font-medium whitespace-nowrap',
    'transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-60',
    variants[variant],
    sizes[size],
    full && 'w-full',
    className,
  ]}
  {...rest}
>
  {@render children()}
</button>
