import AppKit
import ApplicationServices
import ScreenCaptureKit
import SwiftUI

// Every app's status item (Stats, Wi-Fi, battery, ...), mirrored into the
// bar. The system menu bar is auto-hidden behind doubar but MenuBarAgent
// keeps rendering it, so its window is captured with ScreenCaptureKit and
// cut into items along the frames Accessibility reports. Clicks are
// forwarded as AXPress, which opens the item's own menu. Right-click hides
// an item; the settings button lists every item to pick which are shown.

@MainActor
final class StatusItems: ObservableObject {
    static let shared = StatusItems()

    struct Item: Identifiable {
        /// Stable across launches: the app's bundle id and the item's
        /// identifier, description or position within the app.
        let id: String
        let appName: String
        /// What the item calls itself, e.g. "Wi-Fi", if anything.
        let label: String?
        let pid: pid_t
        let element: AXUIElement
        /// Horizontal span in global coordinates. Only x is used: while the
        /// menu bar is hidden its items' vertical position is meaningless.
        let minX: CGFloat
        let width: CGFloat
    }

    /// Items left to right, with their latest picture.
    @Published private(set) var items: [Item] = []
    @Published private(set) var images: [String: CGImage] = [:]
    /// Ids of the items kept out of the bar, saved across launches.
    @Published private(set) var hidden: Set<String>

    // The suite WorkspaceNames uses, so the bare binary and the .app agree.
    private let defaults = UserDefaults(suiteName: "com.yaofur.doubar") ?? .standard
    private let hiddenKey = "hiddenStatusItems"

    /// The height of the slice cut from the middle of the menu bar.
    static let sliceHeight: CGFloat = 22

    private var menuBars: [SCWindow] = []
    private var tick = 0
    private var busy = false
    private var askedForPermission = false
    private var wasCollapsed = false

    // The system chevron in its two states. These are its English labels;
    // it has no identifier.
    private static let systemCollapse = "com.apple.MenuBarAgent/Hide Menu Bar Items"
    private static let systemExpand = "com.apple.MenuBarAgent/Show Hidden Menu Bar Items"

    private init() {
        hidden = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
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

    func setHidden(_ isHidden: Bool, _ item: Item) {
        if isHidden { hidden.insert(item.id) } else { hidden.remove(item.id) }
        defaults.set(hidden.sorted(), forKey: hiddenKey)
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

        var found = await Self.scan()
        // macOS's own "Hide Menu Bar Items" chevron collapses every item to
        // its left, and collapsed items aren't drawn at all: Accessibility
        // puts them on top of the chevron. doubar hides items itself, so the
        // chevron stays out of the bar. Expanding takes a real click on the
        // system menu bar (AXPress only collapses), so while collapsed the
        // items left of it go without a picture.
        let expand = found.first { $0.id == Self.systemExpand }
        let collapsedEdge = expand.map { $0.minX + $0.width } ?? -.infinity
        if (expand != nil) != wasCollapsed {
            wasCollapsed = expand != nil
            if wasCollapsed { log("menu bar items collapsed by macOS; expand them with « in the system menu bar") }
        }
        found.removeAll { $0.id == Self.systemExpand || $0.id == Self.systemCollapse }
        items = found
        guard !found.isEmpty, CGPreflightScreenCaptureAccess() else { return }

        // Looking the window up is the costly part, and it only changes when
        // displays are reconfigured; capturing a stale one fails, which
        // triggers a fresh lookup.
        tick += 1
        if menuBars.isEmpty || tick % 10 == 0 { menuBars = await Self.findMenuBars() }
        var captures: [(SCWindow, CGImage)] = []
        for bar in menuBars {
            if let image = await Self.capture(bar) { captures.append((bar, image)) } else { menuBars = [] }
        }

        var fresh: [String: CGImage] = [:]
        for item in found where item.minX >= collapsedEdge {
            guard let (bar, image) = captures.first(where: {
                $0.0.frame.minX <= item.minX && item.minX + item.width <= $0.0.frame.maxX
            }) else { continue }
            let scale = CGFloat(image.width) / bar.frame.width
            let slice = CGRect(
                x: (item.minX - bar.frame.minX) * scale,
                y: (bar.frame.height - Self.sliceHeight) / 2 * scale,
                width: item.width * scale, height: Self.sliceHeight * scale)
            fresh[item.id] = image.cropping(to: slice.integral)
        }
        images = fresh
    }

    /// Every app's status items via its AXExtrasMenuBar, sorted left to right.
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
                for (pid, appId, appName) in apps {
                    let app = AXUIElementCreateApplication(pid)
                    // A hung app shouldn't stall the whole scan.
                    AXUIElementSetMessagingTimeout(app, 0.2)
                    guard let bar: AXUIElement = app.attribute("AXExtrasMenuBar"),
                          let children: [AXUIElement] = bar.attribute(kAXChildrenAttribute)
                    else { continue }
                    // Apps like Stats give every item the same (empty) name,
                    // so repeats within an app are numbered in AX order.
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
                        let name = child.text(kAXIdentifierAttribute)
                            ?? inner.lazy.compactMap { $0.text(kAXIdentifierAttribute) }.first ?? label ?? ""
                        let n = seen[name, default: 0]
                        seen[name] = n + 1
                        items.append(Item(
                            id: "\(appId)/\(name)" + (n > 0 || name.isEmpty ? "#\(n)" : ""), appName: appName,
                            label: label, pid: pid, element: target, minX: frame.minX, width: frame.width))
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

    private static func capture(_ window: SCWindow) async -> CGImage? {
        let scale = NSScreen.screens.first { $0.frame.minX == window.frame.minX }?.backingScaleFactor ?? 2
        let cfg = SCStreamConfiguration()
        cfg.width = Int(window.frame.width * scale)
        cfg.height = Int(window.frame.height * scale)
        cfg.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: cfg)
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

/// A status item's captured picture, at bar size.
private struct ItemImage: View {
    let item: StatusItems.Item
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: item.width * Theme.pillHeight / StatusItems.sliceHeight, height: Theme.pillHeight)
    }
}

struct StatusItemsView: View {
    @ObservedObject private var model = StatusItems.shared
    @EnvironmentObject private var screen: Screen
    @State private var hovered: String?
    @State private var settingsFrame: CGRect = .zero
    @State private var itemFrames: [String: CGRect] = [:]

