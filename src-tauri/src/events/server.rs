use serde::{Deserialize, Serialize};
use std::io::Read;
use std::sync::Arc;
use tauri::{AppHandle, Emitter};
use tiny_http::{Response, Server};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventPayload {
    #[serde(rename = "type")]
    pub event_type: String,
    #[serde(default)]
    pub data: serde_json::Value,
}

pub fn start_event_server(app_handle: AppHandle, port: u16) -> Result<(), String> {
    let server = Server::http(format!("127.0.0.1:{}", port))
        .map_err(|e| format!("Failed to start HTTP server on port {}: {}", port, e))?;

    let server = Arc::new(server);

    println!("Event server listening on http://127.0.0.1:{}", port);
    println!("Send events with: curl -X POST http://127.0.0.1:{}/events -H 'Content-Type: application/json' -d '{{\"type\":\"your-event\",\"data\":{{}}}}'", port);

    std::thread::spawn(move || {
        for mut request in server.incoming_requests() {
            let method = request.method().to_string();
            let url = request.url().to_string();

            // Handle CORS preflight
            if method == "OPTIONS" {
                let response = Response::from_string("")
                    .with_header(
                        tiny_http::Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..])
                            .unwrap(),
                    )
                    .with_header(
                        tiny_http::Header::from_bytes(
                            &b"Access-Control-Allow-Methods"[..],
                            &b"POST, OPTIONS"[..],
                        )
                        .unwrap(),
                    )
                    .with_header(
                        tiny_http::Header::from_bytes(
                            &b"Access-Control-Allow-Headers"[..],
                            &b"Content-Type"[..],
                        )
                        .unwrap(),
                    );
                let _ = request.respond(response);
                continue;
            }

            // Handle POST /events
            if method == "POST" && url == "/events" {
                let mut content = String::new();
                if let Err(e) = request.as_reader().read_to_string(&mut content) {
                    eprintln!("Failed to read request body: {}", e);
                    let response = Response::from_string(format!("{{\"error\":\"Failed to read request: {}\"}}", e))
                        .with_status_code(400);
                    let _ = request.respond(response);
                    continue;
                }

                match serde_json::from_str::<EventPayload>(&content) {
                    Ok(payload) => {
                        println!("Received event: {:?}", payload);

                        // Emit event to frontend
                        if let Err(e) = app_handle.emit("external-event", payload.clone()) {
                            eprintln!("Failed to emit event to frontend: {}", e);
                        }

                        let response = Response::from_string(format!("{{\"success\":true,\"type\":\"{}\"}}", payload.event_type))
                            .with_header(
                                tiny_http::Header::from_bytes(&b"Access-Control-Allow-Origin"[..], &b"*"[..])
                                    .unwrap(),
                            )
                            .with_header(
                                tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..])
                                    .unwrap(),
                            );
                        let _ = request.respond(response);
                    }
                    Err(e) => {
                        eprintln!("Failed to parse JSON: {}", e);
                        let response = Response::from_string(format!("{{\"error\":\"Invalid JSON: {}\"}}", e))
                            .with_status_code(400)
                            .with_header(
                                tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..])
                                    .unwrap(),
                            );
                        let _ = request.respond(response);
                    }
                }
            } else {
                // Handle other routes
                let response = Response::from_string(format!("{{\"error\":\"Not found. Use POST /events\"}}"))
                    .with_status_code(404)
                    .with_header(
                        tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..])
                            .unwrap(),
                    );
                let _ = request.respond(response);
            }
        }
    });

    Ok(())
}

pub fn try_start_event_server(app_handle: AppHandle, preferred_port: u16, max_attempts: u16) -> Result<u16, String> {
    for attempt in 0..max_attempts {
        let port = preferred_port + attempt;
        match start_event_server(app_handle.clone(), port) {
            Ok(_) => return Ok(port),
            Err(e) => {
                if attempt == max_attempts - 1 {
                    return Err(format!("Failed to start server after {} attempts. Last error: {}", max_attempts, e));
                }
                eprintln!("Port {} unavailable, trying next port...", port);
            }
        }
    }
    Err("Failed to start event server".to_string())
}
