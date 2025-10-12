#[cfg(target_os = "macos")]
use objc2_app_kit::{NSBitmapImageRep, NSImage, NSWorkspace};
#[cfg(target_os = "macos")]
use objc2_foundation::{NSDictionary};

/// Converts an NSImage to a base64-encoded PNG data URI
/// Inspired by: https://gist.github.com/hinzundcode/2ca9b9a425b8ed0d9ec4
#[cfg(target_os = "macos")]
fn convert_nsimage_to_base64(icon: &NSImage) -> Result<String, String> {
    // Convert NSImage to TIFF data
    let tiff_data = icon
        .TIFFRepresentation()
        .ok_or_else(|| "Failed to get TIFF representation".to_string())?;

    // Create NSBitmapImageRep from TIFF data
    let bitmap_rep = NSBitmapImageRep::imageRepWithData(&tiff_data)
        .ok_or_else(|| "Failed to create bitmap representation".to_string())?;

    // Convert to PNG using NSBitmapImageRep
    let png_data = unsafe {
        let properties = NSDictionary::new();
        bitmap_rep
            .representationUsingType_properties(
                objc2_app_kit::NSBitmapImageFileType::PNG,
                &*properties,
            )
            .ok_or_else(|| "Failed to convert to PNG".to_string())?
    };

    // Get the raw bytes and encode to base64
    let bytes = png_data.to_vec();
    let base64_str = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &bytes);

    Ok(format!("data:image/png;base64,{}", base64_str))
}

/// Gets the icon of a running application by name and returns it as a base64-encoded PNG data URI
/// 
/// # Arguments
/// * `app_name` - The localized name of the application
/// 
/// # Returns
/// * `Ok(String)` - Base64-encoded PNG data URI of the app icon
/// * `Err(String)` - Error message if the app is not found or icon conversion fails
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
                    return convert_nsimage_to_base64(&icon);
                } else {
                    return Err(format!("Could not get icon for app '{}'", app_name));
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
