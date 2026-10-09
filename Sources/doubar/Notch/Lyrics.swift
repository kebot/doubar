import Foundation

// Time-synced lyrics from several public providers, after bragi's
// server/lyrics.ts (https://github.com/kebot/bragi). Every provider searches
// for the song; the candidates from all of them are scored together on how
// well they match (title, artist and, most of all, length, since a top
// result is often a live take or a cover), and the best few are loaded until
// one has synced lines. Plain-text lyrics never count.
//
//   netease  NetEase Cloud Music (music.163.com)
//   kugou    Kugou (kugou.com); its song search is plain http
//   lrclib   LRCLIB (lrclib.net)
//   lrcx     the public LrcApi instance (api.lrc.cx): Apple Music and its own
//            catalogue; https://github.com/HisAtri/LrcApi
//
// The order above is the preference that breaks ties.

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

/// Synced lyrics fetched once per track and cached by track ID; a miss is
/// asked again after 30 minutes.
@MainActor
enum Lyrics {
    private struct Entry {
        let lines: [LyricLine]?
        let at: Date
    }

    private static var cache: [String: Entry] = [:]
    private static var inFlight: [String: Task<[LyricLine]??, Never>] = [:]
    private static let missLifetime: TimeInterval = 30 * 60

    /// The track's synced lines, or nil when no provider has them.
    static func lines(for track: Spotify.Track) async -> [LyricLine]? {
        if let hit = cache[track.id], hit.lines != nil || Date().timeIntervalSince(hit.at) < missLifetime {
            return hit.lines
        }
        let query = LyricsQuery(title: track.name, artist: track.artist, album: track.album, duration: track.duration)
        let task = inFlight[track.id] ?? Task { await LyricsSearch.synced(for: query) }
        inFlight[track.id] = task
        let result = await task.value
        inFlight[track.id] = nil
        // Every provider failing (offline, say) isn't an answer; leave it
        // uncached to retry on the next track change.
        guard let result else { return nil }
        cache[track.id] = Entry(lines: result, at: Date())
        return result
    }
}

struct LyricsQuery {
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
}

private struct Candidate {
    let source: String
    let title: String
    let artist: String
    let album: String
    /// Seconds.
    let duration: Double?
    /// The LRC text, or nil when there is none.
    let load: () async -> String?
}

private typealias Provider = (LyricsQuery) async throws -> [Candidate]

private enum LyricsSearch {
    static let providers: [(String, Provider)] = [
        ("netease", netease), ("kugou", kugou), ("lrclib", lrclib), ("lrcx", lrcx),
    ]

