// screens/workout.js — the running workout. It is used between sets, so the
// important button ("Satz speichern") is big and alone.
//
// The screen is drawn again completely (paint) after every action. In between,
// only the clocks change; the clock (clock.js) updates them.
//
// GOLD
//   a set that beats your history (heaviest, best estimated 1RM, most reps at
//   a weight) turns gold with a ★; an exercise card turns gold when you moved
//   more kilograms than ever before WITH THE SAME NUMBER OF SETS.

import { h, fill, go, formatDuration, formatCountdown, formatDate, formatThousands, toast, openSheet, confirmSheet, reducedMotion } from '../util.js';
import * as W from '../workout.js';
import { getExercise, saveSetup } from '../library.js';
import { formatSet, formatRepTarget, formatWeight, formatNumber, parseNumber, repUnit, UNIT_SHORT } from '../format.js';
import { loadRecords, findNewRecords, volumeComparison, getLastSession, loadTrends, sessionScore, addTrendPoint, localDay } from '../records.js';
import { latestBodyWeightKg } from '../bodyWeights.js';
import { onTick } from '../clock.js';
import { setFields, setRows, draftFromSet, readDraft, recordText, sparkline } from '../components.js';
import { openExercisePicker } from '../dialogs/exercisePicker.js';
import { openExerciseEditor } from '../dialogs/exerciseEditor.js';
import { openSetSheet } from '../dialogs/setSheet.js';
import { tap } from '../device.js';
import { settings } from '../settings.js';

let root = null;                 // the element this screen draws into
let active = null;               // { workout, state } from workout.js
let lastSessions = new Map();    // exercise id → what was done last time (or null)
let drafts = new Map();          // card id → what is typed in for the next set
let history = new Map();         // exercise id → your records before this workout
let newRecords = new Map();      // set id → record, for sets of today that beat the history
let bodyWeightKg = null;         // for the volume of body-weight exercises
let rest = null;                 // the elements of the rest bar
let note = null;                 // { entryId, text }: the latest record, shown inside its card
let trends = new Map();          // exercise id → the best set of the last sessions (records.js, loadTrends)
const openCues = new Set();      // exercises whose "Technik" tips are unfolded

export async function render(container) {
  root = container;
  active = await W.getActive();
  if (!active) { go('#/home'); return null; }
  lastSessions = new Map();
  drafts = new Map();
  note = null;
  bodyWeightKg = await latestBodyWeightKg();
  history = await loadRecords(active.workout.id, bodyWeightKg);
  trends = await loadTrends(active.workout.id);
  await paint();
  const stopTicking = onTick(updateRest);
  return () => { stopTicking(); rest = null; };      // called when the screen is left
}

/* ---------- Drawing ---------- */

async function paint() {
  const { workout } = active;
  for (const entry of workout.exercises) {
    if (!lastSessions.has(entry.exerciseId)) {
      lastSessions.set(entry.exerciseId, await getLastSession(entry.exerciseId, workout.id));
    }
  }
  const timings = W.setTimings(workout);
  newRecords = findNewRecords(workout, history);
  const empty = workout.exercises.length === 0;
  const scrollY = window.scrollY;

  fill(root,
    h('header', { class: 'topbar' },
      h('button', { class: 'btn ghost', onclick: () => go('#/home') }, '‹ Start'),
      h('div', { class: 'clock', 'aria-label': 'Trainingszeit', dataset: { since: workout.startedAt } },
        formatDuration(Date.now() - Date.parse(workout.startedAt)))),
    h('input', {
      type: 'text', value: workout.name, 'aria-label': 'Name des Trainings',
      onchange: (event) => W.changeActive((w) => { w.name = event.target.value.trim() || 'Training'; }),
    }),
    workout.exercises.map((entry, index) => entryCard(entry, timings, index)),
    empty ? h('p', { class: 'muted center' }, 'Füge deine erste Übung hinzu.') : null,
    h('button', { class: empty ? 'btn block big' : 'btn block secondary', onclick: addExercise }, '+ Übung hinzufügen'),
    h('label', { class: 'field' }, h('span', {}, 'Notizen zum Training'),
      h('textarea', { value: workout.notes, onchange: (event) => W.changeActive((w) => { w.notes = event.target.value; }) })),
    h('button', { class: 'btn block', onclick: finish }, 'Training beenden'),
    h('div', { class: 'spacer' }),
    h('button', { class: 'btn ghost block', onclick: discard }, 'Training verwerfen'),
    h('div', { class: 'rest-spacer' }),
    restBar());

  window.scrollTo(0, scrollY);
  updateRest(Date.now());
}

