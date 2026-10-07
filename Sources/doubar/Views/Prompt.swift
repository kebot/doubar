import AppKit
import SwiftUI

/// A one-line text field in a small panel below a pill (the workspace
/// rename field, the clock's custom format). Return saves, Escape or a
/// click anywhere else cancels. It is a non-activating panel that still
/// becomes key, so it takes the keyboard without activating doubar or
/// taking focus from the app in front. (Activating the app instead doesn't
/// work: since macOS 14 an app can't take activation for itself.)
@MainActor
final class TextPrompt {
    static let shared = TextPrompt()

    private var panel: PromptPanel?

    func begin(
        label: String, placeholder: String, initial: String, width: CGFloat = 160, below anchor: NSRect,
        save: @escaping (String) -> Void
    ) {
        let panel = self.panel ?? PromptPanel()
        self.panel = panel
        let view = PromptView(label: label, placeholder: placeholder, initial: initial, width: width) { [weak self] text in
            if let text { save(text) }
            self?.end()
        }
        // A fresh identity each time, so the field resets and refocuses.
        panel.setContent(view.id(UUID()), below: anchor, gap: 6)
        // The app is never active, so order front regardless, then take key.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// Close the field without saving.
    func end() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

private final class PromptPanel: PopupPanel {
    // The one popup that takes the keyboard. Being a non-activating panel,
    // it does so without activating doubar.
    override var canBecomeKey: Bool { true }

    /// Clicking anywhere else cancels, like a popover.
    override func resignKey() {
        super.resignKey()
        Task { @MainActor in TextPrompt.shared.end() }
    }

    /// Editing shortcuts normally come from the Edit menu, which an app
    /// with no main menu doesn't have; send them to the field directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = Self.editActions[event.charactersIgnoringModifiers ?? ""],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let editActions: [String: Selector] = [
        "a": #selector(NSResponder.selectAll(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)), "z": Selector(("undo:")),
    ]
}

private struct PromptView: View {
    let label: String
    let placeholder: String
    let initial: String
    let width: CGFloat
    /// The text, or nil when cancelled.
    let done: (String?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.dim)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .frame(width: width)
                .focused($focused)
                .onSubmit { done(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .onExitCommand { done(nil) }
        }
        .font(Theme.font)
        .foregroundStyle(Theme.foreground)
        .environment(\.colorScheme, Config.shared.isDark ? .dark : .light)
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
