import SwiftUI

/// The bar's look, from config.toml and theme.toml. The view at the root of
/// each window observes `Config`, so a change to either file redraws
/// everything that reads these.
@MainActor
enum Theme {
    static var background: Color { Config.shared.colors.pill }
    static var foreground: Color { Config.shared.colors.text }
    /// Text and glyphs in the bar: with status items in Accent Only, the
    /// built-in widgets follow them, so the whole bar is one colour.
    static var barText: Color {
        Config.shared.iconTint == .mono ? Config.shared.colors.accent : Config.shared.colors.text
    }
    static var hover: Color { Config.shared.colors.hover }
    static var border: Color { Config.shared.colors.border }
    static var dim: Color { Config.shared.colors.dim }
    static var accent: Color { Config.shared.colors.accent }
    static var pillHeight: CGFloat { Config.shared.bar.height }
    static var font: Font { Config.shared.font }
    static var popupRadius: CGFloat { Config.shared.popupRadius }
    static var previewRadius: CGFloat { Config.shared.previewRadius }
}

struct BarView: View {
    @ObservedObject private var config = Config.shared
    // Observed so pills come and go with what they show.
    @ObservedObject private var statusItems = StatusItems.shared
    @ObservedObject private var spotify = Spotify.shared

    var body: some View {
        let layout = config.effectiveLayout
        HStack(spacing: config.bar.gap) {
            side(layout.left)
            Spacer(minLength: 0)
            side(layout.right)
        }
        .padding(.horizontal, config.bar.paddingX)
        .padding(.top, config.bar.paddingTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(config.font)
        .foregroundStyle(Theme.barText)
    }

    private func side(_ pills: [[String]]) -> some View {
        HStack(spacing: config.bar.gap) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                // Workspaces draw a pill each, so they never share one.
                if pill.contains("workspaces"), AeroSpace.enabled {
                    AeroSpaceView()
                }
                let parts = pill.filter { $0 != "workspaces" }.flatMap(parts)
                if !parts.isEmpty {
                    BarPill(parts: parts)
                }
            }
        }
    }

    /// What `entry` draws right now: nothing for an app that isn't running
    /// or a Spotify that isn't playing, so its pill closes up.
    private func parts(_ entry: String) -> [BarPart] {
        switch entry {
        case "clock", "settings":
            return [.widget(entry)]
        case "spotify":
            return spotify.track == nil ? [] : [.widget(entry)]
        default:
            return statusItems.items(for: entry).compactMap { item in
                statusItems.images[item.id].map { .status(item, $0) }
            }
        }
    }
}

/// One thing drawn in a pill.
enum BarPart: Identifiable {
    case status(StatusItems.Item, CGImage)
    case widget(String)

    var id: String {
        switch self {
        case .status(let item, _): Entry.status(item.id)
        case .widget(let name): name
        }
    }

    var widget: String? {
        if case .widget(let name) = self { name } else { nil }
    }
}

private struct BarPill: View {
    let parts: [BarPart]

    @ObservedObject private var config = Config.shared

    var body: some View {
        // A widget alone in its pill colours the whole pill; in a shared
        // pill it colours just its own part.
        let solo = parts.count == 1 ? parts[0].widget : nil
        Pill(padding: padding(solo), colors: solo.flatMap { config.colors(for: config.style(of: $0)) }) {
            ForEach(parts) { BarPartView(part: $0, shared: solo == nil) }
        }
    }

    private func padding(_ widget: String?) -> CGFloat {
        switch widget {
        case "clock": config.bar.pillPadding
        case "spotify": 0
        default: 4
        }
    }
}

private struct BarPartView: View {
    let part: BarPart
    /// In a pill with other parts.
    let shared: Bool

    @ObservedObject private var config = Config.shared
    @EnvironmentObject private var screen: Screen

    var body: some View {
        switch part {
        case .status(let item, let image):
            StatusItemView(item: item, image: image) {
                EntryMenu(key: part.id, bar: screen.windowFrame)
            }
        case .widget("settings"):
            SettingsButton()
        case .widget(let name):
            let colors = shared ? config.colors(for: config.style(of: name)) : nil
            widget(name)
                .foregroundStyle(colors?.text ?? Theme.barText)
                .background { if let colors { Capsule().fill(colors.pill) } }
                .contentShape(Rectangle())
                .contextMenu { EntryMenu(key: name, bar: screen.windowFrame) }
        }
    }

    @ViewBuilder
    private func widget(_ name: String) -> some View {
        switch name {
        case "clock": ClockView().padding(.horizontal, shared ? 6 : 0)
        case "spotify": SpotifyView()
        default: EmptyView()
        }
    }
}

/// Opens the settings popup.
private struct SettingsButton: View {
    @EnvironmentObject private var screen: Screen
    @State private var hovered = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 18, height: Theme.pillHeight)
            .opacity(hovered ? 1 : 0.6)
            .contentShape(Rectangle())
            .onWindowFrameChange { frame = $0 }
            .onHover { hovered = $0 }
            .onTapGesture {
                // Opened from inside the bar's mouse-up, the popup ignores
                // every click after; the next run-loop turn is clear of it.
                let anchor = screen.toScreen(frame)
                DispatchQueue.main.async { BarSettings.shared.toggle(below: anchor) }
            }
            .contextMenu { EntryMenu(key: "settings", bar: screen.windowFrame) }
    }
}

/// The capsule every bar item sits in.
struct Pill<Content: View>: View {
    /// Horizontal padding; nil for the configured `pill-padding`.
    var padding: CGFloat?
    /// Tints the capsule, e.g. while hovered.
    var highlighted = false
    /// A widget's own pill and text colours.
    var colors: (pill: Color, text: Color)?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, padding ?? Config.shared.bar.pillPadding)
            .frame(height: Theme.pillHeight)
            .foregroundStyle(colors?.text ?? Theme.barText)
            .background {
                Capsule()
                    .fill(colors?.pill ?? Theme.background)
                    .overlay(Capsule().fill(highlighted ? Theme.hover : .clear))
            }
            .lineLimit(1)
    }
}

extension View {
    /// Call `action` with this view's frame in its window (SwiftUI's
    /// top-left space) now and whenever it changes.
    func onWindowFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { action(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { _, frame in action(frame) }
        })
    }
}
