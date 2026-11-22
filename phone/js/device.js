// device.js — keeping the screen on, vibration, and the flashing signal.

import { platform } from './util.js';

/* ---------- Keep the screen on (Screen Wake Lock API) ---------- */

let wakeLock = null;      // the lock while we hold one
let wakeWanted = false;   // should the screen stay on right now?

export function wakeLockSupported() {
  return 'wakeLock' in navigator;
}

/** Ask for the screen to stay on (true), or allow it to sleep again (false). */
export async function setWakeLock(wanted) {
  wakeWanted = wanted;
  if (wanted) {
    await acquireWakeLock();
  } else if (wakeLock) {
    await wakeLock.release().catch(() => {});
    wakeLock = null;
  }
}

async function acquireWakeLock() {
  if (!wakeWanted || wakeLock || !wakeLockSupported() || document.visibilityState !== 'visible') return;
  try {
    wakeLock = await navigator.wakeLock.request('screen');
    wakeLock.addEventListener('release', () => { wakeLock = null; });
  } catch (error) {
    wakeLock = null;      // the phone may refuse (e.g. Low Power Mode); the app works anyway
  }
}

// The system takes the lock away whenever the app goes to the background,
// so we ask again each time it becomes visible.
document.addEventListener('visibilitychange', acquireWakeLock);

/* ---------- Vibration ----------
 *
 * Safari on the iPhone has no Vibration API. But since iOS 17.4, tapping a
 * "switch" checkbox gives a short haptic tick, and clicking it from code does
 * the same. We click a hidden one (three times for the end of the rest).
 * This is a known trick, not an official feature, so Settings has a test button.
 * (navigator.vibrate is only used where it exists, e.g. when testing on a PC.)
 */

/** Can this phone vibrate from the app? */
export function vibrationSupported() {
  return typeof navigator.vibrate === 'function' || platform() === 'ios';
}

function appleTick() {
  const label = document.createElement('label');
  label.setAttribute('aria-hidden', 'true');
  label.style.display = 'none';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.setAttribute('switch', '');
  label.append(input);
  document.head.append(label);
  label.click();
  label.remove();
}

/** One light tick, as a confirmation right after a tap (iPhone only). */
export function tap() {
  if (platform() === 'ios') appleTick();
}

/** Buzz three times: short, short, long. */
export function vibrate() {
  if (typeof navigator.vibrate === 'function') {
    navigator.vibrate([200, 100, 200, 100, 400]);
  } else if (platform() === 'ios') {
    appleTick();
    setTimeout(appleTick, 180);
    setTimeout(appleTick, 360);
  }
}

/* ---------- Visual signal ---------- */

/** Blink the rest panel a few times (see "flash" in app.css). */
export function flashScreen() {
  document.body.classList.add('flash');
  setTimeout(() => document.body.classList.remove('flash'), 1500);
}
