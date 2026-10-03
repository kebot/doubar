import AppKit
import SwiftUI

// Drag an app icon onto another workspace's pill to move that window there.
//
// This is a plain mouse drag, not a system drag-and-drop session: those
// don't start reliably from a window of an app that is never active. AppKit
// keeps sending mouse-dragged events to the window the press began in, even
// outside it, so the drag still reaches the bars of other displays. Drop
// targets are found by hit-testing the cursor against every pill's screen
// frame.

@MainActor
final class WindowDrag: ObservableObject {
    static let shared = WindowDrag()

    struct Target: Hashable {
        let workspace: String
        let monitorId: Int
    }

    /// The window being dragged, and the pill under the cursor.
    @Published private(set) var window: AeroSpace.Window?
    @Published private(set) var target: Target?

    private var targets: [Target: NSRect] = [:]
    private var ghost: DragGhost?

    /// Pills report where they are on screen, so drops can find them.
    func register(_ target: Target, frame: NSRect) { targets[target] = frame }
    func unregister(_ target: Target) { targets[target] = nil }

    func update(_ window: AeroSpace.Window) {
        let mouse = NSEvent.mouseLocation
        if self.window == nil {
            self.window = window
            Peek.shared.hide()
            log("drag \(window.appName) (\(window.windowId)) from \(window.workspace), \(targets.count) targets")
        }
        let ghost = self.ghost ?? DragGhost()
        self.ghost = ghost
        ghost.show(window.appName, at: mouse)

        let hit = targets.first { $0.value.insetBy(dx: -2, dy: -6).contains(mouse) }?.key
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

    func isTarget(_ workspace: String, on monitorId: Int) -> Bool {
        window != nil && target == Target(workspace: workspace, monitorId: monitorId)
    }
}

/// The icon that follows the cursor during a drag.
private final class DragGhost: NSPanel {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var appName = ""
    private static let size: CGFloat = 32

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        canHide = false
        contentView = host
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

    /// Register this view, at `frame` in the bar's window space, as the drop
    /// target for `workspace`.
    func workspaceDropTarget(_ workspace: String, frame: CGRect, screen: Screen) -> some View {
        let target = WindowDrag.Target(workspace: workspace, monitorId: screen.monitorId)
        return self
            .onAppear { WindowDrag.shared.register(target, frame: screen.toScreen(frame)) }
            .onChange(of: frame) { _, f in WindowDrag.shared.register(target, frame: screen.toScreen(f)) }
            .onDisappear { WindowDrag.shared.unregister(target) }
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
        let isTarget = drag.isTarget(name, on: screen.monitorId)
        Pill(padding: 12, highlighted: isTarget) {
            Text("+ \(name)")
        }
        .overlay(
            Capsule().strokeBorder(
                Theme.foreground.opacity(isTarget ? 0.6 : 0.3),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .scaleEffect(isTarget ? 1.06 : 1)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { frame = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, f in frame = f }
        })
        .workspaceDropTarget(name, frame: frame, screen: screen)
        .animation(.easeOut(duration: 0.15), value: isTarget)
    }
}
