// records.js — what you did before: "last time", personal records, and the
// volume record per exercise (for the gold).
//
// TWO SOURCES
// Finished workouts that are not exported yet are still in the "workouts"
// store, with all details. Exported workouts have left the phone; before they
// left, everything this file needs was copied into a small summary per
// exercise (store "exerciseStats", see foldIntoStats). Every function here
// looks at both.
//
// WHICH SETS COUNT
// Only normal working sets ("work") count for records and the gold. Warm-ups,
// drop sets and rest-pause parts never make a record.

import * as db from './db.js';
import { getExercise } from './library.js';
import { setVolumeKg, effectiveReps, repUnit } from './format.js';

const MAX_SETS = 12;            // the volume record is kept for up to 12 working sets

/* ---------- Records ---------- */

/**
 * Estimated one-rep max (Epley formula): the weight you could probably lift once.
 * It is only used where it means something: multi-joint exercises with free
 * weights or machines, and sets of at most 8 reps (above that it gets inaccurate).
 */
export function epley(weightKg, reps) {
  return reps === 1 ? weightKg : weightKg * (1 + reps / 30);
}

/** Does this exercise get an estimated 1RM at all? */
export function hasE1rm(exercise) {
  return Boolean(exercise && exercise.compound && exercise.loadType === 'external' && !exercise.unit);
}

/** Is this set short enough for a sensible 1RM estimate? */
export function e1rmSet(set) {
  return effectiveReps(set) <= 8;
}

/** An empty record for one exercise. */
function emptyRecord() {
  return { maxWeightKg: -1, bestE1rm: 0, bestSet: null, repsAt: new Map(), volumeBySets: [] };
}

/** Add one set to the record of its exercise. Only working sets count. */
function addSet(record, set, exercise) {
  if (set.type !== 'work') return;
  const reps = effectiveReps(set);
  const best = record.bestSet;
  if (!best || set.weightKg > best.weightKg || (set.weightKg === best.weightKg && reps > best.reps)) {
    record.bestSet = { weightKg: set.weightKg, reps };
  }
  record.maxWeightKg = Math.max(record.maxWeightKg, set.weightKg);
  if (hasE1rm(exercise) && e1rmSet(set)) record.bestE1rm = Math.max(record.bestE1rm, epley(set.weightKg, reps));
  record.repsAt.set(set.weightKg, Math.max(record.repsAt.get(set.weightKg) || 0, reps));
}

/** The sets of each exercise in one workout: Map exercise id → sets. */
function setsByExercise(workout) {
  const result = new Map();
  for (const entry of workout.exercises) {
    if (entry.sets.length === 0) continue;
    if (!result.has(entry.exerciseId)) result.set(entry.exerciseId, []);
    result.get(entry.exerciseId).push(...entry.sets);
  }
  return result;
}

/**
 * The volume record works "at the same number of sets": [vol of 1st set,
 * vol of sets 1–2, vol of sets 1–3, …] of the working sets of one workout.
 * A 5th, sloppy set therefore never wins against a strong workout with 4 sets:
 * it is compared with the first 5 sets of earlier workouts that had 5 sets.
 */
export function volumeBySets(sets, exercise, bodyWeightKg) {
  const result = [];
  let sum = 0;
  for (const set of sets) {
    if (set.type !== 'work') continue;
    sum += setVolumeKg(set, exercise, bodyWeightKg);
    result.push(sum);
    if (result.length === MAX_SETS) break;
  }
  return result;
}

/** Keep the best of two lists, place by place. */
function bestOf(a, b) {
  const result = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) result.push(Math.max(a[i] || 0, b[i] || 0));
  return result;
}

/** A stored summary back into a record (the summary keeps repsAt as a list of pairs). */
function recordFromStats(stats) {
  return {
    maxWeightKg: stats.maxWeightKg,
    bestE1rm: stats.bestE1rm,
    bestSet: stats.bestSet,
    repsAt: new Map(stats.repsAt),
    volumeBySets: stats.volumeBySets || [],
  };
}

/**
 * Your best results per exercise, from everything before the given workout.
 * Returns a Map: exercise id → {
 *   maxWeightKg   heaviest weight ever used
 *   bestE1rm      best estimated one-rep max (0 for exercises without one)
 *   bestSet       the heaviest set { weightKg, reps } (most reps at that weight)
 *   repsAt        Map: weight → most reps ever done with it
 *   volumeBySets  best volume of the first 1, 2, 3 … working sets of one workout
 * }
 */
