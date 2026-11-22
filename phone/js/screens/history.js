// screens/history.js — every finished workout, newest first.
//
//   "noch nicht exportiert"  still on the phone: tap it to see and correct it
//   ✓                        exported and removed from the phone to save space

import { h, fill, formatDate, formatDuration, formatThousands, openSheet } from '../util.js';
import { listHistory } from '../archive.js';
import { summarize } from '../workout.js';
import { formatSets } from '../format.js';

/** A short summary of a workout that is no longer on the phone. */
function showSaved(line) {
  openSheet((close) => [
    h('h3', {}, `✓ ${line.name}`),
    h('p', {}, `${formatDate(line.startedAt)} · ${formatDuration(line.durationMs)} · ${formatSets(line.workSets)} Sätze · ${formatThousands(line.volumeKg)} kg`),
    h('p', { class: 'muted' }, line.exerciseNames.join(', ')),
    h('p', { class: 'small muted' }, 'Dieses Training wurde exportiert. Die Details sind in der Export-Datei und in der Windows-App.'),
    h('button', { class: 'btn block secondary', onclick: close }, 'Schließen'),
  ]);
}

export async function render(root) {
  const lines = await listHistory();
  fill(root,
    h('h1', {}, 'Verlauf'),
    lines.length === 0 ? h('p', { class: 'muted' }, 'Noch keine fertigen Trainings.') : null,
    lines.map(({ archived, workout }) => {
      if (archived) {
        return h('button', { class: 'list-item saved', onclick: () => showSaved(workout) },
          h('div', {},
            h('div', { class: 'title' }, workout.name),
            h('div', { class: 'sub' }, `${formatDate(workout.startedAt)} · ${formatDuration(workout.durationMs)}`)),
          h('div', { class: 'end saved-check', 'aria-label': 'Gesichert' }, '✓'));
      }
      const summary = summarize(workout, null);
      return h('a', { class: 'list-item', href: `#/history/${workout.id}` },
        h('div', {},
          h('div', { class: 'title' }, workout.name),
          h('div', { class: 'sub' }, `${formatDate(workout.startedAt)} · ${formatDuration(summary.durationMs)} · noch nicht exportiert`)),
        h('div', { class: 'end' }, `${formatSets(summary.workSets)} Sätze ›`));
    }));
}
