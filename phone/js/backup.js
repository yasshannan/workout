// backup.js — export to a JSON file, share it, and import a JSON file.
//
// This is the ONLY way data leaves the phone: you tap Export and choose where
// the file goes. Nothing is sent anywhere by itself.

import { dropUpdateBackup } from './safety.js';
import * as db from './db.js';
import { SCHEMA_VERSION, APP_ID, checkImport } from './schema.js';
import { settings, updateSettings, DEFAULT_SETTINGS } from './settings.js';
import { reloadFromDb } from './library.js';
import { archiveWorkouts, pruneBodyWeights, pruneMeasurements, clearExported, archivedIds, removedIds } from './archive.js';
import { h, nowIso } from './util.js';

/** When was the last export, and how much is waiting to be exported? */
export async function exportStatus() {
  const lastExportAt = await db.getMeta('lastExportAt', null);
  const isNew = (record) => !lastExportAt || record.updatedAt > lastExportAt;
  const workouts = (await db.getAll('workouts')).filter((w) => w.finishedAt && isNew(w));
  const bodyWeights = (await db.getAll('bodyWeights')).filter(isNew);
  const measurements = (await db.getAll('measurements')).filter(isNew);
  return {
    lastExportAt,
    pendingWorkouts: workouts.filter((w) => !w.deletedAt).length,
    pendingBodyWeights: bodyWeights.filter((b) => !b.deletedAt).length,
    pendingMeasurements: measurements.filter((m) => !m.deletedAt).length,
    pendingTotal: workouts.length + bodyWeights.length + measurements.length,
  };
}

/**
 * Build the export file: everything that changed since the last export (the
 * first time: everything). Exercises and templates are always included
 * completely: they are small, and the Windows app then always knows your own
 * exercises and muscle mapping. Returns { data, file, exportedAt }.
 */
export async function buildExport() {
  const exportedAt = nowIso();
  const since = await db.getMeta('lastExportAt', null);
  const isNew = (record) => !since || record.updatedAt > since;
  const s = settings();

  const data = {
    schemaVersion: SCHEMA_VERSION,
    app: APP_ID,
    exportedAt,
    exportType: since ? 'incremental' : 'full',
    changedSince: since,
    // unit, soundOn and effortScale are fixed in this app but still part of the file format
    settings: { unit: 'kg', defaultRestSec: s.defaultRestSec, soundOn: false, vibrateOn: s.vibrateOn,
                keepScreenOn: s.keepScreenOn, effortScale: 'rpe', theme: s.theme },
    exercises: await db.getAll('exercises'),
    templates: await db.getAll('templates'),
    // the running workout is not exported; it goes out once it is finished
    workouts: (await db.getAll('workouts')).filter((w) => w.finishedAt && isNew(w))
      .sort((a, b) => (a.startedAt < b.startedAt ? -1 : 1)),
    bodyWeights: (await db.getAll('bodyWeights')).filter(isNew)
      .sort((a, b) => (a.measuredAt < b.measuredAt ? -1 : 1)),
    measurements: (await db.getAll('measurements')).filter(isNew)
      .sort((a, b) => (a.measuredAt < b.measuredAt ? -1 : 1)),
  };

  // File name with the local date and time, e.g. workout-2026-11-16-2118.json
  const d = new Date();
  const two = (n) => String(n).padStart(2, '0');
  const name = `workout-${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}-${two(d.getHours())}${two(d.getMinutes())}.json`;
  const file = new File([JSON.stringify(data, null, 1)], name, { type: 'application/json' });
  return { data, file, exportedAt };
}

/**
 * Hand the file to the user. Must be called straight from a button tap.
 *  1. the share sheet (OneDrive, Files, Mail, AirDrop …) if the phone can share files
 *  2. otherwise a normal download (Android Chrome does not share .json files)
 * Returns 'shared', 'downloaded' or 'cancelled'.
 */
export async function deliverFile(file) {
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file] });
      return 'shared';
    } catch (error) {
      if (error.name === 'AbortError') return 'cancelled';     // the share sheet was closed
    }
  }
  const url = URL.createObjectURL(file);
  const link = h('a', { href: url, download: file.name });
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  return 'downloaded';
}

/**
 * You confirmed that the file arrived: remember the time, keep a copy of the
 * file (only the newest one, so it can be shared again if it gets lost later),
 * and move everything that was in it off the phone. Returns how many workouts moved.
 * Until this is called nothing is removed: a file that never arrived costs nothing.
 */
export async function markExported(exportedAt, file) {
  await db.setMeta('lastExportFile', { name: file.name, text: await file.text(), exportedAt });
  await db.setMeta('lastExportAt', exportedAt);
  const moved = await clearExported(exportedAt);
  await dropUpdateBackup();                 // the file now holds everything the copy held
  return moved;
}

/** The copy of the newest confirmed export as a File, or null. */
export async function lastExportFile() {
  const saved = await db.getMeta('lastExportFile', null);
  return saved ? { file: new File([saved.text], saved.name, { type: 'application/json' }), exportedAt: saved.exportedAt } : null;
}

/** Read and check a file chosen by the user. Throws an Error with a readable message. */
export async function readImportFile(file) {
  let data;
  try {
    data = JSON.parse(await file.text());
  } catch (error) {
    throw new Error('Diese Datei ist keine gültige JSON-Datei.');
  }
  return checkImport(data);
}

/**
 * Merge an imported file into the phone (for example after reinstalling the app).
 * The rule is the same as in the Windows app, and it prevents duplicates:
 *   unknown id               → add
 *   known id, file is newer  → replace
 *   known id, file is older  → keep what we have
 * Records that already left the phone count as known.
 * The imported workouts come from an export, so they are saved elsewhere already:
 * they are folded into the records and moved off the phone straight away.
 * Returns counts: { added, updated, unchanged }.
 */
export async function importData(data, { restoreSettings = false } = {}) {
  const result = { added: 0, updated: 0, unchanged: 0 };
  const gone = new Set([...await archivedIds(), ...await removedIds()]);
  for (const storeName of ['exercises', 'templates', 'workouts', 'bodyWeights', 'measurements']) {
    const existing = new Map((await db.getAll(storeName)).map((record) => [record.id, record]));
    const toWrite = [];
    for (const record of data[storeName] || []) {
      const mine = existing.get(record.id);
      if (!mine && gone.has(record.id)) result.unchanged++;
      else if (!mine) { toWrite.push(record); result.added++; }
      else if (record.updatedAt > mine.updatedAt) { toWrite.push(record); result.updated++; }
      else result.unchanged++;
    }
    await db.putMany(storeName, toWrite);
  }
  if (restoreSettings && data.settings) {
    const patch = {};
    for (const key of Object.keys(DEFAULT_SETTINGS)) {
      if (key in data.settings) patch[key] = data.settings[key];
    }
    await updateSettings(patch);
  }
  await reloadFromDb();

  const workoutsFromFile = new Set(data.workouts.map((workout) => workout.id));
  const weightsFromFile = new Set(data.bodyWeights.map((entry) => entry.id));
  const measuresFromFile = new Set((data.measurements || []).map((entry) => entry.id));
  const lastExportAt = await db.getMeta('lastExportAt', null);
  await archiveWorkouts((workout) => workoutsFromFile.has(workout.id));
  await pruneBodyWeights((entry) => weightsFromFile.has(entry.id) || (lastExportAt && entry.updatedAt <= lastExportAt));
  await pruneMeasurements((entry) => measuresFromFile.has(entry.id) || (lastExportAt && entry.updatedAt <= lastExportAt));
  return result;
}
