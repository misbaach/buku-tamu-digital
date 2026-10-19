<script lang="ts">
  import { invalidate } from '$app/navigation';
  import ImagePlus from '@lucide/svelte/icons/image-plus';
  import {
    CATEGORIES,
    CATEGORY_LABEL,
    GREETING_BODY_MAX,
    GREETING_DEFAULTS,
    GREETING_LAYOUTS,
    GREETING_LAYOUT_LABEL,
    GREETING_TITLE_MAX,
    UPLOAD_MIME,
    greetingFormSchema,
    type Category,
    type GreetingLayout,
    type GreetingPopup,
  } from '@guestbook/shared';
  import GreetingPreview from '$lib/features/greeting/GreetingPreview.svelte';
  import { PhotoError, removeGreetingPhoto, signedPhotoUrl, uploadGreetingPhoto } from '$lib/features/greeting/photo';
  import { dbErrorMessage } from '$lib/errors';
  import { fieldErrors } from '$lib/forms';
  import { supabase } from '$lib/supabase';
  import { toast } from '$lib/toast.svelte';
  import Button from '$lib/ui/Button.svelte';
  import Field from '$lib/ui/Field.svelte';
  import RadioGroup from '$lib/ui/RadioGroup.svelte';
  import Tabs from '$lib/ui/Tabs.svelte';
  import TextareaField from '$lib/ui/TextareaField.svelte';

  let { data } = $props();

  interface Form {
    title: string;
    body: string;
    layout: GreetingLayout;
    photoPath: string | null;
    photoVersion: number;
    photoUrl: string | null;
  }

  function fromPopup(category: Category, p: GreetingPopup | undefined): Form {
    const d = GREETING_DEFAULTS[category];
    return {
      title: p?.title ?? d.title,
      body: p?.body ?? d.body,
      layout: p?.layout ?? d.layout,
      photoPath: p?.photo_path ?? null,
      photoVersion: p?.photo_version ?? 0,
      photoUrl: null,
    };
  }

  // Editor dimiliki halaman ini sampai disimpan; nilai awal dari server (bawaan bila belum diatur).
  const forms = $state(
    Object.fromEntries(CATEGORIES.map((c) => [c, fromPopup(c, data.popups[c])])) as Record<Category, Form>,
  );
  let active = $state<Category>('regular');
  let sampleName = $state('Budi Santoso');
  let errors = $state<Record<string, string>>({});
  let busy = $state(false);
  let photoBusy = $state(false);
  let photoError = $state<string | null>(null);

  const form = $derived(forms[active]);
  const saved = $derived(fromPopup(active, data.popups[active]));
  const dirty = $derived(form.title !== saved.title || form.body !== saved.body || form.layout !== saved.layout);

  // Pratinjau foto lewat signed URL berumur pendek (bucket privat).
  $effect(() => {
    for (const c of CATEGORIES) {
      const f = forms[c];
      if (f.photoPath && !f.photoUrl) void signedPhotoUrl(f.photoPath).then((url) => (forms[c].photoUrl = url));
    }
  });

  function insertVariable(name: string) {
    const el = document.getElementById(`greeting-body-${active}`) as HTMLTextAreaElement | null;
    const token = `{{${name}}}`;
    const start = el?.selectionStart ?? form.body.length;
    const end = el?.selectionEnd ?? form.body.length;
    form.body = form.body.slice(0, start) + token + form.body.slice(end);
    queueMicrotask(() => {
      el?.focus();
      el?.setSelectionRange(start + token.length, start + token.length);
    });
  }

  function popupOf(f: Form): GreetingPopup {
    return {
      title: f.title.trim(),
      body: f.body.trim(),
      layout: f.layout,
      photo_path: f.photoPath,
      photo_version: f.photoVersion,
    };
  }

  async function writePopup(category: Category, popup: GreetingPopup) {
    return supabase
      .from('greeting_configs')
      .update({ popup: { ...popup } })
      .eq('event_id', data.event.id)
      .eq('category', category);
  }

  async function save(event: SubmitEvent) {
    event.preventDefault();
    if (busy) return;
    const parsed = greetingFormSchema.safeParse(form);
    errors = parsed.success ? {} : fieldErrors(parsed.error.issues);
    if (!parsed.success) return;
    busy = true;
    const { error } = await writePopup(active, popupOf({ ...form, ...parsed.data }));
    busy = false;
    if (error) return void toast.error(dbErrorMessage(error));
    toast.success(`Sapaan ${CATEGORY_LABEL[active]} disimpan.`);
    await invalidate('app:greetings');
  }

  // Foto langsung tersimpan setelah diunggah; teks tetap menunggu tombol Simpan.
  async function changePhoto(file: File | undefined) {
    if (!file || photoBusy) return;
    const category = active;
    photoBusy = true;
    photoError = null;
    try {
      const old = forms[category].photoPath;
      const path = await uploadGreetingPhoto(data.event.id, category, file);
      const next = {
        ...popupOf(fromPopup(category, data.popups[category])),
        photo_path: path,
        photo_version: forms[category].photoVersion + 1,
      };
      const { error } = await writePopup(category, next);
      if (error) {
        await removeGreetingPhoto(path);
        throw new PhotoError(dbErrorMessage(error));
      }
      if (old) await removeGreetingPhoto(old);
      forms[category].photoPath = path;
      forms[category].photoVersion = next.photo_version;
      forms[category].photoUrl = null;
      toast.success(`Foto sapaan ${CATEGORY_LABEL[category]} disimpan.`);
      await invalidate('app:greetings');
    } catch (e) {
      photoError = e instanceof PhotoError ? e.message : 'Foto gagal diunggah. Coba lagi.';
    } finally {
      photoBusy = false;
    }
  }

  async function removePhoto() {
    const category = active;
    const old = forms[category].photoPath;
    if (!old || photoBusy) return;
    photoBusy = true;
    photoError = null;
    const next = {
      ...popupOf(fromPopup(category, data.popups[category])),
      photo_path: null,
      photo_version: forms[category].photoVersion + 1,
    };
    const { error } = await writePopup(category, next);
    photoBusy = false;
    if (error) return void (photoError = dbErrorMessage(error));
    await removeGreetingPhoto(old);
    forms[category].photoPath = null;
    forms[category].photoVersion = next.photo_version;
    forms[category].photoUrl = null;
    toast.success(`Foto sapaan ${CATEGORY_LABEL[category]} dihapus.`);
    await invalidate('app:greetings');
  }
