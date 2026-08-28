import Foundation
import RailCore
import RailPresentation
import Testing

/// JRM_FLIGHTY_UI_REFACTOR_SPEC.md §5.1's search-field contract.
///
/// The list is asserted field by field rather than by one happy-path query,
/// because the defect this replaces was precisely a *missing* field: the old
/// inline predicate searched six of the eight, and no test noticed because
/// every test searched by train number.
struct JourneySearchMatcherTests {

    static func train(
        id: String = "t-odoriko-1",
        date: String? = "2026-07-26",
        number: String = "踊り子1号",
        direction: String? = "下り",
        trainType: String? = "特急",
        company: String? = "JR東日本",
        origin: String = "東京",
        destination: String = "伊豆急下田",
        stops: [Stop]? = nil
    ) -> Train {
        Train(
            id: id,
            date: date,
            number: number,
            trainType: trainType,
            company: company,
            origin: origin,
            destination: destination,
            direction: direction,
            stops: stops ?? [
                Stop(name: origin, departure: "09:00", rideSegment: true),
                Stop(name: "熱海", arrival: "10:19", departure: "10:20", rideSegment: true),
                Stop(name: destination, arrival: "11:40", rideSegment: false),
            ])
    }

    // MARK: - every field §5.1 names

    @Test(arguments: [
        "t-odoriko",  // record id
        "踊り子",  // service name
        "2026-07-26",  // date
        "下り",  // direction
        "東京",  // origin
        "伊豆急下田",  // destination
        "熱海",  // an intermediate stop
        "特急",  // train type
        "JR東日本",  // operator
    ])
    func everyContractedFieldIsSearchable(needle: String) {
        #expect(JourneySearchMatcher.matches(Self.train(), query: needle))
    }

    /// The two that were missing before this module existed, named on their
    /// own so a regression reads as what it is rather than as one row of a
    /// parameterised failure.
    @Test
    func dateAndDirectionAreSearchable() {
        #expect(JourneySearchMatcher.matches(Self.train(), query: "2026-07"))
        #expect(JourneySearchMatcher.matches(Self.train(), query: "下り"))
    }

    @Test
    func aWordInNoFieldMatchesNothing() {
        #expect(!JourneySearchMatcher.matches(Self.train(), query: "のぞみ"))
    }

    // MARK: - how it matches

    @Test
    func matchingIsCaseInsensitive() {
        let train = Self.train(number: "Odoriko 1", company: "JR East")
        #expect(JourneySearchMatcher.matches(train, query: "odoriko"))
        #expect(JourneySearchMatcher.matches(train, query: "JR EAST"))
    }

    @Test
    func aSubstringIsEnough() {
        #expect(JourneySearchMatcher.matches(Self.train(), query: "伊豆"))
    }

    @Test
    func anEmptyOrBlankQueryMatchesEverything() {
        #expect(JourneySearchMatcher.matches(Self.train(), query: ""))
        #expect(JourneySearchMatcher.matches(Self.train(), query: "   \n "))
    }

    @Test
    func surroundingWhitespaceIsTrimmedRatherThanSearchedFor() {
        #expect(JourneySearchMatcher.matches(Self.train(), query: "  踊り子  "))
    }

    // MARK: - the field list itself

    @Test
    func absentOptionalFieldsContributeNothingRatherThanEmptyStrings() {
        let sparse = Self.train(
            date: nil, direction: nil, trainType: nil, company: nil,
            stops: [Stop(name: "東京", departure: "09:00", rideSegment: true)])
        #expect(!JourneySearchMatcher.fields(of: sparse).contains(""))
        // And an empty query still does not fall through to "matches nothing".
        #expect(JourneySearchMatcher.matches(sparse, query: ""))
    }

    /// §3.2 forbids the record id leading a journey's identity. The field
    /// order is the scan order, and the id is last in it.
    @Test
    func theRecordIdentifierIsLastInTheScanOrder() {
        let fields = JourneySearchMatcher.fields(of: Self.train())
        #expect(fields.first == "踊り子1号")
        #expect(fields.last == "t-odoriko-1")
    }

