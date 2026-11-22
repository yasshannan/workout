// exercisePicker.js — the exercise library as a full-screen layer: search,
// filter by muscle group, pick an exercise or edit one.

import { h, fill, openOverlay } from '../util.js';
import { listExercises, getMuscles, muscleName } from '../library.js';
import { chipGroup } from '../components.js';
import { openExerciseEditor } from './exerciseEditor.js';

/**
 * Open the library.
 *   onPick(exercise)  called when an exercise is tapped; the layer then closes.
 *                     Without onPick the library is only for browsing and editing.
 */
export function openExercisePicker({ title = 'Übung hinzufügen', onPick = null } = {}) {
  let query = '';
  const muscleFilter = new Set();          // empty = every muscle
  const list = h('div', {});
  let closeLayer = () => {};

  const matches = (exercise) => {
    const text = query.trim().toLowerCase();
    if (text && !exercise.name.toLowerCase().includes(text)) return false;
    if (muscleFilter.size === 0) return true;
    const [muscle] = muscleFilter;
    return exercise.primaryMuscles.includes(muscle) || exercise.secondaryMuscles.includes(muscle);
  };

  const paintList = () => {
    const found = listExercises().filter(matches);
    fill(list,
      found.map((exercise) => h('div', { class: 'row' },
        h('button', {
          class: 'list-item',
          onclick: () => {
            if (onPick) { closeLayer(); onPick(exercise); }
            else openExerciseEditor(exercise, { onDone: paintList });
          },
        },
          h('div', {},
            h('div', { class: 'title' }, exercise.name, exercise.isCustom ? ' ★' : ''),
            h('div', { class: 'sub' }, exercise.primaryMuscles.map(muscleName).join(', ')))),
        // when picking, a separate button opens the editor
        onPick ? h('button', {
          class: 'btn ghost fixed', 'aria-label': `Bearbeiten: ${exercise.name}`,
          onclick: () => openExerciseEditor(exercise, { onDone: paintList }),
        }, 'Ändern') : null)),
      found.length === 0
        ? h('p', { class: 'muted center' }, listExercises().length === 0
            ? 'Noch keine Übungen. Lege eine mit „+ Neue Übung“ an.'
            : 'Keine Übung gefunden.')
        : null);
  };

  closeLayer = openOverlay((close) => [
    h('div', { class: 'topbar' },
      h('button', { class: 'btn ghost', onclick: close }, '‹ Zurück'),
      h('button', {
        class: 'btn small secondary',
        onclick: () => openExerciseEditor(null, {
          onDone: (saved) => {
            if (saved && onPick) { close(); onPick(saved); } else paintList();
          },
        }),
      }, '+ Neue Übung')),
    h('h1', {}, title),
    h('input', {
      type: 'search', placeholder: 'Übung suchen', 'aria-label': 'Übung suchen',
      oninput: (event) => { query = event.target.value; paintList(); },
    }),
    h('div', { class: 'spacer' }),
    chipGroup({
      options: getMuscles().map((m) => ({ id: m.id, label: m.name })),
      selected: muscleFilter, scroll: true, onChange: paintList,
    }),
    list,
  ]);
  paintList();
}
