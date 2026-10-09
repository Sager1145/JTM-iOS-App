import Foundation

/// Stateless ordered JSON writing for canonical train-store bytes.
/// Model projection and workspace mutations stay with their existing owners.
enum CanonicalTrainStoreJSON {

    /// `JSON.stringify(value, null, indent)`.
    ///
    /// Hand-written because no `JSONEncoder` configuration produces insertion
    /// order, and insertion order is the format. The rest of the rules are
    /// V8's, and each of the ones below is reachable from a hand-authored
    /// itinerary, since a station name is free text:
    ///
    ///   - `indent` is clamped to 0…10 and spelled as spaces. At 0 there is
    ///     no whitespace at all, not even after a colon.
    ///   - An empty array or object is `[]` / `{}` even with a gap.
    ///   - Only `"`, `\` and the C0 controls are escaped. `/` is NOT escaped
    ///     (Foundation's `JSONEncoder` escapes it), non-ASCII is emitted raw
    ///     (which is what makes a CJK station name one token rather than six
    ///     escapes), and U+2028/U+2029 are emitted raw despite being line
    ///     terminators in JavaScript source.
    ///   - The five short escapes are `\b \t \n \f \r`; every other C0
    ///     control is `\u00xx` in LOWER-case hex.
    ///   - A non-finite number is `null`, and a finite one is spelled by
    ///     ``JSNumber/string(_:)`` — `139`, not `139.0`.
    static func stringify(_ value: TrainValidation.JSON, indent: Int = 0) -> String {
        var out = ""
        // Reserving is worth it: the Japanese archive is 1.18 MB and this is
        // called on every save.
        out.reserveCapacity(1 << 12)
        let gap = String(repeating: " ", count: max(0, min(10, indent)))
        write(value, gap: gap, currentIndent: "", into: &out)
        return out
    }

    private static func write(
        _ value: TrainValidation.JSON, gap: String, currentIndent: String, into out: inout String
    ) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        // `JSON.stringify(NaN)` and `JSON.stringify(Infinity)` are both "null":
        // JSON has no spelling for either, so the value is dropped rather than
        // the call failing.
        case .number(let number): out += number.isFinite ? JSNumber.string(number) : "null"
        case .string(let text): quote(text, into: &out)
        case .array(let items):
            writeArray(items, gap: gap, currentIndent: currentIndent, into: &out)
        case .object(let object):
            writeObject(object, gap: gap, currentIndent: currentIndent, into: &out)
        }
    }

    private static func writeArray(
        _ items: [TrainValidation.JSON], gap: String, currentIndent: String, into out: inout String
    ) {
        guard !items.isEmpty else {
            out += "[]"
            return
        }
        let inner = currentIndent + gap
        out += gap.isEmpty ? "[" : "[\n\(inner)"
        for (index, item) in items.enumerated() {
            if index > 0 { out += gap.isEmpty ? "," : ",\n\(inner)" }
            write(item, gap: gap, currentIndent: inner, into: &out)
        }
        out += gap.isEmpty ? "]" : "\n\(currentIndent)]"
    }

    private static func writeObject(
        _ object: TrainValidation.JSON.Object, gap: String, currentIndent: String, into out: inout String
    ) {
        guard !object.keys.isEmpty else {
            out += "{}"
            return
        }
        let inner = currentIndent + gap
        out += gap.isEmpty ? "{" : "{\n\(inner)"
        for (index, key) in object.keys.enumerated() {
            if index > 0 { out += gap.isEmpty ? "," : ",\n\(inner)" }
            quote(key, into: &out)
            out += gap.isEmpty ? ":" : ": "
            write(object[key] ?? .null, gap: gap, currentIndent: inner, into: &out)
        }
        out += gap.isEmpty ? "}" : "\n\(currentIndent)}"
    }

    /// `QuoteJSONString`.
    ///
    /// Walks UTF-16 code units rather than scalars: a character outside the
    /// BMP is a surrogate PAIR, and handling each half on its own turns one
    /// emoji into two replacement characters. Restated here rather than
    /// shared with `TrainValidation.JSON.canonicalText`'s private copy — this
    /// file may not edit that one — so the parity test asserts the two agree
    /// on a string, which is the check that keeps them from drifting.
    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        var units: [UInt16] = []
        // Runs of ordinary code units are flushed in one go: escaping is rare
        // and per-unit `String(decoding:)` on a 1.18 MB archive is not free.
        func flush() {
            guard !units.isEmpty else { return }
            out += String(decoding: units, as: UTF16.self)
            units.removeAll(keepingCapacity: true)
        }
        for unit in text.utf16 {
            switch unit {
            case 0x22: flush(); out += "\\\""
            case 0x5C: flush(); out += "\\\\"
            case 0x08: flush(); out += "\\b"
            case 0x09: flush(); out += "\\t"
            case 0x0A: flush(); out += "\\n"
            case 0x0C: flush(); out += "\\f"
            case 0x0D: flush(); out += "\\r"
            case 0..<0x20:
                flush()
                out += "\\u00"
                let hex = "0123456789abcdef"
                out.append(hex[hex.index(hex.startIndex, offsetBy: Int(unit >> 4))])
                out.append(hex[hex.index(hex.startIndex, offsetBy: Int(unit & 0xF))])
            default: units.append(unit)
            }
        }
        flush()
        out += "\""
    }
}
