import { el, icon, savedBadge } from './components.js';
import { lifecycleStage } from './lifecycle.js';

/**
 * V2 explorations for SelectionActionPresenter.swift — interaction-metaphor
 * directions for the capture pill (V4 Progress ring retired after review).
 * Every variant honors the native timing contract:
 *
 *   show ≤0.35s · auto-hide 2.4s · hover pauses the timer ·
 *   mouse-leave re-arms at 0.9s · dismiss instant.
 *
 * All motion is opacity/scale/position/stroke-trim — implementable in
 * SwiftUI (materials, springs, trim(from:to:)) without exotic effects.
 */
export default {
  title: 'Marker/Selection Action V2',
};

// ---------- shared builders ----------

/** Base material capsule shared by pill-shaped variants. */
function capsule(className, children) {
  return el('div', `v2-pill${className ? ` ${className}` : ''}`, children);
}

/** 28×28 copy button; onCopy fires once. */
function copyButton(onCopy) {
  const button = el('button', 'v2-copy', [icon('docOnDoc', 15)]);
  button.title = 'Copy to Clipboard';
  button.addEventListener('click', onCopy, { once: true });
  return button;
}

/** Green check that springs in where the copy button was. */
function poppedCheck(size = 13) {
  const check = el('span', 'v2-check-pop', [icon('checkmark', size)]);
  check.title = 'Copied to Clipboard';
  return check;
}

/** Applies a static board state ('hover' | 'copied') to a fresh variant. */
function applyState(node, state, complete) {
  if (state === 'hover') node.classList.add('force-hover');
  if (state === 'copied') complete();
  return node;
}

// ---------- variant builders ----------
// Each maker is (ctx, state) → node. `ctx` is the live lifecycle context
// (null on the static board); `state` is a board snapshot: rest/hover/copied.

/**
 * V1 “Ink dot” — an 8px green dot lands at the mouse-up point; it blooms
 * into the full pill only when the cursor moves toward it. Copy collapses
 * everything back into a popping green check chip. Ultra-quiet default.
 */
function makeInk(ctx, state) {
  const root = el('div', 'v2-ink', [el('span', 'ink-dot')]);
  const done = el('span', 'ink-done', [icon('checkmark', 11)]);
  done.title = 'Copied to Clipboard';
  const complete = () => root.classList.add('expand', 'copied');
  const pill = capsule('', [savedBadge(), el('span', 'v2-divider'), copyButton(complete)]);
  root.append(pill, done);

  if (ctx) {
    const onMove = (event) => {
      if (!root.isConnected) return ctx.stage.removeEventListener('mousemove', onMove);
      const rect = root.getBoundingClientRect();
      if (Math.hypot(event.clientX - (rect.left + 4), event.clientY - (rect.top + 4)) < 64) {
        root.classList.add('expand');
        ctx.stage.removeEventListener('mousemove', onMove);
      }
    };
    ctx.stage.addEventListener('mousemove', onMove);
    ctx.onCleanup(() => ctx.stage.removeEventListener('mousemove', onMove));
  } else if (state === 'hover' || state === 'copied') {
    root.classList.add('expand');
  }
  if (state === 'copied') complete();
  return root;
}

/**
 * V2 “Underline shimmer” — a hairline accent underline sweeps beneath the
 * selection with one specular shimmer, then settles; a small tab docked to
 * its end is the whole click target. Copy replays the sweep in green.
 */
function makeShimmer(ctx, state) {
  const root = el('div', 'v2-shimmer', [el('span', 'shimmer-line')]);
  const tab = el('button', 'shimmer-tab', [el('span', 'dot'), 'Copy']);
  tab.title = 'Copy to Clipboard';
  const complete = () => {
    root.classList.add('copied');
    tab.replaceChildren(icon('checkmark', 10), 'Copied');
  };
  tab.addEventListener('click', complete, { once: true });
  root.append(tab);
  return applyState(root, state, complete);
}

/**
 * V3 “Split capsule” — the pill lands with a soft spring; on hover its two
 * halves (saved | copy) part with a gap and the copy half fills accent.
 * Copy fills it green and the halves snap back together.
 */
