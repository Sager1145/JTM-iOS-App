import RailCore
import RailPresentation
import Testing

/// The selected trip's station tiers, on three real sample trips.
@Suite("SelectedTripStationTiers")
struct SelectedTripStationTiersTests {
    typealias Tiers = SelectedTripStationTiers
    typealias Fixtures = SelectedTripStationTiersFixtures

    /// Classifies a fixture the way the app does for a recorded trip: first
    /// and last stop are the boundaries, nothing is generated.
    private func stations(
        _ stops: [Fixtures.Stop], transfers: Set<String> = [], inferred: Set<String> = []
    ) -> [Tiers.Station] {
        stops.enumerated().map { index, stop in
            Tiers.Station(
                key: stop.name,
                stationClass: Tiers.stationClass(
                    stopType: stop.stopType,
                    isBoundary: index == 0 || index == stops.count - 1,
                    changesLine: transfers.contains(stop.name),
                    isGenerated: inferred.contains(stop.name), hasTime: false),
                coordinate: Coordinate(lon: stop.lon, lat: stop.lat))
        }
    }

    private func totals(_ ranking: Tiers.Ranking, _ scale: Double, _ layers: Tiers.Layers = .init())
        -> (dots: Int, names: Int)
    {
        ranking.counts(metresPerPoint: scale, layers: layers).values.reduce((0, 0)) {
            ($0.0 + $1.dots, $0.1 + $1.names)
        }
    }

    private func count(_ ranking: Tiers.Ranking, _ stationClass: Tiers.StationClass, _ scale: Double)
        -> (dots: Int, names: Int)
    {
        ranking.counts(metresPerPoint: scale)[stationClass] ?? (0, 0)
    }

    // MARK: - the three trips

    /// 丸ノ内線 大手町→池袋, 8 km: every mark once the trip fills a phone
    /// (about 25 m per point), every name on a larger window.
    @Test func shortMetroHopShowsEveryStationWhenItFillsTheScreen() {
        let ranking = Tiers.rank(stations(Fixtures.marunouchi))
        #expect(totals(ranking, 300) == (2, 2))
        #expect(totals(ranking, 100) == (6, 2))
        #expect(totals(ranking, 25) == (8, 6))
        #expect(totals(ranking, 12) == (8, 8))
    }

    /// 湘南新宿ライン 特別快速 大宮→横浜, 58 km, 22 passing stations: stops
    /// first, passing stations only when zoomed in, their names last.
    @Test func commuterTripShowsStopsBeforePassingStations() {
        let ranking = Tiers.rank(stations(Fixtures.shonanShinjuku))
        #expect(totals(ranking, 2_400) == (2, 2))
        // Fit to a phone: both ends, all seven stops, no passing station.
        #expect(totals(ranking, 180) == (9, 6))
        #expect(count(ranking, .pass, 180) == (0, 0))
        #expect(count(ranking, .pass, 60) == (18, 0))
        #expect(totals(ranking, 5) == (31, 31))
    }

    /// はやぶさ27号 東京→新函館北斗, 780 km, 18 passing stations.
    @Test func shinkansenTripKeepsPassingStationsOffTheOverview() {
        let ranking = Tiers.rank(stations(Fixtures.hayabusa))
        // Fit to a phone: 上野 is 3.6 km from 東京 and waits.
        #expect(totals(ranking, 2_400) == (6, 5))
        #expect(count(ranking, .pass, 180) == (0, 0))
        #expect(count(ranking, .pass, 120) == (18, 0))
        #expect(totals(ranking, 40) == (26, 26))
    }

