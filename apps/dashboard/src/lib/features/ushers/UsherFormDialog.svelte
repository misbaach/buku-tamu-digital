<script lang="ts">
  import { USHER_MODE_LABEL, USHER_MODES, usherFormSchema, type UsherMode } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { fieldErrors } from '$lib/forms';
  import { supabase } from '$lib/supabase';
  import Button from '$lib/ui/Button.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';
  import Field from '$lib/ui/Field.svelte';
  import RadioGroup from '$lib/ui/RadioGroup.svelte';

  // FR-R-01: tambah/ubah Penerima Tamu. PIN dibuat server dan dikembalikan sekali lewat onsaved.
  interface Props {
    open: boolean;
    eventId: string;
    usher: { id: string; name: string; mode: UsherMode; is_active: boolean } | null;
    onsaved: (result: { name: string; pin?: string; revokedDevices?: number }) => void;
  }

  let { open = $bindable(false), eventId, usher, onsaved }: Props = $props();

  let name = $state('');
  let mode = $state<UsherMode>('check_in');
  let active = $state(true);
  let errors = $state<Record<string, string>>({});
  let formError = $state<string | null>(null);
  let busy = $state(false);

  $effect(() => {
    if (!open) return;
    name = usher?.name ?? '';
    mode = usher?.mode ?? 'check_in';
    active = usher?.is_active ?? true;
    errors = {};
    formError = null;
  });

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    if (busy) return;
    const parsed = usherFormSchema.safeParse({ name, mode });
    errors = parsed.success ? {} : fieldErrors(parsed.error.issues);
    if (!parsed.success) return;
    busy = true;
    formError = null;
    if (usher) {
      const { data, error } = await supabase.rpc('admin_update_usher', {
        p_usher_id: usher.id,
        p_patch: { name: parsed.data.name, mode: parsed.data.mode, is_active: active },
      });
      busy = false;
      if (error) return void (formError = dbErrorMessage(error));
      open = false;
      onsaved({ name: parsed.data.name, revokedDevices: (data as { revoked_devices: number }).revoked_devices });
    } else {
      const { data, error } = await supabase.rpc('admin_create_usher', {
        p_event_id: eventId,
        p_name: parsed.data.name,
        p_mode: parsed.data.mode,
      });
      busy = false;
      if (error) return void (formError = dbErrorMessage(error));
      open = false;
      onsaved({ name: parsed.data.name, pin: (data as { pin: string }).pin });
    }
  }
</script>

<Dialog bind:open title={usher ? `Ubah ${usher.name}` : 'Tambah penerima tamu'} size="sm">
  <form id="usher-form" class="space-y-5" onsubmit={submit} novalidate>
    {#if formError}
      <p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-sm">{formError}</p>
    {/if}
    <Field id="usher-name" label="Nama" bind:value={name} error={errors.name} maxlength={60} autocomplete="off" />
    <RadioGroup
      name="usher-mode"
      legend="Mode"
      options={USHER_MODES.map((m) => ({ value: m, label: USHER_MODE_LABEL[m] }))}
      bind:value={mode}
    />
    {#if mode === 'check_out'}
      <p class="text-sm text-ink-muted">
        Usher Check-Out sudah bisa masuk ke app, tetapi datanya baru diterima setelah mode Check-Out tersedia di App
        Penerima Tamu.
      </p>
    {/if}
    {#if usher}
      <label class="flex items-start gap-3">
        <input
          type="checkbox"
          bind:checked={active}
          class="mt-1 size-4 accent-ink"
          aria-describedby="usher-active-hint"
        />
        <span>
          <span class="font-medium">Aktif</span>
          <span id="usher-active-hint" class="block text-sm text-ink-muted">
            Menonaktifkan mencabut semua perangkat usher ini (tingkat Cabut). Data yang masih dikirim masuk karantina.
          </span>
        </span>
      </label>
    {/if}
  </form>
  {#snippet footer()}
    <Button variant="secondary" onclick={() => (open = false)} disabled={busy}>Batal</Button>
    <Button type="submit" form="usher-form" {busy}>{usher ? 'Simpan perubahan' : 'Tambah dan buat PIN'}</Button>
  {/snippet}
</Dialog>
