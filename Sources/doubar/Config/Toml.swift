import Foundation

// A small TOML reader that also remembers where each value sits in the
// text, so doubar can change one value (or regenerate one table) and leave
// the rest of the file, comments included, as the user wrote it.
//
// It covers what doubar's files use: tables, dotted and quoted keys, basic
// and literal strings, integers, floats, booleans, arrays (across lines,
// with comments and trailing commas) and inline tables. Multi-line strings,
// dates and arrays of tables are rejected with an error.

indirect enum TomlValue: Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TomlValue])
    case table([String: TomlValue])

    var string: String? { if case .string(let s) = self { s } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    var array: [TomlValue]? { if case .array(let a) = self { a } else { nil } }
    var table: [String: TomlValue]? { if case .table(let t) = self { t } else { nil } }

    /// An integer or a float.
    var number: Double? {
        switch self {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    subscript(key: String) -> TomlValue? { table?[key] }

    /// The value as TOML, on one line.
    var toml: String {
        switch self {
        case .string(let s): Self.quote(s)
        case .int(let i): String(i)
        case .double(let d): d.rounded() == d && abs(d) < 1e15 ? String(format: "%.1f", d) : String(d)
        case .bool(let b): b ? "true" : "false"
        case .array(let a): "[" + a.map(\.toml).joined(separator: ", ") + "]"
        case .table(let t):
            t.isEmpty ? "{}" : "{ " + t.keys.sorted().map { "\(Self.key($0)) = \(t[$0]!.toml)" }.joined(separator: ", ") + " }"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case _ where c.value < 0x20 || c.value == 0x7F: out += String(format: "\\u%04X", c.value)
            default: out.unicodeScalars.append(c)
            }
        }
        return out + "\""
    }

    /// A key as TOML: bare when it can be, quoted otherwise.
    static func key(_ k: String) -> String {
        !k.isEmpty && k.unicodeScalars.allSatisfy(isBare) ? k : quote(k)
    }

    static func isBare(_ c: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_" || c == "-"
    }
}

struct TomlError: Error, CustomStringConvertible {
    let line: Int
    let message: String
    var description: String { "line \(line): \(message)" }
}

struct TomlDocument {
    let text: String
    private(set) var root: [String: TomlValue] = [:]

    private let scalars: [Unicode.Scalar]
    /// Each key's value, by its full path, as a range of scalar offsets.
    private var values: [[String]: Range<Int>] = [:]
    /// Each key's whole line, newline included.
    private var keyLines: [[String]: Range<Int>] = [:]
    /// Each table's header line, and where its last key line ends.
    private var tables: [[String]: (header: Range<Int>, end: Int)] = [:]

    init(_ text: String) throws {
        self.text = text
        scalars = Array(text.unicodeScalars)
        var p = Parser(s: scalars)
        var current: [String] = []
        var defined: Set<[String]> = []
        tables[[]] = (0..<0, 0)

        while p.i < scalars.count {
            let lineStart = p.i
            p.skipSpaces()
            guard let c = p.peek else { break }
            if c == "#" || c == "\n" || c == "\r" {
                try p.endOfLine()
                continue
            }
            if c == "[" {
                if p.peek(1) == "[" { throw p.error("arrays of tables ([[...]]) aren't supported") }
                p.i += 1
                let path = try p.key()
                guard p.consume("]") else { throw p.error("expected ] after the table name") }
                try p.endOfLine()
                guard defined.insert(path).inserted else {
                    throw p.error("table [\(path.joined(separator: "."))] is defined twice")
                }
                try Self.ensureTable(path[...], in: &root, line: p.line)
                current = path
                tables[path] = (lineStart..<p.i, p.i)
                continue
            }
            let key = try p.key()
            p.skipSpaces()
            guard p.consume("=") else { throw p.error("expected = after \(key.joined(separator: "."))") }
            p.skipSpaces()
            let valueStart = p.i
            let value = try p.value()
            let valueEnd = p.i
            try p.endOfLine()
            let path = current + key
            try Self.insert(value, at: path[...], into: &root, line: p.line)
            values[path] = valueStart..<valueEnd
            keyLines[path] = lineStart..<p.i
            tables[current]?.end = p.i
        }
    }

    subscript(key: String) -> TomlValue? { root[key] }

    // MARK: Edits. Each returns the new text; the document itself is unchanged.

    /// Set `key` in `table` to `value`, or remove it when `value` is nil.
    /// An existing value is replaced in place, keeping the rest of its line
    /// (a trailing comment, say). A new key goes after the table's last key;
    /// a new table goes at the end of the file.
    func setting(_ value: TomlValue?, at table: [String], _ key: String) -> String {
        let path = table + [key]
        if let range = values[path] {
            guard let value else { return replacing(keyLines[path]!, with: "") }
            return replacing(range, with: value.toml)
        }
        guard let value else { return text }
        let line = "\(TomlValue.key(key)) = \(value.toml)\n"
        guard let t = tables[table] else { return appendingTable(table, body: line) }
        let needsBreak = t.end > 0 && scalars[t.end - 1] != "\n"
        return replacing(t.end..<t.end, with: (needsBreak ? "\n" : "") + line)
    }

    /// Replace `table`, from its header through its last key, with `body`.
    /// Comments between its keys are lost; those before the header and
    /// after the last key stay. A missing table is added at the end, after
    /// `comment` if given.
    func replacingTable(_ table: [String], with body: String, comment: String? = nil) -> String {
        guard let t = tables[table], !table.isEmpty else { return appendingTable(table, body: body, comment: comment) }
        return replacing(t.header.lowerBound..<t.end, with: "[\(Self.path(table))]\n" + body)
    }

    private func appendingTable(_ table: [String], body: String, comment: String? = nil) -> String {
        var out = text
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty && !out.hasSuffix("\n\n") { out += "\n" }
        if let comment { out += comment.split(separator: "\n").map { "# \($0)\n" }.joined() }
        return out + "[\(Self.path(table))]\n" + body
    }

    private func replacing(_ range: Range<Int>, with new: String) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[..<range.lowerBound])
        out.append(contentsOf: new.unicodeScalars)
        out.append(contentsOf: scalars[range.upperBound...])
        return String(out)
    }

    private static func path(_ table: [String]) -> String {
        table.map(TomlValue.key).joined(separator: ".")
    }

    // MARK: Building the tree

    private static func ensureTable(_ path: ArraySlice<String>, in dict: inout [String: TomlValue], line: Int) throws {
        guard let first = path.first else { return }
        var child: [String: TomlValue]
        switch dict[first] {
        case nil: child = [:]
        case .table(let t): child = t
        default: throw TomlError(line: line, message: "\(first) is already a value, not a table")
        }
        try ensureTable(path.dropFirst(), in: &child, line: line)
        dict[first] = .table(child)
    }

    fileprivate static func insert(
        _ value: TomlValue, at path: ArraySlice<String>, into dict: inout [String: TomlValue], line: Int
    ) throws {
        let first = path.first!
        if path.count == 1 {
            guard dict[first] == nil else { throw TomlError(line: line, message: "\(first) is set twice") }
            dict[first] = value
            return
        }
        var child: [String: TomlValue]
        switch dict[first] {
        case nil: child = [:]
        case .table(let t): child = t
        default: throw TomlError(line: line, message: "\(first) is already a value, not a table")
        }
        try insert(value, at: path.dropFirst(), into: &child, line: line)
        dict[first] = .table(child)
    }
}

