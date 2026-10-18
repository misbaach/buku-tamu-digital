<script lang="ts">
  import { invalidate } from '$app/navigation';
  import { resolve } from '$app/paths';
  import Download from '@lucide/svelte/icons/download';
  import FileUp from '@lucide/svelte/icons/file-up';
  import {
    CATEGORY_LABEL,
    crossCheckImport,
    IMPORT_COLUMNS,
    rsvpLabel,
    type ImportField,
    type ImportRowResult,
  } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { downloadTemplate, ImportFileError, parseGuestFile } from '$lib/features/import/parse';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import Badge from '$lib/ui/Badge.svelte';
  import Button from '$lib/ui/Button.svelte';
  import LinkButton from '$lib/ui/LinkButton.svelte';
  import Pagination from '$lib/ui/Pagination.svelte';

  let { data } = $props();

  type Step = 'unggah' | 'tinjau' | 'selesai';
  const STEPS: { id: Step; label: string }[] = [
    { id: 'unggah', label: 'Unggah berkas' },
    { id: 'tinjau', label: 'Tinjau tamu' },
    { id: 'selesai', label: 'Selesai' },
  ];
  const FIELD_LABEL = Object.fromEntries(IMPORT_COLUMNS.map((c) => [c.key, c.header])) as Record<ImportField, string>;
  const PER_PAGE = 100;

  let step = $state<Step>('unggah');
  let fileName = $state('');
  let results = $state<ImportRowResult[]>([]);
  let busy = $state(false);
  let error = $state<string | null>(null);
  let dragging = $state(false);
  let onlyIssues = $state(false);
  let pageNo = $state(1);
  let summary = $state<{ inserted: number; groups_created: number } | null>(null);
  let input = $state<HTMLInputElement>();

  const valid = $derived(results.filter((r) => r.ok));
  const invalidCount = $derived(results.length - valid.length);
  const shown = $derived(onlyIssues ? results.filter((r) => !r.ok) : results);
  const pageRows = $derived(shown.slice((pageNo - 1) * PER_PAGE, pageNo * PER_PAGE));
  const newGroups = $derived.by(() => {
    const existing = new Set(data.groups.map((g) => g.name.trim().toLowerCase()));
    // eslint-disable-next-line svelte/prefer-svelte-reactivity -- Map sementara di dalam $derived, bukan state
    const found = new Map<string, string>();
    for (const r of valid) {
      const g = r.ok ? r.value.group : null;
      if (g && !existing.has(g.toLowerCase()) && !found.has(g.toLowerCase())) found.set(g.toLowerCase(), g);
    }
    return [...found.values()];
  });

  async function handleFile(file: File | undefined) {
    if (!file) return;
    busy = true;
    error = null;
    fileName = file.name;
    try {
      const parsed = await parseGuestFile(file);
      const numbers = [
        ...new Set(parsed.flatMap((r) => (r.ok && r.value.special_number ? [r.value.special_number] : []))),
      ];
      let used = new Map<string, string>();
      if (numbers.length > 0) {
        const { data: rows, error: dbError } = await supabase.rpc('admin_check_special_numbers', {
          p_event_id: data.event.id,
          p_numbers: numbers,
        });
        if (dbError) throw dbError;
        used = new Map(rows.map((r) => [r.special_number, r.guest_name]));
      }
      results = crossCheckImport(parsed, used);
      onlyIssues = false;
      pageNo = 1;
      step = 'tinjau';
    } catch (e) {
      error = e instanceof ImportFileError ? e.message : dbErrorMessage(e);
    } finally {
      busy = false;
      if (input) input.value = '';
    }
  }

  async function process() {
    busy = true;
    error = null;
    const rows = valid.flatMap((r) => (r.ok ? [r.value] : []));
    const { data: result, error: dbError } = await supabase.rpc('admin_import_guests', {
      p_event_id: data.event.id,
      p_rows: rows,
    });
    busy = false;
    if (dbError) {
      error = dbErrorMessage(dbError);
      return;
    }
    summary = result as { inserted: number; groups_created: number };
    step = 'selesai';
    void invalidate('app:guests');
  }

  function reset() {
    step = 'unggah';
    results = [];
    error = null;
    summary = null;
  }
</script>

<svelte:head>
  <title>Impor tamu · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Impor tamu</h2>
    <p class="mt-1 text-sm text-ink-muted">Tambahkan banyak tamu sekaligus dari berkas Excel atau CSV.</p>
  </div>
  <LinkButton href={resolve(`/acara/${data.event.id}/tamu`)}>Kembali ke daftar tamu</LinkButton>
