import Foundation
import RailCore
import Testing

struct TrainServicePatternsTests {

    // MARK: - catalog shape

    @Test("the bundled catalog has stable identities and well-formed stop lists")
    func catalogLoads() {
        let patterns = TrainServicePatterns.patterns
        #expect(patterns.count >= 120)
        #expect(Set(patterns.map(\.id)).count == patterns.count)

        let serviceIDs = Set(TrainServiceBranding.services.map(\.id))
        let unknownServiceIDs = patterns.filter { serviceIDs.contains($0.serviceId) == false }
        #expect(unknownServiceIDs.isEmpty, "patterns with unknown serviceId: \(unknownServiceIDs.map(\.id))")

        let badStopLists = patterns.filter { pattern in
            pattern.stops.count < 2
                || pattern.stops.first != pattern.origin
                || pattern.stops.last != pattern.destination
        }
        #expect(badStopLists.isEmpty, "patterns with malformed stop lists: \(badStopLists.map(\.id))")

        let emptyNames = patterns.filter { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(emptyNames.isEmpty, "patterns with empty names: \(emptyNames.map(\.id))")
    }

    // MARK: - station coverage

    @Test("every station named in a pattern exists in the shipped station table")
    func stationsExistInStationTable() throws {
        let root = try Self.repositoryRoot()
        let url = root.appending(path: "app/data/stations.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let features = json?["features"] as? [[String: Any]] ?? []
        let knownNames = Set(features.compactMap { feature -> String? in
            // ADR 0010: the neutral key, with the pre-2026-09 N02 key as fallback.
            let props = feature["properties"] as? [String: Any]
            return (props?["station_name"] ?? props?["N02_005"]) as? String
        })
        #expect(knownNames.isEmpty == false)

        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            for name in pattern.stops + pattern.optionalStops + pattern.via {
                if knownNames.contains(name) == false {
                    offenders.append("(\(pattern.id), \(name))")
                }
            }
        }
        #expect(offenders.isEmpty, "unknown station names: \(offenders)")
    }

    @Test("every v3 stop resolves to its exact bundled editor station")
    func stationReferencesResolve() throws {
        let root = try Self.repositoryRoot()
        let url = root.appending(path: "app/public/rail/jp-2025.json")
        let directory = try JSONDecoder().decode(
            CompactPackage.StationDirectory.self, from: Data(contentsOf: url))
        let catalog = EditorCatalogBuilder.build(directory.lineSources(regionCode: "jp"))
        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            for ref in pattern.stopRefs + pattern.optionalStopRefs {
                guard let station = catalog.station(ref.stationKey) else {
                    offenders.append("\(pattern.id): missing \(ref.name) / \(ref.sourceCode)")
                    continue
                }
                if station.name != ref.name {
                    offenders.append("\(pattern.id): \(ref.sourceCode) names \(station.name), expected \(ref.name)")
                }
            }
            let train = TrainServicePatterns.apply(
                pattern, to: Train(id: "ref-check", number: "", origin: "", destination: "", stops: []))
            if train.stops.map(\.n02StationCode) != pattern.stopRefs.map(\.sourceCode) {
                offenders.append("\(pattern.id): apply dropped station identity")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    private static func repositoryRoot(from file: StaticString = #filePath) throws -> URL {
        var directory = URL(filePath: "\(file)").deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: directory.appending(path: "app/data/stations.json").path)
            {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    // MARK: - same-name, different-route variants

    @Test("Sunrise Izumo and Sunrise Seto share an origin but diverge at the destination")
    func sameNameDifferentRoute() {
        let izumo = TrainServicePatterns.patterns(for: "sunrise-izumo")
        let seto = TrainServicePatterns.patterns(for: "sunrise-seto")
        #expect(izumo.isEmpty == false)
        #expect(seto.isEmpty == false)
        #expect(izumo.allSatisfy { $0.origin == "東京" })
        #expect(seto.allSatisfy { $0.origin == "東京" })
        #expect(izumo.allSatisfy { $0.destination == "出雲市" })
        #expect(seto.allSatisfy { $0.destination == "高松" })
    }

    // MARK: - search

    @Test("search matches by native name, Latin name, and is case-insensitive")
    func searchByName() {
        let sunrise = TrainServicePatterns.search("サンライズ")
        #expect(Set(sunrise.map(\.serviceId)) == ["sunrise-izumo", "sunrise-seto"])

        let seto = TrainServicePatterns.search("Sunrise Seto")
        #expect(seto.isEmpty == false)
        #expect(seto.allSatisfy { $0.serviceId == "sunrise-seto" })

        let all = TrainServicePatterns.search("")
        #expect(all.count == TrainServicePatterns.patterns.filter { pattern in
            TrainServiceBranding.services.first { $0.id == pattern.serviceId }?.region == "jp"
        }.count)

        let haruka = TrainServicePatterns.search("はるか")
        #expect(haruka.count == 2)
        #expect(Set(haruka.map(\.origin)) == ["京都", "野洲"])
    }

    // MARK: - apply

    @Test("apply fills an empty train and leaves an already-filled train alone")
    func applyToTrain() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })

