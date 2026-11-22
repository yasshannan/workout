// screens/templates.js — the list of workout templates ("Push Day", "Beine" …).

import { h, fill, go } from '../util.js';
import { listTemplates, saveTemplate, newTemplate } from '../templates.js';
import { getExercise } from '../library.js';

export async function render(root) {
  const templates = await listTemplates();

  const create = async () => {
    const template = await saveTemplate(newTemplate());
    go(`#/templates/${template.id}`);
  };

  fill(root,
    h('h1', {}, 'Vorlagen'),
    templates.length === 0
      ? h('p', { class: 'muted' }, 'Eine Vorlage ist eine Liste von Übungen mit Sätzen und Wiederholungen, aus der du ein Training startest.')
      : null,
    templates.map((template) => {
      const names = template.items.map((item) => getExercise(item.exerciseId)).filter(Boolean).map((exercise) => exercise.name);
      return h('a', { class: 'list-item', href: `#/templates/${template.id}` },
        h('div', {},
          h('div', { class: 'title' }, template.name),
          h('div', { class: 'sub' }, names.slice(0, 3).join(', ') + (names.length > 3 ? ` +${names.length - 3}` : ''))),
        h('div', { class: 'end' }, '›'));
    }),
    h('div', { class: 'spacer' }),
    h('button', { class: 'btn block', onclick: create }, '+ Neue Vorlage'));
}
