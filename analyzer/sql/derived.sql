-- derived.sql : everything that is CALCULATED from the imported data.
--
-- All of it is dropped and created again at every start of the app, so this
-- file can change freely between versions without touching your data.
--
--   *_facts tables  one row per workout / per set, with everything worked out
--                   (local day, week, load, volume, estimated 1RM, rest times).
--                   Filled by the "refresh" block in statements.sql.
--   cur_* tables    the part of the facts that passes the current filters.
--                   Filled by the "apply_filter" block in statements.sql.
--   v_* views       what the screens ask for. backend.rows("v_weekly") in QML
--                   simply runs  SELECT * FROM v_weekly.
--
-- Naming: columns are snake_case here and are read under the same names in QML.
-- Texts for the screen are German; numbers in texts use a decimal comma
-- (replace(printf(...), '.', ',')).


-- =====================================================================
--  Fact tables
-- =====================================================================

DROP TABLE IF EXISTS workout_facts;
CREATE TABLE workout_facts (
    workout_id   TEXT PRIMARY KEY,
    name         TEXT,
    started_at   TEXT,
    day          TEXT,          -- local calendar day, 'YYYY-MM-DD'
    week_start   TEXT,          -- the Monday of that week
    duration_min REAL,
    body_kg      REAL           -- body weight closest in time, NULL if never entered
);

DROP TABLE IF EXISTS set_facts;
CREATE TABLE set_facts (
    set_id               TEXT PRIMARY KEY,
    workout_id           TEXT,
    entry_id             TEXT,
    exercise_id          TEXT,
    day                  TEXT,
    week_start           TEXT,
    seq                  INTEGER,   -- position in the workout, in the order the sets were logged
    is_work              INTEGER,   -- 1 = normal working set (only these make records)
    hard                 REAL,      -- counts as hard set: 1 normal, 0.5 drop / rest-pause part, 0 warm-up and cardio
    timed                INTEGER,   -- 1 = reps are seconds or minutes (no volume, no 1RM)
    weight_kg            REAL,      -- as typed on the phone
    reps                 INTEGER,
    eff_reps             INTEGER,   -- for records: the weaker side when sides are done one at a time
    total_reps           INTEGER,   -- for volume: both sides
    load_kg              REAL,      -- what was really moved (body weight, both dumbbells included)
    strength_kg          REAL,      -- the weight strength is measured with (one dumbbell)
    body_kg              REAL,
    has_e1rm             INTEGER,   -- 1 = multi-joint exercise with weights: gets an estimated 1RM
    volume_kg            REAL,      -- load * reps, 0 for warm-ups
    e1rm_epley           REAL,
    e1rm_brzycki         REAL,
    set_sec              REAL,      -- how long the set took (NULL if "Start set" was skipped)
    rest_sec             REAL,      -- pause before this set
    first_of_exercise    INTEGER,   -- 1 = the pause before it was a change of exercise
    prev_is_work         INTEGER,
    target_rest_sec      INTEGER,
    prev_target_rest_sec INTEGER    -- the rest target that was running before this set
);

-- Running volume of the first 1, 2, 3 … normal working sets of an exercise in a
-- workout. The volume record (gold) compares workouts at the same number of sets.
DROP TABLE IF EXISTS exercise_set_cum;
CREATE TABLE exercise_set_cum (
    exercise_id TEXT,
    workout_id  TEXT,
    started_at  TEXT,
    k           INTEGER,
    cum_kg      REAL,
    PRIMARY KEY (exercise_id, workout_id, k)
);
CREATE INDEX idx_cum ON exercise_set_cum (exercise_id, k, started_at);

DROP TABLE IF EXISTS exercise_session_facts;
CREATE TABLE exercise_session_facts (
    exercise_id   TEXT,
    workout_id    TEXT,
    day           TEXT,
    week_start    TEXT,
    started_at    TEXT,
    name          TEXT,
    sets          REAL,          -- hard sets
    work_sets     INTEGER,       -- normal working sets
    reps          INTEGER,
    volume_kg     REAL,
    top_load_kg   REAL,
    top_weight_kg REAL,
    compare_sets  INTEGER,       -- how many sets the volume record compares
    compare_kg    REAL,          -- volume of this workout's first compare_sets sets
    before_best   REAL,          -- the best volume of that many sets in any EARLIER workout
    is_volume_pr  INTEGER,       -- 1 = gold
    session_no    INTEGER,
    PRIMARY KEY (exercise_id, workout_id)
);
CREATE INDEX idx_esf_day ON exercise_session_facts (exercise_id, started_at);

DROP TABLE IF EXISTS cur_sets;
CREATE TABLE cur_sets (
    set_id               TEXT PRIMARY KEY,
    workout_id           TEXT,
    entry_id             TEXT,
    exercise_id          TEXT,
    day                  TEXT,
    week_start           TEXT,
    is_work              INTEGER,
    hard                 REAL,
    weight_kg            REAL,
    reps                 INTEGER,
    eff_reps             INTEGER,
    load_kg              REAL,
    strength_kg          REAL,
    body_kg              REAL,
    volume_kg            REAL,
    set_sec              REAL,
    rest_sec             REAL,
    first_of_exercise    INTEGER,
    prev_is_work         INTEGER,
    target_rest_sec      INTEGER,
    prev_target_rest_sec INTEGER,
    e1rm                 REAL       -- estimated 1RM with the formula chosen in Settings
);
CREATE INDEX idx_cur_sets_exercise ON cur_sets (exercise_id);
CREATE INDEX idx_cur_sets_week ON cur_sets (week_start);

DROP TABLE IF EXISTS cur_workouts;
CREATE TABLE cur_workouts (
    workout_id    TEXT PRIMARY KEY,
    name          TEXT,
    started_at    TEXT,
    day           TEXT,
    week_start    TEXT,
    duration_min  REAL,
    work_sets     REAL,         -- hard sets
    volume_kg     REAL,
    avg_rest_sec  REAL,         -- between working sets of the same exercise
    avg_pause_sec REAL          -- between exercises
);

DROP TABLE IF EXISTS cur_span;
CREATE TABLE cur_span (
    end_day            TEXT,
    first_week         TEXT,
    last_week          TEXT,
    last_complete_week TEXT
);

DROP TABLE IF EXISTS cur_weeks;
CREATE TABLE cur_weeks (
    week_start  TEXT PRIMARY KEY,
    is_complete INTEGER,
    counted     INTEGER         -- 1 = used for weekly averages
);


-- =====================================================================
--  Overview
-- =====================================================================

DROP VIEW IF EXISTS v_totals;
CREATE VIEW v_totals AS
SELECT (SELECT COUNT(*) FROM cur_workouts)                          AS workouts,
       (SELECT COALESCE(SUM(hard), 0) FROM cur_sets)                AS work_sets,
       (SELECT COALESCE(SUM(volume_kg), 0) FROM cur_sets)           AS volume_kg,
       (SELECT COALESCE(AVG(duration_min), 0) FROM cur_workouts)    AS avg_duration_min,
       (SELECT COUNT(DISTINCT exercise_id) FROM cur_sets)           AS exercises,
       (SELECT COUNT(*) FROM cur_weeks)                             AS weeks,
       (SELECT COUNT(*) FROM cur_weeks WHERE counted = 1)           AS counted_weeks,
       (SELECT MIN(day) FROM cur_workouts)                          AS first_day,
       (SELECT MAX(day) FROM cur_workouts)                          AS last_day;

-- One row per week: hard sets, kilograms lifted, number of workouts.
DROP VIEW IF EXISTS v_weekly;
CREATE VIEW v_weekly AS
SELECT k.week_start, k.is_complete,
       COALESCE(a.sets, 0)      AS sets,
       COALESCE(a.volume_kg, 0) AS volume_kg,
       COALESCE(a.workouts, 0)  AS workouts,
       COALESCE(a.minutes, 0)   AS minutes
FROM cur_weeks k
LEFT JOIN (SELECT week_start, SUM(work_sets) AS sets, SUM(volume_kg) AS volume_kg,
                  COUNT(*) AS workouts, SUM(duration_min) AS minutes
           FROM cur_workouts GROUP BY week_start) a ON a.week_start = k.week_start
ORDER BY k.week_start;


-- =====================================================================
--  Muscles
-- =====================================================================

-- Hard sets per workout and muscle: 1 per set for primary muscles, the
-- exercise's share (0.1 to 0.9) for secondary ones. A drop-set part counts half.
DROP VIEW IF EXISTS v_workout_muscle;
CREATE VIEW v_workout_muscle AS
SELECT c.workout_id, c.week_start, em.muscle_id, SUM(c.hard * em.weight) AS sets
FROM cur_sets c
JOIN exercise_muscles em ON em.exercise_id = c.exercise_id
GROUP BY c.workout_id, em.muscle_id;

-- One row per week and muscle (also when the muscle got nothing that week).
-- A workout counts as a "session" for a muscle when it gave it at least one full set.
DROP VIEW IF EXISTS v_muscle_week;
CREATE VIEW v_muscle_week AS
SELECT k.week_start, k.is_complete, k.counted, m.id AS muscle_id,
       COALESCE(SUM(wm.sets), 0)                 AS sets,
       COUNT(CASE WHEN wm.sets >= 1 THEN 1 END)  AS sessions
FROM cur_weeks k
CROSS JOIN muscles m
LEFT JOIN v_workout_muscle wm ON wm.week_start = k.week_start AND wm.muscle_id = m.id
GROUP BY k.week_start, m.id;

-- One row per muscle (all of them): average weekly sets against the target range.
--   status 'none'  no sets, but the target asks for some     'idle'  no sets, target minimum 0
--          'under' below the minimum      'ok'  inside the range      'high'  above the maximum
DROP VIEW IF EXISTS v_muscle_avg;
CREATE VIEW v_muscle_avg AS
SELECT m.id AS muscle_id, m.name, m.region, m.sort_order, m.target_min, m.target_max,
       COALESCE(a.weeks, 0)             AS weeks,
       COALESCE(a.sets_per_week, 0)     AS sets_per_week,
       COALESCE(a.sessions_per_week, 0) AS sessions_per_week,
       CASE WHEN COALESCE(a.sets_per_week, 0) = 0 THEN CASE WHEN m.target_min > 0 THEN 'none' ELSE 'idle' END
            WHEN a.sets_per_week < m.target_min THEN 'under'
            WHEN a.sets_per_week > m.target_max THEN 'high'
            ELSE 'ok' END               AS status
