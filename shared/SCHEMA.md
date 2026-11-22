# The export file format (schema version 1)

The phone app exports one JSON file. The Windows app imports it, and can write a full
backup in the same format that the phone imports. Both apps follow this document. The
formal, machine-checkable version is `schema-v1.json`.

## The file at a glance

```json
{
  "schemaVersion": 1,
  "app": "workout-tracker",
  "exportedAt": "2026-11-16T21:18:00.000Z",
  "exportType": "incremental",
  "changedSince": "2026-11-09T19:02:00.000Z",
  "settings":    { ... },
  "exercises":   [ ... ],
  "templates":   [ ... ],
  "workouts":    [ ... ],
  "bodyWeights": [ ... ],
  "measurements": [ ... ]
}
```

| Field | Meaning |
|---|---|
| `schemaVersion` | Version of this format. Currently `1`. |
| `app` | Always `"workout-tracker"`. Lets the apps reject unrelated JSON files. |
| `exportedAt` | When the file was created. |
| `exportType` | `"full"` for the first export (and Windows backups), `"incremental"` afterwards. |
| `changedSince` | For incremental files: the time of the previous export. Otherwise `null`. |

An incremental file holds the workouts, body weights and measurements that changed since `changedSince`.
`exercises` and `templates` are **always complete**: they are small, and the Windows app then
always knows your own exercises and muscle mapping. A running workout is never exported; it
goes out once it is finished.

After an export **that you confirmed** ("Ja, angekommen") the phone removes the exported
workouts and all but the newest body weight and measurement (see "On the phone after an export").

## Five rules that apply everywhere

1. **Weights are kilograms.** Both apps work in kg only.
2. **Times are UTC timestamps** like `2026-11-10T17:02:11.000Z`. Durations are never stored;
   they are calculated from timestamps (see "Calculated values").
3. **Every record has a unique `id`.** Workouts, sets, templates and body weights use random
   UUIDs. Built-in exercises use fixed names such as `barbell-bench-press`.
4. **Every top-level record has `updatedAt`.** It changes whenever the record is edited.
5. **Deleting is a change too.** A deleted record can be sent with `deletedAt` set, so the
   other app learns that it is gone.

## How merging works (no duplicates)

Both apps use the same rule when they import a file. For each record in the file:

| Situation | Action |
|---|---|
| The `id` is unknown | add the record |
| The `id` is known and the file's `updatedAt` is newer | replace the stored record |
| The `id` is known and the file's `updatedAt` is the same or older | keep the stored record |

A workout is replaced as a whole, with its exercises and sets. Importing the same file twice
changes nothing.

## `settings`

| Field | Values | Meaning |
|---|---|---|
| `unit` | `"kg"` | Always kg. |
| `defaultRestSec` | number | Default rest timer target in seconds. |
| `barKg` | number | Optional. Weight of the empty bar for the plate calculator (default 20). Phone only. |
| `soundOn` | `false` | The phone app makes no sound. Kept because older files have it. |
| `vibrateOn` | true/false | Vibrate when the rest is over. |
| `keepScreenOn` | true/false | Keep the screen on during a workout. |
| `effortScale` | `"rpe"` | Kept because older files have it. The app no longer asks for effort. |
| `theme` | `"auto"`, `"light"`, `"dark"` | |

## `exercises`

```json
{
  "id": "barbell-bench-press",
  "name": "Barbell Bench Press",
  "primaryMuscles": ["chest"],
  "secondaryMuscles": ["triceps", "front_delts"],
  "movement": "push",
  "equipment": "barbell",
  "loadType": "external",
  "compound": true,
  "load": "total",
  "weightStep": 2.5,
  "isCustom": false,
  "updatedAt": "2026-11-17T00:00:00.000Z",
  "deletedAt": null
}
```