/** One exercise card. Only the open card shows its sets and the input fields. */
function entryCard(entry, timings, index) {
  const { state, workout } = active;
  const exercise = getExercise(entry.exerciseId);
  const plan = state.plan[entry.id] || {};
  const done = entry.sets.filter((set) => set.type === 'work').length;
  const target = formatRepTarget(plan.repsMin, plan.repsMax);
  const countText = (plan.targetSets ? `${done} von ${plan.targetSets} Sätzen` : `${done} ${done === 1 ? 'Satz' : 'Sätze'}`)
    + (target ? ` · ${target} ${UNIT_SHORT[repUnit(exercise)]}` : '');

  const comparison = volumeComparison(workout, entry.exerciseId, history.get(entry.exerciseId), bodyWeightKg);
  const gold = Boolean(comparison && comparison.gold);
  const estimated = exercise && exercise.loadType !== 'external' ? ' (geschätzt)' : '';
  const volumeLine = comparison
    ? h('div', { class: gold ? 'volume-line gold-text' : 'volume-line' },
        gold ? '★ Volumenrekord' : 'Volumen',
        ` (${comparison.sets} ${comparison.sets === 1 ? 'Satz' : 'Sätze'})${estimated}: `,
        `${formatThousands(comparison.todayKg)} kg / Bestwert ${formatThousands(comparison.bestKg)} kg`)
    : null;
  const recordLine = note && note.entryId === entry.id ? h('div', { class: 'record-note', role: 'status' }, note.text) : null;

  const group = W.supersetOf(workout, entry);
  const supersetTag = entry.supersetGroup
    ? h('span', { class: 'tag' }, `Supersatz ${entry.supersetGroup} · ${group.indexOf(entry) + 1}/${group.length}`)
    : null;
  const top = h('div', { class: 'entry-top' },
    h('button', { class: 'entry-head', onclick: () => chooseEntry(entry) },
      h('span', { class: 'entry-name' }, exercise ? exercise.name : 'Unbekannte Übung'),
      h('span', { class: 'muted small' }, countText, supersetTag ? ' ' : '', supersetTag)),
    h('button', { class: 'btn ghost', 'aria-label': 'Optionen der Übung', onclick: () => entryMenu(entry, exercise, index) }, '⋯'));

  const linked = index > 0 && entry.supersetGroup && entry.supersetGroup === workout.exercises[index - 1].supersetGroup;
  const cardClass = `card${gold ? ' gold' : ''}${linked ? ' linked' : ''}`;
  if (entry.id !== state.entryId) return h('section', { class: cardClass }, top, volumeLine, recordLine);

  const running = Boolean(state.setStartedAt);
  return h('section', { class: `${cardClass} open`, id: 'open-entry' },
    top,
    exercise && exercise.setup ? h('div', { class: 'setup-line' }, `⚙ ${exercise.setup}`) : null,
    cuesLine(exercise),
    h('div', { class: 'last-time' }, lastTimeText(entry, exercise), bestText(entry, exercise)),
    trendLine(entry, exercise),
    progressionLine(entry, exercise, plan),
    volumeLine,
    recordLine,
    setRows(entry, exercise, timings, (set) => editSet(entry, set, exercise), newRecords),
    warmupLine(entry, exercise),
    h('div', { class: 'next-set' },
      setFields(draftFor(entry), exercise, { repTarget: target }),
      h('button', { class: 'btn block big', id: 'log-set', onclick: () => logSet(entry, exercise) }, '✓ Satz speichern'),
      nextButton(entry, plan, done),
      running
        ? h('button', { class: 'btn ghost block small', onclick: cancelSet },
            '■ Satz läuft ', h('span', { dataset: { since: state.setStartedAt } }, formatDuration(Date.now() - Date.parse(state.setStartedAt))),
            ' · abbrechen')
        : h('button', { class: 'btn ghost block small', onclick: startSet }, '▶ Satz starten (misst die Satzdauer)')),
    h('label', { class: 'field' }, h('span', {}, 'Notizen zur Übung'),
      h('textarea', { value: entry.notes, onchange: (event) => W.changeActive(() => { entry.notes = event.target.value; }) })));
}

