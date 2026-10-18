<script lang="ts">
  import { CATEGORY_LABEL } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import RadioGroup from '$lib/ui/RadioGroup.svelte';

  // FR-C-04: pilih urutan → pratinjau → simpan. Nomor yang sudah ada tidak ditimpa kecuali dikonfirmasi.
  interface Props {
    open: boolean;
    eventId: string;
    category: 'vip' | 'vvip';
    onapplied: () => void;
  }

  let { open = $bindable(false), eventId, category, onapplied }: Props = $props();

  interface PreviewRow {
    guest_id: string;
    guest_name: string;
    group_name: string | null;
    old_number: string | null;
    new_number: string;
  }

  let order = $state<'name' | 'group' | 'input'>('name');
  let overwrite = $state(false);
  let preview = $state<{ hash: string; rows: PreviewRow[] } | null>(null);
  let confirmOverwrite = $state(false);
  let busy = $state(false);
  let error = $state<string | null>(null);

  const replaced = $derived(preview?.rows.filter((r) => r.old_number && r.old_number !== r.new_number).length ?? 0);

  function resetPreview() {
    preview = null;
    confirmOverwrite = false;
    error = null;
  }

  // Pratinjau hanya berlaku untuk pilihan yang dipakai membuatnya.
  $effect(() => {
    void order;
    void overwrite;
    resetPreview();
  });

  async function loadPreview() {
    busy = true;
    error = null;
    const { data, error: dbError } = await supabase.rpc('admin_preview_special_numbers', {
      p_event_id: eventId,
      p_category: category,
      p_order: order,
      p_overwrite: overwrite,
    });
    busy = false;
    if (dbError) {
      error = dbErrorMessage(dbError);
      return;
    }
    preview = data as unknown as { hash: string; rows: PreviewRow[] };
  }

  async function apply() {
    if (!preview) return;
    busy = true;
    error = null;
    const { data, error: dbError } = await supabase.rpc('admin_apply_special_numbers', {
      p_event_id: eventId,
      p_category: category,
      p_order: order,
      p_overwrite: overwrite,
      p_expected_hash: preview.hash,
    });
    busy = false;
    if (dbError) {
      error = dbErrorMessage(dbError);
      if (dbError.code === '40001') preview = null;
      return;
    }
    toast.success(`${formatNumber(data)} Nomor Urut ${CATEGORY_LABEL[category]} disimpan.`);
    open = false;
    onapplied();
  }
</script>

<Dialog
  bind:open
  title="Terapkan Nomor Urut {CATEGORY_LABEL[category]}"
  description="Nomor dibuat dari setting prefix, angka awal, dan jumlah digit. Nomor yang sudah dipakai dilewati."
  size="lg"
  onclose={() => {
    resetPreview();
    overwrite = false;
    order = 'name';
  }}
>
  <div class="space-y-5">
    <RadioGroup
      name="apply-order"
      legend="Urutan pemberian nomor"
      options={[
        { value: 'name', label: 'Nama A–Z' },
        { value: 'group', label: 'Grup, lalu nama' },
        { value: 'input', label: 'Urutan input' },
      ]}
      bind:value={order}
    />
    <label class="flex cursor-pointer items-start gap-3 text-[0.9375rem]">
      <input type="checkbox" class="mt-1 size-4 accent-ink" bind:checked={overwrite} />
      <span>
        <span class="font-medium">Timpa nomor yang sudah ada</span>
        <span class="block text-sm text-ink-muted">
          Semua tamu {CATEGORY_LABEL[category]} diberi nomor baru mulai dari angka awal. Tiket yang sudah tercetak tidak berubah.
        </span>
      </span>
    </label>

    {#if error}<p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-sm">
        {error}
      </p>{/if}

    {#if preview}
      {#if preview.rows.length === 0}
        <p class="rounded-control border border-line bg-surface px-3 py-2.5 text-sm" role="status">
          Semua tamu {CATEGORY_LABEL[category]} sudah bernomor. Centang "Timpa nomor yang sudah ada" untuk menomori ulang.
        </p>
      {:else}
        <div>
          <p class="text-sm" role="status">
            <span class="tabular font-semibold">{formatNumber(preview.rows.length)}</span> tamu akan diberi nomor{#if replaced > 0},
              termasuk
              <span class="tabular font-semibold">{formatNumber(replaced)}</span> nomor lama yang diganti{/if}.
          </p>
          <div class="mt-2 max-h-72 overflow-y-auto rounded-dialog border border-line">
            <table class="w-full text-left text-sm">
              <caption class="sr-only">Pratinjau Nomor Urut</caption>
              <thead class="sticky top-0 bg-surface text-ink-muted">
                <tr>
                  <th scope="col" class="px-3 py-2 font-medium">Nama</th>
                  <th scope="col" class="px-3 py-2 font-medium">Grup</th>
                  <th scope="col" class="px-3 py-2 font-medium">Nomor lama</th>
                  <th scope="col" class="px-3 py-2 font-medium">Nomor baru</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-line">
                {#each preview.rows as row (row.guest_id)}
                  <tr>
                    <td class="px-3 py-2">{row.guest_name}</td>
                    <td class="px-3 py-2 text-ink-muted">{row.group_name ?? '—'}</td>
                    <td class="px-3 py-2 font-mono text-ink-muted">{row.old_number ?? '—'}</td>
                    <td class="px-3 py-2 font-mono font-semibold">{row.new_number}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
        {#if replaced > 0}
          <label
            class="flex cursor-pointer items-start gap-3 rounded-control border border-warn bg-warn-bg px-3 py-2.5 text-sm"
          >
            <input type="checkbox" class="mt-0.5 size-4 accent-ink" bind:checked={confirmOverwrite} />
            <span
              >Saya mengerti {formatNumber(replaced)} nomor lama akan diganti dan perubahan ini dicatat di audit log.</span
            >
          </label>
        {/if}
      {/if}
    {/if}
  </div>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (open = false)} disabled={busy}>Batal</Button>
    {#if !preview}
      <Button onclick={loadPreview} {busy}>{busy ? 'Menyiapkan…' : 'Lihat pratinjau'}</Button>
    {:else if preview.rows.length > 0}
      <Button onclick={apply} {busy} disabled={replaced > 0 && !confirmOverwrite}>
        {busy ? 'Menyimpan…' : `Simpan ${formatNumber(preview.rows.length)} nomor`}
      </Button>
    {/if}
  {/snippet}
</Dialog>
