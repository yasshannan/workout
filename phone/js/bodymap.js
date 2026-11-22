// bodymap.js — a human figure, front and back, that shows which muscles a
// template trains:
//
//   dark   main muscle (primary)      light   only on the side (secondary)
//   faint  not trained at all
//
// HOW THE DRAWING WORKS
// Each view is 200 × 430 units. Only the LEFT half of the body is described
// (x from 0 to 100). The right half is the same shapes, mirrored at x = 100.
// Shapes in the middle of the body (abs, the traps on the back, the spine
// muscles) are listed under "center" and drawn once.
// Every shape belongs to one of the 26 muscle groups (the rotator cuff is only
// drawn from behind). Several shapes can
// belong to the same group: the quads, for example, are drawn as their three
// visible heads, but all three light up together.

import { h, openOverlay, daysAgoText } from './util.js';
import { getExercise, getMuscles, muscleShare, muscleName } from './library.js';
import { formatSets } from './format.js';

/* ---------- The body outline (no muscle, drawn first) ---------- */

const BODY_CENTER = [
  'M100,12 C111,12 118,22 118,35 C118,48 111,57 100,57 C89,57 82,48 82,35 C82,22 89,12 100,12 Z',  // head
  'M90,52 L110,52 L113,68 L87,68 Z',                                                                // neck
];
const BODY_LEFT = [
  // torso, left half: shoulder, armpit, waist, hip
  'M100,64 L88,64 C74,67 62,70 56,78 C50,86 50,98 53,106 L60,108 C64,136 70,160 72,182 C68,196 68,206 70,214 L100,216 Z',
  // upper arm and forearm
  'M53,96 C46,112 46,136 50,152 L66,154 C69,138 70,114 66,98 Z',
  'M49,152 C41,170 40,196 42,216 L55,218 C60,198 63,172 65,154 Z',
  // hand
  'M42,216 C38,224 38,236 42,244 C46,248 52,246 54,240 C56,232 56,224 55,218 Z',
  // thigh, lower leg, foot
  'M70,212 C66,244 68,292 74,322 L98,322 C100,292 101,246 100,216 Z',
  'M75,320 C70,348 72,384 78,410 L93,410 C97,384 99,348 98,320 Z',
  'M78,408 L93,408 C96,416 95,424 88,425 L79,425 C74,424 74,414 78,408 Z',
];

/* ---------- Muscles, front view ---------- */

