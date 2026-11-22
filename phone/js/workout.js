// workout.js — the running workout. No HTML in here.
//
// It answers: is there an unfinished workout, how do I start and finish one,
// log a set, and how long has the rest been running?
//
// AUTOSAVE: every function that changes something ends with persist() or
// saveState(), which writes to the database at once. If the app is closed in
// the middle of a workout nothing is lost: getActive() finds it again.

import * as db from './db.js';
import { uuid, nowIso } from './util.js';
import { settings } from './settings.js';
import { getExercise } from './library.js';
import { setVolumeKg, hardSetValue, weightStep, effectiveReps, roundKg } from './format.js';
import { getLastSession } from './records.js';
import { setWakeLock, vibrate, flashScreen } from './device.js';

/* ---------- The active (unfinished) workout ----------
 *
 * current = { workout, state } or null
 *   workout  the record exactly as it is stored and exported
 *   state    things only the phone needs while the workout runs:
 *     entryId        which exercise card is open
 *     setStartedAt   timestamp if "Start set" was tapped, else null
 *     restExpanded   is the rest panel shown big (normally it is one slim bar)?
 *     signalledSetId the set whose "rest is over" signal already fired
 *     plan           per exercise card: { targetSets, restSec, repsMin, repsMax }
 *     warmups        per exercise card: warm-up sets still to do [{ weightKg, reps }]
 */
let current = null;
let loaded = false;

/** The unfinished workout, or null. Reads the database only the first time. */
export async function getActive() {
  if (!loaded) {
    loaded = true;
    const state = await db.getMeta('active', null);
    const workout = state ? await db.get('workouts', state.workoutId) : null;
    current = workout && !workout.finishedAt && !workout.deletedAt ? { workout, state } : null;
  }
  return current;
}

/** The id of the running workout, or null (without reading the database). */
export function activeWorkoutId() {
  return current ? current.workout.id : null;
}

/** Write the workout and its state to the database. */
async function persist() {
  renumber(current.workout);
  current.workout.updatedAt = nowIso();
  await db.put('workouts', current.workout);
  await db.setMeta('active', current.state);
}

/** Write only the state (when the workout itself did not change). */
function saveState() {
  return db.setMeta('active', current.state);
}

/** Keep the "order" numbers equal to the position in the list. */
export function renumber(workout) {
  workout.exercises.forEach((entry, i) => {
    entry.order = i;
    entry.sets.forEach((set, j) => { set.order = j; });
  });
}

/** The screen stays on only while a workout is running and the setting allows it. */
export function syncWakeLock() {
  return setWakeLock(Boolean(current) && settings().keepScreenOn);
}

/** Rest target for an exercise: what was used last time, else the default from Settings. */
async function defaultRestFor(exerciseId, excludeWorkoutId) {
  const last = await getLastSession(exerciseId, excludeWorkoutId);
  if (last) {
    for (let i = last.sets.length - 1; i >= 0; i--) {
      // (the short change time inside a superset is not a rest)
      if (last.sets[i].targetRestSec > SUPERSET_CHANGE_SEC) return last.sets[i].targetRestSec;
    }
  }
  return settings().defaultRestSec;
}

/** Start a workout: empty, or filled from a template. */
export async function startWorkout(template = null) {
  if (await getActive()) return current;          // only one workout at a time
  const now = nowIso();
  const workout = {
    id: uuid(),
    name: template ? template.name : 'Training',
    templateId: template ? template.id : null,
    startedAt: now,
    finishedAt: null,
    utcOffsetMin: -new Date().getTimezoneOffset(),   // Vienna: 60 in winter, 120 in summer
    notes: '',
    updatedAt: now,
    deletedAt: null,
    exercises: [],
  };
  const state = { workoutId: workout.id, entryId: null, setStartedAt: null, restExpanded: false, signalledSetId: null, plan: {}, warmups: {} };

  for (const item of template ? template.items : []) {
    const exercise = getExercise(item.exerciseId);
    if (!exercise || exercise.deletedAt) continue;
    const entry = { id: uuid(), exerciseId: item.exerciseId, order: 0, notes: '', sets: [] };
    if (item.supersetGroup) entry.supersetGroup = item.supersetGroup;
    if (item.repsMin) {
      // The rep target is also kept in the workout itself, so the export has it.
      entry.targetRepsMin = item.repsMin;
      entry.targetRepsMax = item.repsMax || item.repsMin;
    }
    workout.exercises.push(entry);
    state.plan[entry.id] = {
      targetSets: item.targetSets,
      restSec: item.restSec || await defaultRestFor(item.exerciseId, workout.id),
      repsMin: entry.targetRepsMin || null,
      repsMax: entry.targetRepsMax || null,
    };
  }
  if (workout.exercises.length > 0) state.entryId = workout.exercises[0].id;

  current = { workout, state };
  await persist();
  // Ask the browser to protect our data from automatic clean-up.
  if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
  await syncWakeLock();
  return current;
}

