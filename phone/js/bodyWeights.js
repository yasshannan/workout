// bodyWeights.js — body-weight entries. One entry per day.
//
// Every entry is exported. After an export only the newest entry stays on the
// phone, because body-weight exercises need it to work out their volume.

import * as db from './db.js';
import { uuid, nowIso, isToday } from './util.js';

/** All entries that are not deleted, newest first. */
export async function listBodyWeights() {
  const all = await db.getAll('bodyWeights');
  return all.filter((entry) => !entry.deletedAt).sort((a, b) => (a.measuredAt < b.measuredAt ? 1 : -1));
}

/** The newest body weight in kg, or null. */
export async function latestBodyWeightKg() {
  const newest = (await listBodyWeights())[0];
  return newest ? newest.weightKg : null;
}

/** Today's entry, or null. */
export async function todaysBodyWeight() {
  const newest = (await listBodyWeights())[0];
  return newest && isToday(newest.measuredAt) ? newest : null;
}

/** Save today's body weight. If today already has an entry, it is corrected instead of adding a second one. */
export async function saveTodaysBodyWeight(weightKg) {
  const today = await todaysBodyWeight();
  const now = nowIso();
  const record = today
    ? { ...today, weightKg, updatedAt: now }
    : { id: uuid(), measuredAt: now, weightKg, updatedAt: now, deletedAt: null };
  await db.put('bodyWeights', record);
  return record;
}

/** Delete an entry. It is marked (deletedAt), so the next export tells the Windows app. */
export async function deleteBodyWeight(entry) {
  const now = nowIso();
  await db.put('bodyWeights', { ...entry, updatedAt: now, deletedAt: now });
}
