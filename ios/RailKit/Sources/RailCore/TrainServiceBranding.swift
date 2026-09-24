import Foundation

/// Named passenger-service branding and route-source classification.
///
/// Service identity is catalog data, while the classifiers below only use
/// fields recorded on the itinerary. In particular, no decision is inferred
/// from the lines underneath solved route geometry.
public enum TrainServiceBranding {
    public struct Service: Codable, Sendable {
        public let id: String
        public let region: String
        public let names: [String]
        public let logoPath: String?

        public init(id: String, region: String, names: [String], logoPath: String? = nil) {
            self.id = id
            self.region = region
            self.names = names
            self.logoPath = logoPath
        }
    }

    /// The bundled service catalog. A missing or malformed resource is a
    /// packaging error and fails at first use rather than silently disabling
    /// service branding.
    public static let services: [Service] = {
        guard let url = Bundle.module.url(
            forResource: "train-service-branding", withExtension: "json")
        else {
            fatalError("RailCore is missing train-service-branding.json")
        }
        do {
            return try JSONDecoder().decode([Service].self, from: Data(contentsOf: url))
        } catch {
            fatalError("RailCore could not decode train-service-branding.json: \(error)")
        }
    }()

    /// The catalog pre-normalized once and sorted longest-name-first, so
    /// `service(for:)` scans instead of re-normalizing every candidate name
    /// on every call. Longest-first resolution makes サフィール踊り子 win
    /// over the shorter 踊り子 name it contains.
    private static let normalizedCatalog: [(service: Service, name: String)] = services
        .flatMap { service in service.names.map { (service: service, name: normalizedText($0)) } }
        .filter { $0.name.isEmpty == false }
        .sorted { $0.name.count > $1.name.count }

    /// Resolves the longest catalog name found in the train's native or Latin
    /// caption.
    public static func service(for train: Train) -> Service? {
        let region = normalizedRegion(train.region)
        let captions = [train.number, train.numberEn]
            .compactMap { $0 }
            .map(normalizedText)
            .map(stripDirectionalBrackets)

        return normalizedCatalog.first { candidate in
            normalizedRegion(candidate.service.region) == region
                && captions.contains { containsServiceName(candidate.name, in: $0) }
        }?.service
    }

    /// True for an explicitly labelled limited express, or for a service in
    /// the named limited-express catalog even when the imported type is absent.
    /// 特快 only counts in Taiwan/Hong Kong/Macau; in Japan it abbreviates
    /// 特別快速 (a rapid service, e.g. 中央特快), not a limited express.
    public static func isLimitedExpress(_ train: Train) -> Bool {
        if service(for: train) != nil { return true }

        let text = classificationText(train)
        let region = normalizedRegion(train.region)
        let regionAllowsTekkuai = ["tw", "hk", "mo"].contains(region)
        return text.contains("特急")
            || (regionAllowsTekkuai && text.contains("特快"))
            || text.contains("limited express")
            || text.contains("limited-express")
            || text.contains("limitedexpress")
            || text.contains("ltd express")
            || text.contains("ltd. express")
    }

    /// Whether a journey should use line identities detected along its solved
    /// route. The answer comes from recorded service/type/cross-line evidence;
    /// callers must not turn incidental geometric overlap into such evidence.
    public static func usesDetectedLines(_ train: Train) -> Bool {
        if isLimitedExpress(train) { return true }

        let type = normalizedText(train.trainType ?? "")
        let expressMarkers = [
            "急行", "快速", "新幹線", "ライナー", "寝台",
            "自強", "自强", "普悠瑪", "普悠玛", "太魯閣", "太鲁阁", "莒光",
            "高鐵", "高铁", "ktx", "srt", "itx", "새마을", "무궁화",
            "express", "rapid", "intercity", "acela", "corridor",
        ]
        if expressMarkers.contains(where: type.contains) { return true }

        let text = classificationText(train)
        let throughMarkers = [
            "直通", "直通運転", "跨線", "跨线",
            "through service", "through-service", "through running", "through-running",
        ]
        if throughMarkers.contains(where: text.contains) { return true }

        // Cross-line evidence comes only from recorded route sections: policy
        // alternatives are corridors that may never have been ridden, and
        // `train.company` is not a per-leg operator record.
        let sectionLines = recordedValues(in: train.routeSections, keyPath: \.lineNames)
        if distinctCount(sectionLines, normalizing: canonicalRecordedValue) > 1 { return true }

        let sectionOperators = recordedValues(in: train.routeSections, keyPath: \.operatorNames)
        return distinctCount(sectionOperators, normalizing: canonicalOperator) > 1
    }

    private static func normalizedRegion(_ value: String?) -> String {
        let normalized = normalizedText(value ?? "")
        return normalized.isEmpty ? "jp" : normalized
    }

