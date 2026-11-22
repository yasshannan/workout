# Workout Tracker — Version 1.0

A personal fitness app in two parts:

| Part | Folder | What it is |
|---|---|---|
| iPhone logger | `phone/` | A web app for the iPhone's Home Screen (made for iPhone only: SE up to Pro Max). Works offline. Logs your workouts and keeps them on the phone until you export them. Opens with a short intro of the Δ logo. German texts. |
| Windows analyzer | `analyzer/` | Qt 6 / QML app. Imports the exports and shows a plan for next week, animated charts, statistics per exercise and per muscle, and insights. German texts. |
| Shared files | `shared/` | Exercise library, the file format, sample data. Used by both apps. |

Your workouts never go to GitHub or any server. GitHub only hosts the app's code.

---

## Part 1: the phone logger

### 1. Put the project on GitHub (once)

You need a free GitHub account and **GitHub Desktop**. No command line.

1. Create an account at <https://github.com>.
2. Install GitHub Desktop from <https://desktop.github.com> and sign in.
3. Unzip this project somewhere permanent, for example `Documents\workout`.
4. GitHub Desktop: **File → Add local repository…** → choose the `workout` folder. It says the
   folder is not a repository yet: click **create a repository**, keep the name, **Create repository**.
5. Click **Publish repository**, **untick "Keep this code private"**, then **Publish**.

> Why public? On a free account GitHub Pages only works for public repositories. That is fine:
> the repository holds only code and fake sample data.

### 2. Turn on GitHub Pages (once)

1. On github.com open your repository (GitHub Desktop: **Repository → View on GitHub**).
2. **Settings** → **Pages** (left).
3. **Source:** `Deploy from a branch`, **Branch:** `main`, folder `/ (root)`, **Save**.
4. After a minute or two the page shows your address: `https://YOUR-NAME.github.io/workout/`
5. The app is at **`https://YOUR-NAME.github.io/workout/phone/`**

### 3. Install it on the phone (once)

Open the address in **Safari** on the iPhone, wait until the app shows, tap **Share** → **Add to Home Screen** → **Add**.
The app is made for the iPhone only (iOS 16.4 or newer; keeping the screen on needs iOS 18.4).

From now on always open the app from its icon. The browser tab and the icon keep separate data,
and removing the icon deletes the app's data, so export after every workout.

### 4. Five-minute check on the phone

These things cannot be tested on a PC:

1. **Einstellungen → Info** says "Vom Home-Bildschirm geöffnet: ja".
2. **Einstellungen → Vibration testen:** the phone vibrates (iPhone: three short ticks). Then
   **Test in 5 s** and don't touch the phone: it should vibrate again. That is the end-of-rest situation.
   (iPhones have no official vibration for web apps; the app uses a known trick. Tell me if the
   second test stays silent.)
3. Airplane Mode on, close the app completely, open it again: it still works.
4. Start a workout, log a set: the slim rest bar appears at the bottom and the screen stays on (iPhone: iOS 18.4 or newer).
5. Lock the phone for a minute and unlock it: workout clock and rest timer show the right time.
6. Finish, **Jetzt exportieren → Exportieren → Datei teilen / speichern**, save the file to OneDrive
   or Files, check it is there, then **✓ Ja, angekommen**. History then shows the workout with a ✓.

### 5. Using it

- **Training starten** (or tap a template), **+ Übung hinzufügen**, check weight and reps, **✓ Satz speichern**.
  The fields are pre-filled, so most sets need one tap. Tap the number to type it, or **hold − / +**:
  it runs faster the longer you hold. Each exercise has its own step (barbell 2.5 kg, dumbbell 2 kg,
  machine 5 kg; change it in the exercise editor).
- **Kind of set:** Normal · Aufwärmen · Drop · Rest-Pause. Log every part of a drop set on its own
  as "Drop": it counts ½ hard set and never makes a record. **+ Teilwdh.** adds partial reps.