function makeSplit(ctx, state) {
  const saved = el('span', 'half saved', [savedBadge()]);
  const copy = el('button', 'half copy', [icon('docOnDoc', 15)]);
  copy.title = 'Copy to Clipboard';
  const root = el('div', 'v2-split', [saved, copy]);
  const complete = () => {
    root.classList.add('copied');
    copy.replaceChildren(poppedCheck(13));
  };
  copy.addEventListener('click', complete, { once: true });
  return applyState(root, state, complete);
}

/**
 * V5 “Morph” — zero-UI at rest: just a green check chip (saved). Hovering
 * morphs it open to reveal the copy button; copy pops a check and tints
 * the whole chip softly green.
 */
function makeMorph(ctx, state) {
  const check = el('span', 'morph-check', [icon('checkmark', 10)]);
  check.title = 'Saved to Marker';
  const extra = el('span', 'morph-extra');
  const root = el('div', 'v2-morph', [check, extra]);
  let copy;
  const complete = () => {
    root.classList.add('copied');
    copy.replaceWith(poppedCheck(13));
  };
  copy = copyButton(complete);
  extra.append(el('span', 'v2-divider'), copy);
  return applyState(root, state, complete);
}

/**
 * V6 “Trace” — the signature move: a marker-pen hairline traces the pill’s
 * outline (SwiftUI trim), the material fades in behind it, the stroke
 * dissolves. Copy re-traces the outline in green while the check draws
 * itself stroke-by-stroke.
 */
function makeTrace(ctx, state) {
  const bg = el('span', 'trace-bg');
  const outline = el('span', 'trace-outline');
  outline.innerHTML = '<svg><rect x="0.75" y="0.75" rx="9.25" pathLength="1"/></svg>';
  const done = el('span', 'trace-done');
  done.innerHTML =
    '<svg width="15" height="15" viewBox="0 0 16 16">' +
    '<path d="M2.8 8.6 L6.3 12 L13.2 4.2" pathLength="1" fill="none" stroke="currentColor" ' +
    'stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  done.title = 'Copied to Clipboard';
  const root = el('div', 'v2-trace', [bg, outline]);
  let copy;
  const complete = () => {
    root.classList.add('copied');
    copy.replaceWith(done);
  };
  copy = copyButton(complete);
  root.append(el('span', 'trace-content', [savedBadge(), el('span', 'v2-divider'), copy]));
  return applyState(root, state, complete);
}

// ---------- stories ----------

export const InkDot = {
  name: 'V1 · Ink dot',
  render: () => lifecycleStage(makeInk, { hint: 'Move the cursor toward the dot to bloom it' }),
};

export const UnderlineShimmer = {
  name: 'V2 · Underline shimmer',
  render: () => lifecycleStage(makeShimmer, { place: 'underline', hint: 'The tab at the line’s end copies' }),
};

export const SplitCapsule = {
  name: 'V3 · Split capsule',
  render: () => lifecycleStage(makeSplit, { hint: 'Hover: the halves part · copy half fills accent' }),
};

export const Morph = {
  name: 'V5 · Morph',
  render: () => lifecycleStage(makeMorph, { hint: 'Hover the check chip to reveal Copy' }),
};

export const Trace = {
  name: 'V6 · Trace',
  render: () => lifecycleStage(makeTrace, { hint: 'The pill draws itself in; copy re-traces it green' }),
};

// ---------- comparison board ----------

const VARIANTS = [
  ['V1 Ink dot', 'proximity bloom, quietest', makeInk],
  ['V2 Underline shimmer', 'lives under the selection', makeShimmer],
  ['V3 Split capsule', 'halves part on hover', makeSplit],
  ['V5 Morph', 'zero-UI at rest', makeMorph],
  ['V6 Trace', 'draws itself like a marker pen', makeTrace],
];

/** All six side by side: rest, forced hover, and copied states. */
export const AllVariants = {
  render: () => {
    const board = el('div', 'v2-board');
    board.append(
      el('span', 'colhead'),
      ...['Rest', 'Hover', 'Copied'].map((t) => el('span', 'colhead', t)),
    );
    for (const [title, note, make] of VARIANTS) {
      const label = el('span', 'rowlabel', title);
      label.append(el('small', '', note));
      board.append(label);
      for (const state of ['rest', 'hover', 'copied']) {
        board.append(el('div', 'cell', [make(null, state)]));
      }
    }
    return board;
  },
};
