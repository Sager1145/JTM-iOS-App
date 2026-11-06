import Testing

@testable import RailCore

struct ContinuousStrokePointAlongTests {
    typealias Point = ContinuousStroke.Point

    /// The implementation replaced by the binary lower-bound lookup. Keeping
    /// it here makes the test pin every endpoint, duplicate-measure and
    /// subrange choice rather than merely checking approximately plausible
    /// interpolation.
    private func linearReference(
        _ points: [Point], _ cumulative: [Double], _ s: Double, low: Int, high: Int
    ) -> Point {
        if s <= cumulative[low] {
            let a = points[low]
            let b = points[low + 1]
            var length = cumulative[low + 1] - cumulative[low]
            if length == 0 { length = 1 }
            let t = (s - cumulative[low]) / length
            return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        if s >= cumulative[high] {
            let a = points[high - 1]
            let b = points[high]
            var length = cumulative[high] - cumulative[high - 1]
            if length == 0 { length = 1 }
            let t = (s - cumulative[high]) / length
            return Point(x: b.x + (b.x - a.x) * t, y: b.y + (b.y - a.y) * t)
        }
        var index = low + 1
        while index < high && cumulative[index] < s { index += 1 }
        let a = points[index - 1]
        let b = points[index]
        var length = cumulative[index] - cumulative[index - 1]
        if length == 0 { length = 1 }
        let t = (s - cumulative[index - 1]) / length
        return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    @Test func binaryLookupMatchesLinearReferenceAtDuplicatesEndpointsAndSubranges() {
        let points = [
            Point(x: -4, y: 2), Point(x: 0, y: 0), Point(x: 3, y: 4),
            Point(x: 3, y: 4), Point(x: 9, y: 4), Point(x: 9, y: 4),
            Point(x: 12, y: 8), Point(x: 20, y: 8),
        ]
        let cumulative = ContinuousStroke.cumulativeLengths(points)
        let ranges = [(0, 7), (1, 6), (2, 5), (3, 7)]

        for (low, high) in ranges {
            let probes = [
                cumulative[low] - 7, cumulative[low], cumulative[low] + 0.25,
                cumulative[2], cumulative[3], cumulative[4], cumulative[5],
                cumulative[high] - 0.25, cumulative[high], cumulative[high] + 7,
            ]
            for s in probes {
                #expect(
                    ContinuousStroke.pointAlong(
                        points, cumulative, s, low: low, high: high)
                        == linearReference(points, cumulative, s, low: low, high: high),
                    "measure \(s), range \(low)...\(high)")
            }
        }
    }

    @Test func binaryLookupMatchesLinearReferenceAcrossFortyThousandVertices() {
        let points = (0...40_000).map { index -> Point in
            // Repeated points create duplicate cumulative measures alongside
            // irregular positive spans, exercising a nonuniform real lookup.
            if index > 0, index.isMultiple(of: 97) {
                let previous = Double(index - 1)
                return Point(x: previous, y: Double((index - 1) % 31))
            }
            return Point(x: Double(index), y: Double(index % 31))
        }
        let cumulative = ContinuousStroke.cumulativeLengths(points)
        let high = points.count - 1
        let total = cumulative[high]

        var probes = [-1.0, 0, total, total + 1]
        probes += stride(from: 0, through: 1_024, by: 1).map {
            total * Double($0) / 1_024
        }
        probes += stride(from: 97, through: high, by: 97).prefix(64).map {
            cumulative[$0]
        }

        for s in probes {
            #expect(
                ContinuousStroke.pointAlong(points, cumulative, s, low: 0, high: high)
                    == linearReference(points, cumulative, s, low: 0, high: high),
                "measure \(s)")
        }
    }
}
