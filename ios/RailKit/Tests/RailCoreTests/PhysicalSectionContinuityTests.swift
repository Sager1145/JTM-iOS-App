import Foundation
import Testing
@testable import RailCore

struct PhysicalSectionContinuityTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let b = Coordinate(lon: 139.01, lat: 35)
    private let c = Coordinate(lon: 139.02, lat: 35)

    private func rail(_ points: [Coordinate], line: String) -> RouteGraph.SectionFeature {
        .init(properties: .init(lineName: line, operator: "Operator", institutionTypeCode: "1"), lines: [points])
    }
    private func identity(_ line: String) -> RouteGraph.TrackIdentity {
        .init(operatorName: "Operator", lineName: line, railwayClassCode: "")
    }
    private func station(_ point: Coordinate, code: String, line: String) -> Stations.Feature {
        .init(properties: ["n02_station_code": .string(code), "station_name": .string(code),
            "line_name": .string(line), "operator": .string("Operator"),
            "institution_type_code": .string("1")], geometry: .init(type: "Point", coordinates: .array([
                .number(point.lon), .number(point.lat)])))
    }
    private func boundary() -> RouteGraph.PhysicalJunction {
        .init(id: "reviewed", from: .init(identity: identity("West"), coordinate: b),
            to: .init(identity: identity("East"), coordinate: b), evidence: ["survey:reviewed"],
            validFrom: "2020-01-01", validTo: "2021-01-01")
    }
    private func stations() -> Stations.Index {
        .init([station(a, code: "A", line: "West"), station(b, code: "B", line: "West"),
            station(b, code: "B", line: "East"), station(c, code: "C", line: "East")])
    }

    @Test("Same-coordinate independent legs cannot establish a through railway")
    func separateLegsCannotJoin() throws {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([b, c], line: "East")])
        let previous = try #require(RouteSolver.solveSection(
            .init(fromN02StationCode: "A", toN02StationCode: "B", lineNames: ["West"]),
            segmentIndex: 0, train: .init(), country: "jp", graph: graph, stations: stations()))
        let section = RouteSection(fromN02StationCode: "B", toN02StationCode: "C", lineNames: ["East"])
        #expect(RouteSolver.solveSection(section, segmentIndex: 1, train: .init(), country: "jp",
            graph: graph, stations: stations(), continuityAnchor: b) != nil)
        #expect(RouteSolver.solveSection(section, segmentIndex: 1, train: .init(), country: "jp",
            graph: graph, stations: stations(), continuityAnchor: b,
            physicalContinuationKey: previous.rawPathKeys.last) == nil)
        #expect(RouteSolver.physicalContinuationPath(from: previous.rawPathKeys.last!,
            to: RouteGraph.physicalNodeKey(b, identity: identity("East")), graph: graph, rideDate: nil) == nil)
        #expect(RouteSolver.solveSection(section, segmentIndex: 1, train: .init(), country: "jp",
            graph: graph, stations: stations(), physicalContinuationKey: "missing") == nil)
    }

    @Test("Reviewed boundaries permit hard next-line continuation only on their evidence dates")
    func reviewedBoundaryDatesAndDirections() throws {
        let sections = [rail([a, b], line: "West"), rail([b, c], line: "East")]
        let graph = RouteGraph.build(from: sections, junctions: [boundary()])
        for (to, nextLine, previousLine) in [("C", "East", "West"), ("A", "West", "East")] {
            let key = RouteGraph.physicalNodeKey(b, identity: identity(previousLine))
            let section = RouteSection(fromN02StationCode: "B", toN02StationCode: to, lineNames: [nextLine])
            for day in ["2019-12-31", "2021-01-01"] {
                #expect(RouteSolver.solveSection(section, segmentIndex: 1,
                    train: .init(rideDate: day), country: "jp", graph: graph,
                    stations: stations(), physicalContinuationKey: key) == nil)
            }
            let solved = try #require(RouteSolver.solveSection(section, segmentIndex: 1,
                train: .init(rideDate: "2020-06-01"), country: "jp", graph: graph,
                stations: stations(), physicalContinuationKey: key))
            #expect(solved.rawPathKeys.first == key)
            #expect(solved.rawPathKeys[1] == RouteGraph.physicalNodeKey(b, identity: identity(nextLine)))
            #expect(solved.coordinates == solved.rawPathKeys.compactMap { graph.nodes[$0] })
            #expect(solved.coordinates.prefix(2) == [b, b])
        }
    }

    @Test("Same physical identity continues in both directions without a junction")
    func sameIdentity() throws {
        let graph = RouteGraph.build(from: [rail([a, b, c], line: "West")])
        let index = Stations.Index([station(a, code: "A", line: "West"),
            station(b, code: "B", line: "West"), station(c, code: "C", line: "West")])
        let key = RouteGraph.physicalNodeKey(b, identity: identity("West"))
        for code in ["A", "C"] {
            let section = RouteSection(fromN02StationCode: "B", toN02StationCode: code, lineNames: ["West"])
            let solved = try #require(RouteSolver.solveSection(section, segmentIndex: 1, train: .init(),
                country: "jp", graph: graph, stations: index, physicalContinuationKey: key))
            #expect(solved.rawPathKeys.first == key)
        }
    }

    @Test("Qualified same-track endpoints survive station snap limits in both directions")
    func sameTrackDifferentStationSnaps() throws {
        let points = (0...34).map { Coordinate(lon: 139 + Double($0) * 0.0001, lat: 35) }
        let graph = RouteGraph.build(from: [rail(points, line: "West")])
        let index = Stations.Index([station(points[0], code: "A", line: "West"),
            station(points[15], code: "B", line: "West"), station(points[34], code: "C", line: "West")])
        for (priorIndex, destination) in [(2, "C"), (30, "A")] {
            let priorKey = RouteGraph.physicalNodeKey(points[priorIndex], identity: identity("West"))
            let candidates = RouteSolver.collectStationCandidateGraphNodes(
                stationIndices: index.candidateIndices(for: .stop(.init(n02StationCode: "B"))),
                stations: index, graph: graph, hints: .init(requiredLines: ["West"]), allowedCodes: ["1"])
            #expect(!candidates.prefix(12).contains { $0.key == priorKey })
            let section = RouteSection(fromN02StationCode: "B", toN02StationCode: destination, lineNames: ["West"])
            let solved = try #require(RouteSolver.solveSection(section, segmentIndex: 1, train: .init(),
                country: "jp", graph: graph, stations: index, continuityAnchor: points[priorIndex],
                physicalContinuationKey: priorKey))
            #expect(solved.rawPathKeys.first == priorKey)
            #expect(solved.coordinates.first == points[priorIndex])
            #expect(Stations.stationCode(index.features[solved.fromStationIndex]) == "B")
            #expect(solved.snapFrom == 0)
            for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                #expect(graph.adjacency[from]?.contains { $0.to == to && $0.connector == nil } == true)
            }
        }
    }

    @Test("Actual Azusa physical continuation takes precedence over station display resnapping")
    func actualAzusaStationDisplayFilter() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        var features = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features
        _ = RailHistory.apply(try RailHistoryOverlay.load(from: data.appendingPathComponent("rail-history.json")),
            sections: &sections, stations: &features)
        // Include all surveyed memberships near the route, including Kofu's
        // other platform. Each test owns its mutable regional graph cache.
        sections = sections.filter { feature in feature.lines.contains { line in line.contains {
            $0.lon >= 138 && $0.lon <= 138.9 && $0.lat >= 35.55 && $0.lat <= 36.05
        } } }
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            data.appendingPathComponent("physical-rail-junctions.json")))
        let store = RouteGraph.RouteGraphStore(sections: sections, junctions: registry.junctions(for: "jp"))
        let stations = Stations.Index(features)
        let graph = store.fullGraph()
        let previousKey = "21:東日本旅客鉄道|9:中央線|2:11|0:|0:|0:|0:@138.57021,35.66677"
        let coordinate = try #require(graph.nodes[previousKey])
        let section = RouteSection(from: "甲府", to: "茅野", fromN02StationCode: "003867", toN02StationCode: "002764")
        let context = RouteSolver.TrainContext(company: "東日本旅客鉄道", rideDate: "2019-03-16")
        let solved = try #require(RouteSolver.solveSectionOnDemand(section, segmentIndex: 1,
            train: context, country: "jp", graphStore: store, stations: stations,
            continuityAnchor: coordinate, physicalContinuationKey: previousKey))
        #expect(solved.rawPathKeys.first == previousKey)
        #expect(solved.coordinates == solved.rawPathKeys.compactMap { graph.nodes[$0] })
        #expect(Stations.stationCode(stations.features[solved.fromStationIndex]) == "003867")
        for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
            #expect(graph.adjacency[from]?.contains { edge in
                edge.to == to && edge.connector == nil && edge.lineName == "中央線"
                    && RouteGraph.RailValidity.isValid(validFrom: edge.validFrom,
                        validTo: edge.validTo, on: context.rideDate)
            } == true)
        }
    }

    @Test("Actual split Utazu legs cannot bypass the reviewed evidence window")
    func actualUtazuSectionBoundary() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        var sections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features
        let overlay = try RailHistoryOverlay.load(from: data.appendingPathComponent("rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        sections = sections.filter { feature in
            feature.properties.operator == "四国旅客鉄道"
                && ["本四備讃線", "予讃線"].contains(feature.properties.lineName)
                && feature.lines.contains { $0.contains { point in
                    point.lon >= 133.75 && point.lon <= 133.9 && point.lat >= 34.27 && point.lat <= 34.47
                } }
        }
        let junctions = try PhysicalRailJunctionRegistry(data: Data(contentsOf:
            data.appendingPathComponent("physical-rail-junctions.json"))).junctions(for: "jp").filter {
                $0.id.hasPrefix("utazu-")
            }
        let store = RouteGraph.RouteGraphStore(sections: sections, junctions: junctions)
        let stations = Stations.Index(stationFeatures)
        for (start, startCode, end, endCode) in [("児島", "007919", "丸亀", "008271"),
            ("丸亀", "008271", "児島", "007919")] {
            let incoming = RouteSection(from: start, to: "宇多津", fromN02StationCode: startCode, toN02StationCode: "008252")
            let outgoing = RouteSection(from: "宇多津", to: end, fromN02StationCode: "008252", toN02StationCode: endCode)
            for day in ["1988-04-09", "1988-04-10", "2019-10-18"] {
                let previous = RouteSolver.solveSectionOnDemand(incoming, segmentIndex: 0,
                    train: .init(company: "四国旅客鉄道", rideDate: day), country: "jp", graphStore: store, stations: stations)
                let next = previous.flatMap { solved in
                    RouteSolver.solveSectionOnDemand(outgoing, segmentIndex: 1,
                        train: .init(company: "四国旅客鉄道", rideDate: day), country: "jp", graphStore: store,
                        stations: stations, physicalContinuationKey: solved.rawPathKeys.last)
                }
                // 児島↔丸亀 uses the station arm. Both Utazu arms opened
                // 1988-04-10 with the 瀬戸大橋線, so a day before that still
                // cannot cross. 2019-10-18 remains in the evidence text only.
                if day < "1988-04-10" {
                    #expect(next == nil)
                } else {
                    #expect(previous != nil)
                    #expect(next != nil)
                }
            }
        }
    }

    @Test("A zero-distance ordinary edge and passenger connector cannot act as a reviewed boundary")
    func zeroEdgeCannotJoin() {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([b, c], line: "East")])
        let west = RouteGraph.physicalNodeKey(b, identity: identity("West"))
        let east = RouteGraph.physicalNodeKey(b, identity: identity("East"))
        graph.adjacency[west, default: []].append(.init(to: east, length: 0,
            institutionTypeCode: "1", railwayClassCode: "", lineName: "", operator: "", connector: nil))
        #expect(RouteSolver.physicalContinuationPath(from: west, to: east, graph: graph, rideDate: nil) == nil)
    }

    @Test("Recorded exact intervals must retain their surveyed edges and dated boundary")
    func recordedSourceProof() {
        let graph = RouteGraph.build(from: [rail([a, b], line: "West"), rail([b, c], line: "East")], junctions: [boundary()])
        #expect(RouteSolver.verifiedPhysicalPathKeys([a, b, c], graph: graph, rideDate: "2019-12-31") == nil)
        let keys = RouteSolver.verifiedPhysicalPathKeys([a, b, c], graph: graph, rideDate: "2020-06-01")
        #expect(keys == [RouteGraph.physicalNodeKey(a, identity: identity("West")),
            RouteGraph.physicalNodeKey(b, identity: identity("West")),
            RouteGraph.physicalNodeKey(b, identity: identity("East")),
            RouteGraph.physicalNodeKey(c, identity: identity("East"))])
        #expect(RouteSolver.verifiedPhysicalPathKeys([a, c], graph: graph, rideDate: "2020-06-01") == nil)
    }
}
