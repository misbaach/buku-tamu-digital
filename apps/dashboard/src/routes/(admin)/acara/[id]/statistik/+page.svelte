<script lang="ts">
  import { resolve } from '$app/paths';
  import TriangleAlert from '@lucide/svelte/icons/triangle-alert';
  import { CATEGORY_LABEL, STATS_POLL_FALLBACK_MS, STATS_TIMELINE_BUCKET_MIN } from '@guestbook/shared';
  import ArrivalChart from '$lib/features/stats/ArrivalChart.svelte';
  import { liveStats } from '$lib/features/stats/live.svelte';
  import { LIMIT_SOURCE_LABEL, reviewSummary } from '$lib/features/stats/types';
  import { formatNumber } from '$lib/format';
  import Badge from '$lib/ui/Badge.svelte';
  import CategoryIcon from '$lib/ui/CategoryIcon.svelte';

  let { data } = $props();
  const s = $derived(data.stats);
  const review = $derived(reviewSummary(s.review));
  const meter = $derived(s.limit > 0 ? Math.min(100, (s.peoplePresent / s.limit) * 100) : 0);
  const clock = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  let live = $state<ReturnType<typeof liveStats> | null>(null);
  // Bergantung pada id (nilai primitif), bukan objek `data` yang baru setiap kali dimuat ulang; bila tidak,
  // setiap muat ulang menyambung ulang channel dan memicu muat ulang berikutnya tanpa henti.
  const eventId = $derived(data.event.id);
  $effect(() => {
    const l = liveStats(eventId, 'app:stats');
    live = l;
    return () => l.stop();
  });
  const mode = $derived(live?.state.mode ?? 'connecting');
</script>

