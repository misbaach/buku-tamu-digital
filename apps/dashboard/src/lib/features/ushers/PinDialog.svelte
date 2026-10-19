<script lang="ts">
  import Button from '$lib/ui/Button.svelte';
  import Dialog from '$lib/ui/Dialog.svelte';

  // FR-R-02: PIN lengkap hanya ditampilkan sekali; dialog baru bisa ditutup setelah Admin menyatakan sudah mencatat.
  interface Props {
    open: boolean;
    pin: string;
    eventCode: string;
    usherName: string;
  }

  let { open = $bindable(false), pin, eventCode, usherName }: Props = $props();
  let noted = $state(false);

  $effect(() => {
    if (open) noted = false;
  });
</script>

<Dialog bind:open title="PIN untuk {usherName}" size="sm" dismissible={false}>
  <div class="space-y-4">
    <p
      class="rounded-dialog border border-line-strong bg-surface py-5 text-center font-mono text-3xl font-semibold tracking-[0.12em]"
      aria-label="PIN {pin.split('').join(' ')}"
    >
      {pin}
    </p>
    <p class="text-[0.9375rem]">
      Usher memasukkan Kode Acara <span class="font-mono font-semibold">{eventCode}</span> dan PIN ini.
      <strong>PIN hanya ditampilkan sekali.</strong> Bila lupa, buat PIN baru lewat "Reset PIN".
    </p>
    <label class="flex items-center gap-3 font-medium">
      <input type="checkbox" bind:checked={noted} class="size-4 accent-ink" />
      Saya sudah mencatat PIN
    </label>
  </div>
  {#snippet footer()}
    <Button disabled={!noted} onclick={() => (open = false)}>Tutup</Button>
  {/snippet}
</Dialog>
