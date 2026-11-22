"""
check_analyzer.py - run the analyzer's SQL without Qt.

    python tools/check_analyzer.py shared/sample-data.json
    python tools/check_analyzer.py shared/sample-data.json shared/sample-data-incremental.json

It builds a database in memory from analyzer/sql/*.sql, imports the given
export files the same way the Windows app does, and prints what the charts
and the Insights page would show. Handy for trying out a change to a view or
an insight rule: edit the .sql file, run this, read the result.

The functions here mirror the C++ code on purpose:
    split_statements / load_blocks / run_block   ->  analyzer/src/Database.cpp
    import_data                                  ->  analyzer/src/Importer.cpp
"""

import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "analyzer" / "sql"
SCHEMA_VERSION = 1
PLACEHOLDER = re.compile(r":([a-z_]+)")


def split_statements(script):
    """Remove '-- comments', then cut the text at every semicolon."""
    clean = "\n".join(line.split("--")[0] for line in script.split("\n"))
    return [part.strip() for part in clean.split(";") if part.strip()]


def load_blocks(script):
    """statements.sql -> {"block name": [statement, statement, ...]}"""
    blocks, name, lines = {}, None, []
    for line in script.split("\n") + ["-- name: (end)"]:
        if line.strip().startswith("-- name:"):
            if name:
                blocks[name] = split_statements("\n".join(lines))
            name, lines = line.split(":", 1)[1].strip(), []
        else:
            lines.append(line)
    return blocks


class Database:
    def __init__(self, path=":memory:"):
        self.con = sqlite3.connect(path)
        self.con.row_factory = sqlite3.Row
        for file_name in ("schema.sql", "derived.sql"):
            for statement in split_statements((SQL_DIR / file_name).read_text(encoding="utf-8")):
                self.con.execute(statement)
        self.blocks = load_blocks((SQL_DIR / "statements.sql").read_text(encoding="utf-8"))
        self.run_block("refresh")
        self.run_block("apply_filter")

    def execute(self, sql, params=None):
        """Bind exactly the :placeholders that occur in the statement (missing ones become NULL)."""
        params = params or {}
        names = set(PLACEHOLDER.findall(sql))
        return self.con.execute(sql, {name: params.get(name) for name in names})

    def run_block(self, name, params=None):
        for statement in self.blocks[name]:
            self.execute(statement, params)

    def rows(self, view):
        return [dict(row) for row in self.con.execute(f"SELECT * FROM {view}")]

    def row(self, view):
        rows = self.rows(view)
        return rows[0] if rows else {}

    def set_state(self, key, value):
        self.execute(f"UPDATE state SET {key} = :value", {"value": value})
        self.run_block("apply_filter")

    def set_preset(self, preset):
        weeks = {"4w": 4, "8w": 8, "12w": 12, "26w": 26, "52w": 52}.get(preset)
        if weeks:
            self.run_block("range_last_days", {"days": weeks * 7 - 1})
        elif preset == "all":
            self.run_block("range_all")
        # any other value ("custom") keeps from_day and to_day as they are
        self.execute("UPDATE state SET range_preset = :value", {"value": preset})
        self.run_block("apply_filter")


def needs_write(db, table, record, counts):
    """The merge rule: unknown id -> add, newer updatedAt -> replace, otherwise keep ours."""
    row = db.execute(f"SELECT updated_at FROM {table} WHERE id = :id", {"id": record["id"]}).fetchone()
    if row is None:
        counts["added"] += 1
        return True
    if record["updatedAt"] > row["updated_at"]:
        counts["updated"] += 1
        return True
    counts["unchanged"] += 1
    return False


def raw(record):
    return json.dumps(record, separators=(",", ":"))



def current_muscle(muscle_id):
    """Like currentMuscleId() in Importer.cpp: "forearms" of older files means the forearm flexors."""
    return "forearm_flexors" if muscle_id == "forearms" else muscle_id

def store_exercise(db, o):
    db.run_block("upsert_exercise", {
        "id": o["id"], "name": o["name"], "movement": o.get("movement"), "equipment": o.get("equipment"),
        "load_type": o.get("loadType", "external"), "bodyweight_fraction": o.get("bodyweightFraction"),
        "compound": 0 if o.get("compound") is False else 1, "load_mode": o.get("load", "total"), "unit": o.get("unit", "reps"),
        "is_custom": 1 if o.get("isCustom") else 0, "updated_at": o["updatedAt"], "deleted_at": o.get("deletedAt"),
        "raw_json": raw(o)})
    db.run_block("clear_exercise_muscles", {"id": o["id"]})
    shares = o.get("muscleShares", {})
    for muscle in o.get("secondaryMuscles", []):
        db.run_block("insert_exercise_muscle", {"exercise_id": o["id"], "muscle_id": current_muscle(muscle), "role": "secondary",
                                                "weight": shares.get(muscle, 0.5)})
    for muscle in o.get("primaryMuscles", []):      # written last, so primary wins if a muscle is in both lists
        db.run_block("insert_exercise_muscle", {"exercise_id": o["id"], "muscle_id": current_muscle(muscle), "role": "primary", "weight": 1.0})


