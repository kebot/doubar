import AppKit
import ScreenCaptureKit
import SwiftUI

// Peek before you jump: hovering another workspace's pill opens a live
// miniature of it below the bar. Click a window in it to jump there.

/// Where each window sits on its display, as a fraction of the display.
/// AeroSpace parks the windows of hidden workspaces off-screen, so this is
/// remembered from the last time each window's workspace was visible.
@MainActor
enum WindowLayout {
    private static var frames: [Int: CGRect] = [:]
    private static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func record(_ windows: [AeroSpace.Window]) {
        guard !windows.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return }

        var bounds: [Int: CGRect] = [:]
        for w in info {
            guard let n = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String],
                  let r = CGRect(dictionaryRepresentation: b as! CFDictionary)
            else { continue }
            bounds[n] = r
        }

        for w in windows {
            guard let r = bounds[w.windowId],
                  let display = NSScreen.forAeroSpaceMonitor(w.monitorId)?.displayID
            else { continue }
            let d = CGDisplayBounds(display)
            frames[w.windowId] = CGRect(
                x: (r.minX - d.minX) / d.width, y: (r.minY - d.minY) / d.height,
                width: r.width / d.width, height: r.height / d.height)
        }
    }

    /// A unit-space rect (top-left origin) per window: their remembered
    /// places, or an even grid when any of them has never been seen.
    static func layout(_ windows: [AeroSpace.Window]) -> [CGRect] {
        let known = windows.compactMap { frames[$0.windowId]?.intersection(unit) }
        if known.count == windows.count, known.allSatisfy({ !$0.isEmpty }) { return known }

        let cols = max(1, Int(Double(windows.count).squareRoot().rounded(.up)))
        let rows = max(1, (windows.count + cols - 1) / cols)
        let w = 1 / CGFloat(cols), h = 1 / CGFloat(rows)
        return windows.indices.map { i in
            CGRect(x: CGFloat(i % cols) * w, y: CGFloat(i / cols) * h, width: w, height: h)
        }
    }
}

/// Window contents via ScreenCaptureKit, which (unlike the window list's
/// bounds) works for AeroSpace's parked windows too.
enum Thumbnails {
    static func capture(_ ids: [Int], maxPixels: CGFloat) async -> [Int: CGImage] {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [:] }

        let windows = content.windows.filter { ids.contains(Int($0.windowID)) }
        return await withTaskGroup(of: (Int, CGImage?).self) { group in
            for w in windows {
                group.addTask {
                    let scale = min(1, maxPixels / max(w.frame.width, w.frame.height, 1))
                    let cfg = SCStreamConfiguration()
                    cfg.width = max(1, Int(w.frame.width * scale))
                    cfg.height = max(1, Int(w.frame.height * scale))
                    cfg.showsCursor = false
                    let image = try? await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
                    return (Int(w.windowID), image)
                }
            }
            var out: [Int: CGImage] = [:]
            for await (id, image) in group { if let image { out[id] = image } }
            return out
        }
    }
}

@MainActor
final class Peek: ObservableObject {
    static let shared = Peek()

    /// Captured window contents, kept between peeks so a reopened preview
    /// shows something immediately while the fresh capture runs.
    @Published private(set) var images: [Int: CGImage] = [:]

    private(set) var workspace: String?
    private var panel: PeekPanel?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var captureTimer: Timer?
    private var panelHovered = false
    private var askedForPermission = false

    /// Longest side of the miniature screen.
    private static let miniature: CGFloat = 480

