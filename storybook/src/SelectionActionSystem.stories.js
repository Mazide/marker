import { el, popover, spotlightPanel, selectionAction, markerTemplateIcon } from './components.js';

/**
 * Round 10: system coherence. The pill won't live alone — these stages show
 * the Spotlight-style history panel and the compact menubar popover
 * restyled in each finalist's language, with the finalist pill
 * (d-affordance form) floating alongside so the family resemblance reads
 * in one screenshot.
 *
 * Reuses the existing DOM builders untouched; all restyling is scoped
 * CSS overrides (.sys-s2 / .sys-s9c), mostly riding the token variables
 * the builders already consume. Same hierarchy discipline as the pill:
 * interactive = contained/brighter, passive = bare/dimmer.
 */
export default {
  title: 'Marker/Selection Action System',
};

/** Swap the badge's full-color app icon for the currentColor template icon. */
function useTemplateIcon(node, size) {
  for (const appIcon of node.querySelectorAll('.saved-badge .app-icon')) {
    appIcon.replaceWith(markerTemplateIcon(size));
  }
}

/** Finalist pill in its d-affordance form. */
function finalistPill(style) {
  const pill = selectionAction();
  pill.classList.add(...style.split(' '));
  useTemplateIcon(pill, 15);
  return pill;
}

/** Panel + popover + pill in one scoped stage. */
function systemStage(scope, pillStyle) {
  const stage = el('div', `sys-stage ${scope}`);
  stage.append(
    spotlightPanel({ selectedID: 1 }),
    popover({ selectedID: 1 }),
    el('div', 'sys-pill-slot', [finalistPill(pillStyle)]),
  );
  return stage;
}

export const S2_System = {
  name: 'S2 · System',
  render: () => systemStage('sys-s2', 'sa-s2 sa-s2-affd'),
};

export const S9c_System = {
  name: 'S9c · System',
  render: () => systemStage('sys-s9c', 'sa-s9c sa-s9c-affd'),
};
