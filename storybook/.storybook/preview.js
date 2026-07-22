import '../src/marker.css';

/**
 * Theme toolbar: renders every story on a fake macOS desktop so the
 * translucent materials (backdrop-filter) have something to blur.
 */
export const globalTypes = {
  theme: {
    description: 'macOS appearance',
    toolbar: {
      title: 'Theme',
      icon: 'mirror',
      items: [
        { value: 'light', title: 'Light' },
        { value: 'dark', title: 'Dark' },
      ],
      dynamicTitle: true,
    },
  },
};

export const initialGlobals = { theme: 'light' };

export const decorators = [
  (story, context) => {
    const desktop = document.createElement('div');
    desktop.className = 'desktop';
    desktop.dataset.theme = context.globals.theme;
    const result = story();
    if (typeof result === 'string') {
      desktop.innerHTML = result;
    } else {
      desktop.appendChild(result);
    }
    return desktop;
  },
];

export const parameters = {
  layout: 'fullscreen',
  controls: { expanded: true },
};
