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
        guard !windows.isEmpty else { return }
        let bounds = windowBounds(onScreenOnly: true)
        for w in windows {
            guard let r = bounds[w.windowId], let d = displayBounds(w.monitorId) else { continue }
            frames[w.windowId] = CGRect(
                x: (r.minX - d.minX) / d.width, y: (r.minY - d.minY) / d.height,
                width: r.width / d.width, height: r.height / d.height)
        }
    }

    /// Forget windows that no longer exist.
    static func prune(keeping ids: Set<Int>) {
        frames = frames.filter { ids.contains($0.key) }
    }

    /// A unit-space rect (top-left origin) per window, for a workspace on
    /// `monitorId`: their remembered places when all are known, otherwise a
    /// best guess.
    static func layout(_ windows: [AeroSpace.Window], monitorId: Int) -> [CGRect] {
        let known = windows.compactMap { frames[$0.windowId]?.intersection(unit) }
        if known.count == windows.count, known.allSatisfy({ !$0.isEmpty }) { return known }

        // Not all seen on screen yet. A parked window keeps its real size,
        // so lay the windows out at that size: side by side, as AeroSpace's
        // default horizontal tiling does, else stacked, else a grid.
        if let d = displayBounds(monitorId) {
            let bounds = windowBounds(onScreenOnly: false)
            let sizes = windows.compactMap { w in
                bounds[w.windowId].map { CGSize(width: min($0.width / d.width, 1), height: min($0.height / d.height, 1)) }
            }
            if sizes.count == windows.count, let packed = pack(sizes, horizontal: true) ?? pack(sizes, horizontal: false) {
                return packed
            }
        }
        return grid(windows.count)
    }

    /// Sizes laid end to end along one axis and centred, or nil if they
    /// don't fit.
    private static func pack(_ sizes: [CGSize], horizontal: Bool) -> [CGRect]? {
        let total = sizes.reduce(0) { $0 + (horizontal ? $1.width : $1.height) }
        guard total <= 1.02 else { return nil }
        var offset = max(0, (1 - total) / 2)
        return sizes.map { s in
            defer { offset += horizontal ? s.width : s.height }
            return horizontal
                ? CGRect(x: offset, y: (1 - s.height) / 2, width: s.width, height: s.height)
                : CGRect(x: (1 - s.width) / 2, y: offset, width: s.width, height: s.height)
        }
    }

    private static func grid(_ count: Int) -> [CGRect] {
        let cols = max(1, Int(Double(count).squareRoot().rounded(.up)))
        let rows = max(1, (count + cols - 1) / cols)
        let w = 1 / CGFloat(cols), h = 1 / CGFloat(rows)
        return (0..<count).map { i in
            CGRect(x: CGFloat(i % cols) * w, y: CGFloat(i / cols) * h, width: w, height: h)
        }
    }

    private static func displayBounds(_ monitorId: Int) -> CGRect? {
        NSScreen.forAeroSpaceMonitor(monitorId)?.displayID.map(CGDisplayBounds)
    }

    /// Window bounds by window id, in global top-left coordinates.
    private static func windowBounds(onScreenOnly: Bool) -> [Int: CGRect] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var bounds: [Int: CGRect] = [:]
        for w in info {
            guard let n = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary)
            else { continue }
            bounds[n] = r
        }
        return bounds
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

    /// Longest side of the miniature screen, at most; it shrinks to fit.
    private static let miniature: CGFloat = 480
    /// The panel around the miniature: padding, title and footer.
    private static let chrome = CGSize(width: 40, height: 110)

    func pillHover(_ name: String, monitorId: Int, anchor: NSRect, hovering: Bool) {
        // Pills under a dragged icon are drop targets, not peeks.
        guard WindowDrag.shared.window == nil else { return }
        guard hovering else {
            showWork?.cancel()
            scheduleHide()
            return
        }
        hideWork?.cancel()
        // Nothing to preview for a workspace that is already on screen.
        let aerospace = AeroSpace.shared
        guard name != aerospace.focusedWorkspace, !aerospace.visibleWorkspaces.contains(name) else {
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
        guard let name, let (anchor, monitorId) = NSScreen.barAnchor(for: name) else {
            hide()
            return
        }
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

    /// Forget captures of windows that no longer exist.
    func prune(keeping ids: Set<Int>) {
        if images.keys.contains(where: { !ids.contains($0) }) {
            images = images.filter { ids.contains($0.key) }
        }
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

        let panel = self.panel ?? PeekPanel()
        self.panel = panel
        panel.show(
            PeekView(
                name: name, windows: windows,
                rects: WindowLayout.layout(windows, monitorId: monitorId),
                size: Self.miniatureSize(for: screen, below: anchor)),
            below: anchor)
        workspace = name

        // Refresh the miniature while it is open, so it is a live view.
        captureTimer?.invalidate()
        let ids = windows.map(\.windowId)
        capture(ids)
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture(ids) }
        }
    }

    /// The display's shape at up to `miniature` on its longest side, shrunk
    /// so the whole panel fits between the anchor and the bottom of the
    /// screen, and across it.
    private static func miniatureSize(for screen: NSScreen, below anchor: NSRect) -> CGSize {
        let f = screen.frame
        let aspect = f.width / f.height
        var size = aspect >= 1
            ? CGSize(width: miniature, height: miniature / aspect)
            : CGSize(width: miniature * aspect, height: miniature)
        let room = CGSize(
            width: f.width - 16 - chrome.width,
            height: anchor.minY - 8 - (f.minY + 8) - chrome.height)
        let scale = min(1, room.width / size.width, room.height / size.height)
        if scale < 1 { size = CGSize(width: size.width * scale, height: size.height * scale) }
        return size
    }

    private func capture(_ ids: [Int]) {
        Task {
            let fresh = await Thumbnails.capture(ids, maxPixels: Self.miniature * 2)
            guard workspace != nil else { return }
            images.merge(fresh) { $1 }
        }
    }
}

private final class PeekPanel: PopupPanel {
    func show(_ view: PeekView, below anchor: NSRect) {
        setContent(view, below: anchor, gap: 8, inset: 20)
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        }
    }
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
                    .foregroundStyle(Theme.dim)
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
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))

            Text("Click a window to jump to it")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.foreground.opacity(0.5))
        }
        .padding(20)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: Theme.previewRadius)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: Theme.previewRadius).strokeBorder(Theme.border)))
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
