<script lang="ts" module>
  export interface ErrorItem {
    /** id field terkait; bila ada, pesan menjadi tautan ke field tersebut. */
    fieldId?: string;
    message: string;
  }
</script>

<script lang="ts">
  interface Props {
    items: ErrorItem[];
    title?: string;
  }

  let { items, title = 'Periksa kembali isian berikut' }: Props = $props();
  let box = $state<HTMLDivElement>();

  // Setelah submit gagal, fokus pindah ke ringkasan agar pengguna keyboard dan pembaca layar langsung tahu.
  $effect(() => {
    if (items.length > 0) box?.focus();
  });
</script>

{#if items.length > 0}
  <div
    bind:this={box}
    role="alert"
    tabindex="-1"
    class="rounded-control border border-danger bg-danger-bg px-3 py-2.5 text-sm text-ink"
  >
    {#if items.length === 1 && !items[0]?.fieldId}
      <p class="font-medium">{items[0]?.message}</p>
    {:else}
      <p class="font-semibold">{title}</p>
      <ul class="mt-1 list-disc space-y-0.5 pl-5">
        {#each items as item (item.message)}
          <li>
            {#if item.fieldId}
              <!-- min-h-6: target sentuh minimal 24px (WCAG 2.2, 2.5.8) karena tautan bertumpuk rapat. -->
              <a href="#{item.fieldId}" class="inline-flex min-h-6 items-center underline underline-offset-2"
                >{item.message}</a
              >
            {:else}
              {item.message}
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </div>
{/if}
