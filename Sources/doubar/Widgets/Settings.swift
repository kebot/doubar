import AppKit
import SwiftUI

/// The settings popup. Layout: drag pills between Left, Right and Not in
/// bar, onto each other to share a pill, out of a shared pill to split it.
/// Bar: the strip's size and font. Everything is saved to config.toml as it
/// changes. Opened by the settings button, a pill's "Bar Settings…" or
/// `doubar emit settings`; closes on the button again or a click in
/// another app.
///
/// Drags are a DragGesture with hit-testing against the pills' frames, not
/// system drag-and-drop, which doesn't start reliably from an app that is
/// never active.
@MainActor
final class BarSettings {
    static let shared = BarSettings()

    private var panel: PopupPanel?
    private var monitor: Any?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(below anchor: NSRect?) {
        if isOpen { close() } else { open(below: anchor) }
    }

    /// Open below `anchor`, or below the right end of the main display's bar.
    func open(below anchor: NSRect? = nil) {
        let anchor = anchor ?? Self.defaultAnchor
        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        panel.setContent(SettingsView { [weak panel] size in panel?.fit(size) }, below: anchor, gap: 8, inset: 12)
        panel.orderFrontRegardless()
        // A global monitor only sees clicks that go to other apps, which is
        // what "clicked away" means here; mouse events need no permission.
        if monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static var defaultAnchor: NSRect {
        let f = (NSScreen.main ?? NSScreen.screens[0]).frame
        return NSRect(x: f.maxX, y: f.maxY - BarWindow.height + 4, width: 0, height: 0)
    }
}

private enum Tab { case layout, bar }

/// A row of pills in the Layout tab.
private enum Row: Hashable {
    case side(Config.Side)
    /// Not in bar.
    case pool
}

private struct PillRef: Hashable {
    let row: Row
    let index: Int
}

private struct PillFramesKey: PreferenceKey {
    static let defaultValue: [PillRef: CGRect] = [:]
    static func reduce(value: inout [PillRef: CGRect], nextValue: () -> [PillRef: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [Row: CGRect] = [:]
    static func reduce(value: inout [Row: CGRect], nextValue: () -> [Row: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct Drag {
    /// The entries being moved: a whole pill, or one entry of a shared pill.
    var entries: [String]
    var from: Row
    var location: CGPoint
    var drop: Config.Layout.Drop?
}

private struct SettingsView: View {
    /// Called with the view's size, so the panel can follow it.
    let onSize: (CGSize) -> Void

    @ObservedObject private var config = Config.shared
    @ObservedObject private var statusItems = StatusItems.shared
    @State private var tab = Tab.layout
    @State private var drag: Drag?
    @State private var pillFrames: [PillRef: CGRect] = [:]
    @State private var rowFrames: [Row: CGRect] = [:]
    @State private var hovered: String?

    private static let space = "settings"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                tabs
                Spacer(minLength: 8)
                Text(tab == .layout ? "Anything not in Left or Right is hidden" : "Saved to config.toml as you go")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            if let error = config.error {
                Text("\(error). Fix the file to save changes here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.97, green: 0.46, blue: 0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch tab {
            case .layout: layoutTab
            case .bar: BarTab()
            }
        }
        .padding(12)
        .frame(width: 420, alignment: .leading)
        .font(.system(size: 12))
        .foregroundStyle(Theme.foreground)
        // Native controls (pickers, sliders) follow the theme, not macOS.
        .environment(\.colorScheme, config.isDark ? .dark : .light)
        .background(
            RoundedRectangle(cornerRadius: Theme.popupRadius)
                .fill(Theme.background)
                .overlay(RoundedRectangle(cornerRadius: Theme.popupRadius).strokeBorder(Theme.border)))
        .overlay(alignment: .topLeading) { dragOverlay }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(PillFramesKey.self) { pillFrames = $0 }
        .onPreferenceChange(RowFramesKey.self) { rowFrames = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { onSize(g.size) }
                .onChange(of: g.size) { _, size in onSize(size) }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton("Layout", .layout)
            tabButton("Bar", .bar)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.foreground.opacity(0.08)))
    }

    private func tabButton(_ title: String, _ t: Tab) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(tab == t ? Theme.background : .clear))
            .shadow(color: .black.opacity(tab == t ? 0.25 : 0), radius: 1.5, y: 1)
            .opacity(tab == t ? 1 : 0.7)
            .contentShape(Rectangle())
            .onTapGesture { tab = t }
    }

    // MARK: Layout tab

    private var layoutTab: some View {
        let layout = config.effectiveLayout
        return VStack(alignment: .leading, spacing: 12) {
            section("Left") { row(.side(.left), layout.left) }
            section("Right") { row(.side(.right), layout.right) }
            section("Not in bar", note: "drag in to show") { row(.pool, pool(layout).map { [$0] }) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Drop onto a pill to share it · drag out of a pill to split · right-click for more")
                Text(hovered ?? " ")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    /// Running status items and widgets the layout doesn't show.
    private func pool(_ layout: Config.Layout) -> [String] {
        let placed = layout.entries
        let widgets = Entry.widgets.filter { ($0 != "workspaces" || AeroSpace.enabled) && !placed.contains($0) }
        let items = statusItems.items
            .filter { item in !placed.contains { Entry.matches($0, item: item.id) } }
            .map { Entry.status($0.id) }
        return widgets + items
    }

    private func section(_ title: String, note: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                Spacer()
                if let note { Text(note).font(.system(size: 10.5)) }
            }
            .foregroundStyle(Theme.dim)
            content()
        }
    }

    private func row(_ row: Row, _ pills: [[String]]) -> some View {
        let highlighted = rowHighlighted(row)
        return FlowLayout(spacing: 6) {
            ForEach(Array(pills.enumerated()), id: \.offset) { i, pill in
                pillView(pill, row: row)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: PillFramesKey.self, value: [PillRef(row: row, index: i): g.frame(in: .named(Self.space))])
                    })
            }
            if pills.isEmpty {
                Text(row == .pool ? "Every item is in the bar." : "Empty. Drag items here.")
                    .foregroundStyle(Theme.dim)
                    .frame(height: 26)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(highlighted ? Theme.accent.opacity(0.12) : row == .pool ? .clear : Theme.foreground.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    highlighted ? Theme.accent : row == .pool ? Theme.border : .clear,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .background(GeometryReader { g in
            Color.clear.preference(key: RowFramesKey.self, value: [row: g.frame(in: .named(Self.space))])
        })
    }

    /// A pill: dragged whole from its edge (or anywhere, when it holds one
    /// entry), or one entry at a time when it holds several.
    private func pillView(_ pill: [String], row: Row, ghost: Bool = false) -> some View {
        let shared = pill.count > 1
        let isTarget = !ghost && joinTarget.map(pill.contains) == true
        // A shared pill wraps its entries rather than outgrow the row.
        return FlowLayout(spacing: 2) {
            if shared {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 10, height: 24)
            }
            ForEach(pill, id: \.self) { entry in
                let chip = chipView(entry)
                    .opacity(!ghost && drag?.entries == [entry] && shared ? 0.3 : 1)
                if shared && !ghost {
                    chip.gesture(dragGesture([entry], from: row))
                        .contextMenu { chipMenu(entry, row: row) }
                } else {
                    chip
                }
            }
        }
        .padding(.horizontal, shared ? 3 : 1)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.foreground.opacity(ghost ? 0.2 : 0.09)))
        .background(RoundedRectangle(cornerRadius: 14).fill(ghost ? Theme.background : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isTarget ? Theme.accent : Theme.foreground.opacity(0.1), lineWidth: isTarget ? 2 : 1))
        .opacity(!ghost && drag?.entries == pill ? 0.3 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .gesture(dragGesture(pill, from: row), including: ghost ? .none : .all)
        .contextMenu { if !shared { chipMenu(pill[0], row: row) } }
    }

