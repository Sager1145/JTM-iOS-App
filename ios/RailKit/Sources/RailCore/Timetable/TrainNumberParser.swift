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

    /// Drops a "No.", "No", "#" or hyphen written between the name and the
    /// number ("Nozomi No. 23", "Nozomi No.23", "Nozomi-23", "Nozomi #23"). "no" is
    /// a marker only after a space, hyphen or non-letter, so a name that ends in
    /// "no" (Nasuno) keeps it.
    private static func nameWithoutNumberMarker(_ text: String) -> String {
        var rest = text
        while true {
            rest = rest.trimmingCharacters(in: .whitespaces)
            if let last = rest.last, "#-\u{2010}\u{2013}\u{2014}".contains(last) {
                rest.removeLast()
                continue
            }
            let lower = rest.lowercased()
            func markerEnds(_ suffix: String, needsSeparator: Bool) -> Bool {
                guard lower.hasSuffix(suffix) else { return false }
                let before = rest.dropLast(suffix.count).last
                guard let before else { return false }
                if before.isWhitespace || before == "-" { return true }
                return !needsSeparator && !(before.isASCII && before.isLetter)
            }
            if markerEnds("no.", needsSeparator: false) {
                rest.removeLast(3)
            } else if markerEnds("no", needsSeparator: true) {
                rest.removeLast(2)
            } else {
                return rest
            }
        }
    }

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
        let name = nameWithoutNumberMarker(rest)
        return name.isEmpty ? nil : Parsed(name: name, number: number)
    }
}
