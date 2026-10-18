<script lang="ts">
  import Download from '@lucide/svelte/icons/download';
  import { dbErrorMessage } from '$lib/errors';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import type { GuestListRow } from './query';

  // FR-G-07: QR berisi token unik tamu (≥ 128 bit). Token hanya diambil saat tab ini dibuka, bukan di daftar tamu.
  let { guest }: { guest: GuestListRow } = $props();

  let png = $state<string | null>(null);
  let loadError = $state<string | null>(null);

  async function render() {
    const { data, error } = await supabase.from('guests').select('qr_token').eq('id', guest.id).single();
    if (error) {
      loadError = dbErrorMessage(error);
      return;
    }
    const QRCode = (await import('qrcode')).default;
    png = await QRCode.toDataURL(data.qr_token, { width: 768, margin: 2, errorCorrectionLevel: 'M' });
  }

  $effect(() => {
    void render();
  });

  const fileName = $derived(
    `QR-${guest.name
      .normalize('NFKD')
      .replace(/[^\w\s-]/g, '')
      .trim()
      .replace(/\s+/g, '-')
      .slice(0, 60)}${guest.special_number ? `-${guest.special_number}` : ''}.png`,
  );

  function download() {
    if (!png) return;
    const a = document.createElement('a');
    a.href = png;
    a.download = fileName;
    a.click();
    toast.success('QR diunduh.');
  }
</script>

{#if loadError}
  <p role="alert" class="text-sm text-danger">{loadError}</p>
{:else}
  <div class="flex flex-col items-start gap-4 sm:flex-row">
    <div class="grid size-56 shrink-0 place-items-center rounded-dialog border border-line bg-bg">
      {#if png}
        <img src={png} alt="QR check-in untuk {guest.name}" class="size-52" />
      {:else}
        <span class="text-sm text-ink-muted" aria-busy="true">Membuat QR…</span>
      {/if}
    </div>
    <div class="space-y-3 text-sm">
      <p>
        QR ini unik untuk <span class="font-medium">{guest.name}</span> dan dipindai usher saat check-in.
      </p>
      <p class="text-ink-muted">
        Bagikan hanya ke tamu yang bersangkutan. Perangkat usher tidak menyimpan isi QR, hanya sidik hash-nya.
      </p>
      <Button variant="secondary" onclick={download} disabled={!png}>
        <Download size={16} aria-hidden="true" />Unduh PNG
      </Button>
    </div>
  </div>
{/if}
