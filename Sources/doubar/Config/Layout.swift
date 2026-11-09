import Foundation

// A layout entry is a built-in widget's name, or a status item:
// "status:<app id>/<name>" for one item, "status:<app id>" for every item
// of that app. Each pill in [layout] lists one or more entries.

enum Entry {
    static let widgets = ["workspaces", "clock", "settings"]

    private static let statusPrefix = "status:"

    static func status(_ itemId: String) -> String { statusPrefix + itemId }

    /// The status item (or app) a layout entry names; nil for a widget.
    static func itemId(_ entry: String) -> String? {
        entry.hasPrefix(statusPrefix) ? String(entry.dropFirst(statusPrefix.count)) : nil
    }

    static func isStatus(_ entry: String) -> Bool { itemId(entry) != nil }

    private static let commandPrefix = "widget:"

    /// The layout entry for the command widget `id` ([widget.<id>]).
    static func command(_ id: String) -> String { commandPrefix + id }

    /// The command widget a layout entry names; nil for anything else.
    static func commandId(_ entry: String) -> String? {
        entry.hasPrefix(commandPrefix) ? String(entry.dropFirst(commandPrefix.count)) : nil
    }

    static func isCommand(_ entry: String) -> Bool { commandId(entry) != nil }

    /// A widget id as the settings UI writes it: lower-case letters,
    /// digits, "-" and "_"; nil when nothing is left.
    static func sanitizedId(_ name: String) -> String? {
        var out = ""
        for c in name.lowercased().unicodeScalars {
            if ("a"..."z").contains(c) || ("0"..."9").contains(c) || c == "-" || c == "_" {
                out.unicodeScalars.append(c)
            } else if c == " " {
                out += "-"
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Whether `entry` shows the status item `itemId`.
    static func matches(_ entry: String, item itemId: String) -> Bool {
        guard let named = Self.itemId(entry) else { return false }
        // Items used to be named by their whole tooltip; entries saved then
        // still match by their first line.
        let target = firstLine(named)
        return target == itemId || (!target.contains("/") && itemId.hasPrefix(target + "/"))
    }

    /// An item's name up to the first line break: the part of a multi-line
    /// tooltip that doesn't change.
    static func firstLine(_ name: String) -> String {
        name.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? name
    }

    static func isWidget(_ entry: String) -> Bool { widgets.contains(entry) }
}

extension Config.Layout {
    /// Where a dragged pill (or part of one) lands.
    enum Drop: Equatable {
        case before(Config.Side, ref: String)
        case after(Config.Side, ref: String)
        /// Into the pill holding `ref`, sharing it.
        case join(Config.Side, ref: String)
        case end(Config.Side)
        /// Out of the bar.
        case out
    }

    var entries: [String] { (left + right).flatMap { $0 } }

    func side(of entry: String) -> Config.Side? {
        Config.Side.allCases.first { self[$0].contains { $0.contains(entry) } }
    }

    func pill(containing entry: String) -> [String]? {
        (left + right).first { $0.contains(entry) }
    }

    /// Take `entries` out, dropping pills left empty.
    mutating func remove(_ entries: [String]) {
        for side in Config.Side.allCases {
            self[side] = self[side].map { $0.filter { !entries.contains($0) } }.filter { !$0.isEmpty }
        }
    }

    /// Give each entry of the pill holding `entry` a pill of its own.
    mutating func split(pillWith entry: String) {
        guard let side = side(of: entry), let i = self[side].firstIndex(where: { $0.contains(entry) }) else { return }
        self[side].replaceSubrange(i...i, with: self[side][i].map { [$0] })
    }

    /// Move `entries` as one pill to `drop`. Returns false when the drop
    /// is onto the moved pill itself, which changes nothing.
    @discardableResult
    mutating func move(_ entries: [String], _ drop: Drop) -> Bool {
        let ref: String?
        switch drop {
        case .before(_, let r), .after(_, let r), .join(_, let r): ref = r
        case .end, .out: ref = nil
        }
        if let ref, entries.contains(ref) { return false }
        remove(entries)
        switch drop {
        case .out:
            break
        case .end(let side):
            self[side].append(entries)
        case .before(let side, let ref), .after(let side, let ref), .join(let side, let ref):
            guard let i = self[side].firstIndex(where: { $0.contains(ref) }) else {
                self[side].append(entries)
                break
            }
            if case .join = drop {
                self[side][i] += entries
            } else if case .after = drop {
                self[side].insert(entries, at: i + 1)
            } else {
                self[side].insert(entries, at: i)
            }
        }
        return true
    }
}

extension Config {
    /// The layout in use: config.toml's [layout] or, until one is saved,
    /// the bar as it was before layouts: the status items not hidden in the
    /// old settings popup, then the clock and the settings button.
    var effectiveLayout: Layout {
        if let layout { return layout }
        let hidden = StatusItems.legacyHidden
        let items = StatusItems.shared.items.map(\.id).filter { !hidden.contains($0) }.map(Entry.status)
        return Layout(
            left: AeroSpace.enabled ? [["workspaces"]] : [],
            right: (items.isEmpty ? [] : [items]) + [["clock"], ["settings"]])
    }

    /// The entry that puts status item `itemId` in the bar, if any.
    func entry(showing itemId: String) -> String? {
        effectiveLayout.entries.first { Entry.matches($0, item: itemId) }
    }

    /// Change the layout and save it. The first change also saves the
    /// default layout it started from.
    func updateLayout(_ change: (inout Layout) -> Void) {
        var l = effectiveLayout
        change(&l)
        if l != layout { setLayout(l) }
    }

    /// Take `key` (a widget, or "status:<id>" for one item) out of the bar.
    /// An item shown by its app's entry splits that entry into the app's
    /// other items, so the rest of the app stays.
    func removeFromBar(_ key: String) {
        updateLayout { l in
            if l.entries.contains(key) {
                l.remove([key])
                return
            }
            guard let itemId = Entry.itemId(key), let appEntry = l.entries.first(where: { Entry.matches($0, item: itemId) }),
                  let side = l.side(of: appEntry),
                  let p = l[side].firstIndex(where: { $0.contains(appEntry) }),
                  let e = l[side][p].firstIndex(of: appEntry)
            else { return }
            let rest = StatusItems.shared.items.map(\.id)
                .filter { $0 != itemId && Entry.matches(appEntry, item: $0) }
                .map(Entry.status)
            l[side][p].replaceSubrange(e...e, with: rest)
            if l[side][p].isEmpty { l[side].remove(at: p) }
        }
    }
}
