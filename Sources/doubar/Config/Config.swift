import AppKit
import SwiftUI

/// The bar's settings: ~/.config/doubar/config.toml, plus the colour
/// palette in theme.toml next to it (dotter renders that one from the
/// Omarchy theme). Both are polled once a second and reapplied when they
/// change. The settings popup and the widgets' menus write config.toml
/// back, changing only the values they own, so comments and the rest of
/// the file stay as the user wrote them. A file that fails to parse is
/// ignored (the last good settings stay) and nothing is written until it
/// is fixed.
@MainActor
final class Config: ObservableObject {
    static let shared = Config()

    struct Bar: Equatable {
        var height: CGFloat = 20
        var paddingTop: CGFloat = 6
        var paddingX: CGFloat = 10
        var gap: CGFloat = 4
        var pillPadding: CGFloat = 16
        var fontFamily = "system"
        var fontSize: CGFloat = 13
    }

    /// Colour expressions for one widget's pill, from its `style` table.
    struct Style: Equatable {
        var pill: String?
        var text: String?
        var isEmpty: Bool { pill == nil && text == nil }
    }

    struct Clock: Equatable {
        /// A DateFormatter pattern; nil for the system's numeric date and time.
        var format: String?
        var style = Style()
    }

    /// [notch]: the music overlay grown out of the MacBook notch.
    struct Notch: Equatable {
        var enabled = true
        /// Seconds.
        var collapseDelay = 1.5
        /// The current lyric line under the camera while collapsed.
        var lyricPeek = true
        /// Also show it at the top centre of every display without a notch.
        var island = true
        /// Without a notch: the current lyric line in the middle of the top row
        /// while collapsed.
        var centerLyric = true
        /// Liquid Glass below the top row (macOS 26+); the top row stays
        /// black to match the camera housing.
        var glass = true
        var colors = NotchColors()
    }

    /// [notch.colors]. The body is black (or dark glass), so these resolve
    /// against a palette whose `foreground` is the lighter of the theme's
    /// foreground and background, `background` the darker, and whose
    /// `accent` is lifted when too dark for black.
    struct NotchColors: Equatable {
        var text = Color.white
        var secondary = Color.white.opacity(0.6)
        var track = Color.white.opacity(0.16)
        var hover = Color.white.opacity(0.12)
        var accent = Color.purple
        var glow = Color.purple.opacity(0.6)
        var loved = Color.red
        /// Over the cover art.
        var scrim = Color.black.opacity(0.38)
        var icon = Color.white
        /// The Liquid Glass tint below the top row.
        var glass = Color.black.opacity(0.6)
    }

    /// How status items are coloured. Their pictures have a transparent
    /// background, so each is split into its white and grey pixels and its
    /// coloured ones (Stats' graphs and dots, a red low battery), and each
    /// layer redrawn as a mask. `palette` gives the grey layer the icon
    /// colour and each coloured pixel the theme colour nearest its hue;
    /// `mono` draws both in the accent, the coloured layer at half strength
    /// so a chart's line stays apart from its box.
    enum IconTint: String, CaseIterable {
        // Not `none`: SwiftUI's Picker reads `.none` as an empty Optional
        // and writes back another choice.
        case original = "none", palette, mono

        var title: String {
            switch self {
            case .original: "Keep Original Colours"
            case .palette: "Match Theme Palette"
            case .mono: "Accent Only"
            }
        }
    }

    /// The theme's named colours, by hue, for `IconTint.palette`.
    struct Hues {
        let red, yellow, green, cyan, blue, magenta: RGBA

        /// The theme's colour nearest in hue to a (premultiplied) pixel.
        func colour(r: Int, g: Int, b: Int) -> RGBA? {
            let maxC = max(r, g, b), minC = min(r, g, b), d = Double(maxC - minC)
            guard d > 0 else { return nil }
            var h: Double
            if maxC == r { h = Double(g - b) / d } else if maxC == g { h = Double(b - r) / d + 2 } else { h = Double(r - g) / d + 4 }
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
            switch h {
            case ..<20, 330...: return red
            case ..<70: return yellow
            case ..<165: return green
            case ..<200: return cyan
            case ..<260: return blue
            default: return magenta
            }
        }
    }