const FRONT = {
  left: {
    neck: [
      // the muscle at the side of the neck (sternocleidomastoid)
      'M91,54 C92,60 95,65 99,69 L100,66 C97,62 95,58 94,54 Z',
    ],
    traps: [
      'M89,60 C83,65 75,69 66,73 L79,75 C85,71 89,67 91,63 Z',
    ],
    front_delts: [
      'M67,75 C60,77 56,85 56,96 C61,90 67,87 73,86 C74,80 71,76 67,75 Z',
    ],
    side_delts: [
      'M63,74 C55,76 50,84 50,98 C51,103 54,104 55,100 C54,89 57,80 63,74 Z',
    ],
    upper_chest: [
      // the upper (collarbone) part of the pectoral muscle …
      'M99,74 L77,76 C73,79 71,83 71,87 C80,84 90,83 99,84 Z',
    ],
    chest: [
      // … and its large middle and lower part
      'M99,86 C89,85 79,86 71,90 C69,98 70,104 75,109 C83,114 92,115 99,111 Z',
    ],
    obliques: [
      // serratus over the ribs (under the armpit), then the oblique along the waist
      'M72,110 C75,112 79,114 82,116 C80,119 76,121 73,121 C72,117 72,113 72,110 Z',
      'M73,124 C76,125 80,127 83,129 C81,131 78,133 74,133 C73,130 73,127 73,124 Z',
      'M75,136 C74,151 76,165 81,179 L86,179 C84,162 84,148 86,135 C82,135 78,135 75,136 Z',
    ],
    biceps: [
      'M58,102 C53,113 53,132 57,147 C61,149 64,147 66,141 C68,127 67,112 63,101 Z',
    ],
    brachialis: [
      // lies under the biceps; you see it at the outer side of the lower upper arm
      'M54,124 C51,132 51,142 54,151 C56,152 57,149 57,144 C57,136 56,129 54,124 Z',
    ],
    // The forearm from the front (palm forward): the brachioradialis along the
    // thumb side, the flexors (grip, bending the wrist) on the palm side.
    brachioradialis: [
      'M53,154 C46,167 44,190 46,211 L47,207 C50,190 55,172 58,156 Z',
    ],
    forearm_flexors: [
      'M58,156 C55,172 50,190 47,207 L46,211 C49,213 52,212 54,208 C59,190 62,170 61,156 Z',
    ],
    abductors: [
      // tensor fasciae latae: the outer front of the hip
      'M72,198 C69,210 69,224 71,238 C74,226 77,212 79,202 Z',
    ],
    adductors: [
      'M98,216 C92,230 89,252 90,274 C94,264 98,242 99,220 Z',
    ],
    quads: [
      // the three visible heads: outer (vastus lateralis), middle (rectus femoris), inner (vastus medialis)
      'M73,240 C69,266 71,294 79,316 C82,298 82,268 80,242 Z',
      'M84,214 C78,236 78,272 84,304 C88,304 92,272 92,240 C91,226 88,216 84,214 Z',
      'M91,278 C88,293 89,307 94,316 C98,310 98,297 96,284 Z',
    ],
    calves: [
      // the parts of the calf you see from the front, beside the shin
      'M76,332 C72,352 73,374 78,390 C80,374 80,352 79,334 Z',
      'M95,336 C98,352 98,368 95,382 C92,368 91,352 93,338 Z',
    ],
    tibialis: [
      // the muscle along the front of the shin
      'M82,330 C80,350 81,372 84,394 C87,376 88,352 87,332 Z',
    ],
  },
  center: {
    abs: [
      // the "six-pack": three rows on each side and the lower abs
      'M88,113 L99,113 L99,127 L88,127 Q86,120 88,113 Z', 'M101,113 L112,113 Q114,120 112,127 L101,127 Z',
      'M87,130 L99,130 L99,144 L87,144 Z', 'M101,130 L113,130 L113,144 L101,144 Z',
      'M87,147 L99,147 L99,161 L87,161 Z', 'M101,147 L113,147 L113,161 L101,161 Z',
      'M87,164 L99,164 L99,190 Q92,186 88,178 Z', 'M101,164 L113,164 L112,178 Q108,186 101,190 Z',
    ],
  },
};

/* ---------- Muscles, back view ---------- */

