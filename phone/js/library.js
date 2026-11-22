// library.js — the exercise library: built-in exercises plus your own.
//
// The built-in list lives in shared/exercises.json (the Windows app uses the
// same file). At start-up it is merged into the database. Exercises are also
// kept in memory, because nearly every screen needs their names.

import * as db from './db.js';
import { nowIso, uuid } from './util.js';

let muscles = [];                 // [{ id: 'chest', name: 'Brust (Mitte/unten)', region: 'upper' }, …]

// The shared library has English names (the Windows app uses them); the phone
// shows the muscle groups in German. Exercise names stay as they are: most
// gyms use the English names anyway.
const MUSCLE_NAMES = {
  upper_chest: 'Obere Brust', chest: 'Brust (Mitte/unten)', front_delts: 'Vordere Schulter',
  side_delts: 'Seitliche Schulter', rear_delts: 'Hintere Schulter', neck: 'Nacken', traps: 'Trapez',
  rotator_cuff: 'Rotatorenmanschette', upper_back: 'Oberer Rücken', lats: 'Latissimus', biceps: 'Bizeps', brachialis: 'Brachialis',
  triceps: 'Trizeps', brachioradialis: 'Brachioradialis', forearm_flexors: 'Unterarm-Beuger',
  forearm_extensors: 'Unterarm-Strecker', abs: 'Bauch', obliques: 'Seitliche Bauchmuskeln',
  lower_back: 'Unterer Rücken', glutes: 'Gesäß', abductors: 'Abduktoren', adductors: 'Adduktoren',
  quads: 'Quadrizeps', hamstrings: 'Beinbeuger', calves: 'Waden', tibialis: 'Schienbeinmuskel',
};

// Fields you can change yourself. A library update never overwrites them on an
// exercise you edited; it only fills in fields that are missing.
const OWN_FIELDS = ['name', 'primaryMuscles', 'secondaryMuscles', 'muscleShares', 'movement', 'equipment',
  'loadType', 'bodyweightFraction', 'compound', 'load', 'weightStep', 'unit', 'cues'];
const exercises = new Map();      // id → exercise, deleted ones included

/** Load the exercises from the database, then merge in the shared library file. */
export async function loadLibrary() {
  await reloadFromDb();
  muscles = await db.getMeta('muscles', []);
  try {
    // Works offline too: the service worker keeps a copy of the file.
    const response = await fetch('../shared/exercises.json');
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    await mergeLibrary(await response.json());
  } catch (error) {
    if (exercises.size === 0) throw new Error('Die Übungsliste konnte nicht geladen werden. Öffne die App einmal mit Internet.');
  }
}

/** Read all exercises from the database again (after an import). */
export async function reloadFromDb() {
  exercises.clear();
  const upgraded = [];
  for (const stored of await db.getAll('exercises')) {
    const exercise = upgradeMuscles(stored);
    if (exercise !== stored) upgraded.push(exercise);
    exercises.set(exercise.id, exercise);
  }
  if (upgraded.length) await db.putMany('exercises', upgraded);
}

/**
 * Older versions had one muscle group "forearms". It is now split into
 * brachioradialis, forearm flexors and forearm extensors; an exercise of your
 * own that still says "forearms" (mostly grip work) is moved to the flexors.
 * Returns the same object if nothing had to change.
 */
function upgradeMuscles(exercise) {
  const old = 'forearms';
  const has = (list) => (list || []).includes(old);
  if (!has(exercise.primaryMuscles) && !has(exercise.secondaryMuscles)) return exercise;
  const swap = (list) => [...new Set((list || []).map((m) => (m === old ? 'forearm_flexors' : m)))];
  const record = { ...exercise, primaryMuscles: swap(exercise.primaryMuscles), secondaryMuscles: swap(exercise.secondaryMuscles) };
  record.secondaryMuscles = record.secondaryMuscles.filter((m) => !record.primaryMuscles.includes(m));
  if (record.muscleShares && old in record.muscleShares) {
    record.muscleShares = { ...record.muscleShares, forearm_flexors: record.muscleShares[old] };
    delete record.muscleShares[old];
  }
  return record;
}

