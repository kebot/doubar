import AppKit
import SwiftUI

/// Display names for workspaces. AeroSpace can't rename a workspace, so
/// these are labels doubar keeps for itself, saved across launches.
@MainActor
final class WorkspaceNames: ObservableObject {
    static let shared = WorkspaceNames()

    // A fixed suite, so the bare binary and the .app share names.
    private let defaults = UserDefaults(suiteName: "com.yaofur.doubar") ?? .standard
    private let key = "workspaceNames"

    @Published private(set) var names: [String: String]

    private init() {
        names = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    subscript(workspace: String) -> String? { names[workspace] }

    /// Set a workspace's name; blank clears it.
    func set(_ name: String?, for workspace: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        names[workspace] = trimmed.isEmpty ? nil : trimmed
        defaults.set(names, forKey: key)
    }
}

/// The rename field: a small panel below the pill. It is a non-activating
/// panel that still becomes key, so it takes the keyboard without
/// activating doubar or taking focus from the app in front. (Activating
/// the app instead doesn't work: since macOS 14 an app can't take
/// activation for itself.)
@MainActor
final class Rename {
    static let shared = Rename()

    private var panel: RenamePanel?

    func begin(_ workspace: String, below anchor: NSRect) {
        Peek.shared.hide()

        let panel = self.panel ?? RenamePanel()
        self.panel = panel
        panel.show(
            RenameView(workspace: workspace, initial: WorkspaceNames.shared[workspace] ?? "") { [weak self] name in
                if let name { WorkspaceNames.shared.set(name, for: workspace) }
                self?.end()
            },
            below: anchor)
    }

    /// Open the field from a script, anchored to the bar of the workspace's
    /// monitor (`doubar emit rename workspace=<name>`).
    func begin(_ workspace: String) {
        let monitorId = AeroSpace.shared.windows.first { $0.workspace == workspace }?.monitorId ?? 1
        guard let screen = NSScreen.forAeroSpaceMonitor(monitorId) ?? NSScreen.main else { return }
        let f = screen.frame
        begin(workspace, below: NSRect(x: f.minX + 10, y: f.maxY - BarWindow.height + 4, width: 0, height: 0))
    }

    /// Close the field without saving.
    func end() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

private final class RenamePanel: NSPanel {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        canHide = false
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Clicking anywhere else cancels, like a popover.
    override func resignKey() {
        super.resignKey()
        Task { @MainActor in Rename.shared.end() }
    }

    func show(_ view: RenameView, below anchor: NSRect) {
        // A fresh identity each time, so the field resets and refocuses.
        host.rootView = AnyView(view.id(UUID()))
        let size = host.fittingSize
        let bounds = NSScreen.screens.first { $0.frame.intersects(anchor.insetBy(dx: -1, dy: -1)) }?.frame ?? anchor
        let x = min(max(anchor.minX, bounds.minX + 8), bounds.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
    }
}

private struct RenameView: View {
    let workspace: String
    let initial: String
    /// The new name, or nil when cancelled.
    let done: (String?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(workspace)
                .foregroundStyle(Theme.foreground.opacity(0.6))
            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 160)
                .focused($focused)
                .onSubmit { done(text) }
                .onExitCommand { done(nil) }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(Theme.background)
                .overlay(Capsule().strokeBorder(Theme.foreground.opacity(0.2))))
        .fixedSize()
        .onAppear {
            text = initial
            focused = true
        }
    }
}
