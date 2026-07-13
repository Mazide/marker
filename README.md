# Marker

Linux-style primary selection for macOS. Select text in any app — it is
captured into Marker's own history, **without touching the system
clipboard**. Your Cmd+C buffer stays intact.

## Features

- Watches text selections system-wide via the Accessibility API
  (no synthesized Cmd+C, no clipboard pollution).
- Keeps the last 20 selections in a separate history (persisted across
  restarts), with the source app and timestamp for each entry.
- **⌥V** pastes the most recent selection into the active app. The system
  clipboard is briefly swapped and then restored.
- Menu bar popover: click any history entry to copy it to the clipboard.

## Build & run

```sh
./build-app.sh
open build/Marker.app
```

On first launch macOS asks for **Accessibility** permission
(System Settings → Privacy & Security → Accessibility). Marker starts
watching selections as soon as it is granted — no relaunch needed.

## Notes & limitations

- Apps with poor Accessibility support (some Electron apps, some Java
  apps) may not report selections.
- History is stored in `UserDefaults` as plain text — quit Marker before
  selecting things you don't want persisted, or use Clear.
- The ⌥V clipboard swap restores only plain-text clipboard contents;
  rich content (images, files) present in the clipboard at that moment
  is not restored.