</script>

<svelte:head>
  <title>Sapaan · {data.event.name}</title>
</svelte:head>

<h2 class="text-xl font-semibold">Pop-up sapaan</h2>
<p class="mt-1 text-sm text-ink-muted">
  Tampil di HP usher setelah check-in berhasil. Setiap kategori punya tampilan sendiri.
</p>

<div class="mt-5">
  <Tabs
    label="Kategori sapaan"
    tabs={CATEGORIES.map((c) => ({ id: c, label: CATEGORY_LABEL[c] }))}
    bind:active={() => active, (v) => (active = v as Category)}
  >
    {#snippet panel(id)}
      {@const category = id as Category}
      <div class="grid gap-8 pt-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <form class="space-y-5" onsubmit={save} novalidate>
          <Field
            id="greeting-title-{category}"
            label="Judul"
            bind:value={forms[category].title}
            error={errors.title}
            maxlength={GREETING_TITLE_MAX}
            hint="Contoh: Selamat datang, {'{{nama}}'}"
          />
          <div class="space-y-2">
            <TextareaField
              id="greeting-body-{category}"
              label="Teks"
              bind:value={forms[category].body}
              error={errors.body}
              rows={3}
              maxlength={GREETING_BODY_MAX}
              hint="{forms[category].body.length}/{GREETING_BODY_MAX} karakter"
            />
            <div class="flex flex-wrap items-center gap-2 text-sm">
              <span class="text-ink-muted">Sisipkan:</span>
              <Button size="sm" variant="secondary" onclick={() => insertVariable('nama')}>{'{{nama}}'}</Button>
              <Button size="sm" variant="secondary" onclick={() => insertVariable('kategori')}>{'{{kategori}}'}</Button>
            </div>
          </div>
          <RadioGroup
            name="greeting-layout-{category}"
            legend="Tampilan"
            options={GREETING_LAYOUTS.map((l) => ({ value: l, label: GREETING_LAYOUT_LABEL[l] }))}
            bind:value={forms[category].layout}
          />

          <fieldset class="space-y-2">
            <legend class="text-sm font-medium">Foto</legend>
            <p class="text-sm text-ink-muted">
              PNG, JPEG, atau WebP, maksimal 5 MB. Foto langsung tersimpan setelah diunggah.
            </p>
            <div class="flex flex-wrap items-center gap-2">
              <label
                class="inline-flex h-10 cursor-pointer items-center gap-2 rounded-control border border-line-strong bg-bg px-4 text-[0.9375rem] font-medium hover:bg-surface has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-focus"
              >
                <ImagePlus size={16} aria-hidden="true" />{forms[category].photoPath ? 'Ganti foto' : 'Unggah foto'}
                <input
                  type="file"
                  class="sr-only"
                  accept={UPLOAD_MIME.join(',')}
                  disabled={photoBusy}
                  onchange={(e) => {
                    void changePhoto(e.currentTarget.files?.[0]);
                    e.currentTarget.value = '';
                  }}
                />
              </label>
              {#if forms[category].photoPath}
                <Button variant="danger-ghost" onclick={removePhoto} busy={photoBusy}>Hapus foto</Button>
              {/if}
              {#if photoBusy}<span class="text-sm text-ink-muted" role="status">Memproses foto…</span>{/if}
            </div>
            {#if photoError}<p role="alert" class="text-sm text-danger">{photoError}</p>{/if}
            {#if forms[category].layout !== 'text' && !forms[category].photoPath}
              <p class="text-sm text-ink-muted">Tanpa foto, tampilan ini hanya menampilkan teks.</p>
            {/if}
          </fieldset>

          <div class="flex flex-wrap items-center gap-3 border-t border-line pt-4">
            <Button type="submit" {busy}>Simpan sapaan {CATEGORY_LABEL[category]}</Button>
            {#if dirty}<span class="text-sm text-warn" role="status">Perubahan belum disimpan</span>{/if}
          </div>
        </form>

        <div class="space-y-3">
          <Field id="sample-name" label="Nama contoh" bind:value={sampleName} maxlength={60} />
          <GreetingPreview
            {category}
            title={forms[category].title}
            body={forms[category].body}
            layout={forms[category].layout}
            photoUrl={forms[category].photoUrl}
            {sampleName}
          />
        </div>
      </div>
    {/snippet}
  </Tabs>
</div>
