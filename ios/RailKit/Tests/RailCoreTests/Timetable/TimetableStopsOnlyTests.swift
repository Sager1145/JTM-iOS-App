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
               OR time_accuracy != 'unknown'
            """) == 0)
        #expect(try count("""
            SELECT COUNT(*) FROM trip_stop_time_overrides
            WHERE arrival_override IS NOT NULL OR departure_override IS NOT NULL
               OR arrival_seconds_override IS NOT NULL OR departure_seconds_override IS NOT NULL
               OR arrival_day_offset_override IS NOT NULL OR departure_day_offset_override IS NOT NULL
            """) == 0)
        // The after-midnight civil day of a call is a calendar fact and stays.
        #expect(try count("SELECT COUNT(DISTINCT trip_id) FROM stop_times WHERE day_offset != 0") >= 8)
        // The stop lists themselves are still there.
        #expect(try count("SELECT COUNT(*) FROM trips") > 800)
        #expect(try count("SELECT COUNT(*) FROM stop_times") > 8_000)
    }

    /// Provenance free text must not carry a copied clock either (HH:MM, H時M分,
    /// 発/着 after an hour). Ids, hashes and ISO timestamps are not clocks, and the
    /// one publication title that names an issue time is allowed.
    @Test func bundledDatabaseTextColumnsCarryNoClockValue() throws {
        let url = try #require(TrainTimetableDatabase.bundledURL(in: .module))
        var connection: OpaquePointer?
        #expect(sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        let clock = try NSRegularExpression(
            pattern: "(?<![0-9A-Za-z:@.+\\-])\\d{1,2}[:：]\\d{2}(?![0-9:])|(?<![0-9-])\\d{1,2}時(?:\\d{1,2}分|(?=[発着]))")
        let allowed = ["JR九州トレインナビ 2026年6月26日8:00 運転計画"]
        func rows(_ sql: String) -> [[String?]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            var result: [[String?]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
            }
            return result
        }
        let tables = rows("SELECT name FROM sqlite_master WHERE type='table'").compactMap { $0[0] }
        var offenders: [String] = []
        var scanned = 0
        for table in tables {
            let columns = rows("PRAGMA table_info(\(table))")
                .filter { ($0[2] ?? "").uppercased() == "TEXT" }.compactMap { $0[1] }
            for column in columns {
                for row in rows("SELECT \(column) FROM \(table) WHERE \(column) IS NOT NULL") {
                    scanned += 1
                    guard let text = row[0], !allowed.contains(text),
                          clock.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                    else { continue }
                    offenders.append("\(table).\(column): \(text.prefix(60))")
                }
            }
        }
        #expect(scanned > 10_000)
        #expect(offenders.isEmpty, "\(offenders.prefix(5))")
        #expect(try count("SELECT COUNT(*) FROM research_queue WHERE missing_dimension = 'times'") == 0)
    }

    @Test func bundledPatternsAndCatalogNotesCarryNoClockValue() throws {
        let clock = try NSRegularExpression(
            pattern: "(?<![0-9A-Za-z:@.+\\-])\\d{1,2}[:：]\\d{2}(?![0-9:])|(?<![0-9-])\\d{1,2}時(?:\\d{1,2}分|(?=[発着]))")
        for name in ["train-service-patterns", "japan-through-services", "line-service-catalog", "train-service-branding"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(clock.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil, "\(name)")
        }
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

    @Test func applyingToTheRouteEditorKeepsIdentityAndLeavesTimesEmpty() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        // Dropping "times" from the required facts keeps verified trips applicable.
        let trip = try #require(trips.first { $0.canApplyToRouteEditor })
        let draft = Train(id: "draft", date: trip.serviceDate, number: "", origin: "", destination: "", stops: [], region: "jp")
        let applied = try #require(trip.applying(to: draft, ridden: false))
        #expect(applied.stops.count >= 2)
        #expect(applied.stops.allSatisfy { $0.arrival == nil && $0.departure == nil })
        #expect(applied.number.hasPrefix(trip.service.canonicalName))
        #expect(applied.company?.isEmpty == false)
        #expect(!(applied.routeSections ?? []).isEmpty)
    }

    @Test func nameOnlyTicketWithAClockNeverMatchesAStopsOnlyTrip() throws {
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
        let trips = try database.trips(on: "2026-09-30")
        let trip = try #require(trips.first { $0.service.id == "akagi" && $0.publicNumber == "3" })
        let calls = trip.passengerStops
        let query = TimetableTicketMatch.Query(
            date: "2026-09-30", serviceName: trip.service.canonicalName, serviceNumber: nil,
            originCode: try #require(calls[1].station.currentSourceCode),
            destinationCode: try #require(calls[3].station.currentSourceCode),
            departureMinutes: 600)
        #expect(TimetableTicketMatch.candidates(for: query, among: trips).isEmpty)
    }

    @Test func ticketMatchUsesNumberDayAndStationsWithoutPublishedTimes() throws {
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