    /// The palette's red, yellow, green, cyan, blue and magenta.
    var hues: Hues {
        let c = { (key: String, fallback: RGBA) in RGBA.resolve(key, palette: self.palette) ?? fallback }
        return Hues(
            red: c("red", RGBA(r: 0.97, g: 0.46, b: 0.56)), yellow: c("yellow", RGBA(r: 0.88, g: 0.69, b: 0.41)),
            green: c("green", RGBA(r: 0.62, g: 0.81, b: 0.42)), cyan: c("cyan", RGBA(r: 0.49, g: 0.81, b: 1)),
            blue: c("blue", RGBA(r: 0.48, g: 0.64, b: 0.97)), magenta: c("magenta", RGBA(r: 0.73, g: 0.6, b: 0.97)))
    }

    enum Side: String, CaseIterable {
        case left, right
        var other: Side { self == .left ? .right : .left }
        var title: String { self == .left ? "Left" : "Right" }
    }

    /// Pills left to right on each side; each pill lists the entries it
    /// holds ("clock", "status:<app id>/<name>", ...).
    struct Layout: Equatable {
        var left: [[String]] = []
        var right: [[String]] = []

        subscript(side: Side) -> [[String]] {
            get { side == .left ? left : right }
            set { if side == .left { left = newValue } else { right = newValue } }
        }
    }

    /// The colour roles shared by every widget and popup.
    struct Colors: Equatable {
        var pill: Color
        var text: Color
        var hover: Color
        var border: Color
        var dim: Color
        var accent: Color
        var icon: Color
    }

    @Published private(set) var bar = Bar()
    @Published private(set) var colors: Colors
    /// The [layout] table, or nil when the file has none yet (see
    /// `effectiveLayout`).
    @Published private(set) var layout: Layout?
    @Published private(set) var clock = Clock()
    @Published private(set) var workspacesStyle = Style()
    @Published private(set) var notch = Notch()
    @Published private(set) var iconTint = IconTint.original
    /// A built-in palette from [theme] name, or nil to use theme.toml.
    @Published private(set) var themeName: String?
    /// The palette's `mode`, so native controls in popups match it.
    @Published private(set) var isDark = true
    /// Whether theme.toml exists, for the settings popup.
    @Published private(set) var hasThemeFile = false
    @Published private(set) var popupRadius: CGFloat = 12
    @Published private(set) var previewRadius: CGFloat = 16
    /// Why config.toml or theme.toml can't be read, if one can't.
    @Published private(set) var error: String?

    nonisolated static let directory: URL = {
        let env = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? ""
        let base = env.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
            : URL(fileURLWithPath: env)
        return base.appendingPathComponent("doubar")
    }()
    nonisolated static let configURL = directory.appendingPathComponent("config.toml")
    nonisolated static let themeURL = directory.appendingPathComponent("theme.toml")

    /// The look before themes: used for any key theme.toml doesn't set.
    private nonisolated static let builtinPalette = [
        "background": "#261d35", "foreground": "#ede9f5", "accent": "#a48cf2",
        "lighter_background": "#33284a", "muted": "#8a8399", "red": "#f7768e",
    ]
    private nonisolated static let defaultRoles = [
        "pill": "background", "text": "foreground", "hover": "foreground/12%",
        "border": "foreground/15%", "dim": "foreground/60%", "accent": "accent", "icon": "foreground",
    ]

    /// config.toml as currently applied; edits start from here.
    private var text = ""
    /// config.toml as last read from or written to disk.
    private var diskText: String?
    private var palette = builtinPalette
    /// theme.toml's palette.
    private var filePalette: [String: String] = [:]
    private var roles = defaultRoles
    /// [notch.colors] as written.
    private var notchRoles: [String: TomlValue] = [:]
    private var configError: String?
    private var themeError: String?
    private var stamps: [URL: FileStamp] = [:]
    private var pendingWrite: DispatchWorkItem?
    private var timer: Timer?

