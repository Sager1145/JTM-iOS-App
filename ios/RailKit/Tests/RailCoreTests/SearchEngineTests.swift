import Foundation
import Testing
@testable import RailCore

/// The shared search engine against the shipped Japan package (9k stations)
/// and its kana/romaji readings table.
enum SearchEngineFixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let catalog: EditorCatalog? = {
        let url = root.appendingPathComponent("app/public/rail/jp-2025.json")
        guard let data = try? Data(contentsOf: url),
              let directory = try? JSONDecoder().decode(CompactPackage.StationDirectory.self, from: data)
        else { return nil }
        return EditorCatalogBuilder.build(directory.lineSources(regionCode: "jp"))
    }()

    static let readings: [String: [String]] = {
        let url = root.appendingPathComponent("app/data/station-readings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["byCode"] as? [String: [String: Any]] else { return [:] }
        var result: [String: [String]] = [:]
        for (code, row) in rows {
            result[code] = ["kana", "romaji", "zh_Hant", "zh_Hans", "en"]
                .compactMap { row[$0] as? String }.filter { !$0.isEmpty }
        }
        return result
    }()

    static let index: SearchIndex? = catalog.map {
        SearchIndexBuilder.catalog($0, regionCode: "jp", extraNames: readings)
    }
}

struct SearchNormalizerTests {
    private func key(_ text: String) -> [UInt16] { SearchNormalizer.canonical(text) }
    private func loose(_ text: String) -> [UInt16]? { SearchNormalizer.loose(fromCanonical: key(text)) }

    @Test func variantsAndScripts() {
        #expect(key("東京") == key("东京"))
        #expect(key("山手線") == key("山手线"))
        #expect(key("山手綫") == key("山手線"))
        #expect(key("鉄") == key("鐵") && key("鐵") == key("铁"))
        #expect(key("目黒線") == key("目黑线"))
        #expect(key("東急") == key("东急"))
        #expect(key("しんじゅく") == key("シンジュク"))
        #expect(key("ＪＲ東日本") == key("jr東日本"))
        #expect(key("霞ヶ関") == key("霞ケ関"))
        #expect(key("Ōmiya") == key("omiya"))
        #expect(key("Kansai-Kūkō") == key("kansai kuko"))
        // A half-typed Hangul syllable is a key prefix of the finished word.
        #expect(key("서울").starts(with: key("서우")))
        #expect(key("서울").starts(with: key("서울"[...].prefix(1) + "ㅇ")))
    }

    @Test func looseRomaji() {
        let tokyo = loose("tokyo")
        #expect(tokyo != nil)
        for spelling in ["Tōkyō", "Toukyou", "TOKYO", "とうきょう", "トーキョー", "Tookyoo"] {
            #expect(loose(spelling) == tokyo, "\(spelling)")
        }
        #expect(loose("shinjyuku") == loose("しんじゅく"))
        #expect(loose("Shinjuku") == loose("sinzyuku"))
        #expect(loose("tsukiji") == loose("tukizi"))
        #expect(loose("chiba") == loose("tiba"))
        #expect(loose("Shimbashi") == loose("しんばし"))
        #expect(loose("Ohmiya") == loose("おおみや"))
        #expect(loose("fujisawa") == loose("huzisawa"))
        #expect(loose("東京") == nil)
    }

    @Test func boundedDistance() {
        let rows = UnsafeMutablePointer<Int32>.allocate(capacity: SearchMatching.rowCapacity)
        defer { rows.deallocate() }
        func distance(_ a: String, _ b: String, _ budget: Int) -> (Int, Int) {
            let q = Array(a.utf16), k = Array(b.utf16)
            return q.withUnsafeBufferPointer { qb in
                k.withUnsafeBufferPointer { SearchMatching.osa(qb, $0, budget: budget, rows: rows) }
            }
        }
        #expect(distance("tokoy", "tokyo", 2).0 == 1) // transposition
        #expect(distance("kitten", "sitting", 2).0 == 3) // over budget
        #expect(distance("sinzyu", "sinzyuku", 1).1 == 0) // prefix
        #expect(distance("sinjyu", "sinzyuku", 1).1 == 1)
    }
}

