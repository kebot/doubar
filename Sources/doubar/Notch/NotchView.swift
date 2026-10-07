import AppKit
import SwiftUI

/// The notch body, top-centre in its panel. Collapsed: the cover and title
/// in the left wing, 红心 / 垃圾桶 / 下一首 in the right, progress along the
/// bottom border, optionally the current lyric below the camera. Expanded:
/// the same top row, then five lyric lines, then title · artist and a
/// progress bar.
struct NotchView: View {
    @ObservedObject private var notch = Notch.shared
    @ObservedObject private var spotify = Spotify.shared
    // For the colours and lyric-peek.
    @ObservedObject private var config = Config.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // ≥ 10 Hz for the karaoke fill; 30 for the level bars.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spotify.isPlaying)) { context in
            if let track = spotify.track {
                notchBody(track, position: spotify.position(at: context.date), now: context.date)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.25),
            value: notch.layout)
    }

    private func notchBody(_ track: Spotify.Track, position: Double, now: Date) -> some View {
        let layout = notch.layout
        let progress = track.duration > 0 ? position / track.duration : 0
        return ZStack(alignment: .top) {
            if !notch.expanded {
                glow(layout, progress: progress)
            }
            ZStack(alignment: .top) {
                Color.black
                VStack(spacing: 0) {
                    topRow(track, layout: layout, position: position, now: now)
                    if notch.showsPeek {
                        peek(position: position, width: layout.width)
                            .transition(.opacity)
                    }
                    if notch.expanded {
                        expanded(track, position: position, progress: progress)
                            .transition(.opacity)
                    }
                }
                if !notch.expanded {
                    progressBorder(layout, progress: progress)
                }
            }
            .frame(width: layout.width, height: layout.height, alignment: .top)
            .clipShape(NotchShape(radius: layout.radius))
            .contentShape(NotchShape(radius: layout.radius))
            // Controls take their own clicks; the rest of the body expands.
            .onTapGesture { notch.expand() }
        }
    }

    // MARK: Top row

    private func topRow(_ track: Spotify.Track, layout: NotchLayout, position: Double, now: Date) -> some View {
        let wing = (layout.width - notch.base.width) / 2
        let liked = notch.liked.contains(track.id)
        return HStack(spacing: 0) {
            CoverButton(
                artwork: notch.artwork, playing: spotify.isPlaying,
                // Turning with the playback position stops it while paused.
                angle: reduceMotion ? 0 : position / 14 * 360,
                now: now, still: reduceMotion)
            Text(track.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchColors.text)
                .lineLimit(1)
                .frame(maxWidth: max(0, wing - 41), alignment: .leading)
                .padding(.leading, 4)
            Spacer(minLength: 0)
            HStack(spacing: 1) {
                IconButton(symbol: liked ? "heart.fill" : "heart", tint: liked ? NotchColors.loved : nil) {
                    notch.toggleLiked()
                }
                IconButton(symbol: "trash") { notch.ban() }
                IconButton(symbol: "forward.end.fill") { spotify.next() }
            }
        }
        .padding(.horizontal, 9)
        .frame(width: layout.width, height: notch.base.height)
    }

    // MARK: Collapsed

    private func peek(position: Double, width: CGFloat) -> some View {
        let current = notch.lines?.current(at: position).line
        return Group {
            if let current {
                KaraokeText(text: current.text, progress: current.progress(at: position), rest: 0.4)
            } else {
                Text("…").foregroundStyle(NotchColors.text.opacity(0.5))
            }
        }
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 22)
        .frame(width: width, height: NotchLayout.peekHeight)
    }

    /// The 1 pt bottom border: unplayed in `track`, played in the accent.
    private func progressBorder(_ layout: NotchLayout, progress: Double) -> some View {
        let border = BottomBorder(radius: layout.radius)
        return ZStack {
            border.fill(NotchColors.track, style: FillStyle(eoFill: true))
            border.fill(NotchColors.accent, style: FillStyle(eoFill: true))
                .mask(alignment: .leading) {
                    Rectangle().frame(width: layout.width * progress)
                }
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }

    /// Light from the played part of the border, spilling below the notch.
    /// It sits behind the body, which hides all of it but the spill.
    private func glow(_ layout: NotchLayout, progress: Double) -> some View {
        Rectangle()
            .fill(NotchColors.accent)
            .frame(width: max(0, layout.width * progress - layout.radius), height: NotchLayout.border)
            .shadow(color: NotchColors.glow, radius: 4, x: 0, y: 2)
            .padding(.leading, layout.radius)
            .padding(.top, layout.height - NotchLayout.border)
            .frame(width: layout.width, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    // MARK: Expanded

    private func expanded(_ track: Spotify.Track, position: Double, progress: Double) -> some View {
        VStack(spacing: 0) {
            if notch.roomForLyrics {
                lyrics(position: position)
                    .frame(height: NotchLayout.lyricsHeight, alignment: .top)
                    .clipped()
            }
            footer(track, position: position, progress: progress)
        }
        // At its final width throughout, so nothing reflows while the notch
        // grows; the body clips it.
        .frame(width: NotchLayout.expandedWidth(notch.base))
    }

    /// Five lines from the one just sung; click one to seek to it.
    private func lyrics(position: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lines = notch.lines {
                let (index, current) = lines.current(at: position)
                let from = Swift.max(0, index - 1)
                ForEach(from..<Swift.min(lines.count, from + 5), id: \.self) { i in
                    Button { spotify.seek(to: lines[i].start) } label: {
                        lyricLine(lines[i], offset: i - index, current: current, position: position)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lyricLine(_ line: LyricLine, offset: Int, current: LyricLine?, position: Double) -> some View {
        if offset == 0, current != nil {
            KaraokeText(text: line.text, progress: line.progress(at: position), rest: 0.32)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
        } else {
            let opacity: Double = switch offset {
            case ...0: 0.3
            case 1: 0.62
            case 2: 0.42
            default: 0.26
            }
            Text(line.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NotchColors.text.opacity(opacity))
                .lineLimit(1)
        }
    }

    private func footer(_ track: Spotify.Track, position: Double, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(track.name).fontWeight(.semibold).foregroundStyle(NotchColors.text)
                + Text("  ·  \(track.artist)").foregroundStyle(NotchColors.secondary))
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(height: 18)
            HStack(spacing: 8) {
                Text(Self.time(position))
                    .frame(width: 30, alignment: .leading)
                Capsule()
                    .fill(NotchColors.track)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(NotchColors.accent).frame(width: geo.size.width * progress)
                        }
                    }
                Text("-" + Self.time(track.duration - position))
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 10.5).monospacedDigit())
            .foregroundStyle(NotchColors.secondary)
            .frame(height: 14)
        }
        .padding(EdgeInsets(top: 8, leading: 22, bottom: 14, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// m:ss
    private static func time(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension LyricLine {
    func progress(at position: Double) -> Double {
        min(max((position - start) / max(end - start, 0.1), 0), 1)
    }
}

// MARK: Pieces

/// Flush with the top of the screen; only the bottom corners are rounded.
struct NotchShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height, rect.width / 2)
        return UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .circular)
            .path(in: rect)
    }
}

/// A 1 pt bottom border following the corner curves, like CSS's
/// `border-bottom` on a rounded box: fill it even-odd.
private struct BottomBorder: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = NotchShape(radius: radius).path(in: rect)
        path.addPath(NotchShape(radius: radius).path(in: CGRect(
            x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - NotchLayout.border)))
        return path
    }
}