    var body: some View {
        let captured = model.items.filter { model.images[$0.id] != nil }
        if !captured.isEmpty {
            Pill(padding: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: Theme.pillHeight)
                    .opacity(hovered == "settings" ? 1 : 0.6)
                    .contentShape(Rectangle())
                    .onWindowFrameChange { settingsFrame = $0 }
                    .onHover { hovered = $0 ? "settings" : (hovered == "settings" ? nil : hovered) }
                    .onTapGesture { StatusItemsSettings.shared.toggle(below: screen.toScreen(settingsFrame)) }
                ForEach(captured.filter { !model.hidden.contains($0.id) }) { item in
                    ItemImage(item: item, image: model.images[item.id]!)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Theme.foreground.opacity(hovered == item.id ? 0.12 : 0)))
                        .contentShape(Rectangle())
                        .onWindowFrameChange { itemFrames[item.id] = $0 }
                        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
                        .onTapGesture { model.press(item, below: screen.toScreen(itemFrames[item.id] ?? .zero)) }
                        .contextMenu {
                            Button("Hide") { model.setHidden(true, item) }
                        }
                }
            }
        }
    }
}

/// The list of every status item, to pick which the bar shows. It closes on
/// the settings button or a click in another app.
@MainActor
final class StatusItemsSettings {
    static let shared = StatusItemsSettings()

    private var panel: PopupPanel?
    private var monitor: Any?

    func toggle(below anchor: NSRect) {
        if panel?.isVisible == true {
            close()
            return
        }
        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        panel.setContent(StatusItemsSettingsView(), below: anchor, gap: 8, inset: 12)
        panel.orderFrontRegardless()
        // A global monitor only sees clicks that go to other apps, which is
        // what "clicked away" means here; mouse events need no permission.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct StatusItemsSettingsView: View {
    @ObservedObject private var model = StatusItems.shared
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("STATUS ITEMS")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.foreground.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            ForEach(model.items) { item in
                row(item)
            }
        }
        .padding(12)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground.opacity(0.15))))
        .foregroundStyle(Theme.foreground)
        .font(Theme.font)
    }

    private func row(_ item: StatusItems.Item) -> some View {
        let shown = !model.hidden.contains(item.id)
        return HStack(spacing: 10) {
            Image(systemName: shown ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .frame(width: 16)
            Group {
                if let image = model.images[item.id] {
                    ItemImage(item: item, image: image)
                } else {
                    Color.clear.frame(width: 20, height: Theme.pillHeight)
                }
            }
            .frame(minWidth: 40, alignment: .center)
            .opacity(shown ? 1 : 0.4)
            Text([item.appName, item.label].compactMap { $0 }.joined(separator: " · "))
                .opacity(shown ? 1 : 0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.foreground.opacity(hovered == item.id ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
        .onTapGesture { model.setHidden(shown, item) }
    }
}
