// Keeps the field-log page loadable with no connection. Network first (so a new version is picked up as soon as there is a connection),
// the saved copy only when the network fails. It never touches POSTs and never caches the log or tokens.
const CACHE = 'fieldlog-shell-v1';
const SHELL = ['./', 'assets/app.js', 'assets/core.js', 'assets/i18n.js', 'assets/style.css', 'sites'];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // Only the page, its assets and the site list; anything else (entries, whoami, health, admin reads) goes straight to the network.
  const path = url.pathname;
  const ok = path.endsWith('/fieldlog/') || path.includes('/fieldlog/assets/') || path.endsWith('/fieldlog/sites');
  if (!ok) return;
  event.respondWith(
    fetch(req).then((res) => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)); }
      return res;
    }).catch(() => caches.match(req).then((hit) => hit || Response.error())),
  );
});
