import Foundation

struct LyricLine: Equatable {
    /// Seconds.
    let start: Double
    /// The next timestamp (a blank line counts), or 7 s after the last line.
    let end: Double
    let text: String
}

extension Array where Element == LyricLine {
    /// The last line that has started by `position`, if it hasn't ended.
    /// Also returns the index of the last started line, ended or not, which
    /// is where the expanded list scrolls to.
    func current(at position: Double) -> (index: Int, line: LyricLine?) {
        let i = lastIndex { $0.start <= position } ?? -1
        guard i >= 0, position <= self[i].end else { return (i, nil) }
        return (i, self[i])
    }
}

/// Time-synced lyrics, fetched once per track and cached by track ID. Only
/// synced (LRC) lyrics count; plain text is ignored.
@MainActor
enum Lyrics {
    /// nil for a track known to have no synced lyrics.
    private static var cache: [String: [LyricLine]?] = [:]
    private static var inFlight: [String: Task<[LyricLine]??, Never>] = [:]

    /// The track's synced lines, or nil when no source has them.
    static func lines(for track: Spotify.Track) async -> [LyricLine]? {
        if let hit = cache[track.id] { return hit }
        let task = inFlight[track.id] ?? Task { await LRCLIB.synced(for: track) }
        inFlight[track.id] = task
        let result = await task.value
        inFlight[track.id] = nil
        // A network failure isn't an answer; leave it uncached to retry on
        // the next track change.
        guard let result else { return nil }
        cache[track.id] = result
        return result
    }
}

/// https://lrclib.net, free and keyless.
private enum LRCLIB {
    struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
    }

    /// `.some(nil)` when LRCLIB has no synced lyrics, nil on a failure.
    static func synced(for track: Spotify.Track) async -> [LyricLine]?? {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        switch await fetch(Record.self, get.url!) {
        case .failure: return nil
        case .success(let record?):
            if let lines = record.syncedLyrics.map(parse), !lines.isEmpty { return .some(lines) }
        case .success(nil): break
        }

        // /get wants an exact album and duration; search is looser.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        switch await fetch([Record].self, search.url!) {
        case .failure: return nil
        case .success(let records):
            let match = (records ?? []).first {
                $0.syncedLyrics != nil && abs(($0.duration ?? 0) - track.duration) <= 3
            }
            let lines = match?.syncedLyrics.map(parse) ?? []
            return .some(lines.isEmpty ? nil : lines)
        }
    }

    struct Failure: Error {}

    /// The decoded body, nil on a 404.
    private static func fetch<T: Decodable>(_: T.Type, _ url: URL) async -> Result<T?, Failure> {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("doubar (https://github.com/kebot/doubar)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .success(nil) }
            guard status == 200 else { return .failure(Failure()) }
            return .success(try JSONDecoder().decode(T.self, from: data))
        } catch {
            log("lyrics: \(url.path) failed: \(error.localizedDescription)")
            return .failure(Failure())
        }
    }

    private static let stamp = try! NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:[.:]\d+)?)\]"#)

    /// Parse LRC: "[mm:ss.xx]text", possibly several stamps per line.
    /// Metadata tags ([ar:…]) don't match and are skipped.
    static func parse(_ lrc: String) -> [LyricLine] {
        var stamped: [(Double, String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = String(raw) as NSString
            var starts: [Double] = []
            while let m = stamp.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) {
                let min = Double(rest.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(rest.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                starts.append(min * 60 + sec)
                rest = rest.substring(from: NSMaxRange(m.range)) as NSString
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            stamped += starts.map { ($0, text) }
        }
        stamped.sort { $0.0 < $1.0 }
        // A blank line ends the one before it; then it's dropped.
        return stamped.indices.compactMap { i in
            let (start, text) = stamped[i]
            guard !text.isEmpty else { return nil }
            let end = i + 1 < stamped.count ? stamped[i + 1].0 : start + 7
            return LyricLine(start: start, end: end, text: text)
        }
    }
}
