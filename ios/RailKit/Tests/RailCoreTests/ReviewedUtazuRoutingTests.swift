import Foundation
import Testing
@testable import RailCore

struct ReviewedUtazuRoutingTests {
    @Test("Reviewed Utazu boundaries preserve the separate surveyed Sakaide and Marugame arms")
    func actualSourceArms() throws {
        let data = try PortFixtures.repositoryRoot().appendingPathComponent("app/data")
        var sourceSections = try RouteGraph.SectionFeatureCollection.load(
            contentsOf: data.appendingPathComponent("rail-sections.json")).features
        var stationFeatures = try Stations.FeatureCollection.load(
            contentsOf: data.appendingPathComponent("stations.json")).features
        let overlay = try RailHistoryOverlay.load(
            from: data.appendingPathComponent("rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sourceSections, stations: &stationFeatures)
        let sections = sourceSections.filter { feature in
            feature.properties.operator == "四国旅客鉄道"
                && ["本四備讃線", "予讃線"].contains(feature.properties.lineName)
                && feature.lines.contains { line in
                    line.contains { coordinate in
                        coordinate.lon >= 133.75 && coordinate.lon <= 133.9
                            && coordinate.lat >= 34.27 && coordinate.lat <= 34.47
                    }
                }
        }
        #expect(!sections.isEmpty)
        let stations = Stations.Index(.init(features: stationFeatures))
        let registry = try PhysicalRailJunctionRegistry(data: Data(
            contentsOf: data.appendingPathComponent("physical-rail-junctions.json")))
        let easternID = "utazu-honshi-bisan-yosan-eastern-bypass"
        let stationID = "utazu-honshi-bisan-yosan-station-arm"
        let junctions = registry.junctions(for: "jp").filter {
            [easternID, stationID].contains($0.id)
        }
        #expect(junctions.count == 2)
        let eastern = try #require(junctions.first { $0.id == easternID })
        let station = try #require(junctions.first { $0.id == stationID })
        #expect(eastern.from.coordinate == Coordinate(lon: 133.82565, lat: 34.31357))
        #expect(station.from.coordinate == Coordinate(lon: 133.81426, lat: 34.30712))
        for junction in junctions {
            #expect(junction.from.coordinate == junction.to.coordinate)
            #expect(!junction.evidence.isEmpty)
            // This guard checks the reviewed evidence window only. It does
            // not claim either arm opened then or that earlier routes failed.
            #expect(junction.validFrom == "2019-10-18")
            #expect(!RouteGraph.RailValidity.isValid(
                validFrom: junction.validFrom, validTo: junction.validTo, on: "2019-10-17"))
            #expect(RouteGraph.RailValidity.isValid(
                validFrom: junction.validFrom, validTo: junction.validTo, on: "2019-10-18"))
        }
        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: junctions)
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)

        func solve(_ graph: RouteGraph.Graph, _ section: RouteSection) -> RouteSolver.SolvedSection? {
            RouteSolver.solveSection(section, segmentIndex: 0,
                train: .init(company: "四国旅客鉄道", rideDate: "2026-10-03"),
                country: "jp", graph: graph, stations: stations)
        }
        // Source indexes identify the reviewed physical arms. Read their
        // vertices from the actual history-applied source, never a fixture.
        for (destination, code, expected, requiredFeatures) in [
            ("坂出", "008240", eastern, [5506]),
            ("丸亀", "008271", station, [5505, 5500])
        ] {
            // Exercise the production default without per-section line hints
            // as well as the explicitly constrained corridor, both ways.
            let lineHints: [[String]?] = [nil, ["本四備讃線", "予讃線"]]
            let routes = lineHints.flatMap { lineNames in
                [RouteSection(from: "児島", to: destination,
                    fromN02StationCode: "007919", toN02StationCode: code,
                    lineNames: lineNames),
                 RouteSection(from: destination, to: "児島",
                    fromN02StationCode: code, toN02StationCode: "007919",
                    lineNames: lineNames)]
            }
            for section in routes {
                #expect(solve(independent, section) == nil)
                let solved = try #require(solve(joined, section))
                #expect(solved.hints.preferredLines == ["本四備讃線", "予讃線"])
                #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
                for index in requiredFeatures {
                    let feature = sourceSections[index]
                    #expect(feature.properties.operator == "四国旅客鉄道")
                    #expect(feature.properties.lineName == "本四備讃線")
                    for line in feature.quantisedLines {
                        let keys = line.map {
                            RouteGraph.physicalNodeKey($0, identity: feature.physicalTrackIdentity)
                        }
                        let reverseKeys = Array(keys.reversed())
                        #expect(solved.rawPathKeys.indices.contains { start in
                            guard start + keys.count <= solved.rawPathKeys.count else { return false }
                            let slice = Array(solved.rawPathKeys[start..<(start + keys.count)])
                            return slice == keys || slice == reverseKeys
                        })
                    }
                }
                var boundaries = 0
                var lines = Set<String>()
                for (from, to) in zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()) {
                    let fromCoordinate = try #require(independent.nodes[from])
                    let toCoordinate = try #require(independent.nodes[to])
                    let edge = try #require(joined.adjacency[from]?.first { $0.to == to })
                    #expect(edge.connector == nil)
                    #expect(RouteGraph.RailValidity.isValid(
                        validFrom: edge.validFrom, validTo: edge.validTo, on: "2026-10-03"))
                    if let boundary = edge.physicalJunction {
                        #expect(boundary.junction == expected)
                        #expect(edge.length == 0)
                        #expect(fromCoordinate == expected.from.coordinate)
                        #expect(toCoordinate == expected.to.coordinate)
                        boundaries += 1
                    } else {
                        #expect(independent.adjacency[from]?.contains { $0 == edge } == true)
                        #expect(edge.operator == "四国旅客鉄道")
                        lines.insert(edge.lineName)
                    }
                }
                #expect(boundaries == 1)
                #expect(lines == ["本四備讃線", "予讃線"])
            }
        }
    }
}
