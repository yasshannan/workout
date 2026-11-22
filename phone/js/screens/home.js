// screens/home.js — the first screen: start or resume a workout, templates,
// the export reminder, today's body weight, and the last workout.

import { h, fill, go, formatDuration, formatDate, daysAgoText, toast, platform, isInstalled, isToday } from '../util.js';
import { icon } from '../icons.js';
import * as W from '../workout.js';
import { listTemplates } from '../templates.js';
import { listHistory } from '../archive.js';
import { listBodyWeights, saveTodaysBodyWeight } from '../bodyWeights.js';
import { listMeasurements } from '../measurements.js';
import { exportStatus } from '../backup.js';
import { updateSettings, isLightMode } from '../settings.js';
import { formatWeight, parseNumber, roundKg } from '../format.js';
import { muscleRecovery, anyLoad } from '../recovery.js';
import { recoveryCard } from '../bodymap.js';

export async function render(root) {
  const active = await W.getActive();
  const templates = await listTemplates();
  const history = await listHistory();
  const status = await exportStatus();
  const bodyWeights = await listBodyWeights();
  const measurements = await listMeasurements();
  const recovery = await muscleRecovery();

  const start = async (template) => {
    await W.startWorkout(template);
    go('#/workout');
  };

  fill(root,
    h('div', { class: 'topbar' },
      h('h1', {}, icon('logo', 'logo-mark'), 'Training'),
      // the light/dark button of Main.qml in the Qt project, as a round iOS button
      h('button', {
        class: 'btn round secondary',
        'aria-label': isLightMode() ? 'Dunkles Design' : 'Helles Design',
        onclick: async () => { await updateSettings({ theme: isLightMode() ? 'dark' : 'light' }); go('#/home'); },
      }, icon(isLightMode() ? 'moon' : 'sun'))),

    isInstalled() ? null : h('div', { class: 'card notice small' }, installHint()),

    active
      ? h('button', { class: 'btn block big', onclick: () => go('#/workout') },
          'Training fortsetzen · ',
          h('span', { dataset: { since: active.workout.startedAt } }, formatDuration(Date.now() - Date.parse(active.workout.startedAt))))
      : h('button', { class: 'btn block big', onclick: () => start(null) }, 'Training starten'),

    active ? null : [
      h('h2', {}, 'Aus einer Vorlage starten'),
      templates.map((template) => h('button', { class: 'list-item', onclick: () => start(template) },
        h('div', { class: 'title' }, template.name),
        h('div', { class: 'end' }, `${template.items.length} Übungen ›`))),
      templates.length === 0
        ? h('p', { class: 'muted small' }, 'Noch keine Vorlagen. Lege eine unter „Vorlagen“ an oder speichere ein fertiges Training als Vorlage.')
        : null,
    ],

    // which muscles are still tired: helps to pick today's template
    anyLoad(recovery) ? [h('h2', {}, 'Erholung'), recoveryCard(recovery)] : null,

    h('h2', {}, 'Sicherung'),
    exportCard(status),

    h('h2', {}, 'Körpergewicht (freiwillig)'),
    bodyWeightCard(bodyWeights, measurements),

    history.length > 0 ? [h('h2', {}, 'Letztes Training'), lastWorkoutLine(history[0])] : null);
}

/** How to install the app: it is made for the iPhone's Home Screen. */
function installHint() {
  if (platform() === 'ios') {
    return [
      h('strong', {}, 'Auf den Home-Bildschirm legen: '),
      'in Safari auf „Teilen“ ', icon('share', 'inline-icon'), ' tippen, dann „Zum Home-Bildschirm“. ',
      'Nur so läuft sie im Vollbild und ohne Internet, und iOS löscht ihre Daten nicht nach 7 Tagen ohne Besuch.',
    ];
  }
  return 'Diese App ist fürs iPhone gemacht: Öffne diese Adresse in Safari auf deinem iPhone und lege sie auf den Home-Bildschirm.';
}

/**
 * "Letzter Export: vor 3 Tagen" and what is still waiting. After a week (or
 * with 3 workouts and no export yet) the card asks more clearly: until it is
 * exported, a workout exists only on this iPhone.
 */
