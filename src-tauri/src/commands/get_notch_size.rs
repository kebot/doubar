use objc2_app_kit::NSScreen;
use objc2_foundation::MainThreadMarker;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct NotchSize {
    pub width: f64,
    pub height: f64,
    pub top_inset: f64,
}

#[derive(Debug, Serialize)]
pub struct SafeAreaInsets {
    pub top: f64,
    pub bottom: f64,
    pub left: f64,
    pub right: f64,
}

#[tauri::command]
pub fn get_notch_size() -> Result<NotchSize, String> {
    // Get the main thread marker (required for AppKit APIs)
    let mtm = MainThreadMarker::new().ok_or("Must be called on main thread")?;

    // Get the main screen
    let screen = NSScreen::mainScreen(mtm).ok_or("Failed to get main screen")?;

    // Get safe area insets (notch intrudes from the top)
    let safe_area = screen.safeAreaInsets();

    // Get the screen frame to calculate notch width
    let frame = screen.frame();

    // The notch typically spans a portion of the screen width
    // For a more accurate width, we'd need to calculate the difference
    // between the full width and the safe area, but the safe area
    // only gives us top/bottom/left/right insets.

    // The top inset represents the notch height
    let notch_height = safe_area.top;

    // For now, we'll estimate the notch width based on typical MacBook Pro dimensions
    // In reality, the notch width isn't directly exposed by the API
    // A more accurate method would be to measure the menu bar spacing
    let notch_width = if notch_height > 0.0 {
        // Typical notch width is around 200-230 pixels at 2x scale
        frame.size.width * 0.12 // Approximately 12% of screen width
    } else {
        0.0
    };

    Ok(NotchSize {
        width: notch_width,
        height: notch_height,
        top_inset: safe_area.top,
    })
}

#[tauri::command]
pub fn get_safe_area_insets() -> Result<SafeAreaInsets, String> {
    let mtm = MainThreadMarker::new().ok_or("Must be called on main thread")?;
    let screen = NSScreen::mainScreen(mtm).ok_or("Failed to get main screen")?;
    let safe_area = screen.safeAreaInsets();

    Ok(SafeAreaInsets {
        top: safe_area.top,
        bottom: safe_area.bottom,
        left: safe_area.left,
        right: safe_area.right,
    })
}
