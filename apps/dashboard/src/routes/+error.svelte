<script lang="ts">
  import { resolve } from '$app/paths';
  import { page } from '$app/state';

  const message = $derived(
    page.status === 404 ? 'Halaman tidak ditemukan.' : 'Terjadi kesalahan. Muat ulang halaman, lalu coba lagi.',
  );
</script>

<svelte:head>
  <title>{page.status} · Buku Tamu Digital</title>
</svelte:head>

<main class="mx-auto max-w-xl px-4 py-16">
  <p class="font-mono text-sm text-ink-muted">{page.status}</p>
  <h1 class="mt-2 text-2xl font-semibold">{message}</h1>
  <a href={resolve('/')} class="mt-6 inline-block underline underline-offset-2">Kembali ke daftar acara</a>
</main>