/**
 * Copy built-in exercises into the database. An exercise you edited yourself
 * is marked "editedByUser": its own fields are never overwritten, so your
 * muscle mapping survives every update of the library. Only fields it does not
 * have yet (new in the library) are added. Your machine note ("setup") always stays.
 *
 * A built-in exercise that is no longer in the library is removed (marked
 * deleted, so the next export tells the Windows app). Workouts that used it keep
 * their data and still show its name. Exercises you created yourself always stay.
 */
async function mergeLibrary(library) {
  muscles = library.muscles.map((m) => ({ ...m, name: MUSCLE_NAMES[m.id] || m.name }));
  await db.setMeta('muscles', muscles);
  const changed = [];
  for (const item of library.exercises) {
    const mine = exercises.get(item.id);
    let record = null;
    if (mine && mine.editedByUser) {
      const missing = Object.keys(item).filter((key) => !(key in mine) && OWN_FIELDS.includes(key));
      if (missing.length === 0) continue;
      record = { ...mine };
      missing.forEach((key) => { record[key] = item[key]; });
    } else if (mine && mine.updatedAt >= library.updatedAt) {
      continue;
    } else {
      record = { ...item, isCustom: false, updatedAt: library.updatedAt, deletedAt: null };
      if (mine && mine.setup) record.setup = mine.setup;
    }
    exercises.set(record.id, record);
    changed.push(record);
  }
  const inLibrary = new Set(library.exercises.map((item) => item.id));
  for (const mine of [...exercises.values()]) {
    if (mine.isCustom || mine.deletedAt || inLibrary.has(mine.id)) continue;
    const removed = { ...mine, updatedAt: library.updatedAt > mine.updatedAt ? library.updatedAt : mine.updatedAt, deletedAt: library.updatedAt };
    exercises.set(removed.id, removed);
    changed.push(removed);
  }
  await db.putMany('exercises', changed);
}

/** The muscle groups, in body order. */
export function getMuscles() {
  return muscles;
}

/** 'front_delts' → 'Vordere Schulter' */
export function muscleName(id) {
  const muscle = muscles.find((m) => m.id === id);
  return muscle ? muscle.name : (MUSCLE_NAMES[id] || id);
}

/**
 * How much one set of the exercise counts for a muscle: 1 for a primary
 * muscle, the exercise's own share for a secondary one (0.1 to 0.9, default 0.5), else 0.
 */
export function muscleShare(exercise, muscleId) {
  if (!exercise) return 0;
  if (exercise.primaryMuscles.includes(muscleId)) return 1;
  if (!exercise.secondaryMuscles.includes(muscleId)) return 0;
  const shares = exercise.muscleShares || {};
  return shares[muscleId] === undefined ? 0.5 : shares[muscleId];
}

/** One exercise by id. Deleted ones are found too, so old workouts keep their names. */
export function getExercise(id) {
  return exercises.get(id) || null;
}

/** All exercises that are not deleted, sorted by name. */
export function listExercises() {
  return [...exercises.values()]
    .filter((exercise) => !exercise.deletedAt)
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Save a new or changed exercise. Returns the saved record. */
export async function saveExercise(exercise) {
  const record = {
    ...exercise,
    id: exercise.id || uuid(),
    isCustom: exercise.id ? Boolean(exercise.isCustom) : true,
    editedByUser: true,             // library updates leave this exercise alone
    updatedAt: nowIso(),
    deletedAt: null,
  };
  exercises.set(record.id, record);
  await db.put('exercises', record);
  return record;
}

/**
 * Save your machine note ("Sitz 4, Studio A"). This is not a change of the
 * exercise itself, so library updates may still update it.
 */
export async function saveSetup(id, text) {
  const exercise = exercises.get(id);
  if (!exercise) return;
  const record = { ...exercise, setup: text.trim().slice(0, 200), updatedAt: nowIso() };
  if (!record.setup) delete record.setup;
  exercises.set(id, record);
  await db.put('exercises', record);
}

/**
 * Delete one of your own exercises. It is only marked as deleted, so old
 * workouts keep its name and the Windows app learns about it with the next export.
 */
export async function deleteExercise(id) {
  const exercise = exercises.get(id);
  if (!exercise) return;
  const now = nowIso();
  const record = { ...exercise, updatedAt: now, deletedAt: now };
  exercises.set(id, record);
  await db.put('exercises', record);
}
