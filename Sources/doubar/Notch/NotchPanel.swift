import AppKit
import Combine
import SwiftUI

/// A transparent panel at the top centre of one display, above the menu
/// bar, big enough for the expanded body plus its glow; one per display.
/// Only the body takes the mouse: everywhere else the panel ignores it,
/// toggled as the pointer moves, so clicks around it reach what's below.
final class NotchPanel: NSPanel {
    /// Room around the expanded notch for the spring's overshoot and the glow.
    private static let margin: CGFloat = 24

    private var site: NotchSite
    private let host: NotchHostingView
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []

    @MainActor
    init(site: NotchSite) {
        self.site = site
        host = NotchHostingView(rootView: NotchView(site: site))
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The notch has no shadow; the glow is drawn by the view.
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Exempt from application-level hiding; see AppDelegate.
        canHide = false

        host.sizingOptions = []
        contentView = host

        place(site)

        let notch = Notch.shared
        notch.$visible.removeDuplicates().sink { [weak self] visible in
            if visible { self?.orderFrontRegardless() } else { self?.orderOut(nil) }
        }.store(in: &subscriptions)
        // The body's size changes: re-check what's under the pointer.
        notch.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.pointerMoved() }
        }.store(in: &subscriptions)

        monitor([.mouseMoved, .leftMouseDragged]) { [weak self] _ in self?.pointerMoved() }
        monitor([.leftMouseDown, .rightMouseDown]) { _ in
            if notch.expanded, !notch.contains(NSEvent.mouseLocation) { notch.collapse() }
        }
        // Esc. Global key events need Accessibility, which doubar already
        // asks for to press status items.
        monitor([.keyDown]) { event in
            if event.keyCode == 53 { notch.collapse() }
        }
    }

    @MainActor
    func place(_ site: NotchSite) {
        if self.site != site {
            self.site = site
            host.rootView = NotchView(site: site)
        }
        let notch = Notch.shared
        let width = NotchLayout.expandedWidth(site) + Self.margin * 2
        let height = NotchLayout.maxHeight(site) + Self.margin
        let f = site.screenFrame
        setFrame(NSRect(x: f.midX - width / 2, y: f.maxY - height, width: width, height: height), display: true)
        if notch.visible { orderFrontRegardless() }
    }

    override func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        super.close()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Keep the panel at the very top of the screen, over the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    @MainActor
    private func pointerMoved() {
        let notch = Notch.shared
        let inside = notch.visible && notch.frame(for: site).contains(NSEvent.mouseLocation)
        if ignoresMouseEvents == inside { ignoresMouseEvents = !inside }
        if notch.visible { notch.pointerMoved() }
    }

    /// Watch `mask` both in other apps and in doubar's own windows.
    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }) {
            monitors.append(local)
        }
    }
}

private final class NotchHostingView: NSHostingView<NotchView> {
    // The app is never active, so without this the first click would be
    // swallowed as a "bring to front" click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    /// The camera housing's size, nil on a display without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea
        else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}