        let empty = Train(id: "t1", number: "", origin: "", destination: "", stops: [])
        let filled = TrainServicePatterns.apply(pattern, to: empty)
        #expect(filled.number == "サンライズ出雲")
        #expect(filled.trainType == "寝台特急")
        #expect(filled.company == "JR東日本/JR東海/JR西日本")
        #expect(filled.stops.first?.stopType == "origin")
        #expect(filled.stops.last?.stopType == "destination")
        #expect(filled.stops.count == pattern.stops.count)

        let alreadyFilled = Train(
            id: "t2", number: "サンライズ出雲2号", company: "私鉄想定運行会社",
            origin: "", destination: "", stops: [])
        let unchanged = TrainServicePatterns.apply(pattern, to: alreadyFilled)
        #expect(unchanged.number == "サンライズ出雲2号")
        #expect(unchanged.company == "私鉄想定運行会社")
    }

    @Test("apply output passes validateTrain")
    func applyPassesValidation() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let empty = Train(
            id: "t1", date: "2024-01-01", number: "", origin: "", destination: "", stops: [])
        let filled = TrainServicePatterns.apply(pattern, to: empty)
        let json = try TrainValidation.JSON.parse(
            String(decoding: try JSONEncoder().encode(filled), as: UTF8.self))
        var ids = Set<String>()
        #expect(throws: Never.self) { try TrainValidation.validateTrain(json, index: 0, ids: &ids) }
    }

    @Test("ridden: false marks every stop unridden")
    func applyUnridden() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let empty = Train(id: "t1", number: "", origin: "", destination: "", stops: [])
        let filled = TrainServicePatterns.apply(pattern, to: empty, ridden: false)
        #expect(filled.stops.allSatisfy { $0.rideSegment == false })
    }

    @Test("apply clears stale route sections and policy")
    func applyClearsRouting() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let train = Train(
            id: "t1", number: "既存", origin: "", destination: "",
            routePolicy: RoutePolicy(mode: "single_primary_route"), routeSections: [], stops: [])
        let filled = TrainServicePatterns.apply(pattern, to: train)
        #expect(filled.routeSections == nil)
        #expect(filled.routePolicy == nil)
    }

    @Test("reversed apply swaps origin and destination")
    func applyReversed() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let empty = Train(id: "t1", number: "", origin: "", destination: "", stops: [])
        let filled = TrainServicePatterns.apply(pattern, to: empty, reversed: true)
        #expect(filled.origin == pattern.destination)
        #expect(filled.destination == pattern.origin)
        #expect(filled.stops.first?.name == pattern.destination)
        #expect(filled.stops.first?.n02StationCode == pattern.stopRefs.last?.sourceCode)
        #expect(filled.stops.first?.stopType == "origin")
        #expect(filled.stops.last?.name == pattern.origin)
        #expect(filled.stops.last?.n02StationCode == pattern.stopRefs.first?.sourceCode)
        #expect(filled.stops.last?.stopType == "destination")
    }

    @Test("re-picking a different pattern overwrites the previous pattern's number, company and type")
    func applyTwiceFollowsSecondPattern() throws {
        let izumo = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let kounotori = try #require(
            TrainServicePatterns.patterns.first { $0.serviceId == "kounotori" })
        let empty = Train(id: "t1", number: "", origin: "", destination: "", stops: [])
        let once = TrainServicePatterns.apply(izumo, to: empty)
        let twice = TrainServicePatterns.apply(kounotori, to: once)
        #expect(twice.number == kounotori.name)
        #expect(twice.company == kounotori.companyLabel)
        #expect(twice.trainType == "特急")
    }

    @Test("a user-typed number survives a second apply")
    func applyTwicePreservesUserNumber() throws {
        let izumo = try #require(
            TrainServicePatterns.patterns.first { $0.id == "sunrise-izumo-tokyo-izumoshi" })
        let kounotori = try #require(
            TrainServicePatterns.patterns.first { $0.serviceId == "kounotori" })
        let userNamed = Train(
            id: "t1", number: "サンライズ出雲2号", origin: "", destination: "", stops: [])
        let once = TrainServicePatterns.apply(izumo, to: userNamed)
        let twice = TrainServicePatterns.apply(kounotori, to: once)
        #expect(twice.number == "サンライズ出雲2号")
    }

    // MARK: - catalog integrity

    @Test("no pattern has duplicate stops or an overlap between stops and optionalStops")
    func noDuplicateOrOverlappingStops() {
        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            if Set(pattern.stops).count != pattern.stops.count {
                offenders.append("\(pattern.id): duplicate stop")
            }
            if Set(pattern.stops).isDisjoint(with: pattern.optionalStops) == false {
                offenders.append("\(pattern.id): overlap between stops and optionalStops")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test("search folds whitespace and hiragana/katakana")
    func searchFoldsQuery() {
        let all = TrainServicePatterns.search(" ")
        #expect(all.count == TrainServicePatterns.search("").count)

        let haruka = TrainServicePatterns.search("ハルカ")
        #expect(haruka.count == 2)

        let harukaHiragana = TrainServicePatterns.search("はるか ")
        #expect(harukaHiragana.count == 2)
    }

    // MARK: - v2 schema

    @Test("every line named in a pattern exists in the shipped rail-sections table, canonically")
    func lineNamesExistInRailSections() throws {
        let root = try Self.repositoryRoot()
        let url = root.appending(path: "app/data/rail-sections.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let features = json?["features"] as? [[String: Any]] ?? []
        let knownLines = Set(features.compactMap { feature -> String? in
            let props = feature["properties"] as? [String: Any]
            return (props?["line_name"] ?? props?["N02_003"]) as? String
        }).map(TrainServiceBranding.canonicalLineName)
        let knownLineSet = Set(knownLines)

        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            for line in pattern.lines {
                let canonical = TrainServiceBranding.canonicalLineName(line)
                if knownLineSet.contains(canonical) == false {
                    offenders.append("(\(pattern.id), \(line))")
                }
            }
        }
        #expect(offenders.isEmpty, "unknown line names: \(offenders)")
    }

    @Test("validFrom/validUntil, when present, are well-formed ISO dates with validFrom <= validUntil")
    func validityDatesAreWellFormed() {
        let datePattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}$"#)
        func matches(_ value: String) -> Bool {
            datePattern.firstMatch(
                in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }

        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            if let from = pattern.validFrom, matches(from) == false {
                offenders.append("\(pattern.id): malformed validFrom \(from)")
            }
            if let to = pattern.validUntil, matches(to) == false {
                offenders.append("\(pattern.id): malformed validUntil \(to)")
            }
            if let from = pattern.validFrom, let to = pattern.validUntil, from > to {
                offenders.append("\(pattern.id): validFrom \(from) > validUntil \(to)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test("unsolvableLegs entries are pairs of consecutive stops")
    func unsolvableLegsAreConsecutiveStopPairs() {
        var offenders: [String] = []
        for pattern in TrainServicePatterns.patterns {
            let consecutivePairs = zip(pattern.stops, pattern.stops.dropFirst()).map { [$0, $1] }
            for leg in pattern.unsolvableLegs {
                if leg.count != 2 || consecutivePairs.contains(leg) == false {
                    offenders.append("\(pattern.id): \(leg)")
                }
            }
        }
        #expect(offenders.isEmpty, "unsolvableLegs not consecutive stop pairs: \(offenders)")
    }

    @Test("v3 station references and exclusive validity decode; legacy strings fail closed")
    func decodesV3Only() throws {
        let v3JSON = """
        {
            "patternId": "test-v3",
            "serviceId": "test",
            "name": "テスト",
            "company": "テスト鉄道",
            "label": "テスト区間",
            "origin": "A",
            "destination": "C",
            "stops": [
                {"name": "A", "sourceCode": "001"},
                {"name": "B", "sourceCode": "002"},
                {"name": "C", "sourceCode": "003"}
            ],
            "optionalStops": [],
            "via": [],
            "confidence": "high",
            "source": "https://example.com",
            "lines": ["テスト線"],
            "validFrom": "2020-01-01",
            "validUntil": "2024-03-16",
            "completeness": {"stops": "complete", "lines": "partial", "validity": "complete"},
            "notes": "テストノート",
            "unsolvableLegs": [["A", "B"]]
        }
        """
        let v3 = try JSONDecoder().decode(
            TrainServicePatterns.Pattern.self, from: Data(v3JSON.utf8))
        #expect(v3.stops == ["A", "B", "C"])
        #expect(v3.stopRefs.map(\.sourceCode) == ["001", "002", "003"])
        #expect(v3.lines == ["テスト線"])
        #expect(v3.validFrom == "2020-01-01")
        #expect(v3.validUntil == "2024-03-16")
        #expect(v3.isValid(on: "2019-12-31") == false)
        #expect(v3.isValid(on: "2020-01-01"))
        #expect(v3.isValid(on: "2024-03-15"))
        #expect(v3.isValid(on: "2024-03-16") == false)
        #expect(v3.completeness.stops == .complete)
        #expect(v3.completeness.lines == .partial)
        #expect(v3.completeness.validity == .complete)
        #expect(v3.notes == "テストノート")
        #expect(v3.unsolvableLegs == [["A", "B"]])

        let v1JSON = """
        {
            "patternId": "test-v1",
            "serviceId": "test",
            "name": "テスト",
            "company": "テスト鉄道",
            "label": "テスト区間",
            "origin": "A",
            "destination": "C",
            "stops": ["A", "B", "C"],
            "optionalStops": [],
            "via": [],
            "confidence": "high",
            "source": "https://example.com"
        }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TrainServicePatterns.Pattern.self, from: Data(v1JSON.utf8))
        }
    }

    @Test("search filters by status, company, and line")
    func searchWithFilter() throws {
        let all = TrainServicePatterns.patterns

        if let discontinued = all.first(where: { $0.validUntil != nil }) {
            let results = TrainServicePatterns.search(
                "", filter: TrainServicePatterns.Filter(status: .discontinued))
            #expect(results.isEmpty == false)
            #expect(results.allSatisfy { $0.isCurrent == false })
            #expect(results.contains { $0.id == discontinued.id })
        }

        let company = try #require(all.first?.companyLabel)
        let byCompany = TrainServicePatterns.search(
            "", filter: TrainServicePatterns.Filter(company: company))
        #expect(byCompany.isEmpty == false)
        #expect(byCompany.allSatisfy { $0.companyLabel == company })

        if let lineName = all.first(where: { $0.lines.isEmpty == false })?.lines.first {
            let byLine = TrainServicePatterns.search(lineName)
            #expect(byLine.isEmpty == false)
            #expect(byLine.contains { pattern in pattern.lines.contains(lineName) })
        }

        let byCurrentStatus = TrainServicePatterns.search(
            "", filter: TrainServicePatterns.Filter(status: .current))
        #expect(byCurrentStatus.isEmpty == false)
        #expect(byCurrentStatus.allSatisfy { $0.isCurrent })

        let onDate = TrainServicePatterns.search(
            "", filter: TrainServicePatterns.Filter(status: .onDate, rideDate: "2021-03-12"))
        #expect(onDate.isEmpty == false)
        #expect(onDate.allSatisfy { $0.isValid(on: "2021-03-12") })
        #expect(onDate.allSatisfy { $0.completeness.validity != .missing })
        #expect(onDate.contains { $0.id == "ariake-omuta-hakata" })
        let nextDay = TrainServicePatterns.search(
            "", filter: TrainServicePatterns.Filter(status: .onDate, rideDate: "2021-03-13"))
        #expect(nextDay.contains { $0.id == "ariake-omuta-hakata" } == false)

        let someLine = try #require(TrainServicePatterns.lineNames().first)
        let canonicalSomeLine = TrainServiceBranding.canonicalLineName(someLine)
        let byLineFilter = TrainServicePatterns.search(
            "", filter: TrainServicePatterns.Filter(line: someLine))
        #expect(byLineFilter.isEmpty == false)
        #expect(byLineFilter.allSatisfy { pattern in
            pattern.lines.contains { TrainServiceBranding.canonicalLineName($0) == canonicalSomeLine }
        })
    }

    @Test("a name match ranks ahead of a stop-only match")
    func searchRanksNameMatchesFirst() {
        let hidaByName = TrainServicePatterns.search("ひだ")
        #expect(hidaByName.isEmpty == false)
        if let firstNonHida = hidaByName.firstIndex(where: { $0.name != "ひだ" }) {
            let lastHida = hidaByName.lastIndex(where: { $0.name == "ひだ" })
            #expect(lastHida != nil && lastHida! < firstNonHida)
        }

        let hidaByStop = TrainServicePatterns.search("岐阜")
        #expect(hidaByStop.contains { $0.name == "ひだ" })
    }
}
