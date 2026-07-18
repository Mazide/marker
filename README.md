<img src="assets/icon.svg" width="96" alt="Marker icon">

# Marker

Linux-style primary selection for macOS. Select text in any app — it is
captured into Marker's history, a separate buffer that never touches
your clipboard. Paste the latest selection with ⌥V or middle-click, or
copy any entry to the clipboard explicitly from the popover.

## Features

- Watches text selections system-wide via the Accessibility API.
- Keeps formatting where the source app exposes it: captures carry
  RTF/HTML flavors alongside plain text, so ⌥V and history copies
  paste rich into targets that accept it.
- Strict separate-buffer mode: the system clipboard is never written
  on capture, only on an explicit copy from the popover.
- Fallback capture for apps that hide selections from Accessibility
  (Telegram, kitty, …): synthesized Cmd+C or detection of the app's own
  copy-on-select, with the previous clipboard restored afterwards.
- Unlimited history by default, grouped by day, with search and per-app
  filter; source app icon and timestamp on every entry. Optional
  auto-expiry (7/30/90 days) in Settings → History.
- **⌥V** pastes the most recent selection into the active app. The system
  clipboard is briefly swapped and then restored.
- Menu bar popover: click any history entry to copy it to the clipboard.
- Secrets (API keys, tokens, private keys) are never written to history.
- Delete single entries from the popover; clear everything from Settings.
- Gear menu in the popover: Settings, Check for Updates, Quit.
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
