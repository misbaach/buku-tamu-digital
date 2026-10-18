<script lang="ts">
  import { CATEGORY_LABEL, CATEGORIES, type Category } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';

  // FR-G-05 (ubah grup/kategori massal) dan FR-C-05 (hapus Nomor Urut massal, diaudit lewat RPC).
  interface Props {
    eventId: string;
    ids: string[];
    groups: { id: string; name: string }[];
    onchanged: () => void;
    onclear: () => void;
  }

  let { eventId, ids, groups, onchanged, onclear }: Props = $props();
  let group = $state('');
  let category = $state<Category | ''>('');
  let busy = $state(false);
  let confirmClear = $state(false);
  let clearError = $state<string | null>(null);

  async function apply(patch: { group_id: string | null } | { category: Category }, message: string) {
    busy = true;
    const { error } = await supabase.from('guests').update(patch).in('id', ids).eq('event_id', eventId);
    busy = false;
    if (error) {
      toast.error(dbErrorMessage(error));
      return;
    }
    toast.success(message);
    onchanged();
  }

  async function clearNumbers() {
    busy = true;
    clearError = null;
    const { data, error } = await supabase.rpc('admin_clear_special_numbers', {
      p_event_id: eventId,
      p_guest_ids: ids,
    });
    busy = false;
    if (error) {
      clearError = dbErrorMessage(error);
      return;
    }
    confirmClear = false;
    toast.success(data === 0 ? 'Tidak ada Nomor Urut yang dihapus.' : `${formatNumber(data)} Nomor Urut dihapus.`);
    onchanged();
  }
</script>

<div
  role="region"
  aria-label="Aksi untuk tamu terpilih"
  class="sticky bottom-4 z-10 mt-4 flex flex-wrap items-center gap-x-4 gap-y-3 rounded-dialog border border-ink bg-bg px-4 py-3 shadow-lg"
>
  <p class="text-sm font-semibold"><span class="tabular">{formatNumber(ids.length)}</span> dipilih</p>

  <div class="flex items-center gap-2">
    <label for="bulk-group" class="sr-only">Grup baru</label>
    <select
      id="bulk-group"
      bind:value={group}
      class="h-8 cursor-pointer rounded-control border border-line-strong bg-bg px-2 text-sm"
    >
      <option value="" disabled>Pindah ke grup…</option>
      <option value="tanpa">Tanpa grup</option>
      {#each groups as g (g.id)}<option value={g.id}>{g.name}</option>{/each}
    </select>
    <Button
      size="sm"
      variant="secondary"
      disabled={!group || busy}
      onclick={() => apply({ group_id: group === 'tanpa' ? null : group }, 'Grup tamu terpilih diperbarui.')}
      >Terapkan</Button
    >
  </div>

  <div class="flex items-center gap-2">
    <label for="bulk-category" class="sr-only">Kategori baru</label>
    <select
      id="bulk-category"
      bind:value={category}
      class="h-8 cursor-pointer rounded-control border border-line-strong bg-bg px-2 text-sm"
    >
      <option value="" disabled>Ubah kategori…</option>
      {#each CATEGORIES as c (c)}<option value={c}>{CATEGORY_LABEL[c]}</option>{/each}
    </select>
    <Button
      size="sm"
      variant="secondary"
      disabled={!category || busy}
      onclick={() => category && apply({ category }, 'Kategori tamu terpilih diperbarui.')}>Terapkan</Button
    >
  </div>

  <Button size="sm" variant="danger-ghost" disabled={busy} onclick={() => (confirmClear = true)}>
    Hapus Nomor Urut
  </Button>
  <Button size="sm" variant="ghost" class="ml-auto" onclick={onclear}>Batal pilih</Button>
</div>

<ConfirmDialog
  bind:open={confirmClear}
  title="Hapus Nomor Urut {formatNumber(ids.length)} tamu?"
  confirmLabel="Hapus Nomor Urut"
  {busy}
  error={clearError}
  onconfirm={clearNumbers}
>
  <p>Nomor Urut khusus tamu terpilih dikosongkan dan tercatat di audit log. Tiket yang sudah tercetak tidak berubah.</p>
</ConfirmDialog>
