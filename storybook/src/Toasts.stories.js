import { captureToast, readyToast } from './components.js';

const SAMPLE = 'The best interface is the one you never notice until it quietly does the right thing.';

export default {
  title: 'Marker/Toasts',
  args: { text: SAMPLE },
  argTypes: { text: { control: 'text' } },
};

export const Captured = {
  render: (args) => captureToast({ text: args.text, bundleID: 'com.apple.Safari' }),
};

export const CapturedWithWarning = {
  render: (args) =>
    captureToast({
      text: 'ghp_h8Fk2mQx91LpNvA6•••',
      bundleID: 'com.apple.Terminal',
      warning: 'Looks like a secret — not saved to history',
    }),
};

export const ReadyToPaste = {
  render: (args) => readyToast({ text: args.text, hotkeyLabel: '⇧⌘V' }),
};
