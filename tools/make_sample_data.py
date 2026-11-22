"""
make_sample_data.py - writes fake but realistic workout data for testing.

    python tools/make_sample_data.py

Creates two files in shared/:
  sample-data.json              full export: 8 weeks, 4 workouts per week
  sample-data-incremental.json  a later "only new data" export: one new workout,
                                one edited old workout, one new body weight.
                                Import it AFTER the full file to test merging.

The data is built so that the Windows app has something to say:
  - hamstrings get only 4 sets per week (below the 10-set minimum)
  - lats get more than 20 sets per week (very high)
  - bench press estimated 1RM rises about 6 % over the last 4 weeks
  - squat has not progressed for the last 3 weeks
  - two workouts were skipped, so the streak and the calendar are not perfect

Everything is random but repeatable: the same seed always gives the same file.
"""

import datetime as dt
import json
import random
import uuid
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
VIENNA = ZoneInfo("Europe/Vienna")          # switches from UTC+2 to UTC+1 on 25 Oct 2026
rng = random.Random(42)

FIRST_MONDAY = dt.date(2026, 9, 21)
WEEKS = 8


def new_id():
    """A random-looking but repeatable UUID."""
    return str(uuid.UUID(int=rng.getrandbits(128), version=4))


def iso(moment):
    """datetime -> '2026-11-10T17:02:11.000Z' (always UTC, like the phone app writes it)."""
    utc = moment.astimezone(dt.timezone.utc)
    return utc.strftime("%Y-%m-%dT%H:%M:%S.") + f"{utc.microsecond // 1000:03d}Z"


def local(day, hour, minute=0):
    return dt.datetime.combine(day, dt.time(hour, minute), tzinfo=VIENNA)


# ---------------------------------------------------------------------------
# The training plan. Each line: exercise id, working sets, reps of the first
# set, start weight (kg), kg added every 2 weeks, rest (s), warm-up sets.
# ---------------------------------------------------------------------------
CUSTOM_ID = new_id()   # a custom exercise, to test that the Windows app understands it

PLAN = {
    "Push Day": [
        ("barbell-bench-press", 3, 8, 60, 0, 180, [(40, 10)]),          # weights come from BENCH below
        ("incline-dumbbell-press", 3, 10, 22, 1, 150, []),
        ("cable-fly", 2, 12, 15, 1.25, 90, []),
        ("overhead-press", 3, 8, 37.5, 1.25, 150, []),
        ("dumbbell-lateral-raise", 3, 14, 8, 0.5, 75, []),
        ("triceps-pushdown", 3, 12, 25, 1.25, 90, []),
    ],
    "Pull Day": [
        ("lat-pulldown", 4, 10, 55, 2.5, 120, []),
        ("barbell-row", 4, 8, 55, 2.5, 150, []),
        ("seated-cable-row", 4, 10, 50, 2.5, 120, []),
        ("straight-arm-pulldown", 3, 12, 22.5, 1.25, 90, []),
        ("face-pull", 2, 15, 17.5, 1.25, 75, []),
        ("barbell-curl", 3, 10, 27.5, 1.25, 90, []),
        ("hammer-curl", 2, 12, 12, 1, 75, []),
    ],
    "Leg Day": [
        ("back-squat", 3, 8, 80, 0, 210, [(50, 8), (70, 5)]),           # weights come from SQUAT below
        ("leg-press", 3, 10, 140, 5, 180, []),
        ("leg-extension", 4, 12, 45, 2.5, 90, []),
        ("lying-leg-curl", 3, 12, 35, 1.25, 90, []),
        ("back-extension", 2, 15, 0, 0, 75, []),
        ("standing-calf-raise", 2, 12, 60, 2.5, 75, []),
    ],
    "Upper Body": [
        ("dumbbell-bench-press", 3, 10, 24, 1, 150, []),
        ("pull-up", 4, 7, 0, 0, 150, []),
        ("dumbbell-shoulder-press", 2, 10, 18, 1, 120, []),
        ("machine-row", 4, 10, 50, 2.5, 120, []),
        ("dumbbell-curl", 2, 12, 11, 0.5, 75, []),
        ("overhead-triceps-extension", 2, 12, 20, 1.25, 75, []),
    ],
}

# weekday (0 = Monday) -> workout name, usual start hour
SCHEDULE = {0: ("Push Day", 17), 1: ("Pull Day", 17), 3: ("Leg Day", 18), 5: ("Upper Body", 10)}
SKIPPED = {(2, 5), (5, 1)}                      # (week, weekday) sessions that were missed

# Hand-written progress for the two "story" lifts: one (weight, reps per set) per week.
BENCH = [(60, [8, 8, 7]), (60, [8, 8, 8]), (62.5, [7, 7, 6]), (62.5, [8, 7, 7]),
         (62.5, [8, 8, 7]), (65, [7, 7, 6]), (65, [8, 8, 7]), (70, [6, 6, 5])]