    private init() {
        colors = Self.resolveColors(Self.defaultRoles, Self.builtinPalette)
    }

    /// Read both files, then keep watching them.
    func start() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// `doubar emit reload`: read both files now, whether or not they look changed.
    func reload() {
        stamps = [:]
        poll()
    }

    // MARK: Reading

    private func poll() {
        let configStamp = FileStamp(Self.configURL)
        if configStamp != stamps[Self.configURL] {
            stamps[Self.configURL] = configStamp
            loadConfig()
        }
        let themeStamp = FileStamp(Self.themeURL)
        if themeStamp != stamps[Self.themeURL] {
            stamps[Self.themeURL] = themeStamp
            loadTheme()
        }
    }

    private func loadConfig() {
        let disk = (try? String(contentsOf: Self.configURL.resolvingSymlinksInPath(), encoding: .utf8)) ?? ""
        guard disk != diskText else { return }
        diskText = disk
        // The file changed under us: what's on disk wins over an unsaved edit.
        pendingWrite?.cancel()
        pendingWrite = nil
        apply(disk)
    }

    private func loadTheme() {
        var fresh: [String: String] = [:]
        themeError = nil
        let theme = try? String(contentsOf: Self.themeURL.resolvingSymlinksInPath(), encoding: .utf8)
        if let theme {
            do {
                let doc = try TomlDocument(theme)
                // Flat keys, or an Omarchy palette as dotter includes it.
                let table = doc["default"]?["variables"]?.table ?? doc.root
                for (key, value) in table {
                    if let s = value.string { fresh[key] = s }
                }
            } catch {
                themeError = "theme.toml \(error)"
                log(themeError!)
            }
        }
        set(\.hasThemeFile, theme != nil)
        filePalette = fresh
        updatePalette()
        publishError()
    }

    /// A built-in theme named in [theme] wins over theme.toml; keys either
    /// lacks fall back to the built-in look.
    private func updatePalette() {
        let chosen = themeName.flatMap { BuiltinThemes.palettes[$0] } ?? filePalette
        palette = Self.builtinPalette.merging(chosen) { $1 }
        set(\.isDark, palette["mode"] != "light")
        updateColors()
    }

    private func apply(_ newText: String) {
        let doc: TomlDocument
        do {
            doc = try TomlDocument(newText)
        } catch {
            configError = "config.toml \(error)"
            log("\(configError!); keeping the last good settings")
            publishError()
            return
        }
        configError = nil
        text = newText
        decode(doc)
        publishError()
    }

    private func publishError() {
        let e = configError ?? themeError
        if error != e { error = e }
    }

