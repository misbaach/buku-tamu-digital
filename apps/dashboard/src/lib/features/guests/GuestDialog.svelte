<script lang="ts">
  import Trash2 from '@lucide/svelte/icons/trash-2';
  import { dbErrorMessage } from '$lib/errors';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import Tabs from '$lib/ui/Tabs.svelte';
  import AttendancePanel from './AttendancePanel.svelte';
  import GuestForm from './GuestForm.svelte';
  import QrPanel from './QrPanel.svelte';
  import type { GuestListRow } from './query';

  interface Props {
    open: boolean;
    eventId: string;
    /** null = tambah tamu baru */
    guest: GuestListRow | null;
    groups: { id: string; name: string }[];
    initialTab?: 'data' | 'kehadiran' | 'qr';
    onchanged: () => void;
  }

  let { open = $bindable(false), eventId, guest, groups, initialTab = 'data', onchanged }: Props = $props();

  let tab = $state<string>('data');
  let busy = $state(false);
  let confirmDelete = $state(false);
  let deleting = $state(false);
  let deleteError = $state<string | null>(null);

  $effect(() => {
    if (open) tab = initialTab;
  });

  function saved(name: string, created: boolean) {
    toast.success(created ? `${name} ditambahkan.` : `Perubahan ${name} disimpan.`);
    onchanged();
    open = false;
  }

  async function remove() {
    if (!guest) return;
    deleting = true;
    deleteError = null;
    const { error } = await supabase.from('guests').update({ deleted_at: new Date().toISOString() }).eq('id', guest.id);
    deleting = false;
    if (error) {
      deleteError = dbErrorMessage(error);
      return;
    }
    toast.success(`${guest.name} dihapus.`);
    confirmDelete = false;
    open = false;
    onchanged();
  }
</script>

<Dialog bind:open title={guest ? guest.name : 'Tambah tamu'} size="lg">
  {#key guest?.id ?? 'baru'}
    {#if guest}
      <Tabs
        label="Detail tamu"
        tabs={[
          { id: 'data', label: 'Data' },
          { id: 'kehadiran', label: 'Kehadiran' },
          { id: 'qr', label: 'QR' },
        ]}
        bind:active={tab}
      >
        {#snippet panel(active)}
          {#if active === 'data'}
            <GuestForm formId="guest-form" {eventId} {guest} {groups} bind:busy onsaved={saved} />
          {:else if active === 'kehadiran'}
            <AttendancePanel {guest} {onchanged} />
          {:else}
            <QrPanel {guest} />
          {/if}
        {/snippet}
      </Tabs>
    {:else}
      <GuestForm formId="guest-form" {eventId} guest={null} {groups} bind:busy onsaved={saved} />
    {/if}
  {/key}

  {#snippet footer()}
    {#if guest && tab === 'data'}
      <Button variant="danger-ghost" class="mr-auto" onclick={() => (confirmDelete = true)} disabled={busy}>
        <Trash2 size={16} aria-hidden="true" />Hapus tamu
      </Button>
    {/if}
    {#if tab === 'data'}
      <Button variant="secondary" onclick={() => (open = false)} disabled={busy}>Batal</Button>
      <Button type="submit" form="guest-form" {busy}>
        {busy ? 'Menyimpan…' : guest ? 'Simpan perubahan' : 'Simpan tamu'}
      </Button>
    {:else}
      <Button variant="secondary" onclick={() => (open = false)}>Tutup</Button>
    {/if}
  {/snippet}
</Dialog>

{#if guest}
  <ConfirmDialog
    bind:open={confirmDelete}
    title="Hapus {guest.name}?"
    confirmLabel="Hapus tamu"
    busy={deleting}
    error={deleteError}
    onconfirm={remove}
  >
    <p>
      Tamu hilang dari daftar dan dari perangkat usher pada sinkronisasi berikutnya. Riwayat check-in yang sudah ada
      tetap tersimpan.
    </p>
  </ConfirmDialog>
{/if}