SQUAT = [(80, [8, 8, 7]), (82.5, [8, 7, 7]), (85, [8, 7, 6]), (87.5, [7, 7, 6]),
         (90, [6, 6, 5]), (90, [6, 6, 5]), (90, [6, 5, 5]), (90, [6, 6, 5])]


def planned_sets(exercise_id, week, sets, first_reps, start, step):
    """The working sets of one exercise in one week: a list of (weight, reps)."""
    if exercise_id == "barbell-bench-press":
        weight, reps = BENCH[week]
        return [(weight, r) for r in reps]
    if exercise_id == "back-squat":
        weight, reps = SQUAT[week]
        return [(weight, r) for r in reps]
    if exercise_id == "pull-up":                     # body weight: more reps over time
        top = first_reps + week // 3
        return [(0, max(3, top - i)) for i in range(sets)]
    weight = start + step * (week // 2)
    # In the second week on a weight you usually get one more rep.
    top = first_reps + (week % 2)
    return [(weight, max(4, top - (i + 1) // 2 - rng.choice([0, 0, 1]))) for i in range(sets)]


def make_workout(name, template_id, start, week, extra=None):
    """Simulate one workout, set by set, with realistic clock times."""
    clock = start
    workout = {
        "id": new_id(), "name": name, "templateId": template_id,
        "startedAt": iso(start), "finishedAt": None,
        "utcOffsetMin": int(start.utcoffset().total_seconds() // 60),
        "notes": "", "updatedAt": None, "deletedAt": None, "exercises": [],
    }
    plan = list(PLAN[name]) + (extra or [])
    for order, (exercise_id, sets, reps, start_kg, step, rest, warmups) in enumerate(plan):
        clock += dt.timedelta(seconds=rng.randint(120, 260))        # walk over, set up
        entry = {"id": new_id(), "exerciseId": exercise_id, "order": order, "notes": "", "sets": []}
        todo = [("warmup", w, r) for w, r in warmups]
        todo += [("work", w, r) for w, r in planned_sets(exercise_id, week, sets, reps, start_kg, step)]
        for index, (kind, weight, set_reps) in enumerate(todo):
            started = clock
            clock += dt.timedelta(seconds=rng.randint(22, 34) + 2 * set_reps)
            # The app no longer asks for effort (RPE), so it is always empty. The two random
            # draws stay, so the rest of the random data comes out exactly as before.
            if kind == "work" and rng.random() < 0.75:
                rng.choice([0, 0.5, 1])
            entry["sets"].append({
                "id": new_id(), "order": index, "type": kind,
                "weightKg": weight, "reps": set_reps, "rpe": None,
                # About one set in seven: "Start set" was not tapped.
                "startedAt": iso(started) if rng.random() > 0.15 else None,
                "completedAt": iso(clock),
                "targetRestSec": 60 if kind == "warmup" else rest,
            })
            actual_rest = (60 if kind == "warmup" else rest) + rng.randint(-10, 45)
            if index < len(todo) - 1:
                clock += dt.timedelta(seconds=actual_rest)
        workout["exercises"].append(entry)
    clock += dt.timedelta(seconds=rng.randint(60, 200))
    workout["finishedAt"] = iso(clock)
    workout["updatedAt"] = iso(clock)
    return workout


def main():
    # The fake workouts use a fixed list of test exercises (tools/test-library.json), so
    # the sample data does not change when the real library in shared/ changes.
    library = json.loads((ROOT / "tools" / "test-library.json").read_text(encoding="utf-8"))
    exercises = [dict(e, isCustom=False, updatedAt=library["updatedAt"], deletedAt=None)
                 for e in library["exercises"]]
    exercises.append({
        "id": CUSTOM_ID, "name": "Landmine Press",
        "primaryMuscles": ["front_delts"], "secondaryMuscles": ["chest", "triceps"],
        "movement": "push", "equipment": "barbell", "loadType": "external",
        "isCustom": True, "updatedAt": iso(local(FIRST_MONDAY, 16, 40)), "deletedAt": None,
    })

    templates = []
    for name, plan in PLAN.items():
        templates.append({
            "id": new_id(), "name": name,
            # Heavy lifts (8 reps or fewer) get a fixed rep target, everything else a range.
            "items": [{"exerciseId": e[0], "targetSets": e[1], "restSec": e[5],
                       "repsMin": e[2], "repsMax": e[2] if e[2] <= 8 else e[2] + 4} for e in plan],
            "updatedAt": iso(local(FIRST_MONDAY, 16, 30)), "deletedAt": None,
        })
    template_ids = {t["name"]: t["id"] for t in templates}

    workouts = []
    for week in range(WEEKS):
        for weekday, (name, hour) in SCHEDULE.items():
            if (week, weekday) in SKIPPED:
                continue
            day = FIRST_MONDAY + dt.timedelta(weeks=week, days=weekday)
            start = local(day, hour, 30) + dt.timedelta(minutes=rng.randint(-40, 40))
            # Every second week the custom exercise is added to the upper-body day.
            extra = [(CUSTOM_ID, 2, 10, 25, 2.5, 120, [])] if name == "Upper Body" and week % 2 == 0 else None
            workouts.append(make_workout(name, template_ids[name], start, week, extra))
    workouts[5]["notes"] = "Slept badly, felt heavy."
    workouts[-1]["exercises"][0]["notes"] = "Elbows tucked felt better."

    # One workout that was started by accident and deleted again (a "tombstone").
    oops_start = local(FIRST_MONDAY + dt.timedelta(weeks=4, days=2), 12, 5)
    oops = make_workout("Push Day", template_ids["Push Day"], oops_start, 4)
    oops["exercises"] = oops["exercises"][:1]
    oops["exercises"][0]["sets"] = oops["exercises"][0]["sets"][:1]
    oops["finishedAt"] = iso(oops_start + dt.timedelta(minutes=4))
    oops["deletedAt"] = oops["updatedAt"] = iso(oops_start + dt.timedelta(minutes=6))
    workouts.append(oops)
    workouts.sort(key=lambda w: w["startedAt"])

    # Body weight: most mornings, slowly going down, with day-to-day noise.
    body_weights = []
    for offset in range(WEEKS * 7):
        if rng.random() > 0.7:
            continue
        moment = local(FIRST_MONDAY + dt.timedelta(days=offset), 7, 10) + dt.timedelta(minutes=rng.randint(-20, 25))
        weight = 78.6 - 0.025 * offset + rng.uniform(-0.4, 0.4)
        body_weights.append({"id": new_id(), "measuredAt": iso(moment), "weightKg": round(weight, 1),
                             "updatedAt": iso(moment), "deletedAt": None})

    # Body measurements: every second Sunday. A separate random generator, so the
    # numbers above stay exactly the same as in earlier versions of this file.
    mrng = random.Random(77)
    measurements = []
    for week in range(1, WEEKS, 2):
        moment = local(FIRST_MONDAY + dt.timedelta(weeks=week, days=6), 8, 0)
        measurements.append({
            "id": str(uuid.UUID(int=mrng.getrandbits(128), version=4)), "measuredAt": iso(moment),
            "waistCm": round(84.0 - 0.3 * week + mrng.uniform(-0.3, 0.3), 1),
            "chestCm": round(104.0 + mrng.uniform(-0.4, 0.4), 1),
            "armCm": round(37.2 + 0.05 * week + mrng.uniform(-0.2, 0.2), 1),
            "thighCm": round(59.0 + mrng.uniform(-0.3, 0.3), 1),
            "calfCm": None,
            "bodyFatPct": round(16.5 - 0.2 * week, 1),
            "updatedAt": iso(moment), "deletedAt": None,
        })

    settings = {"unit": "kg", "defaultRestSec": 120, "soundOn": True, "keepScreenOn": True,
                "effortScale": "rpe", "theme": "auto", "soundInSilentMode": False}
    last_sunday = FIRST_MONDAY + dt.timedelta(weeks=WEEKS, days=-1)
    exported_at = iso(local(last_sunday, 20, 0))

    full = {
        "schemaVersion": 1, "app": "workout-tracker", "exportedAt": exported_at,
        "exportType": "full", "changedSince": None, "settings": settings,
        "exercises": exercises, "templates": templates, "workouts": workouts, "bodyWeights": body_weights,
        "measurements": measurements,
    }
    (ROOT / "shared" / "sample-data.json").write_text(json.dumps(full, indent=1), encoding="utf-8")

    # ----- The later, incremental export -----
    monday = last_sunday + dt.timedelta(days=1)
    new_workout = make_workout("Push Day", template_ids["Push Day"], local(monday, 17, 20), WEEKS - 1)
    edited = json.loads(json.dumps(workouts[-1]))            # a copy of the last workout…
    edited["notes"] = "Edited on the phone after the first export."
    edited["updatedAt"] = iso(local(monday, 8, 0))           # …with a newer updatedAt
    morning = local(monday, 7, 5)
    new_weight = {"id": new_id(), "measuredAt": iso(morning), "weightKg": 77.1,
                  "updatedAt": iso(morning), "deletedAt": None}
    incremental = {
        "schemaVersion": 1, "app": "workout-tracker", "exportedAt": iso(local(monday, 19, 0)),
        "exportType": "incremental", "changedSince": exported_at, "settings": settings,
        "exercises": exercises, "templates": templates,
        "workouts": [edited, new_workout], "bodyWeights": [new_weight], "measurements": [],
    }
    (ROOT / "shared" / "sample-data-incremental.json").write_text(json.dumps(incremental, indent=1), encoding="utf-8")

    real = [w for w in workouts if not w["deletedAt"]]
    print(f"sample-data.json: {len(real)} workouts (+1 deleted), "
          f"{sum(len(e['sets']) for w in real for e in w['exercises'])} sets, {len(body_weights)} body weights")
    print("sample-data-incremental.json: 1 edited workout, 1 new workout, 1 new body weight")


if __name__ == "__main__":
    main()