    private func chipView(_ entry: String) -> some View {
        let items = entry.hasPrefix("status:") ? statusItems.items(for: entry) : []
        let absent = entry.hasPrefix("status:") && items.isEmpty
        return HStack(spacing: 4) {
            switch entry {
            case "clock": widgetChip("clock", ClockFormat.string(.now, config.clock.format))
            case "spotify": widgetChip("music.note", "Spotify")
            case "settings": widgetChip("slider.horizontal.3", "Settings")
            case "workspaces": widgetChip("square.grid.2x2", "Workspaces")
            default:
                if absent {
                    Text(Self.clip(Self.shortName(entry)))
                } else {
                    ForEach(items) { item in
                        if let image = statusItems.images[item.id] {
                            ItemImage(item: item, image: image, height: 18)
                        } else {
                            // Items macOS has collapsed have no picture.
                            Text(Self.clip(item.label ?? item.appName))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .opacity(absent ? 0.45 : 1)
        .overlay {
            if absent {
                Capsule().strokeBorder(Theme.foreground.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .background(Capsule().fill(hovered == Self.describe(entry, absent) ? Theme.hover : .clear))
        .contentShape(Capsule())
        .onHover { inside in
            let text = Self.describe(entry, absent)
            hovered = inside ? text : (hovered == text ? nil : hovered)
        }
    }

    private func widgetChip(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title)
        }
    }

    private static func clip(_ s: String) -> String {
        s.count > 18 ? s.prefix(17) + "…" : s
    }

    /// "Telegram/#0" for "status:com.tdesktop.Telegram/#0".
    private static func shortName(_ entry: String) -> String {
        let id = entry.dropFirst("status:".count)
        guard let slash = id.firstIndex(of: "/") else { return String(id.split(separator: ".").last ?? id) }
        let app = id[..<slash].split(separator: ".").last ?? ""
        return "\(app)\(id[slash...])"
    }

    private static func describe(_ entry: String, _ absent: Bool) -> String {
        let text = entry.hasPrefix("status:") ? String(entry.dropFirst("status:".count)) : "\(entry) (built in)"
        return absent ? "\(text) · not running" : text
    }

    @ViewBuilder
    private func chipMenu(_ entry: String, row: Row) -> some View {
        switch row {
        case .pool:
            Button("Add to Right") { config.updateLayout { $0.move([entry], .end(.right)) } }
            Button("Add to Left") { config.updateLayout { $0.move([entry], .end(.left)) } }
        case .side(let side):
            if (config.effectiveLayout.pill(containing: entry)?.count ?? 0) > 1 {
                Button("Split Pill") { config.updateLayout { $0.split(pillWith: entry) } }
            }
            Button("Move to \(side.other.title)") { config.updateLayout { $0.move([entry], .end(side.other)) } }
            Button("Remove from Bar") { config.updateLayout { $0.remove([entry]) } }
        }
    }

    // MARK: Dragging

    private func dragGesture(_ entries: [String], from row: Row) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil { drag = Drag(entries: entries, from: row, location: value.location) }
                drag?.location = value.location
                drag?.drop = dropTarget(at: value.location)
            }
            .onEnded { _ in
                guard let d = drag else { return }
                drag = nil
                guard let drop = d.drop, !(d.from == .pool && drop == .out) else { return }
                config.updateLayout { $0.move(d.entries, drop) }
            }
    }

    /// Where a drop at `p` lands: on a pill's middle joins it, near its
    /// edges goes beside it, elsewhere in a row goes after the pill before
    /// the pointer, in the Not in bar row takes it out.
    private func dropTarget(at p: CGPoint) -> Config.Layout.Drop? {
        let layout = config.effectiveLayout
        for side in Config.Side.allCases {
            guard let rowFrame = rowFrames[.side(side)], rowFrame.insetBy(dx: -6, dy: -6).contains(p) else { continue }
            let pills = layout[side]
            let frames = pillFrames
                .filter { $0.key.row == .side(side) && $0.key.index < pills.count }
                .sorted { $0.key.index < $1.key.index }
            // Name a pill by an entry that isn't being moved, if it has one.
            let ref = { (i: Int) in pills[i].first { !(drag?.entries.contains($0) ?? false) } ?? pills[i][0] }
            for (key, f) in frames where f.contains(p) {
                let t = (p.x - f.minX) / max(f.width, 1)
                return t < 0.28 ? .before(side, ref: ref(key.index))
                    : t > 0.72 ? .after(side, ref: ref(key.index)) : .join(side, ref: ref(key.index))
            }
            let before = frames.last { p.y > $0.value.maxY || (p.y >= $0.value.minY - 4 && p.x > $0.value.maxX) }
            if let before { return .after(side, ref: ref(before.key.index)) }
            if let first = frames.first { return .before(side, ref: ref(first.key.index)) }
            return .end(side)
        }
        if let pool = rowFrames[.pool], pool.insetBy(dx: -6, dy: -6).contains(p) { return .out }
        return nil
    }

    /// The entry whose pill a drop would join.
    private var joinTarget: String? {
        if case .join(_, let ref)? = drag?.drop { ref } else { nil }
    }

    private func rowHighlighted(_ row: Row) -> Bool {
        switch (row, drag?.drop) {
        case (.side(let s), .end(let t)?): s == t
        case (.pool, .out?): drag?.from != .pool
        default: false
        }
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if let d = drag {
            ZStack(alignment: .topLeading) {
                if let (frame, before) = caret(d.drop) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.accent)
                        .frame(width: 3, height: frame.height)
                        .offset(x: before ? frame.minX - 4.5 : frame.maxX + 1.5, y: frame.minY)
                }
                pillView(d.entries, row: d.from, ghost: true)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                    .offset(x: d.location.x - 14, y: d.location.y - 14)
            }
            .allowsHitTesting(false)
        }
    }

    /// The frame of the pill a before/after drop goes next to.
    private func caret(_ drop: Config.Layout.Drop?) -> (CGRect, Bool)? {
        let side: Config.Side, ref: String, before: Bool
        switch drop {
        case .before(let s, let r)?: (side, ref, before) = (s, r, true)
        case .after(let s, let r)?: (side, ref, before) = (s, r, false)
        default: return nil
        }
        guard let i = config.effectiveLayout[side].firstIndex(where: { $0.contains(ref) }),
              let frame = pillFrames[PillRef(row: .side(side), index: i)]
        else { return nil }
        return (frame, before)
    }
}

// MARK: Bar tab

private struct BarTab: View {
    @ObservedObject private var config = Config.shared

    private static let families = ["system"] + NSFontManager.shared.availableFontFamilies

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Theme") {
                HStack {
                    label("Palette", config.themeName == nil ? "from dotter's theme.toml" : "built in")
                    ThemePicker(title: "")
                        .labelsHidden()
                }
            }
            group("Size") {
                slider("Height", "pill height", \.height, 14...36)
                slider("Top padding", "above the pills", \.paddingTop, 0...16)
                slider("Side padding", "from the screen edges", \.paddingX, 0...48)
                slider("Gap", "between pills", \.gap, 0...16)
                slider("Pill padding", "inside text pills", \.pillPadding, 4...24)
            }
            group("Font") {
                HStack {
                    label("Family", "any installed font")
                    Picker("", selection: binding(\.fontFamily)) {
                        ForEach(families, id: \.self) { Text($0 == "system" ? "System" : $0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                slider("Size", "label text", \.fontSize, 9...20)
            }
            group("Status items") {
                HStack {
                    label("Icon colour", "of status items")
                    Picker("", selection: Binding(
                        get: { config.iconTint },
                        set: { config.set("status-items", "tint", .string($0.rawValue)) }
                    )) {
                        ForEach(Config.IconTint.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            Text("Every display follows as you drag. Sizes are points.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
        }
    }

    private var families: [String] {
        Self.families.contains(config.bar.fontFamily) ? Self.families : Self.families + [config.bar.fontFamily]
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.dim)
            content()
        }
    }

    private func label(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
            Text(hint).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
        }
        .frame(width: 130, alignment: .leading)
    }

    private func slider(
        _ title: String, _ hint: String, _ key: WritableKeyPath<Config.Bar, CGFloat>, _ range: ClosedRange<CGFloat>
    ) -> some View {
        HStack {
            label(title, hint)
            // Whole points, rounded here: a stepped slider draws a tick per step.
            Slider(value: Binding(get: { config.bar[keyPath: key] }, set: { binding(key).wrappedValue = $0.rounded() }), in: range)
                .controlSize(.small)
                .tint(Theme.accent)
            Text("\(Int(config.bar[keyPath: key])) pt")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(height: 30)
    }

    private func binding<T>(_ key: WritableKeyPath<Config.Bar, T>) -> Binding<T> {
        Binding(
            get: { config.bar[keyPath: key] },
            set: { value in
                var b = config.bar
                b[keyPath: key] = value
                config.setBar(b)
            })
    }
}

/// Lays its children out left to right, wrapping onto new rows.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.flatMap { $0 }.map { $0.frame.maxX }.max() ?? 0
        let height = rows.last.flatMap { $0.map { $0.frame.maxY }.max() } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (i, frame) in row {
                subviews[i].place(
                    at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size))
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, frame: CGRect)]] {
        var rows: [[(index: Int, frame: CGRect)]] = [[]]
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            // Children that wrap (shared pills) get the row's width.
            var size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                rows.append([])
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rows[rows.count - 1].append((i, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return rows
    }
}
