// screens/bodyWeights.js — the body-weight entries on the phone. New entries
// are added on the Start screen. After an export only the newest entry stays
// here; all of them are in the Windows app, which draws the graph.

import { h, fill, go, formatDateTime, confirmSheet } from '../util.js';
import { listBodyWeights, deleteBodyWeight } from '../bodyWeights.js';
import { formatWeight } from '../format.js';

export async function render(root) {
  const entries = await listBodyWeights();

  const remove = async (entry) => {
    if (!await confirmSheet(`Den Eintrag ${formatWeight(entry.weightKg)} löschen?`, 'Löschen', { danger: true })) return;
    await deleteBodyWeight(entry);
    go('#/bodyweights');
  };

  fill(root,
    h('div', { class: 'topbar' }, h('a', { class: 'btn ghost', href: '#/settings' }, '‹ Einstellungen')),
    h('h1', {}, 'Körpergewicht'),
    entries.length === 0 ? h('p', { class: 'muted' }, 'Noch keine Einträge. Trag dein Gewicht am Start-Bildschirm ein.') : null,
    entries.map((entry) => h('div', { class: 'list-item' },
      h('div', {},
        h('div', { class: 'title' }, formatWeight(entry.weightKg)),
        h('div', { class: 'sub' }, formatDateTime(entry.measuredAt))),
      h('button', { class: 'btn small ghost fixed', onclick: () => remove(entry) }, 'Löschen'))),
    h('p', { class: 'small muted' }, 'Nach einem Export bleibt nur der neueste Eintrag auf dem iPhone. Die Windows-App zeigt alle als Verlauf mit Wochenschnitt und Veränderung pro Woche.'));
}
