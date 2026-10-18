<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import { isAdminSession, loginErrorMessage, safeNextPath } from '$lib/auth';
  import { supabase } from '$lib/supabase';
  import Button from '$lib/ui/Button.svelte';
  import ErrorSummary, { type ErrorItem } from '$lib/ui/ErrorSummary.svelte';
  import Field from '$lib/ui/Field.svelte';

  let { data } = $props();

  const REASONS: Record<string, string> = {
    'bukan-admin': 'Akun itu bukan akun Admin. Dashboard ini hanya untuk Admin acara.',
  };

  let email = $state('');
  let password = $state('');
  let busy = $state(false);
  let fieldErrors = $state<{ email?: string; password?: string }>({});
  let formError = $state<string | null>(null);

  const summary = $derived<ErrorItem[]>([
    ...(fieldErrors.email ? [{ fieldId: 'email', message: fieldErrors.email }] : []),
    ...(fieldErrors.password ? [{ fieldId: 'password', message: fieldErrors.password }] : []),
    ...(formError ? [{ message: formError }] : []),
  ]);

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    formError = null;
    fieldErrors = {
      email: !email.trim()
        ? 'Isi email.'
        : !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
          ? 'Format email tidak valid.'
          : undefined,
      password: !password ? 'Isi kata sandi.' : undefined,
    };
    if (fieldErrors.email || fieldErrors.password) return;

    busy = true;
    const { data: result, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      busy = false;
      formError = loginErrorMessage(error);
      return;
    }
    if (!isAdminSession(result.session)) {
      await supabase.auth.signOut();
      busy = false;
      formError = REASONS['bukan-admin'] ?? null;
      return;
    }
    // Tujuan dinamis dari ?ke=, sudah dibatasi ke path internal oleh safeNextPath().
    // eslint-disable-next-line svelte/no-navigation-without-resolve
    await goto(safeNextPath(page.url.searchParams.get('ke')), { replaceState: true });
  }
</script>

<svelte:head>
  <title>Masuk · Buku Tamu Digital</title>
</svelte:head>

<main class="grid min-h-dvh place-items-center bg-surface px-4 py-10">
  <div class="w-full max-w-88">
    <p class="font-semibold tracking-tight">Buku Tamu Digital</p>

    <h1 class="mt-10 text-2xl font-semibold">Masuk</h1>
    <p class="mt-1 text-ink-muted">Dashboard untuk Admin acara.</p>

    {#if data.reason && REASONS[data.reason] && !formError}
      <p class="mt-4 rounded-control border border-warn bg-warn-bg px-3 py-2.5 text-sm" role="status">
        {REASONS[data.reason]}
      </p>
    {/if}

    <form class="mt-6 space-y-4 rounded-dialog border border-line bg-bg p-6" onsubmit={submit} novalidate>
      <ErrorSummary items={summary} />
      <Field
        id="email"
        label="Email"
        type="email"
        autocomplete="username"
        inputmode="email"
        spellcheck={false}
        bind:value={email}
        error={fieldErrors.email}
      />
      <Field
        id="password"
        label="Kata sandi"
        type="password"
        autocomplete="current-password"
        bind:value={password}
        error={fieldErrors.password}
      />
      <Button type="submit" full {busy}>{busy ? 'Memproses…' : 'Masuk'}</Button>
    </form>

    <p class="mt-4 text-sm text-ink-muted">Akun Admin dibuat oleh operator. Lupa kata sandi? Hubungi operator.</p>
  </div>
</main>
