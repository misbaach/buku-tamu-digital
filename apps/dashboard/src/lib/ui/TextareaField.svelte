<script lang="ts">
  import type { HTMLTextareaAttributes } from 'svelte/elements';

  interface Props extends Omit<HTMLTextareaAttributes, 'value'> {
    id: string;
    label: string;
    value?: string;
    hint?: string;
    error?: string | null;
  }

  let { id, label, value = $bindable(''), hint, error = null, class: className = '', ...rest }: Props = $props();
  const hintId = $derived(`${id}-hint`);
  const errorId = $derived(`${id}-error`);
  const describedBy = $derived([hint && hintId, error && errorId].filter(Boolean).join(' ') || undefined);
</script>

<div class={['space-y-1.5', className]}>
  <label for={id} class="block text-sm font-medium">{label}</label>
  <textarea
    {id}
    bind:value
    aria-invalid={error ? 'true' : undefined}
    aria-describedby={describedBy}
    class={[
      'block w-full rounded-control border bg-bg px-3 py-2 text-base text-ink',
      error ? 'border-danger' : 'border-line-strong',
    ]}
    {...rest}></textarea>
  {#if hint}
    <p id={hintId} class="text-sm text-ink-muted">{hint}</p>
  {/if}
  {#if error}
    <p id={errorId} class="text-sm text-danger">{error}</p>
  {/if}
</div>
