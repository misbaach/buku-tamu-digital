<script lang="ts">
  import { formatNumber } from '$lib/format';
  import type { TimelineBucket } from './types';

  // Linimasa kedatangan (FR-S-03): satu seri, batang per interval. Satu warna data (--color-info, lolos validator
  // dataviz), grid tipis, label sumbu memakai token teks, keterangan saat hover, dan tabel sebagai alternatif.
  interface Props {
    buckets: TimelineBucket[];
    timezone: string;
    bucketMin: number;
  }

  let { buckets, timezone, bucketMin }: Props = $props();
  const uid = $props.id();

  // Lebar mengikuti kontainer (bukan viewBox yang diskalakan) agar teks sumbu tetap 11px di layar sempit.
  let width = $state(720);
  const W = $derived(Math.max(280, Math.round(width)));
  const H = 220;
  const PAD = { top: 12, right: 8, bottom: 28, left: 36 };
  const plotW = $derived(W - PAD.left - PAD.right);
  const plotH = H - PAD.top - PAD.bottom;

  const time = $derived(new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit', timeZone: timezone }));
  const max = $derived(Math.max(1, ...buckets.map((b) => b.people)));
  // Tick bulat: 1, 2, 5, 10, 20, 50, ...
  const step = $derived.by(() => {
    const raw = max / 4;
    const mag = 10 ** Math.floor(Math.log10(raw || 1));
    return [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw) ?? mag * 10;
  });
  const top = $derived(Math.ceil(max / step) * step);
  const ticks = $derived(Array.from({ length: Math.floor(top / step) + 1 }, (_, i) => i * step));
  const band = $derived(plotW / Math.max(buckets.length, 1));
  const barW = $derived(Math.min(24, Math.max(4, band - 2)));
  const y = (v: number) => PAD.top + plotH - (v / top) * plotH;
  // Label sumbu-x cukup beberapa saja agar tidak bertabrakan.
  const labelEvery = $derived(Math.max(1, Math.ceil(buckets.length / Math.max(3, Math.floor(plotW / 70)))));

  let active = $state<number | null>(null);
  const activeBucket = $derived(active === null ? null : (buckets[active] ?? null));
  let showTable = $state(false);

  function barPath(x: number, w: number, top: number, bottom: number): string {
    const r = Math.min(4, w / 2, bottom - top);
    // Ujung data membulat 4px, sisi baseline lurus.
    return `M${x},${bottom} V${top + r} Q${x},${top} ${x + r},${top} H${x + w - r} Q${x + w},${top} ${x + w},${top + r} V${bottom} Z`;
  }
</script>

<section aria-labelledby="{uid}-title">
  <div class="flex flex-wrap items-baseline justify-between gap-2">
    <h3 id="{uid}-title" class="font-semibold">Kedatangan per {bucketMin} menit</h3>
    {#if buckets.length > 0}
      <button
        type="button"
        class="cursor-pointer text-sm text-ink-muted underline underline-offset-2 hover:text-ink"
        aria-expanded={showTable}
        aria-controls="{uid}-table"
        onclick={() => (showTable = !showTable)}>{showTable ? 'Tampilkan grafik' : 'Tampilkan sebagai tabel'}</button
      >
    {/if}
  </div>
  <p class="text-sm text-ink-muted">Jumlah orang menurut jam check-in di perangkat usher.</p>

  {#if buckets.length === 0}
    <p class="mt-3 rounded-dialog border border-line px-4 py-8 text-center text-ink-muted">Belum ada kedatangan.</p>
  {:else if showTable}
    <table id="{uid}-table" class="mt-3 w-full max-w-md text-left text-sm">
      <thead class="text-ink-muted">
        <tr
          ><th scope="col" class="py-1.5 font-medium">Mulai</th><th scope="col" class="py-1.5 text-right font-medium"
            >Tamu</th
          ><th scope="col" class="py-1.5 text-right font-medium">Orang</th></tr
        >
      </thead>
      <tbody class="divide-y divide-line">
        {#each buckets as b (b.bucket_start)}
          <tr>
            <td class="tabular py-1.5">{time.format(new Date(b.bucket_start))}</td>
            <td class="tabular py-1.5 text-right">{formatNumber(b.guests)}</td>
            <td class="tabular py-1.5 text-right">{formatNumber(b.people)}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {:else}
    <div class="relative mt-3" bind:clientWidth={width}>
      <svg
        viewBox="0 0 {W} {H}"
        width={W}
        height={H}
        class="block"
        role="img"
        aria-label="Grafik batang kedatangan; data lengkap tersedia sebagai tabel."
      >
        {#each ticks as t (t)}
          <line x1={PAD.left} x2={W - PAD.right} y1={y(t)} y2={y(t)} class="stroke-line" stroke-width="1" />
          <text x={PAD.left - 6} y={y(t)} dy="0.32em" text-anchor="end" class="fill-ink-muted text-[11px] tabular-nums"
            >{t}</text
          >
        {/each}
        {#each buckets as b, i (b.bucket_start)}
          {@const x = PAD.left + i * band + (band - barW) / 2}
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <g onmouseenter={() => (active = i)} onmouseleave={() => (active = null)}>
            <!-- Area hover selebar pita, lebih besar dari batangnya. -->
            <rect x={PAD.left + i * band} y={PAD.top} width={band} height={plotH} fill="transparent" />
            {#if b.people > 0}
              <path d={barPath(x, barW, y(b.people), y(0))} class={active === i ? 'fill-ink' : 'fill-info'} />
            {/if}
          </g>
          {#if i % labelEvery === 0}
            <text x={x + barW / 2} y={H - 8} text-anchor="middle" class="fill-ink-muted text-[11px] tabular-nums"
              >{time.format(new Date(b.bucket_start))}</text
            >
          {/if}
        {/each}
      </svg>
    </div>
    <!-- Keterangan hover tanpa posisi inline (CSP tanpa style attribute). -->
    <p class="mt-1 min-h-6 text-sm" aria-live="polite">
      {#if activeBucket}
        {@const b = activeBucket}
        <span class="tabular font-medium">{time.format(new Date(b.bucket_start))}</span> ·
        <span class="tabular">{formatNumber(b.people)} orang</span> dari
        <span class="tabular">{formatNumber(b.guests)} tamu</span>
      {:else}
        <span class="text-ink-muted">Arahkan kursor ke batang untuk melihat angkanya.</span>
      {/if}
    </p>
  {/if}
</section>