private struct Parser {
    let s: [Unicode.Scalar]
    var i = 0
    var line = 1

    var peek: Unicode.Scalar? { i < s.count ? s[i] : nil }
    func peek(_ n: Int) -> Unicode.Scalar? { i + n < s.count ? s[i + n] : nil }

    func error(_ message: String) -> TomlError { TomlError(line: line, message: message) }

    mutating func consume(_ c: Unicode.Scalar) -> Bool {
        guard peek == c else { return false }
        i += 1
        return true
    }

    mutating func skipSpaces() {
        while let c = peek, c == " " || c == "\t" { i += 1 }
    }

    mutating func skipComment() {
        guard peek == "#" else { return }
        while let c = peek, c != "\n" { i += 1 }
    }

    /// Spaces, comments and line breaks, as allowed inside arrays.
    mutating func skipBlank() {
        while true {
            skipSpaces()
            skipComment()
            if peek == "\r" { i += 1; continue }
            if peek == "\n" { i += 1; line += 1; continue }
            return
        }
    }

    /// Optional spaces and a comment, then a line break or the end of the file.
    mutating func endOfLine() throws {
        skipSpaces()
        skipComment()
        _ = consume("\r")
        guard let c = peek else { return }
        guard c == "\n" else { throw error("unexpected '\(c)'; expected the end of the line") }
        i += 1
        line += 1
    }