def store_workout(db, o):
    db.run_block("clear_workout", {"id": o["id"]})
    db.run_block("upsert_workout", {
        "id": o["id"], "name": o.get("name"), "started_at": o["startedAt"], "finished_at": o.get("finishedAt"),
        "utc_offset_min": o.get("utcOffsetMin", 0), "notes": o.get("notes"), "updated_at": o["updatedAt"],
        "deleted_at": o.get("deletedAt"), "raw_json": raw(o)})
    for entry in o.get("exercises", []):
        db.run_block("insert_entry", {
            "id": entry["id"], "workout_id": o["id"], "exercise_id": entry["exerciseId"],
            "sort_order": entry.get("order", 0), "notes": entry.get("notes"), "superset_group": entry.get("supersetGroup"),
            "target_reps_min": entry.get("targetRepsMin"), "target_reps_max": entry.get("targetRepsMax")})
        for s in entry.get("sets", []):
            db.run_block("insert_set", {
                "id": s["id"], "workout_id": o["id"], "entry_id": entry["id"], "sort_order": s.get("order", 0),
                "type": s.get("type", "work"), "weight_kg": s["weightKg"], "reps": s["reps"], "rpe": s.get("rpe"),
                "reps_left": s.get("repsLeft"), "partials": s.get("partials"),
                "started_at": s.get("startedAt"), "completed_at": s.get("completedAt"),
                "target_rest_sec": s.get("targetRestSec")})


def import_data(db, data, file_name="(memory)"):
    """Merge one export file into the database. Returns {"added", "updated", "unchanged"}."""
    if not isinstance(data, dict) or data.get("app") != "workout-tracker":
        raise ValueError("Das ist keine Export-Datei der Trainings-App.")
    if data.get("schemaVersion", 0) > SCHEMA_VERSION:
        raise ValueError("This file was written by a newer app version.")
    counts = {"added": 0, "updated": 0, "unchanged": 0}
    for o in data["exercises"]:
        if needs_write(db, "exercises", o, counts):
            store_exercise(db, o)
    for o in data["templates"]:
        if needs_write(db, "templates", o, counts):
            db.run_block("upsert_template", {"id": o["id"], "name": o.get("name"), "updated_at": o["updatedAt"],
                                             "deleted_at": o.get("deletedAt"), "raw_json": raw(o)})
    for o in data["workouts"]:
        if needs_write(db, "workouts", o, counts):
            store_workout(db, o)
    for o in data["bodyWeights"]:
        if needs_write(db, "body_weights", o, counts):
            db.run_block("upsert_body_weight", {"id": o["id"], "measured_at": o["measuredAt"], "weight_kg": o["weightKg"],
                                                "updated_at": o["updatedAt"], "deleted_at": o.get("deletedAt"), "raw_json": raw(o)})
    for o in data.get("measurements", []):
        if needs_write(db, "measurements", o, counts):
            db.run_block("upsert_measurement", {
                "id": o["id"], "measured_at": o["measuredAt"], "waist_cm": o.get("waistCm"), "chest_cm": o.get("chestCm"),
                "arm_cm": o.get("armCm"), "thigh_cm": o.get("thighCm"), "calf_cm": o.get("calfCm"),
                "body_fat_pct": o.get("bodyFatPct"), "updated_at": o["updatedAt"], "deleted_at": o.get("deletedAt"),
                "raw_json": raw(o)})
    db.run_block("save_meta", {"key": "settings", "value": raw(data.get("settings", {}))})
    db.run_block("note_export", {"exported_at": data["exportedAt"]})
    db.run_block("log_import", {"imported_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()), "file_name": file_name,
                                "exported_at": data["exportedAt"], "export_type": data.get("exportType"), **counts})
    db.con.commit()
    db.run_block("refresh")
    db.set_preset(db.row("v_state")["range_preset"])     # move the date range forward to the new data
    return counts


def report(db):
    state, totals = db.row("v_state"), db.row("v_totals")
    print(f"\nRange: {state['from_day'] or 'start'} to {state['end_day']}   (data known until {state['known_until']})")
    print(f"Workouts {totals['workouts']}, hard sets {totals['work_sets']}, volume {totals['volume_kg']:.0f} kg, "
          f"average duration {totals['avg_duration_min']:.0f} min, {totals['counted_weeks']} weeks averaged")
    print("\nWeek        sets  volume kg  workouts")
    for w in db.rows("v_weekly"):
        print(f"{w['week_start']}  {w['sets']:4.0f}  {w['volume_kg']:9.0f}  {w['workouts']:8}{'' if w['is_complete'] else '   (running week)'}")
    print("\nMuscle                  sets/week  sessions/week  target   status")
    for m in db.rows("v_muscles"):
        print(f"{m['name']:<22}  {m['sets_per_week']:9.1f}  {m['sessions_per_week']:13.1f}  {m['target_min']:>3g}–{m['target_max']:<3g}  {m['status']}")
    print("\nNext week")
    for n in db.rows("v_next_week"):
        print(f"  {n['text']}  ({n['detail']})")
    print("\nInsights")
    for i in db.rows("v_insights"):
        print(f"  [{i['severity']:<4}] [{i['confidence']:<7}] {i['topic']:<14} {i['text']}")


if __name__ == "__main__":
    os.environ.setdefault("TZ", "Europe/Vienna")
    if hasattr(time, "tzset"):
        time.tzset()
    files = sys.argv[1:] or [str(ROOT / "shared" / "sample-data.json")]
    database = Database()
    for name in files:
        result = import_data(database, json.loads(Path(name).read_text(encoding="utf-8")), Path(name).name)
        print(f"{Path(name).name}: {result['added']} added, {result['updated']} updated, {result['unchanged']} already up to date")
    report(database)
