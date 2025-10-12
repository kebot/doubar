# Doubar


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

## Goals

Instead Config it via yaml/json or other config file, the main config file is a React Component

```tsx
// ~/.config/doubar/App.tsx
import { Time } from 'doubar/component' 

function App () {
    return <Time>
}
```

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
