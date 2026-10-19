import Foundation
import RailCore

/// Searches off the caller's actor and returns an outcome tied to the record it started on.
/// Draft and persisted editors choose their own write adapter after accepting that baseline.
public enum RouteRepairSession {
    public struct Result: Sendable {
        public let baseline: Train
        public let advance: RouteRepairFlow.Advance

        public func accepts(_ current: Train?) -> Bool { current == baseline }

        public func summary(text: (String, [String: Localization.Param]) -> String) -> String {
            RouteRepairFlow.summary(
                repaired: advance.repaired, needsChoice: advance.pause == nil ? 0 : 1,
                gaps: advance.gaps, text: text)
        }
    }

    public static func search(
        train: Train, baseline: Train, package: CompactPackage,
        steps: [RouteRepairFlow.Step], repaired: Int = 0,
        gaps: [RouteRepairFlow.GapName] = [],
        loadAliases: @escaping @Sendable ([String], CompactPackage) throws -> [String: String]
    ) async throws -> Result {
        let advance = try await Task.detached(priority: .userInitiated) {
            let aliases = try loadAliases(train.stops.compactMap(\.n02StationCode), package)
            var advance = RouteRepairFlow.advance(
                train: train, package: package, aliases: aliases, steps: steps)
            advance.repaired += repaired
            advance.gaps = gaps + advance.gaps
            return advance
        }.value
        return Result(baseline: baseline, advance: advance)
    }
}
