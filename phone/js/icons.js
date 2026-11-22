// icons.js — the few drawn symbols of the app (the tab bar's are in index.html).
// Drawn as SVG, so they look the same on every iPhone (a character such as ⚙
// may turn into a colourful emoji on iOS).

const PATHS = {
  // the logo: the Greek letter Delta, the same outline as the app icon
  logo: '<svg viewBox="0 0 1565 1493"><path fill-rule="evenodd" d="M1565 1493H0L553 0H1012ZM489 1202H1073L783 350Z"/></svg>',
  moon: '<svg viewBox="0 0 24 24"><path d="M20 14.6A8 8 0 0 1 9.4 4a8 8 0 1 0 10.6 10.6Z"/></svg>',
  sun: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></svg>',
  // the "Teilen" symbol of Safari: a box with an arrow pointing up
  share: '<svg viewBox="0 0 24 24"><path d="M8.5 9H6.8a1.3 1.3 0 0 0-1.3 1.3v9.4A1.3 1.3 0 0 0 6.8 21h10.4a1.3 1.3 0 0 0 1.3-1.3v-9.4A1.3 1.3 0 0 0 17.2 9h-1.7M12 14.5V3M8.5 6.3 12 2.8l3.5 3.5"/></svg>',
};

/** A drawn symbol as an element, e.g. icon('moon'). Screen readers skip it. */
export function icon(name, className = '') {
  const template = document.createElement('template');
  template.innerHTML = PATHS[name];
  const svg = template.content.firstElementChild;
  svg.setAttribute('aria-hidden', 'true');
  if (className) svg.setAttribute('class', className);
  return svg;
}
