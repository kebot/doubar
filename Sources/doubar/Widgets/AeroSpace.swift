import AppKit
import SwiftUI

// Check https://nikitabobko.github.io/AeroSpace/guide for concepts of AeroSpace
@MainActor
final class AeroSpace: ObservableObject {
    /// Off while using OmniWM, which has its own bar. Gates every entry
    /// point (pills, `emit` events, scroll), so `shared` is never created
    /// and nothing ever runs `aerospace`.
    nonisolated static let enabled = false

    static let shared = AeroSpace()

    struct Window: Decodable, Identifiable, Equatable {
        let appName: String
        let windowId: Int
        var workspace: String
        var monitorId: Int
        var id: Int { windowId }

        enum CodingKeys: String, CodingKey {
            case appName = "app-name", windowId = "window-id", workspace, monitorId = "monitor-id"
        }
    }

    private struct Workspace: Decodable { let workspace: String }

    @Published private(set) var focusedWorkspace = ""
    /// The workspace each monitor is showing.
    @Published private(set) var visibleWorkspaces: Set<String> = []
    @Published private(set) var windows: [Window] = []

    private static let bin = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/aerospace"

    private var refreshing = false
    private var refreshAgain = false

    private init() {
        refresh()
        // Fallback for changes AeroSpace has no hook for (e.g. a window
        // closing); hooks call `doubar emit aerospace` for everything else.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in AeroSpace.shared.refresh() }
        }
    }

    /// Re-query AeroSpace. Calls that arrive mid-refresh are folded into one
    /// follow-up, so a burst of hook events costs at most two round trips.
    func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        Task {
            async let focused: [Workspace]? = query(["list-workspaces", "--focused"])
            async let all: [Window]? = query([
                "list-windows", "--all",
                "--format", "%{workspace}%{window-id}%{app-name}%{monitor-id}",
            ])
            async let visible: [Workspace]? = query(["list-workspaces", "--monitor", "all", "--visible"])
            let (f, w, v) = await (focused, all, visible)
            if let f { focusedWorkspace = f.first?.workspace ?? "" }
            if let w, w != windows {
                windows = w
                let ids = Set(w.map(\.windowId))
                WindowLayout.prune(keeping: ids)
                Peek.shared.prune(keeping: ids)
            }
            if let v {
                let shown = Set(v.map(\.workspace))
                if shown != visibleWorkspaces { visibleWorkspaces = shown }
                // AeroSpace parks hidden workspaces' windows off-screen, so
                // a window's real position is only knowable while visible.
                if let w { WindowLayout.record(w.filter { shown.contains($0.workspace) }) }
            }

            refreshing = false
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }

    // Actions apply locally first so the bar redraws on the click itself;
    // AeroSpace's hook then confirms with a refresh.

    func focus(workspace: String) {
        focusedWorkspace = workspace
        perform(["workspace", workspace])
    }

    func focus(window: Window) {
        focusedWorkspace = window.workspace
        perform(["focus", "--window-id", String(window.windowId)])
    }

    /// Send a window to another workspace, which ends up on `monitorId`.
    func move(_ window: Window, to workspace: String, monitorId: Int) {
        guard window.workspace != workspace,
              let i = windows.firstIndex(where: { $0.windowId == window.windowId })
        else { return }
        windows[i].workspace = workspace
        windows[i].monitorId = monitorId
        perform(["move-node-to-workspace", "--window-id", String(window.windowId), "--", workspace])
    }

    /// The first workspace in keyboard order that holds no windows.
    /// AeroSpace creates workspaces on demand, so any free name is a target.
    var firstFreeWorkspace: String? {
        let used = Set(windows.map { $0.workspace.lowercased() })
        guard let free = Self.keyboard.first(where: { !used.contains($0) }) else { return nil }
        // Names are case-sensitive; follow the case of existing letter names.
        let lettered = windows.map(\.workspace).filter { $0.first?.isLetter == true }
        return lettered.contains { $0 != $0.uppercased() } ? free : free.uppercased()
    }

    /// Move to the next (+1) or previous (-1) occupied workspace on a
    /// monitor, wrapping around. From another monitor, enter at its first.
    func step(_ direction: Int, on monitorId: Int) {
        let names = workspaces(on: monitorId).map(\.name)
        guard !names.isEmpty else { return }
        let target: String
        if let i = names.firstIndex(of: focusedWorkspace) {
            target = names[(i + direction + names.count) % names.count]
        } else {
            target = direction > 0 ? names[0] : names[names.count - 1]
        }
        focus(workspace: target)
    }

    private func perform(_ args: [String]) {
        Task {
            if await run(Self.bin, args) == nil {
                log("aerospace \(args.joined(separator: " ")) failed")
            }
            refresh()
        }
    }

    private func query<T: Decodable>(_ args: [String]) async -> T? {
        guard let out = await run(Self.bin, args + ["--json"]) else {
            log("aerospace \(args.joined(separator: " ")) failed")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(out.utf8))
        } catch {
            log("aerospace \(args.first ?? ""): bad JSON: \(error)")
            return nil
        }
    }

    /// Workspaces on `monitorId` that hold at least one window, in keyboard order.
    func workspaces(on monitorId: Int) -> [(name: String, windows: [Window])] {
        Dictionary(grouping: windows.filter { $0.monitorId == monitorId }, by: \.workspace)
            .map { (name: $0.key, windows: $0.value) }
            .sorted { Self.order($0.name) < Self.order($1.name) }
    }

    private static let keyboard = Array("1234567890qwertyuiop[]\\asdfghjkl;'zxcvbnm,./").map(String.init)

    private static func order(_ name: String) -> Int {
        keyboard.firstIndex(of: name.lowercased()) ?? -1
    }
}