const BACK = {
  left: {
    neck: [
      // the neck muscles beside the spine, above the trapezius
      'M90,53 L96,53 C96,56 95,58 93,60 L89,62 Z',
    ],
    rear_delts: [
      'M66,76 C60,78 56,86 57,97 C62,92 68,90 74,88 C74,82 71,78 66,76 Z',
    ],
    side_delts: [
      'M63,74 C55,76 50,84 50,98 C51,103 54,104 55,100 C54,89 57,80 63,74 Z',
    ],
    upper_back: [
      // rhomboid (between the shoulder blades)
      'M97,86 C90,90 83,96 79,102 C85,108 91,112 97,116 Z',
    ],
    rotator_cuff: [
      // infraspinatus and teres minor, on the shoulder blade
      'M75,92 C69,96 66,102 68,109 C72,107 76,103 78,98 Z',
    ],
    lats: [
      'M68,110 C66,132 72,154 86,172 C90,170 94,162 96,152 C90,138 84,122 78,108 Z',
    ],
    obliques: [
      'M71,152 C71,168 73,182 77,194 L84,188 C80,176 78,164 76,152 Z',
    ],
    triceps: [
      // long and lateral head
      'M58,100 C53,112 53,134 58,148 C61,147 63,140 63,130 C63,116 62,106 60,100 Z',
      'M62,100 C64,110 65,124 64,140 C67,136 68,124 67,112 C67,106 65,102 62,100 Z',
    ],
    // The forearm from behind: the upper end of the brachioradialis at the
    // outer side, below it the extensors (straightening the wrist and fingers).
    brachioradialis: [
      'M53,154 C47,164 45,176 46,188 C49,178 53,166 57,157 Z',
    ],
    forearm_extensors: [
      'M57,157 C53,166 49,178 46,188 C45,196 45,204 46,211 C49,213 52,212 54,208 C59,190 62,170 61,156 Z',
    ],
    abductors: [
      // gluteus medius: the upper, outer part of the hip
      'M76,184 C72,190 70,198 72,206 C78,198 88,192 99,190 C93,184 84,182 76,184 Z',
    ],
    glutes: [
      'M99,193 C88,192 78,197 74,208 C72,224 80,236 99,238 Z',
    ],
    adductors: [
      'M98,240 C95,252 95,264 98,276 L99,242 Z',
    ],
    hamstrings: [
      // outer (biceps femoris) and inner (semitendinosus) hamstring
      'M75,242 C71,266 73,292 80,314 C84,294 86,266 86,244 Z',
      'M88,242 C86,266 88,292 94,314 C98,292 98,266 96,244 Z',
    ],
    calves: [
      // the two heads of the calf muscle
      'M77,328 C72,346 74,368 82,382 C86,366 87,344 86,330 Z',
      'M89,328 C88,346 90,368 96,378 C99,362 99,344 96,330 Z',
    ],
  },
  center: {
    traps: [
      // upper and middle trapezius as one diamond over the upper back
      'M100,54 C94,62 84,68 67,74 C80,80 90,94 96,122 L100,134 L104,122 C110,94 120,80 133,74 C116,68 106,62 100,54 Z',
    ],
    lower_back: [
      // the two columns of spine muscles (erector spinae)
      'M98,132 C92,144 91,164 93,186 L99,188 Z',
      'M102,132 C108,144 109,164 107,186 L101,188 Z',
    ],
  },
};

/* ---------- Working out the muscles of a template ---------- */

/**
 * For every muscle: how many sets the template gives it, and how.
 * Returns a Map: muscle id → { role: 'primary' | 'secondary' | 'none', sets, exercises }
 * A set counts 1 for a primary muscle and the exercise's share (usually ½) for
 * a secondary one. exercises: the names of the exercises that train it.
 */
export function templateMuscles(items) {
  const result = new Map(getMuscles().map((muscle) => [muscle.id, { role: 'none', sets: 0, exercises: [] }]));
  for (const item of items) {
    const exercise = getExercise(item.exerciseId);
    if (!exercise || exercise.unit === 'minutes') continue;     // cardio gives no muscle sets
    for (const [id, muscle] of result) {
      const share = muscleShare(exercise, id);
      if (share === 0) continue;
      muscle.sets += item.targetSets * share;
      muscle.exercises.push(exercise.name);
      if (share === 1) muscle.role = 'primary';
      else if (muscle.role === 'none') muscle.role = 'secondary';
    }
  }
  return result;
}

/* ---------- Drawing ---------- */

const MIRROR = 'matrix(-1 0 0 1 200 0)';     // flips a left-side shape to the right side

