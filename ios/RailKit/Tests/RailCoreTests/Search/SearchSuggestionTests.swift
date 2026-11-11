import Foundation
import Testing
@testable import RailCore

/// Corrections ("Did you mean"), the second pass over weak results, and the
/// empty-box suggestions of the shared search engine.
@Suite struct SearchCorrectionTests {
    /// A reading provider that counts its calls.
    private final class CountingReading: SearchReadingProvider, @unchecked Sendable {
        let lock = NSLock()
        private(set) var calls = 0
        let table: [String: String]
        init(_ table: [String: String]) { self.table = table }
        func latinReading(of text: String) -> String? {
            lock.withLock { calls += 1 }
            return table[text]
        }
    }

    private static let stubReadings = StubSearchReading(["新縮": "shinshuku", "渋矢": "shibuya"])

    /// The shipped Japan data with a stubbed query reading, so the same-reading
    /// cases do not depend on the system's Japanese transcription.
    private static let stubbed: SearchIndex? = SearchEngineFixture.catalog.map {
        SearchIndexBuilder.catalog($0, regionCode: "jp", extraNames: SearchEngineFixture.readings,
                                   readingProvider: stubReadings)
    }

    private let context = SearchContext(regionCode: "jp")

    private func query(_ text: String) throws -> SearchResponse {
        let index = try #require(Self.stubbed)
        return index.query(text, scope: .stations, context: context)
    }

    @Test(arguments: [
        ("shinjkuu", "新宿"), ("いけぶくお", "池袋"), ("渋矢", "渋谷"), ("新縮", "新宿"),
    ])
    func japaneseTyposAreCorrected(typed: String, expected: String) throws {
        let response = try query(typed)
        #expect(response.corrections.map(\.text).contains(expected), "\(typed): \(response.corrections.map(\.text))")
        #expect(response.didYouMean == response.corrections.first)
        #expect(response.corrections.count <= 3)
    }

    @Test func koreanAndTaiwanTyposAreCorrected() throws {
        let korea = try #require(SearchEngineFixture.regionIndex("kr"))
        // 서을 romanizes like 서울 (soul), so the loose key resolves it as an exact
        // match: it is found first, and an exact match carries no correction.
        let seoul = korea.query("서을", scope: .stations, context: SearchContext(regionCode: "kr"))
        #expect(seoul.results.first?.title.hasPrefix("서울") == true)
        #expect(seoul.corrections.isEmpty)

        let taiwan = try #require(SearchEngineFixture.regionIndex("tw"))
        let kaohsiung = taiwan.query("gaoxoing", scope: .stations, context: SearchContext(regionCode: "tw"))
        #expect(kaohsiung.corrections.contains { $0.text.hasPrefix("高雄") }, "\(kaohsiung.corrections.map(\.text))")
    }

    @Test func correctionsAreFewDistinctAndNearestFirst() throws {
        for typed in ["shinjkuu", "Tokoy", "いけぶくお", "渋矢", "新縮", "yamnote", "osaak"] {
            let response = try query(typed)
            let texts = response.corrections.map(\.text)
            #expect(texts.count <= 3, "\(typed)")
            #expect(Set(texts).count == texts.count, "\(typed)")
            let distance = response.corrections.compactMap { correction in
                response.results.first { $0.entity == correction.entity }?.match.editDistance
            }
            #expect(distance == distance.sorted(), "\(typed)")
        }
    }

    @Test func displayTextFollowsTheScriptTyped() throws {
        let latin = try query("shinjkuu")
        let shinjuku = try #require(latin.corrections.first { $0.text == "新宿" })
        #expect(shinjuku.displayText.allSatisfy { $0.isASCII }, "\(shinjuku.displayText)")
        let kana = try query("いけぶくお")
        let ikebukuro = try #require(kana.corrections.first { $0.text == "池袋" })
        #expect(ikebukuro.displayText == "いけぶくろ")
        let kanji = try query("渋矢")
        #expect(kanji.corrections.first { $0.text == "渋谷" }?.displayText == "渋谷")
    }

    @Test func exactMatchesHaveNoCorrection() throws {
        for typed in ["東京", "新宿", "Shinjuku", "しんじゅく"] {
            #expect(try query(typed).corrections.isEmpty, "\(typed)")
        }
    }

