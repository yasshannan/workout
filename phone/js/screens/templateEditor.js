// screens/templateEditor.js — edit one template. Every change is saved at once.
//
// Each exercise is one short line ("3 × 8–12 · Pause 2:00"); tapping it opens
// its settings: sets, reps (a fixed number or a range like 8–12), rest, and
// whether it is a superset with the next exercise. The ≡ handle moves it.
// At the top, a figure shows which muscles the template trains.

import { h, fill, go, confirmSheet, toast, formatDuration } from '../util.js';
import { getTemplate, saveTemplate, deleteTemplate, newItem, applySupersetLinks, linkedWithNext } from '../templates.js';
import { getActive, startWorkout } from '../workout.js';
import { getExercise } from '../library.js';
import { parseNumber, formatRepTarget, repUnit, UNIT_LONG } from '../format.js';
import { stepper, chipGroup } from '../components.js';
import { bodyMapCard } from '../bodymap.js';
import { openExercisePicker } from '../dialogs/exercisePicker.js';

let root = null;
let template = null;
let hasActiveWorkout = false;
let openIndex = -1;              // which item shows its settings (-1: none)

export async function render(container, templateId) {
  root = container;
  template = await getTemplate(templateId);
  if (!template || template.deletedAt) { go('#/templates'); return; }
  hasActiveWorkout = Boolean(await getActive());
  openIndex = -1;
  paint();
}

/** Save and draw everything again (after a change of structure). */
async function saveAndPaint() {
  await saveTemplate(template);
  paint();
}

/** Save after a small change (typing): redraw only the figure and the item's summary line. */
function saveQuietly(index) {
  saveTemplate(template);
  const figure = document.getElementById('template-bodymap');
  if (figure) figure.replaceWith(bodyMapCard(template.items));
  const summary = document.querySelector(`[data-summary="${index}"]`);
  if (summary) summary.textContent = summaryText(template.items[index]);
}

const toCount = (text) => Math.max(1, Math.round(parseNumber(text)) || 1);

/** "3 × 8–12 · Pause 2:00" */
function summaryText(item) {
  const reps = formatRepTarget(item.repsMin, item.repsMax);
  return `${item.targetSets} × ${reps || '?'} · Pause ${formatDuration((item.restSec || 0) * 1000)}`;
}

function paint() {
  fill(root,
    h('div', { class: 'topbar' }, h('a', { class: 'btn ghost', href: '#/templates' }, '‹ Vorlagen')),
    h('label', { class: 'field' }, h('span', {}, 'Name der Vorlage'),
      h('input', { type: 'text', value: template.name, onchange: (event) => { template.name = event.target.value.trim() || 'Vorlage'; saveTemplate(template); } })),

    template.items.length > 0 ? bodyMapCard(template.items) : null,
    template.items.length > 0 ? h('h2', {}, 'Übungen') : null,
    h('div', { class: 'item-list', id: 'item-list' }, template.items.map((item, index) => itemCard(item, index))),
    template.items.length === 0 ? h('p', { class: 'muted' }, 'Noch keine Übungen.') : null,

    h('div', { class: 'stack' },
      h('button', {
        class: 'btn block secondary',
        onclick: () => openExercisePicker({
          onPick: (exercise) => { template.items.push(newItem(exercise.id)); openIndex = template.items.length - 1; saveAndPaint(); },
        }),
      }, '+ Übung hinzufügen'),
      h('button', {
        class: 'btn block', disabled: hasActiveWorkout || template.items.length === 0,
        onclick: async () => { await startWorkout(template); go('#/workout'); },
      }, hasActiveWorkout ? 'Erst das laufende Training beenden' : 'Training starten'),
      h('button', { class: 'btn block danger', onclick: remove }, 'Vorlage löschen')));
}

/** Reps: "Wdh." (one number, repsMin = repsMax) or "Bereich" (repsMin < repsMax). */
function repsEditor(item, index) {
  const unit = repUnit(getExercise(item.exerciseId));
  const isRange = Boolean(item.repsMin) && item.repsMax > item.repsMin;
  const mode = new Set([isRange ? 'range' : 'reps']);

  const fields = isRange
    ? h('div', { class: 'row' },
        stepper({ label: 'Von', value: item.repsMin, step: 1, onChange: (text) => {
          item.repsMin = toCount(text);
          if (item.repsMax < item.repsMin) item.repsMax = item.repsMin;
          saveQuietly(index);
        } }),
        stepper({ label: 'Bis', value: item.repsMax, step: 1, onChange: (text) => {
          item.repsMax = Math.max(item.repsMin, toCount(text));
          saveQuietly(index);
        } }))
    : stepper({ label: UNIT_LONG[unit], value: item.repsMin || '', step: 1, onChange: (text) => {
        item.repsMin = toCount(text);
        item.repsMax = item.repsMin;
        saveQuietly(index);
      } });

  return h('div', {},
    chipGroup({
      options: unit === 'reps'
        ? [{ id: 'reps', label: 'Feste Wdh.' }, { id: 'range', label: 'Wdh.-Bereich' }]
        : [{ id: 'reps', label: 'Feste Zeit' }, { id: 'range', label: 'Zeit-Bereich' }],
      selected: mode, required: true, fill: true,
      onChange: (selected) => {
        if (selected.has('range')) {
          item.repsMin = item.repsMin || 8;
          item.repsMax = item.repsMin + 4;           // e.g. 8 → 8–12
        } else {
          item.repsMin = item.repsMin || 10;
          item.repsMax = item.repsMin;
        }
        saveAndPaint();
      },
    }),
    fields,
    isRange ? h('p', { class: 'small muted' }, 'Schaffst du in allen Sätzen die obere Zahl, schlägt die App beim nächsten Mal mehr Gewicht vor.') : null);
}

