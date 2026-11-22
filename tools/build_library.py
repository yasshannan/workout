"""Builds shared/exercises.json from shared/exercises.txt.

    python tools/build_library.py

exercises.txt has one exercise per line:

    Name [id] | main muscle | secondary muscle share, ... | movement equipment load step [extras] | tip; tip; tip

- [id] is only needed when the id is not the name in lower case with dashes.
  Never change an id: logged workouts point to it.
- Shares go from 0.1 to 0.9 in 0.1 steps ("0.6", ".6" and "0,6" all work).
- load: total, perHand or perSide.   step: weight step in kg.
- extras, in any order:
    compound          multi-joint exercise (gets an estimated 1RM)
    bodyweight[=0.3]  body weight counts as load (share of it, default 1); the weight is extra weight
    assisted          a machine takes weight off (assisted pull-up)
    seconds           a set is timed in seconds (hang, hold, carry)
    minutes           cardio in minutes (gives no muscle sets)
- tips (optional): short technique tips, separated by ";". The phone shows them
  under "Technik" on the exercise.
- Lines starting with # are comments.

When the exercises changed, libraryVersion and the phone's APP_VERSION (sw.js and
js/version.js) go up by one, so phones load the new list.

An exercise id that disappears (deleted line, changed name or [id]) is refused:
logged workouts, records and "last time" point to it. If you really mean it:
    python tools/build_library.py --remove old-id
(the exercise is then only hidden on the phone; logged sets keep it)."""
import json, re, sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TXT, JSON, SW = ROOT / "shared/exercises.txt", ROOT / "shared/exercises.json", ROOT / "phone/sw.js"
VERSION_JS = ROOT / "phone/js/version.js"
MOVEMENTS = {"push", "pull", "legs", "core"}
EQUIPMENT = {"barbell", "dumbbell", "cable", "machine", "bodyweight", "other"}
LOADS = {"total", "perHand", "perSide"}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def parse(lines, muscles):
    out, ids, errors = [], set(), []
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        def bad(msg): errors.append(f"line {n}: {msg}  →  {line}")
        parts = [p.strip() for p in line.split("|")]
        if len(parts) not in (4, 5):
            bad("needs 4 parts separated by | (and the tips as a 5th)"); continue
        head, prim, sec, rest = parts[:4]
        sec = split_shares(sec)
        cues = [c.strip() for c in parts[4].split(";") if c.strip()] if len(parts) == 5 else []
        m = re.fullmatch(r"(.+?)\s*(?:\[([a-z0-9-]+)\])?", head)
        name, eid = m.group(1), m.group(2) or slug(m.group(1))
        if eid in ids: bad(f"id {eid} twice")
        ids.add(eid)
        primary = [p.strip() for p in prim.split(",") if p.strip()]
        shares = {}
        for item in filter(None, (s.strip() for s in sec.split(","))) if sec not in ("", "-", "–") else []:
            pm = re.fullmatch(r"([a-z_]+)\s+(0?[.,]\d)", item)
            if not pm: bad(f"'{item}' should look like 'biceps 0.4'"); continue
            v = float(pm.group(2).replace(",", "."))
            if not 0.1 <= v <= 0.9: bad(f"{item}: share must be 0.1–0.9")
            shares[pm.group(1)] = round(v, 1)
        for mid in primary + list(shares):
            if mid not in muscles: bad(f"unknown muscle '{mid}'")
        if set(primary) & set(shares): bad("a muscle is both main and secondary")
        words, compound, load_type, fraction, unit = [], False, "external", None, None
        for w in rest.split():
            if w == "compound": compound = True
            elif w == "assisted": load_type = "assisted"
            elif w in ("seconds", "minutes"): unit = w
            elif w.startswith("bodyweight") and len(words) >= 2:      # the equipment may be called bodyweight too
                load_type = "bodyweight"
                if "=" in w:
                    try: fraction = float(w.split("=", 1)[1].replace(",", "."))
                    except ValueError: bad(f"'{w}': share must be a number like 0.3")
            else: words.append(w)
        if len(words) != 4: bad("last part: movement equipment load step [extras]"); continue
        mov, eq, load, step = words
        if mov not in MOVEMENTS: bad(f"movement must be one of {sorted(MOVEMENTS)}")
        if eq not in EQUIPMENT: bad(f"equipment must be one of {sorted(EQUIPMENT)}")
        if load not in LOADS: bad(f"load must be one of {sorted(LOADS)}")
        try: step = float(step.replace(",", "."))
        except ValueError: bad("step must be a number"); continue
        e = {"id": eid, "name": name, "primaryMuscles": primary, "secondaryMuscles": list(shares)}
        if shares: e["muscleShares"] = shares
        if load_type != "external" and load != "total": bad("bodyweight / assisted exercises need load total")
        e.update(movement=mov, equipment=eq, loadType=load_type)
        if fraction is not None: e["bodyweightFraction"] = int(fraction) if fraction.is_integer() else fraction
        e.update(compound=compound, load=load, weightStep=int(step) if step.is_integer() else step)
        if unit: e["unit"] = unit
        if cues: e["cues"] = cues
        out.append(e)
    return out, errors