/**
 * Once the planned sets of this exercise are done: "Weiter: Lat Pulldown ›" opens the
 * next exercise that still has sets to do, so you don't have to scroll for it.
 */
function nextButton(entry, plan, done) {
  if (!plan.targetSets || done < plan.targetSets) return null;
  const { workout, state } = active;
  const index = workout.exercises.indexOf(entry);
  const next = [...workout.exercises.slice(index + 1), ...workout.exercises.slice(0, index)].find((other) => {
    const wanted = (state.plan[other.id] || {}).targetSets;
    const sets = other.sets.filter((set) => set.type === 'work').length;
    return wanted ? sets < wanted : sets === 0;
  });
  if (!next) return null;
  const exercise = getExercise(next.exerciseId);
  return h('button', {
    class: 'btn block secondary next-exercise',
    onclick: async () => {
      await chooseEntry(next);
      const card = document.getElementById('open-entry');
      if (card) card.scrollIntoView({ block: 'start', behavior: reducedMotion() ? 'auto' : 'smooth' });
    },
  }, h('span', { class: 'next-name' }, `Weiter: ${exercise ? exercise.name : 'nächste Übung'}`), '›');
}

/** "Letztes Mal (Mo., 9. Nov.): 60 kg × 8 · 60 kg × 8 · 60 kg × 7" */
function lastTimeText(entry, exercise) {
  const last = lastSessions.get(entry.exerciseId);
  if (!last) return 'Erstes Mal bei dieser Übung.';
  const workSets = last.sets.filter((set) => set.type !== 'warmup');
  const shown = workSets.length ? workSets : last.sets;
  return `Letztes Mal (${formatDate(last.startedAt)}): ${shown.map((set) => formatSet(set, exercise)).join(' · ')}`;
}

/** "Bestwert: 70 kg × 6" — the heaviest set you ever did, the thing to beat. */
function bestText(entry, exercise) {
  const record = history.get(entry.exerciseId);
  if (!record || !record.bestSet || (exercise && exercise.loadType === 'assisted')) return null;
  return h('div', {}, `Bestwert: ${formatSet(record.bestSet, exercise)}`);
}

/**
 * "Technik": the short tips of the exercise, folded away until tapped. Stays
 * open for that exercise while the app runs.
 */
function cuesLine(exercise) {
  if (!exercise || !exercise.cues || exercise.cues.length === 0) return null;
  return h('details', {
    class: 'cues',
    open: openCues.has(exercise.id),
    ontoggle: (event) => { if (event.target.open) openCues.add(exercise.id); else openCues.delete(exercise.id); },
  },
  h('summary', {}, 'Technik'),
  h('ul', {}, exercise.cues.map((cue) => h('li', {}, cue))));
}

/**
 * "Trend: +6 % in 8 Trainings" with a small line: the best set of each of the
 * last sessions (and of today, in gold, once there is a working set).
 */