function exportCard(status) {
  const waiting = status.pendingWorkouts;
  const days = status.lastExportAt ? (Date.now() - Date.parse(status.lastExportAt)) / 86400000 : null;
  const overdue = waiting > 0 && (days === null ? waiting >= 3 : days >= 7);
  return h('div', { class: overdue ? 'card overdue-card' : 'card', id: 'export-card' },
    overdue ? h('div', { class: 'overdue' }, '⚠︎ Zeit zu sichern') : null,
    h('div', {}, 'Letzter Export: ', h('strong', {}, status.lastExportAt ? daysAgoText(status.lastExportAt) : 'noch nie')),
    waiting > 0
      ? h('div', { class: 'status-warn' }, waiting === 1
        ? '1 Training ist nur auf diesem iPhone. Exportieren, um es zu sichern.'
        : `${waiting} Trainings sind nur auf diesem iPhone. Exportieren, um sie zu sichern.`)
      : h('div', { class: 'muted' }, 'Alle Trainings sind gesichert.'),
    h('div', { class: 'spacer' }),
    h('button', { class: waiting > 0 ? 'btn block' : 'btn block secondary', onclick: () => go('#/backup') }, 'Export / Import'));
}

/**
 * Body weight: one entry per day. Once today's weight is in, the card shows it
 * with a ✓ until tomorrow. "Korrigieren" fixes a typo in today's entry.
 * Below: the way to the body measurements.
 */
function bodyWeightCard(bodyWeights, measurements) {
  const last = bodyWeights[0];
  const today = last && isToday(last.measuredAt) ? last : null;
  const card = h('div', { class: 'card' });
  const lastMeasure = measurements[0];
  const measureLink = h('a', { class: 'link-row', href: '#/measurements' },
    h('span', {}, 'Körpermaße'),
    h('span', { class: 'muted small' }, lastMeasure ? `zuletzt ${daysAgoText(lastMeasure.measuredAt)} ›` : 'eintragen ›'));

  const showInput = (startValue) => {
    const input = h('input', { type: 'text', inputmode: 'decimal', placeholder: 'kg', 'aria-label': 'Körpergewicht in kg', value: startValue });
    const save = async () => {
      const value = parseNumber(input.value);
      if (!(value > 0)) return toast('Zuerst dein Körpergewicht eingeben');
      await saveTodaysBodyWeight(roundKg(value));
      toast('Körpergewicht gespeichert');
      go('#/home');
    };
    fill(card,
      h('div', { class: 'row' }, input, h('button', { class: 'btn fixed', onclick: save }, 'Speichern')),
      h('div', { class: 'spacer' }),
      h('div', { class: 'muted small' }, last && !today ? `Zuletzt: ${formatWeight(last.weightKg)}, ${daysAgoText(last.measuredAt)}` : 'Ein Eintrag pro Tag'),
      measureLink);
  };

  if (today) {
    fill(card,
      h('div', { class: 'row' },
        h('div', { class: 'today-weight' }, h('span', { class: 'saved-check' }, '✓ '), `Heute: ${formatWeight(today.weightKg)}`),
        h('button', { class: 'btn small ghost fixed', onclick: () => showInput(String(today.weightKg).replace('.', ',')) }, 'Korrigieren')),
      h('div', { class: 'muted small' }, 'Morgen kannst du es wieder eintragen.'),
      measureLink);
  } else {
    showInput('');
  }
  return card;
}

/** The newest workout. A saved (exported) one shows a ✓ and leads to History. */
function lastWorkoutLine({ archived, workout }) {
  const durationMs = archived ? workout.durationMs : W.summarize(workout, null).durationMs;
  return h('a', { class: 'list-item', href: archived ? '#/history' : `#/history/${workout.id}` },
    h('div', {},
      h('div', { class: 'title' }, workout.name),
      h('div', { class: 'sub' }, `${formatDate(workout.startedAt)} · ${daysAgoText(workout.startedAt)}`)),
    h('div', { class: archived ? 'end saved-check' : 'end' }, archived ? '✓' : `${formatDuration(durationMs)} ›`));
}
