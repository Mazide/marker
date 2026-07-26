import { el, selectionAction, pasteConfirmation, markerTemplateIcon } from './components.js';
import { lifecycleStage } from './lifecycle.js';

/**
 * Pure styling on the CANONICAL native pill — layout and behavior are
 * [saved badge] | divider | [copy → green check], untouched.
 *
 * Round 7 state: seven survivors, ranked by owner preference (favorites
 * first). Each also ships a/b/c refinement iterations exploring its own
 * parameter space — see the per-style “Iterations” boards. All variants
 * are SwiftUI-implementable and honor the native timing contract.
 */
export default {
  title: 'Marker/Selection Action Styles',
};

/** Ranked survivors. Order drives AllStyles rows and lifecycle options. */
const STYLES = [
  ['sa-s2', 'S2 Ink / HUD', 'dark chip in both themes, pro-quiet'],
  ['sa-t10', 'T10 Warm paper', 'cream card, letterpress copied stamp'],
  ['sa-s1', 'S1 Liquid Glass', 'lensing translucency, specular rim'],
  ['sa-s9c', 'S9c OLED white', 'true black, crisp white, no glow'],
  ['sa-s9d', 'S9d E-paper', 'ink on paper, inversion refresh'],
  ['sa-s12', 'S12 Monospace minimal', 'mono glyphs, native material'],
  ['sa-t2', 'T2 Linear glow', 'matte dark; light lives in the action'],
  ['sa-s13', 'S13 Catppuccin', 'catppuccin terminal, CLI spinner energy'],
];

/* Cut across rounds 5–7: S3–S8, S9a, S9b, S10, S11, T1, T3–T9. */

/** Styles whose chips render the badge as a monochrome template icon. */
const TEMPLATE_STYLES = new Set(['sa-s2', 'sa-s9c', 'sa-s9d', 'sa-t2', 'sa-s13']);

/** Swap the badge's full-color app icon for the currentColor template icon. */
function useTemplateIcon(node, size) {
  for (const appIcon of node.querySelectorAll('.saved-badge .app-icon')) {
    appIcon.replaceWith(markerTemplateIcon(size));
  }
}

// ---------- builders ----------

/** Canonical pill in a style (space-separated modifiers allowed, e.g.
 * 'sa-s2 sa-s2-a'); state: 'rest' | 'hover' (forced) | 'copied'. */
function styledPill(style, state = 'rest') {
  const pill = selectionAction({ copied: state === 'copied' });
  pill.classList.add(...style.split(' '));
  if (style.split(' ').some((cls) => TEMPLATE_STYLES.has(cls))) useTemplateIcon(pill, 15);
  if (state === 'hover') pill.classList.add('force-hover');
  return pill;
}

/** Icon-only paste confirmation sibling in the same style. */
function styledPaste(style) {
  const paste = pasteConfirmation();
  paste.classList.add(...style.split(' '));
  if (style.split(' ').some((cls) => TEMPLATE_STYLES.has(cls))) useTemplateIcon(paste, 17);
  return paste;
}

const STATES = [
  ['rest', 'Rest'],
  ['hover', 'Hover'],
  ['copied', 'Copied'],
  ['paste', 'Paste confirm'],
];

/** One style across all four states, labeled. */
function styleStrip(style) {
  const strip = el('div', 'sa-strip');
  for (const [, label] of STATES) strip.append(el('span', 'colhead', label));
  for (const [state] of STATES) {
    strip.append(el('div', 'cell', [state === 'paste' ? styledPaste(style) : styledPill(style, state)]));
  }
  return strip;
}

/** Labeled board: [label, classes, note] rows × the four states. */
function stateBoard(rows) {
  const board = el('div', 'v2-board sa-board');
  board.append(el('span', 'colhead'), ...STATES.map(([, t]) => el('span', 'colhead', t)));
  for (const [label, cls, note] of rows) {
    const rowLabel = el('span', 'rowlabel', label);
    rowLabel.append(el('small', '', note));
    board.append(rowLabel);
    for (const [state] of STATES) {
      board.append(el('div', 'cell', [state === 'paste' ? styledPaste(cls) : styledPill(cls, state)]));
    }
  }
  return board;
}

