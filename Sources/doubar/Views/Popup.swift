import AppKit
import SwiftUI

/// Base for doubar's floating panels (the peek preview, the rename field,
/// the drag ghost): borderless and transparent, above app windows on every
/// Space, never hidden with the app, never main. Subclasses opt into key
/// status or click-through as they need.
class PopupPanel: NSPanel {
    let host = PopupHostingView(rootView: AnyView(EmptyView()))

    init(size: NSSize = .zero) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        // Exempt from application-level hiding; see AppDelegate.
        canHide = false
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show `view` sized to fit, `gap` below `anchor` and starting `inset`
    /// left of it, kept inside the screen the anchor is on.
    func setContent(_ view: some View, below anchor: NSRect, gap: CGFloat, inset: CGFloat = 0) {
        host.rootView = AnyView(view)
        let size = host.fittingSize
        let bounds = NSScreen.containing(anchor)?.frame ?? anchor
        let x = min(max(anchor.minX - inset, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = max(anchor.minY - gap - size.height, bounds.minY + 8)
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }

    /// Resize to `size` as the content changes, keeping the top edge where
    /// it is and the panel inside its screen.
    func fit(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != frame.size else { return }
        let bounds = NSScreen.containing(frame)?.frame ?? frame
        let x = min(frame.minX, bounds.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }
}

final class PopupHostingView: NSHostingView<AnyView> {
    // The app is never active, so without this the first click would be
    // swallowed as a "bring to front" click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    static func containing(_ rect: NSRect) -> NSScreen? {
        screens.first { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }
    }

    /// Where a popup for `workspace` goes when no pill is under the pointer
    /// (e.g. opened from `doubar emit`): just below the bar, at the left of
    /// the workspace's monitor, or of the main display.
    @MainActor
    static func barAnchor(for workspace: String) -> (anchor: NSRect, monitorId: Int)? {
        let monitorId = AeroSpace.shared.windows.first { $0.workspace == workspace }?.monitorId
            ?? NSScreen.main?.aeroSpaceMonitorId ?? 1
        guard let screen = forAeroSpaceMonitor(monitorId) else { return nil }
        let f = screen.frame
        return (NSRect(x: f.minX + 10, y: f.maxY - BarWindow.height + 4, width: 0, height: 0), monitorId)
    }
}
