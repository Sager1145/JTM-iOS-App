import Foundation

/// Resolves an explicit Japanese service caption to its recorded English name.
/// A lookup never changes the journey or uses its reader-entered English caption.
public enum JourneyEnglishName {
    public static func official(for train: Train, database: TrainTimetableDatabase) throws -> String? {
        guard TrainTimetableDatabase.accepts(train) else { return nil }
        let caption = train.number.precomposedStringWithCompatibilityMapping
        let date = train.date.flatMap { $0.isEmpty ? nil : $0 }
        let characters = Array(caption)
        var bestLength = 0
        var results: Set<String?> = []
        var depth = 0
        for start in characters.indices {
            let character = characters[start]
            if character == "(" || character == "[" { depth += 1; continue }
            if character == ")" || character == "]" { depth = max(0, depth - 1); continue }
            guard depth == 0, !character.isWhitespace,
                  start == 0 || characters[start - 1].isWhitespace else { continue }
            // Try explicit prefixes, longest first. Queries are small catalog
            // reads and exact returned aliases are checked before use.
            var end = start
            while end < characters.count,
                  !"()[]".contains(characters[end]), !characters[end].isNumber {
                end += 1
            }
            guard end > start else { continue }
            for upper in stride(from: end, through: start + 1, by: -1) {
                let name = String(characters[start..<upper])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count >= bestLength else { continue }
                let boundary = start + name.count
                guard boundary == characters.count || isBoundary(characters[boundary]) else { continue }
                for service in try database.service(named: name, on: date) {
                    guard [service.canonicalName, service.matchingName].compactMap({ $0 })
                        .contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
                    else { continue }
                    if name.count > bestLength { bestLength = name.count; results = [] }
                    let english = service.englishName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    results.insert(english.flatMap { $0.isEmpty ? nil : $0 + suffix(in: characters, after: boundary) })
                }
            }
        }
        return results.count == 1 ? results.first.flatMap { $0 } : nil
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character.isNumber || "()[]号次".contains(character)
    }

    private static func suffix(in characters: [Character], after end: Int) -> String {
        var index = end
        while index < characters.count && characters[index].isWhitespace { index += 1 }
        let numberStart = index
        while index < characters.count && characters[index].isNumber { index += 1 }
        var result = index > numberStart ? " " + String(characters[numberStart..<index]) : ""
        // Only preserve parenthesized running codes, never an old English
        // gloss or an arbitrary destination/comment.
        let remainder = String(characters[index...])
        let pattern = #"\(([0-9]+[A-Za-z][0-9A-Za-z]*)\)"#
        if let range = remainder.range(of: pattern, options: .regularExpression) {
            result += " " + remainder[range]
        }
        return result
    }
}
