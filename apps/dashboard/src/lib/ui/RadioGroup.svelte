<script lang="ts" generics="T extends string">
  import type { Snippet } from 'svelte';

  // Pilihan tunggal sebagai tombol bersegmen (radio native: panah atas/bawah bawaan browser).
  interface Props {
    name: string;
    legend: string;
    options: { value: T; label: string }[];
    value: T;
    error?: string | null;
    icon?: Snippet<[T]>;
  }

  let { name, legend, options, value = $bindable(), error = null, icon }: Props = $props();
  const uid = $props.id();
</script>

<fieldset aria-describedby={error ? `${uid}-error` : undefined}>
  <legend class="mb-1.5 text-sm font-medium">{legend}</legend>
  <div class="flex flex-wrap gap-2">
    {#each options as option (option.value)}
      <label
        class={[
          'inline-flex h-10 cursor-pointer items-center gap-2 rounded-control border px-3 text-[0.9375rem]',
          'has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-focus',
          value === option.value
            ? 'border-ink bg-ink text-on-primary'
            : 'border-line-strong bg-bg text-ink hover:bg-surface',
        ]}
      >
        <input class="sr-only" type="radio" {name} value={option.value} bind:group={value} />
        {#if icon}{@render icon(option.value)}{/if}
        {option.label}
      </label>
    {/each}
  </div>
  {#if error}
    <p id="{uid}-error" class="mt-1.5 text-sm text-danger">{error}</p>
  {/if}
</fieldset>