struct AeroSpaceView: View {
    @ObservedObject private var aerospace = AeroSpace.shared
    @ObservedObject private var drag = WindowDrag.shared
    @EnvironmentObject private var screen: Screen

    var body: some View {
        HStack(spacing: 4) {
            ForEach(aerospace.workspaces(on: screen.monitorId), id: \.name) { ws in
                WorkspacePill(
                    name: ws.name, windows: ws.windows,
                    isFocused: ws.name == aerospace.focusedWorkspace)
            }
            // While an icon is being dragged, offer a workspace that is
            // empty, since AeroSpace lists only the ones with windows.
            if drag.window != nil, let free = aerospace.firstFreeWorkspace {
                FreeWorkspaceTarget(name: free)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: drag.window != nil)
    }
}

/// A workspace: click to go there, click an icon to focus that window,
/// right-click to rename, drop an icon on it to move that window here.
/// Hovering lifts the pill and fans its icon stack open.
private struct WorkspacePill: View {
    let name: String
    let windows: [AeroSpace.Window]
    let isFocused: Bool

    @EnvironmentObject private var screen: Screen
    @ObservedObject private var names = WorkspaceNames.shared
    @ObservedObject private var drag = WindowDrag.shared
    @State private var isHovered = false
    @State private var frame: CGRect = .zero

    private var slot: WorkspaceSlot { WorkspaceSlot(workspace: name, monitorId: screen.monitorId) }
    private var isDropTarget: Bool { drag.isTarget(slot) }
    private var isOpen: Bool { isFocused || isHovered || isDropTarget }

    var body: some View {
        Pill(highlighted: (isHovered && !isFocused) || isDropTarget) {
            Text(name)
            if let label = names[name] {
                Text(label)
                    .padding(.leading, 5)
                    .foregroundStyle(Theme.foreground.opacity(0.7))
            }
            HStack(spacing: isOpen ? 2 : -16) {
                ForEach(windows) { WindowIcon(window: $0) }
            }
            .padding(.leading, 6)
            .contrast(isOpen ? 1 : 0.5)
        }
        .opacity(isOpen ? 1 : 0.8)
        .contentShape(Capsule())
        .onWindowFrameChange { frame = $0 }
        .onHover { hovering in
            isHovered = hovering
            Peek.shared.pillHover(
                name, monitorId: screen.monitorId, anchor: screen.toScreen(frame), hovering: hovering)
        }
        .onTapGesture {
            Peek.shared.hide()
            AeroSpace.shared.focus(workspace: name)
        }
        .reportsPillFrame(slot, frame: frame, screen: screen)
        .contextMenu {
            Button("Rename Workspace…") { Rename.shared.begin(name, below: screen.toScreen(frame)) }
            if names[name] != nil {
                Button("Clear Name") { names.set(nil, for: name) }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isOpen)
    }
}

private struct WindowIcon: View {
    let window: AeroSpace.Window

    @State private var isHovered = false

    var body: some View {
        AppIcon(appName: window.appName)
            .scaleEffect(isHovered ? 1.12 : 1)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.foreground.opacity(isHovered ? 0.18 : 0)))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { AeroSpace.shared.focus(window: window) }
            .windowDragSource(window)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
