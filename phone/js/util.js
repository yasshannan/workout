// util.js — small helpers used everywhere: building HTML, ids, time and
// date text, moving between screens, and the dialogs.

/* ---------- Building HTML ---------- */

/**
 * Create an HTML element in one line:
 *   h('button', { class: 'btn', onclick: save }, 'Save')
 * - props starting with "on" become event listeners
 * - children can be text, elements, arrays, or null/false (those are skipped)
 */
export function h(tag, props, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'dataset') Object.assign(el.dataset, value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
    else if (key in el) el[key] = value;                       // value, disabled, type, id …
    else el.setAttribute(key, value === true ? '' : value);    // aria-label, inputmode …
  }
  append(el, children);
  return el;
}

/** Replace everything inside el with new children (same rules as h). */
export function fill(el, ...children) {
  el.replaceChildren();
  append(el, children);
  return el;
}

function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
}

/* ---------- Ids and time ---------- */

/** A new unique id (UUID). Every workout, set, template … gets one. */
export function uuid() {
  if (crypto.randomUUID) return crypto.randomUUID();
  // Older iOS versions: build the same kind of id from random bytes.
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** The current time as text, always in UTC: "2026-11-16T21:18:00.000Z" */
export function nowIso() {
  return new Date().toISOString();
}

/** Is this timestamp on today's date (in the phone's time zone)? */
export function isToday(iso) {
  return new Date(iso).toDateString() === new Date().toDateString();
}

/* ---------- Text for durations and dates ---------- */

// The app's texts are German, so dates and numbers are written the Austrian
// way, whatever language the phone uses. Times are 24-hour.
export const LOCALE = 'de-AT';
const pad = (n) => String(n).padStart(2, '0');

/** 65000 ms → "1:05", 3723000 ms → "1:02:03" (rounds down, like a stopwatch) */
export function formatDuration(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  return hours > 0 ? `${hours}:${pad(minutes)}:${pad(seconds)}` : `${minutes}:${pad(seconds)}`;
}

/** Same, but rounds up: a countdown shows 0:01 until the very end. */
export function formatCountdown(ms) {
  return formatDuration(Math.ceil(Math.max(0, ms) / 1000) * 1000);
}

/** "Mo., 16. Nov." */
export function formatDate(iso) {
  return new Date(iso).toLocaleDateString(LOCALE, { weekday: 'short', day: 'numeric', month: 'short' });
}

/** "Mo., 16. Nov., 17:02" */
export function formatDateTime(iso) {
  const time = new Date(iso).toLocaleTimeString(LOCALE, { hour: '2-digit', minute: '2-digit' });
  return `${formatDate(iso)}, ${time}`;
}

/** "heute", "gestern", "vor 5 Tagen" — counted in calendar days */
export function daysAgoText(iso) {
  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((startOfDay(new Date()) - startOfDay(new Date(iso))) / 86400000);
  if (days <= 0) return 'heute';
  if (days === 1) return 'gestern';
  return `vor ${days} Tagen`;
}

/** 12345 → "12.345" */
export function formatThousands(n) {
  return Math.round(n).toLocaleString('de-DE');     // de-AT would use a space: "12 345"
}

/* ---------- Device ---------- */

/** 'ios', 'android' or 'other' (a PC). iPads report themselves as Mac with a touch screen. */
export function platform() {
  const agent = navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(agent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) return 'ios';
  if (/Android/.test(agent)) return 'android';
  return 'other';
}

/** Was the app opened from its Home Screen icon (and not in a browser tab)? */
export function isInstalled() {
  return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
}

/* ---------- Moving between screens ---------- */

/** Show another screen, e.g. go('#/history'). app.js listens for the change. */
export function go(hash) {
  if (location.hash === hash) window.dispatchEvent(new HashChangeEvent('hashchange'));
  else location.hash = hash;
}

/* ---------- Messages and dialogs ---------- */

/** A short message at the top that disappears by itself. */
export function toast(message) {
  document.querySelectorAll('.toast').forEach((el) => el.remove());
  const el = h('div', { class: 'toast', role: 'status' }, message);
  document.body.append(el);
  setTimeout(() => el.remove(), 2600);
}

/**
 * A small dialog that slides up from the bottom. It closes with a tap next to
 * it or by pulling it down. build(close) returns the content; call close() to dismiss it.
 */
export function openSheet(build) {
  const backdrop = h('div', { class: 'sheet-backdrop' });
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    if (reducedMotion()) { backdrop.remove(); return; }
    backdrop.classList.add('closing');
    backdrop.addEventListener('transitionend', () => backdrop.remove(), { once: true });
    setTimeout(() => backdrop.remove(), 300);       // in case no transition ran
  };
  backdrop.addEventListener('click', (event) => { if (event.target === backdrop) close(); });
  const sheet = h('div', { class: 'sheet' }, h('div', { class: 'sheet-grip', 'aria-hidden': 'true' }), build(close));
  pullDownToClose(sheet, close);
  backdrop.append(sheet);
  document.body.append(backdrop);
  return close;
}

/** Pulling a sheet down by its top area closes it, like the sheets of iOS. */
function pullDownToClose(sheet, close) {
  let startY = null;
  let moved = 0;
  sheet.addEventListener('touchstart', (event) => {
    // only from the top of the sheet, so scrolling inside it still works
    const top = sheet.getBoundingClientRect().top;
    startY = event.touches[0].clientY - top < 56 && sheet.scrollTop === 0 ? event.touches[0].clientY : null;
    moved = 0;
  }, { passive: true });
  sheet.addEventListener('touchmove', (event) => {
    if (startY === null) return;
    moved = Math.max(0, event.touches[0].clientY - startY);
    sheet.style.transform = `translateY(${moved}px)`;
  }, { passive: true });
  sheet.addEventListener('touchend', () => {
    if (startY === null) return;
    startY = null;
    sheet.style.transform = '';
    if (moved > 90) close();
  });
}

/** Has the user asked the phone for less motion? Then animations are skipped. */
export function reducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** Ask a yes/no question. Resolves to true or false. */
export function confirmSheet(message, okLabel = 'OK', { danger = false, cancelLabel = 'Abbrechen' } = {}) {
  return new Promise((resolve) => {
    openSheet((close) => [
      h('h3', {}, message),
      h('div', { class: 'row' },
        h('button', { class: 'btn secondary', onclick: () => { close(); resolve(false); } }, cancelLabel),
        h('button', { class: danger ? 'btn danger' : 'btn', onclick: () => { close(); resolve(true); } }, okLabel)),
    ]);
  });
}

/** A full-screen layer on top of the current screen. build(close) returns the content. */
export function openOverlay(build) {
  const wrap = h('div', { class: 'overlay-wrap' });
  const close = () => wrap.remove();
  wrap.append(h('div', { class: 'overlay' }, build(close)));
  document.body.append(wrap);
  return close;
}
