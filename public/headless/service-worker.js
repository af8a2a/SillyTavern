const CACHE_NAME = 'sillytavern-headless-shell-v2';
const SHELL_ASSETS = [
    '/headless/',
    '/headless/index.html',
    '/headless/styles.css',
    '/headless/app.js',
    '/headless/manifest.webmanifest',
    '/css/fontawesome.min.css',
    '/css/solid.min.css',
    '/img/logo.png',
    '/img/No-Image-Placeholder.svg',
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(SHELL_ASSETS))
            .then(() => self.skipWaiting()),
    );
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
            .then(() => self.clients.claim()),
    );
});

self.addEventListener('fetch', event => {
    const url = new URL(event.request.url);

    if (url.pathname.startsWith('/api/') || url.pathname === '/csrf-token') {
        return;
    }

    if (event.request.method !== 'GET') {
        return;
    }

    if (url.pathname.startsWith('/headless/')) {
        event.respondWith(
            fetch(event.request)
                .then(response => {
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
                    return response;
                })
                .catch(() => caches.match(event.request)),
        );
        return;
    }

    event.respondWith(
        caches.match(event.request).then(cached => {
            if (cached) {
                return cached;
            }

            return fetch(event.request).then(response => {
                const copy = response.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
                return response;
            });
        }),
    );
});
