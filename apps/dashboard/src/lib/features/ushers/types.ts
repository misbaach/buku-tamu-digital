/** Hasil RPC get_alerts (FR-R-08, FR-R-09). */
export interface Alerts {
  blocked: { ip: string; scope: 'key' | 'ip'; retryAfterSec: number }[];
  loginFailures: { count: number; threshold: number; windowMin: number; warning: boolean };
  quarantineFull: { deviceId: string; code: string; count: number }[];
}

/** Durasi singkat untuk banner, mis. "12 menit" atau "40 detik". */
export function formatWait(seconds: number): string {
  if (seconds < 60) return `${seconds} detik`;
  return `${Math.ceil(seconds / 60)} menit`;
}

/** Selisih jam perangkat, mis. "+3 mnt" atau "−45 dtk". */
export function formatSkew(ms: number): string {
  const sign = ms < 0 ? '−' : '+';
  const abs = Math.abs(ms) / 1000;
  return abs < 60 ? `${sign}${Math.round(abs)} dtk` : `${sign}${Math.round(abs / 60)} mnt`;
}
