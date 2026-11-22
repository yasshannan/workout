// screens/workoutDetail.js — a finished workout that is not exported yet:
// look at it, correct it, or delete it. Every change is saved at once and goes
// into the next export.

import { h, fill, go, formatDateTime, formatDuration, toast, confirmSheet, uuid } from '../util.js';
import * as db from '../db.js';
import { summarize, saveWorkout, deleteWorkout, setTimings, entryTiming } from '../workout.js';
import { templateFromWorkout } from '../templates.js';
import { latestBodyWeightKg } from '../bodyWeights.js';
import { getExercise } from '../library.js';
import { setRows, workoutStats } from '../components.js';
import { openSetSheet } from '../dialogs/setSheet.js';

let root = null;
let workout = null;
let bodyWeightKg = null;

export async function render(container, workoutId) {
  root = container;
  workout = await db.get('workouts', workoutId);
  if (!workout || workout.deletedAt || !workout.finishedAt) { go('#/history'); return; }
  bodyWeightKg = await latestBodyWeightKg();
  paint();
}

async function saveAndPaint() {
  await saveWorkout(workout);
  paint();
}

function paint() {
  const timings = setTimings(workout);
  fill(root,
    h('div', { class: 'topbar' }, h('a', { class: 'btn ghost', href: '#/history' }, '‹ Verlauf')),
    h('h1', {}, formatDateTime(workout.startedAt)),
    h('div', { class: 'card' }, workoutStats(summarize(workout, bodyWeightKg))),
    h('label', { class: 'field' }, h('span', {}, 'Name'),
      h('input', { type: 'text', value: workout.name, onchange: (event) => { workout.name = event.target.value.trim() || 'Training'; saveWorkout(workout); } })),
    h('label', { class: 'field' }, h('span', {}, 'Notizen'),
      h('textarea', { value: workout.notes, onchange: (event) => { workout.notes = event.target.value; saveWorkout(workout); } })),

    workout.exercises.map((entry) => entryCard(entry, timings)),

    h('div', { class: 'stack' },
      h('button', { class: 'btn block secondary', onclick: async () => { await templateFromWorkout(workout); toast('Als Vorlage gespeichert'); } }, 'Als Vorlage speichern'),
      h('button', { class: 'btn block danger', onclick: removeWorkout }, 'Training löschen')));
}

function entryCard(entry, timings) {
  const exercise = getExercise(entry.exerciseId);
  // "Dauer 9:40 · Pause davor 3:12", both worked out from the timestamps
  const timing = entryTiming(entry, timings);
  const facts = [];
  if (timing.durationMs !== null) facts.push(`Dauer ${formatDuration(timing.durationMs)}`);
  if (timing.pauseBeforeMs !== null) facts.push(`Pause davor ${formatDuration(timing.pauseBeforeMs)}`);
  if (entry.supersetGroup) facts.push(`Supersatz ${entry.supersetGroup}`);

  return h('section', { class: 'card' },
    h('h3', {}, exercise ? exercise.name : 'Unbekannte Übung'),
    facts.length ? h('div', { class: 'last-time' }, facts.join(' · ')) : null,
    setRows(entry, exercise, timings, (set) => openSetSheet({
      set, exercise,
      onSave: (values) => { Object.assign(set, values); saveAndPaint(); },
      onDelete: () => { entry.sets = entry.sets.filter((s) => s.id !== set.id); saveAndPaint(); },
    })),
    h('label', { class: 'field' }, h('span', {}, 'Notizen zur Übung'),
      h('textarea', { value: entry.notes, onchange: (event) => { entry.notes = event.target.value; saveWorkout(workout); } })),
    h('div', { class: 'row' },
      h('button', { class: 'btn small secondary', onclick: () => addSet(entry, exercise) }, '+ Satz nachtragen'),
      h('button', { class: 'btn small ghost', onclick: () => removeEntry(entry) }, 'Übung entfernen')));
}

/** Add a set you forgot to log. It has no timestamps, so no duration or rest time. */
function addSet(entry, exercise) {
  openSetSheet({
    set: entry.sets[entry.sets.length - 1] || null,
    exercise,
    title: 'Satz nachtragen',
    saveLabel: 'Hinzufügen',
    onSave: (values) => {
      entry.sets.push({ id: uuid(), order: entry.sets.length, ...values, rpe: null, startedAt: null, completedAt: null, targetRestSec: null });
      saveAndPaint();
    },
  });
}

async function removeEntry(entry) {
  if (!await confirmSheet('Diese Übung mit ihren Sätzen aus dem Training entfernen?', 'Entfernen', { danger: true })) return;
  workout.exercises = workout.exercises.filter((e) => e.id !== entry.id);
  saveAndPaint();
}

async function removeWorkout() {
  if (!await confirmSheet('Dieses Training löschen?', 'Löschen', { danger: true })) return;
  await deleteWorkout(workout);
  toast('Training gelöscht');
  go('#/history');
}
