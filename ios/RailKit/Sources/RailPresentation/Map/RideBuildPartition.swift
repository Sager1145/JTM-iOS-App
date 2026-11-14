import Foundation

/// How a ride-stroke batch is split across worker threads. Requests with the
/// same share key (same chain span in the same frame) always go to the same
/// part, so the first one still builds the points and the rest reuse them,
/// exactly as one thread would. Each part lists its request indices ascending,
/// so merging the parts' answers by original index restores request order.
public enum RideBuildPartition {
    /// Fewest requests worth a thread of their own.
    public static let minimumPerPart = 64

    /// - Parameters:
    ///   - shareKeys: one entry per request, nil for a request that shares nothing.
    ///   - maxParts: the most parts (worker threads) to use.
    public static func partition(shareKeys: [String?], maxParts: Int) -> [[Int]] {
        let count = shareKeys.count
        guard count > 0 else { return [] }
        let parts = max(1, min(maxParts, count / minimumPerPart))
        guard parts > 1 else { return [Array(0..<count)] }
        var groups: [[Int]] = Array(repeating: [], count: parts)
        var assigned: [String: Int] = [:]
        for (index, key) in shareKeys.enumerated() {
            let part: Int
            if let key, let known = assigned[key] {
                part = known
            } else {
                // Least-loaded part, first on ties: deterministic.
                part = groups.indices.min { groups[$0].count < groups[$1].count || (groups[$0].count == groups[$1].count && $0 < $1) }!
                if let key { assigned[key] = part }
            }
            groups[part].append(index)
        }
        return groups.filter { !$0.isEmpty }
    }
}