/** Add an exercise to the running workout and open its card. */
export async function addExercise(exerciseId) {
  const { workout, state } = current;
  const entry = { id: uuid(), exerciseId, order: 0, notes: '', sets: [] };
  workout.exercises.push(entry);
  state.plan[entry.id] = { targetSets: null, restSec: await defaultRestFor(exerciseId, workout.id), repsMin: null, repsMax: null };
  state.entryId = entry.id;
  state.setStartedAt = null;
  await persist();
  return entry;
}

/** Open another exercise card. */
export async function selectEntry(entryId) {
  current.state.entryId = entryId;
  current.state.setStartedAt = null;
  await saveState();
}

/**
 * Do this exercise as a superset with the card above it, or stop doing so.
 * Cards with the same letter (A, B …) are done one after the other without a
 * rest; the rest comes after the last card of the round.
 */
export async function toggleSupersetWithPrevious(entryId) {
  const { workout } = current;
  const index = workout.exercises.findIndex((e) => e.id === entryId);
  if (index <= 0) return;
  const entry = workout.exercises[index];
  const above = workout.exercises[index - 1];
  if (entry.supersetGroup && entry.supersetGroup === above.supersetGroup) {
    delete entry.supersetGroup;
  } else {
    const used = new Set(workout.exercises.map((e) => e.supersetGroup).filter(Boolean));
    let letter = above.supersetGroup;
    if (!letter) {
      letter = 'ABCDEFGHIJ'.split('').find((l) => !used.has(l)) || 'Z';
      above.supersetGroup = letter;
    }
    entry.supersetGroup = letter;
  }
  // a group of one is no superset
  for (const e of workout.exercises) {
    if (e.supersetGroup && workout.exercises.filter((x) => x.supersetGroup === e.supersetGroup).length < 2) delete e.supersetGroup;
  }
  await persist();
}

/** The cards of the superset this card belongs to, in order (just the card itself if none). */
export function supersetOf(workout, entry) {
  if (!entry.supersetGroup) return [entry];
  return workout.exercises.filter((e) => e.supersetGroup === entry.supersetGroup);
}

/** Seconds to change to the next exercise of a superset. */
export const SUPERSET_CHANGE_SEC = 15;

/** "Start set" was tapped: remember when. That also ends the rest. */
export async function startSet() {
  current.state.setStartedAt = nowIso();
  await saveState();
}

export async function cancelSet() {
  current.state.setStartedAt = null;
  await saveState();
}

/**
 * Log a finished set. values = { weightKg, reps, repsLeft, partials, type }.
 * The rest timer starts by itself: it simply measures from this set's completedAt.
 * In a superset the next card of the round opens, with a short change time
 * instead of the rest.
 */
export async function logSet(entryId, values) {
  const { workout, state } = current;
  const entry = workout.exercises.find((e) => e.id === entryId);
  const plan = state.plan[entryId];
  const group = supersetOf(workout, entry);
  const position = group.indexOf(entry);
  const lastOfRound = position === group.length - 1 || values.type !== 'work';
  const set = {
    id: uuid(),
    order: entry.sets.length,
    type: values.type,
    weightKg: values.weightKg,
    reps: values.reps,
    rpe: null,                         // part of the file format; the app does not ask for it
    startedAt: state.entryId === entryId ? state.setStartedAt : null,
    completedAt: nowIso(),
    targetRestSec: lastOfRound ? ((plan && plan.restSec) || settings().defaultRestSec) : SUPERSET_CHANGE_SEC,
  };
  if (values.repsLeft !== null && values.repsLeft !== undefined) set.repsLeft = values.repsLeft;
  if (values.partials > 0) set.partials = values.partials;
  entry.sets.push(set);
  if (set.type === 'warmup' && state.warmups && state.warmups[entryId]) state.warmups[entryId].shift();
  // Warm-ups and the parts of a drop / rest-pause set are not part of a superset round.
  state.entryId = set.type !== 'work' || group.length === 1 ? entryId : group[(position + 1) % group.length].id;
  state.setStartedAt = null;
  await persist();
  return set;
}

