// update.js — registers the service worker (sw.js) and installs new versions.
//
// HOW AN UPDATE HAPPENS
//  1. You change the code, raise APP_VERSION in sw.js and upload it to GitHub.
//  2. The next time the app is opened with internet, the browser notices that
//     sw.js changed and downloads the whole new version in the background.
//  3. As soon as it is ready, and no workout is running, the app reloads
//     itself once and runs the new version.
//  4. If a workout is running, the update waits until you are back on Home.
// Your data lives in IndexedDB, which updates never touch.

import { getActive } from './workout.js';

let registration = null;
// Was this page already run by a service worker when it loaded?
// (Not on the very first visit: then there is nothing to update.)
const hadController = Boolean(navigator.serviceWorker && navigator.serviceWorker.controller);

function isLocalhost() {
  return ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
}

/** Called once at start-up. */
export async function setupServiceWorker() {
  if (!('serviceWorker' in navigator)) return;
  // On your own PC the service worker stays off, so you always see your latest
  // edits. Add ?sw to the address (http://localhost:8000/phone/?sw) to test it.
  if (isLocalhost() && !new URLSearchParams(location.search).has('sw')) return;

  registration = await navigator.serviceWorker.register('sw.js');

  // A new version finished downloading.
  registration.addEventListener('updatefound', () => {
    const worker = registration.installing;
    if (!worker) return;
    worker.addEventListener('statechange', () => {
      if (worker.state === 'installed') applyUpdateIfIdle();
    });
  });

  // The new version took over: reload once to run its code.
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController || reloading) return;
    reloading = true;
    location.reload();
  });

  // Look for a new version every time the app comes back to the front.
  document.addEventListener('visibilitychange', () => { if (!document.hidden) checkForUpdate(); });

  applyUpdateIfIdle();
}

/** Ask the server whether sw.js changed. Returns false when offline. */
export async function checkForUpdate() {
  if (!registration) return false;
  try {
    await registration.update();
    return true;
  } catch (error) {
    return false;
  }
}

/** If a downloaded version is waiting and no workout is running, switch to it now. */
export async function applyUpdateIfIdle() {
  if (!registration || !registration.waiting || !navigator.serviceWorker.controller) return;
  if (await getActive()) return;                     // never reload in the middle of a workout
  registration.waiting.postMessage({ type: 'SKIP_WAITING' });
}

/** The version text from sw.js, or 'dev' when no service worker is running. */
export function getAppVersion() {
  return new Promise((resolve) => {
    const controller = navigator.serviceWorker && navigator.serviceWorker.controller;
    if (!controller) return resolve('dev');
    const channel = new MessageChannel();
    channel.port1.onmessage = (event) => resolve(event.data);
    controller.postMessage({ type: 'GET_VERSION' }, [channel.port2]);
    setTimeout(() => resolve('unbekannt'), 1500);
  });
}
