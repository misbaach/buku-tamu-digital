<script lang="ts" module>
  export interface EventFieldValues {
    name: string;
    couple_names: string;
    event_date: string;
    venue: string;
    timezone: string;
  }
</script>

<script lang="ts">
  import { EVENT_TIMEZONES } from '@guestbook/shared';
  import Field from '$lib/ui/Field.svelte';
  import SelectField from '$lib/ui/SelectField.svelte';

  let {
    values = $bindable(),
    errors,
    idPrefix,
  }: { values: EventFieldValues; errors: Record<string, string>; idPrefix: string } = $props();
</script>

<div class="space-y-4">
  <Field
    id="{idPrefix}name"
    label="Nama acara"
    bind:value={values.name}
    error={errors.name}
    maxlength={120}
    placeholder="Resepsi Rina & Bayu"
  />
  <Field
    id="{idPrefix}couple_names"
    label="Nama mempelai (opsional)"
    bind:value={values.couple_names}
    error={errors.couple_names}
    maxlength={200}
  />
  <div class="grid gap-4 sm:grid-cols-2">
    <Field
      id="{idPrefix}event_date"
      label="Tanggal acara"
      type="date"
      bind:value={values.event_date}
      error={errors.event_date}
    />
    <SelectField
      id="{idPrefix}timezone"
      label="Zona waktu"
      options={EVENT_TIMEZONES.map((t) => ({ value: t.value, label: t.label }))}
      bind:value={values.timezone}
      error={errors.timezone}
      hint="Dipakai untuk mengakhiri sesi usher pukul 06.00 keesokan harinya."
    />
  </div>
  <Field
    id="{idPrefix}venue"
    label="Tempat (opsional)"
    bind:value={values.venue}
    error={errors.venue}
    maxlength={200}
  />
</div>
