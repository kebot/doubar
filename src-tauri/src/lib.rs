use tauri::{Manager, PhysicalPosition, PhysicalSize};

// Learn more about Tauri commands at https://tauri.app/develop/calling-rust/
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![greet])
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();

            // Get the primary monitor
            if let Some(monitor) = window.current_monitor()? {
                let screen_size = monitor.size();
                let window_height = 60;

                // Set window size to match screen width
                window.set_size(PhysicalSize {
                    width: screen_size.width,
                    height: window_height,
                })?;

                // Position at top of screen
                window.set_position(PhysicalPosition {
                    x: 0,
                    y: 0,
                })?;

                // Keep window always on top
                window.set_always_on_top(true)?;
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