/** SVG text for one view. dx moves the whole view to the right. */
function viewSvg(view, muscles, dx) {
  const paths = (list, cssClass, muscleId = '') =>
    list.map((d) => `<path class="${cssClass}" d="${d}"${muscleId ? ` data-muscle="${muscleId}"` : ''}></path>`).join('');

  const muscleShapes = (side) => Object.entries(side).map(([id, list]) => {
    const info = muscles.get(id) || { role: 'none' };
    return paths(list, `bm-${info.role}`, id);
  }).join('');

  // Both halves of the body are drawn twice: first only their outline (a thick
  // line), then only their fill on top. The fill covers the inner half of every
  // line, so where the two halves meet in the middle no line is left over.
  const both = (svg) => `<g>${svg}</g><g transform="${MIRROR}">${svg}</g>`;
  return `<g transform="translate(${dx} 0)">
      ${paths(BODY_CENTER, 'bm-outline')}${both(paths(BODY_LEFT, 'bm-outline'))}
      ${paths(BODY_CENTER, 'bm-body')}${both(paths(BODY_LEFT, 'bm-body'))}
      ${both(muscleShapes(view.left))}
      ${muscleShapes(view.center)}
    </g>`;
}

const ROLE_TEXT = { primary: 'Hauptmuskel', secondary: 'nebenbei', none: 'nicht trainiert' };

/** "Obere Brust: 3 Sätze (Hauptmuskel) – Incline Dumbbell Press" */
function muscleInfo(id, muscles) {
  const info = muscles.get(id);
  if (!info) return '';
  const sets = info.role === 'none' ? '' : `: ${formatSets(info.sets)} Sätze`;
  const list = info.exercises.length ? ` – ${[...new Set(info.exercises)].join(', ')}` : '';
  return `${muscleName(id)}${sets} (${ROLE_TEXT[info.role]})${list}`;
}

/**
 * The figure as an element. Tapping a muscle shows its name, sets and
 * exercises in the line below and outlines it.
 *   views: 'both' (side by side) or 'front' / 'back' alone (for the big view)
 */
function figure(muscles, views, infoLine, describe = muscleInfo) {
  const wrap = h('div', { class: 'bodymap', role: 'img', 'aria-label': 'Muskeln' });
  const front = views !== 'back';
  const back = views !== 'front';
  const width = front && back ? 420 : 200;
  // The SVG is built only from the fixed shapes in this file, never from typed text.
  wrap.innerHTML = `<svg viewBox="0 0 ${width} 450" xmlns="http://www.w3.org/2000/svg">
      ${front ? viewSvg(FRONT, muscles, 0) : ''}
      ${back ? viewSvg(BACK, muscles, front ? 220 : 0) : ''}
      ${front ? '<text x="100" y="446" class="bm-label">Vorne</text>' : ''}
      ${back ? `<text x="${front ? 320 : 100}" y="446" class="bm-label">Hinten</text>` : ''}
    </svg>`;
  wrap.addEventListener('click', (event) => {
    const id = event.target.dataset ? event.target.dataset.muscle : null;
    wrap.querySelectorAll('.bm-picked').forEach((el) => el.classList.remove('bm-picked'));
    if (!id) return;
    wrap.querySelectorAll(`[data-muscle="${id}"]`).forEach((el) => el.classList.add('bm-picked'));
    infoLine.textContent = describe(id, muscles);
  });
  return wrap;
}

/** Front and back, each across the whole screen: twice as big as in the card. */
function openBigView(muscles) {
  openOverlay((close) => {
    const info = h('p', { class: 'bm-info' }, 'Tippe auf einen Muskel.');
    return [
      h('div', { class: 'topbar' }, h('button', { class: 'btn ghost', onclick: close }, '‹ Zurück')),
      h('h1', {}, 'Muskeln'),
      h('div', { class: 'bm-sticky' }, info),
      figure(muscles, 'front', info),
      figure(muscles, 'back', info),
    ];
  });
}

