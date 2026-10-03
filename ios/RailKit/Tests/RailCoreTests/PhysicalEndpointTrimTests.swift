import Foundation
import Testing
@testable import RailCore

private struct PhysicalEndpointTrimPart: Decodable {
    let train: Train
}

@Suite(.serialized)
struct PhysicalEndpointTrimTests {
    private struct GapCounts {
        var boundaryStations: [String] = []
        var nonBoundary = 0
    }

    private struct RealData {
        let stations: Stations.Index
        let graphStore: RouteGraph.RouteGraphStore
        let intervals: RouteSolver.OfficialIntervalIndex
        let network: RouteNetwork
        let eligibility: StationRouteEligibility
        let resolver: StationIntervalResolver
    }

    private let origin = Coordinate(lon: 139, lat: 35)

    private func point(_ metresEast: Double) -> Coordinate {
        Coordinate(lon: origin.lon + metresEast / (111_320 * cos(origin.lat * .pi / 180)), lat: origin.lat)
    }

    private func rail(
        _ points: [Coordinate], line: String = "Rail",
        validFrom: String? = nil, validTo: String? = nil
    ) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator",
            institutionTypeCode: "1", validFrom: validFrom, validTo: validTo), lines: [points])
    }

    private func key(_ point: Coordinate, line: String = "Rail") -> String {
        RouteGraph.physicalNodeKey(point, identity: .init(
            operatorName: "Operator", lineName: line, railwayClassCode: ""))
    }

    @Test("Short endpoint marker bridges are trimmed before source verification")
    func endpointTrimming() throws {
        let a = point(0)
        let b = point(100)
        let c = point(200)
        let graph = RouteGraph.build(from: [rail([a, b, c])])
        let section = RouteSection(lineNames: ["Rail"], operatorNames: ["Operator"])

        let shortBridge = [point(-150), a, b, c, point(350)]
        let trimmed = try #require(RouteSolver.trimmedToGraphNodes(line: shortBridge, graph: graph))
        #expect(trimmed == [a, b, c])
        #expect(RouteSolver.verifiedSourcePath([shortBridge], graph: graph,
            context: .init(), section: section) != nil)

        let longBridge = [point(-300), a, b, c]
        #expect(RouteSolver.trimmedToGraphNodes(line: longBridge, graph: graph) == nil)
        #expect(RouteSolver.verifiedSourcePath([longBridge], graph: graph,
            context: .init(), section: section) == nil)

        let foldedLongBridge = [point(-150), point(-250), a, b]
        #expect(foldedLongBridge.dropLast(2).allSatisfy {
            Geometry.distanceMeters($0, a) <= RouteNetwork.endpointSnapMeters
        })
        #expect(RouteSolver.trimmedToGraphNodes(line: foldedLongBridge, graph: graph) == nil)

        let interiorOffNode = [a, point(50), b]
        #expect(RouteSolver.trimmedToGraphNodes(line: interiorOffNode, graph: graph) == interiorOffNode)
        #expect(RouteSolver.verifiedSourcePath([interiorOffNode], graph: graph,
            context: .init(), section: section) == nil)
    }

    @Test("Same-identity spans are bounded and cannot use other identities or connectors")
    func sameIdentityBoundaries() {
        let points = (0...6).map { point(Double($0) * 100) }
        let graph = RouteGraph.build(from: [rail(points)])
        #expect(RouteSolver.sameIdentitySpan(from: key(points[0]), to: key(points[5]),
            graph: graph, date: nil, maxMeters: 520))
        #expect(RouteSolver.sameIdentitySpan(from: key(points[0]), to: key(points[6]),
            graph: graph, date: nil, maxMeters: 520) == false)

        let identities = RouteGraph.build(from: [
            rail([points[0], points[1]], line: "West"),
            rail([points[1], points[2]], line: "East"),
        ])
        #expect(RouteSolver.sameIdentitySpan(from: key(points[1], line: "West"),
            to: key(points[1], line: "East"), graph: identities, date: nil) == false)

        let connectorGraph = RouteGraph.build(from: [
            rail([points[0], points[1]]), rail([points[2], points[3]]),
        ])
        let left = key(points[1])
        let right = key(points[2])
        let connector = RouteGraph.StationConnector(
            institutionTypeCodes: ["1"], stationName: "Central", groupCode: "shared")
        connectorGraph.adjacency[left, default: []].append(.init(
            to: right, length: 100, institutionTypeCode: "1", railwayClassCode: "",
            lineName: "Rail", operator: "Operator", connector: connector))
        connectorGraph.adjacency[right, default: []].append(.init(
            to: left, length: 100, institutionTypeCode: "1", railwayClassCode: "",
            lineName: "Rail", operator: "Operator", connector: connector))
        #expect(RouteSolver.sameIdentitySpan(from: left, to: right,
            graph: connectorGraph, date: nil) == false)
    }

    @Test("Same-identity spans reject an ordinary West-to-East-to-West detour")
    func sameIdentityOrdinaryDetour() throws {
        let points = (0...5).map { point(Double($0) * 100) }
        let graph = RouteGraph.build(from: [
            rail([points[0], points[1]], line: "West"),
            rail([points[2], points[3]], line: "East"),
            rail([points[4], points[5]], line: "West"),
        ])
        let westStart = key(points[1], line: "West")
        let eastEntry = key(points[2], line: "East")
        let eastExit = key(points[3], line: "East")
        let westEnd = key(points[4], line: "West")
        for (from, to) in [(westStart, eastEntry), (eastExit, westEnd)] {
            graph.adjacency[from, default: []].append(.init(
                to: to, length: 100, institutionTypeCode: "1", railwayClassCode: "",
                lineName: "Rail", operator: "Operator", connector: nil))
        }
        func ordinary(_ from: String, _ to: String) -> RouteGraph.Edge? {
            graph.adjacency[from]?.first {
                $0.to == to && $0.connector == nil && $0.physicalJunction == nil
            }
        }
        let enteringEast = try #require(ordinary(westStart, eastEntry))
        let alongEast = try #require(ordinary(eastEntry, eastExit))
        let returningWest = try #require(ordinary(eastExit, westEnd))
        // Equal endpoint identities force the in-search identity filter to run.
        #expect(westStart.prefix { $0 != "@" } == westEnd.prefix { $0 != "@" })
        #expect(westStart.prefix { $0 != "@" } != eastEntry.prefix { $0 != "@" })
        #expect(westStart != westEnd)
        #expect(RouteSolver.sameIdentitySpan(from: westStart, to: westEnd, graph: graph, date: nil,
            maxMeters: enteringEast.length + alongEast.length + returningWest.length) == false)
    }

    @Test("Same-identity spans reject a West-junction-East-junction-West path")
    func sameIdentityPhysicalJunctionDetour() throws {
        let points = (0...3).map { point(Double($0) * 100) }
        func track(_ line: String) -> RouteGraph.TrackIdentity {
            .init(operatorName: "Operator", lineName: line, railwayClassCode: "")
        }
        func junction(_ id: String, at: Coordinate, from: String, to: String) -> RouteGraph.PhysicalJunction {
            .init(id: id, from: .init(identity: track(from), coordinate: at),
                to: .init(identity: track(to), coordinate: at), evidence: ["survey:reviewed"])
        }
        let graph = RouteGraph.build(from: [
            rail([points[0], points[1]], line: "West"),
            rail([points[1], points[2]], line: "East"),
            rail([points[2], points[3]], line: "West"),
        ], junctions: [
            junction("west-to-east", at: points[1], from: "West", to: "East"),
            junction("east-to-west", at: points[2], from: "East", to: "West"),
        ])
        #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
        let westStart = key(points[1], line: "West")
        let eastStart = key(points[1], line: "East")
        let eastEnd = key(points[2], line: "East")
        let westEnd = key(points[2], line: "West")
        let intoEast = try #require(graph.adjacency[westStart]?.first {
            $0.to == eastStart && $0.physicalJunction?.junction.id == "west-to-east"
        })
        let alongEast = try #require(graph.adjacency[eastStart]?.first {
            $0.to == eastEnd && $0.connector == nil && $0.physicalJunction == nil
        })
        let intoWest = try #require(graph.adjacency[eastEnd]?.first {
            $0.to == westEnd && $0.physicalJunction?.junction.id == "east-to-west"
        })
        #expect(westStart.prefix { $0 != "@" } == westEnd.prefix { $0 != "@" })
        #expect(westStart.prefix { $0 != "@" } != eastStart.prefix { $0 != "@" })
        #expect(RouteSolver.sameIdentitySpan(from: westStart, to: westEnd, graph: graph, date: nil,
            maxMeters: intoEast.length + alongEast.length + intoWest.length) == false)
    }

    @Test("Same-identity spans honor rail validity dates")
    func sameIdentityValidity() {
        let a = point(0)
        let b = point(100)
        let graph = RouteGraph.build(from: [rail([a, b], validFrom: "2025-01-01")])
        #expect(RouteSolver.sameIdentitySpan(from: key(a), to: key(b),
            graph: graph, date: "2025-01-01"))
        #expect(RouteSolver.sameIdentitySpan(from: key(a), to: key(b),
            graph: graph, date: "2024-12-31") == false)
    }

    @Test("Endpoint trimming preserves the two reference rides' exact physical gaps")
    func referenceRideGapCounts() throws {
        let root = try PortFixtures.repositoryRoot()
        let data = try loadRealData(root: root)

        let hikari = try gapCounts(
            fixture: "part-001", expectedID: "20260703_02_tokaido_shinkansen_hikari_kodama",
            branch: .source, root: root, data: data)
        #expect(hikari.boundaryStations.isEmpty)
        #expect(hikari.nonBoundary == 0)

        let oki = try gapCounts(
            fixture: "part-097", expectedID: "20260719_03_super_oki5",
            branch: .legacy, root: root, data: data)
        #expect(oki.boundaryStations == ["益田"])
        #expect(oki.nonBoundary == 0)
    }

    private func loadRealData(root: URL) throws -> RealData {
        let dataRoot = root.appending(path: "app/data")
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: dataRoot.appending(path: "rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: dataRoot.appending(path: "stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: dataRoot.appending(path: "rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            dataRoot.appending(path: "physical-rail-junctions.json")))
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway, junctions: registry.junctions(for: "jp"))
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let network = RouteNetwork(lines: loaded.package.lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator, isLoop: line.isLoop,
                alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line, topology: loaded.topologyByLineID[line.id] ?? .init()),
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
        return RealData(
            stations: Stations.Index(Stations.FeatureCollection(features: stationFeatures)),
            graphStore: graphStore,
            intervals: RouteSolver.OfficialIntervalIndex(sections: sections),
            network: network,
            eligibility: StationRouteEligibility(
                network: network, sections: sections, stations: stationFeatures),
            resolver: StationIntervalResolver(network: network))
    }

    private func proofGraph(
        _ coordinates: [Coordinate], store: RouteGraph.RouteGraphStore
    ) -> RouteGraph.Graph {
        let box = RouteGraph.BBox(
            minX: coordinates.map(\.lon).min()!, minY: coordinates.map(\.lat).min()!,
            maxX: coordinates.map(\.lon).max()!, maxY: coordinates.map(\.lat).max()!)
        return store.regionalGraph(for: RouteGraph.padBBoxMeters(box, meters: 1_000),
            routeSolveInProgress: true)
    }

    private enum ReferenceBranch { case source, legacy }

    private func gapCounts(
        fixture: String, expectedID: String, branch: ReferenceBranch,
        root: URL, data: RealData
    ) throws -> GapCounts {
        let part = try JSONDecoder().decode(PhysicalEndpointTrimPart.self, from: Data(contentsOf:
            root.appending(path: "app/data/sample-data/\(fixture).json")))
        let train = TokyoConventionalRouteInference.applying(to: TrainValidation.normalizeExportTrain(
            TrainValidation.restoringRouteSectionEndpointNames(part.train), country: "jp",
            stations: TrainValidation.StationTable.empty))
        let sections = train.routeSections ?? []
        try #require(train.id == expectedID)
        try #require(sections.isEmpty == false)
        let context = RouteSolver.TrainContext(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin, destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: Dates.normalizeDateString(train.date))
        let allowedCodes = RouteGraph.allowedInstitutionTypeCodes(.init(
            trainType: context.trainType, company: context.company,
            preferredLineNames: context.preferredLineNames,
            preferredOperatorNames: context.preferredOperatorNames,
            allowedInstitutionTypeCodes: context.allowedInstitutionTypeCodes,
            institutionFilterMode: context.institutionFilterMode), country: "jp")
        let inferred = RouteSolver.inferStationSections(
            sections, resolver: data.resolver, network: data.network, eligibility: data.eligibility,
            allowedCodes: allowedCodes, hard: context.institutionFilterMode == "hard")
        try #require(inferred.ambiguous.isEmpty)

        var counts = GapCounts()
        var lastSolvedIndex: Int?
        var physicalKey: String?
        var continuity: Coordinate?
        var displayContinuity: Coordinate?
        var projectionCache = RouteProjectionCache()

        for (index, section) in sections.enumerated() {
            let sharesBoundary = index > 0 && lastSolvedIndex == index - 1
                && RouteSolver.routeSectionBoundarySharesExplicitStop(sections[index - 1], section)
            let previousKey = sharesBoundary ? physicalKey : nil
            let anchor = sharesBoundary ? continuity : nil
            switch branch {
            case .source:
                try #require(section.sectionCodes?.isEmpty == false || inferred.hints[index] != nil)
                var hints = inferred.hints[index] ?? RouteHints(
                    requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                hints.fromStationCode = data.eligibility.stationCode(hints.fromStationCode)
                    ?? hints.fromStationCode
                hints.toStationCode = data.eligibility.stationCode(hints.toStationCode)
                    ?? hints.toStationCode
                let source = try #require(data.network.sourceGeometry(for: hints))
                let exact = try #require(data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: nil, hints: hints),
                    continueFrom: displayContinuity, cache: &projectionCache))
                try #require(source.lines.count == exact.geometry.lines.count)
                let graph = proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
                let keys = RouteSolver.verifiedSourcePath(
                    source.lines, graph: graph, context: context, section: section)
                if keys == nil { counts.nonBoundary += 1 }
                if sharesBoundary,
                   !(previousKey.flatMap { previous in keys?.first.map { first in
                       RouteSolver.physicalBoundaryIsProven(from: previous, to: first,
                           graph: graph, rideDate: context.rideDate)
                   } } ?? false) {
                    counts.boundaryStations.append(section.from ?? "")
                }
                physicalKey = keys?.last
                continuity = source.lines.last?.last
                displayContinuity = exact.geometry.lines.last?.last

            case .legacy:
                try #require(section.sectionCodes?.isEmpty != false && inferred.hints[index] == nil)
                var solved = RouteSolver.solveOfficialInterval(
                    section, segmentIndex: index, train: context, country: "jp",
                    allowedCodes: allowedCodes, intervalIndex: data.intervals,
                    stations: data.stations, continuityAnchor: anchor)
                    ?? RouteSolver.solveSectionOnDemand(
                        section, segmentIndex: index, train: context, country: "jp",
                        graphStore: data.graphStore, stations: data.stations,
                        continuityAnchor: anchor, physicalContinuationKey: previousKey,
                        traversalPolicy: .physicalRail)
                if solved == nil, sharesBoundary {
                    solved = RouteSolver.solveSectionOnDemand(
                        section, segmentIndex: index, train: context, country: "jp",
                        graphStore: data.graphStore, stations: data.stations,
                        traversalPolicy: .physicalRail)
                }
                var resolved = try #require(solved)
                try #require(resolved.coordinates.count >= 2)
                let solvedGraph = proofGraph(resolved.coordinates, store: data.graphStore)
                if resolved.rawPathKeys.first?.contains("@") != true {
                    resolved.rawPathKeys = RouteSolver.verifiedPhysicalPathKeys(
                        resolved.coordinates, graph: solvedGraph, rideDate: context.rideDate,
                        requiredLines: Set(section.lineNames ?? []),
                        requiredOperators: Set(section.operatorNames ?? [])) ?? []
                }
                if resolved.rawPathKeys.isEmpty { counts.nonBoundary += 1 }
                if sharesBoundary,
                   !(previousKey.flatMap { previous in resolved.rawPathKeys.first.map { first in
                       RouteSolver.physicalBoundaryIsProven(from: previous, to: first,
                           graph: proofGraph([resolved.coordinates[0]], store: data.graphStore),
                           rideDate: context.rideDate)
                   } } ?? false) {
                    counts.boundaryStations.append(section.from ?? "")
                }
                physicalKey = resolved.rawPathKeys.last
                continuity = resolved.coordinates.last

                let hints = RouteHints(
                    requiredLineNames: (section.lineNames ?? []).map(Optional.some),
                    preferredLineNames: context.preferredLineNames.map(Optional.some),
                    requiredOperatorNames: (section.operatorNames ?? []).map(Optional.some),
                    preferredOperatorNames: context.preferredOperatorNames.map(Optional.some),
                    requiredLineIDs: section.lineIDs ?? [], sectionCodes: section.sectionCodes ?? [],
                    fromStationCode: section.fromN02StationCode,
                    toStationCode: section.toN02StationCode)
                let canonical = data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: .lineString(resolved.coordinates), hints: hints),
                    continueFrom: nil, cache: &projectionCache)
                try #require(canonical?.matchedSectionCodes.isEmpty != false)
            }
            lastSolvedIndex = index
        }
        return counts
    }
}
