export interface Toast {
  id: number;
  kind: 'success' | 'error';
  message: string;
}

let nextId = 1;
export const toasts = $state<Toast[]>([]);

function push(kind: Toast['kind'], message: string, ms: number) {
  const id = nextId++;
  toasts.push({ id, kind, message });
  setTimeout(() => dismiss(id), ms);
}

export function dismiss(id: number) {
  const i = toasts.findIndex((t) => t.id === id);
  if (i >= 0) toasts.splice(i, 1);
}

export const toast = {
  success: (message: string) => push('success', message, 4000),
  error: (message: string) => push('error', message, 8000),
};
