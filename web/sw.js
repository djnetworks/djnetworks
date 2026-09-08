// sw.js — service worker. Caches the app shell so a screen opens with no signal.
//
// It caches the SHELL ONLY: HTML, CSS, JavaScript, the vendored Supabase client. It deliberately
// does NOT cache API responses. Data that came back from a request is not the same thing as data
// the operator chose to take with him, and a stale row served silently from a cache is exactly how
// a screen tells him a box is on the shelf when it went out yesterday. Rule 2 lives or dies on
// nobody inventing a fact. What travels offline is prefetched explicitly, into IndexedDB, with a
// visible "loaded for offline" state and a timestamp — see db.js.
//
// Bump CACHE when any shell file changes. The old cache is deleted on activate, so a stale shell
// cannot outlive a deploy: "the fix isn't showing up" is this, nine times in ten.

const CACHE = 'djn-shell-2026-09-08-30';

const SHELL = [
  './',
  'index.html',
  'ask.html',
  'team.html',
  'transfer.html',
  'products.html',
  'units.html',
  'orders.html',
  'dispatch.html',
  'return.html',
  'customers.html',
  'ledger.html',
  'reports.html',
  'portal.html',
  'style.css',
  'tokens.css',
  'app.js',
  'boot.js',
  'config.js',
  'db.js',
  'vendor/supabase.js',
  // Named individually rather than by a wildcard: a service worker cache has no globs, and
  // a missing icon on the home screen is a silent failure nobody reports.
  'manifest.webmanifest',
  'assets/djn-icon-32.png',
  'assets/djn-icon-64.png',
  'assets/djn-icon-192.png',
  'assets/djn-icon-512.png',
  'assets/djn-apple-touch-icon.png',
];

self.addEventListener('install', (e) => {
  // One missing file must not fail the whole install, or a typo in this list means no offline
  // support at all and no error anybody sees.
  e.waitUntil((async () => {
    const c = await caches.open(CACHE);
    await Promise.all(SHELL.map(u => c.add(u).catch(() => {})));
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(n => n !== CACHE).map(n => caches.delete(n)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                      // writes never come from a cache
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;       // Supabase and storage go to the network

  // EVERY read and write uses the URL with the query string STRIPPED.
  //
  // This was a bug the first time: match() ignored the ?v= string but put() stored under the full
  // URL including it, so the background refresh wrote to a key nothing ever read. The shell was
  // frozen at whatever was cached on the very first visit, and no reload could shift it — the
  // "fix isn't showing up" failure the djn-deploy skill is about, built into the thing meant to
  // prevent it. Cache-busting is the CACHE name's job here, not the query string's.
  const key = new Request(new URL(req.url).origin + new URL(req.url).pathname, { headers: req.headers });

  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(key);
    if (cached) {
      // Answer instantly from cache, refresh underneath for the next open.
      e.waitUntil(fetch(req).then(r => { if (r.ok) cache.put(key, r.clone()); }).catch(() => {}));
      return cached;
    }
    try {
      const fresh = await fetch(req);
      if (fresh.ok) cache.put(key, fresh.clone());
      return fresh;
    } catch (err) {
      const fallback = await cache.match(new Request(new URL('index.html', self.location).href));
      return fallback ?? new Response('Offline, and this page was never loaded while online.', {
        status: 503, headers: { 'content-type': 'text/plain' },
      });
    }
  })());
});
