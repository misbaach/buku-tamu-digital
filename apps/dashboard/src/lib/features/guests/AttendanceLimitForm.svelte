<script lang="ts">
  import { invalidate } from '$app/navigation';
  import { attendanceLimitSchema } from '@guestbook/shared';
  import { dbErrorMessage } from '$lib/errors';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';

  // FR-S-01: batas opsional; kosong = total jumlah undangan (D14).
  let {
    eventId,
    limit,
    invitedTotal = null,
  }: { eventId: string; limit: number | null; invitedTotal?: number | null } = $props();
  // Nilai awal saja; setelah disimpan, nilai di input sudah sama dengan prop.
  // svelte-ignore state_referenced_locally
  let value = $state(limit == null ? '' : String(limit));
  let busy = $state(false);
  let error = $state<string | null>(null);

  async function save(event: SubmitEvent) {
    event.preventDefault();
    const parsed = attendanceLimitSchema.safeParse(value);
    if (!parsed.success) {
      error = parsed.error.issues[0]?.message ?? 'Nilai tidak valid.';
      return;
    }
    busy = true;
    error = null;
    const { error: dbError } = await supabase.rpc('admin_update_event', {
      p_event_id: eventId,
      p_patch: { attendance_limit: parsed.data },
    });
    busy = false;
    if (dbError) {
      error = dbErrorMessage(dbError);
      return;
    }
    toast.success(
      parsed.data == null ? 'Batas memakai total jumlah undangan.' : `Batas jumlah hadir: ${parsed.data} orang.`,
    );
    await invalidate('app:event');
  }
</script>

<form class="flex flex-wrap items-center gap-x-3 gap-y-2" onsubmit={save} novalidate>
  <label for="attendance-limit" class="text-sm font-medium">Batas jumlah hadir</label>
  <span class="flex items-center gap-2">
    <input
      id="attendance-limit"
      type="number"
      inputmode="numeric"
      min="1"
      bind:value
      aria-describedby="attendance-limit-hint{error ? ' attendance-limit-error' : ''}"
      aria-invalid={error ? 'true' : undefined}
      class={[
        'tabular h-8 w-24 rounded-control border bg-bg px-2 text-[0.9375rem]',
        error ? 'border-danger' : 'border-line-strong',
      ]}
    />
    <span class="text-sm text-ink-muted">orang</span>
  </span>
  <Button type="submit" variant="secondary" size="sm" {busy}>Simpan</Button>
  <p id="attendance-limit-hint" class="text-sm text-ink-muted">
    Dipakai untuk peringatan di Statistik. Kosongkan untuk memakai total undangan{invitedTotal !== null
      ? ` (${invitedTotal.toLocaleString('id-ID')} orang)`
      : ''}.
  </p>
  {#if error}<p id="attendance-limit-error" class="w-full text-sm text-danger">{error}</p>{/if}
</form>
