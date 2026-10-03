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

`doubar emit <event> [key=value ...]` posts a distributed notification (`com.yaofur.doubar.event`) to the running bar and exits; it never starts a bar. AeroSpace hooks call `doubar emit aerospace`; `doubar emit peek workspace=<name>` opens a workspace preview (bare `peek` closes it). `doubar emit rename workspace=<name> [name=<label>]` sets a label or opens the rename field (bare `rename` closes it).

## Architecture (Sources/doubar/)

- `main.swift` — CLI dispatch (`emit`), single-instance lock (`flock` on `$TMPDIR/doubar.lock`), `.accessory` activation policy
- `AppDelegate.swift` — one `BarWindow` per `NSScreen`, keyed by display ID; resyncs on screen-parameter changes and wake, then re-asserts ordering at 0.25/1/3 s
- `BarWindow.swift` — the `NSPanel` and the per-bar `Screen` environment object (AeroSpace `monitorId`)
- `Support.swift` — logging, async `run(path, args)` subprocess helper, IPC, `observeDistributed`
- `Views/Bar.swift` — `BarView` layout, `Pill` capsule (the atomic bar item), `Theme` colours
- `Widgets/` — `AeroSpace.swift` (shared model + views + `AppIcon`), `Peek.swift` (hover preview of a workspace), `Rename.swift` (workspace labels in UserDefaults suite `com.yaofur.doubar`, and the rename field), `WindowDrag.swift` (drag an icon onto a pill → `move-node-to-workspace`), `Spotify.swift`, `Clock.swift`

Widget models are `@MainActor` singletons shared by all bars; per-display state comes from the `Screen` environment object.

## macOS-specific constraints

- Bar windows set `canHide = false`. Depending on what launches doubar, the process can start with `NSApp.isHidden == true`, which hides every window it owns while their frames stay intact. `orderFront:` is a no-op because the app is never active; use `orderFrontRegardless()`.
- Distributed notifications must be observed with `suspensionBehavior: .deliverImmediately` (use `observeDistributed`); Cocoa suspends delivery for inactive apps.
- AeroSpace monitor IDs are 1-based, ordered by display `frame.minX`.
- AeroSpace is found at `/opt/homebrew/bin/aerospace` or `/usr/local/bin/aerospace`.
- Spotify is queried via `osascript` only when it posts `com.spotify.client.PlaybackStateChanged`; the script guards with `is running` so it never launches Spotify.
- Bar windows accept first mouse (`acceptsFirstMouse`) and rely on SwiftUI's `.activeAlways` tracking areas for hover; tooltips (`.help`) never show for an inactive app.
- Peek: AeroSpace parks hidden workspaces' windows off-screen, so `WindowLayout` remembers each window's place from when its workspace was visible (grid fallback). Contents come from ScreenCaptureKit, which captures parked windows fine; it needs Screen Recording permission, granted to whatever launched doubar (the terminal, or the .app when bundled).
- Text input (rename field) uses a `.nonactivatingPanel` that becomes key: it gets the keyboard without activating doubar. Don't `NSApp.activate` for it; since macOS 14 an app can't take activation for itself.
- Icon drags are a `DragGesture` plus a floating ghost panel, not system drag-and-drop (`onDrag` doesn't start reliably from a never-active app). Mouse-dragged events keep going to the bar window the press began in, so drops are found by hit-testing `NSEvent.mouseLocation` against pills' registered screen frames, which also works across displays.
