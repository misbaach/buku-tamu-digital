export interface LocalSupabaseEnv {
  API_URL: string;
  PUBLISHABLE_KEY: string;
  DB_URL: string;
  /** Tidak ada bila edge runtime sedang berhenti. */
  FUNCTIONS_URL?: string;
  /** Tidak ada bila Studio sedang berhenti. */
  STUDIO_URL?: string;
}

export function localSupabaseEnv(): LocalSupabaseEnv;