<svelte:head>
  <title>Statistik · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Statistik</h2>
    <p class="mt-1 text-sm text-ink-muted">Dibandingkan dengan tamu yang sudah konfirmasi Akan hadir.</p>
  </div>
  <p class="flex items-center gap-2 text-sm" role="status">
    <span
      class={['size-2 rounded-full', mode === 'live' ? 'bg-ok' : mode === 'polling' ? 'bg-warn' : 'bg-line-strong']}
      aria-hidden="true"
    ></span>
    <span class="font-medium">
      {mode === 'live'
        ? 'Langsung'
        : mode === 'polling'
          ? `Diperbarui tiap ${STATS_POLL_FALLBACK_MS / 1000} detik`
          : 'Menyambung…'}
    </span>
    {#if live}<span class="tabular text-ink-muted">· {clock.format(live.state.updatedAt)}</span>{/if}
  </p>
</div>

{#if s.overLimit}
  <div role="alert" class="mt-5 flex gap-3 rounded-dialog border border-danger bg-danger-bg px-4 py-3 text-[0.9375rem]">
    <TriangleAlert size={18} class="mt-0.5 shrink-0 text-danger" aria-hidden="true" />
    <p>
      <strong>Jumlah hadir {formatNumber(s.peoplePresent)} orang melebihi batas {formatNumber(s.limit)} orang</strong>
      ({LIMIT_SOURCE_LABEL[s.limitSource]}).
    </p>
  </div>
{/if}

{#if review}
  <p class="mt-4 flex flex-wrap items-center gap-2 text-[0.9375rem]">
    <Badge variant="review">Perlu ditinjau</Badge>
    <span>{review}</span>
    <!-- eslint-disable svelte/no-navigation-without-resolve -- pathname lewat resolve(), hanya ditambah query -->
    <a
      href={resolve(`/acara/${data.event.id}/riwayat`) + '?status=tinjau'}
      class="font-medium underline underline-offset-2">Buka Riwayat</a
    >
    <!-- eslint-enable svelte/no-navigation-without-resolve -->
  </p>
{/if}

<!-- FR-S-01: angka utama -->
<section class="mt-6 rounded-dialog border border-line px-5 py-5" aria-labelledby="present-heading">
  <h3 id="present-heading" class="text-sm font-medium text-ink-muted">Orang hadir</h3>
  <p class="mt-1 flex flex-wrap items-baseline gap-x-3" aria-live="polite">
    <span class="text-5xl font-semibold tracking-tight">{formatNumber(s.peoplePresent)}</span>
    <span class="text-ink-muted">dari <span class="tabular">{formatNumber(s.rsvpGoingPax)}</span> orang Akan hadir</span
    >
  </p>
  <!-- Meter tanpa style inline (CSP): lebar lewat atribut SVG. -->
  <svg class="mt-4 h-2 w-full" viewBox="0 0 100 2" preserveAspectRatio="none" aria-hidden="true">
    <rect width="100" height="2" rx="1" class="fill-surface-2" />
    <rect width={meter} height="2" rx="1" class={s.overLimit ? 'fill-danger' : 'fill-ink'} />
  </svg>
  <p class="mt-2 text-sm text-ink-muted">
    Batas jumlah hadir <span class="tabular font-medium text-ink">{formatNumber(s.limit)}</span> orang ({LIMIT_SOURCE_LABEL[
      s.limitSource
    ]}). Masuk ulang, Ganda, Karantina, dan yang dibatalkan tidak dihitung.
  </p>
</section>

<!-- FR-S-03..05 -->
<dl class="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
  <div class="rounded-dialog border border-line px-4 py-4">
    <dt class="text-sm text-ink-muted">Tamu undangan masuk</dt>
    <dd class="mt-1">
      <span class="text-2xl font-semibold">{formatNumber(s.invitedCheckedIn)}</span>
      <span class="text-sm text-ink-muted">dari {formatNumber(s.rsvpGoingGuests)} Akan hadir</span>
    </dd>
  </div>
  <div class="rounded-dialog border border-line px-4 py-4">
    <dt class="text-sm text-ink-muted">Sudah check-out</dt>
    <dd class="mt-1">
      <span class="text-2xl font-semibold">{formatNumber(s.guestsCheckedOut)}</span>
      <span class="text-sm text-ink-muted">dari {formatNumber(s.guestsPresent)} tamu hadir</span>
    </dd>
  </div>
  <div class="rounded-dialog border border-line px-4 py-4">
    <dt class="text-sm text-ink-muted">Tamu tambahan</dt>
    <dd class="mt-1">
      <span class="text-2xl font-semibold">{formatNumber(s.additionalGuests)}</span>
      <span class="text-sm text-ink-muted">tamu · {formatNumber(s.additionalPeople)} orang</span>
    </dd>
  </div>
  <div class="rounded-dialog border border-line px-4 py-4">
    <dt class="text-sm text-ink-muted">Di luar jumlah tercatat</dt>
    <dd class="mt-1">
      <span class="text-2xl font-semibold">{formatNumber(s.beyondRecorded)}</span>
      <span class="text-sm text-ink-muted">orang lebih dari undangan/konfirmasi</span>
    </dd>
  </div>
</dl>

<div class="mt-8 grid gap-8 lg:grid-cols-[20rem_minmax(0,1fr)]">
  <!-- FR-S-02 -->
  <section aria-labelledby="category-heading">
    <h3 id="category-heading" class="font-semibold">Per kategori</h3>
    <table class="mt-3 w-full text-left text-sm">
      <thead class="text-ink-muted">
        <tr>
          <th scope="col" class="py-2 font-medium">Kategori</th>
          <th scope="col" class="py-2 text-right font-medium">Hadir</th>
          <th scope="col" class="py-2 text-right font-medium">Akan hadir</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-line border-t border-line">
        {#each s.categories as c (c.category)}
          <tr>
            <th scope="row" class="py-2.5 font-medium">
              <span class="inline-flex items-center gap-1.5"
                ><CategoryIcon category={c.category} withText />{CATEGORY_LABEL[c.category]}</span
              >
            </th>
            <td class="tabular py-2.5 text-right">{formatNumber(c.people)} orang</td>
            <td class="tabular py-2.5 text-right text-ink-muted">{formatNumber(c.rsvpPax)}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  </section>

  <section>
    <ArrivalChart buckets={data.timeline} timezone={data.event.timezone} bucketMin={STATS_TIMELINE_BUCKET_MIN} />
  </section>
</div>