/** Iterations board: base style as row "current", plus a/b/c refinements. */
function iterationBoard(style, variants) {
  return stateBoard([['current', style, 'shipping reference'], ...variants]);
}

// ---------- per-style strips (the "current" reference) ----------

export const S2_InkHUD = { name: 'S2 · Ink / HUD', render: () => styleStrip('sa-s2') };
export const T10_WarmPaper = { name: 'T10 · Warm paper', render: () => styleStrip('sa-t10') };
export const S1_LiquidGlass = { name: 'S1 · Liquid Glass', render: () => styleStrip('sa-s1') };
export const S9c_OLEDWhite = { name: 'S9c · OLED white', render: () => styleStrip('sa-s9c') };
export const S9d_EPaper = { name: 'S9d · E-paper', render: () => styleStrip('sa-s9d') };
export const S12_MonospaceMinimal = { name: 'S12 · Monospace minimal', render: () => styleStrip('sa-s12') };
export const T2_LinearGlow = { name: 'T2 · Linear glow', render: () => styleStrip('sa-t2') };
export const S13_Catppuccin = { name: 'S13 · Catppuccin', render: () => styleStrip('sa-s13') };

// ---------- S13 rice skins (kitty-theme style palette swaps) ----------

const RICE_SKINS = ['rice-catppuccin', 'rice-gruvbox', 'rice-tokyonight', 'rice-rosepine'];

/** Terminal pane with a swappable palette skin — flip the macOS theme too. */
export const S13_Rice = {
  name: 'S13 · Rice',
  argTypes: {
    skin: {
      control: 'select',
      options: RICE_SKINS,
      description: 'Palette skin over the same terminal pane base',
    },
  },
  args: { skin: 'rice-catppuccin' },
  render: ({ skin }) => styleStrip(`sa-s13 ${skin}`),
};

/** All four skins side by side; hovered panes take the accent border. */
export const RiceBoard = {
  name: 'S13 · Rice board',
  render: () => stateBoard([
    ['catppuccin', 'sa-s13 rice-catppuccin', 'mocha / latte'],
    ['gruvbox', 'sa-s13 rice-gruvbox', 'retro warm, hard contrast'],
    ['tokyonight', 'sa-s13 rice-tokyonight', 'storm blue / day'],
    ['rosepine', 'sa-s13 rice-rosepine', 'soho vibes / dawn'],
  ]),
};

// ---------- iterations: each survivor's own parameter space ----------

export const S2_Iterations = {
  name: 'S2 · Iterations',
  render: () => iterationBoard('sa-s2', [
    ['a · tone', 'sa-s2 sa-s2-a', 'warmer, deeper black'],
    ['b · geometry', 'sa-s2 sa-s2-b', 'full capsule, tighter padding'],
    ['c · feedback', 'sa-s2 sa-s2-c', 'whole-chip green tint on copied'],
  ]),
};

export const T10_Iterations = {
  name: 'T10 · Iterations',
  render: () => iterationBoard('sa-t10', [
    ['a · palette', 'sa-t10 sa-t10-a', 'paler cream, deeper terracotta'],
    ['b · shadow', 'sa-t10 sa-t10-b', 'crisper, closer to the page'],
    ['c · copied', 'sa-t10 sa-t10-c', 'terracotta ink spreads behind the check'],
  ]),
};

export const S1_Iterations = {
  name: 'S1 · Iterations',
  render: () => iterationBoard('sa-s1', [
    ['a · thickness', 'sa-s1 sa-s1-a', 'heavier lensing, thicker rim'],
    ['b · radius', 'sa-s1 sa-s1-b', '14px instead of near-capsule'],
    ['c · hover', 'sa-s1 sa-s1-c', 'specular slide instead of swell'],
  ]),
};

export const S9c_Iterations = {
  name: 'S9c · Iterations',
  render: () => iterationBoard('sa-s9c', [
    ['a · letterbox', 'sa-s9c sa-s9c-a', 'shorter, wider, cinematic'],
    ['b · hierarchy', 'sa-s9c sa-s9c-b', 'the action is the brightest glyph'],
    ['c · state flip', 'sa-s9c sa-s9c-c', 'two crisp frames instead of instant'],
  ]),
};

