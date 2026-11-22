// screens/finish.js — shown right after a workout: summary, notes and the
// reminder to export.

import { h, fill, go, toast } from '../util.js';
import * as db from '../db.js';
import { summarize, saveWorkout } from '../workout.js';
import { templateFromWorkout } from '../templates.js';
import { latestBodyWeightKg } from '../bodyWeights.js';
import { exportStatus } from '../backup.js';
import { workoutStats } from '../components.js';

export async function render(root, workoutId) {
  const workout = await db.get('workouts', workoutId);
  if (!workout) { go('#/home'); return; }
  const summary = summarize(workout, await latestBodyWeightKg());
  const status = await exportStatus();
  const waiting = status.pendingWorkouts;

  fill(root,
    h('h1', {}, 'Training fertig'),
    h('div', { class: 'card' }, workoutStats(summary)),
    h('label', { class: 'field' }, h('span', {}, 'Name'),
      h('input', {
        type: 'text', value: workout.name,
        onchange: async (event) => { workout.name = event.target.value.trim() || 'Training'; await saveWorkout(workout); },
      })),
    h('label', { class: 'field' }, h('span', {}, 'Notizen'),
      h('textarea', { value: workout.notes, onchange: async (event) => { workout.notes = event.target.value; await saveWorkout(workout); } })),

    h('div', { class: 'card notice' },
      h('h3', {}, 'Daten sichern'),
      h('p', {}, `Trainings bleiben auf dem iPhone, bis du sie exportierst. ${waiting} ${waiting === 1 ? 'Training wartet' : 'Trainings warten'}.`),
      h('p', { class: 'small muted' }, 'Nach dem Export und deiner Bestätigung verlassen sie das iPhone, um Platz zu sparen. Der Verlauf zeigt dann ein ✓.'),
      h('button', { class: 'btn block', onclick: () => go('#/backup') }, 'Jetzt exportieren')),

    h('div', { class: 'stack' },
      h('button', { class: 'btn block secondary', onclick: async () => { await templateFromWorkout(workout); toast('Als Vorlage gespeichert'); } }, 'Als Vorlage speichern'),
      h('button', { class: 'btn block secondary', onclick: () => go('#/home') }, 'Später')));
}
