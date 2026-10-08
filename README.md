# Doubar 🚧 🚧 🚧 

<img width="1512" height="982" alt="image" src="https://github.com/user-attachments/assets/242e6542-4043-47e4-89d3-fdb8a970e8a9" />

⚠️ IT'S HIGHLY WIP, NOT RECOMMENDED FOR AVERAGE USER

A native macOS bar written in Swift (AppKit + SwiftUI): AeroSpace workspaces,
a clock, and Spotify controls with synced lyrics in the notch.

## Get started

Requires the Xcode command line tools (`xcode-select --install`).

```bash
make dev     # build and run in the foreground
make link    # release build, symlinked to ~/.local/bin/doubar
make bundle  # .build/doubar.app, for Login Items
```

## AeroSpace integration

Hook AeroSpace events into the running bar with `doubar emit`:

```toml
on-focus-changed = ['exec-and-forget doubar emit aerospace']
exec-on-workspace-change = ['/bin/bash', '-c', 'doubar emit aerospace']
```

`doubar emit <event> [key=value ...]` posts the event to the running bar and
exits. It never starts a bar itself.

## Using it

- Click a workspace to go there. Click an icon to focus that window.
- Scroll over the workspaces to step through them.
- Drag an app icon onto another workspace to move that window there. While
  dragging, a `+` pill offers the first empty workspace.
- Right-click a workspace to rename it. Names are labels kept by doubar
  (AeroSpace can't rename workspaces); a blank name clears it. From a
  script: `doubar emit rename workspace=1 name=Code`.
- Hover another workspace to peek at it live; click a window in the preview
  to jump to it. `doubar emit peek workspace=3` opens a preview from a key
  binding or script. Previews need Screen Recording permission; without it
  they show app icons only.

## Similar Projects

- [UeberSicht](https://tracesof.net/uebersicht/)
- [SketchyBar](https://github.com/FelixKratz/SketchyBar)
- [Zebar](https://github.com/glzr-io/zebar)
- [omacosy bar](https://github.com/paulsp94/omacosy/blob/main/helper/bar.swift)
