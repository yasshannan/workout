-- schema.sql : the permanent tables of the analyzer's database.
--
-- This file runs at every start of the app. "IF NOT EXISTS" means: create the
-- table the first time, leave it alone afterwards. Your imported data lives here.
--
-- Rules for all .sql files of this app (the loader in Database.cpp is simple):
--   * every statement ends with a semicolon
--   * no semicolon and no double dash inside a text in quotes

-- Small key/value store (for example the settings of the last imported file).
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);

-- Exactly one row: what is currently chosen in the user interface.
-- The filter bar writes into this row, and the views in derived.sql read it.
CREATE TABLE IF NOT EXISTS state (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    from_day     TEXT,                          -- filter: first day 'YYYY-MM-DD', NULL = no limit
    to_day       TEXT,                          -- filter: last day, NULL = no limit
    exercise_id  TEXT,                          -- filter: only this exercise, NULL = all
    muscle_id    TEXT,                          -- filter: only exercises training this muscle
    range_preset TEXT NOT NULL DEFAULT '8w',    -- which range button is active
    sel_exercise TEXT,                          -- exercise shown on the Strength page
    sel_muscle   TEXT,                          -- muscle shown on the Muscles page
    formula      TEXT NOT NULL DEFAULT 'epley', -- 'epley' or 'brzycki'
    level        TEXT NOT NULL DEFAULT 'intermediate', -- 'beginner', 'intermediate', 'advanced' or 'custom'
    theme        TEXT NOT NULL DEFAULT 'auto',  -- 'auto', 'light' or 'dark'
    animations   INTEGER NOT NULL DEFAULT 1,
    known_until  TEXT                           -- day of the newest export that was imported
);
INSERT OR IGNORE INTO state (id) VALUES (1);

-- The 25 muscle groups (the same as in shared/exercises.json), with the weekly
-- target range for hard sets. The targets differ per muscle: big muscles that
-- get little work from other exercises need more direct sets than muscles that
-- are trained anyway (front delts by every press, forearms by every pull).
-- A minimum of 0 means: no direct work is fine.
-- base_min / base_max are the values for an intermediate lifter; the level
-- buttons on the Settings page scale them (beginner fewer, advanced more).
CREATE TABLE IF NOT EXISTS muscles (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    region     TEXT NOT NULL,                   -- 'upper', 'lower' or 'core'
    sort_order INTEGER NOT NULL,
    target_min REAL NOT NULL DEFAULT 10,
    target_max REAL NOT NULL DEFAULT 20,
    base_min   REAL NOT NULL DEFAULT 10,
    base_max   REAL NOT NULL DEFAULT 20
);
INSERT OR IGNORE INTO muscles (id, name, region, sort_order, target_min, target_max, base_min, base_max) VALUES
    ('upper_chest',       'Obere Brust',             'upper',  1,  4, 10,  4, 10),
    ('chest',             'Brust (Mitte/unten)',     'upper',  2,  8, 18,  8, 18),
    ('front_delts',       'Vordere Schulter',        'upper',  3,  0,  8,  0,  8),
    ('side_delts',        'Seitliche Schulter',      'upper',  4,  8, 22,  8, 22),
    ('rear_delts',        'Hintere Schulter',        'upper',  5,  6, 18,  6, 18),
    ('rotator_cuff',      'Rotatorenmanschette',     'upper',  5.5, 0, 8,  0,  8),
    ('neck',              'Nacken',                  'upper',  6,  0, 10,  0, 10),
    ('traps',             'Trapez',                  'upper',  7,  0, 12,  0, 12),
    ('upper_back',        'Oberer Rücken',           'upper',  8,  8, 18,  8, 18),
    ('lats',              'Latissimus',              'upper',  9, 10, 20, 10, 20),
    ('biceps',            'Bizeps',                  'upper', 10,  8, 18,  8, 18),
    ('brachialis',        'Brachialis',              'upper', 11,  0, 10,  0, 10),
    ('triceps',           'Trizeps',                 'upper', 12,  8, 16,  8, 16),
    ('brachioradialis',   'Brachioradialis',         'upper', 13,  0,  8,  0,  8),
    ('forearm_flexors',   'Unterarm-Beuger',         'upper', 14,  0, 10,  0, 10),
    ('forearm_extensors', 'Unterarm-Strecker',       'upper', 15,  0,  8,  0,  8),
    ('abs',               'Bauch',                   'core',  16,  0, 16,  0, 16),
    ('obliques',          'Seitliche Bauchmuskeln',  'core',  17,  0, 12,  0, 12),
    ('lower_back',        'Unterer Rücken',          'core',  18,  0,  8,  0,  8),
    ('glutes',            'Gesäß',                   'lower', 19,  4, 14,  4, 14),
    ('abductors',         'Abduktoren',              'lower', 20,  0, 12,  0, 12),
    ('adductors',         'Adduktoren',              'lower', 21,  0, 12,  0, 12),
    ('quads',             'Quadrizeps',              'lower', 22, 10, 20, 10, 20),
    ('hamstrings',        'Beinbeuger',              'lower', 23,  8, 16,  8, 16),
    ('calves',            'Waden',                   'lower', 24,  8, 16,  8, 16),
    ('tibialis',          'Schienbeinmuskel',        'lower', 25,  0,  8,  0,  8);