    @Test func zoomingInNeverRemovesAMarkOrAName() {
        for trip in [Fixtures.marunouchi, Fixtures.shonanShinjuku, Fixtures.hayabusa] {
            let ranking = Tiers.rank(stations(trip, inferred: [trip[2].name]))
            var shownDots: Set<String> = []
            var shownNames: Set<String> = []
            var scale = 8_000.0
            while scale > 1 {
                for stop in trip {
                    let mark = ranking.mark(for: stop.name, metresPerPoint: scale)
                    #expect(mark != nil)
                    if shownDots.contains(stop.name) { #expect(mark?.drawsDot == true) }
                    if shownNames.contains(stop.name) { #expect(mark?.offersName == true) }
                    if mark?.drawsDot == true { shownDots.insert(stop.name) }
                    if mark?.offersName == true {
                        shownNames.insert(stop.name)
                        #expect(mark?.drawsDot == true)
                    }
                }
                scale *= 0.8
            }
            #expect(shownDots.count == trip.count)
            #expect(shownNames.count == trip.count)
        }
    }

    @Test func originAndDestinationAlwaysShowWithNames() {
        for trip in [Fixtures.marunouchi, Fixtures.shonanShinjuku, Fixtures.hayabusa] {
            let ranking = Tiers.rank(stations(trip))
            for name in [trip[0].name, trip[trip.count - 1].name] {
                let mark = ranking.mark(for: name, metresPerPoint: 1_000_000)
                #expect(mark == Tiers.Mark(stationClass: .terminal, drawsDot: true, offersName: true))
            }
        }
    }

    // MARK: - classes

    @Test func aLineChangeStationOutranksOrdinaryStops() {
        // 淡路町 is the closest stop to an end (0.6 km) and shows last as a
        // stop; as the station where the trip changes line it shows first.
        let plain = Tiers.rank(stations(Fixtures.marunouchi))
        let changing = Tiers.rank(stations(Fixtures.marunouchi, transfers: ["淡路町"]))
        #expect(plain.mark(for: "淡路町", metresPerPoint: 55)?.drawsDot == false)
        let mark = changing.mark(for: "淡路町", metresPerPoint: 55)
        #expect(mark == Tiers.Mark(stationClass: .transfer, drawsDot: true, offersName: true))
        #expect(Tiers.labelPriority(.terminal) > Tiers.labelPriority(.transfer))
        #expect(Tiers.labelPriority(.transfer) > Tiers.labelPriority(.stop))
        #expect(Tiers.labelPriority(.stop) > Tiers.labelPriority(.pass))
        #expect(Tiers.labelPriority(.pass) > Tiers.labelPriority(.onRoute))
        // The busiest hub of a tier never outranks the tier above it.
        let classes = Tiers.StationClass.allCases
        for (higher, lower) in zip(classes, classes.dropFirst()) {
            #expect(Tiers.labelPriority(higher, lineCount: 0, isNetworkTerminal: false)
                > Tiers.labelPriority(lower, lineCount: 99, isNetworkTerminal: true))
        }
        #expect(Tiers.labelPriority(.stop, lineCount: 99, isNetworkTerminal: true)
            == Tiers.labelPriority(.stop) + Tiers.maxLabelBonus)
        #expect(Tiers.labelPriority(.stop, lineCount: 3, isNetworkTerminal: false)
            > Tiers.labelPriority(.stop, lineCount: 1, isNetworkTerminal: true))
    }

    @Test func unknownClassIsItsOwnStateNotAPass() {
        #expect(Tiers.stationClass(
            stopType: nil, isBoundary: false, changesLine: false, isGenerated: false, hasTime: false) == .onRoute)
        // The timeline's "inferred passing station": generated, no time.
        #expect(Tiers.stationClass(
            stopType: "pass_through", isBoundary: false, changesLine: false,
            isGenerated: true, hasTime: false) == .onRoute)
        #expect(Tiers.stationClass(
            stopType: "pass_through", isBoundary: false, changesLine: false,
            isGenerated: true, hasTime: true) == .pass)
        #expect(Tiers.stationClass(
            stopType: "pass_through", isBoundary: false, changesLine: true,
            isGenerated: false, hasTime: false) == .pass)
        #expect(Tiers.stationClass(
            stopType: "passenger_stop", isBoundary: false, changesLine: false,
            isGenerated: false, hasTime: false) == .stop)
        #expect(Tiers.stationClass(
            stopType: "passenger_stop", isBoundary: false, changesLine: true,
            isGenerated: false, hasTime: false) == .transfer)
        #expect(Tiers.stationClass(
            stopType: "pass_through", isBoundary: true, changesLine: false,
            isGenerated: false, hasTime: false) == .terminal)

        let inferred = Set(Fixtures.hayabusa.filter { $0.stopType == "pass_through" }.prefix(5).map(\.name))
        let ranking = Tiers.rank(stations(Fixtures.hayabusa, inferred: inferred))
        #expect(count(ranking, .onRoute, 40) == (5, 5))
        #expect(count(ranking, .pass, 40) == (13, 13))
        // On-route marks wait for the same close view as passing stations.
        #expect(count(ranking, .onRoute, 180) == (0, 0))
    }

    @Test func layerSwitchesGateTheirTiers() {
        let ranking = Tiers.rank(stations(Fixtures.shonanShinjuku, inferred: ["西大井"]))
        let scale = 5.0
        #expect(totals(ranking, scale) == (31, 31))
        #expect(totals(ranking, scale, .init(pass: false)) == (9, 9))
        #expect(totals(ranking, scale, .init(stops: false)) == (24, 24))
        #expect(totals(ranking, scale, .init(terminals: false)) == (29, 29))
        #expect(totals(ranking, scale, .init(terminals: false, stops: false, pass: false)) == (0, 0))
        #expect(ranking.mark(for: "西大井", metresPerPoint: scale, layers: .init(pass: false))
            == Tiers.Mark(stationClass: .onRoute, drawsDot: false, offersName: false))
    }

    // MARK: - details

    @Test func theNumbersAreTheStatedOnes() {
        #expect(Tiers.StationClass.allCases.map(Tiers.dotGap) == [0, 10, 12, 20, 20])
        #expect(Tiers.StationClass.allCases.map(Tiers.nameGap) == [0, 10, 36, 64, 64])
        #expect(Tiers.passDotMaxMetresPerPoint == 120)
        #expect(Tiers.passNameMaxMetresPerPoint == 40)
    }

    @Test func aStationShowsFromItsSpacingToHigherRankedStations() throws {
        let ranking = Tiers.rank(stations(Fixtures.marunouchi))
        // 後楽園 is ranked first among the stops: farthest from both ends.
        let rank = try #require(ranking.ranks["後楽園"])
        #expect(rank.separationMetres > 2_600 && rank.separationMetres < 2_900)
        #expect(rank.dotMaxMetresPerPoint == rank.separationMetres / 12)
        #expect(rank.nameMaxMetresPerPoint == rank.separationMetres / 36)
        #expect(ranking.mark(for: "not on this trip", metresPerPoint: 1) == nil)
    }

    @Test func aRepeatedStationKeepsItsHighestClass() {
        var loop = stations(Fixtures.marunouchi)
        loop.append(Tiers.Station(key: "後楽園", stationClass: .pass, coordinate: loop[4].coordinate))
        loop.append(Tiers.Station(key: "淡路町", stationClass: .transfer, coordinate: loop[1].coordinate))
        let ranking = Tiers.rank(loop)
        #expect(ranking.ranks.count == 8)
        #expect(ranking.ranks["後楽園"]?.stationClass == .stop)
        #expect(ranking.ranks["淡路町"]?.stationClass == .transfer)
    }

    @Test func lineChangesComeFromRecordedSectionLines() {
        let sections = [["丸ノ内線"], ["丸ノ内線"], ["中央線"], [], ["山手線"], ["山手線", "埼京線"], ["埼京線"]]
        // Boundary k sits before section k; boundary 6 has no stop.
        let changes = Tiers.lineChangeStopIndices(sectionLineNames: sections) { $0 == 6 ? nil : $0 * 10 }
        // 丸ノ内線→中央線 at boundary 2. An unnamed section proves nothing,
        // and a shared line (山手線 on both sides) is not a change.
        #expect(changes == [20])
        #expect(Tiers.lineChangeStopIndices(sectionLineNames: [["a"]]) { $0 }.isEmpty)
        #expect(Tiers.lineChangeStopIndices(sectionLineNames: []) { $0 }.isEmpty)
    }
}
