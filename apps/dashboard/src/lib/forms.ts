import type { ErrorItem } from '$lib/ui/ErrorSummary.svelte';

interface IssueLike {
  path: readonly PropertyKey[];
  message: string;
}

/** Pesan pertama per field dari hasil safeParse Zod yang gagal. */
export function fieldErrors(issues: readonly IssueLike[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const issue of issues) {
    const key = String(issue.path[0] ?? '_form');
    out[key] ??= issue.message;
  }
  return out;
}

/** Ringkasan galat yang menautkan ke field (`idPrefix + key`), dalam urutan field di form. */
export function errorSummary(errors: Record<string, string>, order: string[], idPrefix: string): ErrorItem[] {
  return order.filter((k) => errors[k]).map((k) => ({ fieldId: `${idPrefix}${k}`, message: errors[k] as string }));
}
