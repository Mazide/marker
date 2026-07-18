<img src="assets/icon.svg" width="96" alt="Marker icon">

# Marker

Linux-style primary selection for macOS. Select text in any app — it is
captured into Marker's history, a separate buffer that leaves your
clipboard untouched, and pasted with Opt+V or a middle-click. Prefer
classic copy-on-select? Turn on "To clipboard" and every selection also
lands on the system clipboard, ready to Cmd+V.

## Features

- Watches text selections system-wide via the Accessibility API.
- Strict separate-buffer mode by default; optional auto-copy to the
  system clipboard for classic copy-on-select.
- Fallback capture for apps that hide selections from Accessibility
  (Telegram, kitty, …): synthesized Cmd+C or detection of the app's own
  copy-on-select, with the previous clipboard restored afterwards.
- Unlimited history by default, grouped by day, with search and per-app
  filter; source app icon and timestamp on every entry. Optional
  auto-expiry (7/30/90 days) in Settings → History.
- **⌥V** pastes the most recent selection into the active app. The system
  clipboard is briefly swapped and then restored.
- Menu bar popover: click any history entry to copy it to the clipboard.
- Secrets (API keys, tokens, private keys) reach your clipboard but are
  never written to history.
- Delete single entries from the popover; clear everything from Settings.
- Auto-updates via Sparkle.

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
- History is stored unencrypted in a local SQLite database
  (`~/Library/Application Support/Marker`). Use Clear for anything you
  don't want persisted; nothing ever leaves your Mac.
## Privacy & license

No analytics, no telemetry; the network is used only for Sparkle update
checks. Details: [privacy policy](https://getwaymark.net/marker/privacy/).
[MIT](LICENSE).
