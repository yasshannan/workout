// format.js — weights, sets and numbers as text, the volume of a set, and how
// much a set counts. Everything is in kilograms. Numbers are written the
// German way: 62,5 kg.

/** Text → number. Accepts a comma ("62,5") or a point ("62.5"). NaN if empty. */
export function parseNumber(text) {
  const n = parseFloat(String(text).trim().replace(',', '.'));
  return Number.isFinite(n) ? n : NaN;
}

/** 62.5 → "62,5", 60 → "60", 61.999 → "62" */
export function formatNumber(n, decimals = 2) {
  const factor = 10 ** decimals;
  return String(Math.round(n * factor) / factor).replace('.', ',');
}

/** 62.5 → "62,5 kg" */
export function formatWeight(kg) {
  return `${formatNumber(kg)} kg`;
}

/** Round a typed weight to grams before storing it. */
export function roundKg(value) {
  return Math.round(value * 1000) / 1000;
}

/* ---------- How an exercise is loaded ---------- */

/** Default − / + step per equipment, if an exercise has no weightStep of its own. */
const DEFAULT_STEP = { barbell: 2.5, dumbbell: 2, machine: 5, cable: 2.5, bodyweight: 2.5, other: 1.25 };

/** How much the − / + buttons change the weight of this exercise. */
export function weightStep(exercise) {
  if (exercise && exercise.weightStep > 0) return exercise.weightStep;
  return DEFAULT_STEP[exercise ? exercise.equipment : 'barbell'] || 2.5;
}

/**
 * 'total'   the weight is the whole load (barbell, machine, one dumbbell)
 * 'perHand' two equal weights at once (two dumbbells): weightKg is ONE of them
 * 'perSide' one arm or leg at a time: reps per side, the left side may differ
 */
export function loadMode(exercise) {
  return exercise && exercise.load ? exercise.load : 'total';
}

/** Label for the weight field. */
export function weightLabel(exercise) {
  const type = exercise ? exercise.loadType : 'external';
  if (type === 'bodyweight') return 'Zusatzgewicht (kg)';
  if (type === 'assisted') return 'Unterstützung (kg)';
  if (loadMode(exercise) === 'perHand') return 'Gewicht pro Hantel (kg)';
  return 'Gewicht (kg)';
}

/* ---------- What a set counts ---------- */

/**
 * What the reps field of a set means for this exercise:
 *   'reps'     repetitions (the normal case)
 *   'seconds'  holds, hangs and carries: a hard set, but no volume in kg
 *   'minutes'  cardio: neither a hard set nor volume
 */
export function repUnit(exercise) {
  return exercise && exercise.unit ? exercise.unit : 'reps';
}

/** Short and long name of the unit: "Wdh." / "Wiederholungen". */
export const UNIT_SHORT = { reps: 'Wdh.', seconds: 'Sek.', minutes: 'Min.' };
export const UNIT_LONG = { reps: 'Wiederholungen', seconds: 'Sekunden', minutes: 'Minuten' };

/** 8 → "8", 45 s → "45 s", 30 min → "30 min" */
export function formatCount(n, exercise) {
  const unit = repUnit(exercise);
  return unit === 'seconds' ? `${n} s` : unit === 'minutes' ? `${n} min` : String(n);
}

/* ---------- Kinds of sets ---------- */

export const SET_TYPES = [
  { id: 'work', label: 'Normal' },
  { id: 'warmup', label: 'Aufwärmen' },
  { id: 'drop', label: 'Drop' },
  { id: 'restpause', label: 'Rest-Pause' },
];

/**
 * How much one set counts as a hard set:
 *   work 1 · drop / rest-pause ½ (each part of such a set is logged on its own) · warm-up 0
 * Cardio (unit 'minutes') never counts.
 */
export function hardSetValue(set, exercise) {
  if (repUnit(exercise) === 'minutes') return 0;
  if (set.type === 'work') return 1;
  if (set.type === 'drop' || set.type === 'restpause') return 0.5;
  return 0;
}

/** Reps that count for records: for one side at a time, the weaker side. */
export function effectiveReps(set) {
  return set.repsLeft === null || set.repsLeft === undefined ? set.reps : Math.min(set.reps, set.repsLeft);
}

/**
 * One set as text, e.g.
 *   "60 kg × 8"   "2 × 20 kg × 10" (two dumbbells)   "20 kg × 10 / 9" (right / left)
 *   "EG × 12"     "EG+10 kg × 8"   "EG−20 kg × 8"    (EG = Eigengewicht, body weight)
 *   "EG · 45 s"   "2 × 30 kg · 60 s"   "30 min"         (timed exercises)
 *   "… +3 Teilwdh."
 */
