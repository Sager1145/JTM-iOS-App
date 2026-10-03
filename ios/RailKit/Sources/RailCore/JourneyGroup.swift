import Foundation

/// A user-named collection of journeys, independent of their rail regions.
/// Each train carries its assignment so exports need no additional root keys.
public struct JourneyGroup: Codable, Equatable, Sendable, Identifiable {
    public static let maxNameLength = 12

    public var id: String
    public var name: String {
        didSet { name = Self.normalizedName(name) }
    }

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = Self.normalizedName(name)
    }

    /// Trim and collapse whitespace, then limit by extended grapheme clusters.
    /// Emoji and combining marks remain whole characters.
    public static func normalizedName(_ name: String) -> String {
        String(name.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ").prefix(maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name))
    }
}
