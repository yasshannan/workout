// sw.js — the service worker. It makes the app work offline and update itself.
//
// A service worker is a small script the browser keeps running in the
// background. It sits between the app and the network: every file the app asks
// for goes through the "fetch" handler below, which answers from a local copy.
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │  WHEN YOU CHANGE ANY FILE OF THE APP: raise APP_VERSION below.            │
// │  That is what tells phones "there is a new version, download it".         │
// │  If you ADD a file, also add it to the ASSETS list.                       │
// └──────────────────────────────────────────────────────────────────────────┘

const APP_VERSION = '1.1.0';

const CACHE_NAME = `workout-${APP_VERSION}`;

// Every file the app needs. All of them are downloaded together when a version
// is installed, so the app is always complete — never half old, half new.
const ASSETS = [
  './',
  './index.html',
  './manifest.webmanifest',
  './css/theme.css',
  './css/app.css',
  './js/app.js',
  './js/archive.js',
  './js/backup.js',
  './js/bodyWeights.js',
  './js/bodymap.js',
  './js/clock.js',
  './js/components.js',
  './js/db.js',
  './js/device.js',
  './js/dialogs/exerciseEditor.js',
  './js/dialogs/exercisePicker.js',
  './js/dialogs/setSheet.js',
  './js/format.js',
  './js/icons.js',
  './js/library.js',
  './js/records.js',
  './js/recovery.js',
  './js/safety.js',
  './js/schema.js',
  './js/screens/backup.js',
  './js/screens/bodyWeights.js',
  './js/screens/finish.js',
  './js/screens/history.js',
  './js/screens/home.js',
  './js/screens/settings.js',
  './js/screens/templateEditor.js',
  './js/screens/templates.js',
  './js/screens/workout.js',
  './js/screens/workoutDetail.js',
  './js/settings.js',
  './js/templates.js',
  './js/update.js',
  './js/util.js',
  './js/version.js',
  './js/workout.js',
  './js/measurements.js',
  './js/screens/measurements.js',
  './icons/icon-180.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  '../shared/exercises.json',
];

// INSTALL: download every file of this version into its own cache.
self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    // cache: 'reload' = really ask the server, do not reuse the browser's own copy.
    await cache.addAll(ASSETS.map((url) => new Request(url, { cache: 'reload' })));
  })());
});

// ACTIVATE: this version is now in charge. Delete the files of older versions.
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith('workout-') && name !== CACHE_NAME) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

// Messages from the app (see js/update.js).
self.addEventListener('message', (event) => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') self.skipWaiting();        // "take over now"
  if (event.data.type === 'GET_VERSION' && event.ports[0]) event.ports[0].postMessage(APP_VERSION);
});

// FETCH: answer every request from the cache, so the app works without internet.
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  if (new URL(request.url).origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    // Opening the app itself (any address inside it) always gets index.html.
    if (request.mode === 'navigate') {
      const shell = await cache.match('./index.html');
      if (shell) return shell;
    }
    // A file that is not in ASSETS: get it from the network and keep a copy.
    const response = await fetch(request);
    if (response.ok) cache.put(request, response.clone());
    return response;
  })());
});
