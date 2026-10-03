import AppKit
import SwiftUI

@MainActor
final class Spotify: ObservableObject {
    static let shared = Spotify()

    struct Track: Equatable {
        var artist: String
        var name: String
        var artworkURL: URL?
    }

    /// The playing track, or nil when paused, stopped or not running.
    @Published private(set) var track: Track?

    // Guard with `is running`: a bare `tell application "Spotify"` launches
    // Spotify, so asking it while it was quit would relaunch it.
    private static let script = """
        if application "Spotify" is running then tell application "Spotify" to if player state is playing then \
        return (artist of current track) & "|||" & (name of current track) & "|||" & (artwork url of current track)
        """

    private init() {
        // Spotify announces every play/pause/track change, so there is
        // nothing to poll; query once at launch and then on each change.
        observeDistributed(Notification.Name("com.spotify.client.PlaybackStateChanged")) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Quitting while playing doesn't always announce a stop first.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.spotify.client" else { return }
            Task { @MainActor in self?.track = nil }
        }
        Task { await refresh() }
    }

    func refresh() async {
        let raw = await run("/usr/bin/osascript", ["-e", Self.script])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 2, !parts[1].isEmpty else {
            track = nil
            return
        }
        track = Track(
            artist: parts[0], name: parts[1],
            artworkURL: parts.count > 2 ? URL(string: parts[2]) : nil)
    }
}

struct SpotifyView: View {
    @ObservedObject private var spotify = Spotify.shared

    var body: some View {
        if let track = spotify.track {
            Pill(padding: 0) {
                AsyncImage(url: track.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .frame(width: Theme.pillHeight - 4, height: Theme.pillHeight - 4)
                .clipShape(Circle())
                .padding(.leading, 2)

                Text("▶ \(track.artist) – \(track.name)")
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
            }
        }
    }
}