    /// Station titles as queries: exact first, nothing to correct.
    @Test func fiveHundredTitlesStayExactWithoutCorrections() throws {
        let index = try #require(Self.stubbed)
        let stations = index.kinds.indices.filter { index.kinds[$0] == .station }
        let step = max(1, stations.count / 500)
        var checked = 0
        for d in stride(from: 0, to: stations.count, by: step).map({ stations[$0] }) {
            let title = index.titles[d]
            let response = index.query(title, scope: .stations, context: context)
            // A title that is also a company or line word is read as that filter.
            guard response.parsed.applied.isEmpty else { continue }
            checked += 1
            #expect(response.results.first?.match.kind == .exact, "\(title)")
            #expect(response.corrections.isEmpty, "\(title)")
        }
        #expect(checked >= 450)
    }

    @Test func secondPassRunsOnlyOnWeakResults() throws {
        let counting = CountingReading(["新縮": "shinshuku"])
        let catalog = try #require(SearchEngineFixture.catalog)
        let index = SearchIndexBuilder.catalog(
            catalog, regionCode: "jp", extraNames: SearchEngineFixture.readings, readingProvider: counting)
        _ = index.query("新宿", scope: .stations, context: context)
        _ = index.query("新", scope: .stations, context: context)
        #expect(counting.calls == 0)
        _ = index.query("新縮", scope: .stations, context: context)
        #expect(counting.calls == 1)
    }

    @Test func aWrongSameReadingKanjiResolvesThroughItsReading() {
        // Two wrong characters: beyond any typo budget, so only the reading can find it.
        let documents = [
            SearchDocument(entity: .station("1"), title: "新宿",
                           names: [.init("しんじゅく", source: .reading)], importance: 1),
            SearchDocument(entity: .station("2"), title: "新橋", importance: 0.5),
        ]
        let withReading = SearchIndex(
            regionCode: "jp", documents: documents, readingProvider: StubSearchReading(["真珠区": "Shinjuku"]))
        let found = withReading.query("真珠区", context: SearchContext(regionCode: "jp"))
        #expect(found.corrections.first?.text == "新宿")
        #expect(found.results.first?.match.kind == .fuzzy)

        let without = SearchIndex(regionCode: "jp", documents: documents, readingProvider: StubSearchReading([:]))
        #expect(without.query("真珠区", context: SearchContext(regionCode: "jp")).corrections.isEmpty)
    }

    @Test func eachWordOfAMultiWordQueryToleratesATypo() {
        let documents = [
            SearchDocument(entity: .station("1"), title: "Shinjuku Gyoen", importance: 0.5),
            SearchDocument(entity: .station("2"), title: "Shibuya Hikarie", importance: 0.5),
        ]
        let index = SearchIndex(regionCode: "jp", documents: documents, readingProvider: StubSearchReading([:]))
        let response = index.query("gyoen shinjkuu", context: SearchContext(regionCode: "jp"))
        #expect(response.results.first?.title == "Shinjuku Gyoen")
        #expect(response.results.first?.match.kind == .fuzzy)
        #expect(response.corrections.first?.text == "Shinjuku Gyoen")
        // Both words spelled right stays a solid match with nothing to correct.
        let exact = index.query("gyoen shinjuku", context: SearchContext(regionCode: "jp"))
        #expect(exact.results.first?.title == "Shinjuku Gyoen")
        #expect(exact.results.first?.match.kind == .substring)
        #expect(exact.corrections.isEmpty)
    }

    @Test func topCompletionWhileTyping() throws {
        let partial = try query("shinj")
        #expect(partial.completion != nil)
        #expect(try query("新宿").completion == nil)
    }

    @Test func systemReadingReadsKanjiAloud() {
        #if canImport(CoreFoundation) && (os(macOS) || os(iOS))
        let reading = SystemSearchReading().latinReading(of: "渋谷")
        #expect(reading?.isEmpty == false)
        #endif
    }
}

