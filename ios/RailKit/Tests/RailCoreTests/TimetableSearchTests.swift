import Testing
@testable import RailCore

@Suite("Timetable discovery")
struct TimetableSearchTests {
    @Test func termsCanMatchDifferentFieldsAndUseFullWidthOrKana() {
        let fields = ["あずさ", "Azusa", "３号", "中央本線", "07:00"]
        let stops = ["新宿", "甲府", "松本"]
        #expect(TimetableSearch("AZUSA 松本 ３").matches(fields: fields, stops: stops))
        #expect(TimetableSearch("アズサ 07:00").matches(fields: fields, stops: stops))
        #expect(TimetableSearch("ｱｽﾞｻ　松本").matches(fields: fields, stops: stops))
        #expect(!TimetableSearch("azusa 大阪").matches(fields: fields, stops: stops))
        #expect(TimetableSearch("  ").matches(fields: fields, stops: stops))
    }

    @Test func arrowsRequireOrderedDistinctPassengerCalls() {
        let stops = ["新宿", "甲府", "松本"]
        #expect(TimetableSearch("新宿 → 松本").matches(fields: [], stops: stops))
        #expect(TimetableSearch("新宿 -> 甲府 -> 松本").matches(fields: [], stops: stops))
        #expect(!TimetableSearch("松本 → 新宿").matches(fields: [], stops: stops))
        #expect(!TimetableSearch("新宿 → 新宿").matches(fields: [], stops: stops))
        #expect(!TimetableSearch("新宿 →").matches(fields: [], stops: stops))
        #expect(!TimetableSearch("→ 松本").matches(fields: [], stops: stops))
    }

    @Test func undatedPatternsSupportCatalogEnglishAliases() throws {
        let azusa = try #require(TrainServicePatterns.patterns.first { $0.serviceId == "azusa" })
        #expect(TimetableSearch("AZUSA 松本").matches(azusa))
        #expect(TimetableSearch("アズサ").matches(azusa))
    }

    @Test func bundledEnglishNameTimeAndRouteDiscovery() throws {
        let database = try #require(TrainTimetableDatabase.bundled())
        let trips = try database.trips(on: "2026-09-30")
        let azusa = trips.filter { TimetableSearch("AZUSA 松本").matches($0) }
        #expect(!azusa.isEmpty)
        #expect(azusa.allSatisfy { $0.service.englishName?.lowercased().contains("azusa") == true })
        let trip = try #require(azusa.first)
        if let number = trip.publicNumber {
            #expect(TimetableSearch("あずさ\(number)号").matches(trip))
        }
        let origin = try #require(trip.origin)
        let destination = try #require(trip.destination)
        #expect(TimetableSearch("\(origin.station.name) → \(destination.station.name)").matches(trip))
        #expect(!TimetableSearch("\(destination.station.name) → \(origin.station.name)").matches(trip))
        if let departure = origin.departureTime {
            #expect(TimetableSearch("azusa \(departure)").matches(trip))
        }
    }
}
