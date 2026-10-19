<script lang="ts">
  import Crown from '@lucide/svelte/icons/crown';
  import Star from '@lucide/svelte/icons/star';
  import { CATEGORY_LABEL, renderGreeting, type Category, type GreetingLayout } from '@guestbook/shared';

  // Pratinjau pop-up seukuran layar HP usher. Teks dirender sebagai teks biasa (tidak pernah sebagai HTML).
  interface Props {
    category: Category;
    title: string;
    body: string;
    layout: GreetingLayout;
    photoUrl: string | null;
    sampleName: string;
  }

  let { category, title, body, layout, photoUrl, sampleName }: Props = $props();
  const values = $derived({ nama: sampleName || 'Nama Tamu', kategori: CATEGORY_LABEL[category] });
  const showPhoto = $derived(layout !== 'text' && photoUrl !== null);
</script>

<figure class="mx-auto w-full max-w-[18rem]">
  <div class="aspect-[9/16] overflow-hidden rounded-[1.75rem] border-[6px] border-ink bg-ink/80 p-3">
    <div class="flex h-full flex-col justify-center">
      <div class="rounded-dialog bg-bg px-5 py-6 text-center shadow-xl">
        {#if showPhoto && layout === 'photo_wide'}
          <img
            src={photoUrl}
            alt=""
            class="-mx-5 -mt-6 mb-4 aspect-[4/3] w-[calc(100%+2.5rem)] max-w-none object-cover"
          />
        {:else if showPhoto && layout === 'photo_round'}
          <img src={photoUrl} alt="" class="mx-auto mb-4 size-24 rounded-full object-cover" />
        {/if}
        <p class="inline-flex items-center gap-1 text-xs font-semibold tracking-wide text-ink-muted uppercase">
          {#if category === 'vvip'}<Crown size={12} aria-hidden="true" />{:else if category === 'vip'}<Star
              size={12}
              aria-hidden="true"
            />{/if}
          {CATEGORY_LABEL[category]}
        </p>
        <p class="mt-2 text-xl leading-snug font-semibold break-words">{renderGreeting(title, values)}</p>
        {#if body}<p class="mt-2 text-sm leading-relaxed break-words text-ink-muted">
            {renderGreeting(body, values)}
          </p>{/if}
      </div>
    </div>
  </div>
  <figcaption class="mt-2 text-center text-sm text-ink-muted">Pratinjau di HP usher</figcaption>
</figure>
