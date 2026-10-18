<script lang="ts">
  import { invalidate } from '$app/navigation';
  import {
    CATEGORY_LABEL,
    checkTicketNumberSetting,
    formatSpecialNumber,
    type SpecialNumberIssue,
  } from '@guestbook/shared';
  import ApplyNumbersDialog from '$lib/features/numbering/ApplyNumbersDialog.svelte';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import CategoryIcon from '$lib/ui/CategoryIcon.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import Field from '$lib/ui/Field.svelte';

  let { data } = $props();
  type Category = 'vip' | 'vvip';

  const ISSUE_MESSAGE: Record<SpecialNumberIssue, string> = {
    empty: 'Isi prefix.',
    too_long: 'Prefix ditambah jumlah digit melebihi 20 karakter.',
    invalid_chars: 'Prefix hanya boleh huruf, angka, dan tanda hubung; jumlah digit 1–6.',
    device_pattern: 'Prefix ini menghasilkan pola nomor perangkat (mis. A-001). Pakai minimal 3 huruf, mis. "VIP-".',
    gift_pattern: 'Prefix ini menghasilkan pola kode hadiah. Pakai prefix lain.',
  };

  // Form per kategori; nilai awal dari data, dimuat ulang setelah disimpan.
  let forms = $state<Record<Category, { prefix: string; start: string; digits: string }>>({
    vip: { prefix: '', start: '1', digits: '3' },
    vvip: { prefix: '', start: '1', digits: '3' },
  });
  $effect(() => {
    for (const p of data.panels) {
      forms[p.category] = {
        prefix: p.setting.prefix,
        start: String(p.setting.start_number),
        digits: String(p.setting.digits),
      };
    }
  });

  function validate(c: Category): { error: string | null; example: string | null } {
    const f = forms[c];
    const start = Number(f.start);
    const digits = Number(f.digits);
    if (!Number.isInteger(start) || start < 0 || start > 999999)
      return { error: 'Angka awal harus 0–999999.', example: null };
    const issue = checkTicketNumberSetting(f.prefix, digits);
    if (issue) return { error: ISSUE_MESSAGE[issue], example: null };
    return {
      error: null,
      example: `${formatSpecialNumber(f.prefix, start, digits)}, ${formatSpecialNumber(f.prefix, start + 1, digits)}, …`,
    };
  }

  let saving = $state<Category | null>(null);
  let saveErrors = $state<Record<Category, string | null>>({ vip: null, vvip: null });

  async function save(event: SubmitEvent, c: Category) {
    event.preventDefault();
    const v = validate(c);
    if (v.error) {
      saveErrors[c] = v.error;
      return;
    }
    saving = c;
    saveErrors[c] = null;
    const f = forms[c];
    const { error } = await supabase
      .from('ticket_number_settings')
      .update({ prefix: f.prefix.trim().toUpperCase(), start_number: Number(f.start), digits: Number(f.digits) })
      .eq('event_id', data.event.id)
      .eq('category', c);
    saving = null;
    if (error) {
      saveErrors[c] = dbErrorMessage(error);
      return;
    }
    toast.success(`Setting Nomor Urut ${CATEGORY_LABEL[c]} disimpan.`);
    await invalidate('app:numbering');
  }

  // --- Terapkan ---
  let applyOpen = $state(false);
  let applyCategory = $state<Category>('vvip');

  // --- Hapus semua nomor satu kategori ---
  let clearCategory = $state<Category | null>(null);
  let clearOpen = $state(false);
  let clearBusy = $state(false);
  let clearError = $state<string | null>(null);
  const clearPanel = $derived(data.panels.find((p) => p.category === clearCategory));

  async function clearAll() {
    if (!clearCategory) return;
    clearBusy = true;
    clearError = null;
    // PostgREST membatasi 1.000 baris per respons (max_rows), jadi id diambil per halaman.
    const ids: string[] = [];
    for (let from = 0; ; from += 1000) {
      const { data: rows, error } = await supabase
        .from('guests')
        .select('id')
        .eq('event_id', data.event.id)
        .eq('category', clearCategory)
        .is('deleted_at', null)
        .not('special_number', 'is', null)
        .order('id')
        .range(from, from + 999);
      if (error) {
        clearBusy = false;
        clearError = dbErrorMessage(error);
        return;
      }
      ids.push(...rows.map((r) => r.id));
      if (rows.length < 1000) break;
    }
    const { data: count, error: rpcError } = await supabase.rpc('admin_clear_special_numbers', {
      p_event_id: data.event.id,
      p_guest_ids: ids,
    });
    clearBusy = false;
    if (rpcError) {
      clearError = dbErrorMessage(rpcError);
      return;
    }
    toast.success(`${formatNumber(count)} Nomor Urut ${CATEGORY_LABEL[clearCategory]} dihapus.`);
    clearOpen = false;
    await invalidate('app:numbering');
  }