| Field | Meaning |
|---|---|
| `primaryMuscles` | One set of this exercise counts as **1 set** for each of these muscles. |
| `secondaryMuscles` | One set counts as **½ set** for each of these muscles, unless `muscleShares` says otherwise. |
| `muscleShares` | Optional. `{ "triceps": 0.6 }`: how much a set counts for a secondary muscle, 0.1 to 0.9 in steps of 0.1. |
| `movement` | `push`, `pull`, `legs` or `core`. Used for the push/pull balance. |
| `equipment` | `barbell`, `dumbbell`, `machine`, `cable`, `bodyweight`, `other`. |
| `loadType` | How `weightKg` of a set is to be read, see below. |
| `bodyweightFraction` | Only with `loadType: "bodyweight"`. Share of body weight that counts as load (an estimate). Missing = 1. |
| `compound` | Optional, default `true`. Multi-joint exercise. Only these (with `loadType: "external"`) get an estimated 1RM. |
| `load` | Optional, default `"total"`. `"perHand"`: two equal weights at once, `weightKg` is one of them (volume × 2). `"perSide"`: one arm or leg after the other, reps per side. |
| `unit` | Optional, default `"reps"`. What a set's `reps` counts: `"seconds"` for holds, hangs and carries (a hard set, but no volume in kg and no 1RM), `"minutes"` for cardio (no hard set, no volume). |
| `weightStep` | Optional. How much − / + change the weight on the phone (default by equipment: barbell 2.5, dumbbell 2, machine 5). |
| `setup` | Optional. Your note for the machine settings, e.g. "Sitz 4, Studio A". |
| `isCustom` | `true` for exercises you created yourself. |
| `editedByUser` | Optional. `true` once you changed the exercise in one of the apps. Library updates then leave it alone. |

### The 26 muscle groups

| id | Name | Region | id | Name | Region |
|---|---|---|---|---|---|
| `upper_chest` | Upper chest (clavicular) | upper | `forearm_flexors` | Forearm flexors (grip, bending the wrist) | upper |
| `chest` | Chest (mid/lower) | upper | `forearm_extensors` | Forearm extensors (straightening the wrist) | upper |
| `front_delts` | Front delts | upper | `abs` | Abs | core |
| `side_delts` | Side delts | upper | `obliques` | Obliques | core |
| `rear_delts` | Rear delts | upper | `lower_back` | Lower back | core |
| `neck` | Neck | upper | `glutes` | Glutes | lower |
| `traps` | Traps | upper | `abductors` | Abductors (outer hip) | lower |
| `upper_back` | Upper back (rhomboids, teres major) | upper | `adductors` | Adductors (inner thigh) | lower |
| `lats` | Lats | upper | `quads` | Quads | lower |
| `biceps` | Biceps | upper | `hamstrings` | Hamstrings | lower |
| `brachialis` | Brachialis | upper | `calves` | Calves | lower |
| `triceps` | Triceps | upper | `tibialis` | Tibialis (shin) | lower |
| `brachioradialis` | Brachioradialis (thumb side of the forearm) | upper | `rotator_cuff` | Rotator cuff (internal and external rotation) | upper |

The list, the display names and the regions are in `exercises.json`. Its exercise list can be
empty; a built-in exercise that is removed from it is marked deleted on the phone (workouts that
used it keep their data). Files of older versions
may use `forearms` (one group for the whole forearm); both apps read it as `forearm_flexors`.

### `loadType`: what a set's `weightKg` means

| `loadType` | `weightKg` is … | Load used for volume and estimated 1RM |
|---|---|---|
| `external` | the weight lifted | `weightKg` (× 2 with `load: "perHand"`) |
| `bodyweight` | **extra** weight (0 for plain body weight) | `bodyWeight × bodyweightFraction + weightKg` |
| `assisted` | the **assistance** of the machine | `bodyWeight − weightKg` |

`bodyWeight` is the body-weight entry closest in time to the workout. With `load: "perSide"`
the reps of both sides are added up for the volume.

## `templates`

```json
{
  "id": "0b0c…", "name": "Push Day",
  "items": [ { "exerciseId": "barbell-bench-press", "targetSets": 3, "restSec": 180, "repsMin": 8, "repsMax": 12, "supersetGroup": null } ],
  "updatedAt": "…", "deletedAt": null
}
```

`repsMin` / `repsMax` are the rep target: equal for a fixed number (`10` / `10`), different for
a range (`8` / `12`). Older files may not have them. Items next to each other with the same
`supersetGroup` letter (`"A"`) are done as a superset.

## `workouts`

