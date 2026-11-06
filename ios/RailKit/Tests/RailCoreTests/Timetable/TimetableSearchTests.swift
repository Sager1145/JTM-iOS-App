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
        let database = try TrainTimetableDatabase.bundled(bundle: .module)
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
    @Test func timeSeparatorsRemainSignificant() {
        #expect(!TimetableSearch("405").matches(fields: [], stops: [], plainFields: ["10:05", "2024-05-01"]))
        #expect(!TimetableSearch("1005").matches(fields: [], stops: [], plainFields: ["10:05"]))
        #expect(TimetableSearch("Azusa 10:05").matches(fields: ["Azusa"], stops: [], plainFields: ["10:05"]))
    }
    @Test func exactOperatorDoesNotBorrowStationTokens() {
        func pattern(company: String) -> TrainServicePatterns.Pattern {
            .init(id: "precision", serviceId: "test", name: "test", company: company,
                  label: "test", origin: "西船橋", destination: "東京", stopRefs: [],
                  optionalStopRefs: [], via: [], confidence: nil, source: nil)
        }
        RegistryIdentityTestGate.withProvider(Self.discoveryBundle) {
            #expect(!TimetableSearch("JR西").matches(pattern(company: "JR東日本")))
            #expect(TimetableSearch("JR西").matches(pattern(company: "JR西日本")))
            #expect(TimetableSearch("东京地铁").matches(pattern(company: "東京メトロ")))
            #expect(TimetableSearch("东京地铁").matches(pattern(company: "東京都交通局")))
            #expect(!TimetableSearch("Tokyo 地铁").matches(pattern(company: "東京メトロ")))
            let results = TrainServicePatterns.search("JR西")
            let identity = RegistryIdentityCache.identity(forRegion: "jp")
            let west = identity?.operatorIDs(matchingQuery: "JR西") ?? []
            #expect(!results.isEmpty)
            #expect(!west.isEmpty)
            #expect(results.allSatisfy { pattern in
                !Set(identity?.operatorIDs(forCatalogName: pattern.company) ?? []).isDisjoint(with: west)
            })
        }
    }

    private static let discoveryBundle: RegistryIdentityLookup.Provider = { region in
        guard region == "jp" else { return nil }
        return RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1, operatorRecords: [
            "op:jp:west": RegistryOperatorRecord(
                names: ["JR西日本", "西日本旅客鉄道"], label: "JR西日本", identity: "jp.jr-west"),
            "op:jp:east": RegistryOperatorRecord(
                names: ["JR東日本", "東日本旅客鉄道"], label: "JR東日本", identity: "jp.jr-east"),
            "op:jp:metro": RegistryOperatorRecord(
                names: ["東京メトロ"], label: "東京メトロ", identity: "jp.tokyo-metro"),
            "op:jp:toei": RegistryOperatorRecord(
                names: ["東京都交通局"], label: "都営", identity: "jp.toei"),
        ]))
    }
}
