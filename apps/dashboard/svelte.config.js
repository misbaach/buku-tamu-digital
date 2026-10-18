import adapter from '@sveltejs/adapter-static';

// CSP ketat (prd.md 10.4): tanpa unsafe-eval/unsafe-inline, connect-src hanya ke origin Supabase project.
// SvelteKit menghitung hash skrip inline saat build lalu menulisnya sebagai <meta http-equiv>.
// Direktif yang tidak bisa lewat meta (frame-ancestors) dikirim sebagai header lewat static/_headers.
const supabaseUrl = process.env.PUBLIC_SUPABASE_URL;
const supabaseOrigin = supabaseUrl ? new URL(supabaseUrl).origin : undefined;
const supabaseWs = supabaseOrigin?.replace(/^http/, 'ws');
const only = (...values) => values.filter((v) => typeof v === 'string' && v.length > 0);

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    adapter: adapter({ fallback: 'index.html', strict: true }),
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['none'],
        'script-src': ['self'],
        'style-src': ['self'],
        'img-src': only('self', 'data:', 'blob:', supabaseOrigin),
        'font-src': ['self'],
        'connect-src': only('self', supabaseOrigin, supabaseWs),
        'manifest-src': ['self'],
        'base-uri': ['self'],
        'form-action': ['self'],
        'object-src': ['none'],
      },
    },
  },
};

export default config;
