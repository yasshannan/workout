// safety.js — updates never lose your data.
//
// 1. Before the first start of a new version (any update of the code), a copy
//    of every record is kept in meta "updateBackup". When the update also
//    changes the database, db.js makes that copy even earlier, inside the
//    upgrade, before anything is changed.
// 2. If something is missing after an update, Settings → Info brings back
//    everything that is in the copy but no longer on the phone. Nothing that
//    is there is overwritten.
// 3. Only one copy is kept (the newest). A confirmed export replaces it: the
//    export file then holds everything, and the workouts it contains are meant
//    to leave the phone.
// 4. The app asks iOS to protect its storage from being cleared.

import * as db from './db.js';
import { APP_VERSION } from './version.js';

/** Every record of every store, as stored (without the copy itself). */
export async function readAllStores() {
  const stores = {};
  for (const name of await db.storeNames()) {
    const records = await db.getAll(name);
    stores[name] = name === 'meta' ? records.filter((r) => !db.NOT_COPIED.has(r.key)) : records;
  }
  return stores;
}

/** Does the phone hold anything worth keeping (a fresh install holds nothing)? */
function hasData(stores) {
  return Object.entries(stores).some(([name, records]) => (name === 'meta' ? records.some((r) => r.key !== 'appVersion') : records.length > 0));
}

/**
 * Call once at start, right after the database is open and BEFORE anything
 * else reads or changes data. Makes the copy when this version runs for the first time.
 */
export async function protectBeforeUpdate() {
  const lastVersion = await db.getMeta('appVersion', null);
  if (lastVersion === APP_VERSION) return;
  if (db.upgradedFrom) {
    // db.js already copied everything before the database changed: just name the versions
    const backup = await db.getMeta('updateBackup', null);
    if (backup) await db.setMeta('updateBackup', { ...backup, fromVersion: lastVersion || backup.fromVersion, toVersion: APP_VERSION });
  } else {
    const stores = await readAllStores();
    if (hasData(stores)) {
      await db.setMeta('updateBackup', {
        reason: 'app', fromVersion: lastVersion, toVersion: APP_VERSION, createdAt: new Date().toISOString(), stores,
      });
    }
  }
  await db.setMeta('appVersion', APP_VERSION);
}

/** The copy from the last update: { fromVersion, toVersion, createdAt, stores } or null. */
export function lastUpdateBackup() {
  return db.getMeta('updateBackup', null);
}

/** After a confirmed export the copy is not needed any more (the file has everything). */
export function dropUpdateBackup() {
  return db.remove('meta', 'updateBackup');
}

/**
 * Put back every record of the copy that is no longer on the phone. Records
 * that are there stay exactly as they are. Returns how many came back.
 */
export async function restoreMissing() {
  const backup = await lastUpdateBackup();
  if (!backup) return 0;
  const names = new Set(await db.storeNames());
  let restored = 0;
  for (const [name, records] of Object.entries(backup.stores)) {
    if (!names.has(name)) continue;
    const keyPath = await db.keyPathOf(name);
    const present = new Set((await db.getAll(name)).map((record) => record[keyPath]));
    for (const record of records) {
      const key = record[keyPath];
      const emptyActive = name === 'meta' && key === 'active' && !(await db.getMeta('active', null));
      if (present.has(key) && !emptyActive) continue;
      if (name === 'meta' && (db.NOT_COPIED.has(key) || key === 'appVersion' || !record.value)) continue;
      await db.put(name, record);
      restored++;
    }
  }
  return restored;
}

/** Ask iOS to keep the app's storage even when the iPhone runs low on space. */
export function askForPersistentStorage() {
  if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(() => {});
}