/** The card for the template editor: figure, legend and the muscles in words. */
export function bodyMapCard(items) {
  const muscles = templateMuscles(items);
  const info = h('p', { class: 'bm-info' }, 'Tippe auf einen Muskel für Details.');

  const byRole = (role) => getMuscles().filter((m) => muscles.get(m.id).role === role);
  const withSets = (group) => group.map((m) => `${m.name} ${formatSets(muscles.get(m.id).sets)}`).join(' · ');
  const primary = byRole('primary');
  const secondary = byRole('secondary');
  const untrained = byRole('none');

  return h('div', { class: 'card', id: 'template-bodymap' },
    h('div', { class: 'card-head' },
      h('h3', {}, 'Muskeln in dieser Vorlage'),
      h('button', { class: 'btn small ghost', onclick: () => openBigView(muscles) }, '⤢ Größer')),
    figure(muscles, 'both', info),
    info,
    h('div', { class: 'bm-legend' },
      h('span', {}, h('i', { class: 'bm-dot bm-primary' }), 'Hauptmuskel'),
      h('span', {}, h('i', { class: 'bm-dot bm-secondary' }), 'Nebenbei'),
      h('span', {}, h('i', { class: 'bm-dot bm-none' }), 'Nicht trainiert')),
    h('p', { class: 'small' }, h('strong', {}, 'Hauptmuskeln: '), primary.length ? withSets(primary) : '–'),
    h('p', { class: 'small' }, h('strong', {}, 'Nebenbei: '), secondary.length ? withSets(secondary) : '–'),
    h('p', { class: 'small muted' }, h('strong', {}, 'Nicht trainiert: '),
      untrained.length ? untrained.map((m) => m.name).join(', ') : 'keiner, alle Muskelgruppen sind dabei'),
    h('p', { class: 'small muted' }, 'Zahlen = Sätze pro Training: 1 für einen Hauptmuskel, für einen Nebenmuskel je nach Übung 0,1 bis 0,9.'));
}

/* ---------- Recovery (Home): which muscles are still tired ---------- */

const RECOVERY_TEXT = { tired: 'noch müde', recovering: 'erholt sich', fresh: 'frisch' };

/** "Brust: noch müde, zuletzt gestern (Bench Press, Machine Fly)" */
function recoveryInfo(id, recovery) {
  const info = recovery.get(id);
  if (!info) return '';
  const when = info.lastAt ? `, zuletzt ${daysAgoText(info.lastAt)}` : '';
  const list = info.exercises.length ? ` (${info.exercises.join(', ')})` : '';
  return `${muscleName(id)}: ${RECOVERY_TEXT[info.role]}${when}${list}`;
}

/** The card for Home. recovery comes from recovery.js (muscleRecovery). */
export function recoveryCard(recovery) {
  const info = h('p', { class: 'bm-info' }, 'Tippe auf einen Muskel für Details.');
  const names = (role) => getMuscles().filter((m) => recovery.get(m.id).role === role).map((m) => m.name);
  const tired = names('tired');
  const recovering = names('recovering');
  return h('div', { class: 'card', id: 'recovery' },
    h('p', { class: 'muted small' }, 'Geschätzt aus den letzten 72 Stunden: wähle heute lieber, was frisch ist.'),
    figure(recovery, 'both', info, recoveryInfo),
    info,
    h('div', { class: 'bm-legend' },
      h('span', {}, h('i', { class: 'bm-dot bm-tired' }), 'Noch müde'),
      h('span', {}, h('i', { class: 'bm-dot bm-recovering' }), 'Erholt sich'),
      h('span', {}, h('i', { class: 'bm-dot bm-fresh' }), 'Frisch')),
    h('p', { class: 'small' }, h('strong', {}, 'Noch müde: '), tired.length ? tired.join(', ') : '–'),
    h('p', { class: 'small' }, h('strong', {}, 'Erholt sich: '), recovering.length ? recovering.join(', ') : '–'),
    h('p', { class: 'small muted' }, 'Alles andere ist frisch. Gezählt werden die harten Sätze der letzten 72 Stunden, Nebenmuskeln anteilig.'));
}

/** All shapes, for the tests: { front: { muscleId: count }, back: {...} } */
export function shapeCounts() {
  const count = (view) => {
    const out = {};
    for (const [id, list] of Object.entries(view.left)) out[id] = (out[id] || 0) + list.length * 2;
    for (const [id, list] of Object.entries(view.center)) out[id] = (out[id] || 0) + list.length;
    return out;
  };
  return { front: count(FRONT), back: count(BACK) };
}
