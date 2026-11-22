// setSheet.js — the small dialog for adding, correcting or deleting a set.
// Used on the workout screen and for workouts that are not exported yet.

import { h, openSheet, toast } from '../util.js';
import { setFields, draftFromSet, readDraft } from '../components.js';

/**
 * Open the dialog.
 *   set       the set to edit, or a template for a new set (may be null)
 *   onSave    called with { weightKg, reps, repsLeft, partials, type }
 *   onDelete  optional; without it there is no Delete button (for a new set)
 */
export function openSetSheet({ set, exercise, title = 'Satz bearbeiten', saveLabel = 'Speichern', onSave, onDelete = null }) {
  const draft = draftFromSet(set);
  openSheet((close) => [
    h('h3', {}, title),
    setFields(draft, exercise),
    h('div', { class: 'spacer' }),
    h('div', { class: 'row' },
      onDelete
        ? h('button', { class: 'btn danger', onclick: () => { close(); onDelete(); } }, 'Satz löschen')
        : h('button', { class: 'btn secondary', onclick: close }, 'Abbrechen'),
      h('button', {
        class: 'btn',
        onclick: () => {
          const values = readDraft(draft, exercise, toast);
          if (!values) return;
          close();
          onSave(values);
        },
      }, saveLabel)),
  ]);
}
