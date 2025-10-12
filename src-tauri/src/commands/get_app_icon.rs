#[cfg(target_os = "macos")]
use objc2_app_kit::NSWorkspace;

// https://tauri.app/develop/calling-rust/
#[cfg(target_os = "macos")]
#[tauri::command]
pub fn get_app_icon(app_name: String) -> Result<String, String> {
    // Get shared workspace
    let workspace = NSWorkspace::sharedWorkspace();

    // Get all running applications
    let running_apps = workspace.runningApplications();

    // Find the app by name - iterate through the array
    for app in running_apps.iter() {
        if let Some(localized_name) = app.localizedName() {
            let name = localized_name.to_string();

            if name == app_name {
                // Get the app icon
                if let Some(icon) = app.icon() {
                    // Convert NSImage to TIFF data
                    if let Some(tiff_data) = icon.TIFFRepresentation() {
                        // Get the raw bytes from NSData as a Vec
                        let bytes = tiff_data.to_vec();

                        // Convert TIFF to PNG using image crate
                        if let Ok(img) = image::load_from_memory(&bytes) {
                            let mut png_data = Vec::new();
                            let mut cursor = std::io::Cursor::new(&mut png_data);

                            if img
                                .write_to(&mut cursor, image::ImageFormat::Png)
                                .is_ok()
                            {
                                // Encode to base64
                                let base64_str = base64::Engine::encode(
                                    &base64::engine::general_purpose::STANDARD,
                                    &png_data,
                                );
                                return Ok(format!("data:image/png;base64,{}", base64_str));
                            }
                        }
                    }
                }
            }
        }
    }

    Err(format!("App '{}' not found", app_name))
}

#[cfg(not(target_os = "macos"))]
#[tauri::command]
pub fn get_app_icon(_app_name: String) -> Result<String, String> {
    Err("This command is only available on macOS".to_string())
}
