import Foundation

/// Splits typed or printed train text into a service name and a number:
/// "のぞみ 23", "のぞみ23号", "Nozomi 23", "のぞみ２３号". Deliberately minimal and
/// local to the stop-pattern lookup; it does not know which services exist and
/// never guesses a number that is not written.
public enum TrainNumberParser {

    public struct Parsed: Sendable, Hashable {
        /// The service name as written, trimmed (not case-folded).
        public let name: String
        /// The number as written, nil when none is given.
        public let number: Int?
    }

    /// Longest digit run read as a train number.
    private static let maximumDigits = 6

    /// Nil when no service name remains (empty text, or only a number) or the
    /// digit run is too long to be a train number.
    public static func parse(_ text: String) -> Parsed? {
        // NFKC folds full-width digits and spaces to ASCII.
        var rest = text.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.hasSuffix("号") { rest.removeLast() }
        rest = rest.trimmingCharacters(in: .whitespaces)

        var digits = ""
        while let last = rest.last, last.isASCII, last.isNumber {
            digits.insert(last, at: digits.startIndex)
            rest.removeLast()
        }
        if digits.isEmpty {
            return rest.isEmpty ? nil : Parsed(name: rest, number: nil)
        }
        guard digits.count <= maximumDigits, let number = Int(digits) else { return nil }
        if rest.hasSuffix("第") { rest.removeLast() }
        let name = rest.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : Parsed(name: name, number: number)
    }
}
