// clock.js — keeps every clock on screen up to date.
//
// HOW TIMERS WORK IN THIS APP
// The app never counts seconds itself. It stores WHEN something started (a
// timestamp) and, a few times per second, shows "now minus start". iOS pauses
// all JavaScript while the phone is locked or another app is open; with this
// approach every clock is simply right again the moment the app comes back.

import { formatDuration } from './util.js';

const listeners = new Set();

/** Call fn(nowInMilliseconds) four times per second. Returns a function that stops it. */
export function onTick(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function tick() {
  const now = Date.now();
  // Any element written as <span data-since="2026-11-16T17:02:11.000Z"> is a
  // stopwatch: its text is kept up to date here.
  document.querySelectorAll('[data-since]').forEach((el) => {
    el.textContent = formatDuration(now - Date.parse(el.dataset.since));
  });
  listeners.forEach((fn) => fn(now));
}

/** Start the ticker. Called once from app.js. */
export function startClock() {
  setInterval(tick, 250);
  // Back from the lock screen: refresh at once instead of waiting for the next tick.
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick(); });
}
