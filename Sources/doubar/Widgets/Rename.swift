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

/// The rename field, below the workspace's pill (see `TextPrompt`).
@MainActor
final class Rename {
    static let shared = Rename()

    func begin(_ workspace: String, below anchor: NSRect) {
        Peek.shared.hide()
        TextPrompt.shared.begin(
            label: workspace, placeholder: "Name", initial: WorkspaceNames.shared[workspace] ?? "", below: anchor
        ) { name in
            WorkspaceNames.shared.set(name, for: workspace)
        }
    }

    /// Open the field from a script, anchored to the bar of the workspace's
    /// monitor (`doubar emit rename workspace=<name>`).
    func begin(_ workspace: String) {
        guard let (anchor, _) = NSScreen.barAnchor(for: workspace) else { return }
        begin(workspace, below: anchor)
    }

    /// Close the field without saving.
    func end() {
        TextPrompt.shared.end()
    }
}
