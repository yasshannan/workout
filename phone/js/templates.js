// templates.js — workout templates ("Push Day"): a list of exercises with
// sets, rest and a rep target, to start a workout from.
//
// A template item: { exerciseId, targetSets, restSec, repsMin, repsMax, supersetGroup }
//   fixed reps:  repsMin = repsMax (10 / 10)
//   rep range:   repsMin < repsMax (8 / 12)
//   superset:    items next to each other with the same letter ('A') are done as a superset

import * as db from './db.js';
import { uuid, nowIso } from './util.js';
import { settings } from './settings.js';
import { SUPERSET_CHANGE_SEC } from './workout.js';

export async function listTemplates() {
  const all = await db.getAll('templates');
  return all.filter((t) => !t.deletedAt).sort((a, b) => a.name.localeCompare(b.name));
}

export function getTemplate(id) {
  return db.get('templates', id);
}

export async function saveTemplate(template) {
  template.updatedAt = nowIso();
  await db.put('templates', template);
  return template;
}

export function newTemplate(name = 'Neue Vorlage') {
  return { id: uuid(), name, items: [], updatedAt: nowIso(), deletedAt: null };
}

/** A new template item with sensible defaults: 3 sets of 10. */
export function newItem(exerciseId) {
  return { exerciseId, targetSets: 3, restSec: settings().defaultRestSec, repsMin: 10, repsMax: 10 };
}

/**
 * Give the items of a template their superset letters from "linked with the
 * next item" marks: links[i] true means item i and item i + 1 form a superset.
 */
export function applySupersetLinks(template, links) {
  let letter = 0;
  template.items.forEach((item, i) => {
    const linkedToPrevious = i > 0 && links[i - 1];
    if (!linkedToPrevious && links[i]) letter++;
    item.supersetGroup = links[i] || linkedToPrevious ? 'ABCDEFGHIJKLMNOP'[letter - 1] || 'Z' : null;
  });
}

/** Is item i linked with the next item as a superset? */
export function linkedWithNext(template, i) {
  const item = template.items[i];
  const next = template.items[i + 1];
  return Boolean(item && next && item.supersetGroup && item.supersetGroup === next.supersetGroup);
}

/** Templates are only marked as deleted, so the Windows app learns about it too. */
export async function deleteTemplate(template) {
  template.deletedAt = nowIso();
  await saveTemplate(template);
}

/** Turn a workout into a template: same exercises, working sets, rest, and the reps that were done. */
export async function templateFromWorkout(workout) {
  const template = newTemplate(workout.name);
  for (const entry of workout.exercises) {
    if (entry.sets.length === 0) continue;
    const workSets = entry.sets.filter((set) => set.type === 'work');
    const reps = workSets.map((set) => set.reps);
    // the real rest, not the short change time inside a superset
    const rests = entry.sets.map((set) => set.targetRestSec || 0).filter((sec) => sec > SUPERSET_CHANGE_SEC);
    template.items.push({
      exerciseId: entry.exerciseId,
      targetSets: Math.max(1, workSets.length),
      restSec: rests.length ? Math.max(...rests) : settings().defaultRestSec,
      supersetGroup: entry.supersetGroup || null,
      // the same reps in every set → a fixed number, otherwise the range that was done
      repsMin: reps.length ? Math.min(...reps) : 10,
      repsMax: reps.length ? Math.max(...reps) : 10,
    });
  }
  return saveTemplate(template);
}