export function formatSet(set, exercise) {
  const type = exercise ? exercise.loadType : 'external';
  const unit = repUnit(exercise);
  let load = formatWeight(set.weightKg);
  if (type === 'bodyweight') load = set.weightKg > 0 ? `EG+${load}` : 'EG';
  else if (type === 'assisted') load = `EG−${load}`;
  else if (loadMode(exercise) === 'perHand') load = `2 × ${load}`;
  const reps = set.repsLeft !== null && set.repsLeft !== undefined && set.repsLeft !== set.reps
    ? `${set.reps} / ${set.repsLeft}` : String(set.reps);
  if (unit !== 'reps') {
    // "EG · 45 s", "2 × 30 kg · 60 s", "30 min" (no weight: just the time)
    const time = formatCount(reps, exercise);
    return type === 'external' && !(set.weightKg > 0) ? time : `${load} · ${time}`;
  }
  const partials = set.partials > 0 ? ` +${set.partials} Teilwdh.` : '';
  return `${load} × ${reps}${partials}`;
}

/** Short tag shown before the set: W(arm-up), D(rop), RP. Empty for normal sets. */
export function setTypeTag(set) {
  return { warmup: 'W', drop: 'D', restpause: 'RP' }[set.type] || '';
}

/** Target reps as text: "10" or "8–12" ('' when there is no target). */
export function formatRepTarget(repsMin, repsMax) {
  if (!repsMin) return '';
  return repsMax && repsMax !== repsMin ? `${repsMin}–${repsMax}` : String(repsMin);
}

/** 7.5 → "7,5", 0.75 → "0,75", 3 → "3" (a set counts 0.1 to 0.9 for a secondary muscle) */
export function formatSets(n) {
  return formatNumber(n, 2);
}

/* ---------- Volume ---------- */

/**
 * The kilograms one set adds to "volume" (load × reps). Warm-up sets count 0,
 * partial reps are not counted.
 *   external    load = the weight (× 2 for two dumbbells)
 *   bodyweight  load = body weight × the share that counts + extra weight
 *   assisted    load = body weight − assistance
 * One side at a time: the reps of both sides are added up.
 * Timed exercises (seconds, minutes) add nothing: kg × seconds is no volume.
 * bodyWeightKg may be null if no body weight was ever entered.
 */
export function setVolumeKg(set, exercise, bodyWeightKg) {
  if (set.type === 'warmup' || repUnit(exercise) !== 'reps') return 0;
  const type = exercise ? exercise.loadType : 'external';
  const mode = loadMode(exercise);
  const body = bodyWeightKg || 0;
  let load = set.weightKg;
  if (type === 'bodyweight') {
    const share = exercise.bodyweightFraction === undefined ? 1 : exercise.bodyweightFraction;
    load = body * share + set.weightKg;
  } else if (type === 'assisted') {
    load = body > 0 ? Math.max(0, body - set.weightKg) : 0;
  } else if (mode === 'perHand') {
    load = set.weightKg * 2;
  }
  const reps = mode === 'perSide'
    ? set.reps + (set.repsLeft === null || set.repsLeft === undefined ? set.reps : set.repsLeft)
    : set.reps;
  return load * reps;
}

/* ---------- Loading a barbell ---------- */

const PLATES = [25, 20, 15, 10, 5, 2.5, 1.25];

/**
 * The plates for one side of the bar: 100 kg on a 20 kg bar → "25 + 15".
 * Returns '' when it does not apply, "nur Stange" for the empty bar, and adds
 * "(+0,5 kg fehlt)" when the weight cannot be loaded exactly.
 */
export function platesPerSide(totalKg, barKg) {
  if (!(totalKg > 0) || !(barKg > 0) || totalKg < barKg) return '';
  let rest = Math.round(((totalKg - barKg) / 2) * 1000) / 1000;
  if (rest === 0) return 'nur Stange';
  const used = [];
  for (const plate of PLATES) {
    while (rest >= plate - 1e-9) { used.push(plate); rest = Math.round((rest - plate) * 1000) / 1000; }
  }
  const text = used.map((plate) => formatNumber(plate)).join(' + ');
  return rest > 0 ? `${text} (${formatNumber(rest * 2)} kg fehlen)` : text;
}