</script>

<svelte:head>
  <title>Nomor Urut · {data.event.name}</title>
</svelte:head>

<div>
  <h2 class="text-xl font-semibold">Nomor Urut VIP & VVIP</h2>
  <p class="mt-1 max-w-3xl text-sm text-ink-muted">
    Nomor Urut khusus tercetak di tiket tamu VIP/VVIP. Tamu tanpa Nomor Urut mendapat nomor otomatis dari perangkat
    usher (mis. A-017), jadi pola itu tidak bisa dipakai di sini.
  </p>
</div>

<div class="mt-6 grid gap-6 lg:grid-cols-2">
  {#each data.panels as panel (panel.category)}
    {@const c = panel.category}
    {@const v = validate(c)}
    <section class="rounded-dialog border border-line" aria-labelledby="panel-{c}">
      <header class="flex items-center justify-between gap-3 border-b border-line px-5 py-3">
        <h3 id="panel-{c}" class="flex items-center gap-2 font-semibold">
          <CategoryIcon category={c} size={16} withText />{CATEGORY_LABEL[c]}
        </h3>
        <p class="tabular text-sm text-ink-muted">
          {formatNumber(panel.total)} tamu · {formatNumber(panel.total - panel.numbered)} belum bernomor
        </p>
      </header>
      <form class="space-y-4 px-5 py-4" onsubmit={(e) => save(e, c)} novalidate>
        <div class="grid grid-cols-3 gap-3">
          <Field
            id="{c}-prefix"
            label="Prefix"
            class="[&_input]:font-mono [&_input]:uppercase"
            maxlength={19}
            bind:value={forms[c].prefix}
            autocomplete="off"
          />
          <Field id="{c}-start" label="Angka awal" type="number" min={0} max={999999} bind:value={forms[c].start} />
          <Field id="{c}-digits" label="Jumlah digit" type="number" min={1} max={6} bind:value={forms[c].digits} />
        </div>
        <p class="text-sm" aria-live="polite">
          {#if v.error}
            <span class="text-danger">{v.error}</span>
          {:else}
            <span class="text-ink-muted">Contoh:</span> <span class="font-mono font-medium">{v.example}</span>
          {/if}
        </p>
        {#if saveErrors[c]}<p role="alert" class="text-sm text-danger">{saveErrors[c]}</p>{/if}
        <div class="flex flex-wrap gap-2">
          <Button type="submit" variant="secondary" size="sm" busy={saving === c}>Simpan setting</Button>
        </div>
      </form>
      <footer class="flex flex-wrap gap-2 border-t border-line bg-surface px-5 py-3">
        <Button
          size="sm"
          disabled={panel.total === 0}
          onclick={() => {
            applyCategory = c;
            applyOpen = true;
          }}>Terapkan Nomor Urut…</Button
        >
        {#if panel.numbered > 0}
          <Button
            size="sm"
            variant="danger-ghost"
            onclick={() => {
              clearCategory = c;
              clearError = null;
              clearOpen = true;
            }}>Hapus semua Nomor Urut {CATEGORY_LABEL[c]}…</Button
          >
        {/if}
      </footer>
    </section>
  {/each}
</div>

{#key applyCategory}
  <ApplyNumbersDialog
    bind:open={applyOpen}
    eventId={data.event.id}
    category={applyCategory}
    onapplied={() => void invalidate('app:numbering')}
  />
{/key}

{#if clearCategory && clearPanel}
  <ConfirmDialog
    bind:open={clearOpen}
    title="Hapus {formatNumber(clearPanel.numbered)} Nomor Urut {CATEGORY_LABEL[clearCategory]}?"
    confirmLabel="Hapus Nomor Urut"
    busy={clearBusy}
    error={clearError}
    onconfirm={clearAll}
  >
    <p>
      Nomor Urut semua tamu {CATEGORY_LABEL[clearCategory]} dikosongkan dan tercatat di audit log. Tiket yang sudah tercetak
      tidak berubah.
    </p>
  </ConfirmDialog>
{/if}
