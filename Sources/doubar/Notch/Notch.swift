import AppKit
import Combine
import SwiftUI

// Music control and time-synced lyrics in an overlay that grows out of the
// MacBook notch. It follows Spotify, the same player as the bar's widget.
// Design: https://claude.ai/artifact/LZMrGNVNDMt3FAymphWWRZ ("v1 final").

/// The notch's colours, from [notch.colors]; see `Config.NotchColors`.
/// NotchView observes `Config`, so a change redraws everything reading these.
@MainActor
enum NotchColors {
    private static var c: Config.NotchColors { Config.shared.notch.colors }
    static var text: Color { c.text }
    static var secondary: Color { c.secondary }
    static var track: Color { c.track }
    static var hover: Color { c.hover }
    static var accent: Color { c.accent }
    static var glow: Color { c.glow }
    static var loved: Color { c.loved }
    static var scrim: Color { c.scrim }
    static var icon: Color { c.icon }
}

/// Sizes from the design, for a 14" MacBook Pro whose notch is 200 × 32;
/// widths grow from the real notch, heights from its real height.
struct NotchLayout: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat

    static let lyricsHeight: CGFloat = 178
    static let footerHeight: CGFloat = 62
    static let peekHeight: CGFloat = 24
    /// The collapsed notch's progress border.
    static let border: CGFloat = 1

    static func collapsedWidth(_ base: CGSize) -> CGFloat { base.width + 220 }
    static func expandedWidth(_ base: CGSize) -> CGFloat { base.width + 240 }

    static func of(base: CGSize, expanded: Bool, peek: Bool, lyrics: Bool) -> NotchLayout {
        if expanded {
            let h = base.height + (lyrics ? lyricsHeight : 0) + footerHeight
            return NotchLayout(width: expandedWidth(base), height: h, radius: 28)
        }
        if peek {
            return NotchLayout(width: collapsedWidth(base), height: base.height + peekHeight + 4, radius: 18)
        }
        return NotchLayout(width: collapsedWidth(base), height: base.height + 2, radius: 12)
    }
}

@MainActor
final class Notch: ObservableObject {
    static let shared = Notch()

    /// The hardware notch, set by the panel.
    var base = CGSize(width: 200, height: 32)
    /// The display the notch is on.
    var screenFrame: NSRect = .zero

    /// Something to show: a track playing, or paused for under five minutes.
    @Published private(set) var visible = false
    @Published private(set) var expanded = false
    /// The current track's synced lyrics; nil while loading or when there
    /// are none.
    @Published private(set) var lines: [LyricLine]?
    /// Whether the size makes room for lyrics. Unlike `lines` it keeps its
    /// value while the next track's lyrics load, so the notch doesn't jump.
    @Published private(set) var roomForLyrics = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var liked: Set<String>
    private var banned: Set<String>

    // The suite StatusItems and WorkspaceNames use.
    private let defaults = UserDefaults(suiteName: "com.yaofur.doubar") ?? .standard
    private let likedKey = "notchLiked"
    private let bannedKey = "notchBanned"

    private var trackID: String?
    private var skipped: String?
    private var pausedSince: Date?
    private var pauseTimeout: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []

    private var spotify: Spotify { .shared }
    private var config: Config.Notch { Config.shared.notch }
    /// Back to nothing after this long paused.
    private static let pausedTimeout: TimeInterval = 5 * 60

    private init() {
        liked = Set(defaults.stringArray(forKey: likedKey) ?? [])
        banned = Set(defaults.stringArray(forKey: bannedKey) ?? [])
        spotify.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.playbackChanged() } }
            .store(in: &subscriptions)
        playbackChanged()
    }

    var layout: NotchLayout {
        NotchLayout.of(base: base, expanded: expanded, peek: showsPeek, lyrics: roomForLyrics)
    }

    var showsPeek: Bool { config.lyricPeek && roomForLyrics && !expanded }

    /// The notch body in screen coordinates.
    var frame: NSRect {
        let l = layout
        return NSRect(x: screenFrame.midX - l.width / 2, y: screenFrame.maxY - l.height, width: l.width, height: l.height)
    }

    // MARK: Playback

    private func playbackChanged() {
        let track = spotify.track
        if track?.id != trackID {
            trackID = track?.id
            if let track { trackStarted(track) }
        }
        // Once per track: Spotify reports the old track for a moment after
        // the skip.
        if let track, spotify.isPlaying, banned.contains(track.id), skipped != track.id {
            skipped = track.id
            spotify.next()
        }

        if spotify.isPlaying || track == nil {
            pausedSince = nil
            pauseTimeout?.cancel()
        } else if pausedSince == nil {
            pausedSince = Date()
            let work = DispatchWorkItem { [weak self] in self?.updateVisible() }
            pauseTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausedTimeout, execute: work)
        }
        updateVisible()
    }

    private func updateVisible() {
        let paused = pausedSince.map { Date().timeIntervalSince($0) >= Self.pausedTimeout } ?? false
        let show = spotify.track != nil && !paused
        if show != visible { visible = show }
        if !show { setExpanded(false) }
    }

    private func trackStarted(_ track: Spotify.Track) {
        lines = nil
        artwork = nil
        Task {
            let fetched = await Lyrics.lines(for: track)
            guard trackID == track.id else { return }
            lines = fetched
            roomForLyrics = fetched != nil
        }
        if let url = track.artworkURL {
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url), trackID == track.id else { return }
                artwork = NSImage(data: data)
            }
        }
    }

    // MARK: Actions

    func toggleLiked() {
        guard let id = trackID else { return }
        if liked.contains(id) { liked.remove(id) } else { liked.insert(id) }
        defaults.set(Array(liked), forKey: likedKey)
    }

    /// Skip now and never play this track again.
    func ban() {
        guard let id = trackID else { return }
        banned.insert(id)
        defaults.set(Array(banned), forKey: bannedKey)
        skipped = id
        spotify.next()
    }

    func expand() { setExpanded(true) }

    func collapse() { setExpanded(false) }

    private func setExpanded(_ value: Bool) {
        collapseWork?.cancel()
        collapseWork = nil
        guard expanded != value, visible || !value else { return }
        expanded = value
    }

    // MARK: Pointer

    /// The pointer moved: collapse a while after it leaves. Only a click
    /// expands.
    func pointerMoved(inside: Bool) {
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
        } else if expanded, collapseWork == nil {
            collapseWork = after(config.collapseDelay) { $0.collapseUnlessHeld() }
        }
    }

    /// Not while a button is held: wait for the release.
    private func collapseUnlessHeld() {
        collapseWork = nil
        if NSEvent.pressedMouseButtons != 0 {
            collapseWork = after(0.2) { $0.collapseUnlessHeld() }
        } else if !frame.contains(NSEvent.mouseLocation) {
            collapse()
        }
    }

    private func after(_ delay: Double, _ action: @escaping (Notch) -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            action(self)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }
}
