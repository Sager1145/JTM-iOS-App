import Testing

@testable import RailPresentation

@Suite("SpatialGrid")
struct SpatialGridTests {
    private func brute(_ xs: [Double], _ ys: [Double], _ r: SpatialGrid.Rect) -> [Int] {
        xs.indices.filter {
            xs[$0] >= r.minX && xs[$0] <= r.maxX && ys[$0] >= r.minY && ys[$0] <= r.maxY
        }
    }

    @Test func matchesAFullScanInScanOrder() {
        var xs: [Double] = []
        var ys: [Double] = []
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 1_000
        }
        for _ in 0..<2_000 { xs.append(next()); ys.append(next()) }
        let grid = SpatialGrid(cellSize: 37, xs: xs, ys: ys)
        for rect in [
            SpatialGrid.Rect(minX: 100, minY: 200, maxX: 340, maxY: 410),
            SpatialGrid.Rect(minX: -50, minY: -50, maxX: 20, maxY: 20),
            SpatialGrid.Rect(minX: 0, minY: 0, maxX: 1_000, maxY: 1_000),
            SpatialGrid.Rect(minX: 500, minY: 500, maxX: 500.5, maxY: 500.5),
        ] {
            #expect(grid.indices(in: rect) == brute(xs, ys, rect))
        }
    }

    @Test func rectsLargerThanTheOccupiedGridWalkOccupiedCells() {
        let grid = SpatialGrid(cellSize: 1, xs: [0, 10_000_000], ys: [0, 10_000_000])
        let all = SpatialGrid.Rect(minX: -1e9, minY: -1e9, maxX: 1e9, maxY: 1e9)
        #expect(grid.indices(in: all) == [0, 1])
    }

    @Test func boundariesAreInclusiveAndNegativeCoordinatesWork() {
        let grid = SpatialGrid(cellSize: 10, xs: [-5, 10, 20], ys: [-5, 10, 20])
        #expect(grid.indices(in: .init(minX: -5, minY: -5, maxX: 10, maxY: 10)) == [0, 1])
        #expect(grid.indices(in: .init(minX: 11, minY: 11, maxX: 19, maxY: 19)).isEmpty)
    }

    @Test func emptyOrInvertedQueriesAnswerNothing() {
        let empty = SpatialGrid(cellSize: 10, xs: [], ys: [])
        #expect(empty.indices(in: .init(minX: 0, minY: 0, maxX: 5, maxY: 5)).isEmpty)
        let grid = SpatialGrid(cellSize: 10, xs: [1], ys: [1])
        #expect(grid.indices(in: .init(minX: 5, minY: 0, maxX: 0, maxY: 5)).isEmpty)
    }
}

@Suite("MarkerPassDebt")
struct MarkerPassDebtTests {
    @Test func aRebuildDuringAGestureDefersTheFullPass() {
        #expect(MarkerPassDebt.pass(deferMarkers: true) == .deferred)
        #expect(MarkerPassDebt.pass(deferMarkers: false) == .full)
    }

    @Test func onlyASettledRebuildResetsTheLabelBudget() {
        #expect(!MarkerPassDebt.resetsMovingBudget(duringGesture: true))
        #expect(MarkerPassDebt.resetsMovingBudget(duringGesture: false))
    }

    @Test func theDebtIsOwedUntilAFullPassRuns() {
        var debt = MarkerPassDebt()
        #expect(!debt.isOwed)
        debt.noteDeferred()
        debt.noteDeferred()
        #expect(debt.isOwed)
        debt.noteFullPassRan()
        #expect(!debt.isOwed)
    }
}