</div>

<ol class="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-sm" aria-label="Langkah impor">
  {#each STEPS as s, i (s.id)}
    {@const done = STEPS.findIndex((x) => x.id === step) > i}
    <li aria-current={step === s.id ? 'step' : undefined} class="flex items-center gap-2">
      <span
        class={[
          'tabular grid size-6 place-items-center rounded-full border text-xs font-semibold',
          step === s.id
            ? 'border-ink bg-ink text-on-primary'
            : done
              ? 'border-ink text-ink'
              : 'border-line-strong text-ink-muted',
        ]}>{i + 1}</span
      >
      <span class={step === s.id ? 'font-semibold' : 'text-ink-muted'}>{s.label}</span>
    </li>
  {/each}
</ol>

{#if error}
  <p role="alert" class="mt-4 rounded-control border border-danger bg-danger-bg px-3 py-2.5 text-sm">{error}</p>
{/if}

{#if step === 'unggah'}
  <div class="mt-6 grid gap-6 lg:grid-cols-[2fr_1fr]">
    <label
      for="import-file"
      class={[
        'flex min-h-56 cursor-pointer flex-col items-center justify-center gap-3 rounded-dialog border-2 border-dashed px-6 py-10 text-center',
        'has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-focus',
        dragging ? 'border-ink bg-surface' : 'border-line-strong bg-bg hover:bg-surface',
      ]}
      ondragover={(e) => {
        e.preventDefault();
        dragging = true;
      }}
      ondragleave={() => (dragging = false)}
      ondrop={(e) => {
        e.preventDefault();
        dragging = false;
        void handleFile(e.dataTransfer?.files[0]);
      }}
    >
      <FileUp size={28} class="text-ink-muted" aria-hidden="true" />
      <span class="font-medium">{busy ? `Membaca ${fileName}…` : 'Pilih berkas atau tarik ke sini'}</span>
      <span class="text-sm text-ink-muted">.xlsx, .xls, atau .csv · maksimal 5 MB · maksimal 5.000 baris</span>
      <input
        bind:this={input}
        id="import-file"
        type="file"
        accept=".xlsx,.xls,.csv"
        class="sr-only"
        disabled={busy}
        onchange={(e) => handleFile(e.currentTarget.files?.[0])}
      />
    </label>
    <div class="rounded-dialog border border-line bg-surface p-5 text-sm">
      <h3 class="font-semibold">Pakai templat</h3>
      <p class="mt-1 text-ink-muted">
        Templat berisi nama kolom yang dikenali dan lembar petunjuk. Hanya kolom Nama yang wajib.
      </p>
      <Button variant="secondary" class="mt-4" onclick={() => downloadTemplate()}>
        <Download size={16} aria-hidden="true" />Unduh templat (.xlsx)
      </Button>
      <ul class="mt-4 list-disc space-y-1 pl-5 text-ink-muted">
        <li>Grup yang belum ada dibuat otomatis.</li>
        <li>Nomor Urut seperti <span class="font-mono">A-017</span> ditolak karena dipakai nomor perangkat.</li>
        <li>Tidak ada yang disimpan sebelum Anda menekan Proses.</li>
      </ul>
    </div>
  </div>
{:else if step === 'tinjau'}
  <section class="mt-6" aria-labelledby="review-title">
    <h3 id="review-title" class="sr-only">Tinjau tamu</h3>
    <div class="flex flex-wrap items-center gap-x-6 gap-y-2 rounded-dialog border border-line bg-surface px-5 py-4">
      <p class="text-sm"><span class="font-medium">{fileName}</span></p>
      <p class="tabular text-sm"><span class="font-semibold">{formatNumber(results.length)}</span> baris</p>
      <p class="tabular text-sm text-ok"><span class="font-semibold">{formatNumber(valid.length)}</span> siap</p>
      {#if invalidCount > 0}
        <p class="tabular text-sm text-danger">
          <span class="font-semibold">{formatNumber(invalidCount)}</span> bermasalah
        </p>
      {/if}
      {#if newGroups.length > 0}
        <p class="text-sm text-ink-muted">Grup baru: {newGroups.join(', ')}</p>
      {/if}
    </div>

    {#if invalidCount > 0}
      <label class="mt-4 inline-flex cursor-pointer items-center gap-2 text-sm">
        <input type="checkbox" class="size-4 accent-ink" bind:checked={onlyIssues} onchange={() => (pageNo = 1)} />
        Tampilkan hanya baris bermasalah
      </label>
    {/if}

    <div class="mt-3 overflow-x-auto rounded-dialog border border-line">
      <table class="w-full min-w-4xl text-left text-sm">
        <caption class="sr-only">Hasil pemeriksaan berkas impor</caption>
        <thead class="bg-surface text-ink-muted">
          <tr>
            <th scope="col" class="px-3 py-2.5 font-medium">Baris</th>
            <th scope="col" class="px-3 py-2.5 font-medium">Nama</th>
            <th scope="col" class="px-3 py-2.5 font-medium">Kategori</th>
            <th scope="col" class="px-3 py-2.5 font-medium">Grup</th>
            <th scope="col" class="px-3 py-2.5 text-right font-medium">Undangan</th>
            <th scope="col" class="px-3 py-2.5 font-medium">Nomor Urut</th>
            <th scope="col" class="px-3 py-2.5 font-medium">RSVP</th>
            <th scope="col" class="px-3 py-2.5 font-medium">Status</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each pageRows as r (r.row)}
            <tr class={r.ok ? '' : 'bg-danger-bg/50'}>
              <td class="tabular px-3 py-2 text-ink-muted">{r.row}</td>
              {#if r.ok}
                <td class="px-3 py-2 font-medium">{r.value.name}</td>
                <td class="px-3 py-2">{CATEGORY_LABEL[r.value.category]}</td>
                <td class="px-3 py-2">{r.value.group ?? '—'}</td>
                <td class="tabular px-3 py-2 text-right">{r.value.invited_pax}</td>
                <td class="px-3 py-2 font-mono">{r.value.special_number ?? ''}</td>
                <td class="px-3 py-2">{rsvpLabel(r.value.rsvp_status, r.value.rsvp_pax)}</td>
                <td class="px-3 py-2"><Badge variant="ok">Siap</Badge></td>
              {:else}
                <td class="px-3 py-2 font-medium">{r.raw.name || '(kosong)'}</td>
                <td class="px-3 py-2">{r.raw.category}</td>
                <td class="px-3 py-2">{r.raw.group}</td>
                <td class="tabular px-3 py-2 text-right">{r.raw.invited_pax}</td>
                <td class="px-3 py-2 font-mono">{r.raw.special_number}</td>
                <td class="px-3 py-2">{r.raw.rsvp_status}</td>
                <td class="px-3 py-2">
                  <ul class="space-y-0.5 text-danger">
                    {#each r.issues as issue, i (i)}
                      <li>
                        {#if issue.field}<span class="font-medium">{FIELD_LABEL[issue.field]}:</span>{/if}
                        {issue.message}
                      </li>
                    {/each}
                  </ul>
                </td>
              {/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    {#if shown.length > PER_PAGE}
      <div class="mt-3">
        <Pagination total={shown.length} page={pageNo} perPage={PER_PAGE} onpage={(p) => (pageNo = p)} />
      </div>
    {/if}

    <div class="mt-6 flex flex-wrap items-center gap-3 border-t border-line pt-4">
      <Button onclick={process} {busy} disabled={valid.length === 0}>
        {busy ? 'Memproses…' : `Proses ${formatNumber(valid.length)} tamu`}
      </Button>
      <Button variant="secondary" onclick={reset} disabled={busy}>Ganti berkas</Button>
      {#if invalidCount > 0}
        <p class="text-sm text-ink-muted">
          {formatNumber(invalidCount)} baris bermasalah akan dilewati. Perbaiki berkas lalu impor ulang baris tersebut.
        </p>
      {/if}
    </div>
  </section>
{:else if summary}
  <div class="mt-6 rounded-dialog border border-line px-6 py-8" role="status">
    <p class="text-lg font-semibold">{formatNumber(summary.inserted)} tamu ditambahkan.</p>
    {#if summary.groups_created > 0}
      <p class="mt-1 text-ink-muted">{formatNumber(summary.groups_created)} grup baru dibuat.</p>
    {/if}
    <div class="mt-5 flex flex-wrap gap-2">
      <LinkButton variant="primary" href={resolve(`/acara/${data.event.id}/tamu`)}>Lihat daftar tamu</LinkButton>
      <Button variant="secondary" onclick={reset}>Impor berkas lain</Button>
    </div>
  </div>
{/if}