    private static func normalizedText(_ value: String) -> String {
        let compatible = value.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .lowercased()
        return compatible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func classificationText(_ train: Train) -> String {
        [train.trainType, train.number, train.numberEn]
            .compactMap { $0 }
            .map(normalizedText)
            .joined(separator: " ")
    }

    /// A Latin-leading name (e.g. "Haruka") needs a train-number context to
    /// avoid matching inside unrelated station or line names such as
    /// "Kinosaki-Onsen" or "Fuji Kyuko Line". CJK-leading names keep the
    /// original word-boundary rule.
    private static func containsServiceName(_ name: String, in caption: String) -> Bool {
        var searchStart = caption.startIndex
        while searchStart < caption.endIndex,
              let range = caption.range(of: name, range: searchStart..<caption.endIndex) {
            let startsWithLatinWord = name.first?.isASCIIWord == true
            let beforeCharacter = range.lowerBound > caption.startIndex
                ? caption[caption.index(before: range.lowerBound)] : nil
            let beforeIsWord = beforeCharacter?.isLetterOrNumber == true

            if startsWithLatinWord {
                let beforeIsWordOrHyphen = beforeIsWord || beforeCharacter == "-"
                if beforeIsWordOrHyphen == false
                    && hasTrainNumberContext(before: range.lowerBound, after: range.upperBound, in: caption) {
                    return true
                }
            } else {
                // CJK-leading names keep the original rule: the preceding
                // character is not checked, only what follows the match —
                // except that a name found straddling an arrow (station-list
                // brackets such as `宇都宮→日光` that survived because they
                // did not end in 行/方面) is a route segment, not the service.
                let endsWithWord = name.last?.isLetter == true
                let nextCharacter = range.upperBound < caption.endIndex ? caption[range.upperBound] : nil
                let afterExtendsName = nextCharacter?.isLetter == true && nextCharacter != "号"
                let adjacentToArrow = beforeCharacter == "→" || beforeCharacter == "←"
                    || nextCharacter == "→" || nextCharacter == "←"
                // A kana-leading name found right after more kana is the tail
                // of a longer word — かもめ inside ゆりかもめ — not the service.
                // Longer catalog names (リレーかもめ) are tried first, so a
                // genuine prefix still wins through its own entry. The
                // prolonged-sound mark ("ー") is excluded from this check so
                // old-style captions like スーパーやくも / スーパーしおかぜ /
                // スーパーいしづち / スーパーいなほ still resolve to their
                // base service.
                let kanaRunContinues = name.first?.isKana == true && beforeCharacter?.isKana == true
                    && beforeCharacter != "ー"
                if adjacentToArrow == false && kanaRunContinues == false
                    && (endsWithWord == false || afterExtendsName == false) {
                    return true
                }
            }
            searchStart = caption.index(after: range.lowerBound)
        }
        return false
    }

    /// True when the text following a Latin-leading name reads as a train
    /// number rather than the continuation of an unrelated name: a digit,
    /// "号", "no."/"no ", or an opening parenthesis. Nothing following (the
    /// name ends the caption) also counts, unless the word immediately
    /// before the name is "for", "to", or "bound" — "Local for Aso" names a
    /// destination, not the train.
    private static func hasTrainNumberContext(
        before start: String.Index, after index: String.Index, in caption: String
    ) -> Bool {
        var remainder = Substring(caption[index...])
        while let first = remainder.first, first.isWhitespace {
            remainder = remainder.dropFirst()
        }
        guard let first = remainder.first else {
            return precededByBoundMarker(before: start, in: caption) == false
        }
        if first.isNumber || first == "(" || first == "（" { return true }
        return remainder.hasPrefix("号") || remainder.hasPrefix("no.") || remainder.hasPrefix("no ")
    }

    /// True when the word immediately before `start` (skipping whitespace)
    /// is "for", "to", or "bound".
    private static func precededByBoundMarker(before start: String.Index, in caption: String) -> Bool {
        var end = start
        while end > caption.startIndex, caption[caption.index(before: end)].isWhitespace {
            end = caption.index(before: end)
        }
        var begin = end
        while begin > caption.startIndex, caption[caption.index(before: begin)].isLetter {
            begin = caption.index(before: begin)
        }
        guard begin < end else { return false }
        let word = caption[begin..<end]
        return word == "for" || word == "to" || word == "bound"
    }

    /// Removes every bracketed segment whose content is a station-to-station
    /// or destination hint (`（宇都宮→日光）`, `(Tokyo-Nikko)`, `（新橋方面）`)
    /// before matching, so a service name that only appears inside such a
    /// segment — as part of a route description rather than the caption's
    /// own service name — cannot match. Brackets are ASCII by the time this
    /// runs: `normalizedText`'s NFKC pass already folds full-width
    /// `（…）` to `(…)`.
    private static func stripDirectionalBrackets(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "(", let close = text[index...].firstIndex(of: ")") {
                let content = text[text.index(after: index)..<close]
                if isDirectionalBracketContent(content) {
                    index = text.index(after: close)
                    continue
                }
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }

    private static func isDirectionalBracketContent(_ content: Substring) -> Bool {
        let markers = ["→", "->", "～", "〜"]
        if markers.contains(where: content.contains) { return true }
        return content.hasSuffix("行") || content.hasSuffix("方面")
    }

    /// Trims, NFKC-normalizes, and folds a trailing 本線 to 線 so that
    /// recorded and detected forms of the same line compare equal.
    public static func canonicalLineName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        return normalized.hasSuffix("本線") ? String(normalized.dropLast(2)) + "線" : normalized
    }

    private static func recordedValues(
        in sections: [RouteSection]?, keyPath: KeyPath<RouteSection, [String]?>
    ) -> [String] {
        (sections ?? []).flatMap { $0[keyPath: keyPath] ?? [] }
    }

    private static func distinctCount(
        _ values: [String], normalizing: (String) -> String
    ) -> Int {
        Set(values.map(normalizing).filter { $0.isEmpty == false }).count
    }

    private static func canonicalRecordedValue(_ value: String) -> String {
        normalizedText(canonicalLineName(value))
    }

    private static func canonicalOperator(_ value: String) -> String {
        normalizedText(OperatorBranding.companyLabel(value))
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
    /// Hiragana, katakana, or the prolonged-sound mark — the characters
    /// that continue a kana word. Excludes the katakana middle dot (・) and
    /// the katakana-hiragana double hyphen (゠), which separate words rather
    /// than continue them.
    var isKana: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        if scalar.value == 0x30FB || scalar.value == 0x30A0 { return false }
        switch scalar.value {
        case 0x3041...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return true
        default: return false
        }
    }


    var isASCIIWord: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.first.map { $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil) }
                == true
    }
}
