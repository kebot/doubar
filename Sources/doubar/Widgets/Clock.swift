import SwiftUI

struct ClockView: View {
    @ObservedObject private var config = Config.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(ClockFormat.string(context.date, config.clock.format))
                .monospacedDigit()
        }
    }
}

@MainActor
enum ClockFormat {
    /// The formats the clock's menu offers; "" is the system's numeric date
    /// and time, the default.
    static let presets = ["", "EEE d MMM  HH:mm", "EEE HH:mm:ss", "h:mm a", "HH:mm"]

    private static var formatters: [String: DateFormatter] = [:]

    /// `date` formatted with a DateFormatter `pattern`, or the system's
    /// numeric date and time when there is none.
    static func string(_ date: Date, _ pattern: String?) -> String {
        guard let pattern, !pattern.isEmpty else { return date.formatted(date: .numeric, time: .standard) }
        if let f = formatters[pattern] { return f.string(from: date) }
        let f = DateFormatter()
        f.dateFormat = pattern
        formatters[pattern] = f
        return f.string(from: date)
    }
}
