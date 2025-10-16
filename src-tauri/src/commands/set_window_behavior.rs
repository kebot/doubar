use tauri::{AppHandle, Manager};

fn recreate_window(app: &AppHandle) -> Result<(), String> {
    // Get the current window
    let window = app
        .get_webview_window("main")
        .ok_or("Failed to get main window")?;

    // Hide then show the window
    window.hide().map_err(|e| e.to_string())?;
    window.show().map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub fn set_window_behavior(
    app: AppHandle,
    ignore_cursor_events: Option<bool>,
    always_on_top: Option<bool>,
    always_on_bottom: Option<bool>,
    recreate: Option<bool>,
    focusable: Option<bool>,
) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or("Failed to get main window")?;

    // Validate that always_on_top and always_on_bottom are not both set to true
    if let (Some(true), Some(true)) = (always_on_top, always_on_bottom) {
        return Err("Cannot set both always_on_top and always_on_bottom to true".to_string());
    }

    // Apply ignore_cursor_events if specified
    if let Some(ignore) = ignore_cursor_events {
        window
            .set_ignore_cursor_events(ignore)
            .map_err(|e| e.to_string())?;
    }

    // Apply always_on_top if specified
    if let Some(on_top) = always_on_top {
        window
            .set_always_on_top(on_top)
            .map_err(|e| e.to_string())?;
    }

    // Apply always_on_bottom if specified
    // Note: Tauri v2 has set_always_on_bottom method
    if let Some(on_bottom) = always_on_bottom {
        window
            .set_always_on_bottom(on_bottom)
            .map_err(|e| e.to_string())?;
    }

    // Apply focusable if specified
    if let Some(focus) = focusable {
        window
            .set_focusable(focus)
            .map_err(|e| e.to_string())?;
    }

    // Handle window recreation if specified
    if let Some(true) = recreate {
        recreate_window(&app)?;
    }

    Ok(())
}
