import Testing
@testable import RailPresentation

@Suite("MapLockWeightedPartition")
struct MapLockWeightedPartition {
    private func flat(_ parts: [[Int]]) -> [Int] { parts.flatMap { $0 }.sorted() }

    @Test func everyIndexAppearsExactlyOnce() {
        let weights = (0..<57).map { ($0 * 37) % 11 * 500 + 10 }
        let parts = RideBuildPartition.partition(weights: weights, maxParts: 4, minimumWeightPerPart: 1000)
        #expect(flat(parts) == Array(0..<57))
        for part in parts { #expect(part == part.sorted()) }
    }

    @Test func neverMoreThanMaxParts() {
        let weights = Array(repeating: 10_000, count: 40)
        #expect(RideBuildPartition.partition(weights: weights, maxParts: 3, minimumWeightPerPart: 1).count <= 3)
        #expect(RideBuildPartition.partition(weights: weights, maxParts: 1, minimumWeightPerPart: 1).count == 1)
    }

    @Test func deterministic() {
        let weights = [5, 900, 40, 900, 7, 3000, 12, 3000, 800]
        let first = RideBuildPartition.partition(weights: weights, maxParts: 4, minimumWeightPerPart: 100)
        for _ in 0..<5 {
            #expect(RideBuildPartition.partition(weights: weights, maxParts: 4, minimumWeightPerPart: 100) == first)
        }
    }

    @Test func underTheThresholdStaysInOnePart() {
        let parts = RideBuildPartition.partition(weights: [10, 20, 30], maxParts: 4, minimumWeightPerPart: 1000)
        #expect(parts == [[0, 1, 2]])
        #expect(RideBuildPartition.partition(weights: [], maxParts: 4, minimumWeightPerPart: 1).isEmpty)
    }

    @Test func heaviestFirstBalancesLoads() {
        // Two huge items must not share a part when two parts are allowed.
        let parts = RideBuildPartition.partition(weights: [5000, 5000, 10, 10], maxParts: 2, minimumWeightPerPart: 100)
        #expect(parts.count == 2)
        #expect(parts.contains { $0.contains(0) } && !parts.contains { $0.contains(0) && $0.contains(1) })
    }
}
