export const FUNCTIONS_ENV: string;
/** Isi supabase/functions/.env lokal (di-gitignore). */
export function readFunctionsEnv(): Record<string, string>;
