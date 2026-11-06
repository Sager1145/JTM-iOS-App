import Testing

@testable import RailCore

/// `Statistics.traversedLines` reduces a ride's matched edges to the lines it
/// actually ran over, dropping station-throat noise below the km threshold.
struct TraversedLinesTests {
    /// Builds a minimal `EdgeIndex` where edge `i` belongs to `names[i]` with
    /// length `kms[i]`. Only `lineName`, `km`, and `lineOperator` matter here.
    private func index(
        names: [String], kms: [Double], operators: [String: String] = [:]
    ) -> Statistics.EdgeIndex {
        var lineOperator = Statistics.OrderedDictionary<String, String>()
        for (name, op) in operators { lineOperator[name] = op }
        return Statistics.EdgeIndex(
            map: [:],
            km: kms,
            mask: Array(repeating: 0, count: names.count),
            lineName: names,
            lineMask: Array(repeating: 0, count: names.count),
            totalKm: kms.reduce(0, +),
            totalsByMask: [:],
            lineTotByCat: Statistics.OrderedDictionary<String, [Int: Double]>(),
            lineOperator: lineOperator)
    }

    @Test func ordersFirstSeenAcrossFourLines() {
        let idx = index(
            names: ["東海道線", "山陽線", "伯備線", "山陰線"],
            kms: [5, 3, 2, 4],
            operators: [
                "東海道線": "JR東海", "山陽線": "JR西日本",
                "伯備線": "JR西日本", "山陰線": "JR西日本",
            ])
        let result = Statistics.traversedLines(edges: [0, 1, 2, 3], index: idx)
        #expect(result.map(\.name) == ["東海道線", "山陽線", "伯備線", "山陰線"])
        #expect(result[0].operatorName == "JR東海")
        #expect(result[1].operatorName == "JR西日本")
        #expect(result.map(\.km) == [5, 3, 2, 4])
    }

    @Test func dropsShortNoiseBetweenTwoRunsOfTheSameLine() {
        // 東海道線(3km) -> 東北線(0.3km, noise) -> 東海道線(2km)
        let idx = index(names: ["東海道線", "東北線", "東海道線"], kms: [3, 0.3, 2])
        let result = Statistics.traversedLines(edges: [0, 1, 2], index: idx)
        #expect(result.map(\.name) == ["東海道線"])
        #expect(result[0].km == 5)
    }

    @Test func fallsBackToTheOnlyMatchWhenNothingClearsTheThreshold() {
        let idx = index(names: ["博多南線"], kms: [0.4])
        let result = Statistics.traversedLines(edges: [0], index: idx)
        #expect(result.map(\.name) == ["博多南線"])
        #expect(result[0].km == 0.4)
    }

    @Test func ignoresUnnamedAndOutOfRangeEdgesAndEmptyInput() {
        let idx = index(names: ["", "東海道線"], kms: [1.5, 5])
        // edge 0 is unnamed, edge 5 is out of range.
        let result = Statistics.traversedLines(edges: [0, 1, 5], index: idx)
        #expect(result.map(\.name) == ["東海道線"])

        #expect(Statistics.traversedLines(edges: [], index: idx) == [])
    }

    @Test func revisitedLineIsUniqueAndOrderedByCentroid() {
        // 山手線's second run (10km, starting at position 3.1) is far larger
        // and later than its first (0.1km at position 0), so its km-weighted
        // centroid (~8.02) lands AFTER 中央線's (~1.6) even though 山手線 was
        // seen first — the centroid rule, not first-seen, decides the order.
        let idx = index(names: ["山手線", "中央線", "山手線"], kms: [0.1, 3, 10])
        let result = Statistics.traversedLines(edges: [0, 1, 2], index: idx)
        #expect(result.map(\.name) == ["中央線", "山手線"])
        #expect(result[0].km == 3)
        #expect(result[1].km == 10.1)
    }

    @Test func relativeFloorDropsAShortLineOnALongRide() {
        // 500km line + 1.2km other line -> floor is 2% of 501.2 = ~10.024km,
        // so the 1.2km line does not qualify even though it clears the 1km absolute floor.
        let idx = index(names: ["東海道新幹線", "在来線throat"], kms: [500, 1.2])
        let result = Statistics.traversedLines(edges: [0, 1], index: idx)
        #expect(result.map(\.name) == ["東海道新幹線"])
    }

    @Test func relativeFloorBoundaryQualifiesAtExactlyOneKm() {
        // total 40km -> floor = max(1, 0.02*40) = max(1, 0.8) = 1.0; a line at
        // exactly 1.0km qualifies because the comparison is >=.
        let idx = index(names: ["幹線", "支線"], kms: [39, 1.0])
        let result = Statistics.traversedLines(edges: [0, 1], index: idx)
        #expect(result.map(\.name) == ["幹線", "支線"])
    }

    @Test func fallbackTieBreakKeepsTheFirstSeenLineOnly() {
        // Two lines, each 0.3km: total 0.6km, floor = max(1, 0.012) = 1.0, so
        // neither qualifies and the fallback's first-maximum-wins tie-break
        // keeps only the first-seen line, A.
        let idx = index(names: ["A", "B"], kms: [0.3, 0.3])
        let result = Statistics.traversedLines(edges: [0, 1], index: idx)
        #expect(result.map(\.name) == ["A"])
    }

    @Test func equalCentroidsBreakTieByFirstSeen() {
        // A, B, B, A with equal 1km edges: by symmetry both lines' km-weighted
        // centroids land at position 2 exactly, so the tie is broken by which
        // line was seen first in the walk — A.
        let idx = index(names: ["A", "B", "B", "A"], kms: [1, 1, 1, 1])
        let result = Statistics.traversedLines(edges: [0, 1, 2, 3], index: idx)
        #expect(result.map(\.name) == ["A", "B"])
    }

    @Test func kyotoClipDoesNotPullSanInForward() {
        // サンライズ出雲: 東海道線(200km, several edges) clips a 0.2km 山陰線
        // station edge at 京都 mid-ride, then continues on 東海道線(100km),
        // 山陽線(180km), 伯備線(138km), and finally its real 山陰線 running
        // (100km) at the very end. First-seen order would pin 山陰線 right
        // after the Kyoto clip; the centroid rule correctly places it last.
        let idx = index(
            names: [
                "東海道線", "東海道線", "東海道線", "山陰線", "東海道線", "山陽線", "伯備線",
                "山陰線",
            ],
            kms: [100, 50, 50, 0.2, 100, 180, 138, 100])
        let result = Statistics.traversedLines(edges: [0, 1, 2, 3, 4, 5, 6, 7], index: idx)
        #expect(result.map(\.name) == ["東海道線", "山陽線", "伯備線", "山陰線"])
        #expect(result.last?.km == 100.2)
    }

    @Test func unnamedEdgesStillAdvanceThePosition() {
        // B(2km) at position 0, an unnamed 20km stretch, A(2km), then B(6km)
        // again. B's centroid depends on the unnamed edge having moved the
        // walk's position forward before A and the second B run are placed:
        // with the advance, B = (2*1 + 6*27)/8 = 20.5 and A = 2*23/2 = 23, so
        // B sorts before A. If unnamed edges did not advance `position`, B's
        // second run would be weighted as if it started right after the
        // first (B = (2*1 + 6*7)/8 = 5.5, A = 23) and A would sort first —
        // the opposite order, which is what this test guards against.
        let idx = index(names: ["B", "", "A", "B"], kms: [2, 20, 2, 6])
        let result = Statistics.traversedLines(edges: [0, 1, 2, 3], index: idx)
        #expect(result.map(\.name) == ["B", "A"])
    }
}
