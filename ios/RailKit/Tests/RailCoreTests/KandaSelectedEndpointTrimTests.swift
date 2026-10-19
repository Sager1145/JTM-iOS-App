import Foundation
import Testing
@testable import RailCore

struct KandaSelectedEndpointTrimTests {
    @Test("Kanda station marker on a foreign track cannot terminate Chuo endpoint trimming")
    func kandaForeignMarkerUsesSelectedSurvey() throws {
        let root = try PortFixtures.repositoryRoot()
        let package = try CompactPackage.load(contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let line = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-中央線" })
        let interval = try #require(line.stations.indices.dropLast().first {
            line.stations[$0].id == "003615" && line.stations[$0 + 1].id == "003677"
        })
        let source = Array(CompactPackage.decodeIntervals(line)[interval].reversed())
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        let foreign = try #require(registry.junctions(for: "jp").first { $0.id == "kanda-tohoku-track" })
        let sourceKeys = Set(source.map(Grid.coordKey))
        let foreignKeys = Set([Grid.coordKey(foreign.from.coordinate), Grid.coordKey(foreign.to.coordinate)])
        let raw = try RouteGraph.SectionFeatureCollection.load(contentsOf:
            root.appending(path: "app/data/rail-sections.json")).features
        let sections = raw.filter { feature in
            guard feature.properties.operator == "東日本旅客鉄道" else { return false }
            let wanted = feature.properties.lineName == "中央線" ? sourceKeys :
                feature.properties.lineName == "東北線" ? foreignKeys : []
            return !wanted.isEmpty && feature.lines.joined().contains { wanted.contains(Grid.coordKey($0)) }
        }
        let graph = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [foreign])
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        let marker = try #require(source.first)
        let markerKeys = RouteGraph.exactNodeKeys(Grid.normalizeGraphCoord(marker), in: graph)
        #expect(!markerKeys.isEmpty)
        #expect(markerKeys.allSatisfy { graph.nodeMeta[$0]?.lineNames == ["東北線"] })
        let trimmed = try #require(RouteSolver.trimmedToGraphNodes(line: source, graph: graph,
            requiredLines: ["中央線"], requiredOperators: ["東日本旅客鉄道"], rideDate: "2026-10-10"))
        #expect(trimmed.first == source[1])
        #expect(trimmed.last == source[source.count - 2])
        let selected = RouteSection(lineNames: ["中央線"], operatorNames: ["東日本旅客鉄道"])
        let keys = try #require(RouteSolver.verifiedSourcePath([source], graph: graph,
            context: .init(rideDate: "2026-10-10"), section: selected, displayRowNames: ["中央線"]))
        #expect(keys.allSatisfy { graph.nodeMeta[$0]?.lineNames == ["中央線"] })
        // Removing a surveyed interior vertex remains invalid. Endpoint
        // qualification must not turn a shortcut into a certified route.
        var shortcut = source
        shortcut.remove(at: 3)
        #expect(RouteSolver.verifiedSourcePath([shortcut], graph: graph,
            context: .init(rideDate: "2026-10-10"), section: selected, displayRowNames: ["中央線"]) == nil)

        var currentSections = raw
        var noStations: [Stations.Feature] = []
        let history = try RailHistoryOverlay.load(from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(history, sections: &currentSections, stations: &noStations)
        let store = RouteGraph.RouteGraphStore(sections: currentSections, policy: .physicalRailway,
            junctions: registry.junctions(for: "jp"), cachePolicy: .bounded(maximumNodes: 100_000),
            identityPeriods: history.identityPeriods, sourceSnapshotID: UUID())
        let corridor = store.corridorGraph(for: source, meters: 1_000)
        let network = RouteNetwork(lines: [.init(lineId: line.id, name: line.name,
            operator: line.operator, isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
            parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line), compactLine: line)])
        let hints = RouteHints(requiredLineIDs: [line.id],
            sectionCodes: ["\(line.id)@003615:003677"], fromStationCode: "003677", toStationCode: "003615")
        let maybeCertified = network.sourceCertification(for: hints)
        let certified = try #require(maybeCertified)
        #expect(certified.geometry.lines == [source])
        #expect(certified.selectedLineIDs == [[line.id]])
        let corridorProof = RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "2026-07-05"), section: selected,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs)
        if corridorProof == nil {
            let qualified = RouteSolver.trimmedToGraphNodes(line: source, graph: corridor,
                requiredLines: ["中央線"], requiredOperators: ["東日本旅客鉄道"],
                rideDate: "2026-07-05", selectedLineIDs: [line.id])
            if let qualified {
                print("Kanda corridor trim=\(qualified.count) first=\(qualified.first!) last=\(qualified.last!)")
                let unscoped = RouteSolver.verifiedPhysicalPathKeys(qualified, graph: corridor,
                    rideDate: "2026-07-05", requiredLines: ["中央線"], requiredOperators: ["東日本旅客鉄道"])
                print("Kanda unscoped proof=\(unscoped ?? [])")
            } else { print("Kanda corridor endpoint qualification rejected") }
        }
        #expect(corridorProof != nil)
    }
}
