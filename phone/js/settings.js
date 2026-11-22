// settings.js — the user's settings, kept in memory and saved in the database.
//
// The app always works in kg, makes no sound and does not ask for effort (RPE).
// Those are not settings, they are simply how the app works.

import { getMeta, setMeta } from './db.js';

export const DEFAULT_SETTINGS = {
  defaultRestSec: 120,   // rest timer target for exercises without their own
  vibrateOn: true,       // vibrate when the rest time is up
  keepScreenOn: true,    // keep the screen on during a workout (Screen Wake Lock)
  theme: 'auto',         // 'auto' (follow the phone), 'light' or 'dark'
  barKg: 20,             // weight of the empty bar, for the plate calculator
};

let current = { ...DEFAULT_SETTINGS };

/** Only the known settings, with their default where something is missing. */
function clean(saved) {
  const result = { ...DEFAULT_SETTINGS };
  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    if (saved && key in saved) result[key] = saved[key];
  }
  return result;
}

/** Load the saved settings once at start-up. */
export async function loadSettings() {
  current = clean(await getMeta('settings', {}));
  applyTheme();
  return current;
}

/** The current settings (read-only: use updateSettings to change them). */
export function settings() {
  return current;
}

/** Change one or more settings and save them. */
export async function updateSettings(patch) {
  current = clean({ ...current, ...patch });
  await setMeta('settings', current);
  applyTheme();
}

/** True if the app is currently shown in light colours. */
export function isLightMode() {
  if (current.theme === 'light') return true;
  if (current.theme === 'dark') return false;
  return !window.matchMedia('(prefers-color-scheme: dark)').matches;
}

/** Put the chosen theme on <html>, so theme.css picks the right colours. */
export function applyTheme() {
  const light = isLightMode();
  document.documentElement.dataset.theme = light ? 'light' : 'dark';
  // the colour of the status bar: one tag, now that the app has decided
  document.querySelectorAll('meta[name="theme-color"]').forEach((meta) => {
    meta.removeAttribute('media');
    meta.content = light ? '#e7e7e7' : '#000000';
  });
  // a copy for index.html, so the next start draws the right colours at once
  try {
    if (current.theme === 'light' || current.theme === 'dark') localStorage.setItem('theme', current.theme);
    else localStorage.removeItem('theme');           // auto: the phone decides
  } catch { /* private mode */ }
}

// In 'auto' mode, follow the phone when it switches between light and dark.
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyTheme);