    private func decode(_ doc: TomlDocument) {
        var b = Bar()
        if let t = doc["bar"] {
            let defaults = b
            b.height = clamp(t["height"]?.number, 12...64) ?? defaults.height
            if let padding = t["padding"]?.array?.compactMap(\.number), padding.count == 2 {
                b.paddingTop = CGFloat(max(0, padding[0]))
                b.paddingX = CGFloat(max(0, padding[1]))
            } else if let padding = t["padding"]?.number {
                b.paddingTop = CGFloat(max(0, padding))
                b.paddingX = CGFloat(max(0, padding))
            }
            b.gap = clamp(t["gap"]?.number, 0...64) ?? defaults.gap
            b.pillPadding = clamp(t["pill-padding"]?.number, 0...64) ?? defaults.pillPadding
            b.fontFamily = t["font"]?["family"]?.string ?? defaults.fontFamily
            b.fontSize = clamp(t["font"]?["size"]?.number, 6...48) ?? defaults.fontSize
        }
        set(\.bar, b)

        var r = Self.defaultRoles
        for (key, value) in doc["colors"]?.table ?? [:] {
            if let s = value.string { r[key] = s }
        }
        roles = r
        let name = doc["theme"]?["name"]?.string
        if let name, BuiltinThemes.palettes[name] == nil { log("[theme] name: no built-in theme \"\(name)\"; using theme.toml") }
        set(\.themeName, name.flatMap { BuiltinThemes.palettes[$0] == nil ? nil : $0 })
        updatePalette()

        set(\.layout, doc["layout"].map { t in
            Layout(left: Self.pills(t["left"]), right: Self.pills(t["right"]))
        })

        let c = doc["clock"]
        set(\.clock, Clock(format: c?["format"]?.string, style: Self.style(c)))

        let n = doc["notch"]
        var notch = Notch()
        notch.enabled = n?["enabled"]?.bool ?? notch.enabled
        notch.collapseDelay = (clamp(n?["collapse-delay"]?.number, 0...5000)).map { Double($0) / 1000 } ?? notch.collapseDelay
        notch.lyricPeek = n?["lyric-peek"]?.bool ?? notch.lyricPeek
        notch.island = n?["island"]?.bool ?? notch.island
        notch.centerLyric = n?["center-lyric"]?.bool ?? notch.centerLyric
        notch.glass = n?["glass"]?.bool ?? notch.glass
        notchRoles = n?["colors"]?.table ?? [:]
        set(\.notch, notch)
        updateNotchColors()

        set(\.workspacesStyle, Self.style(doc["workspaces"]))
        set(\.iconTint, doc["status-items"]?["tint"]?.string.flatMap(IconTint.init) ?? .original)
        set(\.popupRadius, clamp(doc["popup"]?["radius"]?.number, 0...40) ?? 12)
        set(\.previewRadius, clamp(doc["popup"]?["preview-radius"]?.number, 0...40) ?? 16)
    }

    /// Assign only when the value changes, so an unrelated edit doesn't
    /// redraw everything that reads this one.
    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<Config, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    private func clamp(_ v: Double?, _ range: ClosedRange<CGFloat>) -> CGFloat? {
        v.map { min(max(CGFloat($0), range.lowerBound), range.upperBound) }
    }

    /// Unknown names (a removed widget, say) are dropped.
    private static func pills(_ v: TomlValue?) -> [[String]] {
        let known = { (s: String) in Entry.isWidget(s) || s.hasPrefix("status:") }
        return (v?.array ?? []).compactMap { item in
            let group = item.string.map { [$0] } ?? item.array?.compactMap(\.string) ?? []
            let entries = group.filter(known)
            return entries.isEmpty ? nil : entries
        }
    }

    private static func style(_ table: TomlValue?) -> Style {
        Style(pill: table?["style"]?["pill"]?.string, text: table?["style"]?["text"]?.string)
    }

    // MARK: Colours

    private func updateColors() {
        set(\.colors, Self.resolveColors(roles, palette))
        updateNotchColors()
    }

    private func updateNotchColors() {
        let fg = RGBA.resolve("foreground", palette: palette) ?? RGBA(r: 1, g: 1, b: 1)
        let bg = RGBA.resolve("background", palette: palette) ?? RGBA(r: 0, g: 0, b: 0)
        let accent = RGBA.resolve("accent", palette: palette) ?? RGBA(r: 0.64, g: 0.55, b: 0.95)
        var p = palette
        p["foreground"] = (fg.luminance >= bg.luminance ? fg : bg).hex
        // And "background" the darker, so the glass tint stays dark under
        // light text on a light theme too.
        p["background"] = (fg.luminance >= bg.luminance ? bg : fg).hex
        p["accent"] = (accent.luminance < 0.12 ? accent.mixed(with: RGBA(r: 1, g: 1, b: 1), 0.25) : accent).hex
        // "hover" names [colors].hover, read against the notch's foreground.
        p["hover"] = roles["hover"] ?? Self.defaultRoles["hover"]!

        let cover = notchRoles["cover"]
        func role(_ value: TomlValue?, _ fallback: String, _ name: String) -> Color {
            if let expr = value?.string {
                if let c = RGBA.resolve(expr, palette: p) { return c.color }
                log("notch.colors.\(name): can't resolve \"\(expr)\"; using the default")
            }
            return RGBA.resolve(fallback, palette: p)?.color ?? .gray
        }
        var c = NotchColors()
        c.text = role(notchRoles["text"], "foreground", "text")
        c.secondary = role(notchRoles["text-secondary"], "foreground/60%", "text-secondary")
        c.track = role(notchRoles["track"], "foreground/16%", "track")
        c.hover = role(notchRoles["hover"], "hover", "hover")
        c.accent = role(notchRoles["accent"], "accent", "accent")
        c.glow = role(notchRoles["glow"], "accent/60%", "glow")
        c.loved = role(notchRoles["loved"], "#f2545b", "loved")
        c.scrim = role(cover?["scrim"], "#000000/38%", "cover.scrim")
        c.icon = role(cover?["icon"], "#ffffff", "cover.icon")
        c.glass = role(notchRoles["glass"], "background/60%", "glass")
        guard notch.colors != c else { return }
        notch.colors = c
    }

