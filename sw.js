const CACHE = 'mahrjan-new-24';
const ASSETS = ['./', './index-app.html', './app.html', './manifest.json', './mj-bridge.js', './mj-stockcount.js', './mj-datefmt.js', './mj-anim.js', './icon-192.png', './icon-512.png', './icon-maskable-512.png'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(ASSETS.map(a => c.add(a).catch(() => null)))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // Apps Script and Google traffic always goes to the network.
  if (url.hostname.indexOf('google') !== -1) return;
  // app pages and the bridge: network first, so a new version shows at once (cache only when offline)
  if (url.origin === location.origin && (/\.html$|\/$|mj-(bridge|stockcount)\.js$/.test(url.pathname))) {
    e.respondWith(fetch(e.request.url, { cache: 'no-cache', credentials: 'same-origin' }).then(res => { if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); } return res; })
      .catch(() => caches.match(e.request).then(hit => hit || caches.match(url.pathname.endsWith('app.html') ? './app.html' : './index-app.html'))));
    return;
  }
  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      if (res.ok && url.origin === location.origin) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
      }
      return res;
    }).catch(() => caches.match(url.pathname.endsWith('app.html') ? './app.html' : './index-app.html')))
  );
});