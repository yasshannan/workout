// screens/backup.js — export the data to a file, or import a file.
//
// EXPORT IN THREE STEPS, so nothing can get lost:
//   1. "Exportieren" builds the file
//   2. "Datei teilen / speichern" opens the share sheet (OneDrive, Dateien …)
//   3. you check that the file arrived and confirm it. Only then do the
//      workouts leave the phone. Until then you can share it again as often as needed.
// A copy of the newest confirmed file stays on the phone, so it can be shared
// again if it gets lost later.

import { h, fill, go, daysAgoText, formatDateTime, toast } from '../util.js';
import * as db from '../db.js';
import { exportStatus, buildExport, deliverFile, markExported, lastExportFile, readImportFile, importData } from '../backup.js';
import { toggle } from '../components.js';

export async function render(root) {
  const status = await exportStatus();
  const neverExported = !status.lastExportAt;
  const isFreshInstall = (await db.getAll('workouts')).length + (await db.getAll('archive')).length === 0;
  const saved = await lastExportFile();

  // The phone only opens the share sheet straight from a tap, so nothing slow
  // may happen between the tap on "teilen" and the share itself.
  const exportArea = h('div', {});
  const prepare = async () => {
    const { data, file, exportedAt } = await buildExport();
    let shared = false;
    const share = async () => {
      const outcome = await deliverFile(file);
      if (outcome === 'cancelled') return toast('Teilen abgebrochen');
      shared = true;
      paintExport();
    };
    const confirm = async () => {
      const moved = await markExported(exportedAt, file);
      toast(moved > 0 ? `Gesichert ✓ ${moved} ${moved === 1 ? 'Training' : 'Trainings'} vom iPhone entfernt` : 'Gesichert ✓');
      go('#/backup');
    };
    const paintExport = () => fill(exportArea, h('div', { class: 'card' },
      h('h3', {}, shared ? 'Ist die Datei angekommen?' : 'Datei ist bereit'),
      h('p', { class: 'small muted' }, file.name),
      h('p', {}, `${data.workouts.length} Trainings, ${data.bodyWeights.length} Körpergewichte, ${data.measurements.length} Körpermaße · ${Math.max(1, Math.round(file.size / 1024))} KB`),
      shared
        ? [
            h('p', { class: 'small' }, 'Schau kurz in OneDrive oder „Dateien“ nach, ob sie dort ist. Erst nach deiner Bestätigung werden die Trainings vom iPhone entfernt.'),
            h('button', { class: 'btn block big', onclick: confirm }, '✓ Ja, angekommen'),
            h('div', { class: 'spacer' }),
            h('button', { class: 'btn block secondary', onclick: share }, 'Nein – nochmal teilen'),
          ]
        : h('button', { class: 'btn block big', onclick: share }, 'Datei teilen / speichern')));
    paintExport();
  };

  // Import: choose a file, show what is in it, then merge.
  const importArea = h('div', {});
  const fileInput = h('input', {
    type: 'file', accept: '.json,application/json', hidden: true,
    onchange: async () => {
      const file = fileInput.files[0];
      fileInput.value = '';                 // allows choosing the same file again later
      if (!file) return;
      try {
        showImportPreview(await readImportFile(file));
      } catch (error) {
        fill(importArea, h('div', { class: 'card notice' }, error.message));
      }
    },
  });
  const showImportPreview = (data) => {
    // after reinstalling, bring the settings back too; a file of templates only (shared/vorlagen-4-tage.json)
    // carries default settings, so it leaves yours alone
    const templatesOnly = !data.workouts.length && !data.bodyWeights.length && !(data.measurements || []).length && !data.exercises.length;
    let restoreSettings = isFreshInstall && !templatesOnly;
    const run = async () => {
      const result = await importData(data, { restoreSettings });
      fill(importArea, h('div', { class: 'card' },
        h('h3', {}, 'Import fertig'),
        h('p', {}, `${result.added} neu, ${result.updated} aktualisiert, ${result.unchanged} schon aktuell.`),
        h('p', { class: 'small muted' }, '„Letztes Mal“ und deine Rekorde enthalten jetzt die importierten Trainings.')));
    };
    fill(importArea, h('div', { class: 'card' },
      h('h3', {}, 'Diese Datei importieren?'),
      h('p', {}, `Exportiert am ${formatDateTime(data.exportedAt)}.`),
      h('p', {}, `${data.workouts.length} Trainings, ${data.templates.length} Vorlagen, ${data.bodyWeights.length} Körpergewichte.`),
      h('p', { class: 'small muted' }, 'Nichts wird doppelt angelegt. Die Trainings werden nur für „Letztes Mal“ und deine Rekorde verwendet; der Verlauf zeigt sie mit ✓.'),
      h('div', { class: 'setting' },
        h('div', { class: 'label' }, 'Auch die Einstellungen aus der Datei übernehmen'),
        h('div', { class: 'control' }, toggle(restoreSettings, (on) => { restoreSettings = on; }, 'Einstellungen übernehmen'))),
      h('div', { class: 'spacer' }),
      h('button', { class: 'btn block', onclick: run }, 'Importieren')));
  };

  const waiting = [
    status.pendingWorkouts ? `${status.pendingWorkouts} Trainings` : null,
    status.pendingBodyWeights ? `${status.pendingBodyWeights} Körpergewichte` : null,
    status.pendingMeasurements ? `${status.pendingMeasurements} Körpermaße` : null,
  ].filter(Boolean);

  fill(root,
    h('div', { class: 'topbar' }, h('a', { class: 'btn ghost', href: '#/home' }, '‹ Start')),
    h('h1', {}, 'Export / Import'),

    h('div', { class: 'card' },
      h('div', {}, 'Letzter Export: ', h('strong', {}, neverExported ? 'noch nie' : daysAgoText(status.lastExportAt))),
      h('div', { class: waiting.length ? 'status-warn' : 'muted' },
        waiting.length ? `Wartet: ${waiting.join(', ')}.` : 'Alles ist exportiert.')),

    // Always possible: the file also carries your exercises and templates.
    h('button', { class: 'btn block big', onclick: prepare }, 'Exportieren'),
    exportArea,
    h('p', { class: 'small muted' },
      'Speichere die Datei in OneDrive oder „Dateien“ (die Windows-App holt sie dort automatisch ab) oder schick sie dir per Mail. '
      + 'Nach deiner Bestätigung verlassen die Trainings das iPhone. Der Verlauf behält für jedes ein ✓, „Letztes Mal“ und deine Rekorde bleiben.'),

    saved ? [
      h('h2', {}, 'Letzter Export'),
      h('div', { class: 'card' },
        h('p', { class: 'small' }, `${saved.file.name} · ${formatDateTime(saved.exportedAt)}`),
        h('p', { class: 'small muted' }, 'Eine Kopie bleibt bis zum nächsten Export auf dem iPhone, falls die Datei verloren geht.'),
        h('button', { class: 'btn block secondary', onclick: async () => { const outcome = await deliverFile(saved.file); if (outcome !== 'cancelled') toast('Erneut geteilt'); } }, 'Letzten Export nochmal teilen')),
    ] : null,

    h('h2', {}, 'Import'),
    h('button', { class: 'btn block secondary', onclick: () => fileInput.click() }, 'Sicherungsdatei importieren'),
    fileInput,
    importArea);
}
