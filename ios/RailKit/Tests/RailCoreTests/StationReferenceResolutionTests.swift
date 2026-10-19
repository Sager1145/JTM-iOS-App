import Foundation
import Testing

@testable import RailCore

struct StationReferenceResolutionTests {
    @Test("府中 on four lines stays ambiguous until the line is named")
    func fuchuHomonyms() {
        let catalog = Self.japan()
        let all = Self.resolve("府中", in: catalog)
        #expect(all.map(\.station.key.sourceCode) == ["F1", "F2", "F3", "F4"])
        #expect(all.map(\.label) == [
            "府中 (JP, 京王線)", "府中 (JP, 徳島線)", "府中 (JP, 福塩線)", "府中 (JP, 南武線)",
        ])
        let keio = Self.resolve("府中 (JP, 京王線)", in: catalog)
        #expect(keio.map(\.station.key.sourceCode) == ["F1"])
        #expect(keio.map(\.label) == ["府中 (JP, 京王線)"])
        let through = Self.resolve("府中 (都営新宿線)", in: catalog)
        #expect(through.map(\.station.key.sourceCode) == ["F1"])
    }

    @Test("company stations that share a name stay unresolved until the line does")
    func sameNameCompanyStations() {
        let catalog = Self.japan()
        let both = Self.resolve("住吉", in: catalog)
        #expect(both.map(\.station.key.sourceCode) == ["H-SUMI", "K-SUMI"])
        #expect(both.map(\.label) == ["住吉 (JP, 阪神本線)", "住吉 (JP, 京成本線)"])
        #expect(Self.resolve("住吉 (本線)", in: catalog).count == 2)
        #expect(Self.resolve("住吉 (JP, 京成本線)", in: catalog).map(\.station.key.sourceCode) == ["K-SUMI"])
        #expect(Self.resolve("住吉 (JP, 京成 本線)", in: catalog).map(\.station.key.sourceCode) == ["K-SUMI"])
        #expect(Self.resolve("住吉 (JP, 阪神本線)", in: catalog).map(\.station.key.sourceCode) == ["H-SUMI"])
        #expect(Self.resolve("押上 (JP, 京成)", in: catalog).map(\.station.key.sourceCode) == ["OSHIAGE"])
    }

    @Test("MO is Macau, and Tokyo Monorail's MO needs a country")
    func macauVersusMonorail() {
        let catalog = Self.japanAndMacau()
        let macau = Self.resolve("浜松町 (MO)", in: catalog)
        #expect(macau.map(\.station.key.regionCode) == ["mo"])
        #expect(macau.map(\.station.key.sourceCode) == ["MO-HAMA"])
        let monorail = Self.resolve("浜松町 (JP, MO)", in: catalog)
        #expect(monorail.map(\.station.key) == [StationKey(regionCode: "jp", sourceCode: "HAMA")])
        #expect(monorail.map(\.label) == ["浜松町 (JP, 東京モノレール)"])
        #expect(Self.resolve("浜松町 (JP, mo)", in: catalog).map(\.station.key.sourceCode) == ["HAMA"])
        #expect(Self.resolve("浜松町 (jp, 東京モノレール)", in: catalog).map(\.station.key.sourceCode) == ["HAMA"])
    }

    @Test("a numbered line is also reachable without the number, and US is not a country")
    func lineAliasesAndUnsupportedCountries() {
        let catalog = Self.japan()
        #expect(Self.resolve("本町 (JP, 御堂筋線)", in: catalog).map(\.station.key.sourceCode) == ["HON"])
        #expect(Self.resolve("本町 (JP, 1号線(御堂筋線))", in: catalog).map(\.station.key.sourceCode) == ["HON"])
        #expect(Self.resolve("銀座 (G)", in: catalog).map(\.station.key.sourceCode) == ["GINZA"])
        #expect(Self.resolve("Boston (US, Acela)", in: catalog).isEmpty)
        #expect(Self.resolve("Boston (CA, VIA)", in: catalog).isEmpty)
        #expect(Self.resolve("Boston (JP, Acela)", in: catalog).map(\.station.key.sourceCode) == ["BOS"])
    }

    @Test("pasted 府中 (JP, 京王線) is one labeled candidate and the bracket is not leftover text")
    func importRecognizesTheQualifier() {
        let catalog = Self.japan()
        let seed = Self.seed()
        let draft = JourneyCompletion.rawDraft(
            text: "府中 (JP, 京王線)\n新宿",
            catalog: catalog, regionCode: "jp", seed: seed)
        #expect(draft.unmatchedLines.isEmpty)
        #expect(draft.stops.count == 2)
        #expect(draft.stops[0].candidates.map(\.key.sourceCode) == ["F1"])
        #expect(draft.stops[0].candidateLabels == ["府中 (JP, 京王線)"])
        #expect(draft.stops[0].automaticSelection == StationKey(regionCode: "jp", sourceCode: "F1"))

        let timed = JourneyCompletion.rawDraft(
            text: "府中 (JP, 京王線) 09:03 発",
            catalog: catalog, regionCode: "jp", seed: seed)
        #expect(timed.unmatchedLines.isEmpty)
        #expect(timed.stops.first?.departure == "9:03")
        #expect(timed.stops.first?.candidates.map(\.key.sourceCode) == ["F1"])

        let missed = JourneyCompletion.rawDraft(
            text: "府中 (JP, 存在しない線)",
            catalog: catalog, regionCode: "jp", seed: seed)
        #expect(missed.unmatchedLines.isEmpty)
        #expect(missed.stops.first?.candidates.map(\.key.sourceCode) == ["F1", "F2", "F3", "F4"])

        var train = seed
        train.stops[0].name = "府中 (JP, 京王線)"
        train.stops[0].n02StationCode = nil
        train.stops[1].name = "府中"
        train.stops[1].n02StationCode = nil
        let resolved = JourneyCompletion.resolvingUniqueStationNames(in: train, catalogs: ["jp": catalog])
        #expect(resolved.stops[0].n02StationCode == "F1")
        #expect(resolved.stops[1].n02StationCode == nil)

        train.stops[0].name = "新宿"
        let unique = JourneyCompletion.resolvingUniqueStationNames(in: train, catalogs: ["jp": catalog])
        #expect(unique.stops[0].n02StationCode == "SHINJUKU")

        train.stops[0].name = "Boston (US, Acela)"
        let blocked = JourneyCompletion.resolvingUniqueStationNames(in: train, catalogs: ["jp": catalog])
        #expect(blocked.stops[0].n02StationCode == nil)
    }

    @Test("an official name that contains brackets stays the station name")
    func bracketedOfficialNames() {
        let catalog = Self.bracketed()
        let seed = Self.seed()
        let nishitetsu = JourneyCompletion.rawDraft(
            text: "西鉄福岡（天神）", catalog: catalog, regionCode: "jp", seed: seed)
        #expect(nishitetsu.stops.first?.candidates.map(\.key.sourceCode) == ["NFT"])
        let hiroshima = JourneyCompletion.rawDraft(
            text: "広島港（宇品）", catalog: catalog, regionCode: "jp", seed: seed)
        #expect(hiroshima.stops.first?.candidates.map(\.key.sourceCode) == ["HIRO"])
        let platform = JourneyCompletion.rawDraft(
            text: "東京 (3番線) 09:00", catalog: catalog, regionCode: "jp", seed: seed)
        #expect(platform.stops.first?.candidates.map(\.key.sourceCode) == ["TYO"])
        #expect(platform.stops.first?.arrival == "9:00")
        let marked = JourneyCompletion.rawDraft(
            text: "09:00 (発) 東京", catalog: catalog, regionCode: "jp", seed: seed)
        #expect(marked.stops.first?.candidates.map(\.key.sourceCode) == ["TYO"])
        #expect(marked.stops.first?.departure == "9:00")

        var train = seed
        train.stops[0].name = "西鉄福岡（天神）"
        train.stops[0].n02StationCode = nil
        train.stops[1].name = "府中 (JP, 京王線)"
        train.stops[1].n02StationCode = nil
        let resolved = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": catalog])
        #expect(resolved.stops[0].n02StationCode == "NFT")
        #expect(resolved.stops[1].n02StationCode == nil)
        let qualified = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": Self.japan()])
        #expect(qualified.stops[1].n02StationCode == "F1")
    }

    @Test("a line name keeps its nakaguro and still resolves")
    func nakaguroStaysInTheLineName() {
        let catalog = Self.japan()
        let matches = Self.resolve("日暮里 (JP, 日暮里・舎人ライナー)", in: catalog)
        #expect(matches.map(\.station.key.sourceCode) == ["NIP"])
        #expect(matches.map(\.label) == ["日暮里 (JP, 日暮里・舎人ライナー)"])
    }

    @Test("copy and ambiguous-candidate labels round-trip to that station")
    func labelsRoundTrip() {
        let catalog = Self.japan()
        let catalogs = ["jp": catalog]
        for text in ["府中", "住吉"] {
            guard let reference = StationReference.parse(text) else {
                Issue.record("unparsed \(text)")
                continue
            }
            let matches = StationReferenceResolution.resolve(reference, in: catalogs)
            #expect(matches.count > 1)
            for match in matches {
                guard let again = StationReference.parse(match.label) else {
                    Issue.record("label did not parse \(match.label)")
                    continue
                }
                let resolved = StationReferenceResolution.resolve(again, in: catalogs)
                #expect(resolved.map(\.station.key) == [match.station.key])
                #expect(!match.label.contains("・"))
            }
        }
        for code in ["F1", "F2", "F3", "F4", "K-SUMI", "H-SUMI", "NIP"] {
            let key = StationKey(regionCode: "jp", sourceCode: code)
            guard let station = catalog.station(key) else {
                Issue.record("missing \(code)")
                continue
            }
            let label = StationReferenceResolution.copyLabel(for: station, catalog: catalog)
            guard let parsed = StationReference.parse(label) else {
                Issue.record("copy did not parse \(label)")
                continue
            }
            let resolved = StationReferenceResolution.resolve(parsed, in: catalogs)
            #expect(resolved.map(\.station.key.sourceCode) == [code])
            #expect(label.hasPrefix(station.name + " "))
        }
    }

    @Test("a stored bracket stays the name, and only a following group is the qualifier")
    func storedBracketNames() {
        let catalog = EditorCatalogBuilder.build([
            Self.line("nishitetsu", "天神大牟田線", "西日本鉄道", rank: 1, stations: [
                ("NFT", "西鉄福岡（天神）", 130.40, 33.59),
            ]),
            Self.line("yama", "山手線", "東日本旅客鉄道", rank: 1, stations: [
                ("SJK", "新宿", 139.70, 35.69),
            ]),
        ])
        let directory = StationNameDirectory(
            bracketedNames: [
                "西鉄福岡（天神）": StationNameRecord(
                    base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix),
            ],
            baseNameCounts: ["西鉄福岡": 1])
        let seed = Self.seed()

        let full = JourneyCompletion.rawDraft(
            text: "西鉄福岡（天神）", catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(full.stops.first?.automaticSelection == StationKey(regionCode: "jp", sourceCode: "NFT"))

        let qualified = JourneyCompletion.rawDraft(
            text: "西鉄福岡（天神） (JP, 天神大牟田線)",
            catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(qualified.stops.first?.candidates.map(\.key.sourceCode) == ["NFT"])
        #expect(qualified.stops.first?.automaticSelection?.sourceCode == "NFT")

        let half = JourneyCompletion.rawDraft(
            text: "西鉄福岡(天神) (JP, 天神大牟田線)",
            catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(half.stops.first?.automaticSelection?.sourceCode == "NFT")

        let base = JourneyCompletion.rawDraft(
            text: "西鉄福岡", catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(base.stops.first?.ambiguous == false)
        #expect(base.stops.first?.automaticSelection?.sourceCode == "NFT")

        let baseLine = JourneyCompletion.rawDraft(
            text: "西鉄福岡 (JP, 天神大牟田線)",
            catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(baseLine.stops.first?.automaticSelection?.sourceCode == "NFT")

        let wrong = JourneyCompletion.rawDraft(
            text: "西鉄福岡（天神） (JP, 山手線)",
            catalog: catalog, regionCode: "jp", seed: seed, directory: directory)
        #expect(wrong.stops.first?.automaticSelection == nil)

        let crowded = EditorCatalogBuilder.build([
            Self.line("nishitetsu", "天神大牟田線", "西日本鉄道", rank: 1, stations: [
                ("NFT", "西鉄福岡（天神）", 130.40, 33.59),
                ("PLAIN", "西鉄福岡", 130.41, 33.60),
            ]),
        ])
        let ambiguous = JourneyCompletion.rawDraft(
            text: "西鉄福岡", catalog: crowded, regionCode: "jp", seed: seed, directory: directory)
        #expect(ambiguous.stops.first?.ambiguous == false)
        #expect(ambiguous.stops.first?.automaticSelection?.sourceCode == "PLAIN")
        #expect(ambiguous.stops.first?.candidates.map(\.key.sourceCode) == ["PLAIN"])

        let shared = StationNameDirectory(
            bracketedNames: [
                "西鉄福岡（天神）": StationNameRecord(
                    base: "西鉄福岡", bracket: "天神", kind: .subname, position: .suffix),
                "西鉄福岡（天神口）": StationNameRecord(
                    base: "西鉄福岡", bracket: "天神口", kind: .subname, position: .suffix),
            ],
            baseNameCounts: ["西鉄福岡": 2])
        let both = EditorCatalogBuilder.build([
            Self.line("nishitetsu", "天神大牟田線", "西日本鉄道", rank: 1, stations: [
                ("NFT", "西鉄福岡（天神）", 130.40, 33.59),
                ("NFT2", "西鉄福岡（天神口）", 130.42, 33.61),
            ]),
        ])
        let sharedStop = JourneyCompletion.rawDraft(
            text: "西鉄福岡", catalog: both, regionCode: "jp", seed: seed, directory: shared)
        #expect(sharedStop.stops.first?.ambiguous == true)
        #expect(sharedStop.stops.first?.automaticSelection == nil)
        #expect(sharedStop.stops.first?.candidateLabels.isEmpty == false)

        var train = seed
        train.stops[0].name = "西鉄福岡（天神） (JP, 天神大牟田線)"
        train.stops[0].n02StationCode = nil
        train.stops[1].name = "西鉄福岡"
        train.stops[1].n02StationCode = nil
        let resolved = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": catalog], names: ["jp": directory])
        #expect(resolved.stops[0].n02StationCode == "NFT")
        #expect(resolved.stops[1].n02StationCode == "NFT")

        train.stops[0].name = "西鉄福岡(天神)"
        train.stops[1].name = "西鉄福岡"
        let halfResolved = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": catalog], names: ["jp": directory])
        #expect(halfResolved.stops[0].n02StationCode == "NFT")
        let refused = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": crowded], names: ["jp": directory])
        #expect(refused.stops[1].n02StationCode == "PLAIN")

        let copy = StationLabel.presented(
            officialName: "西鉄福岡（天神）",
            qualifier: "(JP, 天神大牟田線)",
            parts: directory.parts(forOfficialName: "西鉄福岡（天神）"),
            statusWord: nil).copy
        let parsed = StationReference.parse(copy, names: directory)
        #expect(parsed?.name == "西鉄福岡（天神）")
        #expect(parsed?.country == "JP")
        #expect(parsed?.line == "天神大牟田線")
        let again = StationReferenceResolution.resolve(parsed!, in: ["jp": catalog])
        #expect(again.map(\.station.key.sourceCode) == ["NFT"])
    }

    @Test("an exact catalog name wins over a unique base")
    func exactCatalogNameWinsOverBase() {
        let bracket = StationNameRecord(
            base: "諫早", bracket: "雲仙・島原口", kind: .subname, position: .suffix)
        let directory = StationNameDirectory(
            bracketedNames: ["諫早（雲仙・島原口）": bracket],
            baseNameCounts: ["諫早": 1])
        let both = EditorCatalogBuilder.build([
            Self.line("nagasaki", "長崎線", "九州旅客鉄道", rank: 1, stations: [
                ("JR-ISA", "諫早", 130.04, 32.85),
            ]),
            Self.line("shimabara", "島原鉄道線", "島原鉄道", rank: 2, stations: [
                ("SHIMA", "諫早（雲仙・島原口）", 130.05, 32.86),
            ]),
        ])
        let seed = Self.seed()
        let pasted = JourneyCompletion.rawDraft(
            text: "諫早", catalog: both, regionCode: "jp", seed: seed, directory: directory)
        #expect(pasted.stops.first?.automaticSelection?.sourceCode == "JR-ISA")
        #expect(pasted.stops.first?.candidates.map(\.key.sourceCode) == ["JR-ISA"])

        let official = JourneyCompletion.rawDraft(
            text: "諫早（雲仙・島原口）", catalog: both, regionCode: "jp", seed: seed, directory: directory)
        #expect(official.stops.first?.automaticSelection?.sourceCode == "SHIMA")

        var train = seed
        train.stops[0].name = "諫早"
        train.stops[0].n02StationCode = nil
        train.stops[1].name = "諫早（雲仙・島原口）"
        train.stops[1].n02StationCode = nil
        let stored = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": both], names: ["jp": directory])
        #expect(stored.stops[0].n02StationCode == "JR-ISA")
        #expect(stored.stops[1].n02StationCode == "SHIMA")

        let bracketOnly = EditorCatalogBuilder.build([
            Self.line("shimabara", "島原鉄道線", "島原鉄道", rank: 2, stations: [
                ("SHIMA", "諫早（雲仙・島原口）", 130.05, 32.86),
            ]),
        ])
        let base = JourneyCompletion.rawDraft(
            text: "諫早", catalog: bracketOnly, regionCode: "jp", seed: seed, directory: directory)
        #expect(base.stops.first?.automaticSelection?.sourceCode == "SHIMA")
        train.stops[1].name = "東京"
        let baseStored = JourneyCompletion.resolvingUniqueStationNames(
            in: train, catalogs: ["jp": bracketOnly], names: ["jp": directory])
        #expect(baseStored.stops[0].n02StationCode == "SHIMA")

        let shared = StationNameDirectory(
            bracketedNames: [
                "諫早（雲仙・島原口）": bracket,
                "諫早（東）": StationNameRecord(
                    base: "諫早", bracket: "東", kind: .subname, position: .suffix),
            ],
            baseNameCounts: ["諫早": 2])
        let two = EditorCatalogBuilder.build([
            Self.line("shimabara", "島原鉄道線", "島原鉄道", rank: 2, stations: [
                ("SHIMA", "諫早（雲仙・島原口）", 130.05, 32.86),
                ("EAST", "諫早（東）", 130.06, 32.87),
            ]),
        ])
        let ambiguous = JourneyCompletion.rawDraft(
            text: "諫早", catalog: two, regionCode: "jp", seed: seed, directory: shared)
        #expect(ambiguous.stops.first?.ambiguous == true)
        #expect(ambiguous.stops.first?.automaticSelection == nil)
        #expect(Set(ambiguous.stops.first?.candidates.map(\.key.sourceCode) ?? []) == ["EAST", "SHIMA"])
    }

    @Test("a bracket tail is a span resolved by exact name, not a legacy fallback")
    func bracketTailIsAResolvedSpan() {
        let directory = StationNameDirectory(
            bracketedNames: [
                "特異（前）": StationNameRecord(
                    base: "特異", bracket: "前", kind: .subname, position: .suffix),
            ])
        let catalog = EditorCatalogBuilder.build([
            Self.line("yamanote", "山手線", "東日本旅客鉄道", rank: 1, stations: [
                ("HAKATA", "博多", 130.42, 33.59),
            ]),
        ])
        let draft = JourneyCompletion.rawDraft(
            text: "特異（前） 博多", catalog: catalog, regionCode: "jp", seed: Self.seed(),
            directory: directory)
        #expect(draft.stops.first?.automaticSelection?.sourceCode == "HAKATA")
        let both = EditorCatalogBuilder.build([
            Self.line("yamanote", "山手線", "東日本旅客鉄道", rank: 1, stations: [
                ("HAKATA", "博多", 130.42, 33.59),
                ("TOK", "東京", 139.7, 35.6),
            ]),
        ])
        let two = JourneyCompletion.rawDraft(
            text: "博多 東京", catalog: both, regionCode: "jp", seed: Self.seed(),
            directory: directory)
        #expect(two.stops.first?.automaticSelection == nil)
        #expect(two.stops.first?.ambiguous == true)
    }

    @Test("two same-name stations that share a line round-trip on a line of their own")
    func sharedLineLabelsRoundTrip() {
        let catalog = EditorCatalogBuilder.build([
            Self.line("shared", "共用線", "共用鉄道", rank: 1, stations: [
                ("A", "同名", 139.0, 35.0),
                ("B", "同名", 139.1, 35.1),
            ]),
            Self.line("onlyA", "甲線", "甲鉄道", rank: 2, stations: [
                ("A", "同名", 139.0, 35.0),
            ]),
            Self.line("onlyB", "乙線", "乙鉄道", rank: 2, stations: [
                ("B", "同名", 139.1, 35.1),
            ]),
        ])
        let catalogs = ["jp": catalog]
        guard let reference = StationReference.parse("同名") else {
            Issue.record("unparsed")
            return
        }
        let matches = StationReferenceResolution.resolve(reference, in: catalogs)
        #expect(matches.count == 2)
        for match in matches {
            guard let again = StationReference.parse(match.label) else {
                Issue.record("label did not parse \(match.label)")
                continue
            }
            let resolved = StationReferenceResolution.resolve(again, in: catalogs)
            #expect(resolved.map(\.station.key) == [match.station.key])
            let copy = StationReferenceResolution.copyLabel(for: match.station, catalog: catalog)
            #expect(copy == match.label)
        }

        let onlyShared = EditorCatalogBuilder.build([
            Self.line("shared", "共用線", "東日本旅客鉄道", rank: 1, stations: [
                ("A", "同名", 139.0, 35.0),
                ("B", "同名", 139.1, 35.1),
            ]),
        ])
        let qualified = StationLabel.qualifiedLineName("共用線", operatorName: "東日本旅客鉄道")
        let expected = StationLabel.full(name: "同名", countryCode: "JP", lineLabel: qualified)
        let sharedMatches = StationReferenceResolution.resolve(
            reference, in: ["jp": onlyShared])
        #expect(sharedMatches.map(\.label) == [expected, expected])
    }

    private static func resolve(_ text: String, in catalog: EditorCatalog) -> [StationReferenceResolution.Match] {
        guard let reference = StationReference.parse(text) else { return [] }
        return StationReferenceResolution.resolve(reference, in: ["catalog": catalog])
    }

    private static func seed() -> Train {
        Train(
            id: "draft", number: "", origin: "", destination: "", visible: true,
            stops: [
                Stop(name: "", stopType: "origin", rideSegment: true),
                Stop(name: "", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
    }

    private static func japan() -> EditorCatalog {
        EditorCatalogBuilder.build([
            line("keio", "京王線", "京王電鉄", rank: 1, stations: [
                ("F1", "府中", 139.48, 35.67),
                ("LINE-NAME", "京王線", 139.50, 35.70),
            ]),
            line("toei", "都営新宿線", "東京都", rank: 2, stations: [("F1", "府中", 139.48, 35.67)]),
            line("tokushima", "徳島線", "四国旅客鉄道", rank: 8, stations: [("F2", "府中", 134.57, 34.07)]),
            line("fukuen", "福塩線", "西日本旅客鉄道", rank: 8, stations: [("F3", "府中", 133.23, 34.57)]),
            line("nambu", "南武線", "東日本旅客鉄道", rank: 3, stations: [("F4", "府中", 139.45, 35.67)]),
            line("keisei", "本線", "京成電鉄", rank: 4, stations: [
                ("K-SUMI", "住吉", 139.87, 35.68),
                ("OSHIAGE", "押上", 139.81, 35.71),
            ]),
            line("hanshin", "本線", "阪神電気鉄道", rank: 4, stations: [("H-SUMI", "住吉", 135.26, 34.72)]),
            line("midosuji", "1号線(御堂筋線)", "大阪市高速電気軌道", rank: 1, stations: [
                ("HON", "本町", 135.50, 34.68),
            ]),
            line("ginza", "銀座線", "東京地下鉄", code: "G", rank: 1, stations: [
                ("GINZA", "銀座", 139.76, 35.67),
            ]),
            line("acela", "Acela", "Amtrak", rank: 1, stations: [("BOS", "Boston", 139.0, 35.0)]),
            line("yamanote", "山手線", "東日本旅客鉄道", rank: 1, stations: [("SHINJUKU", "新宿", 139.70, 35.69)]),
            line("nippori", "日暮里・舎人ライナー", "東京都交通局", rank: 5, stations: [
                ("NIP", "日暮里", 139.77, 35.73),
            ]),
        ])
    }

    private static func bracketed() -> EditorCatalog {
        EditorCatalogBuilder.build([
            line("nishitetsu", "天神大牟田線", "西日本鉄道", rank: 1, stations: [
                ("NFT", "西鉄福岡（天神）", 130.40, 33.59),
            ]),
            line("hiroden", "宇品線", "広島電鉄", rank: 1, stations: [
                ("HIRO", "広島港（宇品）", 132.54, 34.35),
            ]),
            line("tokaido", "東海道線", "東日本旅客鉄道", rank: 1, stations: [
                ("TYO", "東京", 139.77, 35.68),
            ]),
        ])
    }

    private static func japanAndMacau() -> EditorCatalog {
        EditorCatalogBuilder.build([
            line("mono", "東京モノレール", "東京モノレール", code: "MO", rank: 2, stations: [
                ("HAMA", "浜松町", 139.757, 35.655),
            ]),
            line("ml", "氹仔線", "澳門輕軌", region: "mo", rank: 1, stations: [
                ("MO-HAMA", "浜松町", 113.56, 22.16),
            ]),
        ])
    }

    private static func line(
        _ id: String, _ name: String, _ operatorName: String,
        region: String = "jp", code: String? = nil, rank: Int = 0,
        stations: [(String, String, Double, Double)]
    ) -> EditorCatalogLineSource {
        EditorCatalogLineSource(
            regionCode: region, lineID: id, name: name, operatorName: operatorName,
            stations: stations.map {
                EditorCatalogStationSource(sourceCode: $0.0, name: $0.1, longitude: $0.2, latitude: $0.3)
            },
            lineCode: code, rank: rank)
    }
}
