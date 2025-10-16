# Doubar 🚧 🚧 🚧 

<img width="1512" height="982" alt="image" src="https://github.com/user-attachments/assets/242e6542-4043-47e4-89d3-fdb8a970e8a9" />

⚠️ IT'S HIGHLY WIP, NOT RECOMMENDED FOR AVERAGE USER

## Get started

1. install deno and rust
`brew install deno rust`
2. `deno install`
3. `deno task tauri dev`

See: https://tauri.app/ for more details

## Simular Projects

- [UeberSicht](https://tracesof.net/uebersicht/)
- [SketchyBar](https://github.com/FelixKratz/SketchyBar)
- [Zebar](https://github.com/glzr-io/zebar)

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
