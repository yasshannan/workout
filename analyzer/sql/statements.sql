-- statements.sql : every SQL statement the C++ code runs by name.
--
-- A block starts with a line "-- name: something" and ends at the next such
-- line. In C++ you run a block with   m_db.runBlock("something", { ... })
-- and the values in { ... } are put where the :placeholders are.
--
-- Keeping the SQL here (and not inside C++ strings) has one big advantage:
-- tools/check_analyzer.py can run exactly these statements without Qt.
--
-- Rules: a :placeholder may appear only once per statement, and a text in
-- quotes must not contain a semicolon, a double dash or a colon followed by a letter.


-- =====================================================================
--  Import : one block per kind of record
-- =====================================================================

-- name: upsert_exercise
INSERT OR REPLACE INTO exercises
    (id, name, movement, equipment, load_type, bodyweight_fraction, compound, load_mode, unit, is_custom, updated_at, deleted_at, raw_json)
VALUES
    (:id, :name, :movement, :equipment, :load_type, :bodyweight_fraction, :compound, :load_mode, :unit, :is_custom, :updated_at, :deleted_at, :raw_json);

-- name: clear_exercise_muscles
DELETE FROM exercise_muscles WHERE exercise_id = :id;

-- name: insert_exercise_muscle
INSERT OR REPLACE INTO exercise_muscles (exercise_id, muscle_id, role, weight)
VALUES (:exercise_id, :muscle_id, :role, :weight);

-- name: upsert_template
INSERT OR REPLACE INTO templates (id, name, updated_at, deleted_at, raw_json)
VALUES (:id, :name, :updated_at, :deleted_at, :raw_json);

-- name: clear_workout
DELETE FROM sets WHERE workout_id = :id;
DELETE FROM workout_exercises WHERE workout_id = :id;

-- name: upsert_workout
INSERT OR REPLACE INTO workouts
    (id, name, started_at, finished_at, utc_offset_min, notes, updated_at, deleted_at, raw_json)
VALUES
    (:id, :name, :started_at, :finished_at, :utc_offset_min, :notes, :updated_at, :deleted_at, :raw_json);

-- name: insert_entry
INSERT OR REPLACE INTO workout_exercises (id, workout_id, exercise_id, sort_order, notes, superset_group, target_reps_min, target_reps_max)
VALUES (:id, :workout_id, :exercise_id, :sort_order, :notes, :superset_group, :target_reps_min, :target_reps_max);

-- name: insert_set
INSERT OR REPLACE INTO sets
    (id, workout_id, entry_id, sort_order, type, weight_kg, reps, reps_left, partials, rpe, started_at, completed_at, target_rest_sec)
VALUES
    (:id, :workout_id, :entry_id, :sort_order, :type, :weight_kg, :reps, :reps_left, :partials, :rpe, :started_at, :completed_at, :target_rest_sec);

-- The local calendar day is worked out from the UTC time by SQLite.
-- name: upsert_body_weight
INSERT OR REPLACE INTO body_weights (id, measured_at, day, weight_kg, updated_at, deleted_at, raw_json)
SELECT v.id, v.measured_at, date(v.measured_at, 'localtime'), v.weight_kg, v.updated_at, v.deleted_at, v.raw_json
FROM (SELECT :id AS id, :measured_at AS measured_at, :weight_kg AS weight_kg,
             :updated_at AS updated_at, :deleted_at AS deleted_at, :raw_json AS raw_json) v;

-- name: upsert_measurement
INSERT OR REPLACE INTO measurements
    (id, measured_at, day, waist_cm, chest_cm, arm_cm, thigh_cm, calf_cm, body_fat_pct, updated_at, deleted_at, raw_json)
SELECT v.id, v.measured_at, date(v.measured_at, 'localtime'), v.waist_cm, v.chest_cm, v.arm_cm, v.thigh_cm, v.calf_cm,
       v.body_fat_pct, v.updated_at, v.deleted_at, v.raw_json