- **Dumbbells:** for two dumbbells at once you enter the weight of ONE ("Gewicht pro Hantel"), the volume
  counts both. Exercises done one side after the other (one-arm row, split squat …) ask for
  "Wdh. rechts" and "Wdh. links".
- **Barbell:** under the weight you see the plates per side ("Pro Seite: 25 + 10"); set the bar weight
  in Einstellungen. Before the first set of a multi-joint exercise, **Aufwärmsätze planen** suggests
  warm-ups (bar × 10, 40 % × 8, 60 % × 5, 80 % × 3) and fills them in one after the other.
- **Progression:** with a rep range (e.g. 8–12), when every working set reached 12 last time, the app
  says "↑ … → +2,5 kg" and pre-fills the heavier weight with 8 reps (double progression).
- **Supersets:** in a template switch on "Supersatz mit der nächsten Übung", or in a workout ⋯ →
  "Als Supersatz mit der Übung darüber". After a set the next exercise opens with a 15 s "Wechsel";
  the real rest comes after the round.
- **Rest bar:** starts by itself after every set, slim at the bottom. **−15 / +15** change the target (the
  exercise remembers it), tap the time for big numbers, **▶ Los** starts the next set (that measures how
  long the set takes; optional). When the time is up the phone vibrates and the bar flashes. No sound.
- **Machine note:** ⋯ → "Geräte-Einstellung notieren" ("Sitz 4, Studio A") is shown at that exercise
  every time. For a second machine of the same kind (other gym): exercise editor → "Als Kopie anlegen",
  then records and "last time" are kept apart.
- Tap a logged set to correct or delete it. Everything is saved after every tap. If the app is closed
  mid-workout, it reopens in that workout. Swipe from the left edge to go back. Everything is in **kg**.

**Gold = record**
- A normal working set that beats your history (heaviest weight, best estimated 1RM, or most reps at
  that weight) turns gold with a ★. The estimated 1RM is only used for multi-joint exercises with
  weights and sets of up to 8 reps; isolation exercises are judged by weight and reps.
- The **whole exercise card turns gold** when you moved more kilograms **with the same number of sets**
  than ever before: 3 sets today against the first 3 sets of every earlier workout. A sloppy extra set
  never makes gold. "Volumen (3 Sätze): 1.405 kg / Bestwert 1.495 kg" shows how close you are.

**Templates**
- Each exercise is one line ("3 × 8–12 · Pause 2:00"); tap it to change sets, **Feste Wdh.** or
  **Wdh.-Bereich**, rest and superset. Drag the **≡** handle to change the order.
- In the workout the reps field starts at that number (for a range: the lower end), and
  "Ziel 8–12" stands small above the field.
- At the top a **body figure** (front and back, 26 muscle groups) shows what the template trains:
  dark = main muscle, light = on the side, faint = not at all. Tap a muscle for its sets and exercises,
  **⤢ Größer** shows it twice as big. A set counts 1 for a main muscle and 0.1 to 0.9 for a secondary one,
  depending on the exercise (bench press: upper chest 0.6, triceps 0.6, front delts 0.5).

**Body weight and measurements:** enter the weight on Start, once a day. Then Start shows "✓ Heute: 78,2 kg"
until tomorrow (**Korrigieren** fixes a typo). **Körpermaße** (waist, chest, arm, thigh, calf, body fat; all
optional) works the same way; every 1–2 weeks is enough. The Windows app draws the graphs.

**Export:** workouts stay on the phone until you export them. **Exportieren → Datei teilen / speichern**,
then check in OneDrive or Files that the file is there and tap **✓ Ja, angekommen**. Only then do the
workouts leave the phone. History keeps a ✓ line for each, and "last time", "Bestwert", your records,
the progression hint and the gold keep working, because the app keeps a small summary per exercise.
A copy of the newest file stays on the phone until the next export (**Letzten Export nochmal teilen**).

