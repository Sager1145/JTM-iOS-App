import Foundation
import Testing
@testable import RailCore

struct InternalPerfParityTests {
    @Test("JSNumber integral fast path equals the general algorithm")
    func jsNumberFastPath() {
        var values: [Double] = [0, -0.0, 1, -1, 10, 1e15, -1e15, 9_007_199_254_740_991,
                                -9_007_199_254_740_991, 9_007_199_254_740_992, 1e21, 1e22,
                                0.5, 139, 123456789012345680000, .infinity, -.infinity, .nan]
        values += (0..<200_000).map { Double($0) }
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<150_000 {
            values.append(Double(Int64.random(in: -9_007_199_254_740_991...9_007_199_254_740_991, using: &generator)))
        }
        for _ in 0..<50_000 { values.append(Double.random(in: -200...200) * 1000) }
        for value in values {
            #expect(JSNumber.string(value) == JSNumber.slowString(value), "\(value)")
        }
    }

    @Test("decorated sort equals comparator sort, ties included")
    func sortParity() {
        var trains: [Train] = []
        let dates: [String?] = [nil, "2026-07-03", "2026-07-01", "2025-12-31", "undated"]
        let ids = ["a", "B", "a_b", "a-b", "AB", "ab", "z9", "dup"]
        var rng = SystemRandomNumberGenerator()
        for i in 0..<1500 {
            let m = Int.random(in: 0..<30, using: &rng)
            let stops = Bool.random(using: &rng) ? [] : [Stop(name: "s", departure: String(format: "%02d:%02d", m % 24, m * 2 % 60))]
            trains.append(Train(id: ids.randomElement(using: &rng)! + (i % 3 == 0 ? "" : "\(i % 40)"),
                                date: dates.randomElement(using: &rng)!, number: "", origin: "", destination: "", stops: stops))
        }
        let expected = trains.sorted { Dates.compareByDateAndDeparture($0, $1) < 0 }
        #expect(Dates.sortByDateAndDeparture(trains) == expected)
    }
}