    // MARK: - the names the record does not carry

    /// A Taiwanese ride, spelled the way a store actually spells one: the
    /// record carries 台北車站 and the stop carries the operator's own code.
    static func taipeiRide() -> Train {
        Train(
            id: "20260802_01_taoyuan_airport_mrt_express",
            date: "2026-08-02",
            number: "桃園機場捷運 直達車",
            trainType: "直達車",
            company: "桃園捷運",
            origin: "機場第二航廈站",
            destination: "台北車站",
            direction: "up",
            stops: [
                Stop(
                    name: "機場第二航廈站", n02StationCode: "TYMC-A13",
                    departure: "13:25", stopType: "origin", rideSegment: true),
                Stop(
                    name: "新北產業園區站", n02StationCode: "TYMC-A3",
                    arrival: "13:50", departure: "13:51", rideSegment: true),
                Stop(
                    name: "台北車站", n02StationCode: "TRTC-BL12",
                    arrival: "14:05", stopType: "destination", rideSegment: false),
            ])
    }

    /// What ``AppLocalization/localizedStationNames(of:)`` hands in for that
    /// ride with the app in English: the names the reader is looking at,
    /// minus the ones the record already spells that way.
    static func englishNames(_ train: Train) -> [String] {
        train.id == taipeiRide().id
            ? ["Airport Terminal 2 Station", "Taipei Main Station",
               "New Taipei Industrial Park Station"]
            : []
    }

