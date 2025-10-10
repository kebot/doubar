use tauri::{Manager, PhysicalPosition, PhysicalSize, ActivationPolicy};

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
            // https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/prohibited?language=objc
            // Description: The application doesn’t appear in the Dock and may not create windows or be activated.
            app.set_activation_policy(ActivationPolicy::Prohibited);

            app.set_dock_visibility(false);

            let window = app.get_webview_window("main").unwrap();

            // Get the primary monitor
            if let Some(monitor) = window.current_monitor()? {
                let screen_size = monitor.size();
                let window_height = 60;

                // Set window size and position
                window.set_size(PhysicalSize {
                    width: screen_size.width,
                    height: window_height,
                })?;
                window.set_position(PhysicalPosition { x: 0, y: 0 })?;
                window.set_focusable(false)?;
                window.set_visible_on_all_workspaces(true)?;
                window.set_skip_taskbar(true)?;
                window.set_always_on_bottom(true)?;
                window.show()?;
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