FROM (SELECT :id AS id, :measured_at AS measured_at, :waist_cm AS waist_cm, :chest_cm AS chest_cm, :arm_cm AS arm_cm,
             :thigh_cm AS thigh_cm, :calf_cm AS calf_cm, :body_fat_pct AS body_fat_pct,
             :updated_at AS updated_at, :deleted_at AS deleted_at, :raw_json AS raw_json) v;

-- name: log_import
INSERT INTO import_log (imported_at, file_name, exported_at, export_type, added, updated, unchanged)
VALUES (:imported_at, :file_name, :exported_at, :export_type, :added, :updated, :unchanged);

-- Remember the newest export day. Weeks after it are unknown, not "zero training".
-- name: note_export
UPDATE state
SET known_until = (SELECT max(COALESCE(state.known_until, ''), v.day)
                   FROM (SELECT date(:exported_at, 'localtime') AS day) v);

-- name: remember_file
INSERT OR REPLACE INTO imported_files (path, modified) VALUES (:path, :modified);

-- name: save_meta
INSERT OR REPLACE INTO meta (key, value) VALUES (:key, :value);


-- =====================================================================
--  Settings that are not simple "set one column" updates
-- =====================================================================

-- The last N weeks, counted back from the newest export. :days is N * 7 - 1.
-- The result is moved back to a Monday, so the range always holds whole weeks.
-- name: range_last_days
UPDATE state
SET from_day = date(COALESCE(known_until, date('now', 'localtime')), '-' || :days || ' days', 'weekday 0', '-6 days'),
    to_day = NULL;

-- name: range_all
UPDATE state SET from_day = NULL, to_day = NULL;

-- name: set_muscle_target
UPDATE muscles SET target_min = :target_min, target_max = :target_max WHERE id = :id;
UPDATE state SET level = 'custom';

-- The level buttons: the targets of an intermediate lifter, scaled.
-- beginner 0.7 (fewer sets do the job), intermediate 1, advanced 1.25.
-- name: apply_level
UPDATE muscles SET target_min = round(base_min * :factor), target_max = round(base_max * :factor_again);
UPDATE state SET level = :level;


-- =====================================================================
--  refresh : rebuild the fact tables from the imported data.
--  Runs at start-up and after every import.
-- =====================================================================

-- name: refresh
DELETE FROM workout_facts;

INSERT INTO workout_facts (workout_id, name, started_at, day, week_start, duration_min, body_kg)
SELECT w.id, w.name, w.started_at,
       d.day,
       date(d.day, 'weekday 0', '-6 days'),                         -- the Monday of that week
       (julianday(w.finished_at) - julianday(w.started_at)) * 1440.0,
       (SELECT b.weight_kg FROM body_weights b
         WHERE b.deleted_at IS NULL
         ORDER BY abs(julianday(b.measured_at) - julianday(w.started_at))
         LIMIT 1)                                                   -- body weight closest in time
FROM workouts w
JOIN (SELECT id, date(started_at, printf('%+d minutes', utc_offset_min)) AS day FROM workouts) d ON d.id = w.id
WHERE w.deleted_at IS NULL AND w.finished_at IS NOT NULL;

DELETE FROM set_facts;

-- LAG(...) looks at the previous set of the same workout (in the order the sets
-- were logged). That is how rest times are calculated from the timestamps.
--   load_kg      what was really moved: body weight included where needed, both
--                dumbbells for "perHand" exercises
--   strength_kg  the weight that strength is measured with: like load_kg, but one
--                dumbbell for "perHand" exercises (as typed on the phone)
--   hard         how much the set counts as a hard set: 1 normal, ½ for a part of
--                a drop or rest-pause set, 0 for a warm-up and for cardio (minutes)
--   timed        1 = the reps are seconds or minutes: no volume, no 1RM
--   eff_reps     reps for records: the weaker side for one side at a time
--   total_reps   reps for the volume: both sides for one side at a time
INSERT INTO set_facts
    (set_id, workout_id, entry_id, exercise_id, day, week_start, seq, is_work, hard, timed, weight_kg, reps, eff_reps, total_reps,
     load_kg, strength_kg, body_kg, has_e1rm, set_sec, rest_sec, first_of_exercise, prev_is_work, target_rest_sec, prev_target_rest_sec)
