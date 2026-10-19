import Foundation
import Testing
@testable import RailCore

struct TripRoutePlannerTests {
    @Test("A single line reports its intermediate stations and distance")
    func singleLine() throws {
        let package = try fixture([line("one", ["A", "M", "B"], distance: 2)])
        let corridors = try corridors(package, from: "A", to: "B")
        #expect(corridors.count == 1)
        #expect(corridors[0].junctions.isEmpty)
        #expect(corridors[0].passStationCount == 1)
        #expect(corridors[0].distanceKm == 4)
        #expect(corridors[0].id == corridors[0].choice.id)
        #expect(corridors[0].lineNames == ["one"])
        #expect(corridors[0].operatorNames == ["Operator"])
    }

    @Test("independent Tokyo Shinkansen termini are disconnected")
    func tokyoShinkansenTermini() throws {
        let source = try PortFixtures.package(country: "jp")
        let ids = ["jp-東海旅客鉄道-東海道新幹線", "jp-東日本旅客鉄道-東北新幹線"]
        let package = CompactPackage(format: source.format, version: source.version, country: source.country, lines: source.lines.filter { ids.contains($0.id) })
        #expect(TripConnectivity.link(from: package.lines[0], to: package.lines[1], atStationCode: "003766", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .none)
        #expect(!TripConnectivity.allows(from: package.lines[0], to: package.lines[1], atStationCode: "003766"))
        let result = LocalJourneySearch.search(package: package, originCode: "004095", destinationCode: "003505", trainType: "shinkansen")
        #expect(result.choices.isEmpty)
        let draft = Train(id: "tokyo", number: "", trainType: "shinkansen", origin: "品川", destination: "上野", stops: [Stop(name: "品川", n02StationCode: "004095"), Stop(name: "上野", n02StationCode: "003505")])
        #expect(RecordedRouteAdmission.search(in: draft, package: package).choices.isEmpty)
        guard case .disconnected = try TripRoutePlanner.plan(package: package, request: .init(originCode: "004095", destinationCode: "003505", trainType: "shinkansen")) else { Issue.record("Expected disconnected Tokyo termini"); return }
    }

