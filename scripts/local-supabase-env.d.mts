export interface LocalSupabaseEnv {
  API_URL: string;
  PUBLISHABLE_KEY: string;
  DB_URL: string;
  FUNCTIONS_URL: string;
  STUDIO_URL: string;
}

export function localSupabaseEnv(): LocalSupabaseEnv;