    func pillHover(_ name: String, monitorId: Int, anchor: NSRect, hovering: Bool) {
        // Pills under a dragged icon are drop targets, not peeks.
        guard WindowDrag.shared.window == nil else { return }
        guard hovering else {
            showWork?.cancel()
            scheduleHide()
            return
        }
        hideWork?.cancel()
        guard name != AeroSpace.shared.focusedWorkspace else {
            hide()
            return
        }
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.show(name, monitorId: monitorId, anchor: anchor) }
        showWork = work
        // A short intent delay so sweeping across the bar doesn't flash
        // previews; once one is open, moving between pills switches at once.
        DispatchQueue.main.asyncAfter(deadline: .now() + (workspace == nil ? 0.25 : 0), execute: work)
    }

    /// Open the preview of `name` without hovering (`doubar emit peek
    /// workspace=<name>`), anchored to the bar of its monitor; nil closes it.
    /// It closes itself after a few seconds unless the pointer moves onto it.
    func peek(_ name: String?) {
        guard let name,
              let monitorId = AeroSpace.shared.windows.first(where: { $0.workspace == name })?.monitorId,
              let screen = NSScreen.forAeroSpaceMonitor(monitorId)
        else {
            hide()
            return
        }
        let f = screen.frame
        let anchor = NSRect(x: f.minX + 10, y: f.maxY - BarWindow.height + 4, width: 0, height: 0)
        show(name, monitorId: monitorId, anchor: anchor)
        scheduleHide(after: 3)
    }

    func panelHover(_ hovering: Bool) {
        panelHovered = hovering
        if hovering { hideWork?.cancel() } else { scheduleHide() }
    }

    func jump(to window: AeroSpace.Window) {
        hide()
        AeroSpace.shared.focus(window: window)
    }

    func hide() {
        showWork?.cancel()
        hideWork?.cancel()
        captureTimer?.invalidate()
        captureTimer = nil
        workspace = nil
        panelHovered = false
        panel?.orderOut(nil)
    }

    private func scheduleHide(after delay: TimeInterval = 0.3) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panelHovered else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(_ name: String, monitorId: Int, anchor: NSRect) {
        let windows = AeroSpace.shared.windows.filter { $0.workspace == name }
        guard !windows.isEmpty, let screen = NSScreen.forAeroSpaceMonitor(monitorId) else { return }

        if !CGPreflightScreenCaptureAccess(), !askedForPermission {
            askedForPermission = true
            CGRequestScreenCaptureAccess()
        }

        let aspect = screen.frame.width / screen.frame.height
        let size = aspect >= 1
            ? CGSize(width: Self.miniature, height: Self.miniature / aspect)
            : CGSize(width: Self.miniature * aspect, height: Self.miniature)

        let panel = self.panel ?? PeekPanel()
        self.panel = panel
        panel.show(
            PeekView(name: name, windows: windows, rects: WindowLayout.layout(windows), size: size),
            below: anchor, on: screen)
        workspace = name

        // Refresh the miniature while it is open, so it is a live view.
        captureTimer?.invalidate()
        let ids = windows.map(\.windowId)
        capture(ids)
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture(ids) }
        }
    }

    private func capture(_ ids: [Int]) {
        Task {
            let fresh = await Thumbnails.capture(ids, maxPixels: Self.miniature * 2)
            guard workspace != nil else { return }
            images.merge(fresh) { $1 }
        }
    }
}

private final class PeekPanel: NSPanel {
    private let host = PeekHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        canHide = false
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ view: PeekView, below anchor: NSRect, on screen: NSScreen) {
        host.rootView = AnyView(view)
        let size = host.fittingSize
        let bounds = screen.frame
        let x = min(max(anchor.minX - 20, bounds.minX + 8), bounds.maxX - size.width - 8)
        let frame = NSRect(x: x, y: anchor.minY - 8 - size.height, width: size.width, height: size.height)
        setFrame(frame, display: true)
        invalidateShadow()

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        }
    }
}

private final class PeekHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PeekView: View {
    let name: String
    let windows: [AeroSpace.Window]
    let rects: [CGRect]
    let size: CGSize

    @ObservedObject private var peek = Peek.shared
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(["Workspace \(name)", WorkspaceNames.shared[name]].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(windows.count) WINDOW\(windows.count == 1 ? "" : "S")")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.foreground.opacity(0.6))
            }

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.3)
                ForEach(Array(zip(windows, rects)), id: \.0.id) { window, rect in
                    tile(window)
                        .frame(width: rect.width * size.width - 4, height: rect.height * size.height - 4)
                        .offset(x: rect.minX * size.width + 2, y: rect.minY * size.height + 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground.opacity(0.15)))

            Text("Click a window to jump to it")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.foreground.opacity(0.5))
        }
        .padding(20)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground.opacity(0.15))))
        .foregroundStyle(Theme.foreground)
        .onHover { peek.panelHover($0) }
    }

    private func tile(_ window: AeroSpace.Window) -> some View {
        let isHovered = hovered == window.windowId
        return ZStack(alignment: .bottomLeading) {
            if let image = peek.images[window.windowId] {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                // No capture yet, or no Screen Recording permission.
                Theme.foreground.opacity(0.06)
                    .overlay(AppIcon(appName: window.appName, size: 32))
            }
            AppIcon(appName: window.appName, size: 22)
                .shadow(radius: 3)
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Theme.foreground.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1))
        .brightness(isHovered ? 0.05 : 0)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? window.windowId : (hovered == window.windowId ? nil : hovered) }
        .onTapGesture { peek.jump(to: window) }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