    @Test("same-company interior crossing cannot auto-fill a physical path")
    func unreviewedInteriorCrossing() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("cross", ["C", "J", "D"])])
        #expect(LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D").choices.isEmpty)
        let draft = Train(id: "crossing", number: "", origin: "A", destination: "D", stops: [Stop(name: "A", n02StationCode: "A"), Stop(name: "D", n02StationCode: "D")])
        #expect(RecordedRouteAdmission.admission(in: draft, package: package).automaticChoice == nil)
    }

    @Test("JR company boundaries need reviewed physical continuation")
    func jrNetwork() throws {
        let package = try fixture([line("first", ["A", "B"], operatorName: "One"),
                                   line("second", ["B", "C"], operatorName: "Two")])
        guard case .disconnected(let changes) = try plan(package, from: "A", to: "C") else {
            Issue.record("Expected unreviewed JR boundary to remain disconnected"); return
        }
        #expect(changes.first?.link == TripConnectivity.Link.none)
        #expect(changes.first?.stationCode == "B")
    }

    @Test("Passing-through crossings require an explicit override", arguments: ["jr_conventional", "shinkansen", "private", "third_sector"])
    func crossing(kind: String) throws {
        let package = try fixture([line("main", ["A", "J", "B"], kind: kind),
                                   line("cross", ["C", "J", "D"], kind: kind)])
        let trainType = kind == "shinkansen" ? "shinkansen" : "local"
        guard case .disconnected(let changes) = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "D", trainType: trainType)) else {
            Issue.record("Expected a disconnected crossing")
            return
        }
        #expect(changes.first?.link == TripConnectivity.Link.none)
        let outcome = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "D", trainType: trainType, allowUnverifiedConnections: true))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected an overridden corridor")
            return
        }
        #expect(found.first?.junctions.first?.link == TripConnectivity.Link.none)
        #expect(found.first?.junctions.first?.stationCode == "J")
    }

    @Test("A branch terminal needs reviewed physical continuation")
    func branchTerminal() throws {
        let package = try fixture([line("main", ["A", "J", "B"]), line("branch", ["J", "D"])])
        guard case .disconnected = try plan(package, from: "A", to: "D") else {
            Issue.record("Expected unreviewed branch boundary to remain disconnected"); return
        }
    }

    @Test("Same-name rows do not establish physical continuation")
    func sameNameSplit() throws {
        var first = line("main", ["A", "J", "B"])
        var second = line("main-5", ["C", "J", "D"])
        first["name"] = "Main"
        second["name"] = "Main"
        guard case .disconnected = try plan(try fixture([first, second]), from: "A", to: "D") else {
            Issue.record("Expected unreviewed same-name crossing to remain disconnected"); return
        }
    }

    @Test("A loop row has no terminal at its stored first station")
    func loopIsNotTerminal() throws {
        var loop = line("loop", ["J", "D", "E"])
        loop["isLoop"] = true
        let package = try fixture([line("main", ["A", "J", "B"]), loop])
        #expect(TripConnectivity.link(from: package.lines[0], to: package.lines[1],
                                      atStationCode: "J", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .none)
    }

    @Test("Same-operator subway lines require a through-service record")
    func subwayDisconnected() throws {
        let package = try fixture([line("first", ["A", "B"], kind: "subway"),
                                   line("second", ["B", "C"], kind: "subway")])
        guard case .disconnected(let junctions) = try plan(package, from: "A", to: "C") else {
            Issue.record("Expected disconnected subway lines")
            return
        }
        #expect(junctions.count == 1)
        #expect(junctions.first?.link == TripConnectivity.Link.none)
        #expect(junctions.first?.stationCode == "B")
    }

    @Test("Parallel corridors are ordered by distance and company selection is enforced")
    func parallelCorridors() throws {
        let package = try fixture([line("long", ["A", "X", "B"], distance: 3, operatorName: "Long"),
                                   line("short", ["A", "Y", "B"], operatorName: "Short")])
        let found = try corridors(package, from: "A", to: "B")
        #expect(found.count == 2)
        #expect(found.map(\.distanceKm) == [2, 6])
        #expect(found.map { $0.choice.lineIDs } == [["short"], ["long"]])
        let preferred = try TripRoutePlanner.plan(package: package,
            request: .init(originCode: "A", destinationCode: "B", operatorName: "Long"))
        #expect(preferred == .corridors([found[1]]))
        #expect(try TripRoutePlanner.plan(package: package,
            request: .init(originCode: "A", destinationCode: "B", operatorName: "Unknown")) == .noCompanyRoute("Unknown"))
    }

    @Test("Different private operators require a catalog continuation, including junction aliases")
    func privateAndThroughService() throws {
        let package = try fixture([line("first", ["A", "B"], kind: "private", operatorName: "One"),
                                   line("second", ["B", "C"], kind: "private", operatorName: "Two")])
        guard case .disconnected(let junctions) = try plan(package, from: "A", to: "C") else {
            Issue.record("Expected disconnected private lines")
            return
        }
        #expect(junctions.count == 1)
        #expect(junctions.first?.link == TripConnectivity.Link.none)
        let pattern = try #require((try JapanThroughServices.loadBundled()).patterns.first { $0.legs.count >= 2 })
        let realPair = try fixture([
            line(pattern.legs[0].lineID, ["A", "B"], kind: "private", operatorName: "One"),
            line(pattern.legs[1].lineID, ["B", "C"], kind: "private", operatorName: "Two")])
        // Either leg's own code for the joining station counts (rows may code
        // one physical station differently); any other station does not.
        for code in [pattern.legs[0].toStationCode, pattern.legs[1].fromStationCode] {
            #expect(TripConnectivity.link(from: realPair.lines[0], to: realPair.lines[1],
                                          atStationCode: code, patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .throughService)
            #expect(TripConnectivity.link(from: realPair.lines[1], to: realPair.lines[0],
                                          atStationCode: code, patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) == .throughService)
            #expect(!TripConnectivity.allows(from: realPair.lines[0], to: realPair.lines[1], atStationCode: code))
        }
        #expect(TripConnectivity.link(from: realPair.lines[0], to: realPair.lines[1],
                                      atStationCode: "elsewhere", patterns: (try JapanThroughServices.loadBundled()).patterns, connectors: (try JapanThroughServices.loadBundled()).connectors) != .throughService)
    }

    @Test("Same and isolated stations have distinct outcomes")
    func endpoints() throws {
        let package = try fixture([line("one", ["A", "B"]), line("isolated", ["C"])])
        #expect(try plan(package, from: "A", to: "A") == .sameStation)
        #expect(try plan(package, from: "A", to: "C") == .noRoute)
    }

    @Test("Nil continuation preserves the existing ranking fixture and wrapper choices")
    func nilContinuationRegression() throws {
        let package = try fixture([line("direct", ["A", "D"], distance: 5),
                                   line("first", ["A", "B"]), line("second", ["B", "D"]),
                                   line("equal", ["A", "C", "D"])])
        let baseline = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D")
        let explicitNil = LocalJourneySearch.search(package: package, originCode: "A", destinationCode: "D",
                                                    continuation: nil)
        #expect(explicitNil.choices == baseline.choices)
        #expect(explicitNil.choices.map(\.lineIDs) == [["equal"], ["direct"]])
        #expect(explicitNil.isTruncated == baseline.isTruncated)
        #expect(explicitNil.topologyIsComplete == baseline.topologyIsComplete)
        #expect(LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D",
                                           continuation: nil) == baseline.choices)
        let blocked = LocalJourneySearch.choices(package: package, originCode: "A", destinationCode: "D",
                                                 continuation: { _, _, _ in false })
        #expect(blocked.map(\.lineIDs) == [["equal"], ["direct"]])
    }

    @Test("Endpoint line hints prevent falling back to a shared JR route")
    func endpointLineHints() throws {
        let package = try fixture([
            line("subway-a", ["A", "M", "B"], kind: "subway"),
            line("subway-b", ["A", "M", "B"], kind: "subway"),
            line("jr", ["A", "B"])])
        #expect(try !corridors(package, from: "A", to: "B").isEmpty)
        let outcome = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "B",
            originLineID: "subway-a", destinationLineID: "subway-b"))
        guard case .disconnected = outcome else {
            Issue.record("Expected disconnected hinted subway lines")
            return
        }
    }

    @Test("A hinted direct line ranks ahead of a shorter connecting route")
    func directLineFirst() throws {
        var direct = line("direct", ["A", "J", "X", "B"], distance: 5)
        direct["segments"] = [[1, 0, [[0, 0], [1, 0]]],
                              [5, 0, [[1, 0], [2, 0]]],
                              [5, 0, [[2, 0], [3, 0]]]]
        let package = try fixture([direct, line("shortcut", ["J", "Y", "B"])])
        let outcome = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "A", destinationCode: "B", originLineID: "direct"))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected direct and connecting corridors")
            return
        }
        #expect(found.count == 1)
        #expect(found.first?.choice.lineIDs == ["direct"])
        #expect(found.map(\.distanceKm) == [11])
    }

    @Test("Corridors sharing at least eighty percent of station keys collapse")
    func nearDuplicates() throws {
        let package = try fixture([
            line("short", ["A", "M", "N", "P", "B"]),
            line("long", ["A", "M", "N", "Q", "B"], distance: 2),
            line("distinct", ["A", "X", "Y", "Z", "B"])])
        let found = try corridors(package, from: "A", to: "B")
        #expect(found.map { $0.choice.lineIDs } == [["distinct"], ["short"]])
    }

    @Test("Existing package station IDs take precedence over request aliases")
    func aliases() throws {
        let package = try fixture([line("one", ["A", "M", "B"])])
        let outcome = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "external", destinationCode: "B",
            stationAliases: ["external": "A", "A": "wrong"], originLineID: "one"))
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected aliased endpoint route")
            return
        }
        #expect(found.first?.choice.stations.first?.code == "external")
    }

    @Test("Aliased endpoint codes resolving to one station report same station")
    func aliasedEndpointsAreSameStation() throws {
        let package = try fixture([line("one", ["A", "B"])])
        let outcome = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "origin-alias", destinationCode: "destination-alias",
            stationAliases: ["origin-alias": "A", "destination-alias": "A"]))
        #expect(outcome == .sameStation)
    }

    @Test("Ride date reaches planned junction links")
    func rideDateReachesJunctionLink() throws {
        let pattern = try JSONDecoder().decode(JapanThroughServices.Pattern.self, from: Data("""
        {"id":"dated-plan","serviceCode":"DP","name":"Dated plan","aliases":[],
         "kind":"throughRunning","validFrom":"2020-01-01","validTo":"2021-01-01",
         "legs":[
           {"lineID":"first","fromStationCode":"A","toStationCode":"B"},
           {"lineID":"second","fromStationCode":"B","toStationCode":"C"}
         ],"sourceURLs":["https://example.test/planner"],"notes":""}
        """.utf8))
        let package = try fixture([
            line("first", ["A", "B"], kind: "private", operatorName: "One"),
            line("second", ["B", "C"], kind: "private", operatorName: "Two")
        ])
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "C")

        guard case .corridors(let active) = TripRoutePlanner.plan(
            package: package, request: request, rideDate: "2020-06-01", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) else {
            Issue.record("Expected a dated through-service corridor")
            return
        }
        #expect(active.first?.junctions.first?.link == .throughService)

        guard case .disconnected(let inactive) = TripRoutePlanner.plan(
            package: package, request: request, rideDate: "2019-12-31", patterns: [pattern], connectors: (try JapanThroughServices.loadBundled()).connectors) else {
            Issue.record("Expected the pre-validFrom route to be disconnected")
            return
        }
        #expect(inactive.first?.link == TripConnectivity.Link.none)
    }

    @Test("Bundled cross-station connectors plan dated through services")
    func bundledConnectorServices() throws {
        let package = try PortFixtures.package(country: "jp")
        let odakyu = "jp-小田急電鉄-小田原線"
        let gotemba = "jp-東海旅客鉄道-御殿場線"
        let asagiri = try TripRoutePlanner.plan(package: package, request: .init(
            originCode: "003700", destinationCode: "005115",
            originLineID: odakyu, destinationLineID: gotemba), rideDate: "2024-01-01")
        guard case .corridors(let gotembaCorridors) = asagiri else {
            Issue.record("Expected the current ふじさん corridor, got \(asagiri)")
            return
        }
        #expect(gotembaCorridors.contains { corridor in
            corridor.junctions.contains { $0.link == .throughService }
        })

        let tohoku = "jp-東日本旅客鉄道-東北線"
        let senseki = "jp-東日本旅客鉄道-仙石線"
        let request = TripRoutePlanner.Request(
            originCode: "001177", destinationCode: "001083",
            originLineID: tohoku, destinationLineID: senseki)
        let active = try TripRoutePlanner.plan(
            package: package, request: request, rideDate: "2016-01-01")
        guard case .corridors(let sensekiCorridors) = active else {
            Issue.record("Expected the 仙石東北 corridor, got \(active)")
            return
        }
        #expect(sensekiCorridors.contains { corridor in
            corridor.junctions.contains { $0.link == .throughService }
        })

        let inactive = try TripRoutePlanner.plan(
            package: package, request: request, rideDate: "2015-05-29")
        guard case .disconnected(let junctions) = inactive else {
            Issue.record("Expected the pre-opening connector to be disconnected, got \(inactive)")
            return
        }
        #expect(junctions.first?.link == TripConnectivity.Link.none)
    }

    @Test("Bundled corridor crossings require their surveyed junction and date")
    func bundledCorridorPhysicalJunctions() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        let sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        let junctions = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            data.appendingPathComponent("physical-rail-junctions.json"))).junctions(for: "jp")
        for (id, day) in [("matsuda-east-15", "2024-01-01"),
                          ("senseki-tohoku-connector", "2016-01-01")] {
            let junction = try #require(junctions.first { $0.id == id })
            let endpoints = [junction.from, junction.to]
            // Bound the graph only; permission still requires the reviewed
            // record and its endpoints on the real surveyed identities.
            let local = sections.filter { feature in
                endpoints.contains { endpoint in
                    feature.properties.operator == endpoint.identity.operatorName
                        && feature.properties.lineName == endpoint.identity.lineName
                } && feature.lines.contains { line in line.contains { point in
                    endpoints.contains { endpoint in
                        abs(point.lon - endpoint.coordinate.lon) < 0.02
                            && abs(point.lat - endpoint.coordinate.lat) < 0.02
                    }
                } }
            }
            let from = RouteGraph.physicalNodeKey(junction.from.coordinate, identity: junction.from.identity)
            let to = RouteGraph.physicalNodeKey(junction.to.coordinate, identity: junction.to.identity)
            let graph = RouteGraph.build(from: local, junctions: [junction])
            #expect(graph.rejectedPhysicalJunctionIDs.isEmpty)
            #expect(RouteSolver.physicalContinuationPath(
                from: from, to: to, graph: graph, rideDate: day) != nil)
            let withoutJunction = RouteGraph.build(from: local)
            #expect(RouteSolver.physicalContinuationPath(
                from: from, to: to, graph: withoutJunction, rideDate: day) == nil)
            if id == "senseki-tohoku-connector" {
                #expect(RouteSolver.physicalContinuationPath(
                    from: from, to: to, graph: graph, rideDate: "2015-05-29") == nil)
            }
        }
    }

    private func plan(_ package: CompactPackage, from: String, to: String) throws -> TripRoutePlanner.Outcome {
        try TripRoutePlanner.plan(package: package, request: .init(originCode: from, destinationCode: to))
    }

    private func corridors(_ package: CompactPackage, from: String, to: String) throws -> [TripRoutePlanner.Corridor] {
        let outcome = try plan(package, from: from, to: to)
        guard case .corridors(let values) = outcome else {
            Issue.record("Expected corridors, got \(outcome)")
            return []
        }
        return values
    }

    private func line(_ id: String, _ codes: [String], distance: Double = 1,
                      kind: String = "jr_conventional", operatorName: String = "Operator") -> [String: Any] {
        ["id": id, "name": id, "operator": operatorName, "rank": 3, "kind": kind,
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


extension TripRoutePlannerTests {
    @Test("A named display corridor can be reviewed without declaring physical continuation")
    func namedCorridorAcrossCompanies() throws {
        var first = line("A1", ["O", "J"], operatorName: "East")
        var last = line("A2", ["J", "K", "D"], distance: 5, operatorName: "West")
        first["name"] = "Main"
        last["name"] = "Main"
        let package = try fixture([first, last,
            line("B", ["J", "X", "Y"]), line("C", ["Y", "D"]),
            line("shortcut", ["J", "Z", "W", "K"])])
        let request = TripRoutePlanner.Request(originCode: "O", destinationCode: "D", originLineID: "A1", destinationLineID: "A2")
        guard case .disconnected = try TripRoutePlanner.plan(package: package, request: request) else {
            Issue.record("Same-name JR rows cannot establish physical continuation"); return
        }
        var reviewRequest = request
        reviewRequest.allowUnverifiedConnections = true
        let outcome = try TripRoutePlanner.plan(package: package, request: reviewRequest)
        guard case .corridors(let found) = outcome else {
            Issue.record("Expected hinted named corridor")
            return
        }
        #expect(found.first?.choice.lineIDs == ["A1", "A2"])
        #expect(found.first?.lineNames == ["Main"])
        #expect(found.first?.operatorNames == ["East", "West"])
        #expect(found.allSatisfy { $0.junctions.allSatisfy { $0.link == .none } })
        let draft = Train(id: "named", number: "", origin: "O", destination: "D", stops: [Stop(name: "O", n02StationCode: "O"), Stop(name: "D", n02StationCode: "D")])
        let choice = try #require(found.first?.choice)
        #expect(LocalJourneyAutofill.proposal(train: draft, choice: choice)?.train.routeConfirmation == .pending)
        #expect(found.contains { $0.distanceKm < (found.first?.distanceKm ?? 0) })
        #expect(found.allSatisfy { $0.choice.routeSections.first?.lineIDs == ["A1"]
            && $0.choice.routeSections.last?.lineIDs == ["A2"] })
    }
}
