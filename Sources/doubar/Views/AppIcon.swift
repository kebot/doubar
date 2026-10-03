import AppKit
import SwiftUI

/// A running application's icon, or its name when it has none.
struct AppIcon: View {
    let appName: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = AppIcon.icon(for: appName) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Text(appName)
        }
    }

    private static var cache: [String: NSImage] = [:]

    /// The icon of a running application, looked up by its localized name.
    /// Only hits are cached, so an app that wasn't running at first lookup
    /// gets its icon once it is.
    static func icon(for appName: String) -> NSImage? {
        if let cached = cache[appName] { return cached }
        let icon = NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }?.icon
        if let icon { cache[appName] = icon }
        return icon
    }
}
