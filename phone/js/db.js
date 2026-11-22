// db.js — a thin wrapper around IndexedDB, the database built into the browser.
//
// IndexedDB's own API works with events, which is awkward to read. These few
// functions turn it into simple "await db.get(...)" calls.
//
// Stores (think: tables):
//   exercises      built-in library + your own exercises
//   templates      workout templates ("Push Day")
//   workouts       finished workouts that are not exported yet, and the running one
//   bodyWeights    body-weight entries (after an export only the newest one stays)
//   measurements   body measurements: waist, arm … (same rule as body weight)
//   archive        one short line per workout that was exported and removed
//   exerciseStats  per exercise: records and "last time", kept after workouts are removed
//   meta           small key/value things: settings, last export, the running workout …
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │  YOUR DATA SURVIVES EVERY UPDATE. Rules for every future change:          │
// │  1. Updating the app's files (sw.js) never touches this database.         │
// │  2. The database only ever GROWS: a new version may add stores, indexes   │
// │     and fields, never delete or empty them (no deleteObjectStore,         │
// │     deleteIndex, clear, deleteDatabase). Never rename DB_NAME.            │
// │  3. A change of structure = DB_VERSION + 1 and one more step in           │
// │     MIGRATIONS below. Old records must still be readable as they are.     │
// │  4. Before a migration runs, a copy of every record is put into           │
// │     meta "updateBackup" (see safety.js, which also copies before every    │
// │     update of the code). Settings → Info can bring missing data back.     │
// │  The test tests/test_data_safety.py checks all of this.                   │
// └──────────────────────────────────────────────────────────────────────────┘

const DB_NAME = 'workout-tracker';
const DB_VERSION = 3;

/**
 * One step per database version. Step n turns a version n-1 database into
 * version n. Each step only adds; the "has" checks make it safe on any database.
 */
const MIGRATIONS = {
  1: (database, has) => {
    if (!has('exercises')) database.createObjectStore('exercises', { keyPath: 'id' });
    if (!has('templates')) database.createObjectStore('templates', { keyPath: 'id' });
    if (!has('bodyWeights')) database.createObjectStore('bodyWeights', { keyPath: 'id' });
    if (!has('meta')) database.createObjectStore('meta', { keyPath: 'key' });
    if (!has('workouts')) {
      const store = database.createObjectStore('workouts', { keyPath: 'id' });
      store.createIndex('startedAt', 'startedAt');   // lets us read workouts newest-first
    }
  },
  2: (database, has) => {             // short lines for exported workouts, records per exercise
    if (!has('archive')) database.createObjectStore('archive', { keyPath: 'id' });
    if (!has('exerciseStats')) database.createObjectStore('exerciseStats', { keyPath: 'exerciseId' });
  },
  3: (database, has) => {             // body measurements
    if (!has('measurements')) database.createObjectStore('measurements', { keyPath: 'id' });
  },
};

/** Meta keys that are never copied: the copy itself, and the copy of the last export file. */
export const NOT_COPIED = new Set(['updateBackup', 'lastExportFile']);

/** Set when this start of the app upgraded the database (and made the copy). */
export let upgradedFrom = null;

let dbPromise = null;

/** Open the database, creating or upgrading it if needed. */
export function openDb() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    // Runs only when the database is new or DB_VERSION was raised.
    request.onupgradeneeded = (event) => {
      const database = request.result;
      const old = event.oldVersion;
      if (old > 0) {
        upgradedFrom = old;
        copyBeforeUpgrade(database, request.transaction, old);
      }
      const has = (name) => database.objectStoreNames.contains(name);
      for (let version = old + 1; version <= DB_VERSION; version++) MIGRATIONS[version](database, has);
    };

    request.onsuccess = () => {
      const database = request.result;
      database.onversionchange = () => database.close();    // a newer version wants in: make way
      resolve(database);
    };
    request.onerror = () => {
      const error = request.error;
      // An OLDER app on a NEWER database: refuse, but leave every record alone.
      if (error && error.name === 'VersionError') {
        reject(new Error('Deine Daten stammen von einer neueren Version der App. Öffne die App mit Internet, '
          + 'damit sie sich aktualisiert. Deine Daten bleiben erhalten.'));
      } else {
        reject(error);
      }
    };
  });
  return dbPromise;
}

/**
 * Inside the upgrade: read every record of every existing store and keep them
 * as meta "updateBackup", before any migration step changes something.
 */
function copyBeforeUpgrade(database, tx, oldVersion) {
  const names = [...database.objectStoreNames];
  if (!names.includes('meta')) return;
  const stores = {};
  let waiting = names.length;
  for (const name of names) {
    const request = tx.objectStore(name).getAll();
    request.onsuccess = () => {
      stores[name] = name === 'meta' ? request.result.filter((r) => !NOT_COPIED.has(r.key)) : request.result;
      if (--waiting > 0) return;
      const appVersion = (stores.meta.find((r) => r.key === 'appVersion') || {}).value || null;
      tx.objectStore('meta').put({
        key: 'updateBackup',
        value: {
          reason: 'database', fromVersion: appVersion, fromDbVersion: oldVersion, toDbVersion: DB_VERSION,
          createdAt: new Date().toISOString(), stores,
        },
      });
    };
  }
}

/** The names of all stores. */
export async function storeNames() {
  return [...(await openDb()).objectStoreNames];
}

/** The key field of a store ("id", "key" or "exerciseId"). */
export async function keyPathOf(storeName) {
  const database = await openDb();
  return database.transaction(storeName, 'readonly').objectStore(storeName).keyPath;
}

/** Run one operation in a transaction and resolve once it is safely written. */
async function run(storeName, mode, work) {
  const database = await openDb();
  return new Promise((resolve, reject) => {
    const tx = database.transaction(storeName, mode);
    const request = work(tx.objectStore(storeName));
    tx.oncomplete = () => resolve(request ? request.result : undefined);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

/** One record by id (undefined if there is none). */
export function get(storeName, id) {
  return run(storeName, 'readonly', (store) => store.get(id));
}

/** All records of a store, as an array. */
export function getAll(storeName) {
  return run(storeName, 'readonly', (store) => store.getAll());
}

/** Insert or replace one record. */
export function put(storeName, record) {
  return run(storeName, 'readwrite', (store) => store.put(record));
}

/** Insert or replace many records in one go. */
export function putMany(storeName, records) {
  if (records.length === 0) return Promise.resolve();
  return run(storeName, 'readwrite', (store) => { records.forEach((record) => store.put(record)); });
}

/** Remove one record. */
export function remove(storeName, id) {
  return run(storeName, 'readwrite', (store) => store.delete(id));
}

/** Read a small value from the meta store. */
export async function getMeta(key, fallback = null) {
  const record = await get('meta', key);
  return record ? record.value : fallback;
}

/** Write a small value to the meta store. */
export function setMeta(key, value) {
  return put('meta', { key, value });
}

/**
 * Walk through the workouts from newest to oldest and return the first one
 * for which test(workout) is true. Stops reading as soon as it found one.
 */
export async function findNewestWorkout(test) {
  const database = await openDb();
  return new Promise((resolve, reject) => {
    const index = database.transaction('workouts', 'readonly').objectStore('workouts').index('startedAt');
    const request = index.openCursor(null, 'prev');
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) return resolve(null);
      if (test(cursor.value)) return resolve(cursor.value);
      cursor.continue();
    };
    request.onerror = () => reject(request.error);
  });
}
