import Foundation
import RailCore

/// Values and ordering for the statistics dashboard's line-detail categories.
/// Scope, loading and mileage matching remain with the caller.
public enum StatisticsLineCoverage {
    public struct Row: Sendable, Equatable, Identifiable {
        public let name: String
        /// Raw N02 operator used for grouping and identity.
        public let operatorName: String
        /// Short operator label used for display.
        public let company: String
        public let total: Double
        public let ridden: Double
        public var id: String { "\(operatorName)\u{001F}\(name)" }
        public var percent: Double { total > 0 ? 100 * ridden / total : 0 }
    }

    public static func rows(
        mask: Int,
        totals: [(name: String, byMask: [Int: Double])],
        operators: [String: String],
        ridden: Statistics.OrderedDictionary<String, [Int: Double]>
    ) -> [Row] {
        // Small categories show their unridden lines; other categories show
        // only ridden lines, keeping hundreds of empty rows out of the card.
        let includeUnridden = mask == Statistics.maskHSR || mask == Statistics.maskMETRO
        return totals.compactMap { item -> Row? in
            let total = item.byMask[mask] ?? 0
            guard total > 0 else { return nil }
            let riddenKm = ridden[item.name]?[mask] ?? 0
            guard riddenKm > 0 || includeUnridden else { return nil }
            let operatorName = operators[item.name] ?? ""
            return Row(
                name: item.name, operatorName: operatorName,
                company: operatorName.isEmpty ? "" : OperatorBranding.companyLabel(operatorName),
                total: total, ridden: riddenKm)
        }.sorted { a, b in
            // Unknown operators sort last. Raw operator names, rather than
            // their shortened labels, keep each company's lines together.
            if a.operatorName != b.operatorName {
                if a.operatorName.isEmpty { return false }
                if b.operatorName.isEmpty { return true }
                if a.operatorName.localizedStandardCompare(b.operatorName) != .orderedSame {
                    return a.operatorName.localizedStandardCompare(b.operatorName) == .orderedAscending
                }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
