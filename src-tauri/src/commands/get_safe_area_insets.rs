use objc2_app_kit::NSScreen;
use objc2_foundation::MainThreadMarker;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct NotchInfo {
    pub has_notch: bool,
    pub notch_width: f64,
    pub notch_height: f64,
    pub screen_width: f64,
    pub screen_height: f64,
}

#[tauri::command]
pub fn get_safe_area_insets() -> Result<NotchInfo, String> {
    // Get the main thread marker (required for Cocoa APIs)
    let mtm = unsafe { MainThreadMarker::new_unchecked() };
    
    // Get the main screen
    let main_screen = NSScreen::mainScreen(mtm)
        .ok_or_else(|| "No main screen found".to_string())?;
    
    // Get the auxiliary areas (notch-adjacent areas)
    let left_area = main_screen.auxiliaryTopLeftArea();
    let right_area = main_screen.auxiliaryTopRightArea();
    
    // Get the screen frame
    let frame = main_screen.frame();
    
    // If either auxiliary area has width, there's a notch
    let has_notch = left_area.size.width > 0.0 || right_area.size.width > 0.0;
    
    // Calculate the notch width
    // The notch is the gap between the left and right auxiliary areas
    let notch_width = if has_notch {
        // The notch width is screen width minus the two auxiliary areas
        frame.size.width - left_area.size.width - right_area.size.width
    } else {
        0.0
    };
    
    // The notch height is the height of the auxiliary areas
    let notch_height = if has_notch {
        left_area.size.height.max(right_area.size.height)
    } else {
        0.0
    };
    
    // Debug print only in debug builds
    if cfg!(debug_assertions) {
        println!(
            "[tauri] notch detection → has_notch: {}, notch_width: {:.1}, notch_height: {:.1}, screen: {:.1}x{:.1}, left_area_w: {:.1}, right_area_w: {:.1}",
            has_notch,
            notch_width,
            notch_height,
            frame.size.width,
            frame.size.height,
            left_area.size.width,
            right_area.size.width
        );
    }

    Ok(NotchInfo {
        has_notch,
        notch_width,
        notch_height,
        screen_width: frame.size.width,
        screen_height: frame.size.height,
    })
}