    private static func resolveColors(_ roles: [String: String], _ palette: [String: String]) -> Colors {
        func role(_ name: String) -> Color {
            if let expr = roles[name], let c = RGBA.resolve(expr, palette: palette) { return c.color }
            if let expr = roles[name] { log("colors.\(name): can't resolve \"\(expr)\"; using the default") }
            return RGBA.resolve(defaultRoles[name]!, palette: palette)?.color ?? .gray
        }
        return Colors(
            pill: role("pill"), text: role("text"), hover: role("hover"), border: role("border"), dim: role("dim"),
            accent: role("accent"), icon: role("icon"))
    }

    /// A widget's own pill and text colours, or nil to use the shared ones.
    func colors(for style: Style) -> (pill: Color, text: Color)? {
        guard !style.isEmpty else { return nil }
        let resolve = { (e: String?) in e.flatMap { RGBA.resolve($0, palette: self.palette)?.color } }
        return (resolve(style.pill) ?? colors.pill, resolve(style.text) ?? colors.text)
    }

    /// The style a built-in widget has in its table.
    func style(of widget: String) -> Style {
        switch widget {
        case "clock": clock.style
        case "workspaces": workspacesStyle
        default: Style()
        }
    }

    var font: Font {
        bar.fontFamily == "system" ? .system(size: bar.fontSize) : .custom(bar.fontFamily, size: bar.fontSize)
    }

    // MARK: Writing

    /// Set one value in config.toml; nil removes the key. Sliders pass
    /// `debounce`, so the bar follows live and the file is written once
    /// they settle.
    func set(_ table: String, _ key: String, _ value: TomlValue?, debounce: Bool = false) {
        edit(debounce: debounce) { $0.setting(value, at: [table], key) }
    }

    /// Save the [bar] values that differ from the current ones. Called as
    /// sliders move, so the write waits for them to settle.
    func setBar(_ b: Bar) {
        let old = bar
        if b.height != old.height { set("bar", "height", .int(Int(b.height)), debounce: true) }
        if b.paddingTop != old.paddingTop || b.paddingX != old.paddingX {
            set("bar", "padding", .array([.int(Int(b.paddingTop)), .int(Int(b.paddingX))]), debounce: true)
        }
        if b.gap != old.gap { set("bar", "gap", .int(Int(b.gap)), debounce: true) }
        if b.pillPadding != old.pillPadding { set("bar", "pill-padding", .int(Int(b.pillPadding)), debounce: true) }
        if b.fontFamily != old.fontFamily || b.fontSize != old.fontSize {
            set("bar", "font", .table(["family": .string(b.fontFamily), "size": .int(Int(b.fontSize))]), debounce: true)
        }
    }

    /// A widget's style, as an inline table; nil goes back to the defaults.
    func setStyle(_ style: Style?, of widget: String) {
        var t: [String: TomlValue] = [:]
        if let pill = style?.pill { t["pill"] = .string(pill) }
        if let text = style?.text { t["text"] = .string(text) }
        set(widget, "style", t.isEmpty ? nil : .table(t))
    }

