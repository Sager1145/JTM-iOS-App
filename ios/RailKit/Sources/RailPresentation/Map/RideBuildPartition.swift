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

    /// Splits weighted work (one entry per item, e.g. a stroke's vertex count)
    /// across at most `maxParts` parts. Heaviest items first, each into the
    /// least-loaded part (lowest part index on ties, lowest item index among
    /// equal weights), so the split is deterministic and balanced. Every index
    /// appears exactly once; indices ascend within a part. Total weight under
    /// `minimumWeightPerPart` stays in one part.
    public static func partition(weights: [Int], maxParts: Int, minimumWeightPerPart: Int) -> [[Int]] {
        let count = weights.count
        guard count > 0 else { return [] }
        let total = weights.reduce(0) { $0 + max(0, $1) }
        let parts = max(1, min(maxParts, count, total / max(1, minimumWeightPerPart)))
        guard parts > 1 else { return [Array(0..<count)] }
        var loads = Array(repeating: 0, count: parts)
        var groups: [[Int]] = Array(repeating: [], count: parts)
        let order = weights.indices.sorted { left, right in
            weights[left] != weights[right] ? weights[left] > weights[right] : left < right
        }
        for index in order {
            let part = loads.indices.min { loads[$0] != loads[$1] ? loads[$0] < loads[$1] : $0 < $1 }!
            loads[part] += max(0, weights[index])
            groups[part].append(index)
        }
        return groups.filter { !$0.isEmpty }.map { $0.sorted() }
    }
}
