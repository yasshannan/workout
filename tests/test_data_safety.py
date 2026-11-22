"""Updates never lose data. Run before every release:

    pip install playwright && playwright install chromium     (once)
    python tests/test_data_safety.py

1. The rules in the code: the phone database only grows, the version numbers match.
2. Every saved database in tests/fixtures/ (one per release that changed how data
   is stored) is opened by the newest app: not a single record may be lost or
   changed, and a copy of everything is made before the update.
3. An older database version is upgraded without loss; an older app on a newer
   database refuses to start but leaves the data alone.
4. If an update loses something, Settings → "Fehlende Daten zurückholen" brings it back.
"""
import copy, json, re, sys
from playwright.sync_api import sync_playwright, expect
from browser_db import ROOT, start_server, launch, dump, write

PHONE = ROOT / "phone"
problems = []

# ---------- 1. rules in the code ----------
db_js = (PHONE / "js/db.js").read_text(encoding="utf-8")
code_only = re.sub(r"//.*", "", db_js)
for forbidden in ("deleteObjectStore", "deleteIndex", ".clear(", "deleteDatabase"):
    if forbidden in code_only:
        problems.append(f"db.js uses {forbidden}: the database may only grow")
for path in PHONE.glob("js/**/*.js"):
    if "deleteDatabase" in re.sub(r"//.*", "", path.read_text(encoding="utf-8")):
        problems.append(f"{path.name} deletes the database")
sw = (PHONE / "sw.js").read_text(encoding="utf-8")
if "indexedDB" in re.sub(r"//.*", "", sw):
    problems.append("sw.js touches the database: updating the files must never do that")
version = re.search(r"APP_VERSION = '([\d.]+)'", (PHONE / "js/version.js").read_text()).group(1)
if f"APP_VERSION = '{version}'" not in sw:
    problems.append("APP_VERSION in sw.js and js/version.js differ")
db_version = int(re.search(r"const DB_VERSION = (\d+);", db_js).group(1))
for step in range(1, db_version + 1):
    if not re.search(rf"^\s+{step}: \(database, has\) =>", db_js, re.M):
        problems.append(f"db.js has no migration step {step}")

fixtures = sorted((ROOT / "tests/fixtures").glob("phone-db-*.json"))
assert fixtures, "no saved databases in tests/fixtures"


def by_key(store):
    return {r[store["keyPath"]]: r for r in store["records"]}


def keeps(old, new, path):
    """new must hold every field of old with the same value (new fields are fine)."""
    if isinstance(old, dict):
        if not isinstance(new, dict):
            problems.append(f"{path}: changed from an object"); return
        for key, value in old.items():
            if key not in new:
                problems.append(f"{path}.{key}: missing")
            else:
                keeps(value, new[key], f"{path}.{key}")
    elif old != new:
        problems.append(f"{path}: {str(old)[:60]} → {str(new)[:60]}")


def compare(before, after, label):
    for name, store in before["stores"].items():
        if name not in after["stores"]:
            problems.append(f"{label}: store {name} is gone"); continue
        now = by_key(after["stores"][name])
        for key, record in by_key(store).items():
            if key not in now:
                problems.append(f"{label}: {name}/{key} is gone"); continue
            if name == "exercises" and not record.get("isCustom"):
                continue                     # built-in exercises follow the library (and stay, at worst hidden)
            if name == "meta" and key == "appVersion":
                continue
            if name == "meta" and key == "active":
                # the running workout's live state (rest timer, open card) moves on by itself;
                # what must stay is WHICH workout is running
                keeps({"workoutId": (record["value"] or {}).get("workoutId")}, now[key]["value"] or {}, f"{label}: meta/active")
                continue
            keeps(record, now[key], f"{label}: {name}/{key}")


BASE_URL = start_server()
APP = BASE_URL + "phone/"
BLANK = BASE_URL + "tests/fixtures/"        # same address as the app, without starting it


def started(page):
    """Open the app and wait until a screen is drawn."""
    page.goto(APP)
    page.wait_for_function("document.querySelector('#screen') && document.querySelector('#screen').children.length > 0")
    page.wait_for_timeout(600)


