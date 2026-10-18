// Dashboard adalah SPA statis (docs/decisions.md T-001): tidak ada render di server.
export const ssr = false;
export const prerender = false;
export const trailingSlash = 'never';
