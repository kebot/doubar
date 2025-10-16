mod commands;

use tauri::{ActivationPolicy, Manager, PhysicalPosition, PhysicalSize};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            commands::get_app_icon::get_app_icon,
            commands::set_window_behavior::set_window_behavior
        ])
        .setup(|app| {
            // https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/prohibited?language=objc
            // Description: The application doesn’t appear in the Dock and may not create windows or be activated.
            app.set_activation_policy(ActivationPolicy::Prohibited);

            app.set_dock_visibility(false);

            let window = app.get_webview_window("main").unwrap();

            // Get the built-in screen (primary monitor)
            if let Some(monitor) = window.current_monitor()? {
                let screen_frame = monitor.size();
                let screen_position = monitor.position();

                let offset: u32 = 8;

                // Set window size to match screen frame width and maintain height
                // there's a 2px border around the window
                window.set_size(PhysicalSize {
                    width: screen_frame.width + offset,
                    height: screen_frame.height + offset,
                })?;

                window.set_position(PhysicalPosition {
                    x: screen_position.x - offset as i32 / 2,
                    y: screen_position.y - offset as i32,
                })?;

                window.set_focusable(false)?;
                window.set_visible_on_all_workspaces(true)?;

                window.set_skip_taskbar(false)?;

                window.set_always_on_bottom(true)?;

                // window.set_always_on_top(false)?;
                // Make transparent areas click-through by default
                window.set_ignore_cursor_events(false)?;

                window.show()?;
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
