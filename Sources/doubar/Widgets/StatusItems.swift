import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

// Every app's status item (Stats, Wi-Fi, battery, ...), mirrored into the
// bar. The system menu bar is auto-hidden behind doubar but MenuBarAgent
// keeps rendering it, so its window is captured with ScreenCaptureKit and
// cut into items along the frames Accessibility reports. Clicks are
// forwarded as AXPress, which opens the item's own menu. Which items the
// bar shows, and where, is the [layout] in config.toml.

@MainActor
final class StatusItems: ObservableObject {
    static let shared = StatusItems()

    struct Item: Identifiable {
        /// Stable across launches: the app's bundle id and the item's
        /// identifier, description, title or help text (Stats names its
        /// items only there), else its position within the app.
        let id: String
        let appName: String
        /// What the item calls itself, e.g. "Wi-Fi", if anything.
        let label: String?
        let pid: pid_t
        let element: AXUIElement
        /// Horizontal span in global coordinates. Only x is used: while the
        /// menu bar is hidden its items' vertical position is meaningless.
        let minX: CGFloat
        var width: CGFloat
        var obscured = false
    }

    /// Items left to right, with their latest picture.
    @Published private(set) var items: [Item] = []
    @Published private(set) var images: [String: CGImage] = [:]
    /// Each picture split into its white and grey pixels and its coloured
    /// ones, for `IconTint.palette` and `.mono`.
    @Published private(set) var layers: [String: Layers] = [:]

    struct Layers {
        let neutral: CGImage
        /// Nil when the picture has no colour of its own.
        let coloured: CGImage?
    }

    /// Items hidden in the old settings popup, before [layout] existed. The
    /// default layout leaves them out until a layout is saved.
    static let legacyHidden = Set(
        UserDefaults(suiteName: "com.yaofur.doubar")?.stringArray(forKey: "hiddenStatusItems") ?? [])

    /// The height of the slice cut from the middle of the menu bar.
    static let sliceHeight: CGFloat = 22

    private var menuBars: [SCWindow] = []
    private var tick = 0
    private var busy = false
    private var askedForPermission = false
    private var wasCollapsed = false
    private var primedCapture = false

    // The system chevron in its two states. These are its English labels;
    // it has no identifier.
    private static let systemCollapse = "com.apple.MenuBarAgent/Hide Menu Bar Items"
    private static let systemExpand = "com.apple.MenuBarAgent/Show Hidden Menu Bar Items"

    private init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    /// Click `item`. Apps place what they open under the item's real (hidden)
    /// place in the menu bar, so a window of its app that comes on screen
    /// shortly after (Stats' popovers, say) is moved below `anchor`, the
    /// item's place in doubar's bar, when there is one.
    func press(_ item: Item, below anchor: NSRect?) {
        Task {
            // A display focus change can leave an AX element that accepts
            // AXPress but no longer opens anything. Resolve its live copy.
            let current = await Self.scan().first { $0.id == item.id } ?? item
            pressCurrent(current, below: anchor)
        }
    }