function trendLine(entry, exercise) {
  let points = trends.get(entry.exerciseId) || [];
  const today = sessionScore(entry.sets, exercise);
  if (today !== null) points = addTrendPoint(points, localDay(active.workout.startedAt), today);
  if (points.length < 3) return null;
  const first = points[0].s;
  const last = points[points.length - 1].s;
  const change = ((last / first) - 1) * 100;
  const sign = change > 0.05 ? '+' : change < -0.05 ? '−' : '±';
  return h('div', { class: 'trend-line' },
    sparkline(points.map((point) => point.s), { markLast: today !== null }),
    h('span', {}, `Trend: ${sign}${formatNumber(Math.abs(change), 0)} % in ${points.length} Trainings`));
}

/** "↑ Letztes Mal alle Sätze ≥ 12 → +2,5 kg" before the first working set. */
function progressionLine(entry, exercise, plan) {
  if (entry.sets.some((set) => set.type === 'work')) return null;
  const step = W.progression(lastSessions.get(entry.exerciseId), plan, exercise);
  return step ? h('div', { class: 'progress-line' }, `↑ ${step.text}`) : null;
}

/** Plan warm-ups (before the first working set), or show the ones still to do. */
function warmupLine(entry, exercise) {
  const planned = W.plannedWarmups(entry.id);
  if (planned.length > 0) {
    return h('div', { class: 'warmup-line' },
      h('span', {}, `Aufwärmen: noch ${planned.map((set) => `${formatWeight(set.weightKg)} × ${set.reps}`).join(' · ')}`),
      h('button', { class: 'btn ghost small fixed', onclick: () => setWarmups(entry, []) }, 'Überspringen'));
  }
  if (entry.sets.length > 0) return null;
  const draft = draftFor(entry);
  const workKg = parseNumber(draft.weight);
  const suggestion = W.warmupPlan(workKg, exercise);
  if (suggestion.length === 0) return null;
  const work = { weightKg: workKg, reps: parseNumber(draft.reps) || null };
  return h('button', { class: 'btn secondary block small', onclick: () => setWarmups(entry, suggestion, work) },
    `Aufwärmsätze für ${formatWeight(workKg)} planen (${suggestion.length})`);
}

/** What is typed in for the next set, pre-filled so that usually nothing needs typing. */
function draftFor(entry) {
  if (!drafts.has(entry.id)) {
    const guess = W.prefill(entry, lastSessions.get(entry.exerciseId), active.state.plan[entry.id], getExercise(entry.exerciseId));
    drafts.set(entry.id, draftFromSet(guess));
  }
  return drafts.get(entry.id);
}

/* ---------- The rest bar at the bottom ---------- */

function restBar() {
  const label = h('span', { class: 'rest-label' }, 'Pause');
  const time = h('span', { class: 'rest-time' }, '0:00');
  const target = h('span', { class: 'rest-target' }, '');
  const fillBar = h('div', { class: 'rest-bar-fill' });
  const panel = h('div', { class: 'rest', hidden: true, role: 'timer' },
    h('div', { class: 'rest-inner' },
      h('div', { class: 'rest-bar' }, fillBar),
      h('div', { class: 'rest-main' },
        // tapping the time switches between the slim bar and big numbers
        h('button', { class: 'rest-clock', 'aria-label': 'Pause groß oder klein anzeigen', onclick: () => expandRest(!active.state.restExpanded) },
          label, time, target),
        h('div', { class: 'rest-buttons' },
          h('button', { class: 'btn small', 'aria-label': '15 Sekunden weniger', onclick: () => adjustRest(-15) }, '−15'),
          h('button', { class: 'btn small', 'aria-label': '15 Sekunden mehr', onclick: () => adjustRest(15) }, '+15'),
          h('button', { class: 'btn small solid', onclick: startSet }, '▶ Los')))));
  rest = { panel, label, time, fillBar, target };
  return panel;
}

