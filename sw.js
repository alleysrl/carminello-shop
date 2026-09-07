/* Service worker minimale: rende l'app installabile e tiene in cache le immagini.
   Le pagine e i dati passano SEMPRE dalla rete (niente ordini "vecchi" in cache). */
const CACHE = "carminello-v1";
self.addEventListener("install", e => { self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))); self.clients.claim(); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin || !/\/assets\/(img|icons)\//.test(u.pathname)) return;
  e.respondWith(caches.open(CACHE).then(async c => { const hit = await c.match(e.request); if (hit) return hit; const r = await fetch(e.request); if (r.ok) c.put(e.request, r.clone()); return r; }));
});
