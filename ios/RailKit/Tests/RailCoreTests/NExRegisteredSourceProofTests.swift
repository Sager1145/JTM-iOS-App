import Foundation
import Testing
@testable import RailCore

struct NExRegisteredSourceProofTests {
    @Test("Duplicate edge records preserve one proof while distinct node walks remain ambiguous")
    func duplicateRecordsVersusDistinctWalks() throws {
        func point(_ metres: Double) -> Coordinate {
            Coordinate(lon: 139 + metres / (111_320 * cos(35 * .pi / 180)), lat: 35)
        }
        func rail(_ points: [Coordinate]) -> RouteGraph.SectionFeature {
            .init(properties: .init(lineName: "Rail", operator: "Operator", institutionTypeCode: "1"),
                lines: [points])
        }
        let source = [point(0), point(50), point(200)]
        let duplicate = RouteGraph.build(from: [rail([point(0), point(100), point(200)])], policy: .physicalRailway)
        for key in Array(duplicate.adjacency.keys) {
            let edges = duplicate.adjacency[key] ?? []
            duplicate.adjacency[key] = edges + edges
        }
        #expect(RouteSolver.verifiedPhysicalPathKeys(source, graph: duplicate, rideDate: nil,
            requiredLines: ["Rail"], requiredOperators: ["Operator"]) != nil)
        let branched = RouteGraph.build(from: [rail([point(0), point(100), point(200)]),
            rail([point(0), point(110), point(200)])], policy: .physicalRailway)
        #expect(RouteSolver.verifiedPhysicalPathKeys(source, graph: branched, rideDate: nil,
            requiredLines: ["Rail"], requiredOperators: ["Operator"]) == nil)
    }
    @Test("NEx Tokyo–Shinagawa source has one physical walk across overlapping registered surveys")
    func overlappingRegisteredSurveyProof() throws {
        let root = try PortFixtures.repositoryRoot()
        let package = try CompactPackage.load(contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let line = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let intervals = CompactPackage.decodeIntervals(line)
        let source = intervals[0] + intervals[1].dropFirst()
        #expect(source.count == 92)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        let selected = registry.junctions(for: "jp").filter {
            ["tokyo-tokaido-shimbashi", "shimbashi-tokaido-shinagawa"].contains($0.id)
        }
        #expect(selected.count == 2)
        let endpointKeys = Set(selected.flatMap { [Grid.coordKey($0.from.coordinate), Grid.coordKey($0.to.coordinate)] })
        let raw = try RouteGraph.SectionFeatureCollection.load(contentsOf:
            root.appending(path: "app/data/rail-sections.json")).features
        let sections = raw.filter {
            $0.properties.operator == "東日本旅客鉄道" && $0.properties.lineName == "東海道線"
                && $0.lines.joined().contains { endpointKeys.contains(Grid.coordKey($0)) }
        }
        let graph = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: selected)
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        let trimmed = try #require(RouteSolver.trimmedToGraphNodes(line: source, graph: graph,
            requiredLines: ["東海道線"], requiredOperators: ["東日本旅客鉄道"], rideDate: "2026-07-27"))
        let first = try #require(trimmed.first)
        let offset = try #require(source.firstIndex(of: first))
        let anchors: Set<Int> = [intervals[0].count - 1 - offset]
        let proof = RouteSolver.verifiedPhysicalPathKeys(trimmed, graph: graph, rideDate: "2026-07-27",
            requiredLines: ["東海道線"], requiredOperators: ["東日本旅客鉄道"], anchorIndices: anchors)
        if proof == nil {
            // Probe only actual graph-node prefixes; non-node terminal markers
            // alone cannot finish a physical proof.
            for end in 1..<trimmed.count where !RouteGraph.exactNodeKeys(
                Grid.normalizeGraphCoord(trimmed[end]), in: graph).isEmpty {
                let prefix = Array(trimmed[...end])
                if RouteSolver.verifiedPhysicalPathKeys(prefix, graph: graph, rideDate: "2026-07-27",
                    requiredLines: ["東海道線"], requiredOperators: ["東日本旅客鉄道"],
                    anchorIndices: anchors.filter { $0 < end }) == nil {
                    print("NEx first rejected node prefix sourceIndex=\(end + offset) previous=\(trimmed[end - 1]) node=\(trimmed[end])")
                    break
                }
            }
        }
        #expect(proof != nil)

        // Match production's bounded corridor extraction, including other
        // identities and every registered overlay that reaches this source.
        var currentSections = raw
        var noStations: [Stations.Feature] = []
        let history = try RailHistoryOverlay.load(from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(history, sections: &currentSections, stations: &noStations)
        let store = RouteGraph.RouteGraphStore(sections: currentSections, policy: .physicalRailway,
            junctions: registry.junctions(for: "jp"), cachePolicy: .bounded(maximumNodes: 100_000),
            identityPeriods: history.identityPeriods, sourceSnapshotID: UUID())
        let corridor = store.corridorGraph(for: source, meters: 1_000)
        let visits = [Stop(name: "東京", n02StationCode: "003766"),
                      Stop(name: "品川", n02StationCode: "004095")]
        let sparse = Train(id: "public-nex-proof", date: "2026-07-27", number: "Narita Express",
            trainType: "express", origin: "東京", destination: "品川",
            routeSections: [RouteSection(from: "東京", to: "品川",
                fromN02StationCode: "003766", toN02StationCode: "004095")], stops: visits, region: "jp")
        let actualSection = try #require(RegistryIdentityTestGate.withProvider({ region in
            region == "jp" ? RegistryIdentity(bundle: RegistryBundle(region: "jp", run: 1)) : nil
        }) {
            TokyoConventionalRouteInference.applying(to: sparse, package: package).routeSections?.first
        })
        #expect(actualSection.lineNames == ["総武線"])
        #expect(actualSection.lineIDs == [line.id])
        #expect(actualSection.sectionCodes == ["\(line.id)@003766:003872", "\(line.id)@003872:004095"])
        let network = RouteNetwork(lines: [.init(lineId: line.id, name: line.name,
            operator: line.operator, isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
            parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line), compactLine: line)])
        let actualHints = RouteHints(requiredLineIDs: actualSection.lineIDs ?? [],
            sectionCodes: actualSection.sectionCodes ?? [],
            fromStationCode: actualSection.fromN02StationCode, toStationCode: actualSection.toN02StationCode)
        let certified = try #require(network.sourceCertification(for: actualHints))
        #expect(certified.geometry.lines == [source])
        #expect(certified.rowNames == ["総武線"])
        let corridorProof = RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "2026-07-27"),
            section: actualSection,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs)
        if corridorProof == nil {
            print("NEx production corridor proof rejected; nodes=\(corridor.nodes.count) rejectedRegistry=\(corridor.rejectedPhysicalJunctionIDs)")
            if let bounded = RouteSolver.trimmedToGraphNodes(line: source, graph: corridor,
                requiredLines: ["東海道線"], requiredOperators: ["東日本旅客鉄道"], rideDate: "2026-07-27"),
               let first = bounded.first, let start = source.firstIndex(of: first) {
                for end in 1..<bounded.count where !RouteGraph.exactNodeKeys(
                    Grid.normalizeGraphCoord(bounded[end]), in: corridor).isEmpty {
                    if RouteSolver.verifiedPhysicalPathKeys(Array(bounded[...end]), graph: corridor,
                        rideDate: "2026-07-27", requiredLines: ["東海道線"],
                        requiredOperators: ["東日本旅客鉄道"],
                        anchorIndices: Set([intervals[0].count - 1 - start].filter { $0 < end })) == nil {
                        print("NEx corridor first rejected node prefix sourceIndex=\(end + start) previous=\(bounded[end - 1]) node=\(bounded[end])")
                        break
                    }
                }
            } else {
                print("NEx corridor endpoint qualification rejected")
            }
        }
        #expect(corridorProof != nil)
        #expect(certified.selectedLineIDs == [[line.id]])
        let memo = RouteResolutionMemo()
        let snapshotProvenance = corridor.sourceProofProvenance
        let provenance = try #require(snapshotProvenance)
        let retained = try memo.proof(lines: certified.geometry.lines,
            context: .init(rideDate: "2026-07-27"), section: actualSection, graphProvenance: provenance,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs) { corridorProof }
        #expect(retained == corridorProof)
        var examinedWrongRow = false
        let wrongRow = try memo.proof(lines: certified.geometry.lines,
            context: .init(rideDate: "2026-07-27"), section: actualSection, graphProvenance: provenance,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: [["jp-unregistered-row"]]) {
                examinedWrongRow = true
                return nil
            }
        #expect(examinedWrongRow)
        #expect(wrongRow == nil)
        // A successful graph memo must not lend that registry ownership to
        // another selected display row or to an unbound source request.
        #expect(RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "2026-07-27"), section: actualSection,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: [["jp-unregistered-row"]]) == nil)
        #expect(RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "2026-07-27"), section: actualSection,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices) == nil)
        #expect(RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "1900-01-01"), section: actualSection,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs) == nil)
        let rawSection = try #require(sections.first)
        let rawSource = try #require(rawSection.lines.first)
        let unbound = RouteGraph.build(from: [rawSection], policy: .physicalRailway)
        #expect(RouteSolver.verifiedSourcePath([rawSource], graph: unbound,
            context: .init(rideDate: "2026-07-27"), section: actualSection,
            selectedLineIDs: [[line.id]]) == nil)
        let original = try #require(selected.first)
        let rejected = RouteGraph.PhysicalJunction(id: "rejected-owned-source",
            from: .init(identity: original.from.identity,
                coordinate: .init(lon: 139, lat: 35)), to: original.to, evidence: original.evidence,
            validFrom: original.validFrom, validTo: original.validTo, kind: original.kind,
            path: original.path, source: original.source, attachMeters: original.attachMeters,
            lineIDs: original.lineIDs)
        let declaredOnly = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: [rejected])
        #expect(declaredOnly.rejectedPhysicalJunctionIDs == [rejected.id])
        #expect(declaredOnly.adjacency.values.joined().allSatisfy { $0.registeredTrackLineIDs.isEmpty })
        // Expiring installed records invalidates graph proofs and forbids
        // falling back to raw Tokaido edges under the Sobu selection.
        for key in Array(corridor.adjacency.keys) {
            var edges = corridor.adjacency[key] ?? []
            for index in edges.indices where !edges[index].registeredTrackLineIDs.isEmpty {
                edges[index].validTo = "2026-07-27"
            }
            corridor.adjacency[key] = edges
        }
        #expect(RouteSolver.verifiedSourcePath(certified.geometry.lines, graph: corridor,
            context: .init(rideDate: "2026-07-27"), section: actualSection,
            displayRowNames: certified.rowNames, anchorIndices: certified.anchorIndices,
            selectedLineIDs: certified.selectedLineIDs) == nil)
    }
}
