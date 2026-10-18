<script lang="ts">
  import { CATEGORY_LABEL, guestFormSchema, type Category, type RsvpStatus } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { errorSummary, fieldErrors } from '$lib/forms';
  import { supabase } from '$lib/supabase';
  import CategoryIcon from '$lib/ui/CategoryIcon.svelte';
  import ErrorSummary from '$lib/ui/ErrorSummary.svelte';
  import Field from '$lib/ui/Field.svelte';
  import RadioGroup from '$lib/ui/RadioGroup.svelte';
  import SelectField from '$lib/ui/SelectField.svelte';
  import TextareaField from '$lib/ui/TextareaField.svelte';
  import type { GuestListRow } from './query';

  interface Props {
    formId: string;
    eventId: string;
    guest: GuestListRow | null;
    groups: { id: string; name: string }[];
    busy: boolean;
    onsaved: (name: string, created: boolean) => void;
  }

  let { formId, eventId, guest, groups, busy = $bindable(false), onsaved }: Props = $props();
  const p = $derived(`${formId}-`);

  // Nilai input selalu teks; Zod mengubahnya ke tipe yang disimpan. Form dipasang ulang per tamu ({#key}),
  // jadi cukup nilai awal dari prop.
  // svelte-ignore state_referenced_locally
  let values = $state({
    name: guest?.name ?? '',
    phone: guest?.phone ?? '',
    category: (guest?.category ?? 'regular') as Category,
    group_id: guest?.group_id ?? '',
    invited_pax: String(guest?.invited_pax ?? 1),
    special_number: guest?.special_number ?? '',
    rsvp_status: (guest?.rsvp_status ?? 'unconfirmed') as RsvpStatus,
    rsvp_pax: guest?.rsvp_pax == null ? '' : String(guest.rsvp_pax),
    notes: guest?.notes ?? '',
  });
  let errors = $state<Record<string, string>>({});
  let formError = $state<string | null>(null);

  const order = [
    'name',
    'category',
    'phone',
    'group_id',
    'invited_pax',
    'special_number',
    'rsvp_status',
    'rsvp_pax',
    'notes',
  ];
  const summary = $derived([...errorSummary(errors, order, p), ...(formError ? [{ message: formError }] : [])]);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (busy) return; // Enter berulang saat menyimpan tidak mengirim dua kali
    formError = null;
    const parsed = guestFormSchema.safeParse(values);
    errors = parsed.success ? {} : fieldErrors(parsed.error.issues);
    if (!parsed.success) return;

    busy = true;
    const row = parsed.data;
    const { error } = guest
      ? await supabase.from('guests').update(row).eq('id', guest.id)
      : await supabase.from('guests').insert({ ...row, event_id: eventId });
    busy = false;
    if (error) {
      const message = dbErrorMessage(error);
      // Nomor Urut ganda adalah galat yang paling mungkin; arahkan ke field-nya.
      if (message.startsWith('Nomor Urut')) errors = { special_number: message };
      else formError = message;
      return;
    }
    onsaved(row.name, !guest);
  }
</script>

<form id={formId} class="space-y-4" onsubmit={submit} novalidate>
  <ErrorSummary items={summary} />
  <Field id="{p}name" label="Nama" bind:value={values.name} error={errors.name} maxlength={120} autocomplete="off" />
  <RadioGroup
    name="{p}category"
    legend="Kategori"
    options={(['regular', 'vip', 'vvip'] as const).map((c) => ({ value: c, label: CATEGORY_LABEL[c] }))}
    bind:value={values.category}
    error={errors.category}
  >
    {#snippet icon(c)}<CategoryIcon category={c} size={14} withText />{/snippet}
  </RadioGroup>
  <div class="grid gap-4 sm:grid-cols-2">
    <Field
      id="{p}phone"
      label="Telepon (opsional)"
      type="tel"
      inputmode="tel"
      bind:value={values.phone}
      error={errors.phone}
      autocomplete="off"
    />
    <SelectField
      id="{p}group_id"
      label="Grup"
      options={[{ value: '', label: 'Tanpa grup' }, ...groups.map((g) => ({ value: g.id, label: g.name }))]}
      bind:value={values.group_id}
      error={errors.group_id}
    />
    <Field
      id="{p}invited_pax"
      label="Jumlah undangan"
      type="number"
      inputmode="numeric"
      min={1}
      max={50}
      bind:value={values.invited_pax}
      error={errors.invited_pax}
    />
    <Field
      id="{p}special_number"
      label="Nomor Urut (opsional)"
      class="[&_input]:font-mono [&_input]:uppercase"
      bind:value={values.special_number}
      error={errors.special_number}
      hint="Contoh: VIP-007. Pola seperti A-017 dipakai nomor perangkat, jadi tidak bisa dipakai."
      maxlength={20}
      autocomplete="off"
    />
  </div>
  <RadioGroup
    name="{p}rsvp_status"
    legend="Status RSVP"
    options={[
      { value: 'going', label: 'Akan hadir' },
      { value: 'not_going', label: 'Tidak hadir' },
      { value: 'unconfirmed', label: 'Belum konfirmasi' },
    ]}
    bind:value={values.rsvp_status}
    error={errors.rsvp_status}
  />
  {#if values.rsvp_status === 'going'}
    <Field
      id="{p}rsvp_pax"
      label="Jumlah orang yang akan hadir"
      type="number"
      inputmode="numeric"
      min={0}
      max={50}
      class="sm:max-w-56"
      bind:value={values.rsvp_pax}
      error={errors.rsvp_pax}
    />
  {/if}
  <TextareaField
    id="{p}notes"
    label="Catatan (opsional)"
    rows={2}
    maxlength={500}
    bind:value={values.notes}
    error={errors.notes}
    hint="Tidak pernah dikirim ke perangkat usher."
  />
</form>
