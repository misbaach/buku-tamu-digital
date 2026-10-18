<script lang="ts">
  import type { HTMLSelectAttributes } from 'svelte/elements';

  interface Props extends Omit<HTMLSelectAttributes, 'value'> {
    id: string;
    label: string;
    options: { value: string; label: string }[];
    value?: string;
    hint?: string;
    error?: string | null;
    /** Sembunyikan label secara visual (tetap terbaca pembaca layar), mis. di toolbar filter. */
    hideLabel?: boolean;
  }

  let {
    id,
    label,
    options,
    value = $bindable(''),
    hint,
    error = null,
    hideLabel = false,
    class: className = '',
    ...rest
  }: Props = $props();

  const hintId = $derived(`${id}-hint`);
  const errorId = $derived(`${id}-error`);
  const describedBy = $derived([hint && hintId, error && errorId].filter(Boolean).join(' ') || undefined);
</script>

<div class={['space-y-1.5', className]}>
  <label for={id} class={hideLabel ? 'sr-only' : 'block text-sm font-medium'}>{label}</label>
  <select
    {id}
    bind:value
    aria-invalid={error ? 'true' : undefined}
    aria-describedby={describedBy}
    class={[
      'block h-10 w-full cursor-pointer rounded-control border bg-bg px-2.5 text-base text-ink',
      error ? 'border-danger' : 'border-line-strong',
    ]}
    {...rest}
  >
    {#each options as option (option.value)}
      <option value={option.value}>{option.label}</option>
    {/each}
  </select>
  {#if hint}
    <p id={hintId} class="text-sm text-ink-muted">{hint}</p>
  {/if}
  {#if error}
    <p id={errorId} class="text-sm text-danger">{error}</p>
  {/if}
</div>
