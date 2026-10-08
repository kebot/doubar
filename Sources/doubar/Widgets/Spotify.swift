import AppKit
import SwiftUI

@MainActor
final class Spotify: ObservableObject {
    static let shared = Spotify()

    struct Track: Equatable {
        /// Spotify's URI, e.g. "spotify:track:…".
        var id: String
        var artist: String
        var name: String
        var album: String
        /// Seconds.
        var duration: Double
        var artworkURL: URL?
    }

    /// The loaded track, playing or paused; nil when stopped or not running.
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    /// The player position at `positionAt`; see `position(at:)`.
    private var position: Double = 0
    private var positionAt = Date()

    // Guard with `is running`: a bare `tell application "Spotify"` launches
    // Spotify, so asking it while it was quit would relaunch it.
    private static let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is stopped then return ""
                set t to current track
                return (player state as text) & "|||" & (id of t) & "|||" & (artist of t) & "|||" & (name of t) ¬
                    & "|||" & (album of t) & "|||" & (duration of t) & "|||" & (player position as text) ¬
                    & "|||" & (artwork url of t)
            end tell
        end if
        """

    private init() {
        // Spotify announces every play/pause/track change; query once at
        // launch and then on each change.
        observeDistributed(Notification.Name("com.spotify.client.PlaybackStateChanged")) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Quitting while playing doesn't always announce a stop first.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.spotify.client" else { return }
            Task { @MainActor in
                self?.track = nil
                self?.isPlaying = false
            }
        }
        // Seeks made in Spotify itself aren't announced, so while playing
        // the position is re-read now and then; between reads it is
        // interpolated.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                await self.refresh()
            }
        }
        Task { await refresh() }
    }

    /// The playback position in seconds at `date`, interpolated from the last
    /// read while playing.
    func position(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? position + date.timeIntervalSince(positionAt) : position
        return min(max(p, 0), track.duration)
    }

    func refresh() async {
        let raw = await run("/usr/bin/osascript", ["-e", Self.script])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 7, !parts[1].isEmpty else {
            track = nil
            isPlaying = false
            return
        }
        let number = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let next = Track(
            id: parts[1], artist: parts[2], name: parts[3], album: parts[4],
            duration: number(parts[5]) / 1000,
            artworkURL: parts.count > 7 ? URL(string: parts[7]) : nil)
        if track != next { track = next }
        let playing = parts[0] == "playing"
        if isPlaying != playing { isPlaying = playing }
        position = number(parts[6])
        positionAt = Date()
        objectWillChange.send()
    }

    // MARK: Controls

    func playPause() {
        position = position()
        positionAt = Date()
        isPlaying.toggle()
        tell("playpause")
    }

    func next() { tell("next track") }

    func seek(to seconds: Double) {
        position = seconds
        positionAt = Date()
        objectWillChange.send()
        tell("set player position to \(seconds)")
    }

    private func tell(_ command: String) {
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to \(command)"
        Task {
            _ = await run("/usr/bin/osascript", ["-e", script])
            await refresh()
        }
    }
}