SELECT s.id, s.workout_id, s.entry_id, e.exercise_id, wf.day, wf.week_start,
       ROW_NUMBER() OVER win,
       (s.type = 'work'),
       CASE WHEN COALESCE(x.unit, 'reps') = 'minutes' THEN 0
            ELSE CASE s.type WHEN 'work' THEN 1.0 WHEN 'drop' THEN 0.5 WHEN 'restpause' THEN 0.5 ELSE 0 END END,
       (COALESCE(x.unit, 'reps') <> 'reps'),
       s.weight_kg, s.reps,
       min(s.reps, COALESCE(s.reps_left, s.reps)),
       CASE WHEN x.load_mode = 'perSide' THEN s.reps + COALESCE(s.reps_left, s.reps) ELSE s.reps END,
       CASE x.load_type
           WHEN 'bodyweight' THEN COALESCE(wf.body_kg, 0) * COALESCE(x.bodyweight_fraction, 1) + s.weight_kg
           WHEN 'assisted'   THEN max(0, COALESCE(wf.body_kg, s.weight_kg) - s.weight_kg)
           ELSE s.weight_kg * CASE WHEN x.load_mode = 'perHand' THEN 2 ELSE 1 END
       END,
       CASE x.load_type
           WHEN 'bodyweight' THEN COALESCE(wf.body_kg, 0) * COALESCE(x.bodyweight_fraction, 1) + s.weight_kg
           WHEN 'assisted'   THEN max(0, COALESCE(wf.body_kg, s.weight_kg) - s.weight_kg)
           ELSE s.weight_kg
       END,
       wf.body_kg,
       (COALESCE(x.compound, 1) = 1 AND COALESCE(x.load_type, 'external') = 'external' AND COALESCE(x.unit, 'reps') = 'reps'),
       (julianday(s.completed_at) - julianday(s.started_at)) * 86400.0,
       (julianday(COALESCE(s.started_at, s.completed_at)) - julianday(LAG(s.completed_at) OVER win)) * 86400.0,
       (LAG(s.entry_id) OVER win IS NOT s.entry_id),
       LAG(s.type = 'work') OVER win,
       s.target_rest_sec,
       LAG(s.target_rest_sec) OVER win
FROM sets s
JOIN workout_exercises e ON e.id = s.entry_id
JOIN workout_facts wf ON wf.workout_id = s.workout_id
LEFT JOIN exercises x ON x.id = e.exercise_id
WINDOW win AS (PARTITION BY s.workout_id ORDER BY s.completed_at, e.sort_order, s.sort_order);

-- Volume and estimated one-rep max. Warm-up sets count for neither.
--   Epley:   weight * (1 + reps / 30)
--   Brzycki: weight * 36 / (37 - reps)
-- The estimate is only made where it means something: normal working sets of
-- multi-joint exercises with weights, with at most 8 reps (above that both
-- formulas get inaccurate). Isolation exercises are judged by weight and reps.
UPDATE set_facts
SET volume_kg = (hard > 0) * (timed = 0) * load_kg * total_reps,
    e1rm_epley = CASE WHEN is_work = 1 AND has_e1rm = 1 AND eff_reps <= 8 AND strength_kg > 0
                      THEN CASE WHEN eff_reps = 1 THEN strength_kg ELSE strength_kg * (1 + eff_reps / 30.0) END END,
    e1rm_brzycki = CASE WHEN is_work = 1 AND has_e1rm = 1 AND eff_reps <= 8 AND strength_kg > 0
                        THEN strength_kg * 36.0 / (37 - eff_reps) END;

-- The volume record works "at the same number of sets": the first 1, 2, 3 …
-- normal working sets of a workout, added up. A sloppy extra set never makes a
-- record: a workout with 4 sets is compared with the first 4 sets of earlier
-- workouts (or, if there never were 4, with the most sets ever done).
DELETE FROM exercise_set_cum;