export async function loadRecords(excludeWorkoutId, bodyWeightKg) {
  const records = new Map();
  for (const stats of await db.getAll('exerciseStats')) {
    if (stats.bestSet) records.set(stats.exerciseId, recordFromStats(stats));
  }
  for (const workout of await db.getAll('workouts')) {
    if (workout.id === excludeWorkoutId || !workout.finishedAt || workout.deletedAt) continue;
    for (const [exerciseId, sets] of setsByExercise(workout)) {
      const exercise = getExercise(exerciseId);
      if (!records.has(exerciseId)) records.set(exerciseId, emptyRecord());
      const record = records.get(exerciseId);
      sets.forEach((set) => addSet(record, set, exercise));
      record.volumeBySets = bestOf(record.volumeBySets, volumeBySets(sets, exercise, bodyWeightKg));
    }
  }
  return records;
}

/**
 * Which sets of this workout are new personal records?
 * `history` comes from loadRecords(). Returns a Map: set id → { kind, weightKg }
 *   kind 'weight'  heavier than ever before
 *   kind 'e1rm'    best estimated one-rep max
 *   kind 'reps'    more reps than ever before with this weight
 * The very first time you do an exercise nothing counts as a record.
 */
export function findNewRecords(workout, history) {
  // Work on copies, so a set can raise the bar for the sets after it.
  const running = new Map();
  for (const [exerciseId, record] of history) {
    running.set(exerciseId, { ...record, repsAt: new Map(record.repsAt) });
  }
  const sets = [];
  for (const entry of workout.exercises) {
    for (const set of entry.sets) sets.push({ exerciseId: entry.exerciseId, set });
  }
  sets.sort((a, b) => (a.set.completedAt || '').localeCompare(b.set.completedAt || ''));

  const found = new Map();
  for (const { exerciseId, set } of sets) {
    if (set.type !== 'work') continue;
    const before = running.get(exerciseId);
    if (!before) continue;
    const exercise = getExercise(exerciseId);
    const loadType = exercise ? exercise.loadType : 'external';
    const reps = effectiveReps(set);
    const repsBefore = before.repsAt.get(set.weightKg);
    if (loadType !== 'assisted' && set.weightKg > before.maxWeightKg) {
      found.set(set.id, { kind: 'weight', weightKg: set.weightKg });
    } else if (hasE1rm(exercise) && e1rmSet(set) && epley(set.weightKg, reps) > before.bestE1rm + 0.001) {
      found.set(set.id, { kind: 'e1rm', weightKg: set.weightKg });
    } else if (repsBefore !== undefined && reps > repsBefore) {
      found.set(set.id, { kind: 'reps', weightKg: set.weightKg, unit: exercise ? exercise.unit : undefined });
    }
    addSet(before, set, exercise);
  }
  return found;
}

/**
 * The volume comparison of one exercise in a workout, or null when there is
 * nothing to compare with yet. Returns { sets, todayKg, bestKg, gold }:
 *   sets     how many working sets are compared (today's count, or fewer if
 *            you never did that many before)
 *   todayKg  volume of today's first `sets` working sets
 *   bestKg   best volume of the first `sets` working sets in any workout before
 *   gold     todayKg beats bestKg
 */
export function volumeComparison(workout, exerciseId, record, bodyWeightKg) {
  if (!record || record.volumeBySets.length === 0) return null;
  if (repUnit(getExercise(exerciseId)) !== 'reps') return null;       // timed: no volume in kg
  const sets = setsByExercise(workout).get(exerciseId) || [];
  const today = volumeBySets(sets, getExercise(exerciseId), bodyWeightKg);
  if (today.length === 0) return null;
  const count = Math.min(today.length, record.volumeBySets.length);
  const todayKg = today[count - 1];
  const bestKg = record.volumeBySets[count - 1];
  return { sets: count, todayKg, bestKg, gold: bestKg > 0 && todayKg > bestKg + 0.001 };
}

/* ---------- Last time ---------- */

/**
 * The most recent earlier session of an exercise: { workoutId, startedAt, sets }
 * or null. Used for "Letztes Mal: 60 kg × 8", the pre-filled fields, the
 * progression hint and the rest time.
 */
