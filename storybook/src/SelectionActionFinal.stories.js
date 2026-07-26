import { el, selectionAction, pasteConfirmation, markerTemplateIcon } from './components.js';
import { lifecycleStage } from './lifecycle.js';

/**
 * Round 9: the approved final motion package on the two finalists in their
 * d-affordance form. Frequency-tiered principle: daily motion minimal,
 * teaching motion rare.
 *
 *   appear    directional settle: 6px slide from the selection + overshoot
 *   dismiss   first-run: flight to the menu-bar icon · daily: 0.15s fade
 *   copy      S2: check pop + half-strength tint flash · S9c: instant flip
 *             + one-frame chip blink; then the active dismiss mode at 0.6s
 *   paste     rises 4px, fades in 0.12s, holds, fades at 0.9s
 *   hover     keycap brightness only, 0.1s, zero geometry
 *   reduced   everything collapses to pure fades (macOS Reduce Motion)
 */
export default {
  title: 'Marker/Selection Action Final',
};

const CONTROLS = {
  argTypes: {
    mode: {
      control: 'select',
      options: ['daily', 'first-run'],
      description: 'Dismiss behavior: quiet fade vs teaching flight to the menu bar',
    },
    reduceMotion: {
      control: 'boolean',
      description: 'macOS Reduce Motion: pure fades in every phase',
    },
  },
  args: { mode: 'daily', reduceMotion: false },
};

const FINALISTS = {
  s2: { style: 'sa-s2 sa-s2-affd', fin: 'fin-s2' },
  s9c: { style: 'sa-s9c sa-s9c-affd', fin: 'fin-s9c' },
};

/** Restarts a one-shot animation class. */
function replayClass(node, cls) {
  node.classList.remove(cls);
  void node.offsetWidth;
  node.classList.add(cls);
}

/** Swap the badge's full-color app icon for the currentColor template icon. */
function useTemplateIcon(node, size) {
  for (const appIcon of node.querySelectorAll('.saved-badge .app-icon')) {
    appIcon.replaceWith(markerTemplateIcon(size));
  }
}

/** First-run teaching dismiss: collapse + two-axis arc to the status icon. */
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
  return 180;
}

/** Daily dismiss: quiet 0.15s fade. Also every dismiss under Reduce Motion. */
function fadeExit(pill) {
  pill.classList.add('fin-exit-fade');
  return 150;
}

function finalBuild(key, reduceMotion) {
  return (ctx) => {
    const { style, fin } = FINALISTS[key];
    // Copy plays its local feedback, then follows the dismiss mode 0.6s later.
    const pill = selectionAction({ onCopy: () => ctx.scheduleHide(600) });
    pill.classList.add(...style.split(' '), fin, 'fin-appear');
    if (reduceMotion) pill.classList.add('fin-reduced');
    useTemplateIcon(pill, 15);
    return pill;
  };
}

function finalPaste(key, reduceMotion) {
  return () => {
    const { style, fin } = FINALISTS[key];
    const paste = pasteConfirmation();
    paste.classList.add(...style.split(' '), fin, 'fin-paste');
    if (reduceMotion) paste.classList.add('fin-reduced');
    useTemplateIcon(paste, 17);
    return paste;
  };
}

function finalStage(key, { mode, reduceMotion }) {
  return lifecycleStage(finalBuild(key, reduceMotion), {
    menubar: true,
    exit: mode === 'first-run' && !reduceMotion ? flightExit : fadeExit,
    paste: finalPaste(key, reduceMotion),
    hint: reduceMotion
      ? 'Reduce Motion: every phase is a pure fade'
      : mode === 'first-run'
        ? 'Dismiss flies home to the menu bar (teaching, first ~10 runs)'
        : 'Dismiss is a quiet fade (daily default)',
  });
}

export const S2_Final = {
  name: 'S2 · Final',
  ...CONTROLS,
  render: (args) => finalStage('s2', args),
};

export const S9c_Final = {
  name: 'S9c · Final',
  ...CONTROLS,
  render: (args) => finalStage('s9c', args),
};

/** Both finalists stacked with shared controls — pick the winner by feel. */
export const FinalSideBySide = {
  ...CONTROLS,
  render: (args) => {
    const wrap = el('div', '');
    wrap.style.cssText = 'display:flex;flex-direction:column;gap:28px;';
    wrap.append(finalStage('s2', args), finalStage('s9c', args));
    return wrap;
  },
};