/**
 * Plan warm-up sets for a card; the next sets are then pre-filled with them,
 * and after them the working weight they were planned for (work).
 */
export async function setWarmups(entryId, list, work = null) {
  if (!current.state.warmups) current.state.warmups = {};
  if (!current.state.warmupWork) current.state.warmupWork = {};
  current.state.warmups[entryId] = list;
  if (work) current.state.warmupWork[entryId] = work;
  await saveState();
}

/** Warm-up sets still planned for a card ([] if none). */
export function plannedWarmups(entryId) {
  const all = current && current.state.warmups;
  return (all && all[entryId]) || [];
}

/** Make the running rest longer or shorter. The exercise remembers the new target. */
export async function adjustRest(deltaSec) {
  const { workout, state } = current;
  const last = lastCompletedSet(workout);
  if (!last) return;
  const target = Math.min(900, Math.max(15, (last.set.targetRestSec || settings().defaultRestSec) + deltaSec));
  last.set.targetRestSec = target;
  if (!state.plan[last.entry.id]) state.plan[last.entry.id] = { targetSets: null, restSec: target, repsMin: null, repsMax: null };
  // The change time inside a superset is not the exercise's rest.
  const group = supersetOf(workout, last.entry);
  if (group.indexOf(last.entry) === group.length - 1) state.plan[last.entry.id].restSec = target;
  // If the end moved into the future again, the signal may fire again.
  if (Date.parse(last.set.completedAt) + target * 1000 > Date.now()) state.signalledSetId = null;
  await persist();
}

export async function setRestExpanded(expanded) {
  current.state.restExpanded = expanded;
  await saveState();
}

/**
 * Change the running workout in any other way (edit a set, notes, name …):
 *   await changeActive((workout) => { workout.notes = 'felt good'; });
 */
export async function changeActive(change) {
  const { workout, state } = current;
  change(workout, state);
  if (state.entryId && !workout.exercises.some((e) => e.id === state.entryId)) {
    state.entryId = workout.exercises.length ? workout.exercises[workout.exercises.length - 1].id : null;
    state.setStartedAt = null;
  }
  await persist();
}

/** Finish the running workout. Exercises without sets are dropped. Returns the finished record. */
export async function finishWorkout() {
  const { workout } = current;
  workout.exercises = workout.exercises.filter((entry) => entry.sets.length > 0);
  workout.finishedAt = nowIso();
  await persist();
  await db.setMeta('active', null);
  current = null;
  await syncWakeLock();
  return workout;
}

/** Throw the running workout away (it was never exported, so nothing else knows it). */
export async function discardWorkout() {
  await db.remove('workouts', current.workout.id);
  await db.setMeta('active', null);
  current = null;
  await syncWakeLock();
}

/* ---------- Finished workouts that are still on the phone ---------- */

/** All finished, not deleted workouts on the phone, newest first. */
export async function listFinishedWorkouts() {
  const all = await db.getAll('workouts');
  return all.filter((w) => w.finishedAt && !w.deletedAt).sort((a, b) => (a.startedAt < b.startedAt ? 1 : -1));
}

/** Save changes to a finished workout. The new updatedAt puts it into the next export. */
export async function saveWorkout(workout) {
  renumber(workout);
  workout.updatedAt = nowIso();
  await db.put('workouts', workout);
}

/**
 * Delete a finished workout. Normally it was never exported and can simply go.
 * Rare case: it was finished before the last export (so the Windows app may
 * have it) and changed afterwards. Then it is only marked as deleted, so the
 * next export tells the Windows app; after that export it disappears.
 */
export async function deleteWorkout(workout) {
  const lastExportAt = await db.getMeta('lastExportAt', null);
  if (lastExportAt && workout.finishedAt <= lastExportAt) {
    workout.deletedAt = nowIso();
    await saveWorkout(workout);
  } else {
    await db.remove('workouts', workout.id);
  }
}

/* ---------- Progression, warm-ups and pre-filling the next set ---------- */

