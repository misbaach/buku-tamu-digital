<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { supabase } from '$lib/supabase';
  import Button from '$lib/ui/Button.svelte';

  let { data, children } = $props();
  let leaving = $state(false);

  async function logout() {
    leaving = true;
    await supabase.auth.signOut();
    await goto(resolve('/masuk'), { replaceState: true });
  }
</script>

<a
  href="#konten"
  class="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-control focus:bg-bg focus:px-3 focus:py-2"
>
  Lewati ke konten
</a>

<header class="border-b border-line bg-bg">
  <div class="mx-auto flex h-14 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
    <a href={resolve('/')} class="shrink-0 font-semibold tracking-tight whitespace-nowrap">Buku Tamu Digital</a>
    <div class="flex min-w-0 items-center gap-3 text-sm">
      <span class="hidden truncate text-ink-muted sm:block" title={data.email}>{data.email}</span>
      <Button variant="secondary" size="sm" onclick={logout} busy={leaving}>Keluar</Button>
    </div>
  </div>
</header>

<main id="konten" class="mx-auto max-w-6xl px-4 py-8 sm:px-6" tabindex="-1">
  {@render children()}
</main>