@Suite struct SearchEmptyBoxTests {
    private func index() throws -> SearchIndex { try #require(SearchEngineFixture.index) }

    @Test func orderIsRecentFrequentNearbyHubs() throws {
        let index = try index()
        let context = SearchContext(regionCode: "jp")
        let tokyo = try #require(index.query("東京", scope: .stations, context: context).results.first)
        let shinjuku = try #require(index.query("新宿", scope: .stations, context: context).results.first)
        // A box around the least important located station: a few nearby rows, then hubs.
        let remote = try #require(index.kinds.indices.first {
            index.kinds[$0] == .station && index.importance[$0] == 0 && !index.latitudes[$0].isNaN
                && index.titles[$0] != tokyo.title && index.titles[$0] != shinjuku.title
        })
        let lat = Double(index.latitudes[remote]), lon = Double(index.longitudes[remote])
        let box = SearchMapRect(centerLatitude: lat, centerLongitude: lon, latitudeDelta: 0.0006, longitudeDelta: 0.0006)
        let personal = SearchContext(
            regionCode: "jp", recentPicks: [tokyo.entity], recentQueries: ["目黒"],
            rideCounts: [shinjuku.entity: 12], visibleRegion: box)
        let response = index.query("", scope: .stations, context: personal)

        let rank: [SearchMatchKind: Int] = [.recent: 0, .frequent: 1, .browse: 2, .hub: 3]
        let kinds = response.results.map(\.match.kind)
        #expect(kinds.allSatisfy { rank[$0] != nil })
        #expect(kinds.compactMap { rank[$0] } == kinds.compactMap { rank[$0] }.sorted())
        #expect(Array(response.results.prefix(2).map(\.entity)) == [tokyo.entity, shinjuku.entity])
        #expect(Array(kinds.prefix(2)) == [.recent, .frequent])
        #expect(kinds.contains(.browse))
        #expect(kinds.contains(.hub))
        #expect(response.recentQueries == ["目黒"])
        let entities = response.results.map(\.entity)
        #expect(Set(entities).count == entities.count)
        for nearby in response.results where nearby.match.kind == .browse {
            #expect(box.contains(latitude: nearby.latitude ?? 0, longitude: nearby.longitude ?? 0))
        }
    }

    @Test func hubsAreTheStationsServedByMostLines() throws {
        let index = try index()
        let response = index.query("", scope: .stations, context: SearchContext(regionCode: "jp"))
        #expect(!response.results.isEmpty)
        #expect(response.results.allSatisfy { $0.match.kind == .hub && $0.entity.kind == .station })
        let titles = response.results.map(\.title)
        #expect(Set(titles).count == titles.count)
        let top = index.hubDocs.first.map { index.importance[Int($0)] } ?? 0
        #expect(top > 0.5)
        #expect(response.results.allSatisfy { index.importance[Int(index.docByEntity[$0.entity]!)] >= top - 0.5 })
    }
}

@Suite struct RecentSearchStoreTests {
    private func defaults() -> UserDefaults {
        let name = "RecentSearchStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func keepsMostRecentFirstCappedAndPerRegion() {
        let defaults = defaults()
        for text in ["新宿", "shinjuku", "東京", "Tokyo "] {
            RecentSearchStore.record(text, box: .stationPicker, regionCode: "jp", defaults: defaults)
        }
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: defaults)
                == ["Tokyo", "東京", "shinjuku", "新宿"])
        // An equal spelling moves to the front instead of repeating.
        RecentSearchStore.record("SHINJUKU", box: .stationPicker, regionCode: "jp", defaults: defaults)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: defaults).first == "SHINJUKU")
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: defaults).count == 4)
        // Too short, other region, other box.
        RecentSearchStore.record("a", box: .stationPicker, regionCode: "jp", defaults: defaults)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "jp", defaults: defaults).count == 4)
        #expect(RecentSearchStore.load(.stationPicker, regionCode: "tw", defaults: defaults).isEmpty)
        #expect(RecentSearchStore.load(.journeys, regionCode: "jp", defaults: defaults).isEmpty)
        for n in 0..<20 {
            RecentSearchStore.record("query \(n)", box: .journeys, regionCode: "jp", defaults: defaults)
        }
        let capped = RecentSearchStore.load(.journeys, regionCode: "jp", defaults: defaults)
        #expect(capped.count == RecentSearchStore.limit)
        #expect(capped.first == "query 19")
        RecentSearchStore.clear(.journeys, regionCode: "jp", defaults: defaults)
        #expect(RecentSearchStore.load(.journeys, regionCode: "jp", defaults: defaults).isEmpty)
    }
}