    /// The defect. The journey card says "Taipei Main Station" because
    /// `StationNaming` sends 台北車站 through the readings table; typing that
    /// found nothing, because the store is all the matcher could see.
    @Test
    func theNameOnTheScreenIsSearchable() {
        let ride = Self.taipeiRide()
        #expect(
            JourneySearchMatcher.matches(
                ride, query: "Taipei Main Station", alsoNamed: Self.englishNames))
        // A substring of one, and case-folded, like every other field.
        #expect(
            JourneySearchMatcher.matches(ride, query: "taipei main", alsoNamed: Self.englishNames))
        // An intermediate stop's localized name, not only the two endpoints'.
        #expect(
            JourneySearchMatcher.matches(
                ride, query: "Industrial Park", alsoNamed: Self.englishNames))
        // And the spelling the record itself carries still answers.
        #expect(JourneySearchMatcher.matches(ride, query: "台北車站", alsoNamed: Self.englishNames))
    }

    /// The default is *nothing*, and it has to stay nothing: `RailPresentation`
    /// cannot reach the readings table, and a test that passed here without a
    /// caller supplying one would be asserting something the app does not do.
    @Test
    func withoutTheCallersNamesOnlyTheRecordIsSearched() {
        #expect(!JourneySearchMatcher.matches(Self.taipeiRide(), query: "Taipei Main Station"))
        #expect(!JourneySearchMatcher.fields(of: Self.taipeiRide()).contains("Taipei Main Station"))
    }

    /// Producing those names costs a table lookup per stop, so a journey any
    /// recorded field already answers for must not pay for them — that is the
    /// whole reason ``JourneySearchMatcher/matches(_:trimmed:alsoNamed:)``
    /// asks last rather than in the field list's order.
    @Test
    func theCallersNamesAreAskedForOnlyWhenTheRecordHasMissed() {
        let ride = Self.taipeiRide()
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        func names(_ train: Train) -> [String] {
            counter.calls += 1
            return Self.englishNames(train)
        }
        // Every recorded field, in scan order — none of them may ask.
        for needle in ["桃園機場捷運", "機場第二航廈站", "台北車站", "新北產業園區站",
                       "2026-08-02", "up", "直達車", "桃園捷運", "20260802_01"] {
            #expect(JourneySearchMatcher.matches(ride, query: needle, alsoNamed: names))
        }
        #expect(counter.calls == 0)
        // A miss asks exactly once, and a localized hit is still a hit.
        #expect(JourneySearchMatcher.matches(ride, query: "Taipei Main", alsoNamed: names))
        #expect(counter.calls == 1)
        #expect(!JourneySearchMatcher.matches(ride, query: "のぞみ", alsoNamed: names))
        #expect(counter.calls == 2)
    }

    /// §5.1 is reviewed by reading ``JourneySearchMatcher/fields(of:)``, so
    /// the alternate spellings sit with the stations they re-spell rather than
    /// at the end — and the record id stays last regardless.
    @Test
    func theCallersNamesFollowTheStationsTheyRespell() {
        let fields = JourneySearchMatcher.fields(of: Self.taipeiRide(), alsoNamed: Self.englishNames)
        let stops = fields.firstIndex(of: "新北產業園區站")
        let localized = fields.firstIndex(of: "Taipei Main Station")
        let date = fields.firstIndex(of: "2026-08-02")
        #expect(stops != nil && localized != nil && date != nil)
        #expect(stops! < localized!)
        #expect(localized! < date!)
        #expect(fields.last == Self.taipeiRide().id)
    }

    @Test
    func anEmptyLocalizedNameIsNotAField() {
        let fields = JourneySearchMatcher.fields(
            of: Self.taipeiRide(), alsoNamed: { _ in ["", "Taipei Main Station", ""] })
        #expect(!fields.contains(""))
        #expect(fields.contains("Taipei Main Station"))
    }

    // MARK: - filtering a day

    @Test
    func filteringKeepsStoreOrder() {
        let trains = [
            Self.train(id: "a", number: "踊り子1号"),
            Self.train(id: "b", number: "こだま700号"),
            Self.train(id: "c", number: "踊り子9号"),
        ]
        #expect(JourneySearchMatcher.filter(trains, query: "踊り子").map(\.id) == ["a", "c"])
    }

    @Test
    func filteringWithNoQueryReturnsEverythingUntouched() {
        let trains = [Self.train(id: "a"), Self.train(id: "b")]
        #expect(JourneySearchMatcher.filter(trains, query: " ").map(\.id) == ["a", "b"])
    }

    @Test
    func filteringSeesTheCallersNamesToo() {
        let trains = [Self.train(id: "a"), Self.taipeiRide(), Self.train(id: "c")]
        #expect(
            JourneySearchMatcher.filter(
                trains, query: "Taipei Main Station", alsoNamed: Self.englishNames)
                .map(\.id) == [Self.taipeiRide().id])
        #expect(JourneySearchMatcher.filter(trains, query: "Taipei Main Station").isEmpty)
    }
}

/// The localized spellings, through the table that actually ships.
///
/// The suite above states the contract with a hand-written closure, which is
/// the right shape for a contract and proves nothing about the data: it would
/// pass just as happily if `station-readings-tw.json` had never carried an
/// English name for 台北車站, or if the shipped store's stop codes missed its
/// `byCode` index. Both are load-bearing — the app's closure looks a station
/// up by the OPERATOR's own code (`TRTC-BL12`, `TYMC-A13`), which is a
/// dictionary hit or nothing at all — so they are checked against the files.
///
/// This is the arithmetic of `AppLocalization.localizedStationNames(of:)`
/// without the app: one region's engine, chosen here rather than resolved from
/// the ride, because the app target and its `@MainActor` naming engines are
/// out of `swift test`'s reach.
@Suite("JourneySearchMatcher localized names")
struct JourneySearchMatcherLocalizedNameTests {

