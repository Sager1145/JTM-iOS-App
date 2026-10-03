import Foundation
import Testing
@testable import RailCore

struct LocalJourneySearchTests {
    @Test("Transfers cross different operators only at the exact shared station code")
    func transfer() throws {
        let package = try fixture([
            line("first", ["A", "B"], operatorName: "One"),
            line("second", ["B", "C"], operatorName: "Two"),
            line("nearby", ["B-other", "D"]),
        ])
        let choice = try #require(LocalJourneySearch.choices(
            package: package, originCode: "A", destinationCode: "C").first)
        #expect(choice.stations.map(\.code) == ["A", "B", "C"])
        #expect(choice.lineIDs == ["first", "second"])
        #expect(choice.operatorNames == ["One", "Two"])
        #expect(choice.routeSections.count == 2)
        #expect(choice.routeSections.flatMap { $0.sectionCodes ?? [] } == choice.sectionCodes)
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D").isEmpty)
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "C",
                                           excludingStationCodes: ["B"]).isEmpty)
    }

    @Test("Directed row continuations preserve repeated physical station occurrences", arguments: [false, true])
    func repeated(reverse: Bool) throws {
        var row = line("repeat", ["A", "B", "C", "B", "D"])
        row["permittedTraversal"] = reverse ? "reverse" : "forward"
        let package = try fixture([row])
        let from = reverse ? "D" : "A", to = reverse ? "A" : "D"
        let choices = LocalJourneySearch.choices(package: package, originCode: from, destinationCode: to)
        let choice = try #require(choices.first)
        let codes = ["A", "B", "C", "B", "D"]
        #expect(choices.count == 1)
        #expect(choice.stations.map(\.code) == (reverse ? Array(codes.reversed()) : codes))
        #expect(Set(choice.sectionCodes).count == 4)
        #expect(choice.routeSections.count == 4)
        #expect(LocalJourneySearch.choices(package: package, originCode: to, destinationCode: from).isEmpty)
    }

    @Test("A loop retains both directions and the physical closing interval")
    func loop() throws {
        var row = line("loop", ["A", "B", "C"])
        row["isLoop"] = true
        row["segments"] = (0..<3).map { [1, 0, [[Double($0), 0], [Double(($0 + 1) % 3), 0]]] as [Any] }
        let choices = LocalJourneySearch.choices(package: try fixture([row]), originCode: "A", destinationCode: "C")
        #expect(choices.map { $0.stations.map(\.code) } == [["A", "C"], ["A", "B", "C"]])
        #expect(choices.first?.sectionCodes == ["loop@A:C"])
    }

    @Test("Distance precedes transfers and stable ordering survives package row reordering")
    func ranking() throws {
        let rows = [line("direct", ["A", "D"], distance: 5),
                    line("first", ["A", "B"], distance: 1),
                    line("second", ["B", "D"], distance: 1),
                    line("equal", ["A", "C", "D"], distance: 1)]
        let first = LocalJourneySearch.choices(package: try fixture(rows), originCode: "A", destinationCode: "D")
        let reordered = LocalJourneySearch.choices(package: try fixture(Array(rows.reversed())), originCode: "A", destinationCode: "D")
        #expect(first == reordered)
        #expect(first.count == 3)
        #expect(first[0].lineIDs == ["equal"])
        #expect(first[1].lineIDs == ["first", "second"])
        #expect(first[2].lineIDs == ["direct"])
    }

    @Test("High speed policy and physical geometry restrict offline search")
    func physicalPolicy() throws {
        var fast = line("fast", ["A", "D"])
        fast["kind"] = "high_speed"
        var broken = line("broken", ["A", "Z"])
        broken["segments"] = [[1, 0, [[0, 0]]] as [Any]]
        let package = try fixture([line("ordinary", ["A", "B", "D"]), fast, broken])
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D")
            .first?.lineIDs == ["ordinary"])
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D", trainType: "highSpeed")
            .first?.lineIDs == ["fast"])
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "Z").isEmpty)
    }

    @Test("Exponential diamond graph has bounded choices and obeys the expansion budget")
    func boundedGraph() throws {
        var rows: [[String: Any]] = []
        for layer in 0..<30 {
            for branch in 0..<2 {
                var row = line("\(layer)-\(branch)", ["S\(layer)", "V\(layer)-\(branch)", "S\(layer + 1)"])
                row["permittedTraversal"] = "forward"
                rows.append(row)
            }
        }
        // Thirty diamonds admit more than one billion routes.
        let package = try fixture(rows)
        let choices = LocalJourneySearch.choices(package: package, originCode: "S0", destinationCode: "S30")
        #expect(choices.count == 3)
        #expect(Set(choices.map(\.id)).count == 3)
        #expect(choices.allSatisfy { $0.routeSections.count == 60 })
        #expect(LocalJourneySearch.choices(package: package, originCode: "S0", destinationCode: "S30",
                                           maximumExpansions: 1).isEmpty)
        #expect(LocalJourneySearch.choices(package: package, originCode: "S0", destinationCode: "S30",
                                           maximumChoices: 1).count == 1)
    }

    @Test("Audited Keisei–Asakusa–Keikyu intervals connect Aoto to Haneda physically")
    func japaneseThroughNetwork() throws {
        let source = try PortFixtures.package(country: "jp")
        let corridorIDs = ["jp-京成電鉄-押上線", "jp-東京都-1号線浅草線",
                           "jp-京浜急行電鉄-本線", "jp-京浜急行電鉄-空港線"]
        let package = CompactPackage(format: source.format, version: source.version,
                                     country: source.country,
                                     lines: source.lines.filter { corridorIDs.contains($0.id) })
        let route = try #require(LocalJourneySearch.choices(
            package: package, originCode: "003280", destinationCode: "004368").first)
        #expect(route.lineIDs == corridorIDs)
        #expect(route.stations.contains { $0.code == "003526" }) // Oshiage
        #expect(route.stations.contains { $0.code == "004042" }) // Sengakuji
        #expect(route.stations.last?.name == "羽田空港第1・第2ターミナル")
        #expect(route.routeSections.count == route.stations.count - 1)
        #expect(route.routeSections.allSatisfy { $0.sectionCodes?.count == 1 })
        // Physical connectivity does not assert a dated single-seat service.
        let reverse = try #require(LocalJourneySearch.choices(
            package: package, originCode: "004368", destinationCode: "003280").first)
        #expect(reverse.sectionCodes == Array(route.sectionCodes.reversed()))
    }

    private func line(_ id: String, _ codes: [String], distance: Double = 1,
                      operatorName: String = "Operator") -> [String: Any] {
        ["id": id, "name": id, "operator": operatorName, "rank": 3,
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [distance, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
