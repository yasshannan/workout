// exerciseEditor.js — create your own exercise, or change one: which muscles
// it trains and how much, how it is loaded, and the weight step. The muscles
// matter for the statistics: every set counts 1 set for each main muscle and
// 0.1 to 0.9 sets for each secondary muscle, depending on how much it works.

import { h, openOverlay, toast, confirmSheet } from '../util.js';
import { getMuscles, saveExercise, deleteExercise } from '../library.js';
import { MOVEMENTS, EQUIPMENT, MOVEMENT_LABELS, EQUIPMENT_LABELS, LOAD_TYPES, LOAD_MODES, UNITS } from '../schema.js';
import { chipGroup, stepper } from '../components.js';
import { parseNumber, formatNumber, weightStep } from '../format.js';

function select(options, value, onChange) {
  const el = h('select', { onchange: (event) => onChange(event.target.value) },
    options.map((option) => h('option', { value: option.id }, option.label)));
  el.value = value;
  return el;
}

/**
 * Open the editor. Pass null to create a new exercise.
 * onDone(saved exercise, or null after deleting) is called when it closes after a change.
 */
export function openExerciseEditor(exercise, { onDone = () => {} } = {}) {
  const isNew = !exercise;
  // Work on a copy: nothing changes unless Save is tapped.
  const draft = exercise
    ? { ...exercise, muscleShares: { ...(exercise.muscleShares || {}) } }
    : { name: '', movement: 'push', equipment: 'barbell', loadType: 'external', load: 'total', compound: true, primaryMuscles: [], secondaryMuscles: [], muscleShares: {} };
  if (!draft.load) draft.load = 'total';
  const primary = new Set(draft.primaryMuscles);
  const secondary = new Set(draft.secondaryMuscles);
  const muscleOptions = getMuscles().map((m) => ({ id: m.id, label: m.name }));
  const muscleLabel = (id) => (muscleOptions.find((m) => m.id === id) || { label: id }).label;

  // How much each secondary muscle counts: 0.1 to 0.9, in steps of 0.1
  const sharesBox = h('div', {});
  const paintShares = () => {
    const ids = [...secondary].filter((id) => !primary.has(id));
    sharesBox.replaceChildren(...ids.map((id) => {
      const share = draft.muscleShares[id] === undefined ? 0.5 : draft.muscleShares[id];
      return h('div', { class: 'share-row' },
        stepper({
          label: muscleLabel(id), value: formatNumber(share), step: 0.1, decimal: true,
          onChange: (text) => {
            const value = parseNumber(text);
            if (value > 0) draft.muscleShares[id] = Math.min(0.9, Math.max(0.1, Math.round(value * 10) / 10));
          },
        }));
    }));
    if (ids.length) sharesBox.prepend(h('p', { class: 'small muted' }, 'Wie viel zählt ein Satz für den Nebenmuskel? 0,1 = kaum, 0,9 = fast wie ein Hauptmuskel.'));
  };
  paintShares();

  // Only for body-weight exercises: how much of the body weight counts as load.
  const shareInput = h('input', {
    type: 'text', inputmode: 'numeric',
    value: String(Math.round((draft.bodyweightFraction === undefined ? 1 : draft.bodyweightFraction) * 100)),
  });
  const shareField = h('label', { class: 'field' },
    h('span', {}, 'Anteil des Körpergewichts als Last, in % – eine Schätzung (Klimmzug ≈ 100, Liegestütz ≈ 65, 0 = nur Sätze zählen)'),
    shareInput);
  const loadModeField = h('label', { class: 'field' }, h('span', {}, 'Gewicht wird angegeben als …'),
    select(LOAD_MODES, draft.load, (value) => { draft.load = value; }));
  const showLoadFields = () => {
    shareField.hidden = draft.loadType !== 'bodyweight';
    loadModeField.hidden = draft.loadType !== 'external';
  };
  showLoadFields();

  let stepText = formatNumber(weightStep(draft));

  openOverlay((close) => {
    const collect = () => {
      draft.name = draft.name.trim();
      if (!draft.name) { toast('Gib der Übung einen Namen'); return null; }
      if (primary.size === 0) { toast('Wähle mindestens einen Hauptmuskel'); return null; }
      draft.primaryMuscles = [...primary];
      draft.secondaryMuscles = [...secondary].filter((id) => !primary.has(id));   // never both
      const shares = {};
      for (const id of draft.secondaryMuscles) {
        if (draft.muscleShares[id] !== undefined && draft.muscleShares[id] !== 0.5) shares[id] = draft.muscleShares[id];
      }
      if (Object.keys(shares).length) draft.muscleShares = shares; else delete draft.muscleShares;
      if (draft.loadType === 'bodyweight') {
        const percent = parseNumber(shareInput.value);
        draft.bodyweightFraction = Number.isNaN(percent) ? 1 : Math.min(1, Math.max(0, percent / 100));
      } else {
        delete draft.bodyweightFraction;
      }
      if (draft.loadType !== 'external') draft.load = 'total';
      const step = parseNumber(stepText);
      if (step > 0) draft.weightStep = step;
      return draft;
    };

    const save = async () => {
      if (!collect()) return;
      const saved = await saveExercise(draft);
      close();
      onDone(saved);
    };

    // A copy for a second machine of the same kind (other gym, other brand):
    // records and "last time" are kept apart.
    const duplicate = async () => {
      if (!collect()) return;
      const copy = { ...draft, id: null, isCustom: true, name: `${draft.name} (2)` };
      delete copy.setup;
      const saved = await saveExercise(copy);
      close();
      toast(`Kopie „${saved.name}“ angelegt`);
      onDone(saved);
      openExerciseEditor(saved, { onDone });
    };

    const remove = async () => {
      if (!await confirmSheet(`„${draft.name}“ löschen? Trainings damit behalten ihre Daten.`, 'Löschen', { danger: true })) return;
      await deleteExercise(draft.id);
      close();
      onDone(null);
    };

    const compound = new Set(draft.compound ? ['yes'] : []);
    return [
      h('div', { class: 'topbar' },
        h('button', { class: 'btn ghost', onclick: close }, '‹ Abbrechen'),
        h('button', { class: 'btn small', onclick: save }, 'Speichern')),
      h('h1', {}, isNew ? 'Neue Übung' : 'Übung bearbeiten'),
      h('label', { class: 'field' }, h('span', {}, 'Name'),
        h('input', { type: 'text', value: draft.name, oninput: (event) => { draft.name = event.target.value; } })),
      h('h2', {}, 'Hauptmuskeln (1 Satz)'),
      chipGroup({ options: muscleOptions, selected: primary, multi: true, onChange: paintShares }),
      h('h2', {}, 'Nebenmuskeln'),
      chipGroup({ options: muscleOptions, selected: secondary, multi: true, onChange: paintShares }),
      sharesBox,
      h('label', { class: 'field' }, h('span', {}, 'Bewegung (für die Drück/Zieh-Balance)'),
        select(MOVEMENTS.map((id) => ({ id, label: MOVEMENT_LABELS[id] })), draft.movement, (value) => { draft.movement = value; })),
      h('label', { class: 'field' }, h('span', {}, 'Gerät'),
        select(EQUIPMENT.map((id) => ({ id, label: EQUIPMENT_LABELS[id] })), draft.equipment, (value) => { draft.equipment = value; })),
      h('label', { class: 'field' }, h('span', {}, 'Wie wird belastet?'),
        select(LOAD_TYPES, draft.loadType, (value) => { draft.loadType = value; showLoadFields(); })),
      loadModeField,
      shareField,
      h('label', { class: 'field' }, h('span', {}, 'Ein Satz zählt …'),
        select(UNITS, draft.unit || 'reps', (value) => { if (value === 'reps') delete draft.unit; else draft.unit = value; })),
      stepper({ label: 'Gewichtsschritt für − / + (kg)', value: stepText, step: 0.25, decimal: true, onChange: (text) => { stepText = text; } }),
      h('div', { class: 'setting' },
        h('div', { class: 'label' }, 'Mehrgelenksübung', h('div', { class: 'small muted' }, 'Nur diese bekommen ein geschätztes 1RM (Bankdrücken ja, Seitheben nein).')),
        h('div', { class: 'control' }, chipGroup({ options: [{ id: 'yes', label: 'Ja' }], selected: compound, multi: true, onChange: () => { draft.compound = compound.has('yes'); } }))),
      h('div', { class: 'spacer' }),
      isNew ? null : h('button', { class: 'btn secondary block', onclick: duplicate }, 'Als Kopie anlegen (z. B. andere Maschine)'),
      h('div', { class: 'spacer' }),
      // built-in exercises can be changed but not deleted
      !isNew && draft.isCustom ? h('button', { class: 'btn danger block', onclick: remove }, 'Übung löschen') : null,
    ];
  });
}
