import Foundation
import SQLite3
import Testing
@testable import RailCore

@Suite("Train timetable SQLite runtime")
struct TrainTimetableDatabaseTests {
    @Test func publishedDraftUsesOnlyOrderedPassengerCalls() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let query = try database.trip(id: "shinano-1", on: "2026-09-29")
        let template = try #require(query)
        let first = try #require(template.stops.first)
        let last = try #require(template.stops.last)
        func call(_ source: TrainTimetableDatabase.StopTime, type: String)
            -> TrainTimetableDatabase.StopTime {
            .init(sequence: source.sequence, station: source.station,
                  arrivalTime: source.arrivalTime, departureTime: source.departureTime,
                  arrivalSeconds: source.arrivalSeconds, departureSeconds: source.departureSeconds,
                  dayOffset: source.dayOffset, arrivalDayOffset: source.arrivalDayOffset,
                  departureDayOffset: source.departureDayOffset, callType: type,
                  pickupAllowed: source.pickupAllowed, dropoffAllowed: source.dropoffAllowed,
                  platform: source.platform, timeAccuracy: source.timeAccuracy)
        }
        func trip(_ stops: [TrainTimetableDatabase.StopTime]) -> TrainTimetableDatabase.Trip {
            .init(id: template.id, serviceDate: template.serviceDate,
                  timetableVersionID: template.timetableVersionID,
                  timetableEditionName: template.timetableEditionName, service: template.service,
                  calendarID: template.calendarID, trainNumber: template.trainNumber,
                  publicNumber: template.publicNumber, direction: template.direction,
                  serviceClass: template.serviceClass, operationGroupID: template.operationGroupID,
                  notes: template.notes, timetableCompleteness: template.timetableCompleteness,
                  factCompleteness: template.factCompleteness, stops: stops,
                  timetableSymbols: [], lineSegments: [], operatorSegments: template.operatorSegments)
        }
        let draft = Train(id: "passenger-projection", date: nil, number: "",
                          origin: "", destination: "", stops: [], region: "jp")
        let mixed = trip([call(last, type: "pass"), first,
                          call(first, type: "passenger_stop"), last, call(first, type: "pass")])
        let projected = try #require(mixed.publishedStopsDraft(to: draft, ridden: false))
        #expect(projected.origin == first.station.name)
        #expect(projected.destination == last.station.name)
        #expect(projected.stops.map(\.name) == [first.station.name, first.station.name, last.station.name])
        #expect(projected.stops.map(\.stopType) == ["origin", "passenger_stop", "destination"])
        #expect(projected.stops.allSatisfy { $0.rideSegment == false })
        #expect(trip([]).publishedStopsDraft(to: draft) == nil)
        #expect(trip([call(last, type: "pass"), first]).publishedStopsDraft(to: draft) == nil)
    }

    @Test func bundledArtifactColdQueryIsLazyAndIndexed() throws {
        let clock = ContinuousClock()
        let start = clock.now
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: "2026-05-16")
        let elapsed = start.duration(to: clock.now)
        #expect(!trips.isEmpty)
        #expect(!(try database.sources(for: trips[0])).isEmpty)
        #expect(elapsed < .seconds(1))
        print("bundled timetable cold open + date query: \(elapsed)")
    }

    @Test func bundled2013ShinanoFootnoteKeepsItsDateAndReadOnlyStatus() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let id = "jr-central.shinano.81.2013-summer"
        let earlyQuery = try database.trip(id: id, on: "2013-08-12")
        let early = try #require(earlyQuery)
        let regularQuery = try database.trip(id: id, on: "2013-08-03")
        let regular = try #require(regularQuery)
        #expect(early.serviceDate == "2013-08-12")
        #expect(early.stops.first?.departureTime == "08:25")
        #expect(early.stops.first?.departureSeconds == 30_300)
        #expect(regular.stops.first?.departureTime == "08:28")
        #expect(try database.trip(id: id, on: "2013-08-01") == nil)
        #expect(!early.canApplyToRouteEditor)
        #expect(early.stops.count == 2)
        let sources = try database.sources(for: early)
        #expect(sources.contains { $0.id == "jr-central-summer-20130517" })
    }

    @Test func printedNumericPlatformsSurviveEditorProjection() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let draft = Train(id: "platform-check", date: nil, number: "", origin: "",
                          destination: "", stops: [], region: "jp")
        let hokutoQuery = try database.trip(
            id: "jr-hokkaido.hokuto.3.exact-2026-09-30", on: "2026-09-30")
        let hokuto = try #require(hokutoQuery)
        #expect(hokuto.stops.last?.platform == "(7)")
        #expect(hokuto.publishedStopsDraft(to: draft)?.stops.last?.platformNumber == 7)
        let kaijiQuery = try database.trip(
            id: "jr-east.kaiji.2.exact-2026-09-30", on: "2026-09-30")
        let kaiji = try #require(kaijiQuery)
        #expect(kaiji.stops.first { $0.platform == "２" } != nil)
        #expect(kaiji.publishedStopsDraft(to: draft)?.stops.contains { $0.platformNumber == 2 } == true)
    }

    @Test func publishedSymbolsRemainSeparateFromPassengerStops() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let hokutoQuery = try database.trip(
            id: "jr-hokkaido.hokuto.1.exact-2026-09-30", on: "2026-09-30")
        let hokuto = try #require(hokutoQuery)
        #expect(hokuto.timetableSymbols.map(\.stationName) ==
                ["大沼公園", "室蘭", "母恋", "御崎", "輪西", "鷲別", "幌別", "沼ノ端", "千歳"])
        #expect(hokuto.timetableSymbols.map(\.symbol) ==
                ["レ", "||", "||", "||", "||", "レ", "レ", "レ", "レ"])
        #expect(!hokuto.passengerStops.contains { $0.station.name == "大沼公園" })
        #expect(!hokuto.passengerStops.contains { $0.station.name == "室蘭" })

        let hokuto2Query = try database.trip(
            id: "jr-hokkaido.hokuto.2.exact-2026-09-30", on: "2026-09-30")
        let hokuto2 = try #require(hokuto2Query)
        #expect(hokuto2.timetableSymbols.map(\.stationName) ==
                ["千歳", "沼ノ端", "白老", "登別", "幌別", "鷲別", "輪西", "御崎", "母恋", "室蘭",
                 "伊達紋別", "洞爺", "大沼公園", "五稜郭"])
        #expect(hokuto2.timetableSymbols.map(\.symbol) ==
                ["レ", "レ", "レ", "レ", "レ", "レ", "||", "||", "||", "||", "レ", "レ", "レ", "レ"])

        let huisTenBoschQuery = try database.trip(
            id: "jr-kyushu.huis-ten-bosch.11.2026-09-30", on: "2026-09-30")
        let huisTenBosch = try #require(huisTenBoschQuery)
        #expect(huisTenBosch.timetableSymbols.first?.stationName == "佐世保")
        #expect(huisTenBosch.timetableSymbols.first?.symbol == "||")
        #expect(!huisTenBosch.stops.contains { $0.station.name == "佐世保" })
    }

    @Test func bundledPlannedFormationPreservesDateAndCarOrder() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let ibusukiQuery = try database.trip(
            id: "jr-kyushu.ibusuki-no-tamatebako.1.2026-07-01", on: "2026-09-30")
        let ibusuki = try #require(ibusukiQuery)
        let formationQuery = try database.formation(for: ibusuki)
        let formation = try #require(formationQuery)
        #expect(formation.evidenceKind == "planned")
        #expect(formation.serviceDate == "2026-09-30")
        #expect(formation.label == "C")
        #expect(formation.carCount == 2)
        #expect(formation.reservedSeatCapacity == 63)
        #expect(formation.allReserved == true)
        #expect(formation.cars.map(\.number) == ["2", "1"])
        #expect(formation.cars.map(\.vehicleSeries) == ["キハ140", "キハ47"])
        let precedingQuery = try database.trip(
            id: "jr-kyushu.ibusuki-no-tamatebako.1.2026-07-01", on: "2026-09-29")
        let preceding = try #require(precedingQuery)
        #expect(try database.formation(for: preceding) == nil)
        let hokutoQuery = try database.trip(
            id: "jr-hokkaido.hokuto.3.exact-2026-09-30", on: "2026-09-30")
        let hokuto = try #require(hokutoQuery)
        let hokutoFormationQuery = try database.formation(for: hokuto)
        let hokutoFormation = try #require(hokutoFormationQuery)
        #expect(hokutoFormation.allReserved == true)
        #expect(hokutoFormation.greenCarAvailable == true)
        #expect(hokutoFormation.carCount == nil)
        #expect(hokutoFormation.cars.isEmpty)
    }

    @Test func bundledEastVariantsAndKyushuSummerDatesSelectExactOccurrences() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let saturday = try database.trips(for: "azusa", on: "2026-09-26")
        let sunday = try database.trips(for: "azusa", on: "2026-09-27")
        #expect(saturday.count == 1 && sunday.count == 1)
        let selected = try #require(saturday.first)
        let regular = try #require(sunday.first)
        #expect(selected.id != regular.id)
        #expect(selected.trainNumber == "1M" && regular.trainNumber == "1M")
        #expect(selected.stops.count == 12 && regular.stops.count == 12)
        #expect(selected.stops.last?.arrivalTime == "09:43")
        #expect(regular.stops.last?.arrivalTime == "09:38")
        #expect(!selected.canApplyToRouteEditor && !regular.canApplyToRouteEditor)
        let from = try #require(regular.origin)
        let to = try #require(regular.destination)
        let fromCode = try #require(from.station.currentSourceCode)
        let toCode = try #require(to.station.currentSourceCode)
        let departure = try #require(from.departureTime)
        let arrival = try #require(to.arrivalTime)
        let input = Train(
            id: "azusa-lookup", date: "2026-09-27", number: "", origin: from.station.name,
            destination: to.station.name, stops: [
                Stop(name: from.station.name, n02StationCode: fromCode,
                     departure: departure, stopType: "origin"),
                Stop(name: to.station.name, n02StationCode: toCode,
                     arrival: arrival, stopType: "destination"),
            ], region: "jp")
        #expect(TimetableTripMatch.candidates(
            for: input, serviceName: "あずさ", among: sunday).contains(regular))
        #expect(try database.trips(for: "tokiwa", on: "2026-09-18").isEmpty)
        #expect(try database.trips(for: "tokiwa", on: "2026-09-22").count == 1)
        #expect(try database.trips(for: "ibusuki-no-tamatebako", on: "2026-09-28").count == 6)
        #expect(try database.trips(for: "ibusuki-no-tamatebako", on: "2026-09-29").count == 6)
        #expect(try database.trips(named: "Niseko express", on: "2026-09-23").count == 2)
        #expect(try database.trips(on: "2026-09-30").count >= 18)
        #expect(try database.trips(for: "yufuin-no-mori", on: "2026-09-30").count == 6)
        let ginga = try #require(database.trips(for: "west-express-ginga", on: "2026-09-30").first)
        #expect(ginga.trainNumber == "8078M" && ginga.stops.count == 16)
    }

    @Test func sameStationDwellCanCrossMidnightWithoutChangingSourceClocks() throws {
        let fixture = try FixtureDatabase(splitMidnightDwell: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        let stop = try #require(trip.stops.first)
        #expect(trip.serviceDate == "2026-09-29")
        #expect(stop.arrivalTime == "23:42")
        #expect(stop.departureTime == "00:30")
        #expect(stop.arrivalSeconds == 85_320)
        #expect(stop.departureSeconds == 88_200)
        #expect(stop.arrivalDayOffset == 0)
        #expect(stop.departureDayOffset == 1)
    }

    @Test func datedPlatformOverrideCanReplaceOrClearBasePlatform() throws {
        let replaced = try FixtureDatabase(platformOverride: "9")
        defer { replaced.remove() }
        let replacedDatabase = try TrainTimetableDatabase(url: replaced.url)
        let datedQuery = try replacedDatabase.trip(id: "shinano-1", on: "2026-09-29")
        let ordinaryQuery = try replacedDatabase.trip(id: "shinano-1", on: "2026-09-21")
        let dated = try #require(datedQuery)
        let ordinary = try #require(ordinaryQuery)
        #expect(dated.stops.last?.platform == "9")
        #expect(ordinary.stops.last?.platform == "2")

        let cleared = try FixtureDatabase(clearPlatformOverride: true)
        defer { cleared.remove() }
        let clearedDatabase = try TrainTimetableDatabase(url: cleared.url)
        let blankQuery = try clearedDatabase.trip(id: "shinano-1", on: "2026-09-29")
        let blank = try #require(blankQuery)
        #expect(blank.stops.last?.platform == nil)
    }

    @Test func datedTrainNumberOverrideDoesNotChangeBaseTemplate() throws {
        let fixture = try FixtureDatabase(trainNumberOverride: "8071D")
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let datedQuery = try database.trip(id: "shinano-1", on: "2026-09-29")
        let ordinaryQuery = try database.trip(id: "shinano-1", on: "2026-09-21")
        #expect(try #require(datedQuery).trainNumber == "8071D")
        #expect(try #require(ordinaryQuery).trainNumber == "1001M")
    }

    @Test func bundledGingaNightUsesOriginalServiceDateAcrossWakayamaDwell() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let queried = try database.trip(
            id: "jr-west.west-express-ginga.kumano-night.2026-07-03", on: "2026-09-28")
        let trip = try #require(queried)
        let wakayama = try #require(trip.stops.first { $0.station.name == "和歌山" })
        #expect(trip.serviceDate == "2026-09-28")
        #expect(wakayama.arrivalTime == "23:42")
        #expect(wakayama.departureTime == "0:30")
        #expect(wakayama.arrivalSeconds == 85_320)
        #expect(wakayama.departureSeconds == 88_200)
        #expect(wakayama.arrivalDayOffset == 0)
        #expect(wakayama.departureDayOffset == 1)
        #expect(!wakayama.isPassengerCall)
        #expect(!wakayama.pickupAllowed && !wakayama.dropoffAllowed)
        #expect(!trip.canApplyToRouteEditor)
        #expect(trip.stops.last?.arrivalSeconds == 120_900)
    }

    @Test func calendarExceptionsAndOverridesMaterializeExactServiceDay() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)

        // The base calendar runs Monday only, but the explicit remove wins.
        #expect(try database.trips(on: "2026-09-28").isEmpty)

        // Tuesday is added explicitly. The following-day arrival remains part
        // of Tuesday's service occurrence and receives its dated override.
        let trips = try database.trips(on: "2026-09-29")
        let trip = try #require(trips.first)
        #expect(trip.id == "shinano-1")
        #expect(trip.trainNumber == "1001M")
        #expect(trip.stops.count == 2)
        #expect(trip.stops[1].arrivalTime == "25:03")
        #expect(trip.stops[1].arrivalSeconds == 90_180)
        #expect(trip.stops[1].dayOffset == 0)
        #expect(trip.canApplyToRouteEditor)

        let exactInput = Train(
            id: "lookup", date: "2026-09-29", number: "しなの", origin: "名古屋",
            destination: "長野", stops: [
                Stop(name: "名古屋", n02StationCode: "NAGOYA", departure: "23:50", stopType: "origin"),
                Stop(name: "長野", n02StationCode: "NAGANO", arrival: "25:03", stopType: "destination"),
            ], region: "jp")
        #expect(TimetableTripMatch.candidates(for: exactInput, among: trips).map(\.id) == [trip.id])
        var nameOnly = exactInput
        nameOnly.number = ""
        #expect(TimetableTripMatch.candidates(
            for: nameOnly, serviceName: "しなの", among: trips).map(\.id) == [trip.id])
        var wrongTime = exactInput
        wrongTime.stops[1].arrival = "25:04"
        #expect(TimetableTripMatch.candidates(for: wrongTime, among: trips).isEmpty)
        var wrongService = exactInput
        wrongService.number = "ひだ"
        #expect(TimetableTripMatch.candidates(for: wrongService, among: trips).isEmpty)

        let pattern = try #require(trip.compatibilityPattern())
        #expect(pattern.name == "しなの 1号")
        #expect(pattern.stops == ["名古屋", "長野"])
        #expect(pattern.lines == ["中央線"])
        #expect(pattern.validFrom == "2026-09-29")
        #expect(pattern.validUntil == "2026-09-30")

        let draft = Train(
            id: "draft", date: nil, number: "", origin: "", destination: "",
            stops: [], region: "jp")
        let applied = try #require(trip.applying(to: draft, ridden: true))
        #expect(applied.date == "2026-09-29")
        #expect(applied.number == "しなの 1号")
        #expect(applied.stops[0].departure == "23:50")
        #expect(applied.stops[1].arrival == "25:03")
        #expect(applied.routeSections?.count == 1)
        #expect(applied.routeSections?.first?.fromN02StationCode == "NAGOYA")
        #expect(applied.routeSections?.first?.toN02StationCode == "NAGANO")
        #expect(applied.routeSections?.first?.lineNames == ["中央線"])
        #expect(applied.routeSections?.first?.operatorNames == ["JR東海"])
        #expect(applied.routePolicy?.preferredLineNames == ["中央線"])
        #expect(applied.routePolicy?.jrOnly == true)

        let reopened = try JSONDecoder().decode(
            Train.self, from: JSONEncoder().encode(applied))
        #expect(reopened.stops[0].departure == "23:50")
        #expect(reopened.stops[1].arrival == "25:03")
    }

    @Test func indexedTripServiceAndAliasQueriesReturnSameOccurrence() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)

        #expect(try database.trip(id: "shinano-1", on: "2026-09-29")?.id == "shinano-1")
        #expect(Set(try database.trips(for: "shinano", on: "2026-09-29").map(\.id))
                == ["shinano-1", "research-trip"])
        #expect(Set(try database.trips(named: "スーパー", on: "2026-09-29").map(\.id))
                == ["shinano-1", "research-trip"])
        #expect(Set(try database.trips(named: "Shinano", on: "2026-09-29").map(\.id))
                == ["shinano-1", "research-trip"])
        #expect(try database.service(named: "スーパー", on: "2026-09-29").map(\.id) == ["shinano"])
        #expect(try database.coverage(on: "2026-09-29").status == .partial)
    }

    @Test func tripSourcesUnionEditionAndFactProvenanceWithoutInventingMetadata() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)

        let sources = try database.sources(for: trip)
        #expect(sources.map(\.id) == ["fact-source", "version-source"])
        #expect(sources[0].title == "Trip fact page")
        #expect(sources[0].publisher == "Fact Publisher")
        #expect(sources[0].urlOrLocator == "archive:fact")
        #expect(sources[0].licenseStatus == "metadata_only")
        #expect(sources[1].title == "Edition source")
    }

    @Test func applyingNormalizedClockRetainsItsFollowingServiceDay() throws {
        let fixture = try FixtureDatabase(normalizedDayOffsetTime: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        #expect(trip.stops[1].arrivalTime == "01:03")
        #expect(trip.stops[1].dayOffset == 1)
        let draft = Train(id: "draft", date: nil, number: "", origin: "", destination: "",
                          stops: [], region: "jp")
        let applied = try #require(trip.applying(to: draft))
        #expect(applied.stops[1].arrival == "25:03")
        let reopened = try JSONDecoder().decode(Train.self, from: JSONEncoder().encode(applied))
        #expect(reopened.date == "2026-09-29")
        #expect(reopened.stops[1].arrival == "25:03")
    }

    @Test func incompleteTripRemainsQueryableButCannotBecomeEditorRoute() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)

        let queried = try database.trip(id: "research-trip", on: "2026-09-29")
        let trip = try #require(queried)
        #expect(!trip.canApplyToRouteEditor)
        #expect(trip.compatibilityPattern() == nil)
        let empty = Train(id: "draft", number: "", origin: "", destination: "", stops: [], region: "jp")
        let draft = try #require(trip.publishedStopsDraft(to: empty))
        #expect(draft.routeSections == nil)
        #expect(draft.routePolicy == nil)
        #expect(draft.stops.count == trip.passengerStops.count)
        #expect(draft.numberEn?.hasPrefix("Shinano") == true)
    }

    @Test func mixedJRAndPrivateOperatorTripAllowsPrivateRouteSegments() throws {
        let fixture = try FixtureDatabase(mixedOperatorSegments: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        #expect(trip.canApplyToRouteEditor)

        let draft = Train(
            id: "draft", date: nil, number: "", origin: "", destination: "",
            stops: [], region: "jp")
        let applied = try #require(trip.applying(to: draft))
        #expect(applied.routePolicy?.jrOnly == false)
        #expect(applied.routePolicy?.preferredOperatorNames == ["JR東海", "東武鉄道"])
    }

    @Test func routeOnlyLineBoundaryProjectsAnOrderedUntimedPassThrough() throws {
        let fixture = try FixtureDatabase(routeOnlyLineBoundary: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)

        #expect(trip.stops.count == 2)
        #expect(trip.passengerStops.map(\.station.name) == ["水戸", "上野"])
        #expect(!trip.stops.contains { $0.station.name == "日暮里" })
        #expect(trip.lineSegments.count == 2)
        #expect(trip.canApplyToRouteEditor)
        // The passenger-only compatibility projection cannot encode the
        // ordered physical-line boundary and therefore remains unavailable.
        #expect(trip.compatibilityPattern() == nil)
        let draft = Train(
            id: "draft", date: nil, number: "", origin: "", destination: "",
            stops: [], region: "jp")
        let publishedDraft = try #require(trip.publishedStopsDraft(to: draft))
        #expect(publishedDraft.stops.count == 2)
        #expect(!publishedDraft.stops.contains { $0.name == "日暮里" })

        let applied = try #require(trip.applying(to: draft))
        #expect(applied.stops.count == 3)
        #expect(applied.stops.map(\.name) == ["水戸", "日暮里", "上野"])
        #expect(applied.stops[1].n02StationCode == "003417")
        #expect(applied.stops[1].stopType == "pass_through")
        #expect(applied.stops[1].arrival == nil)
        #expect(applied.stops[1].departure == nil)
        #expect(applied.routeSections?.count == 2)
        #expect(applied.routeSections?[0].fromN02StationCode == "002319")
        #expect(applied.routeSections?[0].toN02StationCode == "003417")
        #expect(applied.routeSections?[0].lineNames == ["常磐線"])
        #expect(applied.routeSections?[1].fromN02StationCode == "003417")
        #expect(applied.routeSections?[1].toN02StationCode == "003505")
        #expect(applied.routeSections?[1].lineNames == ["東北線"])
        #expect(applied.routeSections?.allSatisfy { $0.operatorNames == ["JR東日本"] } == true)
    }

    @Test func historicalLineReferenceRemainsQueryableButCannotEnterCurrentEditor() throws {
        let fixture = try FixtureDatabase(historicalLineReference: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        let queried = try database.trip(id: "shinano-1", on: "2026-09-29")
        let trip = try #require(queried)
        let segment = try #require(trip.lineSegments.first)

        #expect(segment.referenceKind == .historicalOverlay)
        #expect(segment.currentN02LineID == nil)
        #expect(segment.railHistoryID == "jp.test.historical-line")
        #expect(!trip.canApplyToRouteEditor)
        #expect(trip.compatibilityPattern() == nil)

        let missingFixture = try FixtureDatabase(missingLineReference: true)
        defer { missingFixture.remove() }
        let missingDatabase = try TrainTimetableDatabase(url: missingFixture.url)
        let missingResult = try missingDatabase.trip(id: "shinano-1", on: "2026-09-29")
        let missingTrip = try #require(missingResult)
        #expect(missingTrip.lineSegments.first?.referenceKind == nil)
        #expect(!missingTrip.canApplyToRouteEditor)
    }

    @Test func malformedDateFailsBeforeSQLiteQuery() throws {
        let fixture = try FixtureDatabase()
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        #expect(throws: TrainTimetableDatabase.DatabaseError.self) {
            _ = try database.trips(on: "2026-02-30")
        }
    }

    @Test func artifactIdentityIsCheckedBeforeQueries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-jtm-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        if let connection { sqlite3_close(connection) }
        #expect(throws: TrainTimetableDatabase.DatabaseError.self) {
            _ = try TrainTimetableDatabase(url: url)
        }
    }

    @Test func holidayPolicyRequiresVerifiedHistoricalCalendar() throws {
        let unverified = try FixtureDatabase(holidayPolicy: "treat_as_sunday")
        defer { unverified.remove() }
        let unsafeDatabase = try TrainTimetableDatabase(url: unverified.url)
        #expect(throws: TrainTimetableDatabase.DatabaseError.self) {
            _ = try unsafeDatabase.trips(on: "2026-09-26")
        }

        let verified = try FixtureDatabase(
            holidayPolicy: "treat_as_sunday", holidayYearStatus: "verified")
        defer { verified.remove() }
        let database = try TrainTimetableDatabase(url: verified.url)
        #expect(try database.trips(on: "2026-09-26").count == 2)
    }

    @Test func unrelatedHolidayCalendarDoesNotBlockQuery() throws {
        let fixture = try FixtureDatabase(unrelatedHolidayCalendar: true)
        defer { fixture.remove() }
        let database = try TrainTimetableDatabase(url: fixture.url)
        #expect(try database.trip(id: "shinano-1", on: "2026-09-29")?.id == "shinano-1")
    }

    @Test func datedStationAndOperatorIdentitiesFailClosedForEditor() throws {
        let stationFixture = try FixtureDatabase(stationValidUntil: "2026-09-29")
        defer { stationFixture.remove() }
        let stationResult = try TrainTimetableDatabase(url: stationFixture.url)
            .trip(id: "shinano-1", on: "2026-09-29")
        let stationTrip = try #require(stationResult)
        #expect(!stationTrip.canApplyToRouteEditor)

        let operatorFixture = try FixtureDatabase(operatorValidUntil: "2026-09-29")
        defer { operatorFixture.remove() }
        let operatorResult = try TrainTimetableDatabase(url: operatorFixture.url)
            .trip(id: "shinano-1", on: "2026-09-29")
        let operatorTrip = try #require(operatorResult)
        #expect(!operatorTrip.canApplyToRouteEditor)

        let boundsFixture = try FixtureDatabase(invalidOperatorSegmentBounds: true)
        defer { boundsFixture.remove() }
        let boundsResult = try TrainTimetableDatabase(url: boundsFixture.url)
            .trip(id: "shinano-1", on: "2026-09-29")
        let boundsTrip = try #require(boundsResult)
        #expect(!boundsTrip.canApplyToRouteEditor)

        let lineOperatorFixture = try FixtureDatabase(mismatchedLineOperatorCoverage: true)
        defer { lineOperatorFixture.remove() }
        let lineOperatorResult = try TrainTimetableDatabase(url: lineOperatorFixture.url)
            .trip(id: "shinano-1", on: "2026-09-29")
        let lineOperatorTrip = try #require(lineOperatorResult)
        #expect(!lineOperatorTrip.canApplyToRouteEditor)
    }

    @Test func nationalAncestralZeroIntervalIsAuthoritative() throws {
        let fixture = try FixtureDatabase(nationalZeroInterval: true)
        defer { fixture.remove() }
        let coverage = try TrainTimetableDatabase(url: fixture.url).coverage(on: "1945-01-01")
        #expect(coverage.status == .verified)
        #expect(coverage.timetableVersionIDs.isEmpty)
    }
}

