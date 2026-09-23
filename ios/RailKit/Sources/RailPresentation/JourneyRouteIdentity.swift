import Foundation
import RailCore

/// Service identity is independent of the railways a train travels over.
public enum JourneyRouteIdentity {
    public static func recordedLineNames(of train: Train) -> [String] {
        let sections = unique((train.routeSections ?? []).flatMap { $0.lineNames ?? [] })
        // Policy hints can include alternative corridors that were never ridden.
        return sections.isEmpty ? unique(train.routePolicy?.preferredLineNames ?? []) : sections
    }

    public static func detectedApplies(_ train: Train, detected: [Statistics.TraversedLine]) -> Bool {
        !detected.isEmpty
            && (TrainServiceBranding.usesDetectedLines(train) || recordedLineNames(of: train).isEmpty)
    }

    public static func lineNames(of train: Train, detected: [Statistics.TraversedLine]) -> [String] {
        let recorded = recordedLineNames(of: train)
        guard detectedApplies(train, detected: detected) else { return recorded }
        // Detection may cover only the loaded portion. Keep recorded legs
        // that detection doesn't already cover until the entire route has
        // finished resolving. Policy alternatives never contribute here —
        // only route sections that were actually ridden. Coverage compares
        // canonical forms so 東海道本線 and its detected 東海道線 count as
        // the same line.
        let observed = unique(detected.map(\.name))
        let observedCanonical = Set(observed.map(canonicalLineName))
        let sectionLines = unique((train.routeSections ?? []).flatMap { $0.lineNames ?? [] })
        let uncovered = sectionLines.filter { observedCanonical.contains(canonicalLineName($0)) == false }
        return unique(observed + uncovered)
    }

    /// Trims, NFKC-normalizes, and folds a trailing 本線 to 線 so that
    /// recorded and detected forms of the same line compare equal.
    private static func canonicalLineName(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        return normalized.hasSuffix("本線") ? String(normalized.dropLast(2)) + "線" : normalized
    }

    public static func operatorNames(of train: Train, detected: [Statistics.TraversedLine]) -> [String] {
        let sections = unique((train.routeSections ?? []).flatMap { $0.operatorNames ?? [] })
        let recorded = (sections.isEmpty ? train.routePolicy?.preferredOperatorNames ?? [] : sections)
            + [train.company].compactMap { $0 }
        return unique(recorded + (detectedApplies(train, detected: detected)
            ? detected.compactMap(\.operatorName) : []))
    }

    /// A limited express never wears a line mark: it resolves its own service
    /// logo, then falls back to its operator's logo, then to the default
    /// train glyph (a nil result) — never to a line mark.
    public static func logoPath(
        for train: Train, lineLogo: @autoclosure () -> String?,
        operatorLogo: @autoclosure () -> String?
    ) -> String? {
        if TrainServiceBranding.isLimitedExpress(train) {
            return TrainServiceBranding.service(for: train)?.logoPath ?? operatorLogo()
        }
        return lineLogo()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
