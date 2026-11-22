// measurements.js — body measurements (waist, chest, arm, thigh, calf, body fat).
//
// Works like the body weight: one entry per day, every field is optional, every
// entry is exported, and after an export only the newest entry stays on the
// phone. The Windows app keeps all of them and draws the graphs.

import * as db from './db.js';
import { uuid, nowIso, isToday } from './util.js';

/** The fields, in the order they are shown. */
export const MEASURES = [
  { id: 'waistCm', label: 'Taille', unit: 'cm' },
  { id: 'chestCm', label: 'Brust', unit: 'cm' },
  { id: 'armCm', label: 'Oberarm (angespannt)', unit: 'cm' },
  { id: 'thighCm', label: 'Oberschenkel', unit: 'cm' },
  { id: 'calfCm', label: 'Wade', unit: 'cm' },
  { id: 'bodyFatPct', label: 'Körperfett', unit: '%' },
];

/** All entries that are not deleted, newest first. */
export async function listMeasurements() {
  const all = await db.getAll('measurements');
  return all.filter((entry) => !entry.deletedAt).sort((a, b) => (a.measuredAt < b.measuredAt ? 1 : -1));
}

/**
 * Save today's measurements. values: { waistCm: 82.5, armCm: null, … }.
 * If today already has an entry, it is corrected instead of adding a second one.
 */
export async function saveTodaysMeasurements(values) {
  const newest = (await listMeasurements())[0];
  const today = newest && isToday(newest.measuredAt) ? newest : null;
  const now = nowIso();
  const record = today ? { ...today, updatedAt: now } : { id: uuid(), measuredAt: now, updatedAt: now, deletedAt: null };
  for (const { id } of MEASURES) record[id] = values[id] > 0 ? values[id] : null;
  await db.put('measurements', record);
  return record;
}

/** Delete an entry. It is marked (deletedAt), so the next export tells the Windows app. */
export async function deleteMeasurement(entry) {
  const now = nowIso();
  await db.put('measurements', { ...entry, updatedAt: now, deletedAt: now });
}
