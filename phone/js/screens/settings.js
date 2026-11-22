// screens/settings.js — all settings on one page.

import { h, fill, go, toast, isInstalled, formatDateTime, confirmSheet } from '../util.js';
import { APP_VERSION } from '../version.js';
import { lastUpdateBackup, restoreMissing } from '../safety.js';
import { settings, updateSettings } from '../settings.js';
import { chipGroup, toggle, stepper, settingRow } from '../components.js';
import { parseNumber } from '../format.js';
import { vibrate, vibrationSupported, wakeLockSupported } from '../device.js';
import { syncWakeLock } from '../workout.js';
import { getAppVersion, checkForUpdate, applyUpdateIfIdle } from '../update.js';
import { openExercisePicker } from '../dialogs/exercisePicker.js';
import { icon } from '../icons.js';

export async function render(root) {
  const s = settings();
  const version = await getAppVersion();
  const persisted = navigator.storage && navigator.storage.persisted ? await navigator.storage.persisted() : false;
  const backup = await lastUpdateBackup();

  const theme = chipGroup({
    options: [{ id: 'auto', label: 'Auto' }, { id: 'light', label: 'Hell' }, { id: 'dark', label: 'Dunkel' }],
    selected: new Set([s.theme]), required: true,
    onChange: (selected) => updateSettings({ theme: [...selected][0] }),
  });

  fill(root,
    h('h1', {}, 'Einstellungen'),
    settingRow('Farben', theme),

    h('h2', {}, 'Pausen-Timer'),
    stepper({
      label: 'Standard-Pause zwischen Sätzen (Sekunden)', value: s.defaultRestSec, step: 15,
      onChange: (text) => updateSettings({ defaultRestSec: Math.min(900, Math.max(15, Math.round(parseNumber(text)) || 15)) }),
    }),
    settingRow('Vibrieren, wenn die Pause vorbei ist',
      toggle(s.vibrateOn, (on) => updateSettings({ vibrateOn: on }), 'Vibrieren'),
      vibrationSupported()
        ? 'Kurzes Antippen, ab iOS 17.4. Bei gesperrtem iPhone blinkt nur die Leiste. Unten testen.'
        : 'Hier kein iPhone: die Pausenleiste blinkt stattdessen.'),
    h('div', { class: 'spacer' }),
    h('div', { class: 'row' },
      h('button', { class: 'btn secondary', onclick: vibrate }, 'Vibration testen'),
      // the real situation: the phone vibrates by itself after a while, without a tap
      h('button', { class: 'btn secondary', onclick: () => { toast('Vibriert in 5 Sekunden…'); setTimeout(vibrate, 5000); } }, 'Test in 5 s')),

    h('h2', {}, 'Langhantel'),
    stepper({
      label: 'Gewicht der leeren Stange (kg)', value: String(s.barKg).replace('.', ','), step: 2.5, decimal: true,
      onChange: (text) => { const kg = parseNumber(text); if (kg > 0) updateSettings({ barKg: kg }); },
    }),
    h('p', { class: 'small muted' }, 'Für den Scheibenrechner („Pro Seite: 20 + 10“) und die Aufwärmsätze.'),

    h('h2', {}, 'Bildschirm'),
    settingRow('Bildschirm im Training anlassen',
      toggle(s.keepScreenOn, async (on) => { await updateSettings({ keepScreenOn: on }); await syncWakeLock(); }, 'Bildschirm anlassen'),
      wakeLockSupported() ? 'Über das Home-Bildschirm-Symbol ab iOS 18.4.' : 'Braucht iOS 16.4 oder neuer.'),

    h('h2', {}, 'Daten'),
    h('div', { class: 'stack' },
      h('button', { class: 'btn block secondary', onclick: () => openExercisePicker({ title: 'Übungen' }) }, 'Übungen'),
      h('button', { class: 'btn block secondary', onclick: () => go('#/backup') }, 'Export / Import'),
      h('button', { class: 'btn block secondary', onclick: () => go('#/bodyweights') }, 'Körpergewicht-Einträge'),
      h('button', { class: 'btn block secondary', onclick: () => go('#/measurements') }, 'Körpermaße')),

    h('h2', {}, 'Schutz bei Updates'),
    updateProtection(backup),

    h('h2', {}, 'Info'),
    h('div', { class: 'card about' },
      icon('logo', 'about-logo'),
      h('div', {},
        h('div', { class: 'about-name' }, 'Training'),
        h('div', { class: 'small muted' }, `Version ${APP_VERSION} · fürs iPhone`),
        h('div', { class: 'small muted' }, 'Alle Daten bleiben auf diesem iPhone, bis du sie exportierst.'))),
    h('div', { class: 'card small' },
      h('div', {}, `App-Version: ${version}`),
      h('div', {}, `Vom Home-Bildschirm geöffnet: ${isInstalled() ? 'ja' : 'nein'}`),
      h('div', {}, `Speicher vor Aufräumen geschützt: ${persisted ? 'ja' : 'nein (iOS entscheidet selbst)'}`),
      h('div', { class: 'spacer' }),
      h('button', {
        class: 'btn small secondary',
        onclick: async () => {
          const reached = await checkForUpdate();
          toast(reached ? 'Geprüft. Eine neue Version installiert sich von selbst.' : 'Prüfen nicht möglich (offline oder lokal).');
          applyUpdateIfIdle();
        },
      }, 'Nach Update suchen')));
}

/** Updates never delete data; the copy from the last update can bring missing things back. */
function updateProtection(backup) {
  const versions = backup
    ? `vor dem Update ${backup.fromVersion ? `von ${backup.fromVersion} ` : ''}auf ${backup.toVersion || APP_VERSION}`
    : '';
  return h('div', { class: 'card small' },
    h('p', {}, 'Updates löschen keine Daten. Vor jedem Update legt die App auf dem iPhone eine Kopie von allem an.'),
    backup
      ? [
          h('p', { class: 'muted' }, `Letzte Kopie: ${formatDateTime(backup.createdAt)} (${versions}).`),
          h('button', {
            class: 'btn block secondary',
            onclick: async () => {
              const ok = await confirmSheet('Alles zurückholen, was in der Kopie ist, aber jetzt fehlt? '
                + 'Was da ist, bleibt unverändert. Auch seit dem Update Gelöschtes kommt zurück.', 'Zurückholen');
              if (!ok) return;
              const count = await restoreMissing();
              toast(count > 0 ? `${count} ${count === 1 ? 'Eintrag' : 'Einträge'} zurückgeholt` : 'Es fehlt nichts.');
              if (count > 0) setTimeout(() => location.reload(), 900);    // read everything again
            },
          }, 'Fehlende Daten zurückholen'),
        ]
      : h('p', { class: 'muted' }, 'Noch keine Kopie: sie entsteht beim nächsten Update. Nach einem Export ist die Exportdatei deine Sicherung.'));
}