/** Four times per second: refresh the countdown from the timestamps. */
function updateRest(now) {
  if (!rest) return;
  const info = W.restInfo(now);
  rest.panel.hidden = !info;
  document.body.classList.toggle('resting', Boolean(info));
  if (!info) return;
  const over = info.remainingMs <= 0;
  const group = W.supersetOf(active.workout, info.entry);
  const changing = group.indexOf(info.entry) < group.length - 1;
  rest.panel.classList.toggle('over', over);
  rest.panel.classList.toggle('expanded', Boolean(active.state.restExpanded));
  rest.label.textContent = changing ? (over ? 'Wechseln – los!' : 'Wechsel') : (over ? 'Pause vorbei – los!' : 'Pause');
  // Before the target: count down. After it: count up ("+0:12").
  rest.time.textContent = over ? `+${formatDuration(-info.remainingMs)}` : formatCountdown(info.remainingMs);
  rest.fillBar.style.transform = `scaleX(${Math.min(1, info.elapsedMs / info.targetMs)})`;
  rest.target.textContent = `Ziel ${formatDuration(info.targetMs)}`;
}

async function adjustRest(seconds) {
  await W.adjustRest(seconds);
  updateRest(Date.now());
}

async function expandRest(expanded) {
  await W.setRestExpanded(expanded);
  updateRest(Date.now());
}

/* ---------- Actions ---------- */

async function chooseEntry(entry) {
  if (entry.id === active.state.entryId) return;
  await W.selectEntry(entry.id);
  await paint();
}

async function startSet() {
  if (!active.state.entryId) return toast('Zuerst eine Übung hinzufügen');
  await W.startSet();
  await paint();
  // Bring "Satz speichern" into view (above the rest bar), so it can be tapped right after the set.
  revealAboveBars(document.getElementById('log-set'));
}

async function cancelSet() {
  await W.cancelSet();
  await paint();
}

async function setWarmups(entry, list, work = null) {
  await W.setWarmups(entry.id, list, work);
  drafts.delete(entry.id);
  await paint();
}

async function logSet(entry, exercise) {
  const values = readDraft(draftFor(entry), exercise, toast);
  if (!values) return;
  if (settings().vibrateOn) tap();      // a tick you feel: the set is saved (must happen during the tap)
  const before = volumeComparison(active.workout, entry.exerciseId, history.get(entry.exerciseId), bodyWeightKg);
  const set = await W.logSet(entry.id, values);
  drafts.delete(entry.id);          // the next set gets a fresh pre-fill
  newRecords = findNewRecords(active.workout, history);
  const after = volumeComparison(active.workout, entry.exerciseId, history.get(entry.exerciseId), bodyWeightKg);
  const record = newRecords.get(set.id);
  if (after && after.gold && !(before && before.gold)) note = { entryId: entry.id, text: '★ Volumenrekord bei dieser Übung!' };
  else if (record) note = { entryId: entry.id, text: `★ Neuer Rekord: ${recordText(record)}` };
  else note = null;
  // In a superset the next card opened: start it with a fresh pre-fill too.
  if (active.state.entryId !== entry.id) drafts.delete(active.state.entryId);
  await paint();
  if (active.state.entryId !== entry.id) {
    const card = document.getElementById('open-entry');
    if (card) card.scrollIntoView({ block: 'start', behavior: 'smooth' });
  } else {
    // e.g. a record note made the card taller; after the last planned set "Weiter: …" shows too
    revealAboveBars(document.querySelector('#open-entry .next-exercise') || document.getElementById('log-set'));
  }
}

/**
 * Scroll just far enough that el is not hidden behind the rest bar at the
 * bottom (on an iPhone 15 Pro the bar and the home bar take ~110 points).
 */
function revealAboveBars(el) {
  if (!el) return;
  const rest = document.querySelector('.rest');
  const limit = rest && !rest.hidden ? rest.getBoundingClientRect().top : window.innerHeight;
  const gap = el.getBoundingClientRect().bottom + 12 - limit;
  if (gap > 0) window.scrollBy({ top: gap, behavior: reducedMotion() ? 'auto' : 'smooth' });
}

