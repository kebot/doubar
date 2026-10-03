import AppKit
import SwiftUI

/// A workspace as shown on one monitor's bar.
struct WorkspaceSlot: Hashable {
    let workspace: String
    let monitorId: Int
}

/// Where each workspace pill is on screen, across every bar: drags find
/// their drop target here, and scrolling is scoped to the pills' span.
///
/// Each pill view registers under its own id, so a pill whose workspace or
/// monitor changes replaces its entry instead of leaving a stale one.
/// Frames are kept in their bar's window space and converted on lookup, so
/// they stay right when a bar moves to another display.
@MainActor
enum PillFrames {
    private struct Entry {
        let slot: WorkspaceSlot
        let frame: CGRect
        weak var screen: Screen?

        var screenFrame: NSRect? { screen?.toScreen(frame) }
    }

    private static var entries: [UUID: Entry] = [:]

    static func set(_ id: UUID, slot: WorkspaceSlot, frame: CGRect, screen: Screen) {
        entries[id] = Entry(slot: slot, frame: frame, screen: screen)
    }

    static func remove(_ id: UUID) { entries[id] = nil }

    /// The pill under `point` (screen coordinates), with a little slack
    /// since the pills are only 20pt tall.
    static func slot(at point: NSPoint) -> WorkspaceSlot? {
        entries.values.first { $0.screenFrame?.insetBy(dx: -2, dy: -6).contains(point) == true }?.slot
    }

    /// The horizontal span of the pills on a monitor's bar, in screen
    /// coordinates.
    static func span(on monitorId: Int) -> ClosedRange<CGFloat>? {
        let frames = entries.values.filter { $0.slot.monitorId == monitorId }.compactMap(\.screenFrame)
        guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max() else { return nil }
        return minX...maxX
    }
}

extension View {
    /// Register this view, at `frame` in its bar's window space, as the pill
    /// for `slot`.
    func reportsPillFrame(_ slot: WorkspaceSlot, frame: CGRect, screen: Screen) -> some View {
        modifier(PillFrameReporter(slot: slot, frame: frame, screen: screen))
    }
}

private struct PillFrameReporter: ViewModifier {
    let slot: WorkspaceSlot
    let frame: CGRect
    let screen: Screen

    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear(perform: update)
            .onChange(of: frame) { update() }
            .onChange(of: slot) { update() }
            .onDisappear { PillFrames.remove(id) }
    }

    private func update() {
        PillFrames.set(id, slot: slot, frame: frame, screen: screen)
    }
}
