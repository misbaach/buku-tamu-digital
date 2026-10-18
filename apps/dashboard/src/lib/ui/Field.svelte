<script lang="ts">
  import type { HTMLInputAttributes } from 'svelte/elements';

  interface Props extends Omit<HTMLInputAttributes, 'value'> {
    id: string;
    label: string;
    hint?: string;
    error?: string | null;
    value?: string;
  }

  let { id, label, hint, error = null, value = $bindable(''), class: className = '', ...rest }: Props = $props();

  const hintId = $derived(`${id}-hint`);
  const errorId = $derived(`${id}-error`);
  const describedBy = $derived([hint && hintId, error && errorId].filter(Boolean).join(' ') || undefined);
</script>

<div class={['space-y-1.5', className]}>
  <label for={id} class="block text-sm font-medium">{label}</label>
  <input
    {id}
    bind:value
    aria-invalid={error ? 'true' : undefined}
    aria-describedby={describedBy}
    class={[
      'block h-10 w-full rounded-control border bg-bg px-3 text-base text-ink',
      'placeholder:text-ink-muted focus-visible:border-focus',
      error ? 'border-danger' : 'border-line-strong',
    ]}
    {...rest}
  />
  {#if hint}
    <p id={hintId} class="text-sm text-ink-muted">{hint}</p>
  {/if}
  {#if error}
    <p id={errorId} class="text-sm text-danger">{error}</p>
  {/if}
</div>
