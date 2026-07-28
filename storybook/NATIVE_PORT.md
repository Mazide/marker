# Native port: selection-action pill v2

Source of truth for porting the storybook prototype back into SwiftUI.
Prototype: `storybook/src` — stories `Selection Action Styles / Final / System`,
CSS sections `V2 styles` + `round-9 final motion` in `marker.css`.

## Scope

1. Restyle `SelectionActionPresenter` (pill + paste confirmation) to the S2 Ink/HUD
   language with the d-affordance layout and the final motion package.
2. Introduce `PillTheme` — palette-only theming (7 tokens), user-selectable
   in Settings. Behavior, layout, and motion are identical across themes.
3. Unify popup anchoring: paste confirmation uses the same anchor rule as the
   capture pill.

Out of scope (later): panel/popover restyle (see System stories), per-theme
motion personalities (S13 spinner etc.), first-run menu-bar flight.

## Layout & affordance (from S2 Affordance, row d ★)

Canonical layout unchanged: `[status: app icon 16 + green check badge 9] | divider | [copy 28×28 → check]`.

- Status zone = **bare**: no container, no hover reaction, opacity 0.8,
  `cursor` stays arrow. Semantics: "already done, nothing to press".
- Copy zone = **bare icon** in a 28×28 hit area: no fill or outline in any
  theme, at rest or on hover. Hover only brightens the icon to 100% and uses
  the pointing-hand cursor (`NSCursor.pointingHand` via `onHover`).
- Copied state: bare green check replaces the copy icon
  (status language; nothing left to press).
- Paste confirmation: bare badge only, no container ever.

## S2 chip (default theme "Ink")

- Background: near-opaque warm dark `Color(red: 0.125, green: 0.122, blue: 0.133)`
  at 0.94 — same in BOTH system appearances (HUD-style, like the volume OSD).
  No material blur required; if trivial, `.ultraThinMaterial` under the tint is fine.
- No border. Shadow: black 0.30, radius 9, y 3.
- Radius 12 (between current 10 and full capsule; matches prototype).
- Iconography: white template icon (`menubar-icon` asset rendered template,
  white); divider white 14%; check badge systemGreen with white check.

## PillTheme

```swift
struct PillTheme {
    let chip: Color          // chip background (opaque-ish)
    let surface: Color       // secondary app surface
    let border: Color?       // 1px pane border (nil for Ink)
    let text: Color          // primary glyphs
    let dim: Color           // status-zone / secondary
    let accent: Color        // theme accent
    let success: Color       // check badge / copied
}
enum PillThemeChoice: String, CaseIterable { // @AppStorage("pillTheme"), default .ink
    case ink, oled, catppuccin, gruvbox, tokyonight, rosepine
}
```

- Each case returns a light+dark pair (follows system appearance):
  ink = same both; oled = true black / crisp white, transitions replaced with
  instant state flips is NOT done in v1 — motion stays unified;
  catppuccin = Mocha/Latte; gruvbox dark/light; tokyonight storm/day;
  rosepine base/dawn. Hex values: see `marker.css` skin token blocks — copy exactly.
- Rice themes (catppuccin/gruvbox/tokyonight/rosepine) additionally draw the
  1 px `border` and use mono-leaning font for the copied check line? — NO:
  v1 keeps identical layout/typography; border token only.
- Settings UI: "Appearance" row in SettingsView — horizontal picker of live
  mini-pill previews (render `SelectionActionView` snapshots per theme),
  theme names are proper nouns, not localized. One new localized string:
  the section label. All 7 `Localizable.strings`.

## Motion (from Final stories; round-9 CSS)

- Appear: fade 0 → 1, 0.15 s ease-out + 6 px slide from the selection direction
  (dx/dy = normalized vector from selection center to anchor; fallback: from left)
  with slight overshoot — `spring(response: 0.3, dampingFraction: 0.75)`.
- Auto-hide 2.4 s; hover pauses; mouse-leave re-arms 0.9 s (existing contract, keep).
- Dismiss: fade 0.15 s (replaces instant orderOut alpha=0 — animate then orderOut).
- Copy feedback: check `scaleEffect` 1.4 → 1 spring ~0.25 s; chip flashes
  success color at 8% overlay and settles to clear over 0.35 s.
  Then hide after 0.6 s (shortened from the remaining timer).
- Paste confirmation: appear = fade 0.12 s + rise 4 px; auto-hide 0.9 s, fade-out 0.15 s.
- `accessibilityReduceMotion` (NSWorkspace / @Environment): all of the above
  collapse to pure fades — no slide, no spring, no flash.

## Anchoring

- `showPasteConfirmation` switches from `centeredAboveFrame` to `positionedFrame`
  (same +gap offset as the capture pill). Delete `centeredAboveFrame` and its tests;
  keep/extend `positionedFrame` tests to cover the paste path.

## Acceptance

- Pill and paste confirmation appear at the same anchor rule.
- Copy zone is the only element that looks pressable and the only one with
  pointing-hand cursor; status zone ignores hover.
- Theme switch in Settings restyles the pill live; default `.ink` requires
  no user action and matches the S2 Final story.
- Reduce Motion honored.
- `swift build` + existing test suite green; `SelectionActionPresenterTests`
  updated for the anchoring change.
