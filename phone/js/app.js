// app.js — the starting point. It loads everything once, then shows the
// screen that matches the address after the "#":
//
//   #/home              Home
//   #/workout           the running workout
//   #/finish/<id>       summary after finishing
//   #/history           all workouts        #/history/<id>     one workout (not exported yet)
//   #/templates         all templates       #/templates/<id>   one template
//   #/backup            export / import
//   #/settings          settings
//   #/bodyweights       body-weight entries
//   #/measurements      body measurements
//
// Each screen is a file in js/screens/ with a function render(container, id).
// It may return a function that is called when the screen is left.

import { h, fill, reducedMotion } from './util.js';
import { openDb } from './db.js';
import { protectBeforeUpdate, askForPersistentStorage } from './safety.js';
import { loadSettings } from './settings.js';
import { loadLibrary } from './library.js';
import { startClock, onTick } from './clock.js';
import { getActive, watchRest, syncWakeLock } from './workout.js';
import { setupServiceWorker, applyUpdateIfIdle } from './update.js';

import * as home from './screens/home.js';
import * as workoutScreen from './screens/workout.js';
import * as finish from './screens/finish.js';
import * as history from './screens/history.js';
import * as workoutDetail from './screens/workoutDetail.js';
import * as templates from './screens/templates.js';
import * as templateEditor from './screens/templateEditor.js';
import * as backup from './screens/backup.js';
import * as settingsScreen from './screens/settings.js';
import * as bodyWeights from './screens/bodyWeights.js';
import * as measurements from './screens/measurements.js';

/** Which screen belongs to an address? */
function screenFor(name, id) {
  switch (name) {
    case 'workout': return workoutScreen;
    case 'finish': return finish;
    case 'history': return id ? workoutDetail : history;
    case 'templates': return id ? templateEditor : templates;
    case 'backup': return backup;
    case 'settings': return settingsScreen;
    case 'bodyweights': return bodyWeights;
    case 'measurements': return measurements;
    default: return home;
  }
}

/** Where the "back" swipe leads from a screen ('' = nowhere: it is a main screen). */
function parentOf(name, id) {
  if (name === 'history' && id) return '#/history';
  if (name === 'templates' && id) return '#/templates';
  if (name === 'backup' || name === 'measurements') return '#/home';
  if (name === 'bodyweights') return '#/settings';
  return '';
}

/** How deep a screen is: going deeper slides in from the right, going back from the left. */
function depthOf(name, id) {
  return parentOf(name, id) ? 1 : 0;
}

let leaveScreen = null;     // clean-up function of the screen that is showing
let renderCount = 0;        // lets a slow screen notice that a newer one has started
let lastDepth = 0;
let currentParent = '';

async function showScreen() {
  const [name = 'home', id = null] = location.hash.replace(/^#\/?/, '').split('/');
  const screen = screenFor(name, id);
  const myTurn = ++renderCount;

  if (leaveScreen) { leaveScreen(); leaveScreen = null; }
  document.querySelectorAll('.sheet-backdrop, .overlay-wrap').forEach((el) => el.remove());

  // Draw into a fresh element, and only show it if the user has not moved on meanwhile.
  const container = h('div', {});
  let cleanup = null;
  try {
    cleanup = await screen.render(container, id ? decodeURIComponent(id) : null);
  } catch (error) {
    console.error(error);
    fill(container, h('div', { class: 'card notice' }, `Etwas ist schiefgelaufen: ${error.message}`));
  }
  if (myTurn !== renderCount) { if (cleanup) cleanup(); return; }
  leaveScreen = cleanup || null;

  // A short slide when moving between screens (none if the phone asks for less motion).
  const depth = depthOf(name, id);
  if (!reducedMotion()) container.classList.add(depth > lastDepth ? 'enter-deeper' : depth < lastDepth ? 'enter-back' : 'enter');
  lastDepth = depth;
  currentParent = parentOf(name, id);

  document.getElementById('screen').replaceChildren(container);
  window.scrollTo(0, 0);

  // The tab bar is hidden during a workout: the rest timer lives down there.
  const tabbar = document.getElementById('tabbar');
  tabbar.hidden = screen === workoutScreen || screen === finish;
  tabbar.querySelectorAll('a').forEach((link) => link.classList.toggle('on', link.dataset.tab === (name || 'home')));

  await syncWakeLock();
  if (screen === home) applyUpdateIfIdle();          // a calm moment for a waiting update
}

async function start() {
  try {
    await openDb();
    await protectBeforeUpdate();          // first start of a new version: copy everything before it is used
    askForPersistentStorage();
    await loadSettings();
    await loadLibrary();
  } catch (error) {
    fill(document.getElementById('screen'), h('div', { class: 'card notice' }, `Die App konnte nicht starten: ${error.message}`));
    return;
  }

  setupSwipeBack();
  setupTypingMode();
  startClock();
  onTick(watchRest);                                  // the rest-over signal works on every screen
  window.addEventListener('hashchange', showScreen);

  // An unfinished workout? Go straight back into it.
  if (await getActive() && location.hash !== '#/workout') location.hash = '#/workout';
  else await showScreen();

  setupServiceWorker().catch((error) => console.warn('Service worker not available:', error));
}

/**
 * A web app on the iPhone has no "back" swipe of its own. Swiping from the
 * left edge to the right goes back to the screen above (not on main screens
 * and not while a dialog is open).
 */
function setupSwipeBack() {
  let start = null;
  document.addEventListener('touchstart', (event) => {
    const touch = event.touches[0];
    const blocked = document.querySelector('.sheet-backdrop, .overlay-wrap');
    start = touch.clientX < 28 && currentParent && !blocked ? { x: touch.clientX, y: touch.clientY } : null;
  }, { passive: true });
  document.addEventListener('touchend', (event) => {
    if (!start) return;
    const touch = event.changedTouches[0];
    const dx = touch.clientX - start.x;
    const dy = Math.abs(touch.clientY - start.y);
    start = null;
    if (dx > 80 && dy < 60) location.hash = currentParent;
  }, { passive: true });
}

/**
 * While the keyboard is open, the bars fixed at the bottom (tab bar, rest
 * timer) are hidden: on iPhones they would jump up and cover the field you type in.
 */
function setupTypingMode() {
  const typing = (el) => el && el.matches && el.matches('input[type="text"], input[type="search"], textarea');
  document.addEventListener('focusin', (event) => {
    if (typing(event.target)) document.body.classList.add('typing');
  });
  // The bars come back only AFTER the tap that ended the typing is done (or on
  // the next scroll): otherwise the rest bar would appear under the finger in
  // the middle of a tap on "Satz speichern" and catch it.
  document.addEventListener('focusout', (event) => {
    if (typing(event.relatedTarget)) return;
    const show = () => {
      if (!typing(document.activeElement)) document.body.classList.remove('typing');
    };
    ['click', 'scroll'].forEach((name) => window.addEventListener(name, () => queueMicrotask(show), { capture: true, once: true }));
  });
}

start();
