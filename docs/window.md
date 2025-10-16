- Like übersicht there's only one webview in `doubar`.

## Window

- the window is full screen SO it can covers the Notch area

### Control the window for intractive

```typescript
import { invoke } from '@tauri-apps/api/core'

// top most window with cursor events not ignored: usecase: Modal
// this will make other part of the component not controlable by Mouse
invoke('set_window_behavior', {
  ignore_cursor_events: false,
  always_on_top: true,
})

// widgets not intractive excepts the bar
invoke('set_window_behavior', {
  ignore_cursor_events: true,
  always_on_top: true,
})

// window on bottom with cursor events enabled
invoke('set_window_behavior', {
  ignore_cursor_events: false,
  always_on_bottom: true,
})

```