export async function getLastSession(exerciseId, excludeWorkoutId) {
  let found = null;
  const workout = await db.findNewestWorkout((w) =>
    w.id !== excludeWorkoutId && w.finishedAt && !w.deletedAt &&
    w.exercises.some((entry) => entry.exerciseId === exerciseId && entry.sets.length > 0));
  if (workout) {
    found = { workoutId: workout.id, startedAt: workout.startedAt, sets: setsByExercise(workout).get(exerciseId) };
  }
  const stats = await db.get('exerciseStats', exerciseId);
  if (stats && stats.lastSession && (!found || stats.lastSession.startedAt > found.startedAt)) {
    found = stats.lastSession;
  }
  return found;
}

/* ---------- Trend: a small line of the last sessions per exercise ---------- */

const TREND_POINTS = 12;        // sessions kept per exercise for the trend line

/** "2026-11-21" in the phone's time zone. */
export function localDay(iso) {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/**
 * A strength score for one session: its best working set by the Epley formula
 * (for isolation exercises too: here it only compares sessions with each
 * other). Only exercises with added weight, counted in reps: for body-weight
 * exercises a change of body weight would look like progress. null if none.
 */
export function sessionScore(sets, exercise) {
  if (!exercise || exercise.loadType !== 'external' || repUnit(exercise) !== 'reps') return null;
  let best = 0;
  for (const set of sets) {
    if (set.type !== 'work' || !(set.weightKg > 0)) continue;
    const reps = effectiveReps(set);
    if (reps > 0) best = Math.max(best, epley(set.weightKg, reps));
  }
  return best > 0 ? Math.round(best * 10) / 10 : null;
}

/** Add a session to a trend: one point per day (the better one), sorted, the newest 12. */
export function addTrendPoint(points, day, score) {
  const list = (points || []).filter((point) => point.d !== day || point.s > score);
  if (!list.some((point) => point.d === day)) list.push({ d: day, s: score });
  return list.sort((a, b) => (a.d < b.d ? -1 : a.d > b.d ? 1 : 0)).slice(-TREND_POINTS);
}

/** The trend of every exercise: Map exercise id → [{ d: day, s: score }], oldest first. */
export async function loadTrends(excludeWorkoutId) {
  const trends = new Map();
  for (const stats of await db.getAll('exerciseStats')) {
    if (stats.trend && stats.trend.length) trends.set(stats.exerciseId, stats.trend);
  }
  for (const workout of await db.getAll('workouts')) {
    if (workout.id === excludeWorkoutId || !workout.finishedAt || workout.deletedAt) continue;
    for (const [exerciseId, sets] of setsByExercise(workout)) {
      const score = sessionScore(sets, getExercise(exerciseId));
      if (score !== null) trends.set(exerciseId, addTrendPoint(trends.get(exerciseId), localDay(workout.startedAt), score));
    }
  }
  return trends;
}

/* ---------- Keeping the summary when workouts leave the phone ---------- */

/** Only what "last time", the prefill and the progression hint need of a set. */
function slimSet(set) {
  const slim = { type: set.type, weightKg: set.weightKg, reps: set.reps, targetRestSec: set.targetRestSec };
  if (set.repsLeft !== null && set.repsLeft !== undefined) slim.repsLeft = set.repsLeft;
  return slim;
}

/**
 * Copy everything "last time", the records and the gold need from one workout
 * into the summary per exercise. Doing it twice for the same workout changes
 * nothing: it only keeps maximums and the newest session.
 */
export async function foldIntoStats(workout, bodyWeightKg) {
  for (const [exerciseId, sets] of setsByExercise(workout)) {
    const exercise = getExercise(exerciseId);
    const stored = await db.get('exerciseStats', exerciseId);
    const record = stored && stored.bestSet ? recordFromStats(stored) : emptyRecord();
    sets.forEach((set) => addSet(record, set, exercise));
    const session = { workoutId: workout.id, startedAt: workout.startedAt, sets: sets.map(slimSet) };
    const keepOld = stored && stored.lastSession && stored.lastSession.startedAt > session.startedAt;
    const score = sessionScore(sets, exercise);
    const trend = score === null ? (stored && stored.trend) : addTrendPoint(stored && stored.trend, localDay(workout.startedAt), score);
    await db.put('exerciseStats', {
      exerciseId,
      maxWeightKg: record.maxWeightKg,
      bestE1rm: record.bestE1rm,
      bestSet: record.bestSet,
      repsAt: [...record.repsAt],
      volumeBySets: bestOf(record.volumeBySets, volumeBySets(sets, exercise, bodyWeightKg)),
      lastSession: keepOld ? stored.lastSession : session,
      ...(trend && trend.length ? { trend } : {}),      // 12 small points at most: { d: day, s: score }
    });
  }
}
