# naming

TauBar: Tauri Bar

## Compare

- [UberSicht](https://tracesof.net/uebersicht/)
- [SketchyBar](https://github.com/FelixKratz/SketchyBar)
- [Zebar](https://github.com/glzr-io/zebar)

## Goals

Instead Config it via yaml/json or other config file, the main config file is a React Component

```tsx
// ~/.config/taubar/App.tsx
import { Time } from 'taobar/component' 

function App () {
    return <Time>
}
```

Competible with UeberSicht's plugin

```tsx

```

## Dev, Tauri + React + TypeScript

- deno task tauri dev

## Recommended IDE Setup

- [VS Code](https://code.visualstudio.com/) + [Tauri](https://marketplace.visualstudio.com/items?itemName=tauri-apps.tauri-vscode) + [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)