function editSet(entry, set, exercise) {
  openSetSheet({
    set, exercise,
    onSave: async (values) => {
      await W.changeActive(() => { Object.assign(set, values); });
      drafts.delete(entry.id);
      await paint();
    },
    onDelete: async () => {
      await W.changeActive(() => { entry.sets = entry.sets.filter((s) => s.id !== set.id); });
      drafts.delete(entry.id);
      await paint();
    },
  });
}

function addExercise() {
  openExercisePicker({
    onPick: async (exercise) => {
      await W.addExercise(exercise.id);
      await paint();
      const card = document.getElementById('open-entry');
      if (card) card.scrollIntoView({ block: 'start', behavior: 'smooth' });
    },
  });
}

/** The machine note: "Sitz 4, Griff weit, Studio A". */
function editSetup(exercise) {
  openSheet((close) => {
    const input = h('input', { type: 'text', value: exercise.setup || '', placeholder: 'z. B. Sitz 4, Polster 2, Studio A', maxlength: 200 });
    return [
      h('h3', {}, 'Geräte-Einstellung'),
      h('p', { class: 'small muted' }, 'Wird bei dieser Übung immer angezeigt.'),
      input,
      h('div', { class: 'spacer' }),
      h('div', { class: 'row' },
        h('button', { class: 'btn secondary', onclick: close }, 'Abbrechen'),
        h('button', { class: 'btn', onclick: async () => { await saveSetup(exercise.id, input.value); close(); await paint(); } }, 'Speichern')),
    ];
  });
}

/** The "⋯" menu of an exercise card. */
function entryMenu(entry, exercise, index) {
  const { workout } = active;
  const above = workout.exercises[index - 1];
  const inSupersetWithAbove = above && entry.supersetGroup && entry.supersetGroup === above.supersetGroup;
  openSheet((close) => [
    h('h3', {}, exercise ? exercise.name : 'Übung'),
    h('div', { class: 'stack' },
      exercise ? h('button', { class: 'btn block secondary', onclick: () => { close(); editSetup(exercise); } },
        exercise.setup ? 'Geräte-Einstellung ändern' : 'Geräte-Einstellung notieren') : null,
      above ? h('button', {
        class: 'btn block secondary',
        onclick: async () => { close(); await W.toggleSupersetWithPrevious(entry.id); await paint(); },
      }, inSupersetWithAbove ? 'Supersatz mit der Übung darüber auflösen' : 'Als Supersatz mit der Übung darüber') : null,
      exercise ? h('button', {
        class: 'btn block secondary',
        onclick: () => { close(); openExerciseEditor(exercise, { onDone: paint }); },
      }, 'Übung und Muskeln bearbeiten') : null,
      h('button', {
        class: 'btn block danger',
        onclick: async () => {
          close();
          if (entry.sets.length > 0 && !await confirmSheet('Diese Übung mit ihren Sätzen aus dem Training entfernen?', 'Entfernen', { danger: true })) return;
          await W.changeActive((w) => { w.exercises = w.exercises.filter((e) => e.id !== entry.id); });
          await paint();
        },
      }, 'Aus dem Training entfernen'),
      h('button', { class: 'btn block ghost', onclick: close }, 'Abbrechen')),
  ]);
}

async function finish() {
  const setCount = active.workout.exercises.reduce((sum, entry) => sum + entry.sets.length, 0);
  if (setCount === 0) {
    if (await confirmSheet('Noch kein Satz gespeichert. Training verwerfen?', 'Verwerfen', { danger: true, cancelLabel: 'Weitermachen' })) {
      await W.discardWorkout();
      go('#/home');
    }
    return;
  }
  if (!await confirmSheet('Training beenden?', 'Beenden', { cancelLabel: 'Weitermachen' })) return;
  const finished = await W.finishWorkout();
  go(`#/finish/${finished.id}`);
}

async function discard() {
  if (!await confirmSheet('Training verwerfen? Alles, was du darin gespeichert hast, geht verloren.', 'Verwerfen', { danger: true, cancelLabel: 'Weitermachen' })) return;
  await W.discardWorkout();
  go('#/home');
}