    static func repoFile(_ path: String) throws -> URL {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appending(path: path)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }
        Issue.record("\(path) not found from \(#filePath)")
        throw CocoaError(.fileNoSuchFile)
    }

    /// `app/data/train-store-tw.json` — the Taiwanese sample, as shipped.
    static func taiwanTrains() throws -> [Train] {
        try JSONDecoder().decode(
            TrainStore.self,
            from: Data(contentsOf: repoFile("app/data/train-store-tw.json"))).trains
    }

    /// `StationReadingsStore`'s decode, which lives in the app target.
    private struct RawRow: Decodable {
        let zhHant: String?
        let zhHans: String?
        let ja: String?
        let en: String?
        enum CodingKeys: String, CodingKey {
            case ja, en
            case zhHant = "zh_Hant"
            case zhHans = "zh_Hans"
        }
        var row: Localization.StationReadingRow {
            .init(zhHant: zhHant, zhHans: zhHans, ja: ja, en: en)
        }
    }
    private struct RawTable: Decodable {
        let country: String?
        let byCode: [String: RawRow]?
        let byName: [String: RawRow]?
    }

    /// Taiwan's naming engine, in one language.
    ///
    /// The catalog is empty on purpose: `stationName` reads the readings table
    /// and never the UI strings, so the 432-key file would only be a second
    /// thing that could fail.
    static func taiwanNaming(_ language: Localization.Language) throws -> Localization {
        let raw = try JSONDecoder().decode(
            RawTable.self, from: Data(contentsOf: repoFile("app/data/station-readings-tw.json")))
        let catalog = try Localization.Catalog(
            data: Data(#"{"sourceLanguage":"en","version":"1.0","strings":{}}"#.utf8))
        return Localization(
            catalog: catalog,
            language: language,
            stationReadings: Localization.StationReadings(
                country: raw.country,
                byCode: (raw.byCode ?? [:]).mapValues(\.row),
                byName: (raw.byName ?? [:]).mapValues(\.row)))
    }

    /// `AppLocalization.localizedStationNames(of:)`, region already settled.
    static func localizedNames(_ naming: Localization) -> (Train) -> [String] {
        { train in
            var names: [String] = []
            names.reserveCapacity(train.stops.count + 2)
            func add(_ recorded: String?, _ code: String?) {
                guard let recorded, !recorded.isEmpty else { return }
                let localized = naming.stationName(recorded, code: code)
                guard !localized.isEmpty, localized != recorded else { return }
                names.append(localized)
            }
            add(train.origin, train.stops.first(where: { $0.stopType == "origin" })?
                .n02StationCode ?? train.stops.first?.n02StationCode)
            add(train.destination, train.stops.first(where: { $0.stopType == "destination" })?
                .n02StationCode ?? train.stops.last?.n02StationCode)
            for stop in train.stops { add(stop.name, stop.n02StationCode) }
            return names
        }
    }

    @Test("the English name on the screen finds the ride the record spells 台北車站")
    func englishFindsWhatTheRecordSpellsInChinese() throws {
        let trains = try Self.taiwanTrains()
        let alsoNamed = Self.localizedNames(try Self.taiwanNaming(.en))
        let byChinese = JourneySearchMatcher.filter(trains, query: "台北車站").map(\.id)
        #expect(!byChinese.isEmpty, "the shipped Taiwanese sample should call at 台北車站")

        // The defect: without the caller's names, the spelling on the screen
        // answered nothing at all.
        #expect(JourneySearchMatcher.filter(trains, query: "Taipei Main Station").isEmpty)

        let byEnglish = JourneySearchMatcher.filter(
            trains, query: "Taipei Main Station", alsoNamed: alsoNamed).map(\.id)
        #expect(byEnglish == byChinese)
    }

    @Test("a Japanese reader searching the same store searches Japanese")
    func japaneseFindsTheJapaneseSpelling() throws {
        let trains = try Self.taiwanTrains()
        let alsoNamed = Self.localizedNames(try Self.taiwanNaming(.ja))
        #expect(
            JourneySearchMatcher.filter(trains, query: "台北駅", alsoNamed: alsoNamed).map(\.id)
                == JourneySearchMatcher.filter(trains, query: "台北車站").map(\.id))
    }

    /// Traditional Chinese is what a Taiwanese store is written in, so the
    /// table's answer is the record's own spelling and every name is dropped
    /// before it reaches the matcher. Asserted rather than assumed: it is what
    /// makes the common case cost nothing.
    @Test("a spelling the record already carries is not searched twice")
    func theActiveLanguageMatchingTheRecordAddsNoFields() throws {
        let trains = try Self.taiwanTrains()
        let alsoNamed = Self.localizedNames(try Self.taiwanNaming(.zhHant))
        let added = trains.reduce(0) { $0 + alsoNamed($1).count }
        #expect(added == 0)
    }

    /// The fast path and the field list, over a store and a table that ship,
    /// with the closure that ships. Same property as
    /// ``JourneySearchMatcherFastPathTests``, now that there is a field the
    /// two walk in different places.
    @Test("the inline walk answers what the field list answers, aliases included")
    func fastPathMatchesFieldList() throws {
        let trains = try Self.taiwanTrains()
        let alsoNamed = Self.localizedNames(try Self.taiwanNaming(.en))
        let needles = [
            "Taipei", "Station", "taipei main", "Zuoying", "MRT", "台北", "桃園",
            "2026", "捷運", "zzz", "-", "t",
        ]
        for needle in needles {
            for train in trains {
                let byFields = JourneySearchMatcher.fields(of: train, alsoNamed: alsoNamed)
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
                #expect(
                    JourneySearchMatcher.matches(train, query: needle, alsoNamed: alsoNamed)
                        == byFields,
                    "\(train.id) disagreed on \(needle)")
            }
        }
    }
}

