import AppKit
import Combine
import SwiftUI

// Music control and time-synced lyrics in an overlay that grows out of the
// MacBook notch, and the same at the top centre of every other display. It
// follows Spotify; all displays share one state.
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
    static var glass: Color { c.glass }
}

/// Where one panel sits: a display, and its camera housing if it has one.
/// A display without one gets the same overlay, top centre, with the
/// current lyric line in the middle of the top row where the camera would be.
struct NotchSite: Equatable {
    var screenFrame: NSRect
    /// nil on a display without a notch.
    var hardware: CGSize?

    var hasNotch: Bool { hardware != nil }
}

/// Sizes from the design, for a 14" MacBook Pro whose notch is 200 × 32;
/// widths grow from the real notch, heights from its real height. Without
/// a notch, the middle of the top row is the lyric line's (300 pt) or
/// nothing.
struct NotchLayout: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    /// The top row's height.
    var row: CGFloat
    /// The middle of the top row, between the wings: the camera, or the
    /// lyric line.
    var center: CGFloat

    static let lyricsHeight: CGFloat = 178
    static let footerHeight: CGFloat = 62
    static let peekHeight: CGFloat = 24
    /// The collapsed notch's progress border.
    static let border: CGFloat = 1
    /// Without a notch: the top row, and the lyric line in its middle.
    static let islandRow: CGFloat = 32
    static let islandLyricWidth: CGFloat = 300

    /// The middle of the top row while expanded, which also sets the
    /// expanded width.
    private static func expandedCenter(_ site: NotchSite) -> CGFloat { site.hardware?.width ?? islandLyricWidth }
    static func row(_ site: NotchSite) -> CGFloat { site.hardware?.height ?? islandRow }
    static func expandedWidth(_ site: NotchSite) -> CGFloat { expandedCenter(site) + 240 }
    /// The tallest the body gets, for sizing its panel.
    static func maxHeight(_ site: NotchSite) -> CGFloat { row(site) + lyricsHeight + footerHeight }

    /// - `lyricLine`: the collapsed lyric line is on (below the camera with
    ///   a notch, in the middle of the top row without).
    static func of(site: NotchSite, expanded: Bool, paused: Bool, lyricLine: Bool, lyrics: Bool) -> NotchLayout {
        let row = row(site)
        if expanded {
            let h = row + (lyrics ? lyricsHeight : 0) + footerHeight
            let center = expandedCenter(site)
            return NotchLayout(width: center + 240, height: h, radius: 28, row: row, center: center)
        }
        // Paused: the cover alone, beside the camera or as a small tab.
        if paused {
            let center = site.hardware?.width ?? 0
            return NotchLayout(width: center + (site.hasNotch ? 80 : 40), height: row, radius: 12, row: row, center: center)
        }
        guard let base = site.hardware else {
            let center = lyricLine ? islandLyricWidth : 0
            return NotchLayout(width: center + 220, height: row + 2, radius: 12, row: row, center: center)
        }
        if lyricLine {
            return NotchLayout(
                width: base.width + 220, height: row + peekHeight + 4, radius: 18, row: row, center: base.width)
        }
        return NotchLayout(width: base.width + 220, height: row + 2, radius: 12, row: row, center: base.width)
    }
}

@MainActor
final class Notch: ObservableObject {
    static let shared = Notch()

    /// Every panel's place, by display; set by AppDelegate.
    var sites: [CGDirectDisplayID: NotchSite] = [:]

    /// Something to show: a track playing, or paused for under five minutes.
    @Published private(set) var visible = false
    @Published private(set) var expanded = false
    @Published private(set) var playing = false
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

    func layout(for site: NotchSite) -> NotchLayout {
        NotchLayout.of(
            site: site, expanded: expanded, paused: compact, lyricLine: showsLyricLine(on: site),
            lyrics: roomForLyrics)
    }

    /// Paused and collapsed: just the cover, to play.
    var compact: Bool { !playing && !expanded }

    /// Whether the collapsed lyric line is chosen on this kind of display:
    /// `lyric-peek` with a notch, `center-lyric` without.
    func lyricLineOn(_ site: NotchSite) -> Bool { site.hasNotch ? config.lyricPeek : config.centerLyric }

    func showsLyricLine(on site: NotchSite) -> Bool { lyricLineOn(site) && roomForLyrics && !expanded && playing }

    /// The body in screen coordinates.
    func frame(for site: NotchSite) -> NSRect {
        let l = layout(for: site)
        let f = site.screenFrame
        return NSRect(x: f.midX - l.width / 2, y: f.maxY - l.height, width: l.width, height: l.height)
    }

    /// Whether `point` is on any display's body.
    func contains(_ point: NSPoint) -> Bool { sites.values.contains { frame(for: $0).contains(point) } }

    /// Whether the pointer is over any display's body, or a little beyond
    /// it, so drifting past its edge doesn't start the collapse.
    private var pointerNear: Bool {
        let p = NSEvent.mouseLocation
        return sites.values.contains { frame(for: $0).insetBy(dx: -16, dy: -16).contains(p) }
    }

    // MARK: Playback

    private func playbackChanged() {
        let track = spotify.track
        if playing != spotify.isPlaying { playing = spotify.isPlaying }
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

    /// A click on the body steps through expanded → collapsed without
    /// lyrics → collapsed with the lyric line → expanded. The lyric-line
    /// step is skipped when there's no line to show (no synced lyrics, or
    /// paused). Which collapsed look is used is saved in config.toml per
    /// kind of display (`lyric-peek`, `center-lyric`), and is also where
    /// pointer-out and Esc return to.
    func cycle(on site: NotchSite) {
        if expanded {
            setLyricLine(false, on: site)
            collapse()
        } else if !lyricLineOn(site), roomForLyrics, playing {
            setLyricLine(true, on: site)
        } else {
            expand()
        }
    }

    private func setLyricLine(_ on: Bool, on site: NotchSite) {
        guard lyricLineOn(site) != on else { return }
        Config.shared.set("notch", site.hasNotch ? "lyric-peek" : "center-lyric", .bool(on))
    }

    func collapse() { setExpanded(false) }

    private func setExpanded(_ value: Bool) {
        collapseWork?.cancel()
        collapseWork = nil
        guard expanded != value, visible || !value else { return }
        expanded = value
    }

    // MARK: Pointer

    /// The pointer moved: collapse once it has been away from every body
    /// for the collapse delay; coming back cancels that. Only a click
    /// expands.
    func pointerMoved() {
        if pointerNear {
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
        } else if !pointerNear {
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