    private func pressCurrent(_ item: Item, below anchor: NSRect?) {
        let element = item.element, id = item.id, pid = item.pid
        let bounds = anchor.flatMap { NSScreen.containing($0)?.frame }
        // Accessibility's coordinates are top-left, from the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        DispatchQueue.global(qos: .userInitiated).async {
            let before = Set(Self.onScreenWindows(of: pid).keys)
            // AXPress can block until the menu it opens closes.
            DispatchQueue.global(qos: .userInitiated).async {
                if id == "com.apple.campo/Search" { return Self.openSpotlight() }
                let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
                if err != .success { log("pressing \(id) failed (\(err.rawValue))") }
            }
            guard let anchor, let bounds else { return }
            for _ in 0..<20 {
                usleep(50_000)
                // Menus come on screen too, but aren't windows Accessibility
                // can move; they just open under the hidden item.
                guard let frame = Self.onScreenWindows(of: pid).first(where: { !before.contains($0.key) })?.value,
                      let popup = AXUIElementCreateApplication(pid).windows
                        .first(where: { $0.frame.map { Self.close($0, frame) } ?? false })
                else { continue }
                let x = min(max(anchor.midX - frame.width / 2, bounds.minX + 8), bounds.maxX - frame.width - 8)
                popup.setPosition(CGPoint(x: x, y: primaryHeight - (anchor.minY - 6)))
                return
            }
        }
    }

    /// `doubar emit status-item id=<id>`: click an item as if from the bar.
    func press(id: String?) {
        guard let item = items.first(where: { $0.id == id }) else {
            log("status-item: unknown id; ids: \(items.map(\.id))")
            return
        }
        press(item, below: nil)
    }

    /// Spotlight's item accepts AXPress but does nothing, as does its slot in
    /// MenuBarAgent, so it is opened with the Spotlight shortcut instead:
    /// the user's own (symbolic hotkey 64), else Command-Space.
    private nonisolated static func openSpotlight() {
        let hotkey = (UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")?["64"] as? [String: Any])
        let params = (hotkey?["value"] as? [String: Any])?["parameters"] as? [Int]
        var key: CGKeyCode = 49, flags: CGEventFlags = .maskCommand
        if hotkey?["enabled"] as? Bool == true, let params, params.count == 3 {
            // NSEvent modifier flags and CGEventFlags share their bits.
            key = CGKeyCode(params[1])
            flags = CGEventFlags(rawValue: UInt64(params[2]))
        }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// On-screen windows of `pid` by window number, with their frames
    /// (global, top-left).
    private nonisolated static func onScreenWindows(of pid: pid_t) -> [Int: CGRect] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var out: [Int: CGRect] = [:]
        for w in info {
            guard let n = w[kCGWindowNumber as String] as? Int,
                  w[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary)
            else { continue }
            out[n] = r
        }
        return out
    }

    private nonisolated static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// The items a layout entry shows, left to right.
    func items(for entry: String) -> [Item] {
        items.filter { Entry.matches(entry, item: $0.id) }
    }

    private func refresh() async {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            if !askedForPermission {
                askedForPermission = true
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
            return
        }
        busy = true
        defer { busy = false }

        // MenuBarAgent may expose live AX elements before it has drawn their
        // pictures. Give it one visible layout pass at startup, then let the
        // hidden bars settle before reading their frames and pixels.
        if !primedCapture, CGPreflightScreenCaptureAccess() {
            primedCapture = true
            await Self.primeCapture()
            try? await Task.sleep(for: .milliseconds(700))
        }

        var found = await Self.scan()
        // macOS's own "Hide Menu Bar Items" chevron collapses every item to
        // its left, and collapsed items aren't drawn at all: Accessibility
        // puts them on top of the chevron. doubar hides items itself, so the
        // chevron stays out of the bar. Expanding takes a real click on the
        // system menu bar (AXPress only collapses), so while collapsed the
        // items left of it go without a picture.
        let expand = found.first { $0.id == Self.systemExpand }
        let collapsedEdge = expand.map { $0.minX + $0.width } ?? -.infinity
        let previousWidths = Dictionary(items.map { ($0.id, $0.width) }, uniquingKeysWith: { first, _ in first })
        for index in found.indices {
            // Overflow parks items on top of the chevron rather than drawing
            // them. A focus change must not replace their pictures or widths
            // with these overlapping slots, but their live elements still press.
            if found[index].obscured || found[index].minX < collapsedEdge {
                found[index].obscured = true
                if let width = previousWidths[found[index].id] { found[index].width = width }
            }
        }
        if (expand != nil) != wasCollapsed {
            wasCollapsed = expand != nil
            if wasCollapsed { log("menu bar items collapsed by macOS; expand them with « in the system menu bar") }
        }
        found.removeAll { $0.id == Self.systemExpand || $0.id == Self.systemCollapse }
        items = found
        guard !found.isEmpty, CGPreflightScreenCaptureAccess() else { return }

        // Looking the window up is the costly part, and it only changes when
        // displays are reconfigured; capturing a stale one fails, which
        // triggers a fresh lookup. Since macOS 27.2 each display has a
        // second MenuBarAgent window over the real one that stays fully
        // transparent while the menu bar is auto-hidden; blank captures are
        // skipped so the items are cut from the window that has them.
        tick += 1
        if menuBars.isEmpty || tick % 10 == 0 { menuBars = await Self.findMenuBars() }
        var captures: [(SCWindow, CGImage)] = []
        for bar in menuBars {
            guard let image = await Self.capture(bar) else { menuBars = []; continue }
            if !Self.isBlank(image) { captures.append((bar, image)) }
        }

        var fresh: [String: CGImage] = [:]
        for item in found {
            if item.obscured {
                fresh[item.id] = images[item.id]
                continue
            }
            guard let (bar, image) = captures.first(where: {
                $0.0.frame.minX <= item.minX && item.minX + item.width <= $0.0.frame.maxX
            }) else { continue }
            let scale = CGFloat(image.width) / bar.frame.width
            let slice = CGRect(
                x: (item.minX - bar.frame.minX) * scale,
                y: (bar.frame.height - Self.sliceHeight) / 2 * scale,
                width: item.width * scale, height: Self.sliceHeight * scale)
            if let cropped = Self.crop(image, to: slice.integral), !Self.isBlank(cropped) {
                fresh[item.id] = cropped
            } else {
                fresh[item.id] = images[item.id]
            }
        }
        images = fresh
        switch Config.shared.iconTint {
        case .original: if !layers.isEmpty { layers = [:] }
        case .mono: layers = fresh.compactMapValues { Self.layers($0, hues: nil) }
        case .palette:
            let hues = Config.shared.hues
            layers = fresh.compactMapValues { Self.layers($0, hues: hues) }
        }
    }

    /// Split a picture into its white and grey pixels and its saturated
    /// ones (Stats' graphs and dots, a red low battery), whose colour
    /// carries meaning. With `hues`, each saturated pixel takes the theme's
    /// colour for its hue instead, at its own opacity, so a chart's line
    /// stays apart from its box.
    private static func layers(_ image: CGImage, hues: Config.Hues?) -> Layers? {
        let w = image.width, h = image.height
        let space = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.premultipliedLast.rawValue
        func context() -> CGContext? {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info)
        }
        guard w > 0, h > 0, let source = context(), let neutral = context(), let coloured = context(),
              let src = source.data?.bindMemory(to: UInt8.self, capacity: w * h * 4),
              let n = neutral.data?.bindMemory(to: UInt8.self, capacity: w * h * 4),
              let c = coloured.data?.bindMemory(to: UInt8.self, capacity: w * h * 4)
        else { return nil }
        source.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var anyColour = false
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            // Premultiplied, so the channel spread is relative to alpha.
            let r = Int(src[i]), g = Int(src[i + 1]), b = Int(src[i + 2]), a = Int(src[i + 3])
            let saturated = max(r, g, b) - min(r, g, b) > a / 4
            anyColour = anyColour || saturated
            let target = saturated ? c : n
            if saturated, let hues, let colour = hues.colour(r: r, g: g, b: b) {
                // Premultiplied by the pixel's own alpha.
                let alpha = Double(a) / 255
                target[i] = UInt8(colour.r * alpha * 255)
                target[i + 1] = UInt8(colour.g * alpha * 255)
                target[i + 2] = UInt8(colour.b * alpha * 255)
                target[i + 3] = UInt8(a)
            } else {
                for k in 0..<4 { target[i + k] = src[i + k] }
            }
        }
        guard let neutralImage = neutral.makeImage() else { return nil }
        return Layers(neutral: neutralImage, coloured: anyColour ? coloured.makeImage() : nil)
    }

    private static func primeCapture() async {
        let key = "_HIHideMenuBar" as CFString
        guard CFPreferencesCopyValue(key, kCFPreferencesAnyApplication,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool == true
        else { return }
        func setHidden(_ hidden: Bool) {
            CFPreferencesSetValue(key, hidden as CFBoolean, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("AppleInterfaceMenuBarHidingChangedNotification"),
                object: nil, userInfo: nil, deliverImmediately: true)
        }
        setHidden(false)
        // This scope restores auto-hide even when the task is cancelled.
        defer { setHidden(true) }
        try? await Task.sleep(for: .seconds(1))
    }

    /// Every app's status items, including the live elements MenuBarAgent
    /// hosts while auto-hide removes them from the app's AXExtrasMenuBar.
    private nonisolated static func scan() async -> [Item] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != getpid() }
            .map { app in
                let name = app.localizedName ?? "\(app.processIdentifier)"
                return (app.processIdentifier, app.bundleIdentifier ?? name, name)
            }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                var items: [Item] = []
                var hosted: [pid_t: [AXUIElement]] = [:]
                if let agent = apps.first(where: { $0.1 == "com.apple.MenuBarAgent" }) {
                    let root = AXUIElementCreateApplication(agent.0)
                    AXUIElementSetMessagingTimeout(root, 0.2)
                    for window in root.windows {
                        for group in window.children {
                            for child in group.children {
                                var owner: pid_t = 0
                                guard AXUIElementGetPid(child, &owner) == .success,
                                      owner != agent.0, let frame = child.frame,
                                      frame.width > 0, frame.height > 0, frame.height < 60
                                else { continue }
                                let existing = hosted[owner, default: []]
                                if !existing.contains(where: { CFEqual($0, child) }) {
                                    hosted[owner, default: []].append(child)
                                }
                            }
                        }
                    }
                }
                for (pid, appId, appName) in apps {
                    let app = AXUIElementCreateApplication(pid)
                    // A hung app shouldn't stall the whole scan.
                    AXUIElementSetMessagingTimeout(app, 0.2)
                    let bar: AXUIElement? = app.attribute("AXExtrasMenuBar")
                    let own = bar?.children ?? []
                    let children = own.isEmpty
                        ? (hosted[pid] ?? []).sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }
                        : own
                    // Hosted children arrive in an unstable order; unnamed
                    // items are numbered left to right when the own bar is absent.
                    var seen: [String: Int] = [:]
                    for child in children {
                        guard let frame = child.frame, frame.width > 0 else { continue }
                        // MenuBarAgent's own items (Wi-Fi, Control Center,
                        // ...) are slots with no actions; the menu extra
                        // inside carries the identifier
                        // ("com.apple.menuextra.wifi") and the press.
                        let inner = child.actionNames.contains(kAXPressAction) ? [] : child.descendants(depth: 3)
                        let target = inner.first { $0.actionNames.contains(kAXPressAction) } ?? child
                        let label = child.text(kAXDescriptionAttribute) ?? child.text(kAXTitleAttribute)
                            ?? inner.lazy.compactMap { $0.text(kAXDescriptionAttribute) }.first
                            ?? child.text(kAXHelpAttribute)
                        // Some apps (magpie) put live figures on the lines
                        // below the name in their tooltip, so only the first
                        // line is stable enough to name the item.
                        let name = Entry.firstLine(
                            child.text(kAXIdentifierAttribute)
                                ?? inner.lazy.compactMap { $0.text(kAXIdentifierAttribute) }.first ?? label ?? "")
                        let n = seen[name, default: 0]
                        seen[name] = n + 1
                        items.append(Item(
                            id: "\(appId)/\(name)" + (n > 0 || name.isEmpty ? "#\(n)" : ""), appName: appName,
                            label: label, pid: pid, element: target, minX: frame.minX, width: frame.width))
                    }
                }
                // Separate items never overlap in a drawn menu bar. macOS
                // instead piles overflow items into the chevron's slot, even
                // while the auto-hidden bar omits the chevron from its AX tree.
                let spans = items.map { ($0.minX, $0.minX + $0.width) }
                for i in items.indices {
                    items[i].obscured = spans.indices.contains { j in
                        i != j && min(spans[i].1, spans[j].1) - max(spans[i].0, spans[j].0) > 2
                    }
                }
                cont.resume(returning: items.sorted { $0.minX < $1.minX })
            }
        }
    }

    /// MenuBarAgent's menu bar window on each display.
    private static func findMenuBars() async -> [SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        else { return [] }
        return content.windows.filter {
            $0.owningApplication?.applicationName == "MenuBarAgent" && $0.frame.height < 60 && $0.frame.width > 0
        }
    }

    /// Give each cropped icon its own pixel buffer before handing it to SwiftUI.
    private static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        guard let slice = image.cropping(to: rect),
              let context = CGContext(data: nil, width: slice.width, height: slice.height,
                                      bitsPerComponent: 8, bytesPerRow: slice.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(slice, in: CGRect(x: 0, y: 0, width: slice.width, height: slice.height))
        return context.makeImage()
    }

    /// Whether a capture has no visible pixel at all.
    private static func isBlank(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.bindMemory(to: UInt8.self, capacity: w * h * 4)
        else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<(w * h) where data[i * 4 + 3] > 12 { return false }
        return true
    }

    private static func capture(_ window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let cfg = SCStreamConfiguration()
        cfg.width = Int(window.frame.width * scale)
        cfg.height = Int(window.frame.height * scale)
        cfg.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: cfg)
    }
}

private extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// A string attribute, or nil when it is missing or empty.
    func text(_ name: String) -> String? {
        guard let s: String = attribute(name), !s.isEmpty else { return nil }
        return s
    }

    var windows: [AXUIElement] { attribute(kAXWindowsAttribute) ?? [] }

    var children: [AXUIElement] { attribute(kAXChildrenAttribute) ?? [] }

    /// Children, their children and so on, `depth` levels down, breadth first.
    func descendants(depth: Int) -> [AXUIElement] {
        var out: [AXUIElement] = [], level = [self]
        for _ in 0..<depth {
            level = level.flatMap(\.children)
            out += level
        }
        return out
    }

    var actionNames: [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(self, &names)
        return names as? [String] ?? []
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
    }

    var frame: CGRect? {
        guard let pos: AXValue = attribute(kAXPositionAttribute), let size: AXValue = attribute(kAXSizeAttribute)
        else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos, .cgPoint, &p)
        AXValueGetValue(size, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
}

/// A status item's captured picture, `height` tall.
struct ItemImage: View {
    let item: StatusItems.Item
    let image: CGImage
    var height: CGFloat = Theme.pillHeight

    var body: some View {
        let size = CGSize(width: item.width * height / StatusItems.sliceHeight, height: height)
        // The picture's background is transparent, so each layer, as a
        // template image, keeps its shape and takes one colour.
        let tint = Config.shared.iconTint, colors = Config.shared.colors
        if tint != .original, let layers = StatusItems.shared.layers[item.id] {
            ZStack {
                tinted(layers.neutral, tint == .mono ? colors.accent : colors.icon)
                if let coloured = layers.coloured {
                    if tint == .mono {
                        tinted(coloured, colors.accent).opacity(0.5)
                    } else {
                        // Already moved onto the palette.
                        Image(decorative: coloured, scale: 1).resizable()
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
        }
    }

    private func tinted(_ image: CGImage, _ colour: Color) -> some View {
        Image(decorative: image, scale: 1)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(colour)
    }
}

/// One status item in the bar: click opens its menu, right-click offers
/// `menu`.
struct StatusItemView<Menu: View>: View {
    let item: StatusItems.Item
    let image: CGImage
    @ViewBuilder var menu: Menu

    @EnvironmentObject private var screen: Screen
    @State private var hovered = false
    @State private var frame: CGRect = .zero

    var body: some View {
        content.hidden()
            .onWindowFrameChange { frame = $0 }
            .background(StatusItemClickTarget(
                frame: screen.toScreen(frame), content: AnyView(content)))
    }

    private var content: some View {
        ItemImage(item: item, image: image)
            .padding(.horizontal, 4)
            .background(Capsule().fill(hovered ? Theme.hover : .clear))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { StatusItems.shared.press(item, below: screen.toScreen(frame)) }
            .contextMenu { menu }
    }
}

/// The auto-hidden system menu bar can reveal over the bottom-level bar
/// before mouse-down. Keep each mirrored item visible and clickable above it.
private struct StatusItemClickTarget: NSViewRepresentable {
    let frame: NSRect
    let content: AnyView

    func makeNSView(context: Context) -> TargetView { TargetView() }

    func updateNSView(_ view: TargetView, context: Context) {
        view.place(frame, content: content)
    }

    static func dismantleNSView(_ view: TargetView, coordinator: ()) {
        view.panel.orderOut(nil)
    }

    final class TargetHostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    final class TargetView: NSView {
        let panel: NSPanel
        private let host = TargetHostingView(rootView: AnyView(EmptyView()))

        override init(frame: NSRect) {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            super.init(frame: frame)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.canHide = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            host.sizingOptions = []
            panel.contentView = host
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func place(_ frame: NSRect, content: AnyView) {
            guard frame.width > 0, frame.height > 0 else { panel.orderOut(nil); return }
            host.rootView = content
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }
}
