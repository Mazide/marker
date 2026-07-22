/**
 * DOM builders mirroring the SwiftUI views one-to-one.
 * HistoryView.swift → popover / row / emptyState / footer
 * ToastPresenter.swift → toasts
 */

// ---------- helpers ----------

export function el(tag, className, children = []) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  for (const child of [].concat(children)) {
    if (child == null) continue;
    node.append(child.nodeType ? child : document.createTextNode(child));
  }
  return node;
}

function html(tag, className, markup) {
  const node = el(tag, className);
  node.innerHTML = markup;
  return node;
}

// ---------- SF-Symbol stand-ins (inline SVG, sized in px ≈ pt) ----------

const SVG = {
  magnifyingglass:
    '<circle cx="6.5" cy="6.5" r="4.75" fill="none" stroke="currentColor" stroke-width="1.5"/><line x1="10.2" y1="10.2" x2="14" y2="14" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>',
  xmarkCircleFill:
    '<circle cx="8" cy="8" r="7"/><path d="M5.6 5.6 L10.4 10.4 M10.4 5.6 L5.6 10.4" stroke="var(--popover-material, #fff)" stroke-width="1.4" stroke-linecap="round"/>',
  filterCircle:
    '<circle cx="8" cy="8" r="6.75" fill="none" stroke="currentColor" stroke-width="1.3"/><line x1="4.8" y1="6.2" x2="11.2" y2="6.2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="5.8" y1="8.2" x2="10.2" y2="8.2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><line x1="6.8" y1="10.2" x2="9.2" y2="10.2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>',
  filterCircleFill:
    '<circle cx="8" cy="8" r="7.4"/><line x1="4.8" y1="6.2" x2="11.2" y2="6.2" stroke="var(--popover-material, #fff)" stroke-width="1.2" stroke-linecap="round"/><line x1="5.8" y1="8.2" x2="10.2" y2="8.2" stroke="var(--popover-material, #fff)" stroke-width="1.2" stroke-linecap="round"/><line x1="6.8" y1="10.2" x2="9.2" y2="10.2" stroke="var(--popover-material, #fff)" stroke-width="1.2" stroke-linecap="round"/>',
  gearshape:
    '<g transform="scale(0.542)" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></g>',
  docOnDocFill:
    '<rect x="5.5" y="1.5" width="8" height="10" rx="1.5"/><rect x="2.5" y="4.5" width="8" height="10" rx="1.5" stroke="var(--popover-material, #fff)" stroke-width="1"/>',
  warningFill:
    '<path d="M8 1.5 L15 13.5 a1 1 0 0 1 -0.9 1.5 H1.9 a1 1 0 0 1 -0.9 -1.5 Z"/><path d="M8 6 v4 M8 12.4 v0.2" stroke="var(--toast-material, #fff)" stroke-width="1.4" stroke-linecap="round"/>',
  handRaisedFill:
    '<path d="M5 8 V3.4 a1 1 0 0 1 2 0 V2.6 a1 1 0 0 1 2 0 V3.4 a1 1 0 0 1 2 0 V5 a1 1 0 0 1 2 0 v4.6 c0 2.8-1.8 4.9-4.5 4.9 -2 0-3.1-0.9-4.2-2.6 L3 9.4 a1.1 1.1 0 0 1 1.9-1.1 Z"/>',
  cursorMotion:
    '<path d="M6 3 L13 9 L9.4 9.6 L11.2 13.4 L9.6 14.2 L7.8 10.3 L5.2 12.6 Z"/><path d="M1.5 4.5 h2.8 M1.5 7 h2 M1.5 9.5 h1.4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" fill="none"/>',
  handTap:
    '<circle cx="8" cy="4" r="2.6" fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M8 4 v5.5 M6 9 v-1 a1 1 0 0 1 2 0 M10 9.5 V8 a1 1 0 0 1 2 0 v2.8 c0 1.8-1.2 3-3 3 -1.3 0-2-0.5-2.8-1.6 l-1.4-2 a0.9 0.9 0 0 1 1.5-1 Z" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>',
  computermouse:
    '<rect x="4" y="1.5" width="8" height="13" rx="4" fill="none" stroke="currentColor" stroke-width="1.3"/><line x1="8" y1="3.5" x2="8" y2="6.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>',
};

