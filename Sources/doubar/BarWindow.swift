import AppKit
import SwiftUI

/// Per-bar state the SwiftUI tree reads.
final class Screen: ObservableObject {
    @Published var monitorId: Int
    /// The bar window's frame in screen coordinates, to place popups.
    var windowFrame: NSRect = .zero
    init(monitorId: Int) { self.monitorId = monitorId }

    /// Convert a rect in SwiftUI's top-left window space to AppKit screen
    /// coordinates.
    func toScreen(_ r: CGRect) -> NSRect {
        NSRect(x: windowFrame.minX + r.minX, y: windowFrame.maxY - r.maxY, width: r.width, height: r.height)
    }
}

/// A transparent strip along the top edge of one display, sitting just
/// below normal windows and on every Space. It takes clicks, hover and
/// scroll without ever activating the app or taking key focus.
final class BarWindow: NSPanel {
    static let height: CGFloat = 30

    private let screenState: Screen

    init(screen: NSScreen, monitorId: Int) {
        screenState = Screen(monitorId: monitorId)
        screenState.windowFrame = Self.frame(on: screen)
        super.init(
            contentRect: Self.frame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        // Hover tracking needs mouse-moved events even though the app is
        // never active; SwiftUI's own tracking areas take it from there.
        acceptsMouseMovedEvents = true
        // Always on bottom: under every normal window, above the desktop.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        // Exempt the bar from application-level hiding; see AppDelegate.
        canHide = false

        let host = BarHostingView(rootView: AnyView(BarView().environmentObject(screenState)))
        host.sizingOptions = []
        host.screen = screenState
        contentView = host

        orderFrontRegardless()
    }

    func place(on screen: NSScreen, monitorId: Int) {
        if screenState.monitorId != monitorId { screenState.monitorId = monitorId }
        screenState.windowFrame = Self.frame(on: screen)
        setFrame(screenState.windowFrame, display: true)
        // The app is never active, so plain orderFront: is a no-op.
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The full width of the display, flush with its top edge so the bar
    /// can cover the notch area.
    private static func frame(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        return NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height)
    }
}

private final class BarHostingView: NSHostingView<AnyView> {
    weak var screen: Screen?
    private var scrollAccumulator: CGFloat = 0

    // The app is never active, so without this the first click on the bar
    // would be swallowed as a "bring to front" click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI on macOS 14 has no scroll-wheel modifier, so wheel and
    /// trackpad scrolls over the workspace pills are turned into steps here.
    override func scrollWheel(with event: NSEvent) {
        guard AeroSpace.enabled, let screen, let window else { return }
        // Only the horizontal span matters: the bar is barely taller than
        // the pills, and missing them by a few points shouldn't count.
        let x = window.convertPoint(toScreen: event.locationInWindow).x
        guard PillFrames.span(on: screen.monitorId)?.contains(x) == true, event.momentumPhase.isEmpty
        else { return }

        if event.phase == .began { scrollAccumulator = 0 }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 30
        scrollAccumulator += delta
        // One step per notch, or per ~30pt of trackpad travel.
        guard abs(scrollAccumulator) >= 30 else { return }
        let step = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        Task { @MainActor in AeroSpace.shared.step(step, on: screen.monitorId) }
    }
}
