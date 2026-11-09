import Combine
import SwiftUI

/// Command widgets: `[widget.<id>]` tables in config.toml. Each runs a shell
/// command every `interval` seconds and shows the first line of its output
/// in a pill placed by a `widget:<id>` layout entry. Only widgets that are
/// in the layout run, and each runs once however many displays show it.
@MainActor
final class CommandWidgets: ObservableObject {
    static let shared = CommandWidgets()

    struct Output: Equatable {
        /// First non-empty line of stdout.
        var text = ""
        /// Why the last run failed: stderr's first line, or the exit status.
        var error: String?
        var updated: Date?
    }

    @Published private(set) var outputs: [String: Output] = [:]

    private var timers: [String: Timer] = [:]
    /// The command each timer was made for, so an edit restarts it.
    private var running: [String: Config.Command] = [:]
    private var inFlight: Set<String> = []
    private var cancellable: AnyCancellable?

    func start() {
        // Published emits before the new value is stored, so use the values it sends.
        cancellable = Config.shared.$commands
            .combineLatest(Config.shared.$layout)
            .sink { [weak self] commands, layout in
                let ids = Set((layout?.entries ?? []).compactMap(Entry.commandId))
                Task { @MainActor in self?.sync(commands.filter { ids.contains($0.key) }) }
            }
    }

    private func sync(_ wanted: [String: Config.Command]) {
        for id in Array(timers.keys) where wanted[id] == nil {
            timers[id]?.invalidate()
            timers[id] = nil
            running[id] = nil
            outputs[id] = nil
        }
        for (id, command) in wanted where running[id] != command {
            timers[id]?.invalidate()
            running[id] = command
            if outputs[id] == nil { outputs[id] = Output() }
            timers[id] = Timer.scheduledTimer(withTimeInterval: command.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(id) }
            }
            refresh(id)
        }
    }

    /// Run widget `id` now, unless the last run is still going.
    func refresh(_ id: String) {
        guard let command = running[id], inFlight.insert(id).inserted else { return }
        Task {
            let result = await runShell(command.command)
            inFlight.remove(id)
            // The widget may have been removed or edited while it ran.
            guard running[id] == command else { return }
            outputs[id] = Self.output(result)
        }
    }

    /// A click: the widget's `click` command, then a refresh.
    func click(_ id: String) {
        guard let command = Config.shared.commands[id] else { return }
        guard let click = command.click else { return refresh(id) }
        Task {
            let result = await runShell(click)
            if let status = result.status, status != 0 { log("widget \(id): click exited \(status)") }
            refresh(id)
        }
    }

    nonisolated static func output(_ r: ShellResult) -> Output {
        let line = { (s: String) in
            s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        }
        var o = Output(text: line(r.stdout), updated: Date())
        if r.status != 0 {
            let message = line(r.stderr)
            o.error = message.isEmpty ? (r.status.map { "exited \($0)" } ?? "failed to run") : message
        }
        return o
    }

    nonisolated static func clip(_ text: String, _ max: Int) -> String {
        text.count > max ? text.prefix(max - 1) + "…" : text
    }
}

/// What a command widget draws: its icon and the first line of output.
struct CommandWidgetView: View {
    let id: String

    @ObservedObject private var config = Config.shared
    @ObservedObject private var widgets = CommandWidgets.shared

    var body: some View {
        if let command = config.commands[id] {
            let output = widgets.outputs[id]
            HStack(spacing: 4) {
                if output?.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                } else if let icon = command.icon {
                    Image(systemName: icon).font(.system(size: 11))
                }
                if output?.error == nil {
                    let text = CommandWidgets.clip(output?.text ?? "", command.maxLength)
                    if !text.isEmpty { Text(text).monospacedDigit() }
                    else if output?.updated == nil { Text("…").foregroundStyle(Theme.dim) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { widgets.click(id) }
        } else {
            // [layout] names a widget with no table.
            Image(systemName: "questionmark.circle").font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
    }
}
