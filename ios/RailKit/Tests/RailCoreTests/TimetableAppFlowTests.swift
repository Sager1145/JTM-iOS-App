import Foundation
import SQLite3
import Testing
@testable import RailCore

/// Exercises the dated resource through the same draft and archive boundaries
/// used by the app, without promoting incomplete research to a verified route.
@Suite("Bundled timetable app flow")
struct TimetableAppFlowTests {
    @Test(arguments: ["2013-08-12", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-30"])
    func datedPublishedDraftsSurviveWorkspaceAndArchive(serviceDate: String) throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: serviceDate)
        try #require(!trips.isEmpty)
        var workspace = StoreOperations.Workspace()
        var drafted = 0
        for (index, trip) in trips.enumerated() {
            let base = Train(id: "timetable-\(index)", date: nil, number: "", origin: "",
                             destination: "", stops: [], region: "jp")
            guard let draft = trip.publishedStopsDraft(to: base, ridden: false) else {
                #expect(trip.passengerStops.count < 2, "Missing published draft: \(trip.id)")
                continue
            }
            drafted += 1
            #expect(draft.date == serviceDate)
            #expect(draft.id == base.id)
            #expect(draft.stops.count == trip.passengerStops.count)
            #expect(draft.stops.allSatisfy { $0.rideSegment == false })
            if trip.physicalRouteSections.isEmpty {
                #expect(draft.routeSections == nil)
            } else {
                #expect(draft.routeSections == trip.physicalRouteSections)
                #expect(draft.routeSections?.count == draft.stops.count - 1)
                #expect(draft.routeSections?.allSatisfy {
                    $0.sectionCodes?.isEmpty == false && $0.lineIDs?.isEmpty == false
                } == true)
            }
            #expect(draft.routePolicy == nil)
            #expect(draft.origin == trip.origin?.station.name)
            #expect(draft.destination == trip.destination?.station.name)
            #expect(!(try database.sources(for: trip)).isEmpty, "Missing provenance: \(trip.id)")
            #expect(StoreOperations.addTrain(draft, in: &workspace) == .trainCollectionChanged)
            #expect(workspace.selectedTrainID == draft.id)
            #expect(workspace.focusedTrainID == draft.id)
        }
        try #require(drafted > 0)
        let saved = StoreOperations.exportTrainStore(workspace)
        let parsed = try TrainValidation.JSON.parse(saved)
        #expect(try TrainValidation.validateTrainStore(parsed))
        let nativeStore = try JSONDecoder().decode(TrainStore.self, from: Data(saved.utf8))
        #expect(nativeStore.trains.count == drafted)
        let trainsJSON = try #require(parsed["trains"])
        guard case .array(let rawTrains) = trainsJSON else {
            Issue.record("Export did not contain a train array")
            return
        }
        var restored = StoreOperations.Workspace()
        for rawTrain in rawTrains {
            try StoreOperations.appendImportedTrain(rawTrain, in: &restored)
        }
        #expect(restored.store.trains.count == drafted)
        for (before, after) in zip(workspace.trains, restored.trains) {
            #expect(after.id == before.id)
            #expect(after.date == before.date)
            #expect(after.number == before.number)
            #expect(after.numberEn == before.numberEn)
            #expect(after.region == "jp")
            #expect(after.stops.map(\.name) == before.stops.map(\.name))
            #expect(after.stops.map(\.n02StationCode) == before.stops.map(\.n02StationCode))
            #expect(after.stops.map(\.arrival) == before.stops.map(\.arrival))
            #expect(after.stops.map(\.departure) == before.stops.map(\.departure))
            #expect(after.stops.map(\.platformNumber) == before.stops.map(\.platformNumber))
        }
        #expect(StoreOperations.exportTrainStore(restored) == saved)
    }

    @Test func incompleteBundledOccurrencesCannotInstallRoutes() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: "2026-09-30")
        try #require(!trips.isEmpty)
        let base = Train(id: "draft", date: nil, number: "", origin: "", destination: "",
                         stops: [], region: "jp")
        for trip in trips where !trip.canApplyToRouteEditor {
            #expect(trip.applying(to: base) == nil, "Incomplete route applied: \(trip.id)")
            #expect(trip.compatibilityPattern() == nil, "Incomplete compatibility route: \(trip.id)")
        }
        #expect(trips.contains { !$0.canApplyToRouteEditor })
    }

    @Test func conflictingEditionRemainsQueryableButCannotReplaceDraft() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = packageRoot.appendingPathComponent(
            "Sources/RailCore/Resources/train-service-timetable.sqlite")
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("jtm-conflict-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: source, to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var connection: OpaquePointer?
        try #require(sqlite3_open(temporary.path, &connection) == SQLITE_OK)
        let opened = try #require(connection)
        let status = sqlite3_exec(opened, """
            UPDATE timetable_versions SET completeness = 'conflict'
            WHERE timetable_version_id = (
                SELECT timetable_version_id FROM trips
                WHERE trip_id = 'jr-hokkaido.hokuto.3.exact-2026-09-30'
            );
            """, nil, nil, nil)
        sqlite3_close(opened)
        try #require(status == SQLITE_OK)
        let database = try TrainTimetableDatabase(url: temporary)
        let trip = try #require(try database.trip(
            id: "jr-hokkaido.hokuto.3.exact-2026-09-30", on: "2026-09-30"))
        #expect(trip.timetableCompleteness == .conflict)
        #expect(!trip.passengerStops.isEmpty)
        let draft = Train(id: "existing", date: "2026-09-29", number: "User journey",
                          origin: "A", destination: "B", stops: [], region: "jp")
        #expect(trip.publishedStopsDraft(to: draft) == nil)
        #expect(trip.applying(to: draft) == nil)
        #expect(trip.compatibilityPattern() == nil)
    }

    @Test func exactMatchRejectsDifferentDayClocksAndShorterSegments() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(for: "azusa", on: "2026-09-27")
        let trip = try #require(trips.first)
        let base = Train(id: "match", date: nil, number: "", origin: "", destination: "",
                         stops: [], region: "jp")
        let draft = try #require(trip.publishedStopsDraft(to: base))
        #expect(TimetableTripMatch.candidates(for: draft, among: trips).contains(trip))
        var wrongDate = draft
        wrongDate.date = "2026-09-26"
        #expect(TimetableTripMatch.candidates(for: wrongDate, among: trips).isEmpty)
        var wrongClock = draft
        wrongClock.stops[0].departure = "00:00"
        #expect(TimetableTripMatch.candidates(for: wrongClock, among: trips).isEmpty)
        var shorter = draft
        shorter.stops.removeFirst()
        #expect(TimetableTripMatch.candidates(for: shorter, among: trips).isEmpty)
        var unknownStation = draft
        unknownStation.stops[0].n02StationCode = nil
        #expect(TimetableTripMatch.candidates(for: unknownStation, among: trips).isEmpty)
    }

    @Test func overnightDraftStoresServiceDayAndExtendedClock() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trip = try #require(try database.trip(
            id: "jr-west.west-express-ginga.kumano-night.2026-07-03", on: "2026-09-28"))
        let draft = try #require(trip.publishedStopsDraft(to: Train(
            id: "overnight", date: nil, number: "", origin: "", destination: "", stops: [], region: "jp")))
        #expect(draft.date == "2026-09-28")
        #expect(draft.stops.last?.arrival == "33:35")
        #expect(!draft.stops.contains { $0.name == "和歌山" })
        var workspace = StoreOperations.Workspace()
        StoreOperations.addTrain(draft, in: &workspace)
        let saved = StoreOperations.exportTrainStore(workspace)
        let decoded = try JSONDecoder().decode(TrainStore.self, from: Data(saved.utf8))
        #expect(decoded.trains.first?.date == "2026-09-28")
        #expect(decoded.trains.first?.stops.last?.arrival == "33:35")
    }

    @Test(arguments: ["2026-02-29", "2026-13-01", "2026-09-31", "2026-9-30", "", "__all__"])
    func malformedDatesAreRejectedRatherThanNormalized(serviceDate: String) throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        do {
            _ = try database.trips(on: serviceDate)
            Issue.record("Accepted invalid service date: \(serviceDate)")
        } catch TrainTimetableDatabase.DatabaseError.invalidServiceDate(let rejected) {
            #expect(rejected == serviceDate)
        }
    }

    @Test func exactDayAndSeasonalBoundariesDoNotLeakOccurrences() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let exactID = "jr-hokkaido.hokuto.3.exact-2026-09-30"
        #expect(try database.trip(id: exactID, on: "2026-09-29") == nil)
        #expect(try database.trip(id: exactID, on: "2026-09-30") != nil)
        #expect(try database.trip(id: exactID, on: "2026-10-01") == nil)
        let seasonalID = "jr-central.shinano.81.2013-summer"
        #expect(try database.trip(id: seasonalID, on: "2013-08-01") == nil)
        let early = try #require(try database.trip(id: seasonalID, on: "2013-08-12"))
        #expect(early.stops.first?.departureTime == "08:25")
        #expect(early.serviceDate == "2013-08-12")
    }
}
