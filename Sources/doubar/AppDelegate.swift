import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// One bar per display, keyed by CGDirectDisplayID.
    private var bars: [CGDirectDisplayID: BarWindow] = [:]
    private var reassertWork: [DispatchWorkItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Depending on what launches doubar, the process can come up with
        // AppKit's application-hidden flag set, which hides every window it
        // owns. BarWindow also sets canHide = false; this covers the rest.
        if NSApp.isHidden {
            log("NSApp was hidden at startup, unhiding")
            NSApp.unhide(nil)
        }

        IPC.listen { event, params in
            log("event '\(event)' \(params)")
            switch event {
            case "aerospace": AeroSpace.shared.refresh()
            case "peek": Peek.shared.peek(params["workspace"])
            case "rename":
                guard let workspace = params["workspace"] else {
                    Rename.shared.end()
                    break
                }
                if let name = params["name"] {
                    WorkspaceNames.shared.set(name, for: workspace)
                } else {
                    Rename.shared.begin(workspace)
                }
            default: break
            }
        }

        syncBars()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
        // Waking from sleep can leave windows ordered out.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
    }

    private func screensChanged() {
        syncBars()
        // macOS can order our windows out after the screen list has already
        // changed, while the reconfiguration settles. Re-assert a few times.
        reassertWork.forEach { $0.cancel() }
        reassertWork = [0.25, 1, 3].map { delay in
            let work = DispatchWorkItem { [weak self] in
                self?.bars.values.forEach { $0.orderFrontRegardless() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private func syncBars() {
        let screens = NSScreen.screens
        // A reconfiguration can momentarily report no screens at all; tearing
        // every bar down then would just blank the display for a moment.
        guard !screens.isEmpty else {
            log("no screens reported, skipping sync")
            return
        }

        let byPosition = NSScreen.byAeroSpaceMonitor
        var seen = Set<CGDirectDisplayID>()

        for screen in screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            let monitorId = (byPosition.firstIndex(of: screen) ?? 0) + 1
            if let bar = bars[id] {
                bar.place(on: screen, monitorId: monitorId)
            } else {
                log("creating bar for display \(id) (monitor \(monitorId)) frame=\(screen.frame)")
                bars[id] = BarWindow(screen: screen, monitorId: monitorId)
            }
        }

        for (id, bar) in bars where !seen.contains(id) {
            log("display \(id) gone, closing its bar")
            bar.close()
            bars[id] = nil
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Screens in AeroSpace monitor order: 1-based, left to right.
    static var byAeroSpaceMonitor: [NSScreen] {
        screens.sorted { $0.frame.minX < $1.frame.minX }
    }

    static func forAeroSpaceMonitor(_ monitorId: Int) -> NSScreen? {
        let all = byAeroSpaceMonitor
        return all.indices.contains(monitorId - 1) ? all[monitorId - 1] : nil
    }
}
