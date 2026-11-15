import Foundation
import Testing
@testable import RailCore

/// Permanent guard (map-lock run 3, finding A): the linear `contains { abs($0 - m) < 1e-9 }`
/// scans in `buildStroke` made low-zoom preparation quadratic (sub-pixel vertices all count
/// as corners). `MeasureMatcher` must answer exactly like the scan, in O(log n) per query.
struct MeasureMatcherTests {
    private struct Generator {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private static func scan(_ list: [Double], _ m: Double) -> Bool {
        list.contains { abs($0 - m) < 1e-9 }
    }

    @Test func matchesTheLinearScanOnRandomInputs() {
        var random = Generator(state: 42)
        for round in 0..<200 {
            let count = Int(random.next() * 60)
            var list = (0..<count).map { _ in (random.next() * 20).rounded() / 4 }
            if round % 5 == 0 { list.append(.nan) }
            if round % 7 == 0 { list.append(.infinity) }
            let matcher = MeasureMatcher(list)
            var queries = list
            for base in list where base.isFinite {
                // On both sides of the 1e-9 tolerance edge.
                queries += [base + 0.5e-9, base - 0.5e-9, base + 1.5e-9, base - 1.5e-9, base + 1e-9, base - 1e-9]
            }
            queries += (0..<40).map { _ in random.next() * 22 - 1 }
            queries += [.nan, .infinity, -.infinity, 0]
            for query in queries {
                #expect(matcher.matches(query) == Self.scan(list, query), "list \(list) query \(query)")
            }
        }
    }

    @Test func emptyListMatchesNothing() {
        #expect(!MeasureMatcher([]).matches(0))
    }

    @Test func queryCostIsLogarithmicOnASubPixelArc() {
        // A 20k-point arc whose vertices are far closer than a pixel: every vertex is a
        // corner candidate, so the list and the queries both have n entries.
        let n = 20_000
        let measures = (0..<n).map { Double($0) * 0.01 }
        let matcher = MeasureMatcher(measures)
        var comparisons = 0
        for measure in measures {
            #expect(matcher.matches(measure, comparisons: &comparisons))
        }
        let bound = n * (Int(log2(Double(n)).rounded(.up)) + 3)
        #expect(comparisons <= bound, "\(comparisons) comparisons for \(n) queries (bound \(bound))")
        // A linear scan would be n * n / 2 here.
        #expect(comparisons < n * n / 100)
    }
}