/**
 * Double progression: when every working set last time reached the top of the
 * rep target (12 of 8–12, or 10 of a fixed 10), the weight goes up one step
 * and the reps start again at the bottom of the range.
 * Returns { weightKg, reps, text } or null when it is not time yet.
 */
export function progression(lastSession, plan, exercise) {
  if (!lastSession || !plan || !plan.repsMax || !exercise) return null;
  const work = lastSession.sets.filter((set) => set.type === 'work');
  if (work.length === 0 || !work.every((set) => effectiveReps(set) >= plan.repsMax)) return null;
  const top = Math.max(...work.map((set) => set.weightKg));
  const step = weightStep(exercise);
  if (exercise.loadType === 'assisted') {
    if (top <= 0) return null;
    return { weightKg: roundKg(Math.max(0, top - step)), reps: plan.repsMin, text: `Letztes Mal alle Sätze ≥ ${plan.repsMax} → ${step} kg weniger Unterstützung` };
  }
  return { weightKg: roundKg(top + step), reps: plan.repsMin, text: `Letztes Mal alle Sätze ≥ ${plan.repsMax} → +${String(step).replace('.', ',')} kg` };
}

/**
 * Warm-up sets before the first working set, for multi-joint exercises from
 * about 40 kg: 40 % × 8, 60 % × 5, 80 % × 3 of the working weight (with a
 * barbell first the empty bar × 10), rounded to the exercise's step.
 */
export function warmupPlan(workWeightKg, exercise) {
  if (!exercise || exercise.loadType !== 'external' || !(workWeightKg >= 20)) return [];
  const step = weightStep(exercise);
  const round = (kg) => Math.round(kg / step) * step;
  const barKg = settings().barKg;
  const barbell = exercise.equipment === 'barbell' && (exercise.load || 'total') === 'total';
  const steps = exercise.compound ? [[0.4, 8], [0.6, 5], [0.8, 3]] : [[0.5, 10], [0.75, 5]];
  const plan = barbell && workWeightKg > barKg ? [{ weightKg: barKg, reps: 10 }] : [];
  for (const [share, reps] of steps) {
    let kg = round(workWeightKg * share);
    if (barbell) kg = Math.max(kg, barKg);
    if (kg <= 0 || kg >= workWeightKg || plan.some((set) => set.weightKg >= kg)) continue;
    plan.push({ weightKg: roundKg(kg), reps });
  }
  return plan;
}

/**
 * What goes into the fields for the next set:
 *  1. a planned warm-up set                  → that one
 *  2. after a working set today              → the same again
 *     after the planned warm-ups             → the weight they were planned for
 *  3. first working set and time to progress → the heavier weight
 *  4. otherwise                              → the matching set from last time
 *  5. no history at all                      → empty fields
 * With a rep target from the template, working sets start at it (for a range:
 * the lower end). Returns { weightKg, reps, repsLeft, type }.
 */
export function prefill(entry, lastSession, plan, exercise = null) {
  const warmup = plannedWarmups(entry.id)[0];
  if (warmup) return { weightKg: warmup.weightKg, reps: warmup.reps, repsLeft: null, type: 'warmup' };
  const previous = entry.sets[entry.sets.length - 1];
  const doneWork = entry.sets.filter((set) => set.type === 'work').length;
  const lastWork = lastSession ? lastSession.sets.filter((set) => set.type === 'work') : [];
  const step = progression(lastSession, plan, exercise);
  const planned = current && current.state.warmupWork ? current.state.warmupWork[entry.id] : null;
  let guess = { weightKg: null, reps: null, repsLeft: null, type: 'work' };
  if (previous && previous.type !== 'warmup') guess = { weightKg: previous.weightKg, reps: previous.reps, repsLeft: null, type: 'work' };
  else if (doneWork === 0 && planned) guess = { weightKg: planned.weightKg, reps: planned.reps, repsLeft: null, type: 'work' };
  else if (doneWork === 0 && step) guess = { weightKg: step.weightKg, reps: step.reps, repsLeft: null, type: 'work' };
  else if (lastWork[doneWork]) guess = { weightKg: lastWork[doneWork].weightKg, reps: lastWork[doneWork].reps, repsLeft: null, type: 'work' };
  else if (lastWork.length) guess = { weightKg: lastWork[lastWork.length - 1].weightKg, reps: lastWork[lastWork.length - 1].reps, repsLeft: null, type: 'work' };
  else if (previous) guess = { weightKg: previous.weightKg, reps: previous.reps, repsLeft: null, type: 'work' };
  if (plan && plan.repsMin && guess.type === 'work') guess.reps = plan.repsMin;
  return guess;
}

