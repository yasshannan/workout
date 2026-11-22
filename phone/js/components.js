// components.js — reusable pieces of the user interface.

import { h, formatDuration, formatThousands } from './util.js';
import {
  parseNumber, formatNumber, formatSet, formatWeight, formatSets, weightLabel, roundKg, weightStep,
  loadMode, setTypeTag, platesPerSide, SET_TYPES, repUnit, UNIT_SHORT, UNIT_LONG,
} from './format.js';
import { settings } from './settings.js';

/**
 * Hold a button down and it repeats, faster and faster: 60 → 100 kg is one
 * press of about two seconds instead of 16 taps. A short tap counts once.
 */
function repeatOnHold(button, action) {
  let timer = null;
  let count = 0;
  const stop = () => { clearTimeout(timer); timer = null; };
  const tick = () => {
    action();
    count++;
    timer = setTimeout(tick, count < 4 ? 220 : count < 12 ? 110 : 55);
  };
  button.addEventListener('pointerdown', (event) => {
    event.preventDefault();          // no text selection, no long-press menu
    count = 0;
    tick();
  });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach((name) => button.addEventListener(name, stop));
  button.addEventListener('contextmenu', (event) => event.preventDefault());
  // keyboard users (Enter / Space) still get a normal click
  button.addEventListener('click', (event) => { if (event.detail === 0) action(); });
}

/**
 * A number field with big − and + buttons:   [ − ]   60   [ + ]
 * Tap the number to type it; hold − or + to change it quickly.
 * onChange(text) is called with the field's text after every change.
 * note: optional small text above the field, at the right (e.g. "Ziel 8–12").
 * below: optional element under the field (e.g. the plate calculator).
 */
export function stepper({ label, value, step, decimal = false, note = '', below = null, onChange }) {
  const input = h('input', {
    class: 'stepper-input',
    type: 'text',
    inputmode: decimal ? 'decimal' : 'numeric',     // which phone keyboard to show
    value: value === null || value === undefined ? '' : String(value),
    placeholder: '0',
    'aria-label': label,
  });
  const bump = (direction) => {
    const now = parseNumber(input.value) || 0;
    // snap to the step, so 61 + 2.5 gives 62.5 and not 63.5
    const next = Math.round((now + direction * step) / step) * step;
    input.value = formatNumber(Math.max(0, roundKg(next)));
    onChange(input.value);
  };
  input.addEventListener('input', () => onChange(input.value));
  input.addEventListener('focus', () => input.select());
  const less = h('button', { class: 'btn secondary step', type: 'button', 'aria-label': `${label}: weniger` }, '−');
  const more = h('button', { class: 'btn secondary step', type: 'button', 'aria-label': `${label}: mehr` }, '+');
  repeatOnHold(less, () => bump(-1));
  repeatOnHold(more, () => bump(1));
  return h('div', { class: 'stepper' },
    h('div', { class: 'stepper-label' },
      h('span', {}, label),
      note ? h('span', { class: 'stepper-note' }, note) : null),
    h('div', { class: 'stepper-row' }, less, input, more),
    below);
}

/**
 * A row of chips where one (or, with multi, several) can be switched on.
 *   options:  [{ id, label }]
 *   selected: a Set of ids; it is changed directly when the user taps
 *   required: one option must always stay on
 *   fill:     the chips share the full width
 */
export function chipGroup({ options, selected, multi = false, required = false, scroll = false, fill = false, small = false, onChange }) {
  const group = h('div', { class: `chips${scroll ? ' scroll' : ''}${fill ? ' fill' : ''}${small ? ' small' : ''}` });
  const paint = () => {
    group.replaceChildren(...options.map((option) => h('button', {
      class: selected.has(option.id) ? 'chip on' : 'chip',
      type: 'button',
      'aria-pressed': selected.has(option.id) ? 'true' : 'false',
      onclick: () => {
        if (selected.has(option.id)) {
          if (required) return;
          selected.delete(option.id);
        } else {
          if (!multi) selected.clear();
          selected.add(option.id);
        }
        paint();
        if (onChange) onChange(selected);
      },
    }, option.label)));
  };
  paint();
  return group;
}

