import SwiftUI

/// A colour as config.toml writes it:
///
///   "#261d35", "#261d35cc"           a literal colour, alpha optional
///   "accent"                         a palette key from theme.toml
///   "foreground/12%"                 any colour at 12% of its opacity
///   "mix(background, accent, 20%)"   a blend, as dotter's `mix` helper
///
/// Palette values are themselves expressions, usually plain hex.
struct RGBA: Equatable {
    var r, g, b, a: Double

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }

    init?(hex: String) {
        var s = Substring(hex)
        guard s.first == "#" else { return nil }
        s = s.dropFirst()
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(
            r: Double((rgb >> 16) & 0xFF) / 255, g: Double((rgb >> 8) & 0xFF) / 255, b: Double(rgb & 0xFF) / 255,
            a: s.count == 8 ? Double(v & 0xFF) / 255 : 1)
    }

    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: a + (other.a - a) * t)
    }

    /// Resolve `expression` against `palette`, or nil when it doesn't parse
    /// or names a key the palette lacks.
    static func resolve(_ expression: String, palette: [String: String], depth: Int = 0) -> RGBA? {
        guard depth < 8 else { return nil }
        let e = expression.trimmingCharacters(in: .whitespaces)
        if e.hasPrefix("#") { return RGBA(hex: e) }
        if e.hasPrefix("mix("), e.hasSuffix(")") {
            let args = splitArgs(e.dropFirst(4).dropLast())
            guard args.count == 3, let a = resolve(args[0], palette: palette, depth: depth + 1),
                  let b = resolve(args[1], palette: palette, depth: depth + 1), let t = fraction(args[2])
            else { return nil }
            return a.mixed(with: b, t)
        }
        // A slash outside mix(...) sets the opacity.
        if let slash = e.lastIndex(of: "/") {
            guard var c = resolve(String(e[..<slash]), palette: palette, depth: depth + 1),
                  let t = fraction(String(e[e.index(after: slash)...]))
            else { return nil }
            c.a *= t
            return c
        }
        return palette[e].flatMap { resolve($0, palette: palette, depth: depth + 1) }
    }

    /// "12%" or "0.12".
    private static func fraction(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("%") { return Double(t.dropLast()).map { $0 / 100 } }
        return Double(t)
    }

    /// Split on commas that aren't inside parentheses.
    private static func splitArgs(_ s: Substring) -> [String] {
        var out: [String] = [], depth = 0, current = ""
        for c in s {
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if c == ",", depth == 0 {
                out.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        out.append(current)
        return out
    }
}
