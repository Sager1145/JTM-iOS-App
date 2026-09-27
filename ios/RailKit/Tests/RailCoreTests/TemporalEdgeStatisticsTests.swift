import Testing
@testable import RailCore

struct TemporalEdgeStatisticsTests {
    private func section(
        _ name: String,
        kind: RouteGraph.TemporalKind,
        validTo: String? = nil,
        historyId: String? = nil,
        from: Coordinate,
        to: Coordinate
    ) -> Statistics.Section {
        Statistics.Section(
            properties: Statistics.SectionProperties(
                n02_003: .string(name),
                n02_004: .string("Op"),
                validTo: validTo,
                historyId: historyId,
                temporalKind: kind),
            coordinates: [from, to])
    }

    private func ride(_ from: Coordinate, _ to: Coordinate) -> Statistics.RouteFeature {
        Statistics.RouteFeature(
            lines: [[from, to]], rideSegment: true, from: nil, to: nil)
    }

    @Test("dated retired ride counts as retired, not current coverage")
    func datedRetiredRideStaysOutOfCurrentCoverage() {
        let currentA = Coordinate(lon: 139.0, lat: 35.0)
        let currentB = Coordinate(lon: 139.01, lat: 35.0)
        let retiredA = Coordinate(lon: 140.0, lat: 36.0)
        let retiredB = Coordinate(lon: 140.02, lat: 36.0)
        let oldA = Coordinate(lon: 141.0, lat: 37.0)
        let oldB = Coordinate(lon: 141.03, lat: 37.0)
        let index = Statistics.buildEdgeIndex(
            sections: [
                section("現行線", kind: .current, from: currentA, to: currentB),
                section(
                    "廃止線", kind: .historical, validTo: "2000-01-01",
                    historyId: "ex.closed", from: retiredA, to: retiredB),
                section(
                    "旧線", kind: .relocatedOld, validTo: "2010-01-01",
                    historyId: "ex.old-bit", from: oldA, to: oldB),
            ],
            country: "jp")
        let currentKm = Statistics.equirectKm(139, 35, 139.01, 35)
        let retiredKm = Statistics.equirectKm(140, 36, 140.02, 36)
        let oldKm = Statistics.equirectKm(141, 37, 141.03, 37)

        #expect(index.totalKm == currentKm)

        let dated = Statistics.collectTrainStatsEntry(
            features: [ride(retiredA, retiredB)], index: index, rideDate: "1990-06-01")
        let datedStats = Statistics.aggregateMileageStats(
            index: index, entries: [dated], country: "jp")
        #expect(datedStats.totalRiddenKm == retiredKm)
        #expect(datedStats.retiredNetworkKm == retiredKm)
        #expect(datedStats.currentNetworkRiddenKm == 0)
        #expect(datedStats.networkKm == 0)
        #expect(datedStats.historicalLineCount == 1)
        #expect(datedStats.historicalUniqueKm == retiredKm)
        #expect(index.totalKm == currentKm)

        let currentRide = Statistics.collectTrainStatsEntry(
            features: [ride(currentA, currentB)], index: index, rideDate: "2020-01-01")
        let currentStats = Statistics.aggregateMileageStats(
            index: index, entries: [currentRide], country: "jp")
        #expect(currentStats.currentNetworkRiddenKm == currentKm)
        #expect(currentStats.totalRiddenKm == currentKm)
        #expect(currentStats.networkKm == currentKm)
        #expect(index.totalKm == currentKm)

        let undated = Statistics.collectTrainStatsEntry(
            features: [ride(retiredA, retiredB)], index: index, rideDate: nil)
        #expect(undated.edges.isEmpty)
        let undatedStats = Statistics.aggregateMileageStats(
            index: index, entries: [undated], country: "jp")
        #expect(undatedStats.retiredNetworkKm == 0)
        #expect(undatedStats.totalRiddenKm == 0)

        let oldRide = Statistics.collectTrainStatsEntry(
            features: [ride(oldA, oldB)], index: index, rideDate: "2005-01-01")
        let oldStats = Statistics.aggregateMileageStats(
            index: index, entries: [oldRide], country: "jp")
        #expect(oldStats.relocatedOldKm == oldKm)
        #expect(oldStats.retiredNetworkKm == 0)
        #expect(oldStats.currentNetworkRiddenKm == 0)
        #expect(oldStats.historicalUniqueKm == oldKm)
        #expect(index.totalKm == currentKm)
    }

