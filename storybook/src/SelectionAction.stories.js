import { el, selectionAction, pasteConfirmation } from './components.js';

/**
 * SelectionActionPresenter.swift — the floating pill beside the mouse-up
 * point, and the icon-only paste confirmation above the cursor.
 *
 * Native timings:
 *   show: alpha 0→1, 0.12s ease-out · auto-hide 2.4s · dismiss instant
 *   hover keeps it alive · leave → hide after 0.9s
 *   paste confirmation: same show, auto-hide 0.9s
 */
export default {
  title: 'Marker/Selection Action',
};

export const Saved = {
  render: () => selectionAction(),
};

export const Copied = {
  render: () => selectionAction({ copied: true }),
};

export const PasteConfirmation = {
  render: () => pasteConfirmation(),
};

/** Fake cursor arrow, tip at (x, y). */
function cursor(x, y) {
  const c = el('span', '');
  c.style.cssText = `position:absolute;left:${x}px;top:${y}px;z-index:2;pointer-events:none;`;
  c.innerHTML =
    '<svg width="17" height="22" viewBox="0 0 17 22"><path d="M1 1 L1 16.5 L5.2 12.8 L8 19.5 L10.6 18.4 L7.8 11.8 L13.4 11.4 Z" fill="#fff" stroke="#000" stroke-width="1.1" stroke-linejoin="round"/></svg>';
  return c;
}

/**
 * Full lifecycle with native timings, replayable. The pill appears beside
 * a fake mouse-up point (gap 10), fades in over 0.12s, auto-hides after
 * 2.4s. Hover pauses the timer; leaving re-arms it at 0.9s. Copy flips
 * the button to a green check without touching the timer.
 */
export const CaptureLifecycle = {
  render: () => {
    const stage = el('div', 'lifecycle-stage');
    stage.style.cssText =
      'position:relative;width:560px;height:240px;border-radius:12px;' +
      'background:color-mix(in srgb, var(--popover-material) 55%, transparent);' +
      'padding:28px 32px;font-size:14px;line-height:1.6;color:var(--label);box-sizing:border-box;';

    const para = el('div', '');
    para.innerHTML =
      'Select text. It’s already saved. ' +
      '<span style="background:color-mix(in srgb, var(--accent) 30%, transparent);border-radius:2px;">' +
      'Marker keeps every selection you make</span>, so copying becomes optional.';
    stage.append(para);

    // Mouse-up lands at the end of the highlighted run.
    const anchorX = 330;
    const anchorY = 78;
    stage.append(cursor(anchorX, anchorY));

    let pill = null;
    let hideTimer = null;

    const clearPill = () => {
      clearTimeout(hideTimer);
      hideTimer = null;
      pill?.remove();
      pill = null;
    };

    const scheduleHide = (delay) => {
      clearTimeout(hideTimer);
      hideTimer = setTimeout(clearPill, delay);
    };

    const show = () => {
      clearPill();
      pill = selectionAction();
      pill.classList.add('enter');
      pill.style.cssText = `position:absolute;left:${anchorX + 10}px;top:${anchorY + 10}px;`;
      pill.addEventListener('mouseenter', () => clearTimeout(hideTimer));
      pill.addEventListener('mouseleave', () => scheduleHide(900));
      stage.append(pill);
      scheduleHide(2400);
    };

    const replay = el('button', 'replay', 'Replay capture');
    replay.style.cssText =
      'position:absolute;left:32px;bottom:20px;border:none;border-radius:6px;' +
      'padding:4px 12px;font:inherit;font-size:12px;color:#fff;background:var(--accent);cursor:default;';
    replay.addEventListener('click', show);
    stage.append(replay);

    show();
    return stage;
  },
};

/** Gesture paste: confirmation pops centered above the cursor for 0.9s. */
export const PasteLifecycle = {
  render: () => {
    const stage = el('div', '');
    stage.style.cssText =
      'position:relative;width:560px;height:200px;border-radius:12px;' +
      'background:color-mix(in srgb, var(--popover-material) 55%, transparent);';

    const anchorX = 280;
    const anchorY = 120;
    stage.append(cursor(anchorX, anchorY));

    let pill = null;
    let hideTimer = null;

    const show = () => {
      clearTimeout(hideTimer);
      pill?.remove();
      pill = pasteConfirmation();
      pill.classList.add('enter');
      // Centered above the anchor, 14pt gap.
      pill.style.cssText = `position:absolute;left:${anchorX}px;top:${anchorY - 14}px;transform:translate(-50%,-100%);`;
      stage.append(pill);
      hideTimer = setTimeout(() => {
        pill?.remove();
        pill = null;
      }, 900);
    };

    const replay = el('button', 'replay', 'Replay paste');
    replay.style.cssText =
      'position:absolute;left:24px;bottom:20px;border:none;border-radius:6px;' +
      'padding:4px 12px;font:inherit;font-size:12px;color:#fff;background:var(--accent);cursor:default;';
    replay.addEventListener('click', show);
    stage.append(replay);

    show();
    return stage;
  },
};
