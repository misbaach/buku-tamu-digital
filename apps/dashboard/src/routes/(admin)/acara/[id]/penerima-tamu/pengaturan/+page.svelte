<script lang="ts">
  import { invalidate } from '$app/navigation';
  import { resolve } from '$app/paths';
  import ArrowLeft from '@lucide/svelte/icons/arrow-left';
  import Lock from '@lucide/svelte/icons/lock';
  import {
    CATEGORIES,
    CATEGORY_LABEL,
    PRINT_TICKET_FIELDS,
    PRINT_TICKET_FIELD_LABEL,
    PRINT_TICKET_MAX_COPIES,
    checkinSettingsSchema,
    type Category,
    type PrintTicketField,
  } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { formatEventDate } from '$lib/format';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import SelectField from '$lib/ui/SelectField.svelte';
  import Switch from '$lib/ui/Switch.svelte';

  let { data } = $props();

  // Form dipasang per acara; nilai awal dari server, lalu dimiliki form sampai disimpan.
  // svelte-ignore state_referenced_locally
  let showVerification = $state(data.settings.show_verification);
  // svelte-ignore state_referenced_locally
  let allowMulti = $state(data.settings.allow_multi_checkin);
  // svelte-ignore state_referenced_locally
  let ticket = $state(structuredClone(data.settings.print_ticket));
  let copies = $derived(String(ticket.copies));
  let errors = $state<Record<string, string>>({});
  let busy = $state(false);

  function toggle<T>(list: T[], value: T, on: boolean): T[] {
    return on ? [...list.filter((v) => v !== value), value] : list.filter((v) => v !== value);
  }
  // Urutan cetak mengikuti urutan baku, bukan urutan klik.
  const orderedFields = $derived(PRINT_TICKET_FIELDS.filter((f) => ticket.fields.includes(f)));

  const sample: Record<PrintTicketField, string> = $derived({
    event_name: data.event.name,
    couple_names: data.event.couple_names ?? 'Nama mempelai',
    event_date: formatEventDate(data.event.event_date),
    guest_name: 'Budi Santoso',
    category: 'VIP',
    group_name: 'Keluarga',
    ticket_number: 'VIP-007',
    pax: '2 orang',
    checked_in_at: '19.05',
  });

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (busy) return;
    const parsed = checkinSettingsSchema.safeParse({
      show_verification: showVerification,
      allow_multi_checkin: allowMulti,
      print_ticket: { ...ticket, fields: orderedFields, copies: Number(copies) },
    });
    errors = {};
    if (!parsed.success) {
      for (const issue of parsed.error.issues) errors[String(issue.path.at(-1))] ??= issue.message;
      return;
    }
    busy = true;
    const { error } = await supabase.from('checkin_settings').update(parsed.data).eq('event_id', data.event.id);
    busy = false;
    if (error) return void toast.error(dbErrorMessage(error));
    toast.success('Pengaturan check-in disimpan. Perangkat usher menerimanya saat sinkronisasi berikutnya.');
    await invalidate('app:checkin-settings');
  }
</script>

<svelte:head>
  <title>Pengaturan check-in · {data.event.name}</title>
</svelte:head>

<a
  href={resolve(`/acara/${data.event.id}/penerima-tamu`)}
  class="inline-flex items-center gap-1 text-sm text-ink-muted hover:text-ink"
>
  <ArrowLeft size={14} aria-hidden="true" />Penerima Tamu
</a>
<h2 class="mt-2 text-xl font-semibold">Pengaturan check-in</h2>
<p class="mt-1 text-sm text-ink-muted">Berlaku untuk semua perangkat usher acara ini.</p>

