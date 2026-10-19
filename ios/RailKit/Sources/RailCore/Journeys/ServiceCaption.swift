import Foundation

/// A train's caption, split so a row can print its Latin name as a subline.
///
/// `Train.number` is a caption and not a number — see `Train`, and the
/// committed Japanese store, where it reads 「はるか38号 (Haruka 38) (1038M)」
/// or 「根室本線 普通 (Nemuro Main Line Local) (5625D)」: a native name, its
/// Latin name in the first parentheses, and the running number in the last.
/// Printed as one string at one size, the Latin name is the longest of the
/// three parts and the least often read, and it is what pushes the running
/// number onto a second line.
///
/// jsonspec §3.1 gives the Latin name its own key, `number_en`, and
/// `normalizeImportedTrain` calls this on the way in so that a store still
/// carrying the concatenated caption is imported into the two fields once —
/// after which the caption is stored, edited and searched as what it is, and
/// no view has to take a string apart to draw it.
///
/// This splits exactly that shape and nothing else. The caption is free text
/// that other stores fill differently — 「自強(3000) 125次（嘉義→高雄）」,
/// 「東鐵綫 官方路線示例」, 「경북선 공식 노선 예시」 — and a caption that is
/// not `native (latin) (number)` is returned whole, so nothing a reader wrote
/// is ever re-arranged by a guess. The JavaScript counterpart is
/// `splitLegacyServiceCaption` in app-store-ops.js; both are checked by the
/// same table of captions.
public struct ServiceCaption: Equatable, Sendable {
    /// The caption with the Latin name lifted out — 「はるか38号 (1038M)」 —
    /// or the whole caption when there was nothing to lift.
    public var primary: String
    /// 「Haruka 38」, or nil when the caption did not carry one.
    public var latinName: String?

    public init(primary: String, latinName: String? = nil) {
        self.primary = primary
        self.latinName = latinName
    }

    /// Splits `native (latin) (number)`; returns the caption whole otherwise.
    ///
    /// All three parts are required, and each has to be what it claims: the
    /// native part must contain a Han, kana or Hangul character, the Latin
    /// part must contain a letter and none of those, and the number part
    /// must be non-empty. Only ASCII parentheses count — the full-width
    /// 「（嘉義→高雄）」 of the Taiwanese store is a destination, not a name.
    public static func split(_ caption: String) -> ServiceCaption {
        let whole = ServiceCaption(primary: caption)
        let text = Substring(caption.trimmingCharacters(in: .whitespacesAndNewlines))

        guard let (beforeNumber, number) = trailingGroup(of: text),
              !number.isEmpty, !number.contains(where: { $0 == "(" || $0 == ")" }),
              let (native, latin) = trailingGroup(of: beforeNumber),
              !latin.isEmpty, !latin.contains(where: { $0 == "(" || $0 == ")" }),
              latin.contains(where: \.isLetter), !latin.contains(where: isNativeScript),
              !native.isEmpty, native.contains(where: isNativeScript)
        else { return whole }

        return ServiceCaption(
            primary: "\(native) (\(number))",
            latinName: String(latin))
    }

    /// Splits the captions of a store written before `number_en` existed.
    /// Returns nil when nothing changed, so a caller can tell a migration
    /// that wrote something from a load that did not. A train that already
    /// says `numberEn` is left alone whatever its caption looks like.
    public static func migrateLegacyCaptions(_ trains: [Train]) -> [Train]? {
        var changed = false
        let migrated = trains.map { train -> Train in
            // A blank is absent, as it is at both import doors.
            let existing = train.numberEn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard existing.isEmpty else { return train }
            let service = split(train.number)
            guard let latin = service.latinName else { return train }
            var next = train
            next.number = service.primary
            next.numberEn = latin
            changed = true
            return next
        }
        return changed ? migrated : nil
    }

    /// `"head (group)"` → `("head", "group")`, with the head trimmed of the
    /// whitespace that separated them. Nil unless the text ends in a group.
    private static func trailingGroup(of text: Substring)
        -> (head: Substring, group: Substring)?
    {
        guard text.last == ")",
              let open = text.lastIndex(of: "(")
        else { return nil }
        let group = text[text.index(after: open)..<text.index(before: text.endIndex)]
        var head = text[..<open]
        while let last = head.last, last.isWhitespace { head.removeLast() }
        return (head, group)
    }

    /// Han, hiragana, katakana or Hangul — the scripts the native name is
    /// written in, and the ones a Latin name must not contain.
    private static func isNativeScript(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x1100...0x11FF,   // Hangul Jamo
                 0x3040...0x309F,   // Hiragana
                 0x30A0...0x30FF,   // Katakana
                 0x3130...0x318F,   // Hangul Compatibility Jamo
                 0x3400...0x4DBF,   // CJK Extension A
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0xAC00...0xD7AF:   // Hangul Syllables
                return true
            default:
                return false
            }
        }
    }
}
