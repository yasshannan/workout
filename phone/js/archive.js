// archive.js — workouts leave the phone after they were exported.
//
// After an export the details of a workout are in the file (and in the Windows
// app), so the phone does not need them any more. Before a workout leaves:
//   1. everything "last time", the records and the gold need is copied into
//      the small summary per exercise (records.js, foldIntoStats)
//   2. a one-line entry goes into the store "archive", so History can show a ✓
// Deleted workouts, old body weights and old measurements are removed completely; their ids are
// remembered, so importing an old file does not bring them back.

import * as db from './db.js';
import { foldIntoStats } from './records.js';
import { summarize, activeWorkoutId, listFinishedWorkouts } from './workout.js';
import { getExercise } from './library.js';
import { listBodyWeights, latestBodyWeightKg } from './bodyWeights.js';
import { listMeasurements } from './measurements.js';
import { nowIso } from './util.js';

/**
 * Everything for the History screen, newest first:
 *   { archived: false, workout }  still on the phone, with all details
 *   { archived: true, workout }   the one-line entry of an exported workout
 */
export async function listHistory() {
  const onPhone = (await listFinishedWorkouts()).map((workout) => ({ archived: false, workout }));
  const archived = (await db.getAll('archive')).map((line) => ({ archived: true, workout: line }));
  return onPhone.concat(archived).sort((a, b) => (a.workout.startedAt < b.workout.startedAt ? 1 : -1));
}

/** Ids that were removed from the phone on purpose. */
export async function removedIds() {
  return new Set(await db.getMeta('removedIds', []));
}

async function rememberRemoved(ids) {
  if (ids.length === 0) return;
  const known = await removedIds();
  ids.forEach((id) => known.add(id));
  await db.setMeta('removedIds', [...known]);
}

/** Ids of all workouts that already left the phone. */
export async function archivedIds() {
  return new Set((await db.getAll('archive')).map((line) => line.id));
}

/** Move finished workouts off the phone; test(workout) decides which ones. Returns how many moved. */
export async function archiveWorkouts(test) {
  const bodyWeightKg = await latestBodyWeightKg();
  const removed = [];
  let moved = 0;
  for (const workout of await db.getAll('workouts')) {
    if (!workout.finishedAt || workout.id === activeWorkoutId() || !test(workout)) continue;
    if (workout.deletedAt) {
      removed.push(workout.id);
    } else {
      await foldIntoStats(workout, bodyWeightKg);
      const summary = summarize(workout, bodyWeightKg);
      await db.put('archive', {
        id: workout.id,
        name: workout.name,
        startedAt: workout.startedAt,
        finishedAt: workout.finishedAt,
        archivedAt: nowIso(),
        durationMs: summary.durationMs,
        workSets: summary.workSets,
        volumeKg: summary.volumeKg,
        exerciseNames: workout.exercises.map((entry) => (getExercise(entry.exerciseId) || { name: 'Unbekannte Übung' }).name),
      });
      moved++;
    }
    await db.remove('workouts', workout.id);
  }
  await rememberRemoved(removed);
  return moved;
}

/**
 * Remove the body-weight entries for which test(entry) is true, except the
 * newest one: body-weight exercises need it to work out their volume.
 */
export async function pruneBodyWeights(test) {
  const newest = (await listBodyWeights())[0];
  const removed = [];
  for (const entry of await db.getAll('bodyWeights')) {
    if (test(entry) && (!newest || entry.id !== newest.id)) {
      await db.remove('bodyWeights', entry.id);
      removed.push(entry.id);
    }
  }
  await rememberRemoved(removed);
}

/** The same for measurements: all but the newest entry, to compare the next one with. */
export async function pruneMeasurements(test) {
  const newest = (await listMeasurements())[0];
  const removed = [];
  for (const entry of await db.getAll('measurements')) {
    if (test(entry) && (!newest || entry.id !== newest.id)) {
      await db.remove('measurements', entry.id);
      removed.push(entry.id);
    }
  }
  await rememberRemoved(removed);
}

/** After a confirmed export: everything up to exportedAt leaves the phone. Returns how many workouts moved. */
export async function clearExported(exportedAt) {
  const moved = await archiveWorkouts((workout) => workout.updatedAt <= exportedAt);
  await pruneBodyWeights((entry) => entry.updatedAt <= exportedAt);
  await pruneMeasurements((entry) => entry.updatedAt <= exportedAt);
  return moved;
}