/** An An/Aus switch. onChange(true or false) is called when it is tapped. */
export function toggle(value, onChange, label) {
  let on = Boolean(value);
  const button = h('button', { type: 'button', 'aria-label': label, onclick: () => { on = !on; paint(); onChange(on); } });
  const paint = () => {
    button.className = on ? 'chip on' : 'chip';
    button.textContent = on ? 'An' : 'Aus';
    button.setAttribute('aria-pressed', on ? 'true' : 'false');
  };
  paint();
  return button;
}

/** One line of a settings list: label (and hint) on the left, a control on the right. */
export function settingRow(label, control, hint) {
  return h('div', { class: 'setting' },
    h('div', { class: 'label' }, label, hint ? h('div', { class: 'small muted' }, hint) : null),
    h('div', { class: 'control' }, control));
}

/** The three headline numbers of a workout, from summarize() in workout.js. */
export function workoutStats(summary) {
  const stat = (value, name) => h('div', { class: 'stat' }, h('div', { class: 'value' }, value), h('div', { class: 'name' }, name));
  return h('div', { class: 'stats' },
    stat(formatDuration(summary.durationMs), 'Dauer'),
    stat(formatSets(summary.workSets), 'Harte Sätze'),
    stat(formatThousands(summary.volumeKg), 'Volumen (kg)'));
}

/** A record from findNewRecords() in words. */
export function recordText(record) {
  if (record.kind === 'weight') return 'schwerstes Gewicht';
  if (record.kind === 'e1rm') return 'bestes geschätztes 1RM';
  if (record.unit === 'seconds' || record.unit === 'minutes') return `längste Zeit mit ${formatWeight(record.weightKg)}`;
  return `meiste Wdh. mit ${formatWeight(record.weightKg)}`;
}

/**
 * All logged sets of one exercise as tappable rows:
 *   W    40 kg × 10                       (warm-up)
 *   1    60 kg × 8 ★          0:41 · Pause 2:31
 *   D    45 kg × 6                        (drop set part)
 * timings comes from setTimings(); records (optional) from findNewRecords().
 */
export function setRows(entry, exercise, timings, onClick, records = null) {
  let number = 0;
  return entry.sets.map((set) => {
    const timing = timings.get(set.id);
    const record = records ? records.get(set.id) : null;
    const side = [];
    if (timing && timing.durationMs !== null) side.push(formatDuration(timing.durationMs));
    if (timing && timing.restBeforeMs !== null) side.push(`Pause ${formatDuration(timing.restBeforeMs)}`);
    const tag = setTypeTag(set);
    return h('button', { class: record ? 'set-row pr' : 'set-row', type: 'button', onclick: () => onClick(set) },
      h('span', { class: 'set-no' }, tag || String(++number)),
      h('span', { class: 'set-main' }, formatSet(set, exercise),
        record ? h('span', { class: 'record', title: `Neuer Rekord: ${recordText(record)}` }, ' ★') : null),
      h('span', { class: 'set-side' }, side.join(' · ')));
  });
}

/* ---------- Typing in a set ---------- */

/** A "draft" for a set that is being typed in. Numbers are kept as text. */
export function draftFromSet(set) {
  const text = (n) => (n === null || n === undefined ? '' : String(n));
  return {
    weight: set && set.weightKg !== null && set.weightKg !== undefined ? formatNumber(set.weightKg) : '',
    reps: set && set.reps ? String(set.reps) : '',
    repsLeft: text(set && set.repsLeft),
    partials: text(set && set.partials > 0 ? set.partials : ''),
    type: (set && set.type) || 'work',
  };
}

/**
 * The fields for one set: weight (with the plates for a barbell), reps (right
 * and left for one side at a time), the kind of set, and partial reps.
 * What the user types is written into the draft.
 * options.repTarget: shown small above the reps ("Ziel 8–12").
 */
