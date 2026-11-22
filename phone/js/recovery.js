// recovery.js — which muscles are still tired from the last days (an estimate).
//
// THE MODEL (simple on purpose)
// Every hard set of the last 72 hours puts load on its muscles: 1 for a
// primary muscle, the exercise's share (0.1 to 0.9) for a secondary one. The
// load fades in a straight line to zero over 72 hours, the usual time a muscle
// needs after a hard session. What is left decides:
//   'tired'       4 or more     (e.g. 6 hard sets yesterday)
//   'recovering'  1.5 to 4
//   'fresh'       less
// Cardio (minutes) and warm-ups put no load on a muscle.
//
// It needs no data of its own: the workouts still on the phone, and for
// exported ones the last session per exercise that records.js keeps anyway.

import * as db from './db.js';
import { getExercise, getMuscles, muscleShare } from './library.js';
import { hardSetValue } from './format.js';

export const WINDOW_HOURS = 72;
const TIRED = 4;
const RECOVERING = 1.5;

/**
 * Map muscle id → { role: 'tired' | 'recovering' | 'fresh', load, lastAt, exercises }
 * now: a time in milliseconds (for the tests).
 */
export async function muscleRecovery(now = Date.now()) {
  const hoursAgo = (iso) => (now - Date.parse(iso)) / 3600000;
  const inWindow = (iso) => hoursAgo(iso) >= 0 && hoursAgo(iso) < WINDOW_HOURS;

  // The sessions of the window: workout + exercise → its sets (also the running workout).
  const sessions = new Map();
  for (const workout of await db.getAll('workouts')) {
    if (workout.deletedAt || !inWindow(workout.startedAt)) continue;
    for (const entry of workout.exercises) {
      const key = `${workout.id}|${entry.exerciseId}`;
      const known = sessions.get(key);
      sessions.set(key, { exerciseId: entry.exerciseId, at: workout.startedAt, sets: (known ? known.sets : []).concat(entry.sets) });
    }
  }
  for (const stats of await db.getAll('exerciseStats')) {
    const last = stats.lastSession;
    if (!last || !inWindow(last.startedAt)) continue;
    const key = `${last.workoutId}|${stats.exerciseId}`;
    if (!sessions.has(key)) sessions.set(key, { exerciseId: stats.exerciseId, at: last.startedAt, sets: last.sets });
  }

  const result = new Map(getMuscles().map((muscle) => [muscle.id, { role: 'fresh', load: 0, lastAt: null, exercises: [] }]));
  for (const session of sessions.values()) {
    const exercise = getExercise(session.exerciseId);
    if (!exercise) continue;
    const hard = session.sets.reduce((sum, set) => sum + hardSetValue(set, exercise), 0);
    if (hard <= 0) continue;
    const left = Math.max(0, 1 - hoursAgo(session.at) / WINDOW_HOURS);
    for (const [id, muscle] of result) {
      const share = muscleShare(exercise, id);
      if (!share) continue;
      muscle.load += hard * share * left;
      if (!muscle.lastAt || session.at > muscle.lastAt) muscle.lastAt = session.at;
      if (!muscle.exercises.includes(exercise.name)) muscle.exercises.push(exercise.name);
    }
  }
  for (const muscle of result.values()) {
    muscle.load = Math.round(muscle.load * 10) / 10;
    muscle.role = muscle.load >= TIRED ? 'tired' : muscle.load >= RECOVERING ? 'recovering' : 'fresh';
  }
  return result;
}

/** Is any muscle still tired or recovering? (Otherwise Home shows no card: all fresh.) */
export function anyLoad(recovery) {
  for (const muscle of recovery.values()) if (muscle.role !== 'fresh') return true;
  return false;
}