FROM muscles m
LEFT JOIN (SELECT muscle_id, COUNT(*) AS weeks,
                  SUM(sets) * 1.0 / COUNT(*)     AS sets_per_week,
                  SUM(sessions) * 1.0 / COUNT(*) AS sessions_per_week
           FROM v_muscle_week WHERE counted = 1 GROUP BY muscle_id) a ON a.muscle_id = m.id;

-- The list of the Muscles page (only one muscle when the muscle filter is set).
DROP VIEW IF EXISTS v_muscles;
CREATE VIEW v_muscles AS
SELECT * FROM v_muscle_avg
WHERE (SELECT muscle_id FROM state) IS NULL OR muscle_id = (SELECT muscle_id FROM state)
ORDER BY sort_order;

-- Weekly sets of the muscle that is selected on the Muscles page.
DROP VIEW IF EXISTS v_muscle_series;
CREATE VIEW v_muscle_series AS
SELECT week_start, is_complete, sets, sessions
FROM v_muscle_week
WHERE muscle_id = (SELECT sel_muscle FROM state)
ORDER BY week_start;

-- Which exercises gave the selected muscle its sets (complete weeks only).
DROP VIEW IF EXISTS v_muscle_exercises;
CREATE VIEW v_muscle_exercises AS
WITH n AS (SELECT max(1, COUNT(*)) AS weeks FROM cur_weeks WHERE counted = 1)
SELECT x.id AS exercise_id, x.name, em.role,
       SUM(c.hard)                          AS work_sets,
       SUM(c.hard * em.weight) * 1.0 / n.weeks AS sets_per_week,
       SUM(c.volume_kg)                     AS volume_kg
FROM cur_sets c
JOIN cur_weeks k ON k.week_start = c.week_start AND k.counted = 1
JOIN exercise_muscles em ON em.exercise_id = c.exercise_id AND em.muscle_id = (SELECT sel_muscle FROM state)
JOIN exercises x ON x.id = c.exercise_id
CROSS JOIN n
GROUP BY x.id
HAVING SUM(c.hard) > 0
ORDER BY sets_per_week DESC, x.name;

-- Everything about the selected muscle in the chosen range, as one row.
DROP VIEW IF EXISTS v_muscle_detail;
CREATE VIEW v_muscle_detail AS
SELECT m.*,
       (SELECT COUNT(*) FROM v_muscle_exercises)                                    AS exercises,
       (SELECT COUNT(*) FROM v_muscle_week w WHERE w.muscle_id = m.muscle_id AND w.counted = 1
                                               AND w.sets < m.target_min)          AS weeks_under,
       (SELECT COUNT(*) FROM v_muscle_week w WHERE w.muscle_id = m.muscle_id AND w.counted = 1
                                               AND w.sets >= m.target_min AND w.sets <= m.target_max) AS weeks_ok,
       (SELECT COUNT(*) FROM v_muscle_week w WHERE w.muscle_id = m.muscle_id AND w.counted = 1
                                               AND w.sets > m.target_max)          AS weeks_high,
       (SELECT MAX(w.sets) FROM v_muscle_week w WHERE w.muscle_id = m.muscle_id)    AS best_week_sets,
       (SELECT COALESCE(SUM(c.volume_kg * em.weight), 0) FROM cur_sets c
          JOIN exercise_muscles em ON em.exercise_id = c.exercise_id AND em.muscle_id = m.muscle_id) AS volume_kg
FROM v_muscle_avg m
WHERE m.muscle_id = (SELECT sel_muscle FROM state);

-- Push against pull, upper against lower body, in working sets per week.
DROP VIEW IF EXISTS v_balance;
CREATE VIEW v_balance AS
WITH n AS (SELECT max(1, COUNT(*)) AS weeks FROM cur_weeks WHERE counted = 1),
     t AS (SELECT x.movement, SUM(c.hard) AS sets
           FROM cur_sets c
           JOIN cur_weeks k ON k.week_start = c.week_start AND k.counted = 1
           JOIN exercises x ON x.id = c.exercise_id
           GROUP BY x.movement),
     p AS (SELECT COALESCE((SELECT sets FROM t WHERE movement = 'push'), 0) * 1.0 / n.weeks AS push,
                  COALESCE((SELECT sets FROM t WHERE movement = 'pull'), 0) * 1.0 / n.weeks AS pull,
                  COALESCE((SELECT sets FROM t WHERE movement = 'legs'), 0) * 1.0 / n.weeks AS legs
           FROM n)
SELECT 'push_pull' AS pair, 'Drücken' AS a_label, p.push AS a_value, 'Ziehen' AS b_label, p.pull AS b_value FROM p
UNION ALL
SELECT 'upper_lower', 'Oberkörper', p.push + p.pull, 'Beine', p.legs FROM p;


-- =====================================================================
--  Strength
-- =====================================================================

-- Per exercise: is the estimated 1RM going up? Not one week against another
-- (one bad day would decide), but the TREND: a straight line through the best
-- e1RM of every training week of the last 6 weeks (least squares).
--   weeks_fit       how many training weeks the line is based on (4 or more: reliable)
--   last_e1rm       the line today          ref_e1rm   the line 4 weeks ago
--   pct_4w          change over 4 weeks along the line, in %
--   weeks_since_best    weeks since the best e1RM in the range was first reached
--   trained_since_best  in how many of those weeks the exercise was trained
DROP VIEW IF EXISTS v_exercise_trend;
CREATE VIEW v_exercise_trend AS
WITH wk AS (SELECT exercise_id, week_start, MAX(e1rm) AS e1rm
            FROM cur_sets WHERE e1rm IS NOT NULL
            GROUP BY exercise_id, week_start),
     agg AS (SELECT exercise_id, MAX(week_start) AS last_week, MAX(e1rm) AS max_e1rm, COUNT(*) AS weeks
             FROM wk GROUP BY exercise_id),
     pts AS (SELECT w.exercise_id, (julianday(w.week_start) - julianday(a.last_week)) / 7.0 AS x, w.e1rm AS y
             FROM wk w JOIN agg a ON a.exercise_id = w.exercise_id
             WHERE w.week_start >= date(a.last_week, '-35 days')),
     fit AS (SELECT exercise_id, COUNT(*) AS n, SUM(x) AS sx, SUM(y) AS sy, SUM(x * x) AS sxx, SUM(x * y) AS sxy
             FROM pts GROUP BY exercise_id),
     line AS (SELECT exercise_id, n,
                     CASE WHEN n >= 3 AND n * sxx - sx * sx > 0 THEN (n * sxy - sx * sy) / (n * sxx - sx * sx) END AS slope,
                     sx, sy
              FROM fit),
     base AS (SELECT a.exercise_id, a.weeks, a.last_week, a.max_e1rm, l.n AS weeks_fit, l.slope,
                     CASE WHEN l.slope IS NOT NULL THEN (l.sy - l.slope * l.sx) / l.n END AS last_e1rm,
                     (SELECT MIN(w.week_start) FROM wk w
                       WHERE w.exercise_id = a.exercise_id AND w.e1rm >= a.max_e1rm - 0.001) AS best_week
              FROM agg a LEFT JOIN line l ON l.exercise_id = a.exercise_id)
SELECT b.exercise_id, b.weeks, b.weeks_fit, b.last_week, b.max_e1rm, b.last_e1rm,
       b.last_e1rm - 4 * b.slope AS ref_e1rm, b.best_week,
       CASE WHEN b.last_e1rm - 4 * b.slope > 0 THEN (b.last_e1rm / (b.last_e1rm - 4 * b.slope) - 1) * 100.0 END AS pct_4w,
       CAST(round((julianday(b.last_week) - julianday(b.best_week)) / 7.0) AS INTEGER) AS weeks_since_best,
       (SELECT COUNT(*) FROM wk w
         WHERE w.exercise_id = b.exercise_id AND w.week_start > b.best_week) AS trained_since_best
FROM base b;

-- One row per exercise and workout, over ALL your data (a table filled by
-- "refresh"). is_volume_pr = 1: more kilograms than ever with the same number of sets.
DROP VIEW IF EXISTS v_exercise_session_all;
CREATE VIEW v_exercise_session_all AS SELECT * FROM exercise_session_facts;

-- Sessions of the selected exercise inside the chosen range.
DROP VIEW IF EXISTS v_exercise_sessions;
CREATE VIEW v_exercise_sessions AS
SELECT a.workout_id, a.day, a.name, a.sets, a.work_sets, a.reps, a.volume_kg, a.top_load_kg, a.top_weight_kg, a.session_no,
       a.compare_sets, a.compare_kg, a.before_best, a.is_volume_pr
FROM v_exercise_session_all a CROSS JOIN state s
WHERE a.exercise_id = s.sel_exercise
  AND (s.from_day IS NULL OR a.day >= s.from_day) AND (s.to_day IS NULL OR a.day <= s.to_day)
ORDER BY a.started_at;

-- The line chart of the Exercises page: the best set of each training day.
--   multi-joint exercises with weights: the estimated 1RM (metric 'e1rm')
--   everything else: the heaviest working weight of the day (metric 'top')
-- rel = the value divided by the body weight of that day (relative strength).
-- is_pr = 1 when that day beat every earlier day (over ALL your data, not only
-- the chosen range). Those points are drawn in gold.
DROP VIEW IF EXISTS v_strength_series;
CREATE VIEW v_strength_series AS
WITH ex AS (SELECT COALESCE((SELECT compound = 1 AND load_type = 'external' AND unit = 'reps' FROM exercises WHERE id = st.sel_exercise), 0) AS has_e1rm
            FROM state st),
daily AS (
    SELECT f.day, f.load_kg, f.strength_kg, f.weight_kg, f.eff_reps AS reps, f.body_kg,
           CASE WHEN ex.has_e1rm = 1
                THEN CASE st.formula WHEN 'brzycki' THEN f.e1rm_brzycki ELSE f.e1rm_epley END
                ELSE f.strength_kg END AS value
    FROM set_facts f CROSS JOIN state st CROSS JOIN ex
    WHERE f.exercise_id = st.sel_exercise AND f.is_work = 1),
