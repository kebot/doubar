# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Doubar is a macOS menu bar replacement built with Tauri v2 + React + TypeScript. The app renders a transparent, always-on-bottom, click-through window spanning the full screen width, positioned at the top. It has no Dock icon and cannot be focused — it behaves purely as a desktop overlay bar.

## Commands

```bash
make dev          # start Tauri dev server (hot reload)
make install      # install JS dependencies with bun
make build  # production build (aarch64)
```

The Vite dev server is hardcoded to port 1420 (`strictPort: true`).

## Architecture

### Frontend (src/)

- `main.tsx` — entry point; mounts `<App>` into the DOM
- `App.tsx` — top-level layout; assembles the bar from widgets
- `components/Bar.tsx` — `<Bar left right>` layout component and `<Pill>` — the styled capsule used for all bar items
- `widgets/` — self-contained bar widgets:
  - `AeroSpace/` — shows AeroSpace workspaces; uses Zustand store that shells out to `/opt/homebrew/bin/aerospace` via Tauri's shell plugin
  - `Time.tsx` — clock widget
- `dev/DevMain.tsx` — browser-only dev harness that mocks `window.__TAURI_INTERNALS__` so the UI can be iterated without running Tauri

### Rust backend (src-tauri/src/)

Two Tauri commands registered in `lib.rs`:

| Command | File | Purpose |
|---|---|---|
| `get_app_icon` | `commands/get_app_icon.rs` | Returns a running app's icon as a base64 PNG data URI via macOS `NSWorkspace` (objc2 bindings) |
| `set_window_behavior` | `commands/set_window_behavior.rs` | Dynamically changes window properties: `ignore_cursor_events`, `always_on_top/bottom`, `focusable`, `recreate` |

`lib.rs` `setup` hook positions the window to match the primary monitor frame (with an 8px bleed offset to hide the 2px Tauri border) and sets `ActivationPolicy::Prohibited` so the app never appears in the Dock or Cmd+Tab switcher.

### Tauri JS API usage pattern

```typescript
import { invoke } from '@tauri-apps/api/core'
invoke<string>('get_app_icon', { appName })

import { Command } from '@tauri-apps/plugin-shell'
Command.create('exec-sh', ['-c', `aerospace ... --json`]).execute()
```

### Styling

Tailwind CSS v4 (via `@tailwindcss/vite`). CSS variables `--bar-height` and `--background`/`--foreground` control theming. The `Pill` component is the atomic UI unit for bar items.

## macOS-specific constraints

- The window uses `macOSPrivateApi: true` in `tauri.conf.json` for `alwaysOnBottom` support.
- `get_app_icon.rs` is `#[cfg(target_os = "macos")]` only — do not call it on other platforms.
- AeroSpace queries hardcode `/opt/homebrew/bin/aerospace` — requires Homebrew on Apple Silicon.
