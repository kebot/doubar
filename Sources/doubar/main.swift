import AppKit

// doubar                      start the bar
// doubar emit <event> [k=v]   forward an event to the running bar, then exit
// doubar check-config         report problems in config.toml and theme.toml
//
// `emit` never starts a bar. AeroSpace hooks call it on every focus change,
// so if it could become the primary instance a stray hook would launch the
// bar from AeroSpace's environment instead of the user's.
let argv = CommandLine.arguments
switch argv.dropFirst().first {
case "emit":
    exit(IPC.emit(Array(argv.dropFirst(2))))
case "check-config":
    exit(Config.check())
case nil:
    break
case let unknown?:
    log("unknown subcommand '\(unknown)'")
    exit(64)
}

guard SingleInstance.acquire() else {
    log("another doubar is already running, exiting")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon, no Cmd+Tab entry, never the active app.
app.setActivationPolicy(.accessory)
app.run()
