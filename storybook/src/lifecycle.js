import { el, markerTemplateIcon } from './components.js';

/**
 * Shared replayable capture stage for selection-action stories.
 * Not a stories file — imported by SelectionActionVariants.stories.js and
 * SelectionActionStyles.stories.js.
 */

/** Fake cursor arrow, tip at (x, y). */
export function cursor(x, y) {
  const c = el('span', '');
  c.style.cssText = `position:absolute;left:${x}px;top:${y}px;z-index:2;pointer-events:none;`;
  c.innerHTML =
    '<svg width="17" height="22" viewBox="0 0 17 22"><path d="M1 1 L1 16.5 L5.2 12.8 L8 19.5 L10.6 18.4 L7.8 11.8 L13.4 11.4 Z" fill="#fff" stroke="#000" stroke-width="1.1" stroke-linejoin="round"/></svg>';
  return c;
}

/**
 * Replayable capture stage with the native timing contract wired in:
 * auto-hide 2.4s, hover pauses, leave re-arms at 0.9s. `build(ctx)` returns
 * the variant node; ctx = { stage, anchor, highlight, statusIcon, scheduleHide, onCleanup }.
 * Options:
 *   place: 'underline' anchors under the selection’s last line.
 *   menubar: true adds a fake menu bar with the Marker status icon (ctx.statusIcon).
 *   exit: (pill, ctx) => ms — plays a custom dismissal; the pill is removed
 *     after the returned duration instead of instantly.
 *   paste: () => node — adds a "Replay paste" button; the node shows centered
 *     above the cursor, holds 0.9s, then fades out (.v2-paste-out class).
 */
export function lifecycleStage(build, { place = 'beside', hint = '', menubar = false, exit = null, paste = null } = {}) {
  const stage = el('div', `v2-stage${menubar ? ' has-menubar' : ''}`);
  let statusIcon = null;
  if (menubar) {
    statusIcon = el('span', 'status-icon active', [markerTemplateIcon(15)]);
    statusIcon.title = 'Marker';
    stage.append(el('div', 'menubar', [statusIcon]));
  }
  const para = el('div', '');
  para.innerHTML =
    'Select text. It’s already saved. ' +
    '<span class="v2-highlight">Marker keeps every selection you make</span>, so copying becomes optional.';
  stage.append(para);
  const highlight = para.querySelector('.v2-highlight');
  const anchor = { x: 330, y: 78 };
  stage.append(cursor(anchor.x, anchor.y));

  let pill = null;
  let hideTimer = null;
  let cleanups = [];
  let ctx = null;
  let exiting = false;

  const clearPill = () => {
    clearTimeout(hideTimer);
    hideTimer = null;
    exiting = false;
    for (const fn of cleanups) fn();
    cleanups = [];
    pill?.remove();
    pill = null;
  };

  const hide = () => {
    if (!pill || exiting) return;
    if (exit) {
      exiting = true;
      hideTimer = setTimeout(clearPill, exit(pill, ctx) ?? 0);
    } else {
      clearPill();
    }
  };

  const scheduleHide = (delay) => {
    if (exiting) return;
    clearTimeout(hideTimer);
    hideTimer = setTimeout(hide, delay);
  };

  const show = () => {
    clearPill();
    ctx = { stage, anchor, highlight, statusIcon, scheduleHide, onCleanup: (fn) => cleanups.push(fn) };
    pill = build(ctx);
    const lines = highlight.isConnected ? highlight.getClientRects() : [];
    if (place === 'underline' && lines.length) {
      const line = lines[lines.length - 1];
      const box = stage.getBoundingClientRect();
      pill.style.cssText =
        `position:absolute;left:${line.left - box.left}px;` +
        `top:${line.bottom - box.top + 2}px;width:${line.width}px;`;
    } else {
      pill.style.cssText = `position:absolute;left:${anchor.x + 10}px;top:${anchor.y + 10}px;`;
    }
    pill.addEventListener('mouseenter', () => clearTimeout(hideTimer));
    pill.addEventListener('mouseleave', () => scheduleHide(900));
    stage.append(pill);
    scheduleHide(2400);
  };

  const replay = el('button', 'replay', 'Replay capture');
  replay.addEventListener('click', show);
  stage.append(replay);

  if (paste) {
    let pasteWrap = null;
    let pasteTimer = null;
    const showPaste = () => {
      clearTimeout(pasteTimer);
      pasteWrap?.remove();
      // Same anchor rule as the capture pill: one learned position for
      // both popups. Wrapper stays so the node's animations own transform.
      pasteWrap = el('span', '');
      pasteWrap.style.cssText =
        `position:absolute;left:${anchor.x + 10}px;top:${anchor.y + 10}px;`;
      pasteWrap.append(paste());
      stage.append(pasteWrap);
      pasteTimer = setTimeout(() => {
        pasteWrap?.firstChild?.classList.add('v2-paste-out');
        pasteTimer = setTimeout(() => {
          pasteWrap?.remove();
          pasteWrap = null;
        }, 160);
      }, 900);
    };
    const pasteBtn = el('button', 'replay replay-paste', 'Replay paste');
    pasteBtn.addEventListener('click', showPaste);
    stage.append(pasteBtn);
  }

  if (hint) stage.append(el('span', 'hint', hint));

  requestAnimationFrame(show); // wait for mount so underline placement can measure
  return stage;
}