/// The fast path and the field list may not disagree.
///
/// `matches(_:trimmed:)` walks the fields inline rather than building
/// ``JourneySearchMatcher/fields(of:)`` first, which is what makes a keystroke
/// cheap — and which is also how the two could drift apart, silently, the next
/// time a field is added to one of them. So the contract is checked directly:
/// over the real national store and over queries chosen to land on each field
/// in turn, "some field contains the needle" and "the matcher says yes" have
/// to be the same answer, every time.
@Suite("JourneySearchMatcher fast path")
struct JourneySearchMatcherFastPathTests {

    /// The committed sample store — 201 real journeys, with the spellings a
    /// synthesised record does not have: empty operators, free-text
    /// directions, ids that repeat a station name.
    static func sampleTrains() throws -> [Train] {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appending(path: "app/data/sample-data/sample-full.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try JSONDecoder()
                    .decode(TrainStore.self, from: Data(contentsOf: candidate)).trains
            }
            directory = directory.deletingLastPathComponent()
        }
        Issue.record("app/data/sample-data/sample-full.json not found from \(#filePath)")
        throw CocoaError(.fileNoSuchFile)
    }

    @Test("the inline walk answers exactly what the field list answers")
    func fastPathMatchesFieldList() throws {
        let trains = try Self.sampleTrains()
        #expect(trains.count > 100, "the sample store should be the national one")
        // Queries that land on each field in turn, plus ones that land on
        // nothing — the case that scans every field of every record.
        let needles = [
            "ひかり", "Odoriko", "東京", "新宿", "JR", "2026", "上り", "下り",
            "特急", "9999", "zzz", "-", "t", "京",
        ]
        for needle in needles {
            for train in trains {
                let byFields = JourneySearchMatcher.fields(of: train)
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
                #expect(
                    JourneySearchMatcher.matches(train, query: needle) == byFields,
                    "\(train.id) disagreed on \(needle)")
            }
        }
    }

    @Test("a whitespace-only query still matches everything")
    func blankQuery() throws {
        let trains = try Self.sampleTrains()
        #expect(JourneySearchMatcher.filter(trains, query: "  \n ").count == trains.count)
    }

    @Test("an untrimmed query answers what its trimmed form answers")
    func trimming() throws {
        let trains = try Self.sampleTrains()
        for needle in ["  東京 ", "\tOdoriko\n"] {
            let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(
                JourneySearchMatcher.filter(trains, query: needle).map(\.id)
                    == JourneySearchMatcher.filter(trains, query: trimmed).map(\.id))
        }
    }
}