    /// `.some(nil)` when nothing synced was found, nil when every search
    /// failed.
    static func synced(for q: LyricsQuery) async -> [LyricLine]?? {
        // A romanized artist ("Jay Chou" for 周杰倫) isn't found next to a
        // Chinese title; then also search by title alone and let the length
        // pick.
        var queries = [q]
        if !q.title.allSatisfy(\.isASCII), !q.artist.isEmpty, q.artist.allSatisfy(\.isASCII) {
            var bare = q
            bare.artist = ""
            queries.append(bare)
        }

        let lists: [(Int, [Candidate]?)] = await withTaskGroup(of: (Int, [Candidate]?).self) { group in
            for (p, (name, provider)) in providers.enumerated() {
                group.addTask {
                    var found: [Candidate] = []
                    var failed = 0
                    for query in queries {
                        do { found += try await provider(query) } catch {
                            log("lyrics: \(name) search failed: \(error.localizedDescription)")
                            failed += 1
                        }
                    }
                    return (p, failed == queries.count ? nil : found)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        guard lists.contains(where: { $0.1 != nil }) else { return nil }

        var ranked: [(candidate: Candidate, score: Double)] = []
        for (p, list) in lists {
            var seen = Set<String>()
            for (i, c) in (list ?? []).enumerated() {
                guard seen.insert([c.title, c.artist, c.album, "\(c.duration ?? 0)"].joined(separator: "\0")).inserted,
                      let s = Match.score(q, c) else { continue }
                // Provider preference, then the provider's own order, break ties.
                ranked.append((c, s - Double(p) * 0.01 - Double(i) * 0.001))
            }
        }
        ranked.sort { $0.score > $1.score }

        for (c, _) in ranked.prefix(4) {
            guard let lrc = await c.load() else { continue }
            let lines = LRC.parse(lrc)
            if !lines.isEmpty {
                log("lyrics: \(q.artist) – \(q.title) from \(c.source) (\(c.artist) – \(c.title))")
                return .some(lines)
            }
        }
        return .some(nil)
    }

    // MARK: Providers

    private static func keywords(_ q: LyricsQuery) -> String {
        let title = Match.baseTitle(q.title)
        return [title.isEmpty ? q.title : title, q.artist].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let neteaseHeaders = ["Origin": "https://music.163.com", "Referer": "https://music.163.com/"]

    private static func netease(_ q: LyricsQuery) async throws -> [Candidate] {
        let data = try await HTTP.json("https://music.163.com/api/cloudsearch/pc",
                                       ["type": "1", "offset": "0", "limit": "10", "s": keywords(q)], headers: neteaseHeaders)
        let songs = ((data as? [String: Any])?["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        return songs.compactMap { s in
            guard let id = s["id"].map({ "\($0)" }) else { return nil }
            return Candidate(
                source: "netease",
                title: s["name"] as? String ?? "",
                artist: (s["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / "),
                album: (s["al"] as? [String: Any])?["name"] as? String ?? "",
                duration: (s["dt"] as? Double).map { $0 / 1000 },
                load: {
                    let l = try? await HTTP.json("https://music.163.com/api/song/lyric",
                                                 ["lv": "-1", "tv": "-1", "id": id], headers: neteaseHeaders)
                    return ((l as? [String: Any])?["lrc"] as? [String: Any])?["lyric"] as? String
                })
        }
    }

    private static func kugou(_ q: LyricsQuery) async throws -> [Candidate] {
        // No https for this one; the bundle's Info.plist lets it through ATS.
        let data = try await HTTP.json("http://mobilecdn.kugou.com/api/v3/search/song",
                                       ["format": "json", "page": "1", "pagesize": "10", "showtype": "1", "keyword": keywords(q)])
        let songs = ((data as? [String: Any])?["data"] as? [String: Any])?["info"] as? [[String: Any]] ?? []
        return songs.compactMap { s in
            guard let hash = s["hash"] as? String else { return nil }
            let duration = s["duration"] as? Double
            return Candidate(
                source: "kugou",
                title: s["songname"] as? String ?? "",
                artist: s["singername"] as? String ?? "",
                album: s["album_name"] as? String ?? "",
                duration: duration,
                load: {
                    let found = try? await HTTP.json("https://krcs.kugou.com/search", [
                        "ver": "1", "man": "yes", "client": "mobi", "keyword": "", "album_audio_id": "",
                        "duration": duration.map { String(Int($0 * 1000)) } ?? "", "hash": hash,
                    ])
                    guard let best = ((found as? [String: Any])?["candidates"] as? [[String: Any]])?.first,
                          let id = best["id"].map({ "\($0)" }), let key = best["accesskey"] as? String
                    else { return nil }
                    let d = try? await HTTP.json("https://lyrics.kugou.com/download", [
                        "ver": "1", "client": "pc", "fmt": "lrc", "charset": "utf8", "id": id, "accesskey": key,
                    ])
                    return ((d as? [String: Any])?["content"] as? String)
                        .flatMap { Data(base64Encoded: $0) }
                        .flatMap { String(data: $0, encoding: .utf8) }
                })
        }
    }

    private static func lrclib(_ q: LyricsQuery) async throws -> [Candidate] {
        var params = ["track_name": q.title]
        if !q.artist.isEmpty { params["artist_name"] = q.artist }
        // LRCLIB asks clients to name themselves.
        let data = try await HTTP.json("https://lrclib.net/api/search", params,
                                       headers: ["User-Agent": "doubar (https://github.com/kebot/doubar)"])
        return (data as? [[String: Any]] ?? []).compactMap { r in
            // Synced lyrics come with the search; skip records without them
            // so they don't take a place among the few loaded.
            guard let lrc = r["syncedLyrics"] as? String else { return nil }
            return Candidate(
                source: "lrclib",
                title: r["trackName"] as? String ?? "",
                artist: r["artistName"] as? String ?? "",
                album: r["albumName"] as? String ?? "",
                duration: r["duration"] as? Double,
                load: { lrc })
        }
    }

    private static func lrcx(_ q: LyricsQuery) async throws -> [Candidate] {
        let title = Match.baseTitle(q.title)
        let data = try await HTTP.json("https://api.lrc.cx/jsonapi",
                                       ["title": title.isEmpty ? q.title : title, "artist": q.artist])
        return (data as? [[String: Any]] ?? []).compactMap { x in
            // Plain lyrics come back too, unmarked; only keep timed ones.
            guard let lrc = (x["lrc"] as? String) ?? (x["lyrics"] as? String), !LRC.parse(lrc).isEmpty else { return nil }
            return Candidate(
                source: "lrcx",
                title: x["title"] as? String ?? "",
                artist: x["artist"] as? String ?? "",
                album: x["album"] as? String ?? "",
                duration: (x["duration"] as? Double) ?? (x["duration"] as? String).flatMap(Double.init),
                load: { lrc })
        }
    }
}

private enum HTTP {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let browser =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

    static func json(_ base: String, _ params: [String: String], headers: [String: String] = [:]) async throws -> Any {
        var url = URLComponents(string: base)!
        url.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!, timeoutInterval: 8)
        request.setValue(browser, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure(errorDescription: "\(url.host ?? base): HTTP \(status)") }
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }
}

// MARK: Matching

private enum Match {
    /// nil when the candidate is clearly another song.
    static func score(_ q: LyricsQuery, _ c: Candidate) -> Double? {
        let title = max(similarity(q.title, c.title), similarity(baseTitle(q.title), baseTitle(c.title)))
        guard title >= 0.5 else { return nil }
        let artist = artistSimilarity(q.artist, c.artist)
        var s = title * 3 + artist * 1.5
        if !q.album.isEmpty, !c.album.isEmpty { s += similarity(q.album, c.album) * 0.5 }
        if let d = c.duration, d > 0 {
            let diff = abs(q.duration - d)
            // A live take, an edit or a cover is usually more than 20 s off;
            // with another artist name (a romanized one, or another song of
            // the same title) only the same recording will do.
            if diff > (artist < 0.5 ? 3 : 20) { return nil }
            s += diff <= 3 ? 2 : diff <= 8 ? 1 : 0
        } else {
            // Nothing to check the length against: only with a matching
            // artist, and below candidates whose length does match.
            if artist < 0.5 { return nil }
            s -= 1
        }
        return s
    }

    /// Without "(Live)", "（2009）", "- Remastered 2011", "-Studio Recording"
    /// and the like.
    static func baseTitle(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*[(（\[【].*?[)）\]】]\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*-\s*[A-Za-z][^-]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ s: String) -> [Character] {
        let scalars = s.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars.filter { u in
            switch u.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control,
                 .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation,
                 .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
                false
            default:
                true
            }
        }
        return Array(String(String.UnicodeScalarView(scalars)))
    }

    /// Dice coefficient over character bigrams, with start and end markers so
    /// order counts in short (two-character Chinese) titles.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = normalize(a), b = normalize(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        func grams(_ s: [Character]) -> [String: Int] {
            let s = ["\u{2}"] + s + ["\u{3}"]
            var out: [String: Int] = [:]
            for i in 0..<(s.count - 1) { out[String([s[i], s[i + 1]]), default: 0] += 1 }
            return out
        }
        let ga = grams(a), gb = grams(b)
        let common = ga.reduce(0) { $0 + min($1.value, gb[$1.key] ?? 0) }
        return Double(2 * common) / Double(a.count + 1 + b.count + 1)
    }

    static func artistSimilarity(_ a: String, _ b: String) -> Double {
        func split(_ s: String) -> [String] {
            s.replacingOccurrences(of: #"(?i)\s*(?:[,/&、;]|\bfeat\.?|\bft\.?)\s*"#, with: "\0", options: .regularExpression)
                .split(separator: "\0").map(String.init)
        }
        var best = similarity(a, b)
        for x in split(a) { for y in split(b) { best = max(best, similarity(x, y)) } }
        return best
    }
}

// MARK: LRC

private enum LRC {
    private static let stamp = try! NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:[.:]\d+)?)\]"#)

    /// Parse LRC: "[mm:ss.xx]text", possibly several stamps per line. Lines
    /// without a stamp (tags like [ar:…] or [hash:…], NetEase's JSON credit
    /// lines, section headers like [Verse]) are skipped, so plain-text lyrics
    /// parse to nothing.
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
            let text = rest.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}")))
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