final class FixtureDatabase {
    let url: URL

    init(
        holidayPolicy: String = "none", holidayYearStatus: String? = nil,
        unrelatedHolidayCalendar: Bool = false,
        stationValidUntil: String? = nil, operatorValidUntil: String? = nil,
        nationalZeroInterval: Bool = false, invalidOperatorSegmentBounds: Bool = false,
        mixedOperatorSegments: Bool = false, normalizedDayOffsetTime: Bool = false,
        splitMidnightDwell: Bool = false,
        routeOnlyLineBoundary: Bool = false, mismatchedLineOperatorCoverage: Bool = false,
        historicalLineReference: Bool = false, missingLineReference: Bool = false,
        platformOverride: String? = nil, clearPlatformOverride: Bool = false,
        trainNumberOverride: String? = nil
    ) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("train-timetable-\(UUID().uuidString).sqlite")
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK, let connection else {
            throw FixtureError.sqlite("open")
        }
        defer { sqlite3_close(connection) }

        try execute(Self.schema, on: connection)
        try execute(Self.data, on: connection)
        if let trainNumberOverride {
            try execute("""
                INSERT INTO trip_train_number_overrides VALUES(
                  'shinano-1', '2026-09-29', '\(trainNumberOverride)', 'fact-source');
                """, on: connection)
        }
        if let platformOverride {
            try execute("""
                UPDATE trip_stop_time_overrides
                SET platform_override = '\(platformOverride)', platform_override_present = 1
                WHERE trip_id = 'shinano-1' AND stop_sequence = 1;
                """, on: connection)
        } else if clearPlatformOverride {
            try execute("""
                UPDATE trip_stop_time_overrides
                SET platform_override = NULL, platform_override_present = 1
                WHERE trip_id = 'shinano-1' AND stop_sequence = 1;
                """, on: connection)
        }
        if splitMidnightDwell {
            try execute("""
                UPDATE stop_times SET arrival_time='23:42', departure_time='00:30',
                  arrival_seconds=85320, departure_seconds=88200,
                  arrival_day_offset=0, departure_day_offset=1
                WHERE trip_id='shinano-1' AND stop_sequence=0;
                """, on: connection)
        }
        if normalizedDayOffsetTime {
            try execute("""
                UPDATE stop_times SET arrival_time = '01:00', day_offset = 1
                WHERE trip_id = 'shinano-1' AND stop_sequence = 1;
                UPDATE trip_stop_time_overrides SET arrival_override = '01:03'
                WHERE trip_id = 'shinano-1' AND stop_sequence = 1;
                """, on: connection)
        }
        if holidayPolicy != "none" {
            try execute(
                "UPDATE calendars SET holiday_policy = '\(holidayPolicy)'; "
                    + "INSERT INTO holiday_dates VALUES('2026-09-26');",
                on: connection)
        }
        if let holidayYearStatus {
            try execute(
                "INSERT INTO holiday_calendar_years VALUES(2026, '\(holidayYearStatus)');",
                on: connection)
        }
        if unrelatedHolidayCalendar {
            try execute("""
                INSERT INTO calendars VALUES('unrelated-holiday', 0,0,0,0,0,0,1,
                  '2026-01-01', '2027-01-01', 'treat_as_sunday');
                """, on: connection)
        }
        if let stationValidUntil {
            try execute(
                "UPDATE station_identities SET valid_until = '\(stationValidUntil)';",
                on: connection)
        }
        if let operatorValidUntil {
            try execute(
                "UPDATE operators SET valid_until = '\(operatorValidUntil)';",
                on: connection)
        }
        if nationalZeroInterval {
            try execute("""
                INSERT INTO verified_zero_service_intervals
                VALUES('wartime-zero', 'jr-ancestral-national-railways', '1944-05-01', '1949-09-01');
                """, on: connection)
        }
        if invalidOperatorSegmentBounds {
            try execute("""
                UPDATE trip_operator_segments
                SET from_sequence = 99, to_sequence = 100
                WHERE trip_id = 'shinano-1';
                """, on: connection)
        }
        if mixedOperatorSegments {
            try execute("""
                INSERT INTO trip_operator_segments VALUES('shinano-1',1,1,'tobu');
                """, on: connection)
        }
        if routeOnlyLineBoundary {
            try execute("""
                INSERT INTO station_identities VALUES(
                  'nippori', '日暮里', 'current_n02', '003417', NULL, NULL, NULL);
                UPDATE station_identities SET name_snapshot = '水戸', current_source_code = '002319'
                WHERE station_id = 'nagoya';
                UPDATE station_identities SET name_snapshot = '上野', current_source_code = '003505'
                WHERE station_id = 'nagano';
                INSERT INTO operators VALUES('jr-east', 'JR東日本', '1987-04-01', NULL);
                DELETE FROM trip_operator_segments WHERE trip_id = 'shinano-1';
                INSERT INTO trip_operator_segments VALUES('shinano-1',0,1,'jr-east');
                DELETE FROM trip_line_segments WHERE trip_id = 'shinano-1';
                INSERT INTO trip_line_segments VALUES(
                  'shinano-1',0,'nagoya','nippori','常磐線','jr-east','high',
                  'current_n02','jp-東日本旅客鉄道-常磐線',NULL);
                INSERT INTO trip_line_segments VALUES(
                  'shinano-1',1,'nippori','nagano','東北線','jr-east','high',
                  'current_n02','jp-東日本旅客鉄道-東北線-2',NULL);
                """, on: connection)
        }
        if mismatchedLineOperatorCoverage {
            try execute("""
                UPDATE trip_line_segments SET operator_id = 'tobu'
                WHERE trip_id = 'shinano-1';
                INSERT INTO trip_operator_segments VALUES('shinano-1',1,1,'tobu');
                """, on: connection)
        }
        if historicalLineReference {
            try execute("""
                UPDATE trip_line_segments
                SET reference_kind = 'historical_overlay', current_n02_line_id = NULL,
                    rail_history_id = 'jp.test.historical-line'
                WHERE trip_id = 'shinano-1';
                """, on: connection)
        }
        if missingLineReference {
            try execute("""
                UPDATE trip_line_segments
                SET reference_kind = NULL, current_n02_line_id = NULL, rail_history_id = NULL
                WHERE trip_id = 'shinano-1';
                """, on: connection)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: url) }

    private func execute(_ sql: String, on connection: OpaquePointer) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(connection, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw FixtureError.sqlite(detail)
        }
    }

    enum FixtureError: Error { case sqlite(String) }

    static let schema = """
        PRAGMA application_id = 0x4A544D54;
        PRAGMA user_version = 1;
        CREATE TABLE source_documents(source_id TEXT PRIMARY KEY, publisher TEXT, title TEXT,
          url_or_locator TEXT, license_status TEXT);
        CREATE TABLE operators(operator_id TEXT PRIMARY KEY, display_name TEXT,
          valid_from TEXT, valid_until TEXT);
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE services(service_id TEXT PRIMARY KEY, canonical_name TEXT, service_class TEXT,
          historical_generation INTEGER, first_verified_date TEXT, last_verified_date TEXT, jr_scope TEXT);
        CREATE TABLE service_name_periods(service_id TEXT, name TEXT, language TEXT,
          valid_from TEXT, valid_until TEXT);
        CREATE TABLE timetable_versions(timetable_version_id TEXT PRIMARY KEY, effective_from TEXT,
          effective_until TEXT, completeness TEXT, edition_name TEXT);
        CREATE TABLE timetable_version_sources(timetable_version_id TEXT, source_id TEXT);
        CREATE TABLE calendars(calendar_id TEXT PRIMARY KEY, monday INTEGER, tuesday INTEGER,
          wednesday INTEGER, thursday INTEGER, friday INTEGER, saturday INTEGER, sunday INTEGER,
          valid_from TEXT, valid_until TEXT, holiday_policy TEXT);
        CREATE TABLE calendar_exceptions(calendar_id TEXT, service_date TEXT, exception_type TEXT);
        CREATE TABLE holiday_dates(service_date TEXT PRIMARY KEY);
        CREATE TABLE holiday_calendar_years(year INTEGER PRIMARY KEY, status TEXT);
        CREATE TABLE station_identities(station_id TEXT PRIMARY KEY, name_snapshot TEXT,
          reference_kind TEXT, current_source_code TEXT, rail_history_id TEXT,
          valid_from TEXT, valid_until TEXT);
        CREATE TABLE trips(trip_id TEXT PRIMARY KEY, timetable_version_id TEXT, service_id TEXT,
          calendar_id TEXT, train_number TEXT, public_number TEXT, origin_station_id TEXT,
          destination_station_id TEXT, direction TEXT, service_class TEXT, operation_group_id TEXT, notes TEXT);
        CREATE TABLE stop_times(trip_id TEXT, stop_sequence INTEGER, station_id TEXT,
          arrival_time TEXT, departure_time TEXT, arrival_seconds INTEGER, departure_seconds INTEGER,
          day_offset INTEGER, call_type TEXT, pickup_allowed INTEGER, dropoff_allowed INTEGER,
          platform TEXT, time_accuracy TEXT, arrival_day_offset INTEGER, departure_day_offset INTEGER);
        CREATE TABLE trip_stop_time_overrides(trip_id TEXT, service_date TEXT, stop_sequence INTEGER,
          arrival_override TEXT, departure_override TEXT, arrival_seconds_override INTEGER,
          departure_seconds_override INTEGER, arrival_day_offset_override INTEGER,
          departure_day_offset_override INTEGER, platform_override TEXT,
          platform_override_present INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE trip_train_number_overrides(trip_id TEXT, service_date TEXT,
          train_number TEXT, source_id TEXT);
        CREATE TABLE trip_operator_segments(trip_id TEXT, from_sequence INTEGER, to_sequence INTEGER,
          operator_id TEXT);
        CREATE TABLE trip_line_segments(trip_id TEXT, sequence INTEGER, from_station_id TEXT,
          to_station_id TEXT, line_name TEXT, operator_id TEXT, confidence TEXT,
          reference_kind TEXT, current_n02_line_id TEXT, rail_history_id TEXT);
        CREATE TABLE fact_sources(entity_type TEXT, entity_id TEXT, source_id TEXT);
        CREATE TABLE fact_completeness(entity_type TEXT, entity_id TEXT, dimension TEXT, status TEXT);
        CREATE TABLE verified_zero_service_intervals(
          interval_id TEXT, operator_scope TEXT, valid_from TEXT, valid_until TEXT);
        CREATE TABLE coverage_declarations(operator_scope TEXT, year INTEGER, dimension TEXT, status TEXT);
        """

    static let data = """
        INSERT INTO metadata VALUES('schema_version', '1.2.0');
        INSERT INTO source_documents VALUES(
          'version-source','Edition Publisher','Edition source','https://example.test/edition','test_only');
        INSERT INTO source_documents VALUES(
          'fact-source','Fact Publisher','Trip fact page','archive:fact','metadata_only');
        INSERT INTO operators VALUES('jr-central', 'JR東海', '1987-04-01', NULL);
        INSERT INTO operators VALUES('tobu', '東武鉄道', '1897-11-01', NULL);
        INSERT INTO services VALUES('shinano', 'しなの', 'limited_express', 1,
          '2026-03-14', NULL, 'jr');
        INSERT INTO service_name_periods VALUES('shinano', 'スーパーしなの', 'ja', '2026-01-01', NULL);
        INSERT INTO service_name_periods VALUES('shinano', 'Shinano', 'en', '2026-01-01', NULL);
        INSERT INTO timetable_versions VALUES('v1', '2026-01-01', '2027-01-01', 'verified', '2026 edition');
        INSERT INTO timetable_version_sources VALUES('v1','version-source');
        INSERT INTO timetable_version_sources VALUES('v1','fact-source');
        INSERT INTO fact_sources VALUES('trip','shinano-1','fact-source');
        INSERT INTO calendars VALUES('monday', 1,0,0,0,0,0,1,
          '2026-01-01', '2026-09-29', 'none');
        INSERT INTO calendar_exceptions VALUES('monday', '2026-09-28', 'remove');
        INSERT INTO calendar_exceptions VALUES('monday', '2026-09-29', 'add');
        INSERT INTO station_identities VALUES('nagoya', '名古屋', 'current_n02', 'NAGOYA', NULL, NULL, NULL);
        INSERT INTO station_identities VALUES('nagano', '長野', 'current_n02', 'NAGANO', NULL, NULL, NULL);
        INSERT INTO trips VALUES('shinano-1','v1','shinano','monday','1001M','1号',
          'nagoya','nagano','outbound','limited_express',NULL,NULL);
        INSERT INTO trips VALUES('research-trip','v1','shinano','monday','9001M','臨時',
          'nagoya','nagano','outbound','limited_express',NULL,'route research pending');
        INSERT INTO stop_times(trip_id,stop_sequence,station_id,arrival_time,departure_time,arrival_seconds,departure_seconds,day_offset,call_type,pickup_allowed,dropoff_allowed,platform,time_accuracy) VALUES('shinano-1',0,'nagoya',NULL,'23:50',NULL,85800,0,
          'origin',1,0,'10','exact');
        INSERT INTO stop_times(trip_id,stop_sequence,station_id,arrival_time,departure_time,arrival_seconds,departure_seconds,day_offset,call_type,pickup_allowed,dropoff_allowed,platform,time_accuracy) VALUES('shinano-1',1,'nagano','25:00',NULL,90000,NULL,0,
          'destination',0,1,'2','exact');
        INSERT INTO trip_stop_time_overrides(trip_id,service_date,stop_sequence,arrival_override,departure_override,arrival_seconds_override,departure_seconds_override) VALUES('shinano-1','2026-09-29',1,
          '25:03',NULL,90180,NULL);
        INSERT INTO stop_times(trip_id,stop_sequence,station_id,arrival_time,departure_time,arrival_seconds,departure_seconds,day_offset,call_type,pickup_allowed,dropoff_allowed,platform,time_accuracy) VALUES('research-trip',0,'nagoya',NULL,'08:00',NULL,28800,0,
          'origin',1,0,NULL,'exact');
        INSERT INTO stop_times(trip_id,stop_sequence,station_id,arrival_time,departure_time,arrival_seconds,departure_seconds,day_offset,call_type,pickup_allowed,dropoff_allowed,platform,time_accuracy) VALUES('research-trip',1,'nagano','11:00',NULL,39600,NULL,0,
          'destination',0,1,NULL,'exact');
        INSERT INTO trip_operator_segments VALUES('shinano-1',0,1,'jr-central');
        INSERT INTO trip_line_segments VALUES(
          'shinano-1',0,'nagoya','nagano','中央線','jr-central','high',
          'current_n02','N02-CENTRAL',NULL);
        INSERT INTO trip_operator_segments VALUES('research-trip',0,1,'jr-central');
        INSERT INTO trip_line_segments VALUES(
          'research-trip',0,'nagoya','nagano','中央線','jr-central','low',NULL,NULL,NULL);
        INSERT INTO fact_completeness VALUES('trip','shinano-1','validity_calendar','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','identity','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','train_number','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','operator','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','origin_destination','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','stops','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','times','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','route_lines','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','station_refs','verified');
        INSERT INTO fact_completeness VALUES('trip','shinano-1','provenance','verified');
        INSERT INTO fact_completeness VALUES('trip','research-trip','stops','partial');
        """
}
