<script lang="ts">
  import '../app.css';
  import { goto, invalidateAll } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { supabase } from '$lib/supabase';

  let { children } = $props();

  // Sesi berakhir di tab lain atau token tidak bisa diperbarui → kembali ke halaman masuk.
  $effect(() => {
    const { data } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') void goto(resolve('/masuk'), { replaceState: true });
      else if (event === 'SIGNED_IN' || event === 'USER_UPDATED') void invalidateAll();
    });
    return () => data.subscription.unsubscribe();
  });
</script>

{@render children()}