INSERT INTO exercise_set_cum (exercise_id, workout_id, started_at, k, cum_kg)
SELECT exercise_id, workout_id, started_at, k, cum_kg
FROM (SELECT f.exercise_id, f.workout_id, wf.started_at,
             ROW_NUMBER() OVER w AS k,
             SUM(f.volume_kg) OVER w AS cum_kg
      FROM set_facts f
      JOIN workout_facts wf ON wf.workout_id = f.workout_id
      WHERE f.is_work = 1
      WINDOW w AS (PARTITION BY f.exercise_id, f.workout_id ORDER BY f.seq))
WHERE k <= 12;

DELETE FROM exercise_session_facts;

INSERT INTO exercise_session_facts
    (exercise_id, workout_id, day, week_start, started_at, name, sets, work_sets, reps, volume_kg, top_load_kg, top_weight_kg, session_no)
SELECT p.exercise_id, p.workout_id, p.day, p.week_start, p.started_at, p.name, p.sets, p.work_sets, p.reps, p.volume_kg,
       p.top_load_kg, p.top_weight_kg,
       ROW_NUMBER() OVER (PARTITION BY p.exercise_id ORDER BY p.started_at)
FROM (SELECT f.exercise_id, f.workout_id, wf.day, wf.week_start, wf.started_at, wf.name,
             SUM(f.hard)                                         AS sets,
             SUM(f.is_work)                                      AS work_sets,
             SUM(CASE WHEN f.hard > 0 THEN f.total_reps END)      AS reps,
             SUM(f.volume_kg)                                    AS volume_kg,
             MAX(CASE WHEN f.is_work = 1 THEN f.load_kg END)      AS top_load_kg,
             MAX(CASE WHEN f.is_work = 1 THEN f.weight_kg END)    AS top_weight_kg
      FROM set_facts f
      JOIN workout_facts wf ON wf.workout_id = f.workout_id
      GROUP BY f.exercise_id, f.workout_id) p;

UPDATE exercise_session_facts
SET compare_sets = min(work_sets, 12, (SELECT MAX(e.work_sets) FROM exercise_session_facts e
                                       WHERE e.exercise_id = exercise_session_facts.exercise_id
                                         AND e.started_at < exercise_session_facts.started_at));

UPDATE exercise_session_facts
SET compare_kg = (SELECT c.cum_kg FROM exercise_set_cum c
                   WHERE c.exercise_id = exercise_session_facts.exercise_id
                     AND c.workout_id = exercise_session_facts.workout_id
                     AND c.k = exercise_session_facts.compare_sets),
    before_best = (SELECT MAX(c.cum_kg) FROM exercise_set_cum c
                    WHERE c.exercise_id = exercise_session_facts.exercise_id
                      AND c.k = exercise_session_facts.compare_sets
                      AND c.started_at < exercise_session_facts.started_at)
WHERE compare_sets > 0;

UPDATE exercise_session_facts
SET is_volume_pr = COALESCE(before_best > 0 AND compare_kg > before_best + 0.001, 0);

-- =====================================================================
--  apply_filter : copy the part of the facts that passes the filter bar
--  into the cur_ tables. Runs whenever a filter changes. Every chart reads
--  the cur_ tables, so every chart respects the filters automatically.
-- =====================================================================

-- name: apply_filter
DELETE FROM cur_sets;

INSERT INTO cur_sets
    (set_id, workout_id, entry_id, exercise_id, day, week_start, is_work, hard, weight_kg, reps, eff_reps,
     load_kg, strength_kg, body_kg, volume_kg, set_sec, rest_sec, first_of_exercise, prev_is_work, target_rest_sec, prev_target_rest_sec, e1rm)
SELECT f.set_id, f.workout_id, f.entry_id, f.exercise_id, f.day, f.week_start, f.is_work, f.hard, f.weight_kg, f.reps, f.eff_reps,
       f.load_kg, f.strength_kg, f.body_kg, f.volume_kg, f.set_sec, f.rest_sec, f.first_of_exercise, f.prev_is_work, f.target_rest_sec, f.prev_target_rest_sec,
       CASE s.formula WHEN 'brzycki' THEN f.e1rm_brzycki ELSE f.e1rm_epley END
