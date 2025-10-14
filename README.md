# Doubar 🚧 🚧 🚧 

⚠️ IT'S HIGHLY WIP, NOT RECOMMENDED FOR AVERAGE USER

## Get started

1. install deno and rust
`brew install deno rust`
2. `deno install`
3. `deno task tauri dev`

See: https://tauri.app/ for more details

## Provided Rust API

```typescript
import { invoke } from '@tauri-apps/api/core'
// get app icon as base64 icons
invoke<string>('<app-name>', { appName })

// running shell command
import { Command } from '@tauri-apps/plugin-shell'

```

## Config API

WIP

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)

## Simular Projects

- [UeberSicht](https://tracesof.net/uebersicht/)
- [SketchyBar](https://github.com/FelixKratz/SketchyBar)
- [Zebar](https://github.com/glzr-io/zebar)

