import Foundation

/// Shared, locale-independent normalization for multilingual discovery.
public enum SearchFold {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: String] = [:]
    }
    private static let cache = Cache()
    private static let variants: [Character: Character] = [
        "鉄": "铁", "鐵": "铁", "営": "营", "広": "广", "浜": "滨", "沢": "泽",
        "関": "关", "県": "县", "気": "气", "発": "发", "図": "图", "線": "线",
        "東": "东", "電": "电", "車": "车", "臺": "台", "桜": "樱", "竜": "龙",
        "戸": "户", "楽": "乐", "渋": "涩", "円": "圆", "黒": "黑", "徳": "德",
        "歩": "步", "経": "经", "塩": "盐", "辺": "边", "恵": "惠", "横": "横",
        "浅": "浅", "駒": "驹", "舘": "馆", "館": "馆", "庁": "厅", "区": "区",
        "蔵": "藏", "ヶ": "ケ", "ヵ": "ケ"
    ]

    public static func fold(_ value: String) -> String {
        cache.lock.lock()
        let cached = cache.values[value]
        cache.lock.unlock()
        if let cached { return cached }
        var text = value.precomposedStringWithCompatibilityMapping.lowercased()
        // Diacritics are stripped only from Latin letters; kana voicing is meaningful.
        text = text.map { character in
            guard let first = String(character).decomposedStringWithCanonicalMapping.unicodeScalars.first,
                  (0x41...0x7A).contains(first.value) || (0xC0...0x024F).contains(first.value) else {
                return String(character)
            }
            return String(character).folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        }.joined()
        text = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        text = String(text.map { variants[$0] ?? $0 })
        text = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
        var kept = ""
        var separated = false
        for scalar in text.unicodeScalars {
            if ignored.contains(scalar) { separated = true; continue }
            if separated, let last = kept.unicodeScalars.last,
               CharacterSet.decimalDigits.contains(last), CharacterSet.decimalDigits.contains(scalar) {
                kept.append(" ")
            }
            kept.unicodeScalars.append(scalar)
            separated = false
        }
        text = kept
        cache.lock.lock()
        if cache.values.count >= 20_000 { cache.values.removeAll(keepingCapacity: true) }
        cache.values[value] = text
        cache.lock.unlock()
        return text
    }

    public static func tokens(_ query: String) -> [String] {
        func script(_ scalar: Unicode.Scalar) -> Int {
            switch scalar.value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return 3
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF: return 2
            default: return 1
            }
        }
        var runs: [String] = [], current = "", previous = 0
        for scalar in query.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty { runs.append(current); current = "" }
                previous = 0
                continue
            }
            let next = script(scalar)
            if previous != 0 && next != previous { runs.append(current); current = "" }
            current.unicodeScalars.append(scalar)
            previous = next
        }
        if !current.isEmpty { runs.append(current) }
        return runs.map(fold).filter { !$0.isEmpty }
    }

    private static let synonyms = [
        ["地铁", "地下鉄", "地下铁", "捷运", "subway", "metro", "지하철"],
        ["铁路", "铁道", "railway", "railroad", "철도"],
        ["电车", "電鐵", "electric railway"],
        ["新干线", "新幹線", "shinkansen", "신칸센"],
        ["特急", "特快", "limited express", "특급"],
        ["站", "駅", "station", "기차역"]
    ].map { Array(Set($0.map(fold))) }

    private static func alternatives(_ text: String) -> [String] {
        var result: Set<String> = [text]
        for group in synonyms {
            for name in group where text.contains(name) {
                for alternative in group { result.insert(text.replacingOccurrences(of: name, with: alternative)) }
            }
        }
        return Array(result)
    }

    /// Reusable query normalization and synonym expansion for a result scan.
    public struct PreparedQuery: Sendable {
        public let whole: String
        public let tokens: [String]
        public let isEmpty: Bool
        private let wholeAlternatives: [String]
        private let tokenAlternatives: [[String]]
        private let plainTokens: [[String]]

        public init(_ query: String) {
            isEmpty = query.isEmpty
            whole = SearchFold.fold(query)
            tokens = SearchFold.tokens(query)
            wholeAlternatives = whole.isEmpty ? [] : SearchFold.alternatives(whole)
            tokenAlternatives = tokens == [whole] ? [] : tokens.map(SearchFold.alternatives)
            let rawTokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            plainTokens = tokens.map { token in rawTokens.filter { SearchFold.fold($0) == token } }
        }

        public func matches(fields: [String], plainFields: [String] = [], rawQuery: String = "") -> Bool {
            if isEmpty { return true }
            guard !whole.isEmpty else { return false }
            let values = fields.map(SearchFold.fold)
            func hit(_ alternatives: [String]) -> Bool {
                alternatives.contains { candidate in values.contains { $0.contains(candidate) } }
            }
            if hit(wholeAlternatives) { return true }
            if !rawQuery.isEmpty && plainFields.contains(where: { $0.localizedCaseInsensitiveContains(rawQuery) }) { return true }
            return !tokenAlternatives.isEmpty && tokenAlternatives.indices.allSatisfy { index in
                hit(tokenAlternatives[index]) || plainFields.contains { field in
                    plainTokens[index].contains { field.localizedCaseInsensitiveContains($0) }
                }
            }
        }
    }

    public static func matches(query: String, fields: [String]) -> Bool {
        PreparedQuery(query).matches(fields: fields)
    }
}
