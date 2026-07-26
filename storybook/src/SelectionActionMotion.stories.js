import { el, icon, selectionAction } from './components.js';
import { lifecycleStage } from './lifecycle.js';

/**
 * Motion as explanation. Six choreographies on the NEUTRAL native pill —
 * motion is the only variable. Each answers one question without words:
 * where did this come from, where does it live, what did copy do, and
 * where does it go. Added motion ≤0.4s per concept; the native timing
 * contract (2.4s hide · hover pause · 0.9s re-arm) is untouched. All
 * SwiftUI-plausible: position/scale/opacity keyframes; the arc flight is
 * a two-axis eased translate.
 */
export default {
  title: 'Marker/Selection Action Motion',
};

// ---------- small helpers ----------

/** Restarts a one-shot animation class. */
function replayClass(node, cls) {
  node.classList.remove(cls);
  void node.offsetWidth;
  node.classList.add(cls);
}

/** 1px line between two stage points; fades itself out. */
function tetherLine(ctx, x1, y1, x2, y2) {
  const line = el('span', 'sam-tether');
  const length = Math.hypot(x2 - x1, y2 - y1);
  const angle = Math.atan2(y2 - y1, x2 - x1);
  line.style.cssText = `left:${x1}px;top:${y1}px;width:${length}px;transform:rotate(${angle}rad);`;
  ctx.stage.append(line);
  setTimeout(() => line.remove(), 450);
  ctx.onCleanup(() => line.remove());
}

// ---------- concepts ----------
// Each is (ctx) → canonical pill; exits are separate (pill, ctx) → ms.

/**
 * M1 “Born from selection” — the pill unfolds from the mouse-up corner
 * (transform-origin at the anchor) while the selection flashes accent once
 * and a 1px tether briefly joins the two. Origin story made visible.
 */
function buildBorn(ctx) {
  const pill = selectionAction();
  pill.classList.add('sam-m1');
  replayClass(ctx.highlight, 'sam-flash');
  tetherLine(ctx, ctx.anchor.x + 2, ctx.anchor.y + 3, ctx.anchor.x + 11, ctx.anchor.y + 11);
  return pill;
}

/**
 * M2 “Ink absorb” — the highlight visibly drains while an ink drop travels
 * from the selection into the saved badge; the badge only lights up (check
 * pops) when the drop lands. “Your text flowed into Marker.”
 */
function buildAbsorb(ctx) {
  const pill = selectionAction();
  pill.classList.add('sam-m2');
  replayClass(ctx.highlight, 'sam-drain');

  const drop = el('span', 'sam-ink-dot');
  const x0 = ctx.anchor.x - 6;
  const y0 = ctx.anchor.y + 2;
  drop.style.cssText = `left:${x0}px;top:${y0}px;`;
  ctx.stage.append(drop);
  const dx = ctx.anchor.x + 10 + 18 - x0; // saved badge center
  const dy = ctx.anchor.y + 10 + 16 - y0;
  requestAnimationFrame(() => {
    drop.style.transform = `translate(${dx}px, ${dy}px) scale(0.5)`;
    drop.style.opacity = '0';
  });
  setTimeout(() => {
    drop.remove();
    pill.classList.add('sam-landed');
  }, 300);
  ctx.onCleanup(() => drop.remove());
  return pill;
}

/**
 * M3 “Into the menu bar” — the dismiss teaches: the pill collapses to a
 * dot that arcs up to the Marker status icon, which blips once. Explains
 * WHERE selections are saved. Copy hands off the same way shortly after.
 */
function buildToMenubar(ctx) {
  const pill = selectionAction({ onCopy: () => ctx.scheduleHide(600) });
  pill.classList.add('sam-m3');
  return pill;
}

/** M3's exit: collapse + two-axis arc flight to the status icon. */
function flightExit(pill, ctx) {
  pill.classList.add('sam-collapse');
  const box = ctx.stage.getBoundingClientRect();
  const from = pill.getBoundingClientRect();
  const to = ctx.statusIcon.getBoundingClientRect();
  const x0 = from.left - box.left + from.width / 2;
  const y0 = from.top - box.top + from.height / 2;

  const dot = el('span', 'sam-fly-dot');
  dot.style.cssText =
    `left:${x0}px;top:${y0}px;` +
    `--dx:${to.left - box.left + 14 - x0}px;--dy:${to.top - box.top + 11 - y0}px;`;
  ctx.stage.append(dot);
  requestAnimationFrame(() => dot.classList.add('go'));
  setTimeout(() => {
    dot.remove();
    replayClass(ctx.statusIcon, 'sam-blip');
  }, 360);
  return 180; // the empty pill is gone well before the dot lands
}