struct SearchEngineTests {
    private let context = SearchContext(regionCode: "jp")

    private func top(_ query: String, scope: SearchScope = .all, context: SearchContext? = nil) throws -> SearchResponse {
        let index = try #require(SearchEngineFixture.index)
        return index.query(query, scope: scope, context: context ?? self.context)
    }

    @Test func romajiAndTypos() throws {
        let shinjyuku = try top("shinjyuku", scope: .stations)
        #expect(shinjyuku.results.first?.title == "新宿")
        #expect(shinjyuku.results.first?.match.source == .romaji)

        let tokoy = try top("Tokoy", scope: .stations)
        #expect(tokoy.results.contains { $0.title == "東京" && $0.match.kind == .fuzzy })
        #expect(tokoy.didYouMean?.text == "東京")

        for spelling in ["Tōkyō", "toukyou", "とうきょう", "トウキョウ", "东京"] {
            #expect(try top(spelling, scope: .stations).results.first?.title == "東京", "\(spelling)")
        }
        let kanaTypo = try top("しんじゆく", scope: .stations)
        #expect(kanaTypo.results.first?.title == "新宿")
    }

    @Test func variantLineNameIsAmbiguousBetweenOperators() throws {
        let response = try top("山手綫")
        #expect(response.parsed.applied.isEmpty)
        let suggested = Set(response.parsed.suggested.map(\.entity.id))
        #expect(suggested == ["jp-東日本旅客鉄道-山手線", "jp-神戸市-山手線"])
        #expect(response.results.prefix(2).allSatisfy { $0.title == "山手線" && $0.match.kind == .exact })
        #expect(response.didYouMean == nil)
    }

