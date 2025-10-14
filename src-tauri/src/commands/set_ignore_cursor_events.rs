use tauri::{AppHandle, Manager};

#[tauri::command]
pub fn set_ignore_cursor_events(app: AppHandle, ignore: bool) -> Result<(), String> {
    let window = app
        .get_webview_window("main")
        .ok_or("Failed to get main window")?;

    window
        .set_ignore_cursor_events(ignore)
        .map_err(|e| e.to_string())?;

    Ok(())
}