FROM set_facts f CROSS JOIN state s
WHERE (s.from_day IS NULL OR f.day >= s.from_day)
  AND (s.to_day IS NULL OR f.day <= s.to_day)
  AND (s.exercise_id IS NULL OR f.exercise_id = s.exercise_id)
  AND (s.muscle_id IS NULL OR EXISTS (SELECT 1 FROM exercise_muscles em
                                      WHERE em.exercise_id = f.exercise_id AND em.muscle_id = s.muscle_id));

DELETE FROM cur_workouts;

-- One row per workout that still has sets after filtering. Rest times that
-- are clearly not rest (under 5 seconds, over 15 minutes) are left out.
INSERT INTO cur_workouts
    (workout_id, name, started_at, day, week_start, duration_min, work_sets, volume_kg, avg_rest_sec, avg_pause_sec)
SELECT wf.workout_id, wf.name, wf.started_at, wf.day, wf.week_start, wf.duration_min,
       SUM(c.hard),
       SUM(c.volume_kg),
       AVG(CASE WHEN c.first_of_exercise = 0 AND c.is_work = 1 AND c.prev_is_work = 1
                 AND c.rest_sec BETWEEN 5 AND 900 THEN c.rest_sec END),
       AVG(CASE WHEN c.first_of_exercise = 1 AND c.rest_sec BETWEEN 5 AND 1800 THEN c.rest_sec END)
FROM cur_sets c
JOIN workout_facts wf ON wf.workout_id = c.workout_id
GROUP BY wf.workout_id;

DELETE FROM cur_span;

-- end_day: the last day we have knowledge about (never later than the newest export).
-- first_week: where the charts start. If the range starts after your first
-- workout ever, empty weeks at the start of the range are real and are kept.
INSERT INTO cur_span (end_day, first_week)
SELECT CASE WHEN s.to_day IS NOT NULL AND (s.known_until IS NULL OR s.to_day < s.known_until) THEN s.to_day
            ELSE COALESCE(s.known_until, (SELECT MAX(day) FROM workout_facts)) END,
       CASE WHEN s.from_day IS NOT NULL
                 AND date(s.from_day, 'weekday 0', '-6 days') >= (SELECT MIN(week_start) FROM workout_facts)
                 AND EXISTS (SELECT 1 FROM cur_workouts)
            THEN date(s.from_day, 'weekday 0', '-6 days')
            ELSE (SELECT MIN(week_start) FROM cur_workouts) END
FROM state s;

-- A week is complete when its Sunday is not after end_day.
UPDATE cur_span
SET last_week = date(end_day, 'weekday 0', '-6 days'),
    last_complete_week = CASE WHEN strftime('%w', end_day) = '0' THEN date(end_day, '-6 days')
                              ELSE date(end_day, 'weekday 0', '-13 days') END;

DELETE FROM cur_weeks;

-- Every week from first_week to last_week, also weeks without any workout.
WITH RECURSIVE w(week_start) AS (
    SELECT first_week FROM cur_span WHERE first_week IS NOT NULL AND first_week <= last_week
    UNION ALL
    SELECT date(w.week_start, '+7 days') FROM w JOIN cur_span sp ON date(w.week_start, '+7 days') <= sp.last_week
    LIMIT 1000
)
INSERT INTO cur_weeks (week_start, is_complete, counted)
SELECT w.week_start, (w.week_start <= sp.last_complete_week), 0
FROM w CROSS JOIN cur_span sp;

-- "counted" weeks are the ones weekly averages are calculated from: complete
-- weeks only, so a half-finished week does not make you look under-trained.
-- If there is no complete week yet, the running week is used.
UPDATE cur_weeks
SET counted = CASE WHEN (SELECT COALESCE(SUM(is_complete), 0) FROM cur_weeks) > 0 THEN is_complete ELSE 1 END;
