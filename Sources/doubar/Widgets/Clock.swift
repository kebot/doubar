import SwiftUI

struct ClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Pill {
                Text(context.date.formatted(date: .numeric, time: .standard))
                    .monospacedDigit()
            }
        }
    }
}