```json
{
  "id": "7c1e…",
  "name": "Push Day",
  "templateId": "0b0c…",
  "startedAt": "2026-11-10T17:02:11.000Z",
  "finishedAt": "2026-11-10T18:09:40.000Z",
  "utcOffsetMin": 60,
  "notes": "",
  "updatedAt": "2026-11-10T18:09:40.000Z",
  "deletedAt": null,
  "exercises": [
    {
      "id": "a41f…", "exerciseId": "barbell-bench-press", "order": 0, "notes": "",
      "targetRepsMin": 8, "targetRepsMax": 12, "supersetGroup": null,
      "sets": [
        {
          "id": "e9d2…", "order": 0, "type": "work",
          "weightKg": 60, "reps": 8, "rpe": null,
          "startedAt": "2026-11-10T17:05:02.000Z",
          "completedAt": "2026-11-10T17:05:43.000Z",
          "targetRestSec": 180
        }
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `utcOffsetMin` | Local time minus UTC in minutes when the workout started (Vienna: 60 in winter, 120 in summer). Puts the workout on the right calendar day and week. |
| `order` | Position in the list, starting at 0. |
| `targetRepsMin` / `targetRepsMax` | Optional: the rep target from the template the workout was started from. |
| `supersetGroup` | Optional: exercises with the same letter were done as a superset. |
| set `type` | `"work"` (normal), `"warmup"`, `"drop"` or `"restpause"` (one part of a drop or rest-pause set, logged one by one). Warm-ups count for nothing; drop and rest-pause parts count ½ hard set and full volume, but never make a record. |
| set `reps` | With `load: "perSide"`: the right side. |
| set `repsLeft` | Optional, only with `load: "perSide"`: the left side, when it differs. |
| set `partials` | Optional: partial reps after the full ones. Not counted in volume. |
| set `rpe` | Always `null` from the current app (it does not ask for effort). Older files may have numbers. |
| set `startedAt` | When "Start set" was tapped. `null` if it was skipped. |
| set `completedAt` | When the set was logged. `null` for sets added by hand afterwards. |
| set `targetRestSec` | The rest target that was running after this set. |

## `bodyWeights`

```json
{ "id": "5f0a…", "measuredAt": "2026-11-10T06:10:00.000Z", "weightKg": 78.4, "updatedAt": "…", "deletedAt": null }
```

The phone keeps one entry per day.

## `measurements`

```json
{ "id": "…", "measuredAt": "…", "waistCm": 82.5, "chestCm": null, "armCm": 38, "thighCm": null,
  "calfCm": null, "bodyFatPct": 15, "updatedAt": "…", "deletedAt": null }
```

Every value is optional (`null`). One entry per day. Older files have no `measurements`.

## Calculated values

These are not stored. Both apps calculate them the same way, with all sets of a workout in
the order of their `completedAt`:

| Value | Calculation |
|---|---|
| Workout duration | `finishedAt − startedAt` |
| Set duration | `completedAt − startedAt` (unknown if `startedAt` is `null`) |
| Rest before a set | this set's `startedAt` − previous set's `completedAt`. If `startedAt` is `null`: this set's `completedAt` − previous set's `completedAt` (rest and set together). |
| Pause between exercises | the "rest before" of an exercise's first set |
| Exercise duration | last set's `completedAt` − first set's `startedAt` (or its `completedAt`) |
| Hard sets per muscle | sets × 1 for primary muscles, × share (default ½) for secondary muscles; drop / rest-pause parts count ½ of that |
| Volume | load × reps, summed over all sets except warm-ups (load as in the `loadType` table) |
| Estimated 1RM | Epley `w × (1 + reps/30)` (or Brzycki), only for `compound` exercises with weights and sets of at most 8 reps |
| Volume record ("gold") | the first *n* normal working sets of a workout moved more kg than the first *n* sets of every earlier workout, *n* = today's number of sets (or the most sets ever done before, if that is fewer) |

## On the phone after an export

After the file was handed over **and you confirmed that it arrived**, the phone:

1. keeps a copy of this one file (replaced at the next export), so it can be shared again,
2. copies what "last time", the records and the gold need into a small summary per exercise,
3. replaces each exported workout by a one-line entry (History shows it with a ✓),
4. removes exported body weights and measurements except the newest one, and deleted records,
5. remembers the ids it removed, so importing an old file does not bring them back.

None of this is part of the file format; it only explains why the phone holds less than the
Windows app.

## Changing the format later

1. Decide the change and write it down here.
2. If older apps could not read the new files, raise `SCHEMA_VERSION` to 2 in `phone/js/schema.js`
   and `kSchemaVersion` in `analyzer/src/Importer.cpp`.
3. Add a migration step that turns a version-1 file into version 2, for example in `schema.js`:

   ```js
   const MIGRATIONS = {
     1: (data) => {
       data.workouts.forEach((w) => { w.location = null; });   // the new field
       data.schemaVersion = 2;
       return data;
     },
   };
   ```
4. Copy `schema-v1.json` to `schema-v2.json` and adjust it.

An app refuses files with a **newer** version than it knows and says so, instead of guessing.
New optional fields (like the rep targets) need no new version: older apps simply ignore them.
