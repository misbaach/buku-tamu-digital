import {
  GREETING_PHOTO_BUCKET,
  IMAGE_EXTENSION,
  SIGNED_URL_TTL_SEC,
  UPLOAD_MAX_BYTES,
  detectImageMime,
  type Category,
} from '@guestbook/shared';
import { supabase } from '$lib/supabase';

export class PhotoError extends Error {}

/**
 * Unggah foto pop-up ke bucket privat (FR-P-01, prd.md 10.4). Jenis gambar ditentukan dari isi berkas, bukan
 * nama atau tipe yang dilaporkan browser, sehingga SVG yang diberi nama .png tetap ditolak.
 */
export async function uploadGreetingPhoto(eventId: string, category: Category, file: File): Promise<string> {
  if (file.size > UPLOAD_MAX_BYTES) throw new PhotoError('Ukuran foto maksimal 5 MB.');
  const head = new Uint8Array(await file.slice(0, 16).arrayBuffer());
  const mime = detectImageMime(head);
  if (!mime) throw new PhotoError('Format foto harus PNG, JPEG, atau WebP.');
  const path = `${eventId}/${category}/${crypto.randomUUID()}.${IMAGE_EXTENSION[mime]}`;
  const { error } = await supabase.storage
    .from(GREETING_PHOTO_BUCKET)
    .upload(path, file, { contentType: mime, upsert: false });
  if (error) throw new PhotoError('Foto gagal diunggah. Coba lagi.');
  return path;
}

export async function removeGreetingPhoto(path: string): Promise<void> {
  await supabase.storage.from(GREETING_PHOTO_BUCKET).remove([path]);
}

/** URL bertanda tangan berumur pendek untuk pratinjau; bucket tidak pernah publik. */
export async function signedPhotoUrl(path: string): Promise<string | null> {
  const { data } = await supabase.storage.from(GREETING_PHOTO_BUCKET).createSignedUrl(path, SIGNED_URL_TTL_SEC);
  return data?.signedUrl ?? null;
}
