import Foundation

/// One stored split of an official station name (`bracketedNames` in the registry bundle).
///
/// The bracket is not parsed out of the name at runtime. `kind == .status` is
/// display data: closed and historical stations stay selectable for a dated ride.
public struct StationNameRecord: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case subname
        case status
    }

    public enum Position: String, Codable, Sendable {
        case suffix
        case infix
    }

    public enum Status: String, Codable, Sendable {
        case reserved
        case planned
        case closed
        case suspended
        case historical
    }

    public var base: String
    public var bracket: String
    public var kind: Kind
    public var status: Status?
    public var position: Position

    public init(
        base: String, bracket: String, kind: Kind, status: Status? = nil, position: Position
    ) {
        self.base = base
        self.bracket = bracket
        self.kind = kind
        self.status = status
        self.position = position
    }
}

/// Official names that contain one bracket group, plus how many complexes share each base.
public struct StationNameDirectory: Hashable, Sendable {
    public var bracketedNames: [String: StationNameRecord]
    public var baseNameCounts: [String: Int]

    public init(
        bracketedNames: [String: StationNameRecord] = [:],
        baseNameCounts: [String: Int] = [:]
    ) {
        self.bracketedNames = bracketedNames
        self.baseNameCounts = baseNameCounts
    }

    public init(bundle: RegistryBundle) {
        self.init(bracketedNames: bundle.bracketedNames, baseNameCounts: bundle.baseNameCounts)
    }

    /// The stored parts for this official spelling, or the same name with half-width
    /// and full-width brackets folded. Two different names that fold together match nothing.
    public func parts(forOfficialName name: String) -> StationNameRecord? {
        if let exact = bracketedNames[name] { return exact }
        let folded = Self.foldBrackets(name)
        let hits = bracketedNames.filter { Self.foldBrackets($0.key) == folded }
        guard hits.count == 1, let record = hits.values.first else { return nil }
        return record
    }

    /// Longest bracketed official name that is `text` or a leading part of it.
    /// The remainder keeps everything after that name.
    public func leadingOfficialName(in text: String) -> (official: String, remainder: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let foldedText = Self.foldBrackets(trimmed)
        var bestKey: String?
        var bestCount = 0
        for key in bracketedNames.keys {
            let foldedKey = Self.foldBrackets(key)
            guard !foldedKey.isEmpty, foldedText.hasPrefix(foldedKey) else { continue }
            let count = foldedKey.count
            guard count >= bestCount else { continue }
            let next = foldedText.index(foldedText.startIndex, offsetBy: count)
            if next != foldedText.endIndex {
                let mark = foldedText[next]
                // A qualifier may touch the official name: `西鉄福岡（天神）(JP, 天神大牟田線)`.
                if !mark.isWhitespace && mark != "(" { continue }
            }
            if count == bestCount, let current = bestKey {
                let currentExact = String(trimmed.prefix(Self.foldBrackets(current).count)) == current
                let nextExact = String(trimmed.prefix(count)) == key
                if currentExact && !nextExact { continue }
                if currentExact == nextExact && key > current { continue }
            }
            bestKey = key
            bestCount = count
        }
        guard let bestKey else { return nil }
        let remainder = trimmed.dropFirst(bestCount).trimmingCharacters(in: .whitespacesAndNewlines)
        return (bestKey, String(remainder))
    }

    public func officialNames(withBase base: String) -> [String] {
        bracketedNames.compactMap { key, record in record.base == base ? key : nil }.sorted()
    }

    /// `（）`/`()` and `〈〉`/`<>`, including the full-width less-than signs.
    public static func foldBrackets(_ text: String) -> String {
        var folded = ""
        folded.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "（": folded.append("(")
            case "）": folded.append(")")
            case "〈", "＜": folded.append("<")
            case "〉", "＞": folded.append(">")
            default: folded.append(character)
            }
        }
        return folded
    }
}

/// The app installs this from the same bundled registry file as identity upgrade.
public enum StationNameLookup {
    public typealias Provider = @Sendable (String) -> StationNameDirectory?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var provider: Provider?

    public static func install(_ provider: Provider?) {
        lock.lock()
        self.provider = provider
        lock.unlock()
    }

    public static func directory(forRegion region: String) -> StationNameDirectory? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        let current = provider
        lock.unlock()
        return current?(cc)
    }
}