/**
 * M4 “+1 tick” — a tiny “+1” chip rises off the badge and fades, like a
 * counter increment: added to history, one of many. Quietest narrative.
 */
function buildTick(ctx) {
  const pill = selectionAction();
  pill.classList.add('sam-m4');
  pill.append(el('span', 'sam-plus', '+1'));
  return pill;
}

/**
 * M5 “Copy handoff” — on copy, a ghost of the doc icon lifts out of the
 * button and snaps to the cursor, dissolving as it arrives; the check
 * appears underneath. “It’s on your clipboard now”, made physical.
 */
function buildHandoff(ctx) {
  let pill;
  const onCopy = () => {
    const box = ctx.stage.getBoundingClientRect();
    const rect = pill.getBoundingClientRect();
    const x0 = rect.right - box.left - 24;
    const y0 = rect.top - box.top + 8;
    const ghost = el('span', 'sam-ghost', [icon('docOnDoc', 15)]);
    ghost.style.cssText =
      `left:${x0}px;top:${y0}px;` +
      `--gx:${ctx.anchor.x + 1 - x0}px;--gy:${ctx.anchor.y + 2 - y0}px;`;
    ctx.stage.append(ghost);
    requestAnimationFrame(() => ghost.classList.add('go'));
    setTimeout(() => ghost.remove(), 360);
    ctx.onCleanup(() => ghost.remove());
  };
  pill = selectionAction({ onCopy });
  pill.classList.add('sam-m5');
  return pill;
}

/**
 * M6 “Directional settle” — arrival slides 6px FROM the selection with a
 * soft overshoot; the exit retreats back TOWARD it. Both motion vectors
 * point at the source text, so origin and destination read spatially.
 */
function buildDirectional(ctx) {
  const pill = selectionAction();
  pill.classList.add('sam-m6');
  return pill;
}

/** M6's exit: retreat toward the selection and fade. */
function departExit(pill) {
  pill.classList.add('sam-m6-exit');
  return 250;
}

// ---------- stories ----------

const CONCEPTS = [
  ['M1 · Born from selection', () =>
    lifecycleStage(buildBorn, { hint: 'Unfolds from the mouse-up corner, tethered to the text' })],
  ['M2 · Ink absorb', () =>
    lifecycleStage(buildAbsorb, { hint: 'The highlight drains into the badge; check pops on landing' })],
  ['M3 · Into the menu bar', () =>
    lifecycleStage(buildToMenubar, {
      menubar: true,
      exit: flightExit,
      hint: 'Wait for the hide — it flies home. Copy triggers the same flight',
    })],
  ['M4 · +1 tick', () =>
    lifecycleStage(buildTick, { hint: 'A counter increment: one selection of many' })],
  ['M5 · Copy handoff', () =>
    lifecycleStage(buildHandoff, { hint: 'Click copy — the doc ghost snaps to your cursor' })],
  ['M6 · Directional settle', () =>
    lifecycleStage(buildDirectional, {
      exit: departExit,
      hint: 'Arrives from the selection; on timeout it retreats toward it',
    })],
];

export const M1_BornFromSelection = { name: CONCEPTS[0][0], render: CONCEPTS[0][1] };
export const M2_InkAbsorb = { name: CONCEPTS[1][0], render: CONCEPTS[1][1] };
export const M3_IntoTheMenuBar = { name: CONCEPTS[2][0], render: CONCEPTS[2][1] };
export const M4_PlusOneTick = { name: CONCEPTS[3][0], render: CONCEPTS[3][1] };
export const M5_CopyHandoff = { name: CONCEPTS[4][0], render: CONCEPTS[4][1] };
export const M6_DirectionalSettle = { name: CONCEPTS[5][0], render: CONCEPTS[5][1] };

/** All six stages side by side, each with its own Replay. */
export const AllMotion = {
  render: () => {
    const grid = el('div', 'sam-grid');
    for (const [title, make] of CONCEPTS) {
      grid.append(el('div', 'sam-cell', [el('div', 'sam-label', title), make()]));
    }
    return grid;
  },
};
