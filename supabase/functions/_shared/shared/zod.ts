// SALINAN OTOMATIS dari packages/shared/src/zod.ts. Jangan diedit; jalankan `pnpm functions:sync`.
import { z } from 'npm:zod@4.6.5';

// Dashboard memakai CSP tanpa 'unsafe-eval'. Mode JIT Zod mencoba `new Function()` (diblokir CSP dan memicu
// laporan pelanggaran sebelum Zod beralih ke mode biasa). jitless membuat Zod tidak pernah mencobanya.
z.config({ jitless: true });

export { z };