best AS (
    SELECT day, value, load_kg, weight_kg, reps, body_kg,
           ROW_NUMBER() OVER (PARTITION BY day ORDER BY value DESC, reps DESC) AS rn
    FROM daily WHERE value IS NOT NULL AND value > 0),
running AS (
    SELECT day, value, load_kg, weight_kg, reps, body_kg,
           MAX(value) OVER (ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS before_best
    FROM best WHERE rn = 1)
SELECT r.day, r.value AS e1rm, r.value, r.load_kg, r.weight_kg, r.reps,
       CASE WHEN r.body_kg > 0 THEN r.value / r.body_kg END AS rel,
       (SELECT CASE WHEN has_e1rm = 1 THEN 'e1rm' ELSE 'top' END FROM ex) AS metric,
       (r.before_best IS NOT NULL AND r.value > r.before_best + 0.001) AS is_pr
FROM running r CROSS JOIN state s
WHERE (s.from_day IS NULL OR r.day >= s.from_day) AND (s.to_day IS NULL OR r.day <= s.to_day)
ORDER BY r.day;

-- Everything about the selected exercise in the chosen range, as one row.
DROP VIEW IF EXISTS v_exercise_detail;
CREATE VIEW v_exercise_detail AS
WITH ses AS (SELECT * FROM v_exercise_sessions),
     cs AS (SELECT c.* FROM cur_sets c CROSS JOIN state s WHERE c.exercise_id = s.sel_exercise),
     wk AS (SELECT max(1, COUNT(*)) AS n FROM cur_weeks WHERE counted = 1),
     x AS (SELECT * FROM exercises WHERE id = (SELECT sel_exercise FROM state))
SELECT (SELECT COUNT(*) FROM ses)                                   AS sessions,
       (SELECT COALESCE(SUM(sets), 0) FROM ses)                     AS work_sets,
       (SELECT COUNT(*) FROM cs WHERE hard = 0)                     AS warmup_sets,
       (SELECT COUNT(*) FROM cs WHERE hard = 0.5)                   AS drop_sets,
       (SELECT COALESCE(SUM(reps), 0) FROM ses)                     AS total_reps,
       (SELECT COALESCE(SUM(volume_kg), 0) FROM ses)                AS volume_kg,
       (SELECT MAX(volume_kg) FROM ses)                             AS best_session_kg,
       (SELECT day FROM ses ORDER BY volume_kg DESC LIMIT 1)        AS best_session_day,
       (SELECT COALESCE(SUM(is_volume_pr), 0) FROM ses)             AS volume_prs,
       (SELECT COALESCE(SUM(is_pr), 0) FROM v_strength_series)      AS e1rm_prs,
       (SELECT AVG(eff_reps) FROM cs WHERE is_work = 1)             AS avg_reps,
       (SELECT AVG(rest_sec) FROM cs WHERE first_of_exercise = 0 AND is_work = 1 AND prev_is_work = 1
                                       AND rest_sec BETWEEN 5 AND 900) AS avg_rest_sec,
       (SELECT AVG(set_sec) FROM cs WHERE is_work = 1 AND set_sec BETWEEN 3 AND 600) AS avg_set_sec,
       (SELECT COALESCE(SUM(sets), 0) FROM ses
         WHERE day >= (SELECT MIN(week_start) FROM cur_weeks WHERE counted = 1)
           AND day <= date((SELECT MAX(week_start) FROM cur_weeks WHERE counted = 1), '+6 days')) * 1.0
         / (SELECT n FROM wk)                                       AS sets_per_week,
       (SELECT MIN(day) FROM ses)                                   AS first_day,
       (SELECT MAX(day) FROM ses)                                   AS last_day,
       (SELECT compound = 1 AND load_type = 'external' AND unit = 'reps' FROM x) AS has_e1rm,
       (SELECT load_mode FROM x)                                    AS load_mode,
       (SELECT unit FROM x)                                         AS unit,
       -- relative strength: the best value of the range divided by the body weight on that day
       (SELECT rel FROM v_strength_series WHERE rel IS NOT NULL ORDER BY value DESC LIMIT 1) AS best_rel,
       (SELECT rel FROM v_strength_series WHERE rel IS NOT NULL ORDER BY day DESC LIMIT 1)   AS last_rel,
       (SELECT GROUP_CONCAT(name, ', ') FROM (
           SELECT m.name FROM exercise_muscles em JOIN muscles m ON m.id = em.muscle_id
            WHERE em.exercise_id = (SELECT sel_exercise FROM state) AND em.role = 'primary'
            ORDER BY m.sort_order))                                AS primary_names,
       -- secondary muscles in body order, with their share: "Trizeps (0,6)"
       (SELECT GROUP_CONCAT(name, ', ') FROM (
           SELECT m.name || ' (' || replace(printf('%g', em.weight), '.', ',') || ')' AS name
             FROM exercise_muscles em JOIN muscles m ON m.id = em.muscle_id
            WHERE em.exercise_id = (SELECT sel_exercise FROM state) AND em.role = 'secondary'
            ORDER BY m.sort_order))                                AS secondary_names;

-- Hard sets and kilograms of the selected exercise per week (empty weeks included).
DROP VIEW IF EXISTS v_exercise_weekly;
CREATE VIEW v_exercise_weekly AS
SELECT k.week_start, k.is_complete,
       COALESCE(SUM(c.hard), 0)      AS sets,
       COALESCE(SUM(c.volume_kg), 0) AS volume_kg
FROM cur_weeks k
LEFT JOIN cur_sets c ON c.week_start = k.week_start AND c.exercise_id = (SELECT sel_exercise FROM state)
GROUP BY k.week_start
ORDER BY k.week_start;

-- The exercise list of the Strength page.
DROP VIEW IF EXISTS v_exercise_stats;
CREATE VIEW v_exercise_stats AS
SELECT c.exercise_id,
       COALESCE(x.name, 'Unbekannte Übung') AS name,
       COALESCE(x.load_type, 'external')    AS load_type,
       COALESCE(x.load_mode, 'total')       AS load_mode,
       COALESCE(x.unit, 'reps')             AS unit,
       (COALESCE(x.compound, 1) = 1 AND COALESCE(x.load_type, 'external') = 'external' AND COALESCE(x.unit, 'reps') = 'reps') AS has_e1rm,
       SUM(c.hard)                          AS sets,
       COUNT(DISTINCT c.workout_id)         AS sessions,
       MAX(c.day)                           AS last_day,
       MAX(c.e1rm)                          AS best_e1rm,
       MAX(CASE WHEN c.is_work = 1 THEN c.strength_kg END) AS best_weight,
       COUNT(c.e1rm)                        AS e1rm_sets,   -- working sets of 8 reps or fewer
       SUM(c.is_work)                       AS work_sets,
       t.weeks_fit, t.last_e1rm, t.ref_e1rm, t.pct_4w, t.weeks_since_best, t.trained_since_best,
       SUM(c.volume_kg)                     AS volume_kg,
       -- gold: the most recent session in the range was a volume record
       (SELECT a.is_volume_pr FROM v_exercise_session_all a
         WHERE a.exercise_id = c.exercise_id AND a.day <= (SELECT end_day FROM cur_span)
         ORDER BY a.started_at DESC LIMIT 1) AS gold
FROM cur_sets c
LEFT JOIN exercises x ON x.id = c.exercise_id
LEFT JOIN v_exercise_trend t ON t.exercise_id = c.exercise_id
GROUP BY c.exercise_id
HAVING SUM(c.hard) > 0
ORDER BY sets DESC, name;

-- Personal records of the selected exercise.
--   kind 'heaviest'  the heaviest working set
--   kind 'e1rm'      the set with the best estimated 1RM (multi-joint exercises only)
--   kind 'reps'      for each weight: the most reps ever done with it (8 heaviest weights)
DROP VIEW IF EXISTS v_prs;
CREATE VIEW v_prs AS
SELECT * FROM (SELECT 'heaviest' AS kind, c.weight_kg, c.load_kg, c.eff_reps AS reps, c.e1rm, c.day
               FROM cur_sets c
               WHERE c.exercise_id = (SELECT sel_exercise FROM state) AND c.is_work = 1
               ORDER BY c.load_kg DESC, c.eff_reps DESC, c.day LIMIT 1)
UNION ALL
SELECT * FROM (SELECT 'e1rm', c.weight_kg, c.load_kg, c.eff_reps, c.e1rm, c.day
               FROM cur_sets c
               WHERE c.exercise_id = (SELECT sel_exercise FROM state) AND c.e1rm IS NOT NULL
               ORDER BY c.e1rm DESC, c.day LIMIT 1)
UNION ALL
SELECT * FROM (SELECT 'reps', r.weight_kg, r.load_kg, r.reps, r.e1rm, r.day
               FROM (SELECT c.weight_kg, c.load_kg, c.eff_reps AS reps, c.e1rm, c.day,
                            ROW_NUMBER() OVER (PARTITION BY c.weight_kg ORDER BY c.eff_reps DESC, c.day) AS rn
                     FROM cur_sets c
                     WHERE c.exercise_id = (SELECT sel_exercise FROM state) AND c.is_work = 1) r
               WHERE r.rn = 1
               ORDER BY r.weight_kg DESC LIMIT 8);


-- =====================================================================
--  Sessions (duration and rest)
-- =====================================================================

DROP VIEW IF EXISTS v_sessions;
CREATE VIEW v_sessions AS
SELECT workout_id, name, day, started_at, duration_min, work_sets, volume_kg, avg_rest_sec, avg_pause_sec
FROM cur_workouts
ORDER BY started_at;

DROP VIEW IF EXISTS v_session_stats;
CREATE VIEW v_session_stats AS
SELECT (SELECT AVG(duration_min) FROM cur_workouts) AS avg_duration_min,
       (SELECT AVG(rest_sec) FROM cur_sets
         WHERE first_of_exercise = 0 AND is_work = 1 AND prev_is_work = 1
           AND rest_sec BETWEEN 5 AND 900)          AS avg_rest_sec,
       (SELECT AVG(rest_sec) FROM cur_sets
         WHERE first_of_exercise = 1 AND rest_sec BETWEEN 5 AND 1800) AS avg_pause_sec,
       (SELECT AVG(set_sec) FROM cur_sets
         WHERE is_work = 1 AND set_sec BETWEEN 3 AND 600)             AS avg_set_sec;

-- Actual rest against the rest target, for the ten most-trained exercises.
DROP VIEW IF EXISTS v_rest_by_exercise;
CREATE VIEW v_rest_by_exercise AS
SELECT x.name, COUNT(*) AS rests, AVG(c.rest_sec) AS avg_rest_sec, AVG(c.prev_target_rest_sec) AS avg_target_sec
FROM cur_sets c
JOIN exercises x ON x.id = c.exercise_id
WHERE c.first_of_exercise = 0 AND c.is_work = 1 AND c.prev_is_work = 1 AND c.rest_sec BETWEEN 5 AND 900
GROUP BY c.exercise_id
ORDER BY rests DESC, x.name
LIMIT 10;


-- =====================================================================
--  Consistency
-- =====================================================================

-- One row per day with a workout (for the calendar heatmap).
DROP VIEW IF EXISTS v_days;
CREATE VIEW v_days AS
SELECT day, COUNT(*) AS workouts, SUM(work_sets) AS sets, SUM(duration_min) AS minutes
FROM cur_workouts
GROUP BY day
ORDER BY day;

-- Streaks are counted in weeks with at least one workout.
-- Trick: number the active weeks 1, 2, 3 … and subtract that number from the
-- week's own running number. Weeks that follow each other get the same result.
DROP VIEW IF EXISTS v_streaks;
CREATE VIEW v_streaks AS
WITH wk AS (SELECT k.week_start, k.counted,
                   (SELECT COUNT(*) FROM cur_workouts w WHERE w.week_start = k.week_start) AS n
            FROM cur_weeks k),
     act AS (SELECT week_start,
                    CAST(julianday(week_start) AS INTEGER) / 7 - ROW_NUMBER() OVER (ORDER BY week_start) AS grp
             FROM wk WHERE n > 0),
     runs AS (SELECT grp, COUNT(*) AS len, MAX(week_start) AS last_week FROM act GROUP BY grp)
SELECT COALESCE((SELECT MAX(len) FROM runs), 0) AS longest_streak,
       COALESCE((SELECT len FROM runs
                  WHERE last_week >= (SELECT last_complete_week FROM cur_span)
                  ORDER BY last_week DESC LIMIT 1), 0) AS current_streak,
       (SELECT COUNT(*) FROM wk WHERE counted = 1 AND n > 0) AS active_weeks,
       (SELECT COUNT(*) FROM wk WHERE counted = 1)           AS counted_weeks,
       COALESCE((SELECT SUM(n) * 1.0 / COUNT(*) FROM wk WHERE counted = 1), 0) AS workouts_per_week;


-- =====================================================================
--  Body weight and body measurements
-- =====================================================================

-- One row per day, with the average of the last 7 days (the trend line).
DROP VIEW IF EXISTS v_bodyweight_all;
CREATE VIEW v_bodyweight_all AS
WITH d AS (SELECT day, AVG(weight_kg) AS weight_kg
           FROM body_weights WHERE deleted_at IS NULL GROUP BY day)
SELECT day, weight_kg,
       AVG(weight_kg) OVER (ORDER BY CAST(julianday(day) AS INTEGER)
                            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS avg7
FROM d;

DROP VIEW IF EXISTS v_bodyweight;
CREATE VIEW v_bodyweight AS
SELECT m.day, m.weight_kg, m.avg7
FROM v_bodyweight_all m CROSS JOIN state s
WHERE (s.from_day IS NULL OR m.day >= s.from_day) AND (s.to_day IS NULL OR m.day <= s.to_day)
ORDER BY m.day;

-- Start of the trend: average of the first 7 days. End: the 7-day average of the last day.
-- rate_kg_week: change of the 7-day average over the last 4 weeks, per week.
-- rate_pct_week: the same in % of the body weight — the number to steer a
-- build-up (about +0.25 to +0.5 %/week) or a diet (about -0.5 to -1 %/week) by.
DROP VIEW IF EXISTS v_bodyweight_stats;
CREATE VIEW v_bodyweight_stats AS
WITH r AS (SELECT COUNT(*) AS entries, MIN(day) AS first_day, MAX(day) AS last_day FROM v_bodyweight),
     e AS (SELECT r.*,
                  (SELECT AVG(weight_kg) FROM v_bodyweight WHERE day <= date(r.first_day, '+6 days')) AS first_avg,
                  (SELECT avg7 FROM v_bodyweight ORDER BY day DESC LIMIT 1)                           AS last_avg,
                  (SELECT weight_kg FROM v_bodyweight ORDER BY day DESC LIMIT 1)                      AS last_weight,
                  (SELECT avg7 FROM v_bodyweight_all a
                    WHERE a.day <= date(r.last_day, '-28 days') ORDER BY a.day DESC LIMIT 1)          AS avg_4w_ago,
                  (SELECT day FROM v_bodyweight_all a
                    WHERE a.day <= date(r.last_day, '-28 days') ORDER BY a.day DESC LIMIT 1)          AS day_4w_ago,
                  COALESCE(julianday(r.last_day) - julianday(r.first_day), 0)                         AS span_days
           FROM r)
SELECT e.entries, e.first_day, e.last_day, e.first_avg, e.last_avg, e.last_weight, e.span_days,
       CASE WHEN e.avg_4w_ago IS NOT NULL AND julianday(e.last_day) - julianday(e.day_4w_ago) >= 21
            THEN (e.last_avg - e.avg_4w_ago) / ((julianday(e.last_day) - julianday(e.day_4w_ago)) / 7.0) END AS rate_kg_week,
       CASE WHEN e.avg_4w_ago IS NOT NULL AND julianday(e.last_day) - julianday(e.day_4w_ago) >= 21 AND e.last_avg > 0
            THEN (e.last_avg - e.avg_4w_ago) / ((julianday(e.last_day) - julianday(e.day_4w_ago)) / 7.0) / e.last_avg * 100.0 END AS rate_pct_week
FROM e;

-- Body measurements in the chosen range, one row per entry.
DROP VIEW IF EXISTS v_measurements;
CREATE VIEW v_measurements AS
SELECT m.day, m.waist_cm, m.chest_cm, m.arm_cm, m.thigh_cm, m.calf_cm, m.body_fat_pct
FROM measurements m CROSS JOIN state s
WHERE m.deleted_at IS NULL
  AND (s.from_day IS NULL OR m.day >= s.from_day) AND (s.to_day IS NULL OR m.day <= s.to_day)
ORDER BY m.day;

-- Per measure: first and last value in the range (one row per measure that has values).
DROP VIEW IF EXISTS v_measurement_stats;
CREATE VIEW v_measurement_stats AS
WITH long AS (
    SELECT day, 'waist_cm' AS id, 'Taille' AS name, 'cm' AS unit, 1 AS sort_order, waist_cm AS value FROM v_measurements
    UNION ALL SELECT day, 'chest_cm', 'Brust', 'cm', 2, chest_cm FROM v_measurements
    UNION ALL SELECT day, 'arm_cm', 'Oberarm', 'cm', 3, arm_cm FROM v_measurements
    UNION ALL SELECT day, 'thigh_cm', 'Oberschenkel', 'cm', 4, thigh_cm FROM v_measurements
    UNION ALL SELECT day, 'calf_cm', 'Wade', 'cm', 5, calf_cm FROM v_measurements
    UNION ALL SELECT day, 'body_fat_pct', 'Körperfett', '%', 6, body_fat_pct FROM v_measurements)
SELECT id, name, unit, sort_order, COUNT(*) AS entries,
       (SELECT l2.value FROM long l2 WHERE l2.id = l.id AND l2.value IS NOT NULL ORDER BY l2.day LIMIT 1)      AS first_value,
       (SELECT l2.value FROM long l2 WHERE l2.id = l.id AND l2.value IS NOT NULL ORDER BY l2.day DESC LIMIT 1) AS last_value,
       MIN(day) AS first_day, MAX(day) AS last_day
FROM long l
WHERE value IS NOT NULL
GROUP BY id
ORDER BY sort_order;


-- =====================================================================
--  Lists for the filter bar, the Data page and the Settings page
-- =====================================================================

DROP VIEW IF EXISTS v_filter_exercises;
CREATE VIEW v_filter_exercises AS
SELECT x.id, x.name
FROM exercises x
WHERE x.id IN (SELECT exercise_id FROM set_facts)
ORDER BY x.name;

DROP VIEW IF EXISTS v_muscle_list;
CREATE VIEW v_muscle_list AS
SELECT id, name, region, target_min, target_max, base_min, base_max FROM muscles ORDER BY sort_order;

DROP VIEW IF EXISTS v_exercises_all;
CREATE VIEW v_exercises_all AS
SELECT x.id, x.name, x.is_custom,
       COALESCE((SELECT GROUP_CONCAT(em.muscle_id) FROM exercise_muscles em
                  WHERE em.exercise_id = x.id AND em.role = 'primary'), '')   AS primary_ids,
       COALESCE((SELECT GROUP_CONCAT(em.muscle_id) FROM exercise_muscles em
                  WHERE em.exercise_id = x.id AND em.role = 'secondary'), '') AS secondary_ids,
       -- "triceps:0.25,front_delts:0.75": the share of each secondary muscle
       COALESCE((SELECT GROUP_CONCAT(em.muscle_id || ':' || em.weight) FROM exercise_muscles em
                  WHERE em.exercise_id = x.id AND em.role = 'secondary'), '') AS secondary_shares,
       (SELECT COUNT(*) FROM set_facts f WHERE f.exercise_id = x.id)          AS sets
FROM exercises x
WHERE x.deleted_at IS NULL
ORDER BY x.name;

DROP VIEW IF EXISTS v_import_log;
CREATE VIEW v_import_log AS
SELECT id, imported_at, file_name, exported_at, export_type, added, updated, unchanged
FROM import_log
ORDER BY id DESC
LIMIT 30;

-- The state row plus a few facts the user interface needs.
DROP VIEW IF EXISTS v_state;
CREATE VIEW v_state AS
SELECT s.from_day, s.to_day, s.exercise_id, s.muscle_id, s.range_preset, s.sel_exercise, s.sel_muscle,
       s.formula, s.level, s.theme, s.animations, s.known_until,
       (SELECT end_day FROM cur_span)              AS end_day,
       (SELECT COUNT(*) FROM workout_facts)        AS all_workouts,
       (SELECT MIN(day) FROM workout_facts)        AS first_data_day,
       (SELECT MAX(day) FROM workout_facts)        AS last_data_day
FROM state s;


-- =====================================================================
--  Next week : a short plan, the first thing on the Overview page.
--  Each row is one concrete thing to change (or keep). Columns:
--    priority  smaller = more important     kind  'add', 'less', 'up', 'stall', 'balance', 'body', 'ok'
--    text      the action                   detail  why
-- =====================================================================

DROP VIEW IF EXISTS v_next_week;
CREATE VIEW v_next_week AS
WITH ctx AS (SELECT (SELECT COUNT(*) FROM cur_weeks WHERE counted = 1) AS weeks,
                    (SELECT COUNT(*) FROM cur_sets WHERE hard > 0)   AS sets),
-- the newest session of each exercise, with the rep target it was done with
last AS (SELECT a.exercise_id, a.workout_id, a.top_weight_kg,
                ROW_NUMBER() OVER (PARTITION BY a.exercise_id ORDER BY a.started_at DESC) AS rn
         FROM exercise_session_facts a CROSS JOIN state s
         WHERE s.to_day IS NULL OR a.day <= s.to_day),
ready AS (SELECT l.exercise_id, x.name, l.top_weight_kg, MAX(e.target_reps_max) AS target,
                 MIN(f.eff_reps) AS min_reps, COUNT(f.set_id) AS work_sets
          FROM last l
          JOIN workout_exercises e ON e.workout_id = l.workout_id AND e.exercise_id = l.exercise_id
          JOIN set_facts f ON f.entry_id = e.id AND f.is_work = 1
          JOIN exercises x ON x.id = l.exercise_id
          WHERE l.rn = 1 AND e.target_reps_max IS NOT NULL
          GROUP BY l.exercise_id
          HAVING MIN(f.eff_reps) >= MAX(e.target_reps_max))
SELECT priority, kind, text, detail FROM (
    -- muscles below their minimum (only with two or more complete weeks)
    SELECT 10 + m.sort_order AS priority, 'add' AS kind,
           printf('%s: +%d %s pro Woche', m.name, CAST(max(1, round(m.target_min - m.sets_per_week + 0.49)) AS INTEGER),
                  CASE WHEN round(m.target_min - m.sets_per_week + 0.49) <= 1 THEN 'Satz' ELSE 'Sätze' END) AS text,
           printf('jetzt %s pro Woche, Ziel %g–%g', replace(printf('%.1f', m.sets_per_week), '.', ','), m.target_min, m.target_max) AS detail
    FROM v_muscles m CROSS JOIN ctx
    WHERE ctx.weeks >= 2 AND m.status IN ('none', 'under') AND m.target_min > 0

    UNION ALL
    -- muscles above their maximum
    SELECT 40 + m.sort_order, 'less',
           printf('%s: %d %s weniger', m.name, CAST(max(1, round(m.sets_per_week - m.target_max + 0.49)) AS INTEGER),
                  CASE WHEN round(m.sets_per_week - m.target_max + 0.49) <= 1 THEN 'Satz' ELSE 'Sätze' END),
           printf('jetzt %s pro Woche, mehr als %g bringt kaum mehr', replace(printf('%.1f', m.sets_per_week), '.', ','), m.target_max)
    FROM v_muscles m CROSS JOIN ctx
    WHERE ctx.weeks >= 2 AND m.status = 'high'

    UNION ALL
    -- exercises where every working set reached the top of the rep target last time
    SELECT 5, 'up', printf('%s: Gewicht erhöhen', r.name),
           printf('letztes Mal alle %d Sätze mit %s kg ≥ %d Wdh. (Ziel erreicht)', r.work_sets,
                  replace(printf('%g', r.top_weight_kg), '.', ','), r.target)
    FROM ready r

    UNION ALL
    -- lifts without progress for 4 weeks or more, though trained at least 3 times since
    SELECT 20, 'stall', printf('%s: seit %d Wochen kein Fortschritt', e.name, e.weeks_since_best),
           'Wdh.-Bereich für 3–4 Wochen wechseln, oder das Gewicht 10 % senken und neu aufbauen'
    FROM v_exercise_stats e
    WHERE e.has_e1rm = 1 AND e.weeks_since_best >= 4 AND e.trained_since_best >= 3

    UNION ALL
    SELECT 30, 'balance', 'Mehr Zugübungen (Rudern, Klimmzüge, Face Pulls)',
           printf('Drücken %s gegen Ziehen %s Sätze pro Woche', replace(printf('%.1f', b.a_value), '.', ','), replace(printf('%.1f', b.b_value), '.', ','))
    FROM v_balance b CROSS JOIN ctx
    WHERE ctx.weeks >= 2 AND b.pair = 'push_pull' AND b.a_value > b.b_value * 1.3

    UNION ALL
    SELECT 35, 'body',
           CASE WHEN w.rate_pct_week > 0 THEN 'Körpergewicht steigt schnell' ELSE 'Körpergewicht fällt schnell' END,
           printf('%s %% pro Woche: über 0,5 %% Zunahme ist meist viel Fett, über 1 %% Abnahme kostet oft Muskeln',
                  replace(printf('%+.2f', w.rate_pct_week), '.', ','))
    FROM v_bodyweight_stats w
    WHERE w.rate_pct_week > 0.5 OR w.rate_pct_week < -1.0

    UNION ALL
    SELECT 99, 'ok', 'Alles im Zielbereich – so weitermachen',
           'Kein Muskel unter oder über seinem Wochenziel, keine Übung steckt fest.'
    FROM ctx
    WHERE ctx.weeks >= 2 AND ctx.sets > 0
      AND NOT EXISTS (SELECT 1 FROM v_muscles m WHERE m.status IN ('none', 'under', 'high') AND (m.target_min > 0 OR m.status = 'high'))
      AND NOT EXISTS (SELECT 1 FROM v_exercise_stats e WHERE e.has_e1rm = 1 AND e.weeks_since_best >= 4 AND e.trained_since_best >= 3)

    UNION ALL
    SELECT 100, 'info', 'Noch zu wenig Daten für einen Plan',
           'Ab zwei vollständigen Trainingswochen im gewählten Zeitraum gibt es hier konkrete Vorschläge.'
    FROM ctx WHERE ctx.weeks < 2
)
ORDER BY priority, text
LIMIT 8;


-- =====================================================================
--  Insights : plain sentences, each with its reasoning, its source and how
--  sure it is.
--
--  Every SELECT below is one rule. It returns a row only when the rule
--  applies. Columns:
--    severity    'warn' (worth acting on), 'good', or 'info'
--    topic       the group it is shown under
--    rank        smaller = shown earlier
--    text        the sentence
--    reason      how the number was calculated / what to do
--    source      where the rule comes from
--    confidence  'hoch', 'mittel' or 'niedrig': how much data the statement rests on
--  A warning that rests on little data is shown as 'info', so a single odd
--  week never raises an alarm.
-- =====================================================================

-- Things several rules need: the 1RM formula, the number of weeks averaged over.
DROP VIEW IF EXISTS v_ctx;
CREATE VIEW v_ctx AS
SELECT CASE s.formula WHEN 'brzycki' THEN 'Brzycki' ELSE 'Epley' END AS formula_name,
       (SELECT COUNT(*) FROM cur_weeks WHERE counted = 1)    AS weeks,
       (SELECT COUNT(*) FROM cur_sets WHERE hard > 0)        AS work_sets,
       CASE WHEN (SELECT COUNT(*) FROM cur_weeks WHERE counted = 1) >= 4 THEN 'hoch'
            WHEN (SELECT COUNT(*) FROM cur_weeks WHERE counted = 1) >= 2 THEN 'mittel'
            ELSE 'niedrig' END                               AS week_confidence
FROM state s;

DROP VIEW IF EXISTS v_insights;
CREATE VIEW v_insights AS
SELECT severity, topic, rank, text, reason, source, confidence FROM (

    -- Nothing to analyse.
    SELECT 'info' AS severity, 'Daten' AS topic, 1 AS rank,
           'Keine Trainings in diesem Zeitraum.' AS text,
           'Importiere eine Export-Datei auf der Seite „Daten“ oder wähle einen größeren Zeitraum und lösche die Filter.' AS reason,
           '' AS source, 'hoch' AS confidence
    FROM v_ctx x WHERE x.work_sets = 0

    UNION ALL
    -- Very little data: say so, because weekly averages are shaky then.
    SELECT 'info', 'Daten', 2,
           printf('Nur %d vollständige Woche%s in diesem Zeitraum.', x.weeks, CASE WHEN x.weeks = 1 THEN '' ELSE 'n' END),
           'Wochenschnitte aus so wenig Daten sind grob. Warnungen werden erst ab zwei Wochen ausgesprochen, sicher sind sie ab vier.',
           '', 'hoch'
    FROM v_ctx x
    WHERE x.work_sets > 0 AND x.weeks < 3 AND (SELECT COALESCE(SUM(is_complete), 0) FROM cur_weeks) > 0

    UNION ALL
    -- Muscles below their weekly minimum. The biggest shortfall comes first.
    SELECT * FROM (
        SELECT CASE WHEN x.weeks >= 2 THEN 'warn' ELSE 'info' END, 'Volumen',
               CASE WHEN ROW_NUMBER() OVER (ORDER BY m.sets_per_week / m.target_min, m.sort_order) = 1 THEN 10
                    ELSE 40 + ROW_NUMBER() OVER (ORDER BY m.sets_per_week / m.target_min, m.sort_order) END,
               CASE WHEN m.status = 'none'
                    THEN printf('%s: keine Sätze, Ziel sind mindestens %g pro Woche.', m.name, m.target_min)
                    ELSE printf('%s: %s Sätze pro Woche, unter dem Minimum von %g.',
                                m.name, replace(printf('%.1f', m.sets_per_week), '.', ','), m.target_min) END,
               printf('Schnitt über %d Woche%s. Ein Satz zählt 1 für einen Hauptmuskel und 0,1 bis 0,9 für einen Nebenmuskel (je nach Übung), ein Drop-Satz-Teil die Hälfte. Aufwärmsätze zählen nicht. Das Ziel für diesen Muskel kannst du in den Einstellungen ändern.',
                      x.weeks, CASE WHEN x.weeks = 1 THEN '' ELSE 'n' END),
               'Schoenfeld, Ogborn & Krieger 2017 (J Sports Sci): 10 oder mehr Wochensätze bauten mehr Muskel auf als weniger. Muskeln, die durch andere Übungen viel mitarbeiten, brauchen weniger direkte Sätze (Pelland et al. 2024, Preprint, Bruchteil-Zählung).',
               x.week_confidence
        FROM v_muscles m CROSS JOIN v_ctx x
        WHERE x.work_sets > 0 AND m.status IN ('none', 'under') AND m.target_min > 0)

    UNION ALL
    -- Muscles above their weekly maximum.
    SELECT 'info', 'Volumen', 35,
           printf('%s: %s Sätze pro Woche, über dem Ziel von höchstens %g.',
                  m.name, replace(printf('%.1f', m.sets_per_week), '.', ','), m.target_max),
           'Über etwa 20 Wochensätzen pro Muskel zeigen Studien kaum zusätzliches Wachstum, die Ermüdung steigt aber weiter. In Ordnung, wenn du dich gut erholst. Sonst ein paar Sätze zu einem Muskel unter seinem Ziel verschieben.',
           'Baz-Valle et al. 2022 (J Hum Kinet), systematische Übersicht zum Trainingsvolumen.',
           x.week_confidence
    FROM v_muscles m CROSS JOIN v_ctx x
    WHERE x.work_sets > 0 AND m.status = 'high'

    UNION ALL
    -- Muscles inside the range, as one summary line.
    SELECT 'good', 'Volumen', 80,
           printf('%d Muskelgruppe%s im Zielbereich: %s.', q.n, CASE WHEN q.n = 1 THEN '' ELSE 'n' END, q.names),
           'Jeder Muskel hat sein eigenes Wochenziel (Einstellungen). Große Muskeln, die wenig mitarbeiten, brauchen mehr direkte Sätze als z. B. die vordere Schulter, die bei jedem Drücken mittrainiert.',
           'Schoenfeld, Ogborn & Krieger 2017 (J Sports Sci). Baz-Valle et al. 2022 (J Hum Kinet).',
           x.week_confidence
    FROM (SELECT COUNT(*) AS n, GROUP_CONCAT(m.name, ', ') AS names
          FROM v_muscles m WHERE m.status = 'ok' AND m.sets_per_week > 0) q CROSS JOIN v_ctx x
    WHERE q.n > 0

    UNION ALL
    -- A lot of weekly volume packed into about one session.
    SELECT * FROM (
        SELECT 'info', 'Häufigkeit', 55,
               printf('%s: %s Sätze pro Woche, fast alle in einer Einheit.', m.name, replace(printf('%.1f', m.sets_per_week), '.', ',')),
               'Die gleichen Sätze auf zwei Einheiten verteilt machst du frischer. Bei gleichem Wochenvolumen ist der Effekt auf das Wachstum klein: eine Option, kein Muss.',
               'Schoenfeld, Ogborn & Krieger 2016 (Sports Med). Schoenfeld, Grgic & Krieger 2019 (J Sports Sci).',
               x.week_confidence
        FROM v_muscles m CROSS JOIN v_ctx x
        WHERE x.work_sets > 0 AND x.weeks >= 2 AND m.sets_per_week >= 8 AND m.sessions_per_week < 1.5
        ORDER BY m.sets_per_week DESC LIMIT 3)

    UNION ALL
    -- Push against pull.
    SELECT CASE WHEN b.a_value > b.b_value * 1.3 AND x.weeks >= 2 THEN 'warn'
                WHEN b.a_value > b.b_value * 1.3 OR b.b_value > b.a_value * 2.0 THEN 'info' ELSE 'good' END,
           'Balance',
           CASE WHEN b.a_value > b.b_value * 1.3 THEN 25 ELSE 75 END,
           CASE WHEN b.a_value > b.b_value * 1.3
                THEN printf('Du drückst mehr als du ziehst: %s gegen %s Sätze pro Woche.', replace(printf('%.1f', b.a_value), '.', ','), replace(printf('%.1f', b.b_value), '.', ','))
                WHEN b.b_value > b.a_value * 2.0
                THEN printf('Du ziehst viel mehr als du drückst: %s gegen %s Sätze pro Woche.', replace(printf('%.1f', b.b_value), '.', ','), replace(printf('%.1f', b.a_value), '.', ','))
                ELSE printf('Drücken und Ziehen sind ausgeglichen: %s gegen %s Sätze pro Woche.', replace(printf('%.1f', b.a_value), '.', ','), replace(printf('%.1f', b.b_value), '.', ',')) END,
           'Zählt die harten Sätze der Drück-Übungen gegen die der Zug-Übungen. Mindestens so viel ziehen wie drücken ist eine verbreitete Trainerregel für gesunde Schultern.',
           'Faustregel aus der Trainingspraxis, kein Studienwert.',
           x.week_confidence
    FROM v_balance b CROSS JOIN v_ctx x
    WHERE b.pair = 'push_pull' AND b.a_value + b.b_value > 0

    UNION ALL
    -- Upper against lower body.
    SELECT CASE WHEN b.b_value < (b.a_value + b.b_value) * 0.25 AND x.weeks >= 2 THEN 'warn'
                WHEN b.b_value < (b.a_value + b.b_value) * 0.25 OR b.b_value > (b.a_value + b.b_value) * 0.60 THEN 'info' ELSE 'good' END,
           'Balance',
           CASE WHEN b.b_value < (b.a_value + b.b_value) * 0.25 THEN 26 ELSE 76 END,
           printf('Die Beine bekommen %d %% deiner Sätze: %s von %s pro Woche.',
                  CAST(round(b.b_value * 100.0 / (b.a_value + b.b_value)) AS INTEGER),
                  replace(printf('%.1f', b.b_value), '.', ','), replace(printf('%.1f', b.a_value + b.b_value), '.', ',')),
           'Zählt die Sätze der Bein-Übungen gegen Drücken und Ziehen. Ein Push/Pull/Beine-Plan gibt den Beinen etwa ein Drittel, ein Ober-/Unterkörper-Plan etwa die Hälfte.',
           'Faustregel aus der Trainingspraxis, kein Studienwert.',
           x.week_confidence
    FROM v_balance b CROSS JOIN v_ctx x
    WHERE b.pair = 'upper_lower' AND b.a_value + b.b_value > 0

    UNION ALL
    -- No new best estimated 1RM for four weeks or more, although the lift was trained at least three times.
    SELECT 'warn', 'Kraft', 20,
           printf('%s: seit %d Wochen kein neuer Bestwert (geschätztes 1RM %s kg).',
                  e.name, e.weeks_since_best, replace(printf('%.1f', e.best_e1rm), '.', ',')),
           printf('Der Bestwert wurde vor %d Wochen erreicht, seither %d Trainingswochen ohne neuen. Möglichkeiten: erst eine Wiederholung mehr, dann mehr Gewicht. Oder den Wdh.-Bereich für ein paar Wochen wechseln. Und Schlaf und Essen prüfen.',
                  e.weeks_since_best, e.trained_since_best),
           'Progressive Überlastung: ACSM Position Stand 2009, Progression Models in Resistance Training for Healthy Adults (Med Sci Sports Exerc).',
           CASE WHEN e.trained_since_best >= 5 THEN 'hoch' ELSE 'mittel' END
    FROM v_exercise_stats e
    WHERE e.has_e1rm = 1 AND e.weeks_since_best >= 4 AND e.trained_since_best >= 3 AND e.e1rm_sets * 2 >= e.work_sets

    UNION ALL
    -- Trend of the estimated 1RM over the last 6 weeks, for the five heaviest lifts that are not stalled.
    SELECT * FROM (
        SELECT CASE WHEN e.pct_4w >= 2 THEN 'good' WHEN e.pct_4w <= -3 AND e.weeks_fit >= 4 THEN 'warn' ELSE 'info' END,
               'Kraft',
               CASE WHEN e.pct_4w <= -3 THEN 22 ELSE 30 END,
               CASE WHEN e.pct_4w >= 0.5
                    THEN printf('%s: geschätztes 1RM steigt, +%d %% in 4 Wochen (%s → %s kg).',
                                e.name, CAST(round(e.pct_4w) AS INTEGER), replace(printf('%.1f', e.ref_e1rm), '.', ','), replace(printf('%.1f', e.last_e1rm), '.', ','))
                    WHEN e.pct_4w <= -0.5
                    THEN printf('%s: geschätztes 1RM sinkt, −%d %% in 4 Wochen (%s → %s kg).',
                                e.name, CAST(round(-e.pct_4w) AS INTEGER), replace(printf('%.1f', e.ref_e1rm), '.', ','), replace(printf('%.1f', e.last_e1rm), '.', ','))
                    ELSE printf('%s: geschätztes 1RM unverändert (%s kg).', e.name, replace(printf('%.1f', e.last_e1rm), '.', ',')) END,
               printf('Trendlinie durch den besten Satz jeder Trainingswoche der letzten 6 Wochen (%d Wochen mit Daten), %s-Formel, nur Mehrgelenksübungen und Sätze bis 8 Wdh. Ein einzelner schlechter Tag verschiebt die Linie kaum.',
                      e.weeks_fit, x.formula_name),
               'Epley 1985 und Brzycki 1993. Über etwa 8–10 Wdh. wird die Schätzung ungenau (LeSuer et al. 1997, J Strength Cond Res).',
               CASE WHEN e.weeks_fit >= 5 THEN 'hoch' WHEN e.weeks_fit >= 4 THEN 'mittel' ELSE 'niedrig' END
        FROM v_exercise_stats e CROSS JOIN v_ctx x
        WHERE e.has_e1rm = 1 AND e.pct_4w IS NOT NULL AND e.weeks_fit >= 3 AND e.e1rm_sets * 2 >= e.work_sets
          AND NOT (e.weeks_since_best >= 4 AND e.trained_since_best >= 3)
        ORDER BY e.best_e1rm DESC LIMIT 5)

    UNION ALL
    -- Volume records (the gold exercises on the phone) in the chosen range.
    SELECT 'good', 'Rekorde', 28,
           printf('%d Volumenrekord%s in diesem Zeitraum, zuletzt bei %s.', q.n, CASE WHEN q.n = 1 THEN '' ELSE 'e' END, q.names),
           'Ein Volumenrekord: mehr Kilogramm (Gewicht × Wdh.) bei einer Übung als je zuvor MIT DERSELBEN SATZZAHL. Ein zusätzlicher lockerer Satz zählt also nicht, nur mehr Leistung pro Satz.',
           'Progressive Überlastung: ACSM Position Stand 2009 (Med Sci Sports Exerc).',
           'hoch'
    FROM (SELECT COUNT(*) AS n,
                 (SELECT x.name FROM v_exercise_session_all a JOIN exercises x ON x.id = a.exercise_id CROSS JOIN state s
                   WHERE a.is_volume_pr = 1
                     AND (s.from_day IS NULL OR a.day >= s.from_day) AND (s.to_day IS NULL OR a.day <= s.to_day)
                   ORDER BY a.started_at DESC LIMIT 1) AS names
          FROM v_exercise_session_all a CROSS JOIN state s
          WHERE a.is_volume_pr = 1
            AND (s.from_day IS NULL OR a.day >= s.from_day) AND (s.to_day IS NULL OR a.day <= s.to_day)) q
    WHERE q.n > 0

    UNION ALL
    -- Rest between working sets.
    SELECT CASE WHEN s.avg_rest_sec < 90 THEN 'info' ELSE 'good' END,
           'Pausen',
           50,
           printf('Durchschnittliche Pause zwischen Arbeitssätzen: %d:%02d%s',
                  CAST(s.avg_rest_sec AS INTEGER) / 60, CAST(s.avg_rest_sec AS INTEGER) % 60,
                  CASE WHEN s.avg_rest_sec < 90 THEN ', kurz für schwere Sätze.' ELSE '.' END),
           'Gemessen vom Speichern eines Satzes bis zum Start des nächsten (oder bis zu seinem Speichern, wenn „Satz starten“ nicht getippt wurde). Supersatz-Wechsel zählen nicht. 2 Minuten oder mehr bei schweren Grundübungen halten die Wiederholungen in späteren Sätzen oben.',
           'Schoenfeld et al. 2016 (J Strength Cond Res): 3 Minuten Pause brachten mehr Kraft und Muskel als 1 Minute.',
           CASE WHEN (SELECT COUNT(*) FROM cur_sets WHERE rest_sec IS NOT NULL) >= 30 THEN 'hoch' ELSE 'mittel' END
    FROM v_session_stats s
    WHERE s.avg_rest_sec IS NOT NULL

    UNION ALL
    -- Consistency.
    SELECT CASE WHEN k.workouts_per_week >= 2 THEN 'good' ELSE 'info' END,
           'Regelmäßigkeit',
           65,
           printf('Du hast im Schnitt %s-mal pro Woche trainiert. Aktuelle Serie: %d Woche%s.',
                  replace(printf('%.1f', k.workouts_per_week), '.', ','), k.current_streak, CASE WHEN k.current_streak = 1 THEN '' ELSE 'n' END),
           printf('%d von %d Wochen hatten mindestens ein Training. Die längste Serie in diesem Zeitraum: %d Woche%s.',
                  k.active_weeks, k.counted_weeks, k.longest_streak, CASE WHEN k.longest_streak = 1 THEN '' ELSE 'n' END),
           'ACSM Position Stand 2009: 2–3 Trainingstage pro Woche für Anfänger, 3–4 für Fortgeschrittene.',
           (SELECT week_confidence FROM v_ctx)
    FROM v_streaks k
    WHERE k.counted_weeks > 0 AND (SELECT work_sets FROM v_ctx) > 0

    UNION ALL
    -- Body-weight trend, in kg and in % per week.
    SELECT CASE WHEN w.rate_pct_week > 0.5 OR w.rate_pct_week < -1.0 THEN 'warn' ELSE 'info' END,
           'Körpergewicht', 70,
           printf('Körpergewicht (7-Tage-Schnitt) %s → %s kg, zuletzt %s kg pro Woche (%s %%).',
                  replace(printf('%.1f', w.first_avg), '.', ','), replace(printf('%.1f', w.last_avg), '.', ','),
                  replace(printf('%+.2f', w.rate_kg_week), '.', ','), replace(printf('%+.2f', w.rate_pct_week), '.', ',')),
           printf('Aus %d Einträgen, Veränderung des 7-Tage-Schnitts in den letzten 4 Wochen. Aufbau: etwa +0,25 bis +0,5 %% pro Woche hält den Fettzuwachs klein. Diät: etwa −0,5 bis −1 %% pro Woche erhält die Muskeln am besten.', w.entries),
           'Helms, Aragon & Fitschen 2014 (J Int Soc Sports Nutr), Empfehlungen für Wettkampf-Bodybuilder. Iraki et al. 2019 (Sports) zur Aufbauphase.',
           CASE WHEN w.entries >= 20 THEN 'hoch' ELSE 'mittel' END
    FROM v_bodyweight_stats w
    WHERE w.entries >= 5 AND w.rate_kg_week IS NOT NULL

    UNION ALL
    -- Waist against arm: the simplest sign whether weight gained is muscle or fat.
    SELECT 'info', 'Körpermaße', 72,
           printf('Taille %s cm, Oberarm %s cm seit %s.',
                  replace(printf('%+.1f', t.last_value - t.first_value), '.', ','),
                  replace(printf('%+.1f', a.last_value - a.first_value), '.', ','), strftime('%d.%m.%Y', t.first_day)),
           'Wächst der Oberarm und die Taille bleibt gleich, ist die Zunahme vor allem Muskel. Wächst die Taille deutlich schneller, eher Fett.',
           'Faustregel aus der Bodybuilding-Praxis.',
           CASE WHEN t.entries >= 4 THEN 'mittel' ELSE 'niedrig' END
    FROM v_measurement_stats t JOIN v_measurement_stats a ON a.id = 'arm_cm'
    WHERE t.id = 'waist_cm' AND t.entries >= 2 AND a.entries >= 2
)
ORDER BY rank, text;


-- =====================================================================
--  Charts page: everything else worth looking at. Like the other pages,
--  these views read cur_sets and cur_workouts, so the chosen range and the
--  exercise or muscle filter apply. (No semicolons in texts or comments:
--  Database.cpp cuts this file at every semicolon.)
-- =====================================================================

-- Workouts per weekday, Monday = 1 … Sunday = 7, all seven days.
DROP VIEW IF EXISTS v_chart_weekday;
CREATE VIEW v_chart_weekday AS
WITH RECURSIVE d(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM d WHERE n < 7),
     w AS (SELECT ((CAST(strftime('%w', day) AS INTEGER) + 6) % 7) + 1 AS n, duration_min, work_sets
           FROM cur_workouts)
SELECT d.n AS weekday,
       COUNT(w.n)                       AS workouts,
       COALESCE(AVG(w.duration_min), 0) AS avg_minutes,
       COALESCE(SUM(w.work_sets), 0)    AS sets
FROM d LEFT JOIN w ON w.n = d.n
GROUP BY d.n
ORDER BY d.n;

-- When workouts start (local time of the phone), every hour from the earliest to the latest.
DROP VIEW IF EXISTS v_chart_hours;
CREATE VIEW v_chart_hours AS
WITH RECURSIVE h AS (SELECT CAST(strftime('%H', w.started_at, printf('%+d minutes', w.utc_offset_min)) AS INTEGER) AS hour
                     FROM cur_workouts c JOIN workouts w ON w.id = c.workout_id),
     span AS (SELECT MIN(hour) AS lo, MAX(hour) AS hi FROM h),
     r(hour) AS (SELECT lo FROM span WHERE lo IS NOT NULL
                 UNION ALL SELECT r.hour + 1 FROM r, span WHERE r.hour < span.hi)
SELECT r.hour, (SELECT COUNT(*) FROM h WHERE h.hour = r.hour) AS workouts
FROM r
ORDER BY r.hour;

-- Workouts and kilograms added up from the start of the range.
DROP VIEW IF EXISTS v_chart_cumulative;
CREATE VIEW v_chart_cumulative AS
SELECT workout_id, name, day,
       COUNT(*) OVER (ORDER BY started_at, workout_id ROWS UNBOUNDED PRECEDING)       AS total,
       SUM(volume_kg) OVER (ORDER BY started_at, workout_id ROWS UNBOUNDED PRECEDING) AS total_kg
FROM cur_workouts
ORDER BY started_at, workout_id;

-- How long workouts take, in groups of 15 minutes.
DROP VIEW IF EXISTS v_chart_duration_bins;
CREATE VIEW v_chart_duration_bins AS
WITH b(n, label, lo, hi) AS (VALUES (1, 'unter 30', 0, 30), (2, '30–45', 30, 45), (3, '45–60', 45, 60),
                                    (4, '60–75', 60, 75), (5, '75–90', 75, 90), (6, '90+', 90, 100000))
SELECT b.n, b.label,
       (SELECT COUNT(*) FROM cur_workouts w WHERE w.duration_min >= b.lo AND w.duration_min < b.hi) AS workouts
FROM b
ORDER BY b.n;

-- One row per workout: kilograms, hard sets, and how dense it was.
DROP VIEW IF EXISTS v_chart_sessions;
CREATE VIEW v_chart_sessions AS
SELECT workout_id, name, day, started_at, duration_min, work_sets, volume_kg,
       CASE WHEN duration_min > 0 THEN volume_kg / duration_min END        AS kg_per_min,
       CASE WHEN duration_min > 0 THEN work_sets * 60.0 / duration_min END AS sets_per_hour
FROM cur_workouts
ORDER BY started_at;

-- Hard sets by rep range (timed exercises left out). share_pct adds up to 100.
DROP VIEW IF EXISTS v_chart_rep_ranges;
CREATE VIEW v_chart_rep_ranges AS
WITH b(n, label, lo, hi) AS (VALUES (1, '1–5', 1, 5), (2, '6–8', 6, 8), (3, '9–12', 9, 12),
                                    (4, '13–15', 13, 15), (5, '16–20', 16, 20), (6, '21+', 21, 100000)),
     s AS (SELECT c.eff_reps AS reps, c.hard
           FROM cur_sets c JOIN exercises x ON x.id = c.exercise_id
           WHERE c.hard > 0 AND COALESCE(x.unit, 'reps') = 'reps'),
     t AS (SELECT COALESCE(SUM(hard), 0) AS total FROM s),
     g AS (SELECT b.n, b.label, COALESCE((SELECT SUM(s.hard) FROM s WHERE s.reps BETWEEN b.lo AND b.hi), 0) AS sets FROM b)
SELECT g.n, g.label, g.sets,
       CASE WHEN t.total > 0 THEN g.sets * 100.0 / t.total ELSE 0 END AS share_pct
FROM g CROSS JOIN t
ORDER BY g.n;

-- How many sets of each kind (a drop or rest-pause set counts each of its parts).
DROP VIEW IF EXISTS v_chart_set_types;
CREATE VIEW v_chart_set_types AS
WITH t(n, type, label) AS (VALUES (1, 'work', 'Arbeitssätze'), (2, 'drop', 'Drop-Teile'),
                                  (3, 'restpause', 'Rest-Pause-Teile'), (4, 'warmup', 'Aufwärmsätze'))
SELECT t.n, t.type, t.label,
       (SELECT COUNT(*) FROM cur_sets c JOIN sets s ON s.id = c.set_id WHERE s.type = t.type) AS sets
FROM t
ORDER BY t.n;

-- Rests between working sets of the same exercise, grouped like a rest timer.
DROP VIEW IF EXISTS v_chart_rest_bins;
CREATE VIEW v_chart_rest_bins AS
WITH b(n, label, lo, hi) AS (VALUES (1, 'unter 1 min', 0, 60), (2, '1–1½ min', 60, 90), (3, '1½–2 min', 90, 120),
                                    (4, '2–3 min', 120, 180), (5, '3–4 min', 180, 240), (6, 'über 4 min', 240, 100000)),
     r AS (SELECT rest_sec FROM cur_sets
           WHERE first_of_exercise = 0 AND is_work = 1 AND prev_is_work = 1 AND rest_sec BETWEEN 5 AND 900)
SELECT b.n, b.label, (SELECT COUNT(*) FROM r WHERE r.rest_sec >= b.lo AND r.rest_sec < b.hi) AS rests
FROM b
ORDER BY b.n;

-- Hard sets per week by kind of movement.
DROP VIEW IF EXISTS v_chart_movement_week;
CREATE VIEW v_chart_movement_week AS
SELECT k.week_start, k.is_complete,
       COALESCE(SUM(CASE WHEN x.movement = 'push' THEN c.hard END), 0) AS push,
       COALESCE(SUM(CASE WHEN x.movement = 'pull' THEN c.hard END), 0) AS pull,
       COALESCE(SUM(CASE WHEN x.movement = 'legs' THEN c.hard END), 0) AS legs,
       COALESCE(SUM(CASE WHEN x.movement = 'core' THEN c.hard END), 0) AS core
FROM cur_weeks k
LEFT JOIN cur_sets c ON c.week_start = k.week_start
LEFT JOIN exercises x ON x.id = c.exercise_id
GROUP BY k.week_start
ORDER BY k.week_start;

-- Muscle sets (with the shares of secondary muscles) by body region.
DROP VIEW IF EXISTS v_chart_regions;
CREATE VIEW v_chart_regions AS
WITH r(n, region, label) AS (VALUES (1, 'upper', 'Oberkörper'), (2, 'lower', 'Beine'), (3, 'core', 'Rumpf'))
SELECT r.n, r.region, r.label,
       COALESCE((SELECT SUM(c.hard * em.weight) FROM cur_sets c
                 JOIN exercise_muscles em ON em.exercise_id = c.exercise_id
                 JOIN muscles m ON m.id = em.muscle_id
                 WHERE m.region = r.region), 0) AS sets
FROM r
ORDER BY r.n;

-- Every muscle, week by week (the grid of the Charts page).
DROP VIEW IF EXISTS v_chart_muscle_matrix;
CREATE VIEW v_chart_muscle_matrix AS
SELECT w.muscle_id, m.name, m.sort_order, m.target_min, m.target_max, w.week_start, w.is_complete, w.sets
FROM v_muscle_week w
JOIN muscles m ON m.id = w.muscle_id
WHERE (SELECT muscle_id FROM state) IS NULL OR w.muscle_id = (SELECT muscle_id FROM state)
ORDER BY m.sort_order, w.week_start;

-- Progress per exercise: the best set of each session as a strength score
-- (the estimated 1RM, for isolation exercises the same Epley formula), the
-- first two sessions of the range against the last two. At least 3 sessions.
-- Only exercises with a weight you add (not body-weight or assisted ones:
-- there a change of body weight would look like progress).
DROP VIEW IF EXISTS v_chart_progress;
CREATE VIEW v_chart_progress AS
WITH s AS (SELECT c.exercise_id, c.workout_id, MIN(c.day) AS day,
                  MAX(COALESCE(c.e1rm, c.strength_kg * (1 + c.eff_reps / 30.0))) AS score
           FROM cur_sets c JOIN exercises x ON x.id = c.exercise_id
           WHERE c.is_work = 1 AND COALESCE(x.unit, 'reps') = 'reps' AND x.load_type = 'external'
             AND c.strength_kg > 0 AND c.eff_reps > 0
           GROUP BY c.exercise_id, c.workout_id),
     r AS (SELECT exercise_id, day, score,
                  ROW_NUMBER() OVER (PARTITION BY exercise_id ORDER BY day, workout_id) AS rn,
                  COUNT(*) OVER (PARTITION BY exercise_id)                         AS n
           FROM s),
     a AS (SELECT exercise_id, MAX(n) AS sessions, MIN(day) AS first_day, MAX(day) AS last_day,
                  AVG(CASE WHEN rn <= 2 THEN score END)    AS first_score,
                  AVG(CASE WHEN rn > n - 2 THEN score END) AS last_score
           FROM r GROUP BY exercise_id)
SELECT x.id AS exercise_id, x.name, a.sessions, a.first_day, a.last_day, a.first_score, a.last_score,
       (a.last_score / a.first_score - 1) * 100 AS change_pct
FROM a JOIN exercises x ON x.id = a.exercise_id
WHERE a.sessions >= 3 AND a.first_score > 0
ORDER BY change_pct DESC, x.name;

-- The exercises with the most hard sets.
DROP VIEW IF EXISTS v_chart_top_exercises;
CREATE VIEW v_chart_top_exercises AS
SELECT x.id AS exercise_id, x.name, SUM(c.hard) AS sets, COUNT(DISTINCT c.workout_id) AS sessions,
       COALESCE(SUM(c.volume_kg), 0) AS volume_kg
FROM cur_sets c JOIN exercises x ON x.id = c.exercise_id
GROUP BY x.id
HAVING SUM(c.hard) > 0
ORDER BY sets DESC, x.name
LIMIT 15;

-- Records per month, every month of the range: a new best strength score
-- of an exercise with added weight (against ALL earlier sessions, also before
-- the range) and a volume record (gold).
DROP VIEW IF EXISTS v_chart_prs_month;
CREATE VIEW v_chart_prs_month AS
WITH RECURSIVE s AS (SELECT f.exercise_id, f.workout_id, MIN(f.day) AS day,
                            MAX(COALESCE(f.e1rm_epley, f.strength_kg * (1 + f.eff_reps / 30.0))) AS score
                     FROM set_facts f JOIN exercises x ON x.id = f.exercise_id
                     WHERE f.is_work = 1 AND COALESCE(x.unit, 'reps') = 'reps' AND x.load_type = 'external'
                       AND f.strength_kg > 0 AND f.eff_reps > 0
                     GROUP BY f.exercise_id, f.workout_id),
     p AS (SELECT exercise_id, workout_id, day, score,
                  MAX(score) OVER (PARTITION BY exercise_id ORDER BY day, workout_id
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS before_best
           FROM s),
     ev AS (SELECT substr(p.day, 1, 7) AS month, 'strength' AS kind FROM p
            WHERE p.before_best IS NOT NULL AND p.score > p.before_best + 0.001
              AND p.workout_id IN (SELECT workout_id FROM cur_workouts)
              AND p.exercise_id IN (SELECT exercise_id FROM cur_sets)
            UNION ALL
            SELECT substr(e.day, 1, 7), 'volume' FROM exercise_session_facts e
            WHERE e.is_volume_pr = 1
              AND e.workout_id IN (SELECT workout_id FROM cur_workouts)
              AND e.exercise_id IN (SELECT exercise_id FROM cur_sets)),
     span AS (SELECT substr(MIN(day), 1, 7) || '-01' AS lo, substr(MAX(day), 1, 7) || '-01' AS hi FROM cur_workouts),
     m(month_start) AS (SELECT lo FROM span WHERE lo IS NOT NULL
                        UNION ALL SELECT date(m.month_start, '+1 month') FROM m, span WHERE m.month_start < span.hi)
SELECT m.month_start,
       (SELECT COUNT(*) FROM ev WHERE ev.month = substr(m.month_start, 1, 7) AND ev.kind = 'strength') AS strength_prs,
       (SELECT COUNT(*) FROM ev WHERE ev.month = substr(m.month_start, 1, 7) AND ev.kind = 'volume')   AS volume_prs
FROM m
ORDER BY m.month_start;