export const S9d_Iterations = {
  name: 'S9d · Iterations',
  render: () => iterationBoard('sa-s9d', [
    ['a · refresh', 'sa-s9d sa-s9d-a', 'double-pulse inversion'],
    ['b · face', 'sa-s9d sa-s9d-b', 'pure white panel'],
    ['c · ghosting', 'sa-s9d sa-s9d-c', 'residual afterimage settles in'],
  ]),
};

export const S12_Iterations = {
  name: 'S12 · Iterations',
  render: () => iterationBoard('sa-s12', [
    ['a · copy affordance', 'sa-s12 sa-s12-a', 'icon-only, mono voice in the echo'],
    ['b · density', 'sa-s12 sa-s12-b', 'tighter chip'],
    ['c · echo', 'sa-s12 sa-s12-c', 'just the glyph: ✓'],
  ]),
};

export const T2_Iterations = {
  name: 'T2 · Iterations',
  render: () => iterationBoard('sa-t2', [
    ['a · hue', 'sa-t2 sa-t2-a', 'marker-orange only, on brand'],
    ['b · scope', 'sa-t2 sa-t2-b', 'faint ambient at the chip edge'],
    ['c · copied', 'sa-t2 sa-t2-c', 'glow dies to an ember, check stays white'],
  ]),
};

// ---------- round 8: finalist affordance (S2 + S9c) ----------
// Problem: status zone and action zone both read as buttons. These
// treatments make the status read passive and the copy read pressable.
// Language: container = pressable, bare = status (paste sibling stays bare).

export const S2_Affordance = {
  name: 'S2 · Affordance',
  render: () => iterationBoard('sa-s2', [
    ['a · contained action', 'sa-s2 sa-s2-affa', 'keycap copy; only the pressable looks pressable'],
    ['b · brightness', 'sa-s2 sa-s2-affb', 'status quiet at 72%; action loud, hover circle'],
    ['c · micro-caption', 'sa-s2 sa-s2-affc', '“saved” fades in beside the badge on hover'],
    ['d · synthesis ★', 'sa-s2 sa-s2-affd', 'recommended: bare dim status + keycap action + pointer'],
  ]),
};

export const S9c_Affordance = {
  name: 'S9c · Affordance',
  render: () => iterationBoard('sa-s9c', [
    ['a · contained action', 'sa-s9c sa-s9c-affa', 'flat OLED key behind copy, instant hover'],
    ['b · brightness', 'sa-s9c sa-s9c-affb', 'status at 70%; copy is the brightest glyph'],
    ['c · micro-caption', 'sa-s9c sa-s9c-affc', 'mono “saved” slides out on hover'],
    ['d · synthesis ★', 'sa-s9c sa-s9c-affd', 'recommended: dimmed bare status + flat key + pointer'],
  ]),
};

// ---------- comparison board ----------

/** All seven survivors × four states, ranked by owner preference. */
export const AllStyles = {
  render: () => {
    const board = el('div', 'v2-board sa-board');
    board.append(el('span', 'colhead'), ...STATES.map(([, t]) => el('span', 'colhead', t)));
    for (const [style, title, note] of STYLES) {
      const label = el('span', 'rowlabel', title);
      label.append(el('small', '', note));
      board.append(label);
      for (const [state] of STATES) {
        board.append(el('div', 'cell', [state === 'paste' ? styledPaste(style) : styledPill(style, state)]));
      }
    }
    return board;
  },
};

// ---------- live lifecycle with style picker ----------

/** Feel any survivor with the real timings: 2.4s hide, hover pause, 0.9s re-arm. */
export const StyleLifecycle = {
  name: 'Style lifecycle',
  argTypes: {
    style: {
      control: 'select',
      options: [
        ...STYLES.map(([cls]) => cls),
        'sa-s2 sa-s2-affd',
        'sa-s9c sa-s9c-affd',
        'sa-s13 rice-gruvbox',
        'sa-s13 rice-tokyonight',
        'sa-s13 rice-rosepine',
      ],
      description: 'Pill style applied to the canonical layout (…-affd = round-8 recommended affordance)',
    },
  },
  args: { style: 'sa-s2' },
  render: ({ style }) =>
    lifecycleStage(() => styledPill(style), {
      hint: 'Hover pauses the hide timer · click copies',
    }),
};