with sync_playwright() as p:
    browser = launch(p)

    for fixture_path in fixtures:
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        label = fixture_path.stem
        before = {"dbVersion": fixture["dbVersion"], "stores": copy.deepcopy(fixture["stores"])}
        meta = before["stores"]["meta"]["records"]
        if any(r["key"] == "appVersion" and r["value"] == version for r in meta):
            before["stores"]["meta"]["records"] = [r for r in meta if r["key"] != "appVersion"]   # as if from before

        # ---------- 2. the newest app on this saved database ----------
        ctx = browser.new_context(viewport={"width": 393, "height": 798}, is_mobile=True, has_touch=True, accept_downloads=True)
        page = ctx.new_page()
        page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
        page.goto(BLANK)
        write(page, before)
        started(page)
        after = dump(page)
        compare(before, after, label)
        backup = by_key(after["stores"]["meta"]).get("updateBackup")
        if not backup:
            problems.append(f"{label}: no copy was made before the update")
        else:
            copied = {name: len(records) for name, records in backup["value"]["stores"].items()}
            for name, store in before["stores"].items():
                expected = len([r for r in store["records"] if name != "meta" or r["key"] not in ("lastExportFile", "updateBackup")])
                if copied.get(name, 0) < expected:
                    problems.append(f"{label}: the copy holds {copied.get(name, 0)} of {expected} {name}")
            if backup["value"]["toVersion"] != version:
                problems.append(f"{label}: copy is not marked for version {version}")
        if by_key(after["stores"]["meta"]).get("appVersion", {}).get("value") != version:
            problems.append(f"{label}: the app did not note its version")

        # ---------- 4. a buggy update lost a workout and a template: bring them back ----------
        lost_workout = before["stores"]["workouts"]["records"][0]["id"]
        lost_template = before["stores"]["templates"]["records"][0]["id"]
        page.evaluate("""async ([w, t]) => {
          const db = await new Promise((ok) => { const r = indexedDB.open('workout-tracker'); r.onsuccess = () => ok(r.result); });
          await new Promise((ok) => { const tx = db.transaction(['workouts', 'templates'], 'readwrite');
            tx.objectStore('workouts').delete(w); tx.objectStore('templates').delete(t); tx.oncomplete = ok; });
          db.close();
        }""", [lost_workout, lost_template])
        page.goto(APP + "#/settings")
        page.get_by_role("button", name="Fehlende Daten zurückholen").click()
        page.locator(".sheet").get_by_role("button", name="Zurückholen").click()
        expect(page.locator(".toast")).to_contain_text("2 Einträge zurückgeholt")
        page.wait_for_timeout(1500)                                  # the app reads everything again
        compare(before, dump(page), label + " after bringing back")
        page.goto(APP + "#/settings")
        expect(page.get_by_text("Letzte Kopie:")).to_be_visible()

        # a confirmed export replaces the copy (the file holds everything; exported workouts are meant to go)
        page.goto(APP + "#/backup")
        page.get_by_role("button", name="Exportieren", exact=True).click()
        with page.expect_download():
            page.get_by_role("button", name="Datei teilen / speichern").click()
        page.get_by_role("button", name="✓ Ja, angekommen").click()
        expect(page.locator(".toast")).to_contain_text("Gesichert")
        if "updateBackup" in by_key(dump(page)["stores"]["meta"]):
            problems.append(f"{label}: the copy is still there after a confirmed export")
        ctx.close()

        # ---------- 3a. an older database version (before "measurements") ----------
        if fixture["dbVersion"] >= 3:
            old = copy.deepcopy(before)
            old["dbVersion"] = 2
            old["stores"].pop("measurements")
            ctx = browser.new_context(viewport={"width": 393, "height": 798}, is_mobile=True)
            page = ctx.new_page()
            page.on("pageerror", lambda e: problems.append(f"page error: {e}"))
            page.goto(BLANK)
            write(page, old)
            started(page)
            after = dump(page)
            if after["dbVersion"] != db_version or "measurements" not in after["stores"]:
                problems.append(f"{label}: database version 2 was not upgraded")
            compare(old, after, label + " from database version 2")
            backup = by_key(after["stores"]["meta"]).get("updateBackup", {}).get("value", {})
            if backup.get("reason") != "database" or backup.get("fromDbVersion") != 2:
                problems.append(f"{label}: no copy inside the database upgrade: {str(backup)[:80]}")
            ctx.close()

        # ---------- 3b. an older app on a newer database: refuses, keeps everything ----------
        newer = copy.deepcopy(before)
        newer["dbVersion"] = db_version + 50
        ctx = browser.new_context(viewport={"width": 393, "height": 798}, is_mobile=True)
        page = ctx.new_page()
        page.goto(BLANK)
        write(page, newer)
        page.goto(APP)
        expect(page.get_by_text("neueren Version der App")).to_be_visible()
        compare(newer, dump(page), label + " on a newer database")
        ctx.close()

    browser.close()

for problem in problems:
    print("✗", problem)
assert not problems, f"{len(problems)} problems"
print(f"DATA SAFETY TESTS PASSED ({len(fixtures)} saved databases, app {version})")