/* ---------- Timing, always calculated from timestamps ---------- */

/** The most recently logged set of a workout: { entry, set } or null. */
export function lastCompletedSet(workout) {
  let best = null;
  for (const entry of workout.exercises) {
    for (const set of entry.sets) {
      if (set.completedAt && (!best || set.completedAt > best.set.completedAt)) best = { entry, set };
    }
  }
  return best;
}

/**
 * For every set: how long it took and how long the pause before it was.
 * Returns a Map: set id → { durationMs, restBeforeMs } (null where unknown).
 *  - durationMs needs "Start set" to have been tapped
 *  - restBeforeMs runs from the previous set's log time to this set's start
 *    (or to its log time when "Start set" was skipped)
 */
export function setTimings(workout) {
  const sets = [];
  for (const entry of workout.exercises) {
    for (const set of entry.sets) if (set.completedAt) sets.push(set);
  }
  sets.sort((a, b) => (a.completedAt < b.completedAt ? -1 : 1));
  const timings = new Map();
  let previous = null;
  for (const set of sets) {
    const end = Date.parse(set.completedAt);
    const start = set.startedAt ? Date.parse(set.startedAt) : null;
    timings.set(set.id, {
      durationMs: start !== null ? end - start : null,
      restBeforeMs: previous ? (start !== null ? start : end) - Date.parse(previous.completedAt) : null,
    });
    previous = set;
  }
  return timings;
}

/** For one exercise card: how long it took, and the pause before it. Null where unknown. */
export function entryTiming(entry, timings) {
  const timed = entry.sets.filter((set) => set.completedAt);
  if (timed.length === 0) return { durationMs: null, pauseBeforeMs: null };
  const first = timed[0];
  const last = timed[timed.length - 1];
  const firstTiming = timings.get(first.id);
  return {
    durationMs: Date.parse(last.completedAt) - Date.parse(first.startedAt || first.completedAt),
    pauseBeforeMs: firstTiming ? firstTiming.restBeforeMs : null,
  };
}

/**
 * The rest that is running right now, or null (no set logged yet, or a set is
 * in progress). remainingMs goes below zero once the target time is over.
 */
export function restInfo(now = Date.now()) {
  if (!current || current.state.setStartedAt) return null;
  const last = lastCompletedSet(current.workout);
  if (!last) return null;
  const targetMs = (last.set.targetRestSec || settings().defaultRestSec) * 1000;
  const elapsedMs = now - Date.parse(last.set.completedAt);
  return { entry: last.entry, set: last.set, targetMs, elapsedMs, remainingMs: targetMs - elapsedMs };
}

/**
 * Called by the clock four times per second, on every screen: vibrates and
 * flashes at the moment the rest time runs out.
 */
export function watchRest(now) {
  const info = restInfo(now);
  if (!info || info.remainingMs > 0 || current.state.signalledSetId === info.set.id) return;
  current.state.signalledSetId = info.set.id;    // never twice for the same rest
  saveState();
  // Only signal if the time ran out while the app was open. Coming back to the
  // app minutes later should not buzz; the panel then just shows "+2:10".
  const ranOutJustNow = info.remainingMs > -3000;
  if (ranOutJustNow && !document.hidden) {
    if (settings().vibrateOn) vibrate();
    flashScreen();
  }
}

/** The headline numbers of a workout. workSets counts hard sets (a drop set part is ½). */
export function summarize(workout, bodyWeightKg) {
  let workSets = 0;
  let volumeKg = 0;
  let exerciseCount = 0;
  for (const entry of workout.exercises) {
    if (entry.sets.length > 0) exerciseCount++;
    const exercise = getExercise(entry.exerciseId);
    for (const set of entry.sets) {
      workSets += hardSetValue(set, exercise);
      volumeKg += setVolumeKg(set, exercise, bodyWeightKg);
    }
  }
  const end = workout.finishedAt ? Date.parse(workout.finishedAt) : Date.now();
  return { durationMs: end - Date.parse(workout.startedAt), exerciseCount, workSets, volumeKg };
}
