import { popover, sampleItems } from './components.js';

export default {
  title: 'Marker/History Popover',
};

export const Default = {
  render: () => popover({ selectedID: 1 }),
};

export const Searching = {
  args: { search: 'notarytool' },
  render: (args) =>
    popover({
      search: args.search,
      items: sampleItems.filter((i) =>
        i.text.toLowerCase().includes(args.search.toLowerCase()),
      ),
      selectedID: 3,
    }),
};

export const FilterActive = {
  render: () =>
    popover({
      filterActive: true,
      items: sampleItems.filter((i) => i.bundleID === 'com.apple.dt.Xcode'),
      selectedID: 2,
    }),
};

export const NoPermission = {
  render: () =>
    popover({
      empty: {
        iconName: 'handRaisedFill',
        title: 'One permission needed',
        message: 'Marker reads selections through macOS Accessibility. Nothing leaves your Mac.',
        actionTitle: 'Open System Settings',
      },
    }),
};

export const NothingYet = {
  render: () =>
    popover({
      empty: {
        iconName: 'cursorMotion',
        title: 'Nothing here yet',
        message: 'Select text in any app — it lands here, ready to copy or paste.',
      },
    }),
};

export const NoMatches = {
  render: () =>
    popover({
      search: 'zzz',
      empty: {
        iconName: 'magnifyingglass',
        title: 'No matches',
        message: 'Nothing selected like that. Try fewer letters or another app filter.',
      },
    }),
};
