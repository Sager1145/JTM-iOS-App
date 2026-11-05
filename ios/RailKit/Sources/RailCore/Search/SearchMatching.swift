import Foundation

/// Allocation-free comparison of one query key against one stored key.
enum SearchMatching {
    struct Hit {
        var kind: SearchMatchKind
        var distance: Int
        /// Matched key units start (substring) — 0 otherwise.
        var position: Int
        /// Fuzzy hit against a key prefix rather than the whole key.
        var prefixFuzzy: Bool
    }

    /// Longest query compared fuzzily; longer queries match exactly/prefix/substring only.
    static let maxFuzzyLength = 40
    /// Scratch rows `osa` needs for one call.
    static let rowCapacity = 3 * (maxFuzzyLength + 4)

    /// 32-bit character-bag signature. `popcount(q & ~k)` lower-bounds the
    /// number of query characters missing from the key.
    @inline(__always)
    static func mask<C: Collection>(_ units: C) -> UInt32 where C.Element == UInt16 {
        var m: UInt32 = 0
        for u in units { m |= 1 << UInt32((u &* 0x9E37) >> 11 & 31) }
        return m
    }

    /// Allowed typos for a query key.
    static func budget(_ q: UnsafeBufferPointer<UInt16>, loose: Bool) -> Int {
        let n = q.count
        if loose { return n >= 7 ? 2 : (n >= 4 ? 1 : 0) }
        var han = false, jamo = false, kana = false, latin = false
        for u in q {
            if SearchNormalizer.isHan(u) { han = true }
            else if SearchNormalizer.isJamo(u) { jamo = true }
            else if SearchNormalizer.isKana(u) { kana = true }
            else if SearchNormalizer.isLatinOrDigit(u) { latin = true }
        }
        if latin && !han && !kana && !jamo { return 0 } // Latin typos go through the loose key
        if jamo { return n >= 8 ? 2 : (n >= 4 ? 1 : 0) }
        if han && !kana { return n >= 6 ? 2 : (n >= 3 ? 1 : 0) }
        return n >= 6 ? 2 : (n >= 3 ? 1 : 0)
    }

    /// Exact > prefix > substring > fuzzy (bounded OSA distance, whole key or key prefix).
    @inline(__always)
    static func compare(
        _ q: UnsafeBufferPointer<UInt16>, qMask: UInt32,
        _ key: UnsafeBufferPointer<UInt16>, keyMask: UInt32,
        budget: Int, rows: UnsafeMutablePointer<Int32>
    ) -> Hit? {
        let n = q.count, m = key.count
        guard n > 0, m > 0 else { return nil }
        if n <= m, q[0] == key[0] {
            var equal = true
            for i in 1..<n where q[i] != key[i] { equal = false; break }
            if equal { return Hit(kind: n == m ? .exact : .prefix, distance: 0, position: 0, prefixFuzzy: false) }
        }
        if n < m, (qMask & ~keyMask) == 0 {
            let first = q[0]
            var start = 1
            while start <= m - n {
                if key[start] == first {
                    var equal = true
                    for i in 1..<n where q[i] != key[start + i] { equal = false; break }
                    if equal { return Hit(kind: .substring, distance: 0, position: start, prefixFuzzy: false) }
                }
                start += 1
            }
        }
        guard budget > 0, n <= maxFuzzyLength, m + budget >= n,
              (qMask & ~keyMask).nonzeroBitCount <= budget else { return nil }
        let (full, prefix) = osa(q, key, budget: budget, rows: rows)
        if full <= budget { return Hit(kind: .fuzzy, distance: full, position: 0, prefixFuzzy: false) }
        // Typing in progress: a typo in what has been typed so far.
        if n >= 3, prefix <= budget, prefix < full {
            return Hit(kind: .fuzzy, distance: prefix, position: 0, prefixFuzzy: true)
        }
        return nil
    }

    /// Optimal string alignment distance (Damerau with adjacent transpositions),
    /// bounded: returns `budget + 1` as soon as it cannot finish within budget.
    /// `.full` compares to the whole key; `.prefix` to the best key prefix.
    static func osa(
        _ q: UnsafeBufferPointer<UInt16>, _ key: UnsafeBufferPointer<UInt16>,
        budget: Int, rows: UnsafeMutablePointer<Int32>
    ) -> (full: Int, prefix: Int) {
        let n = q.count
        let width = min(key.count, n + budget) // key columns considered
        let stride = width + 1
        let over = Int32(budget + 1)
        var prev2 = rows, prev = rows + stride, cur = rows + 2 * stride
        for j in 0...width { prev[j] = Int32(j) }
        for i in 1...n {
            cur[0] = Int32(i)
            var rowMin = cur[0]
            let qi = q[i - 1]
            let lo = max(1, i - budget), hi = min(width, i + budget)
            if lo > 1 { cur[lo - 1] = over }
            if lo <= hi {
                for j in lo...hi {
                    let cost: Int32 = qi == key[j - 1] ? 0 : 1
                    var v = min(prev[j - 1] + cost, min(prev[j] + 1, cur[j - 1] + 1))
                    if i > 1, j > 1, qi == key[j - 2], q[i - 2] == key[j - 1] {
                        v = min(v, prev2[j - 2] + 1)
                    }
                    cur[j] = v
                    if v < rowMin { rowMin = v }
                }
            }
            if hi < width { for j in (hi + 1)...width { cur[j] = over } }
            if rowMin > over - 1 { return (budget + 1, budget + 1) }
            let t = prev2; prev2 = prev; prev = cur; cur = t
        }
        let full = key.count <= n + budget ? Int(min(prev[key.count], over)) : budget + 1
        var best = over
        let from = max(1, n - budget)
        if from <= width { for j in from...width where prev[j] < best { best = prev[j] } }
        return (full, Int(best))
    }
}