**Reinstalling:** export a full backup in the Windows app (**Daten → Vollständige Sicherung fürs Handy
speichern**), then on the phone **Export / Import → Sicherungsdatei importieren**. Your templates,
exercises and records come back.

### 6. Changing the app later

1. Edit the files in `phone/`.
2. Raise `APP_VERSION` in `phone/sw.js` **and** in `phone/js/version.js` (the same number), e.g.
   `'1.0.3'` → `'1.0.4'`. **This tells phones that there is a new version.** If you add a file, also add it
   to the `ASSETS` list in `sw.js`. (`tools/build_library.py` does the version for you.)
3. GitHub Desktop: short summary bottom left → **Commit to main** → **Push origin**.
4. After a minute or two (green tick under **Actions** on github.com), open the app while online.
   It updates itself and reloads once; **Einstellungen → Info** shows the new version. Your data stays.
   If a workout is running, the update waits until you are back on Home.

### 7. Trying the phone app on your PC

A local web server is needed (double-clicking `index.html` does not work). With Python, in the
folder that **contains** `workout`:

```
python -m http.server 8000
```

Open <http://localhost:8000/workout/phone/> in Chrome or Edge, press **F12**, then **Ctrl+Shift+M**
and pick an iPhone (e.g. iPhone 14 Pro Max). (Started inside the `workout` folder itself, the address is
<http://localhost:8000/phone/>.) If an old version shows, press **Ctrl+F5**.

On `localhost` the offline cache is off on purpose so you always see your edits; add `?sw` to the
address to test offline. For test data: **Export / Import → Sicherungsdatei importieren** →
`shared/sample-data.json`.

---

## Part 2: the Windows analyzer

### 1. Build it in Qt Creator

1. In the **Qt Maintenance Tool** make sure you have **Qt 6.10** with **MinGW 64-bit**. No extra
   modules are needed (no Qt Charts, no Qt Graphs: the charts are drawn by the app).
2. Qt Creator → **File → Open File or Project…** → `workout\analyzer\CMakeLists.txt`.
   (This replaces your old "Hello World" project; its greys and the light/dark button live on here.)
3. Kit **Desktop Qt 6.10 MinGW 64-bit** → **Configure Project**.
4. Bottom left: build type **Release**, then the green **Run** arrow.
5. The app opens on **Daten**. **Dateien importieren…** → `workout\shared\sample-data.json`.

I could not compile the Qt part myself. If the build stops, copy the first red line from
**Issues** or **Compile Output** and send it to me.

### 2. What it shows

| Page | What you see |
|---|---|
| Übersicht | **Nächste Woche**: up to 8 concrete actions ("Beinbeuger: +4 Sätze pro Woche", "Bankdrücken: Gewicht erhöhen", "seit 5 Wochen kein Fortschritt"), then totals and weekly charts |
| Muskeln | All 26 muscle groups: hard sets per week against each muscle's own target, how often trained. Click one: weekly chart, which exercises give it sets (with their share), weeks in range, push/pull and upper/lower balance |
| Übungen | Click an exercise: workouts, sets, reps, kilograms, records, strength per kg body weight. Chart: estimated 1RM (multi-joint) or heaviest weight (isolation), optionally **÷ Körpergewicht**, kilograms per workout or sets per week. **Gold = record**; volume records compare the same number of sets |
| Körper | Body weight with 7-day average and the change per week in kg and % (with what it means for a build-up or a diet), and the body measurements |
| Einheiten | Workout length, rest between sets and between exercises, rest per exercise against your target |
| Regelmäßigkeit | Workouts per week, streaks, calendar heatmap |
| Erkenntnisse | Plain sentences with the reasoning, the source and how sure they are ("Sicherheit"). Trends are a line through 6 weeks, so one bad day never raises an alarm, and nothing warns on less than two weeks of data |
| Daten | Import, automatic import folder, full backup for the phone |
| Einstellungen | Theme, 1RM formula, animations, training level (Anfänger / Fortgeschritten / Erfahren sets all targets at once), weekly target per muscle, which muscles each exercise trains and how much (1, then 0.9 to 0.1) |

The filter bar (date range, one exercise, one muscle) applies to every page. **Seite als PNG** and
**PDF-Bericht** are there too. Muscles that get plenty of work from other exercises (front delts,
forearm flexors and extensors, brachioradialis, obliques …) have a weekly minimum of 0; change any target in Einstellungen.

### 3. Automatic import

1. PC: **Daten → Automatischer Import → Ordner wählen**, e.g. `OneDrive\Workout`.
2. Phone, after a workout: **Jetzt exportieren → Exportieren → Datei teilen / speichern → OneDrive** → that folder, then **✓ Ja, angekommen**.
3. The analyzer imports every new file there by itself, also files that arrived while it was closed.

### 4. A standalone .exe

1. Build in **Release**.
2. Make an empty folder, e.g. `C:\WorkoutAnalyzer`, and copy `appWorkout.exe` into it (from the build
   folder shown under **Projects → Build directory**).
3. Start menu → **Qt 6.10 (MinGW 64-bit)** (a command window with Qt's tools) and run, with your paths:

   ```
   windeployqt --release --qmldir C:\Users\You\Documents\workout\analyzer C:\WorkoutAnalyzer\appWorkout.exe
   ```

4. Double-click `appWorkout.exe`. You can move the whole folder or put a shortcut on the desktop.

Your data is in `C:\Users\You\AppData\Roaming\WorkoutTracker\Workout Analyzer\workout.sqlite`
(shown at the bottom of the Daten page), so rebuilding or moving the app never touches it.
A database from an older version is upgraded by itself at the first start.

### 5. Changing the statistics or insights

All numbers are SQL in `analyzer/sql/derived.sql`: each chart reads one view (e.g. `v_weekly`),
each insight is one block in `v_insights`. Try a change without Qt:

```
python tools\check_analyzer.py shared\sample-data.json
```

---

## FAQ

**Why GitHub?** An iPhone only installs an offline web app from an `https://` address. GitHub Pages
gives you one for free. Only the code is there; your workouts stay on the phone until you export them.

**Why can't the phone send the data by itself on my home Wi-Fi?** A web app cannot see which Wi-Fi it
is on, and a page from `https://` may not talk to an `http://` address in your home network. The
automatic import folder is the next best thing: three taps on the phone, nothing on the PC.

## If something goes wrong

| Problem | What to check |
|---|---|
| Phone shows the old version | `APP_VERSION` raised in `sw.js`? Green tick under **Actions**? Open the app while online, or **Einstellungen → Nach Update suchen**. |
| "404" | The address must end with `/workout/phone/`, Pages must be on, the first deployment takes a minute or two. |
| No vibration | **Einstellungen → Vibrieren** on? It only works while the app is open. If the iPhone never vibrates, the countdown and the flashing bar are the signal. |
| Screen turns off | **Einstellungen → Bildschirm im Training anlassen**; needs iOS 18.4+ and the app opened from its icon. Low Power Mode can override it. |
| Data missing on the phone | Opened in Safari instead of from the icon? Icon removed and added again? Import a backup from the Windows app. |

## What is in the folders

```
workout/
├─ README.md                   this file
├─ index.html                  forwards to phone/
├─ shared/
│  ├─ exercises.txt            the built-in exercises, one line each (edit this one)
│  ├─ exercises.json           made from exercises.txt by tools/build_library.py, plus the 26 muscle groups
│  ├─ schema-v1.json           the file format, formally
│  ├─ SCHEMA.md                the file format, explained
│  ├─ sample-data.json         8 weeks of fake workouts
│  └─ sample-data-incremental.json   a small follow-up export, to test merging
├─ phone/
│  ├─ index.html, manifest.webmanifest, icons/
│  ├─ sw.js                    offline cache and updates (APP_VERSION is here)
│  ├─ css/theme.css            colours: the four greys of Main.qml, status colours, gold
│  ├─ css/app.css              layout
│  └─ js/
│     ├─ app.js                start-up and switching between screens
│     ├─ workout.js            the running workout: log set, rest, supersets, progression, warm-ups
│     ├─ records.js            last time, personal records, best volume (gold)
│     ├─ archive.js            History, and moving exported workouts off the phone
│     ├─ backup.js             export and import
│     ├─ templates.js, bodyWeights.js, measurements.js, library.js, settings.js, schema.js
│     ├─ db.js                 the phone's database (IndexedDB)
│     ├─ clock.js, device.js   clocks; screen wake lock and vibration
│     ├─ format.js, util.js    text, numbers, volume, plates, small helpers
│     ├─ components.js         steppers (hold to repeat), set fields, set rows …
│     ├─ bodymap.js            the body figure of the template editor
│     ├─ screens/              one file per screen
│     └─ dialogs/              exercise picker, exercise editor, set editor
├─ analyzer/
│  ├─ CMakeLists.txt           open this in Qt Creator
│  ├─ main.cpp
│  ├─ src/                     Database, Importer (JSON → SQLite), Backend (what QML calls), ReportExporter (PNG/PDF)
│  ├─ sql/                     schema.sql (tables), derived.sql (statistics, insights), statements.sql
│  ├─ Theme.qml, Main.qml, *Page.qml
│  └─ BarChart, LineChart, Heatmap, RangeBar … .qml   the animated charts
└─ tools/                      make_sample_data.py, make_icons.py, check_analyzer.py,
                               test-library.json (the exercises the sample data uses)
```

A good first file to read: `phone/js/workout.js`. It has no HTML in it, only the logic.

## Adding or changing exercises

1. Open `shared/exercises.txt`. Each line is one exercise:
   `Name [id] | main muscle | secondary share, ... | movement equipment load step [compound]`
   for example `Cable Reverse Curl | brachioradialis | brachialis 0.8, biceps 0.4 | pull cable total 2.5`.
   Extras at the end: `compound`, `bodyweight` (or `bodyweight=0.3`), `assisted`, `seconds`
   (hangs, holds, carries: hard sets without kg volume) and `minutes` (cardio: no muscle sets).
2. Run `python tools/build_library.py`. It checks the lines, writes `exercises.json`
   and raises `APP_VERSION`, so phones load the new list.

## Updates never delete your data

Updating the app only replaces its files; your saved data is kept apart and is never touched. On top of that:

- **iPhone:** before the first start of a new version the app copies all your data (one copy, on the iPhone).
  If anything were missing after an update: **Einstellungen → Schutz bei Updates → Fehlende Daten zurückholen**
  brings back everything that is missing, without changing what is there. A confirmed export replaces the copy
  (the export file then has everything).
- **iPhone database:** it only ever grows. A new version may add things, never delete or empty them
  (rules at the top of `phone/js/db.js`). An older app on newer data refuses to start instead of touching it.
- **Exercises:** `tools/build_library.py` refuses to remove or rename an exercise id, because your logged
  workouts point to it. Rename an exercise by keeping its id: `New Name [old-id]`.
- **Windows:** before a new version changes the database, it copies the file to
  `workout-vor-update.sqlite` next to `workout.sqlite`
  (`C:\Users\<you>\AppData\Roaming\WorkoutTracker\Workout Analyzer\`). To go back: close the app and
  rename the copy to `workout.sqlite`.
- **Check:** `python tests/test_data_safety.py` opens saved databases from earlier versions
  (`tests/fixtures/`) with the newest app and fails if a single record is lost or changed. Run it before
  every release. When a release changes how data is stored, add a fixture: `python tests/make_fixture.py`.

One thing no update can protect against: removing the app's icon from the Home Screen deletes its data in iOS.
Export regularly.

## Versions

See `CHANGELOG.md`. Version 1.0 is the first official version; the numbers before it (up to 3.4)
were development versions. Your data and exports from them work unchanged.
