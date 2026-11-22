// schema.js — the shared file format (see shared/SCHEMA.md).
//
// Both apps read and write the same JSON. SCHEMA_VERSION is written into every
// export as "schemaVersion". If the format ever changes in a way older apps
// cannot read, raise it by one and add a step to MIGRATIONS that upgrades an
// old file to the new shape.

export const SCHEMA_VERSION = 1;
export const APP_ID = 'workout-tracker';

export const MOVEMENTS = ['push', 'pull', 'legs', 'core'];
export const EQUIPMENT = ['barbell', 'dumbbell', 'machine', 'cable', 'bodyweight', 'other'];
export const MOVEMENT_LABELS = { push: 'Drücken', pull: 'Ziehen', legs: 'Beine', core: 'Rumpf' };
export const EQUIPMENT_LABELS = { barbell: 'Langhantel', dumbbell: 'Kurzhantel', machine: 'Maschine', cable: 'Kabelzug', bodyweight: 'Eigengewicht', other: 'Sonstiges' };
export const LOAD_TYPES = [
  { id: 'external', label: 'Gewichte (Stange, Hantel, Maschine)' },
  { id: 'bodyweight', label: 'Eigengewicht (+ Zusatzgewicht)' },
  { id: 'assisted', label: 'Unterstützt (Maschine nimmt Gewicht ab)' },
];
export const UNITS = [
  { id: 'reps', label: 'Wiederholungen' },
  { id: 'seconds', label: 'Sekunden (Halten, Hängen, Tragen)' },
  { id: 'minutes', label: 'Minuten (Ausdauer, zählt nicht als Muskelsatz)' },
];
export const LOAD_MODES = [
  { id: 'total', label: 'Ein Gewicht (Stange, Maschine, eine Hantel)' },
  { id: 'perHand', label: 'Zwei Hanteln gleichzeitig (Gewicht pro Hantel)' },
  { id: 'perSide', label: 'Eine Seite nach der anderen (Wdh. pro Seite)' },
];

// Example for a future version 2:
//   1: (data) => { data.workouts.forEach((w) => { w.newField = null; }); data.schemaVersion = 2; return data; },
const MIGRATIONS = {};

/**
 * Check a parsed JSON file before importing it, and upgrade older versions.
 * Returns the (possibly upgraded) data, or throws an Error whose message can be
 * shown to the user as it is.
 */
export function checkImport(data) {
  if (!data || typeof data !== 'object' || data.app !== APP_ID) {
    throw new Error('Das ist keine Export-Datei dieser App.');
  }
  if (!Number.isInteger(data.schemaVersion) || data.schemaVersion < 1) {
    throw new Error('Die Datei hat keine gültige schemaVersion.');
  }
  if (data.schemaVersion > SCHEMA_VERSION) {
    throw new Error(`Die Datei hat Formatversion ${data.schemaVersion}, diese App kennt nur Version ${SCHEMA_VERSION}. Bitte zuerst die App aktualisieren.`);
  }
  while (data.schemaVersion < SCHEMA_VERSION) {
    const upgrade = MIGRATIONS[data.schemaVersion];
    if (!upgrade) throw new Error(`Eine Datei mit Formatversion ${data.schemaVersion} kann nicht umgewandelt werden.`);
    data = upgrade(data);
  }
  if (data.measurements === undefined) data.measurements = [];     // older files have none
  for (const list of ['exercises', 'templates', 'workouts', 'bodyWeights', 'measurements']) {
    if (!Array.isArray(data[list])) throw new Error(`Die Datei ist beschädigt: "${list}" fehlt.`);
    for (const record of data[list]) {
      if (!record || typeof record.id !== 'string' || typeof record.updatedAt !== 'string') {
        throw new Error(`Die Datei ist beschädigt: ein Eintrag in "${list}" hat keine id oder kein updatedAt.`);
      }
    }
  }
  return data;
}
