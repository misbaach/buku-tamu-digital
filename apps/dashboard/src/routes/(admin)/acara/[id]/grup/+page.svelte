<script lang="ts">
  import { invalidate } from '$app/navigation';
  import Plus from '@lucide/svelte/icons/plus';
  import { dbErrorMessage } from '$lib/errors';
  import { formatNumber } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import EmptyState from '$lib/ui/EmptyState.svelte';
  import Field from '$lib/ui/Field.svelte';
  import TextareaField from '$lib/ui/TextareaField.svelte';

  let { data } = $props();
  type Group = (typeof data.groups)[number];

  // --- Tambah / ubah ---
  let formOpen = $state(false);
  let editing = $state<Group | null>(null);
  let name = $state('');
  let description = $state('');
  let nameError = $state<string | null>(null);
  let formError = $state<string | null>(null);
  let busy = $state(false);

  function openForm(group: Group | null) {
    editing = group;
    name = group?.name ?? '';
    description = group?.description ?? '';
    nameError = null;
    formError = null;
    formOpen = true;
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const n = name.trim();
    const d = description.trim();
    nameError = !n ? 'Isi nama grup.' : n.length > 80 ? 'Nama grup maksimal 80 karakter.' : null;
    if (nameError) return;
    busy = true;
    formError = null;
    const payload = { name: n, description: d || null };
    const { error } = editing
      ? await supabase.from('guest_groups').update(payload).eq('id', editing.id)
      : await supabase.from('guest_groups').insert({ ...payload, event_id: data.event.id });
    busy = false;
    if (error) {
      const message = dbErrorMessage(error);
      if (message.startsWith('Nama grup')) nameError = message;
      else formError = message;
      return;
    }
    toast.success(editing ? `Grup "${n}" disimpan.` : `Grup "${n}" ditambahkan.`);
    formOpen = false;
    await invalidate('app:groups');
  }

  // --- Hapus ---
  let removing = $state<Group | null>(null);
  let confirmOpen = $state(false);
  let removeBusy = $state(false);
  let removeError = $state<string | null>(null);

  async function remove() {
    if (!removing) return;
    removeBusy = true;
    removeError = null;
    const { error } = await supabase
      .from('guest_groups')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', removing.id);
    removeBusy = false;
    if (error) {
      removeError = dbErrorMessage(error);
      return;
    }
    toast.success(`Grup "${removing.name}" dihapus.`);
    confirmOpen = false;
    await invalidate('app:groups');
  }
</script>

<svelte:head>
  <title>Grup · {data.event.name}</title>
</svelte:head>

<div class="flex flex-wrap items-end justify-between gap-4">
  <div>
    <h2 class="text-xl font-semibold">Grup tamu</h2>
    <p class="mt-1 text-sm text-ink-muted">Kelompokkan tamu, mis. keluarga mempelai atau teman kantor.</p>
  </div>
  <Button onclick={() => openForm(null)}><Plus size={16} aria-hidden="true" />Tambah grup</Button>
</div>

<div class="mt-6">
  {#if data.groups.length === 0}
    <EmptyState title="Belum ada grup.">
      Grup juga dibuat otomatis saat impor tamu bila kolom Grup diisi.
      {#snippet actions()}
        <Button onclick={() => openForm(null)}><Plus size={16} aria-hidden="true" />Tambah grup</Button>
      {/snippet}
    </EmptyState>
  {:else}
    <div class="overflow-x-auto rounded-dialog border border-line">
      <table class="w-full min-w-xl text-left text-sm">
        <thead class="bg-surface text-ink-muted">
          <tr>
            <th scope="col" class="px-4 py-2.5 font-medium">Nama grup</th>
            <th scope="col" class="px-4 py-2.5 font-medium">Deskripsi</th>
            <th scope="col" class="px-4 py-2.5 text-right font-medium">Anggota</th>
            <th scope="col" class="px-4 py-2.5 font-medium"><span class="sr-only">Aksi</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          {#each data.groups as group (group.id)}
            <tr class="hover:bg-surface">
              <td class="px-4 py-3 font-medium">{group.name}</td>
              <td class="px-4 py-3 text-ink-muted">{group.description ?? '—'}</td>
              <td class="tabular px-4 py-3 text-right">{formatNumber(group.members)}</td>
              <td class="px-4 py-2">
                <div class="flex justify-end gap-1">
                  <Button size="sm" variant="ghost" onclick={() => openForm(group)} aria-label="Ubah grup {group.name}"
                    >Ubah</Button
                  >
                  <Button
                    size="sm"
                    variant="danger-ghost"
                    aria-label="Hapus grup {group.name}"
                    onclick={() => {
                      removing = group;
                      removeError = null;
                      confirmOpen = true;
                    }}>Hapus</Button
                  >
                </div>
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>

<Dialog bind:open={formOpen} title={editing ? `Ubah grup ${editing.name}` : 'Tambah grup'} size="sm">
  <form id="group-form" class="space-y-4" onsubmit={save} novalidate>
    {#if formError}<p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-sm">
        {formError}
      </p>{/if}
    <Field id="group-name" label="Nama grup" bind:value={name} error={nameError} maxlength={80} autocomplete="off" />
    <TextareaField
      id="group-description"
      label="Deskripsi (opsional)"
      rows={2}
      maxlength={300}
      bind:value={description}
    />
  </form>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (formOpen = false)} disabled={busy}>Batal</Button>
    <Button type="submit" form="group-form" {busy}>{busy ? 'Menyimpan…' : 'Simpan grup'}</Button>
  {/snippet}
</Dialog>

{#if removing}
  <ConfirmDialog
    bind:open={confirmOpen}
    title="Hapus grup {removing.name}?"
    confirmLabel="Hapus grup"
    busy={removeBusy}
    error={removeError}
    onconfirm={remove}
  >
    <p>
      {#if removing.members > 0}
        {formatNumber(removing.members)} tamu di grup ini akan menjadi tanpa grup. Data tamunya tidak dihapus.
      {:else}
        Grup ini tidak punya anggota.
      {/if}
    </p>
  </ConfirmDialog>
{/if}
