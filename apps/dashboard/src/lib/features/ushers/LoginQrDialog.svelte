<script lang="ts">
  import { untrack } from 'svelte';
  import QRCode from 'qrcode';
  import RefreshCw from '@lucide/svelte/icons/refresh-cw';
  import { dbErrorMessage } from '$lib/errors';
  import { supabase } from '$lib/supabase';
  import Button from '$lib/ui/Button.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';

  // FR-R-02: QR Login sekali pakai, berlaku 5 menit. Isi QR = token saja; server hanya menyimpan hash-nya.
  // Menekan "Buat QR baru" membatalkan QR sebelumnya.
  interface Props {
    open: boolean;
    usher: { id: string; name: string } | null;
  }

  let { open = $bindable(false), usher }: Props = $props();
  let image = $state<string | null>(null);
  let expiresAt = $state(0);
  let now = $state(Date.now());
  let busy = $state(false);
  let error = $state<string | null>(null);

  const remaining = $derived(Math.max(0, Math.ceil((expiresAt - now) / 1000)));
  const expired = $derived(image !== null && remaining === 0);
  const clock = $derived(`${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')}`);

  async function create() {
    if (!usher || busy) return;
    busy = true;
    error = null;
    const { data, error: dbError } = await supabase.rpc('admin_create_login_qr', { p_usher_id: usher.id });
    if (dbError) {
      busy = false;
      image = null;
      error = dbErrorMessage(dbError);
      return;
    }
    const result = data as { token: string; expires_at: string };
    image = await QRCode.toDataURL(result.token, { width: 560, margin: 2, errorCorrectionLevel: 'M' });
    expiresAt = new Date(result.expires_at).getTime();
    now = Date.now();
    busy = false;
  }

  $effect(() => {
    if (!open) {
      image = null;
      return;
    }
    // Hanya `open` yang dilacak; create() membaca busy/usher dan tidak boleh memicu efek ini lagi.
    untrack(() => void create());
    const timer = setInterval(() => (now = Date.now()), 1000);
    return () => clearInterval(timer);
  });
</script>

<Dialog bind:open title="QR Login · {usher?.name ?? ''}" size="sm">
  <div class="space-y-4 text-center">
    {#if error}
      <p role="alert" class="rounded-control border border-danger bg-danger-bg px-3 py-2 text-left text-sm">{error}</p>
    {:else if image && !expired}
      <img src={image} alt="QR Login untuk {usher?.name}" width="280" height="280" class="mx-auto size-70" />
      <p class="text-[0.9375rem]">
        Pindai dari layar masuk App Penerima Tamu. Berlaku <span class="tabular font-semibold" aria-live="off"
          >{clock}</span
        >
        lagi, sekali pakai.
      </p>
    {:else if expired}
      <p class="py-10 font-medium" role="status">QR kedaluwarsa. Buat QR baru bila masih dibutuhkan.</p>
    {:else}
      <p class="py-10 text-ink-muted" role="status">Membuat QR…</p>
    {/if}
  </div>
  {#snippet footer()}
    <Button variant="secondary" onclick={create} {busy}><RefreshCw size={16} aria-hidden="true" />Buat QR baru</Button>
    <Button onclick={() => (open = false)}>Selesai</Button>
  {/snippet}
</Dialog>
