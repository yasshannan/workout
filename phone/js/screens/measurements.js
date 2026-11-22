// screens/measurements.js — body measurements: waist, chest, arm, thigh, calf
// and body fat. Every field is optional; one entry per day. After an export
// only the newest entry stays on the phone (to compare the next one with);
// the Windows app keeps all of them and draws the graphs.

import { h, fill, go, formatDate, toast, isToday, confirmSheet } from '../util.js';
import { MEASURES, listMeasurements, saveTodaysMeasurements, deleteMeasurement } from '../measurements.js';
import { formatNumber, parseNumber } from '../format.js';

export async function render(root) {
  const entries = await listMeasurements();
  const newest = entries[0] || null;
  const today = newest && isToday(newest.measuredAt) ? newest : null;
  const previous = today ? entries[1] || null : newest;

  const inputs = new Map();
  const rows = MEASURES.map(({ id, label, unit }) => {
    const input = h('input', {
      type: 'text', inputmode: 'decimal', placeholder: unit, 'aria-label': `${label} in ${unit}`,
      value: today && today[id] ? formatNumber(today[id], 1) : '',
    });
    inputs.set(id, input);
    const before = previous && previous[id] ? `vorher ${formatNumber(previous[id], 1)} ${unit}` : '';
    return h('label', { class: 'measure-row' },
      h('span', { class: 'measure-name' }, label, before ? h('span', { class: 'small muted' }, before) : null),
      input,
      h('span', { class: 'measure-unit muted' }, unit));
  });

  const save = async () => {
    const values = {};
    for (const [id, input] of inputs) {
      const value = parseNumber(input.value);
      values[id] = value > 0 ? Math.round(value * 10) / 10 : null;
    }
    if (Object.values(values).every((value) => value === null)) return toast('Mindestens ein Maß eintragen');
    await saveTodaysMeasurements(values);
    toast('Maße gespeichert');
    go('#/measurements');
  };

  const remove = async (entry) => {
    if (!await confirmSheet(`Den Eintrag vom ${formatDate(entry.measuredAt)} löschen?`, 'Löschen', { danger: true })) return;
    await deleteMeasurement(entry);
    go('#/measurements');
  };

  fill(root,
    h('div', { class: 'topbar' }, h('a', { class: 'btn ghost', href: '#/home' }, '‹ Start')),
    h('h1', {}, 'Körpermaße'),
    h('p', { class: 'small muted' }, 'Am besten alle 1–2 Wochen, morgens, immer an derselben Stelle gemessen. Leere Felder werden nicht gespeichert.'),
    h('div', { class: 'card' },
      h('h3', {}, today ? 'Heute (korrigieren)' : 'Heute'),
      rows,
      h('div', { class: 'spacer' }),
      h('button', { class: 'btn block', onclick: save }, 'Speichern')),
    entries.length > 0 ? h('h2', {}, 'Auf dem iPhone') : null,
    entries.map((entry) => h('div', { class: 'list-item' },
      h('div', {},
        h('div', { class: 'title' }, formatDate(entry.measuredAt)),
        h('div', { class: 'sub' }, MEASURES.filter(({ id }) => entry[id]).map(({ id, label, unit }) => `${label} ${formatNumber(entry[id], 1)} ${unit}`).join(' · '))),
      h('button', { class: 'btn small ghost fixed', onclick: () => remove(entry) }, 'Löschen'))),
    h('p', { class: 'small muted' }, 'Nach einem Export bleibt nur der neueste Eintrag auf dem iPhone. Die Windows-App zeigt alle als Verlauf.'));
}
