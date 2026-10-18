import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';
import type { Database } from '@guestbook/shared/database.types';

// Hanya publishable key. Service role key tidak pernah ada di bundle frontend (prd.md 10.4).
export const supabase = createClient<Database>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    // Dashboard tidak memakai magic link/OAuth, jadi token di URL tidak pernah diproses.
    detectSessionInUrl: false,
  },
});
