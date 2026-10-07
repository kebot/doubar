# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Doubar is a macOS menu bar replacement written in Swift (AppKit + SwiftUI, Swift Package Manager, no Xcode project). It draws a transparent, always-on-bottom strip along the top of every display that takes clicks, hover and scroll without ever activating the app. It has no Dock icon and is never the active app.

## Commands

```bash
make dev     # swift run doubar (foreground)
make build   # release build (arm64) → .build/release/doubar
make link    # build + symlink to ~/.local/bin/doubar
make bundle  # .build/doubar.app (LSUIElement, ad-hoc signed)
```

`doubar emit <event> [key=value ...]` posts a distributed notification (`com.yaofur.doubar.event`) to the running bar and exits; it never starts a bar. `doubar emit reload` rereads the config files, `doubar emit settings` toggles the settings popup, `doubar check-config` reports problems in them. AeroSpace hooks call `doubar emit aerospace`; `doubar emit peek workspace=<name>` opens a workspace preview (bare `peek` closes it). `doubar emit rename workspace=<name> [name=<label>]` sets a label or opens the rename field (bare `rename` closes it).

## Architecture (Sources/doubar/)

- `main.swift` — CLI dispatch (`emit`), single-instance lock (`flock` on `$TMPDIR/doubar.lock`), `.accessory` activation policy
- `AppDelegate.swift` — one `BarWindow` per `NSScreen`, keyed by display ID; resyncs on screen-parameter changes and wake, then re-asserts ordering at 0.25/1/3 s
- `BarWindow.swift` — the bar `NSPanel` (scroll handling included) and the per-bar `Screen` environment object: AeroSpace `monitorId`, the bar's screen frame, and `toScreen` to convert SwiftUI window-space rects to screen coordinates
- `Support.swift` — logging, async `run(path, args)` subprocess helper, IPC, `observeDistributed`
- `Config/` — `Config.swift` (`Config.shared`: reads `~/.config/doubar/config.toml` and the `theme.toml` palette beside it, polls both once a second, writes config.toml back), `Toml.swift` (TOML reader that records where each value sits, for in-place edits), `Colors.swift` (colour expressions: `#hex`, palette key, `key/12%`, `mix(a, b, 20%)`), `Layout.swift` (layout entries and the edits menus and drags make)
- `Notch/` — the overlay grown out of the MacBook notch, following Spotify: `Notch.swift` (`Notch.shared` model: expand/collapse timing, likes and bans in the UserDefaults suite, `NotchLayout` sizes, `NotchColors`), `NotchPanel.swift` (the panel, top-centre of the notched display), `NotchView.swift`, `Lyrics.swift` (LRCLIB synced lyrics, cached by track ID). Design: https://claude.ai/artifact/LZMrGNVNDMt3FAymphWWRZ
- `Views/` — `Bar.swift` (`BarView` built from the layout, `Pill` capsule — the atomic bar item, `Theme` (reads `Config`), `onWindowFrameChange`), `Menus.swift` (`EntryMenu`, the right-click menu of every bar item), `Prompt.swift` (`TextPrompt`, the one-line key panel), `AppIcon.swift`, `Popup.swift` (`PopupPanel` base for every floating panel, `NSScreen.barAnchor`)
- `Widgets/` — `AeroSpace.swift` (shared model + workspace pills), `PillFrames.swift` (`WorkspaceSlot` and the screen frames of every pill, for drop targets and scroll), `Peek.swift` (hover preview of a workspace), `Rename.swift` (workspace labels in UserDefaults suite `com.yaofur.doubar`, and the rename field), `WindowDrag.swift` (drag an icon onto a pill → `move-node-to-workspace`), `StatusItems.swift` (every app's status item mirrored into the bar), `Settings.swift` (`BarSettings` popup: Layout tab drags pills, Bar tab sizes the strip), `Spotify.swift`, `Clock.swift`

`Config/Themes.swift` bundles the Omarchy palettes (generated from `~/dotfiles/themes/`); `[theme] name` picks one over theme.toml. `docs/config.toml` is the documented example config. The dotter template for `theme.toml` lives in `~/dotfiles/doubar/theme.toml`.

Widget models are `@MainActor` singletons shared by all bars; per-display state comes from the `Screen` environment object.

config.toml is the source of truth for the look and the layout. `[layout]` lists pills on `left` and `right`; each pill holds entries: a widget (`clock`, `spotify`, `settings`, `workspaces`) or `status:<app id>/<name>` (one status item) / `status:<app id>` (all of an app's). Anything not listed is hidden. With no `[layout]`, `Config.effectiveLayout` shows every status item (minus the old `hiddenStatusItems` in UserDefaults), Spotify, the clock and the settings button. The UI never re-serialises the file: values change in place (`TomlDocument.setting`), and only `[layout]` is regenerated whole (`replacingTable`). Writes go through a dotter symlink, never over it, and are refused while the file doesn't parse. Views that read `Config` must observe it, context-menu content included, or SwiftUI keeps showing stale values.

AeroSpace support is currently switched off (`AeroSpace.enabled = false`, the window manager is now OmniWM, which has its own bar). The flag hides the workspace pills, ignores `emit` events and turns off scroll-to-switch; the AeroSpace, Peek, Rename and WindowDrag code is left in place.

## macOS-specific constraints

- Bar windows set `canHide = false`. Depending on what launches doubar, the process can start with `NSApp.isHidden == true`, which hides every window it owns while their frames stay intact. `orderFront:` is a no-op because the app is never active; use `orderFrontRegardless()`.
- Distributed notifications must be observed with `suspensionBehavior: .deliverImmediately` (use `observeDistributed`); Cocoa suspends delivery for inactive apps.
- AeroSpace monitor IDs are 1-based, ordered left to right then top to bottom; only `NSScreen.aeroSpaceMonitorId` / `forAeroSpaceMonitor` (AppDelegate.swift) know that mapping.
- AeroSpace is found at `/opt/homebrew/bin/aerospace` or `/usr/local/bin/aerospace`.
- Spotify is queried via `osascript` when it posts `com.spotify.client.PlaybackStateChanged`, and every 10 s while playing; the script guards with `is running` so it never launches Spotify.
- The notch panel (`.statusBar + 1`) is sized for the expanded notch but only the body takes the mouse: mouse-moved monitors (global and local) flip `ignoresMouseEvents` as the pointer crosses `Notch.frame`, and start the collapse timer when it leaves. Only a click expands it. Esc is a global key monitor, so it only works with Accessibility. The base size comes from `safeAreaInsets.top` and the `auxiliaryTop*Area`s. Spotify's AppleScript can't like a track or read its playlist, so 红心 is local and the label is always the title. Seeks inside Spotify aren't announced, so the position is re-read every 10 s while playing and interpolated between.
- Bar windows accept first mouse (`acceptsFirstMouse`) and rely on SwiftUI's `.activeAlways` tracking areas for hover; tooltips (`.help`) never show for an inactive app.
- Peek: AeroSpace parks hidden workspaces' windows off-screen, so `WindowLayout` remembers each window's place from when its workspace was visible; until then it lays windows out at their real (parked) sizes, side by side, then stacked, then as a grid. Peek skips workspaces already on screen and sizes the miniature to fit below the bar. Contents come from ScreenCaptureKit, which captures parked windows fine; it needs Screen Recording permission, granted to whatever launched doubar (the terminal, or the .app when bundled).
- Floating panels subclass `PopupPanel` (`.popUpMenu` level, `canHide = false`, accepts first mouse); `fit(_:)` resizes one as its content changes, keeping the top edge. `TextPrompt` (rename field, clock format) is the one that becomes key (`orderFrontRegardless()` then `makeKey()`): as a `.nonactivatingPanel` it gets the keyboard without activating doubar. Don't `NSApp.activate` for it; since macOS 14 an app can't take activation for itself. With no main menu, Cmd-A/C/V/X/Z reach the field only because `PromptPanel.performKeyEquivalent` sends them itself.
- Status item ids are `<bundle id>/<name>`, the name being the AX identifier, description, title or help text (Stats names its items only in `AXHelp`), numbered `#n` when repeated or empty within an app.
- Status item pictures have a transparent background. `[status-items] tint` splits each into neutral and coloured layers (`StatusItems.layers`) on every capture and redraws them as template images: `palette` gives the neutral layer `colors.icon` and maps each coloured pixel to the palette colour nearest its hue (`Config.Hues`); `mono` draws both in `colors.accent`, the coloured layer at half opacity. In `mono` the built-in widgets' text turns accent too (`Theme.barText`), so the whole bar is one colour. Tinting a whole picture as one template turns filled shapes (Stats' graphs) into solid blocks.
- Status items (macOS 27): there are no per-item windows; `MenuBarAgent` draws the whole menu bar into one window and keeps rendering it while the menu bar is auto-hidden. doubar captures that window with ScreenCaptureKit and slices it by each item's x-span from Accessibility (`AXExtrasMenuBar` of every app); clicks are `AXPress`. MenuBarAgent's own items (Wi-Fi, Control Center, ...) are slots with no actions; the `AXMenuExtra` inside (`com.apple.menuextra.wifi`, ...) takes the press and gives the item its id. Spotlight's item (`com.apple.campo`) ignores every press, so doubar posts the user's Spotlight shortcut (symbolic hotkey 64) instead. Clicks posted to a process are ignored by all of these. `doubar emit status-item id=<id>` clicks an item. Needs Accessibility as well as Screen Recording. Items collapsed by the system's own "Hide Menu Bar Items" chevron aren't drawn at all, so doubar keeps that chevron out of the bar (matched by its English label) and skips the collapsed items. AXPress can collapse but not expand; expanding takes a real click on the system menu bar.
- Settings-popup drags stay inside the popup: a `DragGesture` in a named coordinate space, hit-tested against pill and row frames collected with preference keys, the ghost drawn as an overlay.
- Icon drags are a `DragGesture` plus a floating ghost panel, not system drag-and-drop (`onDrag` doesn't start reliably from a never-active app). Mouse-dragged events keep going to the bar window the press began in, so drops are found by hit-testing `NSEvent.mouseLocation` against `PillFrames`, which also works across displays.
