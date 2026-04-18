use tauri::{AppHandle, Manager};

#[tauri::command]
pub fn set_window_behavior(
    app: AppHandle,
    label: Option<String>,
    ignore_cursor_events: Option<bool>,
    always_on_top: Option<bool>,
    always_on_bottom: Option<bool>,
    recreate: Option<bool>,
    focusable: Option<bool>,
) -> Result<(), String> {
    if let (Some(true), Some(true)) = (always_on_top, always_on_bottom) {
        return Err("Cannot set both always_on_top and always_on_bottom to true".to_string());
    }

    let windows: Vec<_> = if let Some(lbl) = label {
        match app.get_webview_window(&lbl) {
            Some(w) => vec![w],
            None => return Err(format!("Window '{}' not found", lbl)),
        }
    } else {
        let mut ws = vec![];
        let mut i = 0;
        loop {
            match app.get_webview_window(&format!("bar_{}", i)) {
                Some(w) => { ws.push(w); i += 1; }
                None => break,
            }
        }
        ws
    };

    for window in &windows {
        if let Some(ignore) = ignore_cursor_events {
            window.set_ignore_cursor_events(ignore).map_err(|e| e.to_string())?;
        }
        if let Some(on_top) = always_on_top {
            window.set_always_on_top(on_top).map_err(|e| e.to_string())?;
        }
        if let Some(on_bottom) = always_on_bottom {
            window.set_always_on_bottom(on_bottom).map_err(|e| e.to_string())?;
        }
        if let Some(focus) = focusable {
            window.set_focusable(focus).map_err(|e| e.to_string())?;
        }
        if let Some(true) = recreate {
            window.hide().map_err(|e| e.to_string())?;
            window.show().map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}
