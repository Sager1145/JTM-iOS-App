import Foundation

/// Preserves fields in evolving source schemas. Numbers use Double; station IDs remain strings.
public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    public init(data: Data) throws { self = try JSONDecoder().decode(Self.self, from: data) }
    public func data(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    public var numberValue: Double? { if case .number(let v) = self { v } else { nil } }
    public subscript(_ key: String) -> JSONValue? { objectValue?[key] }
}

public enum WorkbenchError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}

public enum ISODay {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    public static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              day.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 45 }),
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]), year >= 1,
              let value = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)),
              string(value) == day else { return nil }
        return value
    }
    public static func validate(_ day: String) throws {
        guard date(day) != nil else { throw WorkbenchError.invalid("日期必须是有效的 YYYY-MM-DD：\(day)") }
    }
    public static func string(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    static func active(_ value: JSONValue, on day: String) -> Bool {
        let start = value["validFrom"]?.stringValue, end = value["validTo"]?.stringValue
        return (start == nil || start! <= day) && (end == nil || day < end!)
    }
}