export function icon(name, size = 16) {
  const span = el('span', 'icon');
  span.innerHTML = `<svg width="${size}" height="${size}" viewBox="0 0 16 16">${SVG[name]}</svg>`;
  return span;
}

// ---------- app icons (placeholder gradients, real ones are NSWorkspace icons) ----------

const APPS = {
  'com.apple.Safari': { name: 'Safari', glyph: '🧭', bg: 'linear-gradient(180deg,#e8f4ff,#cfe6fb)' },
  'com.apple.dt.Xcode': { name: 'Xcode', glyph: '🔨', bg: 'linear-gradient(180deg,#dfeafc,#b8cef5)' },
  'com.apple.Terminal': { name: 'Terminal', glyph: '>_', bg: '#1e1e1e' },
  'com.apple.Notes': { name: 'Notes', glyph: '📒', bg: 'linear-gradient(180deg,#fffbe8,#f7edc0)' },
  'ru.keepcoder.Telegram': { name: 'Telegram', glyph: '✈️', bg: 'linear-gradient(180deg,#5fc9f4,#2b9fd8)' },
  'com.google.Chrome': { name: 'Chrome', glyph: '🌐', bg: 'linear-gradient(180deg,#fff,#eee)' },
};

export function appIcon(bundleID, size = 16) {
  const app = APPS[bundleID] ?? { glyph: '▢', bg: '#ccc' };
  const span = el('span', 'app-icon-glyph', app.glyph);
  span.style.width = `${size}px`;
  span.style.height = `${size}px`;
  span.style.fontSize = `${Math.round(size * 0.62)}px`;
  span.style.background = app.bg;
  if (bundleID === 'com.apple.Terminal') {
    span.style.color = '#4be34b';
    span.style.fontFamily = 'ui-monospace, monospace';
    span.style.fontWeight = '700';
    span.style.fontSize = `${Math.round(size * 0.45)}px`;
  }
  span.title = app.name ?? bundleID;
  return span;
}

export function appName(bundleID) {
  return APPS[bundleID]?.name ?? bundleID;
}

// ---------- sample data ----------

export const sampleItems = [
  {
    id: 1, bundleID: 'com.apple.Safari', time: '14:32', day: 'Today',
    text: 'Select text. It’s already saved. Marker keeps every selection you make, so copying becomes optional.',
  },
  {
    id: 2, bundleID: 'com.apple.dt.Xcode', time: '14:28', day: 'Today',
    text: 'func pickForPaste(_ item: SelectionItem) {\n    pasteSlot = item\n}',
  },
  {
    id: 3, bundleID: 'com.apple.Terminal', time: '13:51', day: 'Today',
    text: 'xcrun notarytool submit Marker.zip --keychain-profile marker --wait',
  },
  {
    id: 4, bundleID: 'com.google.Chrome', time: '13:07', day: 'Today',
    text: 'https://developer.apple.com/documentation/swiftui/menubarextra',
  },
  {
    id: 5, bundleID: 'ru.keepcoder.Telegram', time: '11:45', day: 'Today',
    text: 'Созвон перенесли на 16:00, кидай ссылку на фигму когда будет готово',
  },
  {
    id: 6, bundleID: 'com.apple.Notes', time: '21:14', day: 'Yesterday',
    text: 'Milk, eggs, coffee beans, the good bread from the corner bakery',
  },
  {
    id: 7, bundleID: 'com.apple.dt.Xcode', time: '18:03', day: 'Yesterday',
    text: '~/Library/Application Support/Marker/history.sqlite',
  },
  {
    id: 8, bundleID: 'com.apple.Safari', time: '10:22', day: 'Yesterday',
    text: 'The best interface is the one you never notice until it quietly does the right thing.',
  },
];

