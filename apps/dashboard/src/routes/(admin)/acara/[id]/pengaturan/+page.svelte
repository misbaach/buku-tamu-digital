<script lang="ts">
  import { invalidate, invalidateAll } from '$app/navigation';
  import { eventFormSchema } from '@guestbook/shared';
  import EventFields, { type EventFieldValues } from '$lib/features/events/EventFields.svelte';
  import { dbErrorMessage } from '$lib/errors';
  import { errorSummary, fieldErrors } from '$lib/forms';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import ConfirmDialog from '$lib/ui/ConfirmDialog.svelte';
  import ErrorSummary from '$lib/ui/ErrorSummary.svelte';

  let { data } = $props();

  // $state (bukan $derived yang bisa ditulis): objek ini di-bind per properti ke input, perlu proxy reaktif.
  // eslint-disable-next-line svelte/prefer-writable-derived
  let values = $state<EventFieldValues>({
    name: '',
    couple_names: '',
    event_date: '',
    venue: '',
    timezone: 'Asia/Jakarta',
  });
  $effect(() => {
    values = {
      name: data.event.name,
      couple_names: data.event.couple_names ?? '',
      event_date: data.event.event_date,
      venue: data.event.venue ?? '',
      timezone: data.event.timezone,
    };
  });
  let errors = $state<Record<string, string>>({});
  let formError = $state<string | null>(null);
  let busy = $state(false);

  const summary = $derived([
    ...errorSummary(errors, ['name', 'couple_names', 'event_date', 'timezone', 'venue'], 'event-'),
    ...(formError ? [{ message: formError }] : []),
  ]);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    formError = null;
    const parsed = eventFormSchema.safeParse(values);
    errors = parsed.success ? {} : fieldErrors(parsed.error.issues);
    if (!parsed.success) return;
    busy = true;
    const { error } = await supabase.rpc('admin_update_event', { p_event_id: data.event.id, p_patch: parsed.data });
    busy = false;
    if (error) {
      formError = dbErrorMessage(error);
      return;
    }
    toast.success('Pengaturan acara disimpan.');
    await invalidate('app:event');
  }

  let archiveOpen = $state(false);
  let archiveBusy = $state(false);
  let archiveError = $state<string | null>(null);

  async function archive() {
    archiveBusy = true;
    archiveError = null;
    const { error } = await supabase.rpc('admin_archive_event', { p_event_id: data.event.id });
    archiveBusy = false;
    if (error) {
      archiveError = dbErrorMessage(error);
      return;
    }
    toast.success(`Acara "${data.event.name}" diarsipkan.`);
    archiveOpen = false;
    await invalidateAll();
  }
</script>

<svelte:head>
  <title>Pengaturan · {data.event.name}</title>
</svelte:head>

<div class="max-w-2xl">
  <h2 class="text-xl font-semibold">Pengaturan acara</h2>

  <form class="mt-6 space-y-4" onsubmit={save} novalidate>
    <ErrorSummary items={summary} />
    <EventFields bind:values {errors} idPrefix="event-" />
    <div class="pt-2">
      <Button type="submit" {busy}>{busy ? 'Menyimpan…' : 'Simpan pengaturan'}</Button>
    </div>
  </form>

  <section class="mt-10 rounded-dialog border border-danger/40 p-5" aria-labelledby="archive-title">
    <h3 id="archive-title" class="font-semibold">Arsipkan acara</h3>
    {#if data.event.archived_at}
      <p class="mt-1 text-sm text-ink-muted">Acara ini sudah diarsipkan. Data tetap bisa dilihat.</p>
    {:else}
      <p class="mt-1 text-sm text-ink-muted">
        Setelah diarsipkan, semua perangkat usher berhenti menerima data dan tidak bisa mengirim check-in lagi. Data
        yang belum terkirim hanya bisa masuk lewat berkas ekspor yang diunggah Admin.
      </p>
      <Button variant="danger" class="mt-4" onclick={() => (archiveOpen = true)}>Arsipkan acara…</Button>
    {/if}
  </section>
</div>

<ConfirmDialog
  bind:open={archiveOpen}
  title="Arsipkan {data.event.name}?"
  confirmLabel="Arsipkan acara"
  busy={archiveBusy}
  error={archiveError}
  onconfirm={archive}
>
  <p>
    Setelah diarsipkan, perangkat usher tidak bisa mengirim data lagi. Data yang belum terkirim hanya bisa masuk lewat
    file ekspor. Pastikan semua perangkat sudah tersinkron. Tindakan ini tercatat di audit log dan tidak bisa dibatalkan
    dari dashboard.
  </p>
</ConfirmDialog>
