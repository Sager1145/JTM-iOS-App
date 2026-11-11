import Foundation
import SQLite3
import Testing
@testable import RailCore

/// The bundled timetable is stops only: no copied departure or arrival time may
/// ship in the database or the catalog excerpts, and every reader must work
/// without one.
@Suite("Stops-only timetable data")
struct TimetableStopsOnlyTests {
    private func count(_ sql: String) throws -> Int {
        let url = try #require(TrainTimetableDatabase.bundledURL(in: .module))
        var connection: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    @Test func bundledDatabaseStoresNoTimeValue() throws {
        #expect(try count("""
            SELECT COUNT(*) FROM stop_times
            WHERE arrival_time IS NOT NULL OR departure_time IS NOT NULL
               OR arrival_seconds IS NOT NULL OR departure_seconds IS NOT NULL
               OR arrival_day_offset IS NOT NULL OR departure_day_offset IS NOT NULL
               OR day_offset != 0 OR time_accuracy != 'unknown'
            """) == 0)
        #expect(try count("""
            SELECT COUNT(*) FROM trip_stop_time_overrides
            WHERE arrival_override IS NOT NULL OR departure_override IS NOT NULL
               OR arrival_seconds_override IS NOT NULL OR departure_seconds_override IS NOT NULL
               OR arrival_day_offset_override IS NOT NULL OR departure_day_offset_override IS NOT NULL
            """) == 0)
        // The stop lists themselves are still there.
        #expect(try count("SELECT COUNT(*) FROM trips") > 800)
        #expect(try count("SELECT COUNT(*) FROM stop_times") > 8_000)
    }

    @Test func bundledDatabaseCarriesCreditMetadata() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let credits = try #require(try database.credits())
        #expect(credits.timePolicy == "stops_only")
        #expect(credits.statement.contains("No timetable times"))
        #expect(credits.sources.count >= 5)
        #expect(credits.sources.allSatisfy { $0.sources > 0 })
        #expect(credits.sources.map(\.publisher).contains { $0.hasPrefix("JR West") })
    }

    @Test func bundledTripsHaveOrderedStopsAndNoTimes() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        try #require(!trips.isEmpty)
        for trip in trips {
            #expect(trip.stops.map(\.sequence) == trip.stops.map(\.sequence).sorted())
            for stop in trip.stops {
                #expect(stop.arrivalTime == nil && stop.departureTime == nil)
                #expect(stop.arrivalSeconds == nil && stop.departureSeconds == nil)
            }
            #expect(trip.origin?.departureTime == nil)
        }
    }

    @Test func applyingABundledTripFillsStopsAndLeavesTimesForTheReader() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        let trip = try #require(trips.first { $0.canApplyToCurrentStationDirectory })
        let applied = try #require(trip.publishedStopsDraft(
            to: Train(id: "draft", date: trip.serviceDate, number: "", origin: "", destination: "", stops: [], region: "jp"),
            ridden: false))
        #expect(applied.stops.count >= 2)
        #expect(applied.stops.allSatisfy { $0.arrival == nil && $0.departure == nil })
        #expect(applied.stops.allSatisfy { !$0.name.isEmpty })
    }

    @Test func ticketMatchFallsBackToNameDayAndStationsWithoutPublishedTimes() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        let trip = try #require(trips.first { $0.service.id == "akagi" && $0.publicNumber == "3" })
        let calls = trip.passengerStops
        try #require(calls.count >= 4)
        let query = TimetableTicketMatch.Query(
            date: "2026-09-30", serviceName: trip.service.canonicalName, serviceNumber: "0003号",
            originCode: try #require(calls[1].station.currentSourceCode),
            destinationCode: try #require(calls[3].station.currentSourceCode),
            departureMinutes: 600)
        // A printed departure cannot rule out a trip whose database has no time.
        #expect(TimetableTicketMatch.candidates(for: query, among: trips).map(\.id) == [trip.id])
        var other = query
        other.serviceNumber = "0004号"
        #expect(!TimetableTicketMatch.candidates(for: other, among: trips).map(\.id).contains(trip.id))
    }

    @Test func bundledCatalogExcerptsCarryNoTimes() throws {
        let catalog = try LineServiceCatalog.loadBundled()
        try #require(!catalog.trips.isEmpty)
        for trip in catalog.trips {
            #expect(trip.stops.count >= 2)
            #expect(trip.stops.allSatisfy { $0.arrivalSeconds == nil && $0.departureSeconds == nil })
        }
        let url = try #require(Bundle.module.url(forResource: "line-service-catalog", withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("arrivalSeconds") && !text.contains("departureSeconds"))
    }
}
