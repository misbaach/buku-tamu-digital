<script lang="ts">
  // Saklar on/off: checkbox native dengan role="switch" (Spasi untuk mengubah, dibaca "aktif/nonaktif").
  interface Props {
    id: string;
    label: string;
    description?: string;
    checked: boolean;
    disabled?: boolean;
  }

  let { id, label, description, checked = $bindable(false), disabled = false }: Props = $props();
</script>

<div class="flex items-start justify-between gap-6 py-3">
  <div class="min-w-0">
    <label for={id} class="block font-medium">{label}</label>
    {#if description}<p id="{id}-desc" class="mt-0.5 text-sm text-ink-muted">{description}</p>{/if}
  </div>
  <input
    {id}
    type="checkbox"
    role="switch"
    bind:checked
    {disabled}
    aria-describedby={description ? `${id}-desc` : undefined}
    class={[
      'relative mt-0.5 h-6 w-11 shrink-0 cursor-pointer appearance-none rounded-full border transition-colors duration-150',
      'border-line-strong bg-surface-2 checked:border-ink checked:bg-ink disabled:cursor-not-allowed disabled:opacity-60',
      'before:absolute before:top-0.5 before:left-0.5 before:size-[1.125rem] before:rounded-full before:bg-bg before:shadow-sm',
      'before:transition-transform before:duration-150 checked:before:translate-x-5 motion-reduce:before:transition-none',
    ]}
  />
</div>
