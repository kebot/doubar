import SwiftUI

/// The right-click menu of anything in the bar: a widget's own options,
/// its style, then where it sits. Every choice is saved to config.toml.
struct EntryMenu: View {
    /// A widget's name, or "status:<id>" for one status item.
    let key: String
    /// The frame of the bar it was opened from, to put popups below it.
    let bar: NSRect

    /// Below the right end of the bar.
    private var anchor: NSRect { NSRect(x: bar.maxX, y: bar.minY + 4, width: 0, height: 0) }

    var body: some View {
        switch key {
        case "clock": ClockMenu(anchor: anchor)
        case "spotify": SpotifyMenu()
        default: EmptyView()
        }
        if key == "clock" || key == "spotify" {
            StyleMenu(widget: key)
        }
        if key.hasPrefix("status:") {
            IconTintMenu()
        }
        PlacementMenu(key: key)
        Divider()
        ThemePicker(title: "Theme")
        Button("Bar Settings…") { BarSettings.shared.open(below: anchor) }
    }
}

private struct ClockMenu: View {
    // Observed, or SwiftUI keeps showing the menu as it was first built.
    @ObservedObject private var config = Config.shared
    let anchor: NSRect

    var body: some View {
        let current = config.clock.format ?? ""
        Picker("Format", selection: Binding(
            get: { current },
            set: { config.set("clock", "format", $0.isEmpty ? nil : .string($0)) }
        )) {
            ForEach(ClockFormat.presets, id: \.self) { pattern in
                Text(ClockFormat.string(.now, pattern.isEmpty ? nil : pattern)).tag(pattern)
            }
            if !ClockFormat.presets.contains(current) {
                Text(ClockFormat.string(.now, current)).tag(current)
            }
        }
        .pickerStyle(.inline)
        Button("Custom Format…") {
            TextPrompt.shared.begin(
                label: "Format", placeholder: "EEE d MMM HH:mm", initial: current, width: 220, below: anchor
            ) { pattern in
                config.set("clock", "format", pattern.isEmpty ? nil : .string(pattern))
            }
        }
        Divider()
    }
}

private struct SpotifyMenu: View {
    // Observed, or SwiftUI keeps showing the menu as it was first built.
    @ObservedObject private var config = Config.shared
    private static let widths = [160, 240, 320, 480]

    var body: some View {
        let options = config.spotify
        Toggle("Show Artwork", isOn: Binding(
            get: { options.artwork },
            set: { config.set("spotify", "artwork", .bool($0)) }))
        Picker("Text", selection: Binding(
            get: { options.text },
            set: { config.set("spotify", "text", .string($0.rawValue)) }
        )) {
            Text("Artist and Title").tag(Config.SpotifyText.artistTitle)
            Text("Title Only").tag(Config.SpotifyText.title)
        }
        .pickerStyle(.inline)
        let width = Int(options.maxWidth)
        Picker("Maximum Width", selection: Binding(
            get: { width },
            set: { config.set("spotify", "max-width", .int($0)) }
        )) {
            ForEach(Self.widths.contains(width) ? Self.widths : (Self.widths + [width]).sorted(), id: \.self) {
                Text("\($0) pt").tag($0)
            }
        }
        .pickerStyle(.menu)
        Divider()
    }
}

/// The pill colours a widget can pick from; the file takes any colour.
private struct StyleMenu: View {
    // Observed, or SwiftUI keeps showing the menu as it was first built.
    @ObservedObject private var config = Config.shared
    let widget: String

    private static let presets: [(name: String, style: Config.Style)] = [
        ("Default", Config.Style()),
        ("Accent", Config.Style(pill: "accent", text: "background")),
        ("Subtle", Config.Style(pill: "lighter_background")),
    ]

    var body: some View {
        let current = config.style(of: widget)
        let selected = Self.presets.firstIndex { $0.style == current } ?? -1
        Picker("Style", selection: Binding(
            get: { selected },
            set: { i in if i >= 0 { config.setStyle(Self.presets[i].style, of: widget) } }
        )) {
            ForEach(Self.presets.indices, id: \.self) { Text(Self.presets[$0].name).tag($0) }
            if selected < 0 { Text("Custom (config.toml)").tag(-1) }
        }
        .pickerStyle(.menu)
    }
}

/// The palette: theme.toml (dotter's, from the Omarchy theme) or one of the
/// built-in themes, each shown with its background and accent.
struct ThemePicker: View {
    let title: String

    @ObservedObject private var config = Config.shared

    var body: some View {
        Picker(title, selection: Binding(
            get: { config.themeName ?? "" },
            set: { config.set("theme", "name", $0.isEmpty ? nil : .string($0)) }
        )) {
            Text(config.hasThemeFile ? "theme.toml" : "theme.toml (not found)").tag("")
            Divider()
            ForEach(BuiltinThemes.names, id: \.self) { name in
                Label { Text(name) } icon: { Image(nsImage: Self.swatch(name)) }.tag(name)
            }
        }
        .pickerStyle(.menu)
    }

    private static var swatches: [String: NSImage] = [:]

    /// Two dots: the theme's background, then its accent.
    @MainActor
    static func swatch(_ name: String) -> NSImage {
        if let image = swatches[name] { return image }
        let palette = BuiltinThemes.palettes[name] ?? [:]
        let image = NSImage(size: NSSize(width: 26, height: 12), flipped: false) { _ in
            for (i, key) in ["background", "accent"].enumerated() {
                let c = palette[key].flatMap { RGBA(hex: $0) } ?? RGBA(r: 0.5, g: 0.5, b: 0.5)
                NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).setFill()
                let dot = NSBezierPath(ovalIn: NSRect(x: 1 + CGFloat(i) * 13, y: 0.5, width: 11, height: 11))
                dot.fill()
                NSColor.gray.withAlphaComponent(0.5).setStroke()
                dot.lineWidth = 0.5
                dot.stroke()
            }
            return true
        }
        swatches[name] = image
        return image
    }
}

/// How every status item is coloured; the same setting as the Bar tab's.
private struct IconTintMenu: View {
    @ObservedObject private var config = Config.shared

    var body: some View {
        Picker("Icon Colour", selection: Binding(
            get: { config.iconTint },
            set: { config.set("status-items", "tint", .string($0.rawValue)) }
        )) {
            ForEach(Config.IconTint.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
    }
}

private struct PlacementMenu: View {
    // Observed, or SwiftUI keeps showing the menu as it was first built.
    @ObservedObject private var config = Config.shared
    let key: String

    var body: some View {
        let layout = config.effectiveLayout
        // A status item may be in the bar through its app's entry.
        let entry = layout.entries.contains(key)
            ? key : key.hasPrefix("status:") ? config.entry(showing: String(key.dropFirst("status:".count))) : nil
        if let entry, let side = layout.side(of: entry) {
            Divider()
            if (layout.pill(containing: entry)?.count ?? 0) > 1 {
                Button("Split Pill") { config.updateLayout { $0.split(pillWith: entry) } }
            }
            Button("Move to \(side.other.title)") { config.updateLayout { $0.move([entry], .end(side.other)) } }
            Button("Remove from Bar") { config.removeFromBar(key) }
        }
    }
}
