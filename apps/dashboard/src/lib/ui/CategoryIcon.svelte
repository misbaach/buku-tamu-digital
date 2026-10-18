<script lang="ts">
  import Crown from '@lucide/svelte/icons/crown';
  import Star from '@lucide/svelte/icons/star';
  import { CATEGORY_LABEL, type Category } from '@guestbook/shared';

  // FR-C-01: VVIP mahkota, VIP bintang, Regular tanpa ikon.
  // `withText`: teks kategori sudah tampil di sebelahnya, jadi ikon murni dekoratif (tidak dibaca dua kali).
  let { category, size = 15, withText = false }: { category: Category; size?: number; withText?: boolean } = $props();
</script>

{#if category === 'vvip' || category === 'vip'}
  <span class="inline-flex shrink-0 text-ink" title={withText ? undefined : CATEGORY_LABEL[category]}>
    {#if category === 'vvip'}<Crown {size} aria-hidden="true" />{:else}<Star {size} aria-hidden="true" />{/if}
    {#if !withText}<span class="sr-only">{CATEGORY_LABEL[category]}</span>{/if}
  </span>
{/if}
