mod commands;

use std::collections::HashSet;
use std::sync::Mutex;
use tauri::{ActivationPolicy, AppHandle, Emitter, Manager, Monitor, WebviewUrl, WebviewWindowBuilder};

pub struct ScreenState(pub Mutex<HashSet<usize>>);

const OFFSET: i32 = 8;

pub fn bar_label(index: usize) -> String {
    format!("bar_{}", index)
}

pub fn create_bar_window(app: &AppHandle, label: &str, monitor: &Monitor) -> tauri::Result<()> {
    let size = monitor.size();
    let pos = monitor.position();

    let scale = monitor.scale_factor();
    // Builder takes logical pixels; monitor size/position are physical
    let logical_w = (size.width + OFFSET as u32) as f64 / scale;
    let logical_h = (size.height + OFFSET as u32) as f64 / scale;
    let logical_x = (pos.x as f64 - OFFSET as f64 / 2.0) / scale;
    let logical_y = (pos.y as f64 - OFFSET as f64) / scale;

    eprintln!("[doubar] creating window '{}' monitor={}x{} at ({},{}) scale={} → logical {}x{} at ({},{})",
        label, size.width, size.height, pos.x, pos.y, scale,
        logical_w as u32, logical_h as u32, logical_x as i32, logical_y as i32);

    let window = WebviewWindowBuilder::new(app, label, WebviewUrl::default())
        .title("doubar")
        .transparent(true)
        .decorations(false)
        .skip_taskbar(true)
        .resizable(false)
        .always_on_bottom(true)
        .visible_on_all_workspaces(true)
        .inner_size(logical_w, logical_h)
        .position(logical_x, logical_y)
        .visible(false)
        .focused(false)
        .build()?;

    window.set_focusable(false)?;
    window.set_ignore_cursor_events(false)?;

    let actual_pos = window.outer_position()?;
    let actual_size = window.outer_size()?;
    eprintln!("[doubar] '{}' actual physical pos=({},{}) size={}x{}",
        label, actual_pos.x, actual_pos.y, actual_size.width, actual_size.height);

    window.show()?;
    eprintln!("[doubar] '{}' shown, is_visible={:?}", label, window.is_visible());

    Ok(())
}

fn reposition_bar_window(app: &AppHandle, label: &str, monitor: &Monitor) -> tauri::Result<()> {
    let Some(window) = app.get_webview_window(label) else {
        return Ok(());
    };
    let size = monitor.size();
    let pos = monitor.position();
    let scale = monitor.scale_factor();
    window.set_size(tauri::LogicalSize {
        width: (size.width + OFFSET as u32) as f64 / scale,
        height: (size.height + OFFSET as u32) as f64 / scale,
    })?;
    window.set_position(tauri::LogicalPosition {
        x: (pos.x as f64 - OFFSET as f64 / 2.0) / scale,
        y: (pos.y as f64 - OFFSET as f64) / scale,
    })?;
    Ok(())
}

pub fn sync_windows(app: &AppHandle, disabled: &HashSet<usize>) -> tauri::Result<()> {
    let monitors = app.available_monitors()?;

    for (i, monitor) in monitors.iter().enumerate() {
        let label = bar_label(i);
        if disabled.contains(&i) {
            if let Some(w) = app.get_webview_window(&label) {
                w.close()?;
            }
            continue;
        }
        if app.get_webview_window(&label).is_some() {
            reposition_bar_window(app, &label, monitor)?;
        } else {
            create_bar_window(app, &label, monitor)?;
        }
    }

    // Close windows for monitors that no longer exist
    let mut i = monitors.len();
    loop {
        let label = bar_label(i);
        match app.get_webview_window(&label) {
            Some(w) => {
                w.close()?;
                i += 1;
            }
            None => break,
        }
    }

    Ok(())
}

fn monitor_signature(app: &AppHandle) -> Vec<(i32, i32, u32, u32)> {
    app.available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|m| (m.position().x, m.position().y, m.size().width, m.size().height))
        .collect()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            // doubar emit <event_name> [--key value ...]
            let subcmd = argv.get(1).map(|s| s.as_str());
            match subcmd {
                Some("emit") => {
                    let event_name = match argv.get(2).filter(|s| !s.is_empty()) {
                        Some(n) => n,
                        None => {
                            eprintln!("[doubar] emit: missing event name");
                            return;
                        }
                    };
                    let mut params = serde_json::Map::new();
                    for arg in argv.iter().skip(3) {
                        if let Some((k, v)) = arg.split_once('=') {
                            let key = k.trim_start_matches('-').to_string();
                            if key.is_empty() {
                                eprintln!("[doubar] emit: skipping malformed arg '{}'", arg);
                                continue;
                            }
                            params.insert(key, serde_json::Value::String(v.to_string()));
                        } else {
                            eprintln!("[doubar] emit: skipping arg '{}' (expected key=value)", arg);
                        }
                    }
                    let payload = serde_json::Value::Object(params);
                    eprintln!("[doubar] emit '{}' payload={}", event_name, payload);
                    let _ = app.emit(event_name, payload);
                }
                Some(unknown) => {
                    eprintln!("[doubar] unknown subcommand '{}', ignoring", unknown);
                }
                None => {}
            }
        }))
        .manage(ScreenState(Mutex::new(HashSet::new())))
        .invoke_handler(tauri::generate_handler![
            commands::get_app_icon::get_app_icon,
            commands::set_window_behavior::set_window_behavior,
            commands::set_screen_enabled::set_screen_enabled,
        ])
        .setup(|app| {
            app.set_activation_policy(ActivationPolicy::Prohibited);
            app.set_dock_visibility(false);

            let monitors = app.available_monitors()?;
            eprintln!("[doubar] setup: found {} monitor(s)", monitors.len());
            for (i, m) in monitors.iter().enumerate() {
                eprintln!("[doubar]   monitor[{}]: {}x{} at ({},{})",
                    i, m.size().width, m.size().height, m.position().x, m.position().y);
            }

            let disabled = HashSet::new();
            sync_windows(app.handle(), &disabled)?;

            let handle = app.handle().clone();
            std::thread::spawn(move || {
                let mut last_sig = monitor_signature(&handle);
                loop {
                    std::thread::sleep(std::time::Duration::from_secs(2));
                    let sig = monitor_signature(&handle);
                    if sig != last_sig {
                        last_sig = sig;
                        let disabled = handle.state::<ScreenState>().0.lock().unwrap().clone();
                        let _ = sync_windows(&handle, &disabled);
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
