# Changelog

## 1.0.3 — 21.11.2026 — updates never delete data

- iPhone: before the first start of every new version the app copies all data; Einstellungen →
  "Schutz bei Updates" can bring back anything missing (nothing that is there is changed).
  A confirmed export replaces the copy.
- iPhone database: rules and numbered steps that only add (never delete); a copy is made inside every
  database upgrade before anything changes; an older app on newer data refuses to start and leaves it alone.
- The app asks iOS to protect its storage from the first start.
- Exercise tool: refuses to remove or rename exercise ids that logged workouts point to.
- Windows: copies the database to workout-vor-update.sqlite before a new version changes it.
- tests/test_data_safety.py with a saved database of this version (tests/fixtures/).

## 1.0.2 — 21.11.2026 — true black

- Dark mode is true black for the iPhone's OLED screen (black pixels are switched off: deeper
  contrast, a little less battery). Cards and dialogs use the dark greys of iOS, so they still stand out.
- Status bar and start screens are black in dark mode too.
- The texts say "iPhone" instead of "Handy".

## 1.0.1 — 21.11.2026 — fine-tuned for the iPhone 15 Pro

- Every screen checked at the 15 Pro's size (393 × 852 points, Dynamic Island, home bar), light and dark:
  nothing sticks out or is cut off.
- After saving a set the page scrolls just enough that "Satz speichern" stays above the rest bar
  (a record note used to push it underneath).
- The rest bar fills smoothly at the 120 Hz of the Pro iPhones.

## 1.0.0 — 21.11.2026 — the first official version

**iPhone app**
- Made for the iPhone only: full screen width from the iPhone SE to the Pro Max, clear of the
  Dynamic Island and the home bar, San Francisco font (rounded numbers for weights, reps and timers).
- Intro on every start of the app: the Δ logo draws itself, then the app appears. A tap skips it;
  with "Bewegung reduzieren" switched on in iOS it is left out.
- Start screens for every iPhone size, light and dark, so the app no longer flashes white while it loads.
- Tab bar as in iOS: drawn symbols, see-through with the page blurred behind it.
- Home: logo in the title, round light/dark button, Home Screen hint with Safari's share symbol.
- A light haptic tick when a set is saved (with "Vibrieren" switched on).
- Settings → Info: logo, version and where your data lives.
- The colours chosen in Settings are there from the first moment of the next start.
- Exercises timed in seconds (hangs, holds, carries) or minutes (cardio); muscle group rotator cuff;
  40 researched exercises in `shared/exercises.txt`.

**Windows analyzer**
- Knows timed exercises and the rotator cuff.

The versions before (up to 3.4.3) were development versions. Data and export files from them work unchanged.