def split_shares(sec):
    """Allow '0,6' as a decimal comma: 'biceps 0,6, traps 0,3' → 'biceps 0.6, traps 0.3'."""
    return re.sub(r"(\d),(\d)", r"\1.\2", sec)


def write_json(lib):
    E, M = lib["exercises"], lib["muscles"]
    out = ['{', f'  "libraryVersion": {lib["libraryVersion"]},', f'  "updatedAt": "{lib["updatedAt"]}",', '  "muscles": [']
    out += ['    ' + json.dumps(m, ensure_ascii=False) + (',' if i < len(M) - 1 else '') for i, m in enumerate(M)]
    out += ['  ],', '  "exercises": [']
    out += ['    ' + json.dumps(e, ensure_ascii=False) + (',' if i < len(E) - 1 else '') for i, e in enumerate(E)]
    out += ['  ]', '}']
    JSON.write_text('\n'.join(out) + '\n', encoding="utf-8")


def main():
    lib = json.loads(JSON.read_text(encoding="utf-8"))
    muscles = {m["id"] for m in lib["muscles"]}
    lines = TXT.read_text(encoding="utf-8").splitlines()
    exercises, errors = parse(lines, muscles)
    if errors:
        print("\n".join(errors)); sys.exit(1)
    if exercises == lib["exercises"]:
        print(f"no change ({len(exercises)} exercises)"); return
    old = {e["id"] for e in lib["exercises"]}
    gone = sorted(old - {e["id"] for e in exercises})
    allowed = {sys.argv[i + 1] for i, a in enumerate(sys.argv[:-1]) if a == "--remove"}
    refused = [g for g in gone if g not in allowed]
    if refused:
        print("These exercise ids would disappear: " + ", ".join(refused))
        print("Logged workouts point to them. Keep the [id] in exercises.txt (e.g. 'New Name [" + refused[0] + "]'),")
        print("or, if you really mean it: python tools/build_library.py " + " ".join("--remove " + r for r in refused))
        sys.exit(1)
    lib["exercises"] = exercises
    lib["libraryVersion"] += 1
    lib["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    write_json(lib)
    new_ver = None
    for path in (SW, VERSION_JS):                  # the same number in both files
        text = path.read_text(encoding="utf-8")
        m = re.search(r"APP_VERSION = '(\d+)\.(\d+)\.(\d+)'", text)
        new_ver = new_ver or f"{m.group(1)}.{m.group(2)}.{int(m.group(3)) + 1}"
        path.write_text(text.replace(m.group(0), f"APP_VERSION = '{new_ver}'"), encoding="utf-8")
    print(f"{len(exercises)} exercises, libraryVersion {lib['libraryVersion']}, APP_VERSION {new_ver}")
    if gone: print("removed:", ", ".join(gone))


if __name__ == "__main__":
    main()
