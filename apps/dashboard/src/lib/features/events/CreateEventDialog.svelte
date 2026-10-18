<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { eventFormSchema } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { errorSummary, fieldErrors } from '$lib/forms';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import ErrorSummary from '$lib/ui/ErrorSummary.svelte';
  import EventFields, { type EventFieldValues } from './EventFields.svelte';

  let { open = $bindable(false) }: { open: boolean } = $props();

  const empty = (): EventFieldValues => ({
    name: '',
    couple_names: '',
    event_date: '',
    venue: '',
    timezone: 'Asia/Jakarta',
  });
  let values = $state(empty());
  let errors = $state<Record<string, string>>({});
  let formError = $state<string | null>(null);
  let busy = $state(false);

  const summary = $derived([
    ...errorSummary(errors, ['name', 'couple_names', 'event_date', 'timezone', 'venue'], 'new-event-'),
    ...(formError ? [{ message: formError }] : []),
  ]);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    formError = null;
    const parsed = eventFormSchema.safeParse(values);
    errors = parsed.success ? {} : fieldErrors(parsed.error.issues);
    if (!parsed.success) return;

    busy = true;
    const v = parsed.data;
    const { data: id, error } = await supabase.rpc('admin_create_event', {
      p_name: v.name,
      p_event_date: v.event_date,
      p_couple_names: v.couple_names ?? undefined,
      p_venue: v.venue ?? undefined,
      p_timezone: v.timezone,
    });
    busy = false;
    if (error) {
      formError = dbErrorMessage(error);
      return;
    }
    toast.success(`Acara "${v.name}" dibuat.`);
    open = false;
    await goto(resolve(`/acara/${id}/tamu`));
  }
</script>

<Dialog
  bind:open
  title="Buat acara"
  description="Kode Acara dibuat otomatis dan bisa dibagikan ke usher."
  onclose={() => {
    values = empty();
    errors = {};
    formError = null;
  }}
>
  <form id="create-event-form" class="space-y-4" onsubmit={submit} novalidate>
    <ErrorSummary items={summary} />
    <EventFields bind:values {errors} idPrefix="new-event-" />
  </form>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (open = false)} disabled={busy}>Batal</Button>
    <Button type="submit" form="create-event-form" {busy}>{busy ? 'Membuat…' : 'Buat acara'}</Button>
  {/snippet}
</Dialog>