export function setFields(draft, exercise, { repTarget = '' } = {}) {
  const perSide = loadMode(exercise) === 'perSide';
  const unit = repUnit(exercise);
  const cardio = unit === 'minutes';                 // cardio: only the minutes, no weight
  const barbell = exercise && exercise.equipment === 'barbell' && loadMode(exercise) === 'total' && exercise.loadType === 'external';
  const plates = h('div', { class: 'plates small muted' });
  const showPlates = () => {
    const text = barbell ? platesPerSide(parseNumber(draft.weight), settings().barKg) : '';
    plates.textContent = text ? `Pro Seite: ${text}` : '';
    plates.hidden = !text;
  };
  showPlates();

  const type = new Set([draft.type]);
  const showPartials = draft.partials !== '';
  const partials = stepper({
    label: 'Teilwiederholungen danach', value: draft.partials, step: 1,
    onChange: (text) => { draft.partials = text; },
  });
  partials.hidden = !showPartials;
  const partialsToggle = h('button', {
    class: 'btn ghost small', type: 'button',
    onclick: () => { partials.hidden = !partials.hidden; partialsToggle.textContent = partials.hidden ? '+ Teilwdh.' : '− Teilwdh.'; if (partials.hidden) draft.partials = ''; },
  }, showPartials ? '− Teilwdh.' : '+ Teilwdh.');

  const weightField = stepper({
      label: weightLabel(exercise), value: draft.weight, step: weightStep(exercise), decimal: true, below: plates,
      note: perSide ? 'eine Seite nach der anderen' : '',
      onChange: (text) => { draft.weight = text; showPlates(); },
    });
  weightField.hidden = cardio;
  partialsToggle.hidden = unit !== 'reps';

  return h('div', {},
    weightField,
    perSide
      ? h('div', { class: 'row' },
          stepper({ label: `${UNIT_SHORT[unit]} rechts`, value: draft.reps, step: 1, note: repTarget ? `Ziel ${repTarget}` : '', onChange: (text) => { draft.reps = text; } }),
          stepper({ label: `${UNIT_SHORT[unit]} links`, value: draft.repsLeft || draft.reps, step: 1, onChange: (text) => { draft.repsLeft = text; } }))
      : stepper({
          label: UNIT_LONG[unit], value: draft.reps, step: unit === 'seconds' ? 5 : 1,
          note: repTarget ? `Ziel ${repTarget}` : '',
          onChange: (text) => { draft.reps = text; },
        }),
    h('div', { class: 'type-row' },
      chipGroup({ options: SET_TYPES, selected: type, required: true, small: true, fill: true, onChange: () => { draft.type = [...type][0]; } }),
      partialsToggle),
    partials);
}

/**
 * Turn a draft into values for storing: { weightKg, reps, repsLeft, partials, type }.
 * Returns null and calls problem(message) if something is missing.
 */
export function readDraft(draft, exercise, problem) {
  const reps = Math.round(parseNumber(draft.reps));
  let weight = parseNumber(draft.weight);
  // For body-weight, assisted and cardio exercises an empty weight simply means 0.
  if (Number.isNaN(weight) && exercise && (exercise.loadType !== 'external' || repUnit(exercise) === 'minutes')) weight = 0;
  if (Number.isNaN(weight) || weight < 0) { problem('Zuerst das Gewicht eingeben'); return null; }
  if (!(reps >= 1)) { problem(`Zuerst die ${UNIT_LONG[repUnit(exercise)]} eingeben`); return null; }
  let repsLeft = null;
  if (loadMode(exercise) === 'perSide' && draft.repsLeft !== '') {
    const left = Math.round(parseNumber(draft.repsLeft));
    if (left >= 0 && left !== reps) repsLeft = left;
  }
  const partials = Math.max(0, Math.round(parseNumber(draft.partials)) || 0);
  return { weightKg: roundKg(weight), reps, repsLeft, partials, type: draft.type || 'work' };
}

/**
 * A small line chart of a few numbers, oldest on the left (the trend of an
 * exercise). markLast: the last point is today's, drawn in gold.
 */
export function sparkline(values, { width = 112, height = 30, markLast = false } = {}) {
  const NS = 'http://www.w3.org/2000/svg';
  const make = (tag, attrs) => {
    const el = document.createElementNS(NS, tag);
    for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value);
    return el;
  };
  const lo = Math.min(...values);
  const span = Math.max(...values) - lo || 1;
  const points = values.map((value, i) => [
    values.length === 1 ? width / 2 : 4 + (i * (width - 8)) / (values.length - 1),
    height - 4 - ((value - lo) / span) * (height - 8),
  ]);
  const svg = make('svg', { viewBox: `0 0 ${width} ${height}`, class: 'sparkline', 'aria-hidden': 'true' });
  svg.append(make('polyline', { points: points.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ') }));
  const [x, y] = points[points.length - 1];
  svg.append(make('circle', { cx: x.toFixed(1), cy: y.toFixed(1), r: 3.2, class: markLast ? 'today' : '' }));
  return svg;
}

