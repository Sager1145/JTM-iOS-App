import Foundation
import RailCore

/// What a journey is called when there is room for one line and no more —
/// §9.5.6's compact stop, where the panel header IS the whole panel.
///
/// ## The problem
///
/// `Train.number` is a free-text field, and the committed stores use it as a
/// caption rather than as a name. Real values from the Japanese store:
///
/// ```text
/// はるか38号（Haruka 38）（1038M）
/// 東海道本線 普通（Tōkaidō Main Line Local）
/// 普通（08:05 我孫子行・東京メトロ千代田線から直通）
/// 自強(3000) 137次（臺中→彰化）
/// ```
///
/// Every one of those is right in a list row two lines tall. At the compact
/// stop the header has one line over a tab bar, and what arrives there is the
/// romaji gloss, the departure time, the destination and the through-service
/// note — a sentence, wrapped, where an identity was wanted. The reader
/// already has the times and the endpoints: they are the subtitle directly
/// underneath, and the map is drawing the line behind it.
///
/// ## What is left
///
/// The 種別, the line or train name, and the train number when the record
/// knows one — nothing else, and never a second language's spelling of what
/// is already there. A 特急 keeps its own name (はるか38号) because that is
/// what identifies it; a 普通 keeps its line, because that is.
///
/// ## What is dropped, and how it is told apart
///
/// The asides are bracketed, so brackets are the whole of the rule — with one
/// exception, and the exception is why this is not a `firstIndex(of: "（")`:
/// a bracket can carry the train number (`（1038M）`) and it can be part of
/// the name itself (`自強(3000)`, a class of Taiwanese express). So a group is
/// kept exactly when it reads as a CODE — ASCII letters and digits, at least
/// one digit, no spaces — and dropped when it reads as prose. Kept groups stay
/// where they are, brackets and all, which is what keeps `自強(3000) 137次`
/// intact while `（Haruka 38）` goes.
///
/// Native-only, so it lives here rather than in `RailCore`: the web app's list
/// prints `number` whole and has no compact stop to print it into. It is still
/// a rule with cases, which is why it is in this target rather than in a view
/// — `JourneyTitleTests` is the only thing that can hold it to them.
public enum JourneyTitle {

    /// The journey's name, cut to what identifies it.
    ///
    /// The 種別 leads unless the name already carries it, which most of them
    /// do: `東海道本線 普通` says 普通 in its own order and prefixing another
    /// would be the app arguing with the record. `埼京線（Saikyō Line）（1201F）`
    /// does not, and a 快速 that reads as an ordinary 埼京線 has lost the one
    /// thing that distinguishes it from the train before it.
    ///
    /// Never empty when the record is not: a name that is nothing but asides
    /// falls back to the record's own text rather than to a blank header.
    public static func compact(_ train: Train) -> String {
        let name = withoutAsides(train.number)
        let type = (train.trainType ?? "").trimmingCharacters(in: .whitespaces)
        let parts: [String]
        if type.isEmpty || name.contains(type) {
            parts = [name]
        } else {
            parts = [type, name]
        }
        let title = parts.filter { !$0.isEmpty }.joined(separator: " ")
        guard title.isEmpty else { return title }
        return train.number.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name with its prose asides removed and its code asides left in
    /// place.
    ///
    /// An UNCLOSED bracket is kept whole, along with everything after it. It
    /// is malformed either way, and the two ways of being wrong are not equal:
    /// dropping the tail of a name silently loses a journey's identity, while
    /// keeping it shows the reader the same caption they had before.
    private static func withoutAsides(_ name: String) -> String {
        var kept = ""
        var group = ""
        var closers: [Character] = []
        for character in name {
            if let closer = closing[character] {
                closers.append(closer)
                group.append(character)
                continue
            }
            guard !closers.isEmpty else {
                kept.append(character)
                continue
            }
            group.append(character)
            if character == closers.last {
                closers.removeLast()
                if closers.isEmpty {
                    if isCode(group.dropFirst().dropLast()) { kept += group }
                    group = ""
                }
            }
        }
        kept += group
        return collapsingSpaces(kept)
    }

    /// The bracket pairs the committed stores actually use: the full-width
    /// pair the Japanese and Chinese records are written with, and the ASCII
    /// pair Taiwan's 自強(3000) uses.
    private static let closing: [Character: Character] = ["（": "）", "(": ")"]

    /// Whether a bracket's content is a train number rather than a sentence.
    ///
    /// A digit is required, which is what separates `1038M` and `3000` from
    /// `Kodama` and `Local`; ASCII is required, which is what separates them
    /// from `我孫子行`; and a space ends it, which is what separates them from
    /// `Haruka 38`.
    private static func isCode(_ content: Substring) -> Bool {
        guard !content.isEmpty else { return false }
        var hasDigit = false
        for character in content {
            guard let ascii = character.asciiValue else { return false }
            switch ascii {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): hasDigit = true
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "a")...UInt8(ascii: "z"),
                UInt8(ascii: "-"): break
            default: return false
            }
        }
        return hasDigit
    }

    /// A dropped aside leaves the space that was in front of it behind.
    private static func collapsingSpaces(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace { result.append(" ") }
            pendingSpace = false
            result.append(character)
        }
        return result
    }
}
