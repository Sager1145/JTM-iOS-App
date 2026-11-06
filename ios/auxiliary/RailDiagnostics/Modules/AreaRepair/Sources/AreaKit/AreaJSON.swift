import Foundation

/// An order-preserving JSON value. Object keys keep their file order and
/// numbers keep their literal text, so a row parsed from a repository data
/// file serialises back to the same bytes. Used for patch payloads and for
/// textual edits of the repository's JSON files.
public indirect enum AreaJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number's literal text, exactly as written in the source.
    case number(String)
    case string(String)
    case array([AreaJSON])
    case object([(String, AreaJSON)])

    public static func == (lhs: AreaJSON, rhs: AreaJSON) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(a), .bool(b)): a == b
        case let (.number(a), .number(b)): a == b || (Double(a) != nil && Double(a) == Double(b))
        case let (.string(a), .string(b)): a == b
        case let (.array(a), .array(b)): a == b
        case let (.object(a), .object(b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: false
        }
    }

    public static func number(_ value: Double) -> AreaJSON { .number(formatNumber(value)) }
    public static func number(_ value: Int) -> AreaJSON { .number(String(value)) }

    /// Python `repr(float)` for finite values (shortest round-trip form).
    public static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e16 { return String(format: "%.1f", value) }
        return "\(value)"
    }

    // MARK: access

    public subscript(key: String) -> AreaJSON? {
        get {
            guard case .object(let pairs) = self else { return nil }
            return pairs.first(where: { $0.0 == key })?.1
        }
        set {
            guard case .object(var pairs) = self else { return }
            if let index = pairs.firstIndex(where: { $0.0 == key }) {
                if let newValue { pairs[index].1 = newValue } else { pairs.remove(at: index) }
            } else if let newValue {
                pairs.append((key, newValue))
            }
            self = .object(pairs)
        }
    }

    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var doubleValue: Double? { if case .number(let n) = self { Double(n) } else { nil } }
    public var arrayValue: [AreaJSON]? { if case .array(let a) = self { a } else { nil } }
    public var objectKeys: [String] { if case .object(let p) = self { p.map(\.0) } else { [] } }

    // MARK: parse

    public static func parse(_ data: Data) throws -> AreaJSON {
        var parser = Parser(bytes: Array(data))
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.position == parser.bytes.count else { throw parser.error("trailing content") }
        return value
    }

    public static func parse(_ text: String) throws -> AreaJSON { try parse(Data(text.utf8)) }

    /// Converts any Encodable through JSONEncoder (key order is that encoder's).
    public static func from<T: Encodable>(_ value: T) throws -> AreaJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try parse(encoder.encode(value))
    }

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(serialized(style: .compact).utf8))
    }

    struct Parser {
        let bytes: [UInt8]
        var position = 0

        func error(_ message: String) -> AreaRepairError {
            .invalidJSON("\(message) at byte \(position)")
        }

        mutating func skipWhitespace() {
            while position < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[position]) { position += 1 }
        }

        mutating func expect(_ byte: UInt8) throws {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == byte else {
                throw error("expected \(Character(UnicodeScalar(byte)))")
            }
            position += 1
        }

        /// Peeks the next non-whitespace byte.
        mutating func peek() -> UInt8? {
            skipWhitespace()
            return position < bytes.count ? bytes[position] : nil
        }

        mutating func parseValue() throws -> AreaJSON {
            guard let byte = peek() else { throw error("unexpected end") }
            switch byte {
            case UInt8(ascii: "{"):
                position += 1
                var pairs: [(String, AreaJSON)] = []
                if peek() == UInt8(ascii: "}") { position += 1; return .object(pairs) }
                while true {
                    skipWhitespace()
                    let key = try parseString()
                    try expect(UInt8(ascii: ":"))
                    pairs.append((key, try parseValue()))
                    guard let next = peek() else { throw error("unterminated object") }
                    position += 1
                    if next == UInt8(ascii: "}") { return .object(pairs) }
                    guard next == UInt8(ascii: ",") else { throw error("expected , or }") }
                }
            case UInt8(ascii: "["):
                position += 1
                var items: [AreaJSON] = []
                if peek() == UInt8(ascii: "]") { position += 1; return .array(items) }
                while true {
                    items.append(try parseValue())
                    guard let next = peek() else { throw error("unterminated array") }
                    position += 1
                    if next == UInt8(ascii: "]") { return .array(items) }
                    guard next == UInt8(ascii: ",") else { throw error("expected , or ]") }
                }
            case UInt8(ascii: "\""):
                return .string(try parseString())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default:
                let start = position
                while position < bytes.count, "+-0123456789.eE".utf8.contains(bytes[position]) { position += 1 }
                guard position > start, let text = String(bytes: bytes[start..<position], encoding: .utf8),
                      Double(text) != nil else { throw error("invalid number") }
                return .number(text)
            }
        }

        mutating func literal(_ word: String) throws {
            let utf8 = Array(word.utf8)
            guard position + utf8.count <= bytes.count, Array(bytes[position..<position + utf8.count]) == utf8 else {
                throw error("invalid literal")
            }
            position += utf8.count
        }

        mutating func parseString() throws -> String {
            guard position < bytes.count, bytes[position] == UInt8(ascii: "\"") else { throw error("expected string") }
            position += 1
            var out = [UInt8]()
            while position < bytes.count {
                let byte = bytes[position]
                position += 1
                if byte == UInt8(ascii: "\"") {
                    guard let text = String(bytes: out, encoding: .utf8) else { throw error("invalid UTF-8") }
                    return text
                }
                if byte != UInt8(ascii: "\\") { out.append(byte); continue }
                guard position < bytes.count else { break }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800..<0xDC00).contains(scalar), position + 1 < bytes.count,
                       bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u") {
                        position += 2
                        let low = try hex4()
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let unicode = UnicodeScalar(scalar) else { throw error("invalid escape") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default: throw error("invalid escape")
                }
            }
            throw error("unterminated string")
        }

        mutating func hex4() throws -> UInt32 {
            guard position + 4 <= bytes.count,
                  let text = String(bytes: bytes[position..<position + 4], encoding: .ascii),
                  let value = UInt32(text, radix: 16) else { throw error("invalid \\u escape") }
            position += 4
            return value
        }
    }

    // MARK: serialise

    /// `pretty(indent)` matches Python `json.dumps(indent=2, ensure_ascii=False)`;
    /// `compact` matches `separators=(",", ":")`.
    public enum Style: Sendable, Equatable {
        case compact
        case pretty(indent: Int)
    }

    /// Serialises the value. `depth` is the nesting level the value starts at
    /// (its first line is not indented; nested lines are).
    public func serialized(style: Style = .pretty(indent: 2), depth: Int = 0) -> String {
        var out = ""
        write(into: &out, style: style, depth: depth)
        return out
    }

    private func write(into out: inout String, style: Style, depth: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): out += Self.quote(s)
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                Self.newline(&out, style: style, depth: depth + 1)
                item.write(into: &out, style: style, depth: depth + 1)
            }
            Self.newline(&out, style: style, depth: depth)
            out += "]"
        case .object(let pairs):
            guard !pairs.isEmpty else { out += "{}"; return }
            out += "{"
            for (index, (key, value)) in pairs.enumerated() {
                if index > 0 { out += "," }
                Self.newline(&out, style: style, depth: depth + 1)
                out += Self.quote(key)
                out += style == .compact ? ":" : ": "
                value.write(into: &out, style: style, depth: depth + 1)
            }
            Self.newline(&out, style: style, depth: depth)
            out += "}"
        }
    }

    private static func newline(_ out: inout String, style: Style, depth: Int) {
        guard case .pretty(let indent) = style else { return }
        out += "\n" + String(repeating: " ", count: indent * depth)
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for unit in text.unicodeScalars {
            switch unit {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if unit.value < 0x20 { out += String(format: "\\u%04x", unit.value) }
                else { out.unicodeScalars.append(unit) }
            }
        }
        return out + "\""
    }
}

extension AreaJSON: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Key.self) {
            self = .object(try keyed.allKeys.sorted { $0.stringValue < $1.stringValue }.map {
                ($0.stringValue, try keyed.decode(AreaJSON.self, forKey: $0))
            })
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var items: [AreaJSON] = []
            while !unkeyed.isAtEnd { items.append(try unkeyed.decode(AreaJSON.self)) }
            self = .array(items)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let b = try? single.decode(Bool.self) { self = .bool(b) }
        else if let i = try? single.decode(Int.self) { self = .number(String(i)) }
        else if let d = try? single.decode(Double.self) { self = .number(d) }
        else { self = .string(try single.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .bool(let b):
            var c = encoder.singleValueContainer(); try c.encode(b)
        case .number(let n):
            var c = encoder.singleValueContainer()
            if let i = Int(n) { try c.encode(i) } else { try c.encode(Double(n) ?? 0) }
        case .string(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .array(let items):
            var c = encoder.unkeyedContainer()
            for item in items { try c.encode(item) }
        case .object(let pairs):
            var c = encoder.container(keyedBy: Key.self)
            for (key, value) in pairs { try c.encode(value, forKey: Key(stringValue: key)) }
        }
    }
}
