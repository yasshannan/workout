"""Makes tests/fixtures/phone-db-<app version>.json: the phone app's database as the
current version stores it, filled the way you use the app (templates, an exported
and a finished workout, a running workout, body weight, measurements, settings).

Run it once for every release that changes how data is stored, and keep every
file: test_data_safety.py checks that the newest app still opens all of them
without losing a single record. Never edit an existing fixture.

    python tests/make_fixture.py
"""
import json, re, sys
from playwright.sync_api import sync_playwright, expect
from browser_db import ROOT, start_server, launch, dump

version = re.search(r"APP_VERSION = '([\d.]+)'", (ROOT / "phone/js/version.js").read_text()).group(1)
BASE = start_server() + "phone/"
with sync_playwright() as p:
    b = launch(p)
    ctx = b.new_context(viewport={"width": 393, "height": 798}, is_mobile=True, has_touch=True, accept_downloads=True)
    page = ctx.new_page()
    page.goto(BASE)
    expect(page.get_by_role("heading", name="Training")).to_be_visible()
    page.locator("#intro").wait_for(state="detached")
    # sample data: templates, a custom exercise, workouts, body weights
    page.goto(BASE + "#/backup")
    page.locator('input[type="file"]').set_input_files(str(ROOT / "shared/sample-data.json"))
    page.get_by_role("button", name="Importieren", exact=True).click()
    expect(page.get_by_text("Import fertig")).to_be_visible()
    # settings and a measurement
    page.goto(BASE + "#/settings")
    page.get_by_role("button", name="Dunkel", exact=True).click()
    page.goto(BASE + "#/measurements")
    page.get_by_label("Taille in cm").fill("81")
    page.get_by_role("button", name="Speichern").click()
    expect(page.get_by_text("Heute (korrigieren)")).to_be_visible()
    page.wait_for_timeout(300)
    # an export that is confirmed: workouts move to the archive, records stay
    page.goto(BASE + "#/backup")
    page.get_by_role("button", name="Exportieren", exact=True).click()
    with page.expect_download():
        page.get_by_role("button", name="Datei teilen / speichern").click()
    page.get_by_role("button", name=re.compile("angekommen")).click()
    page.wait_for_timeout(500)
    # one finished workout that is not exported yet, and one that is running
    for finish in (True, False):
        page.goto(BASE + "#/home")
        page.get_by_role("button", name="Training starten").click()
        page.get_by_role("button", name="+ Übung hinzufügen").click()
        page.get_by_placeholder("Übung suchen").fill("Bench")
        page.locator(".overlay .list-item").first.click()
        card = page.locator("#open-entry")
        card.get_by_label("Gewicht (kg)", exact=True).fill("60")
        card.get_by_label("Wiederholungen", exact=True).fill("8")
        page.get_by_role("button", name="✓ Satz speichern").click()
        page.wait_for_timeout(300)
        if finish:
            page.get_by_role("button", name="Training beenden").click()
            page.locator(".sheet").get_by_role("button", name="Beenden").click()
            page.wait_for_timeout(300)
    data = dump(page)
    data["stores"]["meta"]["records"] = [r for r in data["stores"]["meta"]["records"] if r["key"] != "updateBackup"]
    ctx.close(); b.close()
counts = {k: len(v["records"]) for k, v in data["stores"].items()}
out = ROOT / "tests/fixtures" / f"phone-db-{version}.json"
out.write_text(json.dumps({"appVersion": version, **data}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print("wrote", out.name, counts)