    // 留萌線-style in-place retirement: the alignment stays `.current` and only
    // `validTo` moves. That geometry remains the base-map denominator.
    @Test("留萌 in-place retirement (.current + past validTo) stays in totalKm")
    func rumoiInPlaceClosedSectionStaysInTotalKm() {
        let openA = Coordinate(lon: 139.0, lat: 35.0)
        let openB = Coordinate(lon: 139.01, lat: 35.0)
        let closedA = Coordinate(lon: 141.65, lat: 43.90)
        let closedB = Coordinate(lon: 141.67, lat: 43.90)
        let histA = Coordinate(lon: 140.0, lat: 36.0)
        let histB = Coordinate(lon: 140.02, lat: 36.0)
        let index = Statistics.buildEdgeIndex(
            sections: [
                section("現行線", kind: .current, from: openA, to: openB),
                section(
                    "留萌線", kind: .current, validTo: "2026-04-01",
                    from: closedA, to: closedB),
                section(
                    "廃止線", kind: .historical, validTo: "2000-01-01",
                    from: histA, to: histB),
            ],
            country: "jp")
        let openKm = Statistics.equirectKm(139, 35, 139.01, 35)
        let closedKm = Statistics.equirectKm(141.65, 43.90, 141.67, 43.90)
        #expect(index.totalKm == openKm + closedKm)
        #expect(index.currentNetwork.contains(true))
        #expect(index.currentNetwork.filter { $0 }.count == 2)
    }

    @Test("留萌 in-place ride after validTo is riddenAll and retired, not current ridden")
    func rumoiInPlaceRideAfterCloseCountsRetiredNotCurrentRidden() {
        let openA = Coordinate(lon: 139.0, lat: 35.0)
        let openB = Coordinate(lon: 139.01, lat: 35.0)
        let closedA = Coordinate(lon: 141.65, lat: 43.90)
        let closedB = Coordinate(lon: 141.67, lat: 43.90)
        let index = Statistics.buildEdgeIndex(
            sections: [
                section("現行線", kind: .current, from: openA, to: openB),
                section(
                    "留萌線", kind: .current, validTo: "2026-04-01",
                    historyId: "ex.rumoi", from: closedA, to: closedB),
            ],
            country: "jp")
        let openKm = Statistics.equirectKm(139, 35, 139.01, 35)
        let closedKm = Statistics.equirectKm(141.65, 43.90, 141.67, 43.90)
        let totalBefore = index.totalKm
        let entry = Statistics.collectTrainStatsEntry(
            features: [ride(closedA, closedB)], index: index, rideDate: "2026-03-15")
        let stats = Statistics.aggregateMileageStats(
            index: index, entries: [entry], country: "jp", asOf: "2026-04-02")
        #expect(index.totalKm == totalBefore)
        #expect(index.totalKm == openKm + closedKm)
        #expect(stats.riddenAll == closedKm)
        #expect(stats.retiredNetworkKm == closedKm)
        #expect(stats.currentNetworkRiddenKm == 0)
        #expect(stats.totalRiddenKm == closedKm)
        #expect(stats.networkKm == closedKm)
    }

    @Test("留萌 in-place ride with asOf before validTo stays current ridden")
    func rumoiInPlaceRideBeforeValidToStaysCurrentRidden() {
        let closedA = Coordinate(lon: 141.65, lat: 43.90)
        let closedB = Coordinate(lon: 141.67, lat: 43.90)
        let index = Statistics.buildEdgeIndex(
            sections: [
                section(
                    "留萌線", kind: .current, validTo: "2026-04-01",
                    from: closedA, to: closedB),
            ],
            country: "jp")
        let closedKm = Statistics.equirectKm(141.65, 43.90, 141.67, 43.90)
        let entry = Statistics.collectTrainStatsEntry(
            features: [ride(closedA, closedB)], index: index, rideDate: "2026-03-15")
        let stats = Statistics.aggregateMileageStats(
            index: index, entries: [entry], country: "jp", asOf: "2026-03-01")
        #expect(
            Statistics.historicalClassification(
                kind: .current, validFrom: nil, validTo: "2026-04-01", asOf: "2026-03-01"
            ) == nil)
        #expect(stats.currentNetworkRiddenKm == closedKm)
        #expect(stats.retiredNetworkKm == 0)
        #expect(stats.riddenAll == closedKm)
        #expect(index.totalKm == closedKm)
    }

    @Test("historical ridden km stays out of totalKm and riddenAll")
    func historicalRideStaysOutOfTotalKmAndRiddenAll() {
        let histA = Coordinate(lon: 140.0, lat: 36.0)
        let histB = Coordinate(lon: 140.02, lat: 36.0)
        let index = Statistics.buildEdgeIndex(
            sections: [
                section(
                    "廃止線", kind: .historical, validTo: "2000-01-01",
                    historyId: "ex.closed", from: histA, to: histB),
            ],
            country: "jp")
        let retiredKm = Statistics.equirectKm(140, 36, 140.02, 36)
        let entry = Statistics.collectTrainStatsEntry(
            features: [ride(histA, histB)], index: index, rideDate: "1990-06-01")
        let stats = Statistics.aggregateMileageStats(
            index: index, entries: [entry], country: "jp", asOf: "2026-09-24")
        #expect(index.totalKm == 0)
        #expect(stats.riddenAll == 0)
        #expect(stats.networkKm == 0)
        #expect(stats.retiredNetworkKm == retiredKm)
        #expect(stats.totalRiddenKm == retiredKm)
        #expect(stats.currentNetworkRiddenKm == 0)
    }
}