// isCodeLike heuristic, ported from HistoryRow
export function isCodeLike(text) {
  const t = text.trim();
  if (!t) return false;
  if (t.includes('://')) return true;
  if (t.startsWith('/') || t.startsWith('~/')) return true;
  if (t.includes('\n') && /[{};=<>()]/.test(t)) return true;
  if (!/\s/.test(t) && t.length >= 8) return true;
  const symbols = (t.match(/[{}[\]()<>;=+*/\\|&^%$#@_`~]/g) ?? []).length;
  return symbols / t.length > 0.08;
}

function snippet(text) {
  if (isCodeLike(text)) {
    return text.split('\n').map((l) => l.trim()).filter(Boolean).slice(0, 2).join('\n');
  }
  return text.split(/\s+/).join(' ');
}

// ---------- popover pieces ----------

export function searchField({ value = '', placeholder = 'Search' } = {}) {
  const field = el('div', 'search-field', [icon('magnifyingglass', 12)]);
  const input = el('input');
  input.placeholder = placeholder;
  input.value = value;
  field.append(input);
  if (value) field.append(el('button', 'search-clear', [icon('xmarkCircleFill', 12)]));
  return field;
}

export function popoverHeader({ search = '', filterActive = false } = {}) {
  const filter = el('button', `filter-button${filterActive ? ' active' : ''}`, [
    icon(filterActive ? 'filterCircleFill' : 'filterCircle', 15),
  ]);
  filter.title = 'Filter by app';
  return el('div', 'popover-header', [searchField({ value: search }), filter]);
}

export function historyRow(item, { selected = false } = {}) {
  const code = isCodeLike(item.text);
  const row = el('div', `history-row${code ? ' code' : ''}${selected ? ' selected' : ''}`, [
    el('span', 'app-icon', [appIcon(item.bundleID, 16)]),
    el('div', 'snippet', snippet(item.text)),
  ]);
  const trailing = el('div', 'trailing', [
    el('span', 'time', item.time),
    el('div', 'actions', [
      el('button', '', [icon('docOnDocFill', 11)]),
      el('button', '', [icon('xmarkCircleFill', 13)]),
    ]),
  ]);
  trailing.querySelectorAll('button')[0].title = 'Copy to clipboard';
  trailing.querySelectorAll('button')[1].title = 'Delete';
  row.append(trailing);
  return row;
}

export function historyList(items, { selectedID = null } = {}) {
  const list = el('div', 'history-list');
  const days = [...new Set(items.map((i) => i.day))];
  for (const day of days) {
    list.append(el('div', 'day-header', day));
    for (const item of items.filter((i) => i.day === day)) {
      list.append(historyRow(item, { selected: item.id === selectedID }));
    }
  }
  return list;
}

export function emptyState({ iconName, title, message, actionTitle }) {
  const state = el('div', 'empty-state', [
    el('div', 'badge', [icon(iconName, 17)]),
    el('div', 'title', title),
    el('div', 'message', message),
  ]);
  if (actionTitle) state.append(el('button', 'action', actionTitle));
  return state;
}

export function popoverFooter({ hotkeyLabel = '⇧⌘V' } = {}) {
  const gear = el('button', 'gear-button', [icon('gearshape', 13)]);
  gear.title = 'Settings, updates, quit';
  return el('div', 'popover-footer', [
    el('span', 'hint', `↩ picks · ${hotkeyLabel} pastes it · right-click copies`),
    gear,
  ]);
}

export function popover({ search = '', filterActive = false, selectedID = 1, items = sampleItems, empty = null, calm = false } = {}) {
  const root = el('div', `popover${calm ? ' calm' : ''}`, [popoverHeader({ search, filterActive })]);
  root.append(empty ? emptyState(empty) : historyList(items, { selectedID }));
  root.append(popoverFooter());
  return root;
}

/**
 * V2 experiment: Spotlight-style centered panel for the hotkey invocation.
 * Same rows, bigger search, no separate header pill — the field is the header.
 */
export function spotlightPanel({ search = '', filterActive = false, selectedID = 1, items = sampleItems } = {}) {
  const searchRow = el('div', 'panel-search', [icon('magnifyingglass', 16)]);
  const input = el('input');
  input.placeholder = 'Search selections';
  input.value = search;
  searchRow.append(input);
  const filter = el('button', `filter-button${filterActive ? ' active' : ''}`, [
    icon(filterActive ? 'filterCircleFill' : 'filterCircle', 16),
  ]);
  searchRow.append(filter);

  return el('div', 'panel', [
    searchRow,
    historyList(items, { selectedID }),
    popoverFooter(),
  ]);
}

// ---------- menus ----------

function menuItem({ label, shortcut, checked, bundleID, destructive, checkColumn }) {
  const item = el('div', `menu-item${destructive ? ' destructive' : ''}`);
  if (checkColumn) item.append(el('span', 'check', checked ? '✓' : ''));
  if (bundleID) item.append(el('span', 'app-icon', [appIcon(bundleID, 16)]));
  item.append(el('span', 'label', label));
  if (shortcut) item.append(el('span', 'shortcut', shortcut));
  return item;
}

export function menu(items) {
  const root = el('div', 'menu');
  for (const item of items) {
    root.append(item === 'separator' ? el('div', 'menu-separator') : menuItem(item));
  }
  return root;
}

export function gearMenu() {
  return menu([
    { label: 'Settings…', shortcut: '⌘,' },
    { label: 'Check for Updates…' },
    'separator',
    { label: 'Quit Marker', shortcut: '⌘Q' },
  ]);
}

export function filterMenu({ selected = null } = {}) {
  return menu([
    { label: 'All Apps', checked: selected === null, checkColumn: true },
    'separator',
    ...Object.keys(APPS).map((bundleID) => ({
      label: appName(bundleID),
      bundleID,
      checked: selected === bundleID,
      checkColumn: true,
    })),
  ]);
}

export function contextMenu() {
  return menu([
    { label: 'Copy' },
    'separator',
    { label: 'Delete', destructive: true },
  ]);
}

// ---------- toasts ----------

function toastShell(headerChildren, text, warning) {
  const root = el('div', 'toast', [
    el('div', 'toast-header', headerChildren),
    el('div', 'toast-body', text.trim().replaceAll('\n', ' ')),
  ]);
  if (warning) {
    root.append(el('div', 'toast-warning', [icon('warningFill', 10), warning]));
  }
  return root;
}

const markerIcon = () => {
  const span = el('span', 'app-icon-glyph', '');
  span.style.cssText = 'width:14px;height:14px;background:linear-gradient(180deg,#f9a825,#e8750d);position:relative;';
  span.innerHTML = '<span style="position:absolute;inset:4px 2px;background:rgba(255,255,255,.92);border-radius:1.5px;"></span>';
  return el('span', 'app-icon', [span]);
};

export function captureToast({ text, bundleID = 'com.apple.Safari', warning = null } = {}) {
  return toastShell(
    [
      markerIcon(),
      el('span', 'app-name', 'Marker'),
      '· captured from',
      el('span', 'source-icon', [appIcon(bundleID, 12)]),
      appName(bundleID),
    ],
    text,
    warning,
  );
}

export function pasteToast({ text, source = 'threeFingerClick' } = {}) {
  const labels = {
    threeFingerClick: 'three-finger click',
    threeFingerDoubleTap: 'three-finger double tap',
    middleClick: 'middle-click',
  };
  return toastShell(
    [
      markerIcon(),
      el('span', 'app-name', 'Marker'),
      '· pasted via',
      icon(source === 'middleClick' ? 'computermouse' : 'handTap', 11),
      labels[source],
    ],
    text,
  );
}

export function readyToast({ text, hotkeyLabel = '⇧⌘V' } = {}) {
  return toastShell(
    [markerIcon(), el('span', 'app-name', 'Marker'), `· ${hotkeyLabel} pastes this`],
    text,
  );
}