function itemCard(item, index) {
  const exercise = getExercise(item.exerciseId);
  const isOpen = index === openIndex;
  const linkedAbove = index > 0 && linkedWithNext(template, index - 1);
  const handle = h('button', { class: 'drag-handle', 'aria-label': 'Verschieben', type: 'button' }, '≡');
  dragToReorder(handle, index);

  const head = h('div', { class: 'item-head' },
    handle,
    h('button', { class: 'item-title', type: 'button', onclick: () => { openIndex = isOpen ? -1 : index; paint(); } },
      h('span', { class: 'title' }, exercise ? exercise.name : 'Unbekannte Übung'),
      h('span', { class: 'sub', dataset: { summary: String(index) } }, summaryText(item))),
    h('span', { class: 'chevron', 'aria-hidden': 'true' }, isOpen ? '▴' : '▾'));

  const links = template.items.map((_, i) => linkedWithNext(template, i));
  const body = isOpen ? h('div', { class: 'item-body' },
    stepper({ label: 'Sätze', value: item.targetSets, step: 1, onChange: (text) => { item.targetSets = toCount(text); saveQuietly(index); } }),
    repsEditor(item, index),
    stepper({
      label: 'Pause zwischen den Sätzen (Sekunden)', value: item.restSec, step: 15,
      onChange: (text) => { item.restSec = Math.max(0, Math.round(parseNumber(text)) || 0); saveQuietly(index); },
    }),
    index < template.items.length - 1 ? h('div', { class: 'setting' },
      h('div', { class: 'label' }, 'Supersatz mit der nächsten Übung', h('div', { class: 'small muted' }, 'Ohne Pause abwechselnd; die Pause kommt nach der Runde.')),
      h('div', { class: 'control' }, h('button', {
        class: links[index] ? 'chip on' : 'chip', type: 'button',
        onclick: () => { links[index] = !links[index]; applySupersetLinks(template, links); saveAndPaint(); },
      }, links[index] ? 'An' : 'Aus'))) : null,
    h('button', { class: 'btn small ghost', onclick: () => { template.items.splice(index, 1); openIndex = -1; applySupersetLinks(template, links.filter((_, i) => i !== index)); saveAndPaint(); } }, 'Aus der Vorlage entfernen'))
    : null;

  return h('section', { class: `card template-item${linkedAbove ? ' linked' : ''}${isOpen ? ' open' : ''}`, dataset: { index: String(index) } },
    item.supersetGroup && !linkedAbove ? h('div', { class: 'tag' }, `Supersatz ${item.supersetGroup}`) : null,
    head, body);
}

/**
 * Drag the ≡ handle up or down to move an exercise. The card follows the
 * finger; when it is let go, the new order is saved. Superset links stay with
 * the position (an exercise moved away leaves its superset).
 */
function dragToReorder(handle, index) {
  handle.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    const card = handle.closest('.template-item');
    const list = document.getElementById('item-list');
    const cards = [...list.children];
    const startY = event.clientY;
    const middles = cards.map((c) => { const r = c.getBoundingClientRect(); return r.top + r.height / 2; });
    let target = index;
    card.classList.add('dragging');
    handle.setPointerCapture(event.pointerId);

    const move = (e) => {
      const dy = e.clientY - startY;
      card.style.transform = `translateY(${dy}px)`;
      const y = middles[index] + dy;
      target = middles.filter((m, i) => i !== index && m < y).length;
    };
    const end = () => {
      handle.removeEventListener('pointermove', move);
      handle.removeEventListener('pointerup', end);
      handle.removeEventListener('pointercancel', end);
      card.classList.remove('dragging');
      card.style.transform = '';
      if (target === index) return;
      const [item] = template.items.splice(index, 1);
      item.supersetGroup = null;
      template.items.splice(target, 0, item);
      // keep the other supersets: re-letter from the pairs that are still next to each other
      applySupersetLinks(template, template.items.map((it, i) => Boolean(it.supersetGroup && template.items[i + 1] && template.items[i + 1].supersetGroup === it.supersetGroup)));
      openIndex = -1;
      saveAndPaint();
    };
    handle.addEventListener('pointermove', move);
    handle.addEventListener('pointerup', end);
    handle.addEventListener('pointercancel', end);
  });
}

async function remove() {
  if (!await confirmSheet(`Die Vorlage „${template.name}“ löschen?`, 'Löschen', { danger: true })) return;
  await deleteTemplate(template);
  toast('Vorlage gelöscht');
  go('#/templates');
}
