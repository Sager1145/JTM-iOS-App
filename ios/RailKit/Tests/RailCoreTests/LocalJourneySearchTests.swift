import Foundation
import Testing
@testable import RailCore

struct LocalJourneySearchTests {
    @Test("Shared station identity and transfer relations do not prove connected track")
    func transfer() throws {
        let package = try fixture([
            line("first", ["A", "B"], operatorName: "One"),
            line("second", ["B", "C"], operatorName: "Two"),
            line("nearby", ["B-other", "D"]),
        ])
        let result = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "C")
        #expect(result.choices.isEmpty)
        #expect(!result.topologyIsComplete)
        #expect(result.uniqueChoice == nil)
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D").isEmpty)
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
        #expect(first.count == 2)
        #expect(first[0].lineIDs == ["equal"])
        #expect(first[1].lineIDs == ["direct"])
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

    @Test("Choice and expansion limits expose incomplete searches")
    func boundedGraph() throws {
        let package = try fixture([
            line("first", ["A", "B", "D"]),
            line("second", ["A", "C", "D"]),
        ])
        let complete = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D")
        #expect(complete.choices.count == 2)
        #expect(complete.hasAmbiguity)
        #expect(!complete.isTruncated)
        let limited = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                               maximumChoices: 1)
        #expect(limited.choices.count == 1)
        #expect(limited.isTruncated)
        #expect(limited.uniqueChoice == nil)
        let unfinished = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                                  maximumExpansions: 1)
        #expect(unfinished.choices.isEmpty)
        #expect(unfinished.isTruncated)
        #expect(unfinished.uniqueChoice == nil)
    }

    @Test("An exhausted single-row search is still incomplete network coverage")
    func coverage() throws {
        let result = LocalJourneySearch.search(package: try fixture([line("one", ["A", "B", "D"])]),
                                               originCode: "A", destinationCode: "D")
        #expect(result.choices.count == 1)
        #expect(!result.isTruncated)
        #expect(!result.hasAmbiguity)
        #expect(!result.topologyIsComplete)
        #expect(result.uniqueChoice == nil)
    }

    @Test("Ordered authored anchors cannot be bypassed by the shorter row")
    func anchors() throws {
        let package = try fixture([line("short", ["A", "D"]), line("long", ["A", "B", "C", "D"])])
        let result = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                               requiredStationCodes: ["A", "C", "D"])
        #expect(result.choices.map { $0.stations.map(\.code) } == [["A", "B", "C", "D"]])
        #expect(LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                requiredStationCodes: ["A", "C", "B", "D"]).choices.isEmpty)
    }

    @Test("A through-network label cannot supply missing physical junction evidence")
    func japaneseThroughNetwork() throws {
        let source = try PortFixtures.package(country: "jp")
        let corridorIDs = ["jp-京成電鉄-押上線", "jp-東京都-1号線浅草線",
                           "jp-京浜急行電鉄-本線", "jp-京浜急行電鉄-空港線"]
        let package = CompactPackage(format: source.format, version: source.version,
                                     country: source.country,
                                     lines: source.lines.filter { corridorIDs.contains($0.id) })
        let result = LocalJourneySearch.search(package: package, originCode: "003280", destinationCode: "004368")
        #expect(result.choices.isEmpty)
        #expect(!result.topologyIsComplete)
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