    /// Rewrite the [layout] table.
    func setLayout(_ layout: Layout) {
        edit(debounce: false) {
            $0.replacingTable(
                ["layout"], with: Self.layoutBody(layout),
                comment: "Written by doubar's settings; comments inside this table are not kept.")
        }
    }

    private static func layoutBody(_ layout: Layout) -> String {
        var out = ""
        for side in Side.allCases {
            let pills = layout[side]
            guard !pills.isEmpty else {
                out += "\(side.rawValue) = []\n"
                continue
            }
            out += "\(side.rawValue) = [\n"
            for pill in pills {
                if pill.count == 1 {
                    out += "  \(TomlValue.quote(pill[0])),\n"
                } else {
                    out += "  [\n" + pill.map { "    \(TomlValue.quote($0)),\n" }.joined() + "  ],\n"
                }
            }
            out += "]\n"
        }
        return out
    }

    private func edit(debounce: Bool, _ change: (TomlDocument) -> String) {
        if let configError {
            log("not saving: \(configError)")
            NSSound.beep()
            return
        }
        guard let doc = try? TomlDocument(text) else { return }
        apply(change(doc))
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.write() }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (debounce ? 0.3 : 0), execute: work)
    }

    /// Write through a symlink (dotter's), never over it.
    private func write() {
        pendingWrite = nil
        let url = Self.configURL.resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            diskText = text
            stamps[Self.configURL] = FileStamp(Self.configURL)
        } catch {
            log("writing \(url.path) failed: \(error)")
        }
    }

    // MARK: `doubar check-config`

    /// Parse both files and report what's wrong, for the command line.
    nonisolated static func check() -> Int32 {
        var failed = false
        for url in [configURL, themeURL] {
            guard let text = try? String(contentsOf: url.resolvingSymlinksInPath(), encoding: .utf8) else {
                print("\(url.path): not found (defaults apply)")
                continue
            }
            do {
                let doc = try TomlDocument(text)
                print("\(url.path): ok")
                guard url == configURL else { continue }
                let themePalette = (try? String(contentsOf: themeURL.resolvingSymlinksInPath(), encoding: .utf8))
                    .flatMap { try? TomlDocument($0) }
                    .map { ($0["default"]?["variables"]?.table ?? $0.root).compactMapValues(\.string) } ?? [:]
                let name = doc["theme"]?["name"]?.string
                if let name, BuiltinThemes.palettes[name] == nil {
                    print("  [theme] name: no built-in theme \"\(name)\"; one of \(BuiltinThemes.names.joined(separator: ", "))")
                    failed = true
                }
                let chosen = name.flatMap { BuiltinThemes.palettes[$0] } ?? themePalette
                let all = builtinPalette.merging(chosen) { $1 }
                var exprs: [(String, String)] = []
                for (k, v) in doc["colors"]?.table ?? [:] { if let s = v.string { exprs.append(("colors.\(k)", s)) } }
                for w in ["clock", "workspaces"] {
                    for k in ["pill", "text"] {
                        if let s = doc[w]?["style"]?[k]?.string { exprs.append(("\(w).style.\(k)", s)) }
                    }
                }
                for (name, expr) in exprs where RGBA.resolve(expr, palette: all) == nil {
                    print("  \(name): can't resolve \"\(expr)\"")
                    failed = true
                }
            } catch {
                print("\(url.path): \(error)")
                failed = true
            }
        }
        return failed ? 1 : 0
    }
}

/// What changes when a file does, cheap to read every second. The path is
/// resolved first, so a dotter symlink is followed to the real file.
private struct FileStamp: Equatable {
    let modified: Date?
    let size: Int?
    let inode: Int?

    init(_ url: URL) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        modified = attrs?[.modificationDate] as? Date
        size = (attrs?[.size] as? NSNumber)?.intValue
        inode = (attrs?[.systemFileNumber] as? NSNumber)?.intValue
    }
}
