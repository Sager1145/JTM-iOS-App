import Foundation
import Testing
@testable import RailCore

struct RouteDirectionAndBranchTests {
    @Test("Direction exclusions follow changed survey geometry with identical network metadata")
    func directionCacheFollowsGeometry() throws {
        let a = Coordinate(lon: 139, lat: 35)
        let b = Coordinate(lon: 139.1, lat: 35)
        let lineID = "direction-cache-geometry-regression"
        let forward = RouteSection(fromN02StationCode: "000001", toN02StationCode: "000002",
            lineNames: [lineID], operatorNames: ["Operator"])
        let reverse = RouteSection(fromN02StationCode: "000002", toN02StationCode: "000001",
            lineNames: [lineID], operatorNames: ["Operator"])
        // Revisit the first snapshot too: a changed generation must neither
        // weaken its restriction nor poison a previously cached valid solve.
        for middle in [Coordinate(lon: 139.05, lat: 35.01), Coordinate(lon: 139.05, lat: 35.02),
                       Coordinate(lon: 139.05, lat: 35.01)] {
            let points = [a, middle, b]
            var row = line(lineID, ["000001", "000002"], direction: "up")
            row["stations"] = [["000001", "A", a.lon, a.lat], ["000002", "B", b.lon, b.lat]] as [[Any]]
            row["segments"] = [[10, 0, points.map(\.pair)]] as [[Any]]
            let package = try fixture([row])
            let compact = try #require(package.lines.first)
            #expect(RailwayDirection.allowedDirections(for: compact, intervalIndex: 0) == [1])
            let network = RouteNetwork(lines: [.init(lineId: lineID, name: lineID, operator: "Operator",
                isLoop: false, alignmentDirection: "up", parts: [points],
                intervals: RailIntervalCodes.intervals(for: compact), compactLine: compact)])
            let graph = RouteGraph.build(from: [.init(properties: .init(lineName: lineID,
                operator: "Operator", institutionTypeCode: "1"), lines: [points])])
            let stations = Stations.Index(compact.stations.map { station in
                Stations.Feature(properties: ["n02_station_code": .string(station.id),
                    "station_name": .string(station.name), "line_name": .string(lineID),
                    "operator": .string("Operator"), "institution_type_code": .string("1")],
                    geometry: .init(type: "Point", coordinates: .array([
                        .number(station.coordinate.lon), .number(station.coordinate.lat)])))
            })
            let allowed = try #require(RouteSolver.solveSection(forward, segmentIndex: 0,
                train: .init(), country: "jp", graph: graph, stations: stations, directionNetwork: network))
            #expect(allowed.coordinates == points)
            #expect(RouteSolver.solveSection(reverse, segmentIndex: 0, train: .init(), country: "jp",
                graph: graph, stations: stations, directionNetwork: network) == nil)
        }
    }

    @Test("Recorded direction uniquely selects the up or down alignment", arguments: [false, true])
    func directedRoute(reverse: Bool) throws {
        let package = try fixture([
            line("a", ["A", "B"], direction: "up"),
            line("c", ["A", "C", "B"], direction: "down"),
        ])
        let original = RailwayRouteEditing.preparing(train(reverse ? ["B", "A"] : ["A", "B"]))
        let result = RecordedRouteAdmission.search(in: original, package: package)
        #expect(result.choices.count == 1)
        #expect(result.isTruncated == false)
        #expect(result.topologyIsComplete == false)
        #expect(result.directionIsKnown)
        #expect(result.isUniqueWithinPackage)
        let choice = try #require(RecordedRouteAdmission.uniqueChoice(for: result))
        #expect(choice.lineIDs == [reverse ? "c" : "a"])
        #expect(choice.stations.map(\.code) == (reverse ? ["B", "C", "A"] : ["A", "B"]))
        let plan = try #require(RailwayRouteEditing.plan(train: original, choice: choice))
        #expect(plan.requiresConfirmation == false)
        #expect(plan.insertedStops.count == (reverse ? 1 : 0))
        if reverse {
            let passing = try #require(plan.insertedStops.first)
            #expect(passing.n02StationCode == "C")
            #expect(passing.stopType == "pass_through")
            #expect(passing.arrival == nil && passing.departure == nil)
            #expect(passing.actualArrival == nil && passing.actualDeparture == nil)
            #expect(RailwayRouteEditing.isUntouchedGenerated(passing))
        }
        #expect(plan.undo.restore(in: plan.updatedTrain) == original)
    }

    @Test("Every bidirectional branch remains a user choice", arguments: [2, 3], [false, true])
    func branches(count: Int, reverse: Bool) throws {
        let rows = [line("a", ["A", "B"]), line("b", ["A", "D", "B"]),
                    line("third", ["A", "E", "B"])]
        let result = RecordedRouteAdmission.search(in: train(reverse ? ["B", "A"] : ["A", "B"]),
            package: try fixture(Array(rows.prefix(count))))
        #expect(result.choices.count == count)
        #expect(Set(result.choices.flatMap(\.lineIDs)) == Set(rows.prefix(count).compactMap { $0["id"] as? String }))
        #expect(result.isTruncated == false)
        #expect(result.hasAmbiguity)
        #expect(RecordedRouteAdmission.uniqueChoice(for: result) == nil)
    }

    @Test("Unknown train direction and truncated searches cannot auto-complete")
    func incompleteEvidence() throws {
        let package = try fixture([line("a", ["A", "B"]), line("b", ["A", "D", "B"])])
        let limited = RecordedRouteAdmission.search(in: train(["A", "B"]), package: package, maximumChoices: 1)
        #expect(limited.choices.count == 1)
        #expect(limited.isTruncated)
        #expect(RecordedRouteAdmission.uniqueChoice(for: limited) == nil)
        let unknown = LocalJourneySearch.search(package: try fixture([line("a", ["A", "B"])]),
            originCode: "A", destinationCode: "B")
        #expect(unknown.isUniqueWithinPackage)
        #expect(unknown.directionIsKnown == false)
        #expect(RecordedRouteAdmission.uniqueChoice(for: unknown) == nil)
        #expect(RecordedRouteAdmission.uniqueChoice(for: RecordedRouteAdmission.search(in: train(["A", "missing"]), package: package)) == nil)
    }

    @Test("Hakodate to Mori can use the encoded down-only Fujishiro row; reverse cannot")
    func hakodateDirection() throws {
        let source = try PortFixtures.package(country: "jp")
        let mainID = "jp-北海道旅客鉄道-函館線"
        let fujishiroID = mainID + "-p1"
        let package = CompactPackage(format: source.format, version: source.version, country: source.country,
            lines: source.lines.filter { $0.id == mainID || $0.id == mainID + "-2" || $0.id == fujishiroID })
        let fujishiro = try #require(package.lines.first { $0.id == fujishiroID })
        #expect(fujishiro.stations.map(\.name) == ["七飯", "大沼"])
        #expect(RailwayDirection.allowedDirections(for: fujishiro, intervalIndex: 0) == [1])
        let down = RecordedRouteAdmission.search(in: train(["000455", "000420"]), package: package)
        let up = RecordedRouteAdmission.search(in: train(["000420", "000455"]), package: package)
        #expect(down.choices.contains { $0.lineIDs.contains(fujishiroID) })
        #expect(up.choices.isEmpty == false)
        #expect(up.choices.allSatisfy { $0.lineIDs.contains(fujishiroID) == false })
        // The source leaves the main pairing unassigned and omits 仁山.
        // Do not manufacture a one-way main alignment or the missing station.
    }

    @Test("Hokuto stops retain the Niyama alignment in both directions", arguments: [false, true], [false, true])
    func hokutoDisplayPipeline(reverse: Bool, autocomplete: Bool) throws {
        try displayPipeline(reverse: reverse, autocomplete: autocomplete, twoStops: false)
    }

    @Test("Nanae–Onuma display respects the down-only Fujishiro alignment", arguments: [false, true], [false, true])
    func nanaeOnumaDisplayPipeline(reverse: Bool, autocomplete: Bool) throws {
        try displayPipeline(reverse: reverse, autocomplete: autocomplete, twoStops: true)
    }

    private func displayPipeline(reverse: Bool, autocomplete: Bool, twoStops: Bool) throws {
        let package = try PortFixtures.package(country: "jp")
        let mainID = "jp-北海道旅客鉄道-函館線"
        let main = try #require(package.lines.first { $0.id == mainID })
        let branch = try #require(package.lines.first { $0.id == mainID + "-p1" })
        let visits = twoStops ? ["000431", "000427"] : ["000455", "000439", "000429", "000426", "000420"]
        let ordered = reverse ? Array(visits.reversed()) : visits
        var ride = Train(id: "hakodate-direction", number: twoStops ? "Test" : "北斗", origin: ordered.first!,
            destination: ordered.last!, stops: try ordered.map { code in
                let station = try #require(main.stations.first { $0.id == code })
                return Stop(name: station.name, n02StationCode: code)
            })
        #expect(ride.routeSections == nil)
        if autocomplete {
            let prepared = RailwayRouteEditing.preparing(ride)
            // Keep every Hakodate family branch. Searching the entire Japan
            // package hits the bounded search limit before proving uniqueness.
            let corridor = CompactPackage(format: package.format, version: package.version,
                country: package.country, lines: package.lines.filter {
                    $0.id == mainID || $0.id == mainID + "-2" || $0.id == branch.id
                })
            let result = RecordedRouteAdmission.search(in: prepared, package: corridor)
            if twoStops {
                for choice in result.choices {
                    let km = choice.sectionCodes.reduce(0.0) { total, code in
                        total + corridor.lines.reduce(0.0) { sum, line in
                            sum + zip(RailIntervalCodes.intervals(for: line), line.segments)
                                .filter { $0.0.code == code }.reduce(0.0) { $0 + $1.1.distanceKm }
                        }
                    }
                    print("CHOICE reverse=\(reverse) lines=\(choice.lineIDs) sections=\(choice.sectionCodes) visits=\(choice.stations.map { "\($0.name):\($0.code)" }) km=\(km)")
                }
            }
            if twoStops {
                #expect(!result.isTruncated)
                if reverse {
                    let choice = try #require(RecordedRouteAdmission.uniqueChoice(for: result))
                    #expect(choice.lineIDs == [mainID])
                    #expect(choice.stations.map(\.code) == ["000427", "000429", "000431"])
                    #expect(choice.sectionCodes == [mainID + "@000427:000429", mainID + "@000429:000431"])
                } else {
                    #expect(result.choices.count == 2)
                    #expect(RecordedRouteAdmission.uniqueChoice(for: result) == nil)
                    #expect(Set(result.choices.map(\.lineIDs)) == Set([[mainID], [branch.id]]))
                    #expect(Set(result.choices.map(\.sectionCodes)).count == 2)
                }
            }
            let choice = try #require(twoStops && !reverse
                ? result.choices.first { $0.lineIDs.contains(branch.id) }
                : RecordedRouteAdmission.uniqueChoice(for: result))
            if reverse || !twoStops { #expect(!choice.lineIDs.contains(branch.id)) }
            let plan = try #require(RailwayRouteEditing.plan(train: prepared, choice: choice))
            if twoStops && reverse { #expect(!plan.requiresConfirmation) }
            ride = plan.updatedTrain
        }
        let sections = StoreOperations.rideRouteSections(for: ride)
        try #require(!sections.isEmpty)
        let pipeline = PhysicalEndpointTrimTests()
        let data = try pipeline.loadRealData(root: PortFixtures.repositoryRoot())
        let context = RouteSolver.TrainContext(id: ride.id, number: ride.number,
            origin: ride.origin, destination: ride.destination)
        let inferred = RouteSolver.inferStationSections(sections, resolver: data.resolver,
            network: data.network, eligibility: data.eligibility, allowedCodes: ["1"], hard: false)
        #expect(inferred.ambiguous.isEmpty)
        let branchCodes = Set(RailIntervalCodes.intervals(for: branch).map(\.code))
        var drawn: [Coordinate] = []
        var matchedCodes: [String] = []
        var cache = RouteProjectionCache()
        for (index, section) in sections.enumerated() {
            let hints = inferred.hints[index] ?? RouteHints(requiredLineIDs: section.lineIDs ?? [],
                sectionCodes: section.sectionCodes ?? [], fromStationCode: section.fromN02StationCode,
                toStationCode: section.toN02StationCode)
            if !hints.sectionCodes.isEmpty, let source = data.network.sourceCertification(for: hints)?.geometry {
                let exact = try #require(data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: nil, hints: hints), continueFrom: drawn.last, cache: &cache))
                let graph = pipeline.proofGraph(source.lines.flatMap { $0 }, store: data.graphStore)
                #expect(RouteSolver.verifiedSourcePath(source.lines, graph: graph,
                    context: context, section: section) != nil)
                drawn += exact.geometry.lines.flatMap { $0 }
                matchedCodes += hints.sectionCodes
            } else {
                let solved = try #require(RouteSolver.solveSectionOnDemand(section, segmentIndex: index,
                    train: context, country: "jp", graphStore: data.graphStore, stations: data.stations, directionNetwork: data.network))
                let graph = pipeline.proofGraph(solved.coordinates, store: data.graphStore)
                #expect(RouteSolver.verifiedSourcePath([solved.coordinates], graph: graph,
                    context: context, section: section) != nil)
                let exact = data.network.canonicalizeRouteFeature(
                    RouteFeature(geometry: .lineString(solved.coordinates), hints: hints),
                    continueFrom: drawn.last, cache: &cache)
                drawn += exact?.geometry.lines.flatMap { $0 } ?? solved.coordinates
                matchedCodes += exact?.matchedSectionCodes ?? []
            }
        }
        if reverse || !twoStops { #expect(Set(matchedCodes).isDisjoint(with: branchCodes)) }
        // 新函館北斗 is on the main line, not the 七飯–大沼 bypass. Direction
        // permission does not authorize skipping an explicit visit or reversing
        // to 七飯. Both Hokuto stop orders therefore require the 仁山 alignment.
        let mainInterval = try #require(RailIntervalCodes.intervals(for: main).first {
            $0.fromStationCode == "000429" && $0.toStationCode == "000427"
        })
        let branchInterval = try #require(RailIntervalCodes.intervals(for: branch).first)
        func separation(_ point: Coordinate, from line: [Coordinate]) -> Double {
            line.map { Geometry.distanceMeters(point, $0) }.min() ?? .infinity
        }
        let mainWitness = try #require(mainInterval.coordinates.max {
            separation($0, from: branchInterval.coordinates) < separation($1, from: branchInterval.coordinates)
        })
        // Compare against the whole approach: the bypass shares the southern
        // trunk, so 七飯 itself is not evidence of using its exclusive geometry.
        let mainApproach = RailIntervalCodes.intervals(for: main).prefix(7).flatMap(\.coordinates)
        let branchWitness = try #require(branchInterval.coordinates.max {
            separation($0, from: mainApproach) < separation($1, from: mainApproach)
        })
        if twoStops {
            // Probe the physical fallback separately even when stored intervals
            // let the normal display pipeline bypass it entirely.
            let fallbackSection = try #require(StoreOperations.rideRouteSections(for:
                train(ordered)).first)
            let fallback = try #require(RouteSolver.solveSectionOnDemand(fallbackSection,
                segmentIndex: 0, train: context, country: "jp", graphStore: data.graphStore,
                stations: data.stations, directionNetwork: data.network))
            let graph = pipeline.proofGraph(fallback.coordinates, store: data.graphStore)
            #expect(RouteSolver.verifiedSourcePath([fallback.coordinates], graph: graph,
                context: context, section: fallbackSection) != nil)
            if reverse {
                #expect(separation(mainWitness, from: fallback.coordinates) < 100)
                #expect(separation(branchWitness, from: fallback.coordinates) > 500)
            } else {
                #expect(separation(branchWitness, from: fallback.coordinates) < 100)
            }
        }
        if reverse || !twoStops {
            #expect(separation(mainWitness, from: drawn) < 100)
            #expect(separation(branchWitness, from: drawn) > 500)
        } else {
            #expect(!Set(matchedCodes).isDisjoint(with: branchCodes))
            #expect(separation(branchWitness, from: drawn) < 100)
        }
    }

    private func train(_ codes: [String]) -> Train {
        Train(id: "direction-test", number: "Test", origin: codes.first!, destination: codes.last!,
              stops: codes.map { Stop(name: $0, n02StationCode: $0) })
    }

    private func line(_ id: String, _ codes: [String], direction: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
            "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
            "segments": (0..<(codes.count - 1)).map {
                [1, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
            },
        ]
        if let direction {
            row["stationOrderDirection"] = "up"
            row["alignmentDirection"] = direction
        }
        return row
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        try JSONDecoder().decode(CompactPackage.self, from: JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines]))
    }
}
