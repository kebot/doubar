import Foundation

// A layout entry is a built-in widget's name, or a status item:
// "status:<app id>/<name>" for one item, "status:<app id>" for every item
// of that app. Each pill in [layout] lists one or more entries.

enum Entry {
    static let widgets = ["workspaces", "spotify", "clock", "settings"]

    static func status(_ itemId: String) -> String { "status:" + itemId }

    /// Whether `entry` shows the status item `itemId`.
    static func matches(_ entry: String, item itemId: String) -> Bool {
        guard entry.hasPrefix("status:") else { return false }
        let target = entry.dropFirst("status:".count)
        return target == itemId || (!target.contains("/") && itemId.hasPrefix(target + "/"))
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
    /// old settings popup, then Spotify, the clock and the settings button.
    var effectiveLayout: Layout {
        if let layout { return layout }
        let hidden = StatusItems.legacyHidden
        let items = StatusItems.shared.items.map(\.id).filter { !hidden.contains($0) }.map(Entry.status)
        return Layout(
            left: AeroSpace.enabled ? [["workspaces"]] : [],
            right: (items.isEmpty ? [] : [items]) + [["spotify"], ["clock"], ["settings"]])
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
            let itemId = String(key.dropFirst("status:".count))
            guard key.hasPrefix("status:"), let appEntry = l.entries.first(where: { Entry.matches($0, item: itemId) }),
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