<form class="mt-6 grid gap-8 lg:grid-cols-[minmax(0,1fr)_18rem]" onsubmit={save} novalidate>
  <div class="space-y-8">
    <section aria-labelledby="process-heading">
      <h3 id="process-heading" class="text-lg font-semibold">Proses check-in</h3>
      <div class="mt-2 divide-y divide-line border-y border-line">
        <Switch
          id="show-verification"
          label="Tampilkan Verifikasi Tamu"
          description="Usher memeriksa nama, kategori, dan jumlah orang sebelum menyimpan check-in tamu Regular."
          bind:checked={showVerification}
        />
        <div class="flex items-start justify-between gap-6 py-3">
          <div>
            <p class="font-medium">Verifikasi VIP & VVIP</p>
            <p class="mt-0.5 text-sm text-ink-muted">
              Selalu aktif agar QR yang diteruskan ke orang lain tetap terperiksa.
            </p>
          </div>
          <span class="inline-flex shrink-0 items-center gap-1 text-sm text-ink-muted"
            ><Lock size={14} aria-hidden="true" />Selalu aktif</span
          >
        </div>
        <Switch
          id="allow-multi"
          label="Tamu Check-In Lebih 1 Kali"
          description="Aktif: check-in berikutnya tercatat Masuk ulang dan tidak menambah jumlah orang. Nonaktif: tercatat Ganda — tinjau."
          bind:checked={allowMulti}
        />
      </div>
    </section>

    <section aria-labelledby="ticket-heading">
      <h3 id="ticket-heading" class="text-lg font-semibold">Print Tiket Penomoran</h3>
      <div class="mt-2 border-t border-line">
        <Switch
          id="ticket-enabled"
          label="Cetak tiket saat check-in"
          description="Tiket berisi nomor urut untuk pengambilan souvenir atau tempat duduk."
          bind:checked={ticket.enabled}
        />
      </div>
      {#if ticket.enabled}
        <div class="mt-4 grid gap-6 sm:grid-cols-2">
          <fieldset aria-describedby={errors.fields ? 'fields-error' : undefined}>
            <legend class="text-sm font-medium">Informasi di tiket</legend>
            <div class="mt-2 space-y-2">
              {#each PRINT_TICKET_FIELDS as field (field)}
                <label class="flex items-center gap-2.5">
                  <input
                    type="checkbox"
                    class="size-4 accent-ink"
                    checked={ticket.fields.includes(field)}
                    onchange={(e) => (ticket.fields = toggle(ticket.fields, field, e.currentTarget.checked))}
                  />
                  {PRINT_TICKET_FIELD_LABEL[field]}
                </label>
              {/each}
            </div>
            {#if errors.fields}<p id="fields-error" class="mt-2 text-sm text-danger">{errors.fields}</p>{/if}
          </fieldset>
          <div class="space-y-6">
            <fieldset aria-describedby={errors.categories ? 'categories-error' : undefined}>
              <legend class="text-sm font-medium">Kategori yang mendapat tiket</legend>
              <div class="mt-2 space-y-2">
                {#each CATEGORIES as category (category)}
                  <label class="flex items-center gap-2.5">
                    <input
                      type="checkbox"
                      class="size-4 accent-ink"
                      checked={ticket.categories.includes(category)}
                      onchange={(e) =>
                        (ticket.categories = toggle<Category>(ticket.categories, category, e.currentTarget.checked))}
                    />
                    {CATEGORY_LABEL[category]}
                  </label>
                {/each}
              </div>
              {#if errors.categories}<p id="categories-error" class="mt-2 text-sm text-danger">
                  {errors.categories}
                </p>{/if}
            </fieldset>
            <SelectField
              id="ticket-copies"
              label="Jumlah salinan"
              bind:value={copies}
              error={errors.copies}
              options={Array.from({ length: PRINT_TICKET_MAX_COPIES }, (_, i) => ({
                value: String(i + 1),
                label: `${i + 1} salinan`,
              }))}
            />
          </div>
        </div>
      {/if}
    </section>

    <div class="flex gap-2">
      <Button type="submit" {busy}>Simpan pengaturan</Button>
    </div>
  </div>

  {#if ticket.enabled}
    <aside aria-label="Pratinjau tiket" class="lg:sticky lg:top-6 lg:self-start">
      <p class="text-sm font-medium text-ink-muted">Pratinjau tiket (contoh)</p>
      <div class="mt-2 w-full max-w-[16rem] border border-dashed border-line-strong bg-bg px-4 py-4 font-mono text-sm">
        {#each orderedFields as field (field)}
          <p class={field === 'ticket_number' ? 'my-2 text-center text-2xl font-semibold' : 'leading-6'}>
            {sample[field]}
          </p>
        {:else}
          <p class="text-ink-muted">Pilih informasi yang dicetak.</p>
        {/each}
      </div>
    </aside>
  {/if}
</form>
