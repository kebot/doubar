import AppKit
import SwiftUI

// Drag an app icon onto another workspace's pill to move that window there.
//
// This is a plain mouse drag, not a system drag-and-drop session: those
// don't start reliably from a window of an app that is never active. AppKit
// keeps sending mouse-dragged events to the window the press began in, even
// outside it, so the drag still reaches the bars of other displays. Drop
// targets are found by hit-testing the cursor against PillFrames.

@MainActor
final class WindowDrag: ObservableObject {
    static let shared = WindowDrag()

    /// The window being dragged, and the pill under the cursor.
    @Published private(set) var window: AeroSpace.Window?
    @Published private(set) var target: WorkspaceSlot?

    private var ghost: DragGhost?

    func update(_ window: AeroSpace.Window) {
        let mouse = NSEvent.mouseLocation
        if self.window == nil {
            self.window = window
            Peek.shared.hide()
            log("drag \(window.appName) (\(window.windowId)) from \(window.workspace)")
        }
        let ghost = self.ghost ?? DragGhost()
        self.ghost = ghost
        ghost.show(window.appName, at: mouse)

        let hit = PillFrames.slot(at: mouse)
        if hit != target { target = hit }
    }

    func finish() {
        log("drop \(window?.appName ?? "-") on \(target.map { "\($0.workspace)@\($0.monitorId)" } ?? "nothing")")
        if let window, let target, target.workspace != window.workspace {
            AeroSpace.shared.move(window, to: target.workspace, monitorId: target.monitorId)
        }
        ghost?.orderOut(nil)
        window = nil
        target = nil
    }

    func isTarget(_ slot: WorkspaceSlot) -> Bool {
        window != nil && target == slot
    }
}

/// The icon that follows the cursor during a drag.
private final class DragGhost: PopupPanel {
    private var appName = ""
    private static let size: CGFloat = 32

    init() {
        super.init(size: NSSize(width: Self.size, height: Self.size))
        ignoresMouseEvents = true
    }

    func show(_ appName: String, at point: NSPoint) {
        if appName != self.appName {
            self.appName = appName
            host.rootView = AnyView(AppIcon(appName: appName, size: Self.size).opacity(0.9))
        }
        setFrameOrigin(NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2))
        if !isVisible { orderFrontRegardless() }
    }
}

extension View {
    /// Make this view a drag handle for `window`. A press that doesn't move
    /// stays a click.
    func windowDragSource(_ window: AeroSpace.Window) -> some View {
        gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in WindowDrag.shared.update(window) }
                .onEnded { _ in WindowDrag.shared.finish() })
    }
}

/// The "+ 3" pill shown while dragging: a drop target for the first empty
/// workspace.
struct FreeWorkspaceTarget: View {
    let name: String

    @EnvironmentObject private var screen: Screen
    @ObservedObject private var drag = WindowDrag.shared
    @State private var frame: CGRect = .zero

    var body: some View {
        let slot = WorkspaceSlot(workspace: name, monitorId: screen.monitorId)
        let isTarget = drag.isTarget(slot)
        Pill(padding: 12, highlighted: isTarget) {
            Text("+ \(name)")
        }
        .overlay(
            Capsule().strokeBorder(
                Theme.foreground.opacity(isTarget ? 0.6 : 0.3),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .scaleEffect(isTarget ? 1.06 : 1)
        .onWindowFrameChange { frame = $0 }
        .reportsPillFrame(slot, frame: frame, screen: screen)
        .animation(.easeOut(duration: 0.15), value: isTarget)
    }
}
