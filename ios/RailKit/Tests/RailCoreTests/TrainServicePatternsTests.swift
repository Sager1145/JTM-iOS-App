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
            (feature["properties"] as? [String: Any])?["N02_005"] as? String
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
        #expect(filled.stops.first?.stopType == "origin")
        #expect(filled.stops.last?.name == pattern.origin)
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
}