-- The tables below mirror the export file (see shared/SCHEMA.md).
-- raw_json keeps the original record, so a full backup can be written back
-- out without losing anything.

CREATE TABLE IF NOT EXISTS exercises (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    movement            TEXT,
    equipment           TEXT,
    load_type           TEXT NOT NULL DEFAULT 'external',
    bodyweight_fraction REAL,
    compound            INTEGER NOT NULL DEFAULT 1,     -- multi-joint: only these get an estimated 1RM
    load_mode           TEXT NOT NULL DEFAULT 'total',  -- 'total', 'perHand' (two dumbbells) or 'perSide'
    unit                TEXT NOT NULL DEFAULT 'reps',   -- 'reps', 'seconds' (holds, carries) or 'minutes' (cardio)
    is_custom           INTEGER NOT NULL DEFAULT 0,
    updated_at          TEXT NOT NULL,
    deleted_at          TEXT,
    raw_json            TEXT NOT NULL
);

-- Which exercise trains which muscle. weight is 1 for primary, and the
-- exercise's share for secondary muscles (muscleShares, default 0.5).
CREATE TABLE IF NOT EXISTS exercise_muscles (
    exercise_id TEXT NOT NULL,
    muscle_id   TEXT NOT NULL,
    role        TEXT NOT NULL,                  -- 'primary' or 'secondary'
    weight      REAL NOT NULL,
    PRIMARY KEY (exercise_id, muscle_id)
);

CREATE TABLE IF NOT EXISTS templates (
    id         TEXT PRIMARY KEY,
    name       TEXT,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    raw_json   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workouts (
    id             TEXT PRIMARY KEY,
    name           TEXT,
    started_at     TEXT NOT NULL,               -- UTC, '2026-11-10T17:02:11.000Z'
    finished_at    TEXT,
    utc_offset_min INTEGER NOT NULL DEFAULT 0,
    notes          TEXT,
    updated_at     TEXT NOT NULL,
    deleted_at     TEXT,
    raw_json       TEXT NOT NULL
);

-- One exercise performed in one workout.
CREATE TABLE IF NOT EXISTS workout_exercises (
    id          TEXT PRIMARY KEY,
    workout_id  TEXT NOT NULL,
    exercise_id TEXT NOT NULL,
    sort_order  INTEGER NOT NULL,
    notes       TEXT,
    superset_group  TEXT,                       -- 'A', 'B' … or NULL
    target_reps_min INTEGER,                    -- the rep target from the template, if any
    target_reps_max INTEGER
);

CREATE TABLE IF NOT EXISTS sets (
    id              TEXT PRIMARY KEY,
    workout_id      TEXT NOT NULL,
    entry_id        TEXT NOT NULL,              -- workout_exercises.id
    sort_order      INTEGER NOT NULL,
    type            TEXT NOT NULL,              -- 'work', 'warmup', 'drop' or 'restpause'
    weight_kg       REAL NOT NULL,
    reps            INTEGER NOT NULL,           -- for one side at a time: the right side
    reps_left       INTEGER,                    -- the left side, when it differs
    partials        INTEGER,                    -- partial reps after the full ones (not counted)
    rpe             REAL,
    started_at      TEXT,
    completed_at    TEXT,
    target_rest_sec INTEGER
);

CREATE TABLE IF NOT EXISTS body_weights (
    id          TEXT PRIMARY KEY,
    measured_at TEXT NOT NULL,
    day         TEXT NOT NULL,                  -- local calendar day
    weight_kg   REAL NOT NULL,
    updated_at  TEXT NOT NULL,
    deleted_at  TEXT,
    raw_json    TEXT NOT NULL
);

-- Body measurements. Every field is optional.
CREATE TABLE IF NOT EXISTS measurements (
    id           TEXT PRIMARY KEY,
    measured_at  TEXT NOT NULL,
    day          TEXT NOT NULL,
    waist_cm     REAL,
    chest_cm     REAL,
    arm_cm       REAL,
    thigh_cm     REAL,
    calf_cm      REAL,
    body_fat_pct REAL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT,
    raw_json     TEXT NOT NULL
);

-- One line per imported file, shown on the Data page.
CREATE TABLE IF NOT EXISTS import_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    imported_at TEXT NOT NULL,
    file_name   TEXT NOT NULL,
    exported_at TEXT,
    export_type TEXT,
    added       INTEGER NOT NULL DEFAULT 0,
    updated     INTEGER NOT NULL DEFAULT 0,
    unchanged   INTEGER NOT NULL DEFAULT 0
);

-- Files of the auto-import folder that were already imported (path + time last changed),
-- so each file is imported only once. A file that changes is imported again.
CREATE TABLE IF NOT EXISTS imported_files (
    path     TEXT PRIMARY KEY,
    modified TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sets_workout ON sets (workout_id);
CREATE INDEX IF NOT EXISTS idx_entries_workout ON workout_exercises (workout_id);