/// Text filled left to right up to `progress`, the rest at `rest` opacity.
private struct KaraokeText: View {
    let text: String
    let progress: Double
    let rest: Double

    var body: some View {
        Text(text).foregroundStyle(LinearGradient(
            stops: [
                .init(color: NotchColors.text, location: progress),
                .init(color: NotchColors.text.opacity(rest), location: progress),
            ],
            startPoint: .leading, endPoint: .trailing))
    }
}

/// 26 pt hit box, 15 pt icon.
private struct IconButton: View {
    let symbol: String
    var tint: Color?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(tint ?? (hovered ? NotchColors.text : NotchColors.secondary))
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovered ? NotchColors.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// The artwork as a 22 pt disc that plays and pauses. Its icons are always
/// white: they sit on the artwork, not on the notch.
private struct CoverButton: View {
    let artwork: NSImage?
    let playing: Bool
    let angle: Double
    let now: Date
    let still: Bool
    @State private var hovered = false

    var body: some View {
        Button { Spotify.shared.playPause() } label: {
            ZStack {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        Color(white: 0.07)
                    }
                }
                .rotationEffect(.degrees(angle))
                // The configured scrim, darker under the pointer (38% → 55%).
                Circle().fill(NotchColors.scrim)
                Circle().fill(.black.opacity(hovered ? 0.27 : 0))
                if playing, !hovered {
                    LevelBars(now: now, still: still)
                } else {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(NotchColors.icon)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Three white bars bouncing between 2 and 9 pt, each at its own pace.
private struct LevelBars: View {
    let now: Date
    let still: Bool

    private static let paces: [(period: Double, offset: Double)] = [(0.9, 0), (0.62, 0.3), (0.78, 0.5)]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(NotchColors.icon).frame(width: 2, height: still ? 9 : height(i))
            }
        }
        .frame(height: 9)
    }

    /// Eased back and forth, like CSS's `ease-in-out infinite alternate`.
    private func height(_ i: Int) -> CGFloat {
        let pace = Self.paces[i]
        let phase = (now.timeIntervalSinceReferenceDate + pace.offset) / pace.period
        var f = phase.truncatingRemainder(dividingBy: 1)
        if Int(phase) % 2 == 1 { f = 1 - f }
        return 2 + 7 * f * f * (3 - 2 * f)
    }
}
