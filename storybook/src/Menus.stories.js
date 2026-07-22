import { gearMenu, filterMenu, contextMenu } from './components.js';

export default {
  title: 'Marker/Menus',
};

export const Gear = {
  render: () => gearMenu(),
};

export const AppFilter = {
  args: { selected: 'com.apple.dt.Xcode' },
  argTypes: {
    selected: {
      control: 'select',
      options: [null, 'com.apple.Safari', 'com.apple.dt.Xcode', 'com.apple.Terminal'],
    },
  },
  render: (args) => filterMenu({ selected: args.selected }),
};

export const RowContext = {
  render: () => contextMenu(),
};
