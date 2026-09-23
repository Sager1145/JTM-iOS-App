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
                if beforeIsWordOrHyphen == false && hasTrainNumberContext(after: range.upperBound, in: caption) {
                    return true
                }
            } else {
                // CJK-leading names keep the original rule: the preceding
                // character is not checked, only what follows the match.
                let endsWithWord = name.last?.isLetter == true
                let nextCharacter = range.upperBound < caption.endIndex ? caption[range.upperBound] : nil
                let afterExtendsName = nextCharacter?.isLetter == true && nextCharacter != "号"
                if endsWithWord == false || afterExtendsName == false {
                    return true
                }
            }
            searchStart = caption.index(after: range.lowerBound)
        }
        return false
    }

    /// True when the text following a Latin-leading name reads as a train
    /// number rather than the continuation of an unrelated name: nothing,
    /// a digit, "号", "no."/"no ", or an opening parenthesis.
    private static func hasTrainNumberContext(after index: String.Index, in caption: String) -> Bool {
        var remainder = Substring(caption[index...])
        while let first = remainder.first, first.isWhitespace {
            remainder = remainder.dropFirst()
        }
        guard let first = remainder.first else { return true }
        if first.isNumber || first == "(" || first == "（" { return true }
        return remainder.hasPrefix("号") || remainder.hasPrefix("no.") || remainder.hasPrefix("no ")
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
        normalizedText(value)
    }

    private static func canonicalOperator(_ value: String) -> String {
        normalizedText(OperatorBranding.companyLabel(value))
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }

    var isASCIIWord: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.first.map { $0.isASCII && ($0.properties.isAlphabetic || $0.properties.numericType != nil) }
                == true
    }
}
