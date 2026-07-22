import { popover, spotlightPanel, el } from './components.js';

export default {
  title: 'Marker/V2 Experiments',
};

/** Typography calm-down: one line per row, one optical size, muted chrome. */
export const CalmRows = {
  render: () => popover({ calm: true, selectedID: 1 }),
};

/** Current vs calm, side by side. */
export const BeforeAfter = {
  render: () => {
    const wrap = el('div', '', [
      popover({ selectedID: 1 }),
      popover({ calm: true, selectedID: 1 }),
    ]);
    wrap.style.cssText = 'display:flex;gap:40px;align-items:flex-start;';
    return wrap;
  },
};

/** Spotlight-style centered panel — proposed shell for the ⇧⌥V hotkey. */
export const SpotlightPanel = {
  render: () => spotlightPanel({ selectedID: 1 }),
  decorators: [
    (story) => {
      const holder = el('div', '', [story()]);
      holder.style.cssText = 'width:100%;display:flex;justify-content:center;padding-top:6vh;';
      return holder;
    },
  ],
};