    mutating func key() throws -> [String] {
        var parts: [String] = []
        repeat {
            skipSpaces()
            parts.append(try keyPart())
            skipSpaces()
        } while consume(".")
        return parts
    }

    private mutating func keyPart() throws -> String {
        if peek == "\"" { return try basicString() }
        if peek == "'" { return try literalString() }
        let start = i
        while let c = peek, TomlValue.isBare(c) { i += 1 }
        guard i > start else { throw error(peek.map { "unexpected '\($0)'; expected a key" } ?? "expected a key") }
        return String(String.UnicodeScalarView(s[start..<i]))
    }

    mutating func value() throws -> TomlValue {
        switch peek {
        case "\"":
            if peek(1) == "\"" && peek(2) == "\"" { throw error("multi-line strings aren't supported") }
            return .string(try basicString())
        case "'":
            if peek(1) == "'" && peek(2) == "'" { throw error("multi-line strings aren't supported") }
            return .string(try literalString())
        case "[": return try array()
        case "{": return try inlineTable()
        case nil: throw error("expected a value")
        default: return try bareValue()
        }
    }

    private mutating func basicString() throws -> String {
        i += 1
        var out = String.UnicodeScalarView()
        while true {
            guard let c = peek, c != "\n" else { throw error("unterminated string") }
            i += 1
            if c == "\"" { return String(out) }
            guard c == "\\" else { out.append(c); continue }
            guard let e = peek else { throw error("unterminated string") }
            i += 1
            switch e {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "u", "U":
                let n = e == "u" ? 4 : 8
                guard i + n <= s.count, let v = UInt32(String(String.UnicodeScalarView(s[i..<i + n])), radix: 16),
                      let u = Unicode.Scalar(v)
                else { throw error("bad \\\(e) escape") }
                out.append(u)
                i += n
            default: throw error("unknown escape \\\(e)")
            }
        }
    }

    private mutating func literalString() throws -> String {
        i += 1
        let start = i
        while let c = peek, c != "'" {
            guard c != "\n" else { throw error("unterminated string") }
            i += 1
        }
        guard peek == "'" else { throw error("unterminated string") }
        defer { i += 1 }
        return String(String.UnicodeScalarView(s[start..<i]))
    }

    private mutating func array() throws -> TomlValue {
        i += 1
        var items: [TomlValue] = []
        while true {
            skipBlank()
            guard peek != nil else { throw error("the array isn't closed with ]") }
            if consume("]") { return .array(items) }
            items.append(try value())
            skipBlank()
            if consume(",") { continue }
            guard consume("]") else { throw error("expected , or ] in the array") }
            return .array(items)
        }
    }

    private mutating func inlineTable() throws -> TomlValue {
        i += 1
        var table: [String: TomlValue] = [:]
        skipSpaces()
        if consume("}") { return .table(table) }
        while true {
            let k = try key()
            guard consume("=") else { throw error("expected = after \(k.joined(separator: "."))") }
            skipSpaces()
            let v = try value()
            try TomlDocument.insert(v, at: k[...], into: &table, line: line)
            skipSpaces()
            if consume(",") { skipSpaces(); continue }
            guard consume("}") else { throw error("expected , or } in the inline table") }
            return .table(table)
        }
    }

    /// true, false or a number.
    private mutating func bareValue() throws -> TomlValue {
        let start = i
        while let c = peek, !" \t\r\n,]}#".unicodeScalars.contains(c) { i += 1 }
        let raw = String(String.UnicodeScalarView(s[start..<i]))
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        let digits = raw.replacingOccurrences(of: "_", with: "")
        if let n = Int(digits) { return .int(n) }
        if let d = Double(digits), digits.contains(where: \.isNumber) { return .double(d) }
        i = start
        throw error(raw.isEmpty ? "expected a value" : "unexpected value \(raw)")
    }
}
