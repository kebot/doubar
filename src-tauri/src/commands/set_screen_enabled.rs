use crate::{bar_label, create_bar_window, ScreenState};
use tauri::{AppHandle, Manager, State};

#[tauri::command]
pub fn set_screen_enabled(
    app: AppHandle,
    screen_state: State<ScreenState>,
    screen_index: usize,
    enabled: bool,
) -> Result<(), String> {
    let mut disabled = screen_state.0.lock().unwrap();

    if enabled {
        disabled.remove(&screen_index);
        drop(disabled);

        if app.get_webview_window(&bar_label(screen_index)).is_none() {
            let monitors = app.available_monitors().map_err(|e| e.to_string())?;
            if let Some(monitor) = monitors.get(screen_index) {
                create_bar_window(&app, &bar_label(screen_index), monitor)
                    .map_err(|e| e.to_string())?;
            }
        }
    } else {
        disabled.insert(screen_index);
        drop(disabled);

        if let Some(window) = app.get_webview_window(&bar_label(screen_index)) {
            window.close().map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}