    @Test func companyAndLineKeywords() throws {
        for query in ["东急 目黑线", "東急 目黒線", "目黒線 東急", "东急目黑线", "Tokyu 目黒線"] {
            let response = try top(query)
            #expect(response.parsed.applied.map(\.entity) == [.company("jp|東急電鉄"), .line("jp-東急電鉄-目黒線")]
                    || response.parsed.applied.map(\.entity) == [.line("jp-東急電鉄-目黒線"), .company("jp|東急電鉄")]
                    || response.parsed.applied.contains { $0.entity == .line("jp-東急電鉄-目黒線") }, "\(query)")
            #expect(response.results.first?.entity == .line("jp-東急電鉄-目黒線"), "\(query)")
            #expect(response.results.dropFirst().allSatisfy {
                $0.entity.kind != .station || $0.lineIDs.contains("jp-東急電鉄-目黒線") }, "\(query)")
        }
        let station = try top("JR東日本 新宿駅")
        #expect(station.parsed.typeHint == .stations)
        #expect(station.parsed.applied.first?.title == "東日本旅客鉄道")
        #expect(station.results.first?.title == "新宿")
        #expect(station.results.allSatisfy { $0.entity.kind == .station })

        let english = try top("JR East")
        #expect(english.parsed.applied.first?.title == "東日本旅客鉄道")
        let metro = try top("tokyo metro")
        #expect(metro.parsed.applied.first?.title == "東京メトロ")
    }

    @Test func rankingTiers() throws {
        let tokyo = try top("東京", scope: .stations)
        #expect(tokyo.results.first?.title == "東京")
        #expect(tokyo.results.first?.match.kind == .exact)
        let kinds = tokyo.results.map(\.match.kind)
        #expect(kinds == kinds.sorted())
        #expect(tokyo.results.first?.match.highlights == [0..<2])

        let prefix = try top("新宿", scope: .stations)
        let ordered = prefix.results.map(\.title)
        #expect(ordered.first == "新宿")
        #expect(ordered.contains("新宿三丁目"))

        // History lifts one prefix completion above another.
        let index = try #require(SearchEngineFixture.index)
        let plain = index.query("新宿", scope: .stations, context: context).results
        let target = try #require(plain.first { $0.title == "新宿御苑前" })
        var personal = context
        personal.recentPicks = [target.entity]
        let lifted = index.query("新宿", scope: .stations, context: personal).results
        let before = try #require(plain.firstIndex { $0.entity == target.entity })
        let after = try #require(lifted.firstIndex { $0.entity == target.entity })
        #expect(after < before)
        #expect(lifted.first?.title == "新宿") // exact still beats a recent prefix
    }

    @Test func emptyQuerySuggestions() throws {
        let index = try #require(SearchEngineFixture.index)
        let tokyo = try #require(index.query("東京", scope: .stations, context: context).results.first)
        let shinjuku = try #require(index.query("新宿", scope: .stations, context: context).results.first)
        let personal = SearchContext(
            regionCode: "jp", recentPicks: [tokyo.entity], recentQueries: ["目黒"],
            rideCounts: [shinjuku.entity: 12])
        let response = index.query("", scope: .stations, context: personal)
        #expect(response.results.map(\.entity) == [tokyo.entity, shinjuku.entity])
        #expect(response.results.map(\.match.kind) == [.recent, .frequent])
        #expect(response.recentQueries == ["目黒"])
    }

    @Test func textQueryForJourneyFields() {
        let query = SearchTextQuery("shinjyuku")
        #expect(query.match("しんじゅく")?.source == .romaji)
        #expect(query.match("新宿") == nil)
        #expect(SearchTextQuery("Tokoy").match("Tokyo")?.kind == .fuzzy)
        #expect(SearchTextQuery("Tokoy").match("Tokyo", allowFuzzy: false) == nil)
        #expect(SearchTextQuery("东京 地铁").matchesAll(fields: ["東京メトロ", "Tokyo Metro"]))
        #expect(SearchTextQuery("東京站").matchesAll(fields: ["東京駅"]))
        let vocabulary = SearchIndexBuilder.vocabulary(["新宿", "Shinjuku", "東京", "Tokyo"])
        let response = vocabulary.query("Shinjyku", scope: .terms, context: SearchContext(regionCode: ""))
        #expect(response.results.first?.title == "Shinjuku")
        #expect(response.didYouMean?.text == "Shinjuku")
    }

    /// Per-keystroke latency and memory at the JP station count. Debug numbers
    /// are an upper bound; the printed figures are the evidence.
    @Test func performanceAtJapanScale() throws {
        let catalog = try #require(SearchEngineFixture.catalog)
        let readings = SearchEngineFixture.readings
        let clock = ContinuousClock()
        var index: SearchIndex?
        let build = clock.measure {
            index = SearchIndexBuilder.catalog(catalog, regionCode: "jp", extraNames: readings)
        }
        let built = try #require(index)
        let keystrokes = ["s", "sh", "shi", "shin", "shinj", "shinjy", "shinjyu", "shinjyuk", "shinjyuku",
                          "と", "とう", "とうき", "東", "東京", "东急 目黑线", "山手綫", "Tokoy", "yamanote", "新宿駅"]
        _ = built.query("warm", context: context)
        var worst: Duration = .zero
        var total: Duration = .zero
        for text in keystrokes {
            let elapsed = clock.measure { _ = built.query(text, context: context) }
            worst = max(worst, elapsed)
            total += elapsed
        }
        let average = total / keystrokes.count
        print("SearchEngine JP: docs=\(built.count) keys=\(built.keys.count) units=\(built.units.count) "
              + "memory=\(built.memoryFootprint / 1024)KiB build=\(build) avg=\(average) worst=\(worst)")
        #expect(built.count > 9_000)
        #expect(built.memoryFootprint < 8 * 1024 * 1024)
        #expect(average < .milliseconds(50))
    }
}
