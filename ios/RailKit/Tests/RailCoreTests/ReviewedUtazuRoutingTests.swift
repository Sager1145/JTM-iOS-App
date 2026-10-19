import Foundation
import Testing
import RailCore

struct ReviewedUtazuRoutingTests {
    @Test("Reviewed Utazu boundaries preserve the separate surveyed Sakaide and Marugame arms")
    func actualSourceArms() throws {
        let snapshot = try ReviewedCorridorFixtures.snapshot(history: true)
        let sourceSections = snapshot.sections
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

        let easternID = "utazu-honshi-bisan-yosan-eastern-bypass"
        let stationID = "utazu-honshi-bisan-yosan-station-arm"
        let junctions = snapshot.junctions.filter {
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
        }
        // Both Utazu arms opened 1988-04-10 with the 瀬戸大橋線. The 2019-10-18
        // facility document stays in the eastern record's evidence text.
        #expect(eastern.validFrom == "1988-04-10")
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: eastern.validFrom, validTo: eastern.validTo, on: "1988-04-09"))
        #expect(RouteGraph.RailValidity.isValid(
            validFrom: eastern.validFrom, validTo: eastern.validTo, on: "1988-04-10"))
        #expect(station.validFrom == "1988-04-10")
        #expect(!RouteGraph.RailValidity.isValid(
            validFrom: station.validFrom, validTo: station.validTo, on: "1988-04-09"))
        #expect(RouteGraph.RailValidity.isValid(
            validFrom: station.validFrom, validTo: station.validTo, on: "1988-04-10"))
        let independent = RouteGraph.build(from: sections, policy: .physicalRailway)
        let joined = RouteGraph.build(from: sections, policy: .physicalRailway, junctions: junctions)
        #expect(joined.rejectedPhysicalJunctionIDs.isEmpty)

        var worker = ReviewedCorridorWorker(sections: sections, stations: snapshot.stations,
            junctions: junctions)
        func solve(_ reviewed: Bool, _ section: RouteSection) throws -> ReviewedCorridorWorker.Proof? {
            try worker.solve(reviewed: reviewed, section: section, company: "四国旅客鉄道", date: "2026-10-03")
        }
        // Registry geometryEvidence identifies the source arms at these
        // surveyed vertices. History identity copies can shift array positions;
        // locate the same whole source features by identity and both endpoints.
        let bridgeFork = Coordinate(lon: 133.82224, lat: 34.31954)
        let westernApproach = Coordinate(lon: 133.81778, lat: 34.31274)
        for (destination, code, expected, requiredArms) in [
            ("坂出", "008240", eastern, [(bridgeFork, eastern.from.coordinate)]),
            ("丸亀", "008271", station, [(westernApproach, bridgeFork),
                                        (station.from.coordinate, westernApproach)])
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
                #expect(try solve(false, section) == nil)
                let solved = try #require(try solve(true, section))
                #expect(solved.coordinates == solved.rawPathKeys.compactMap { joined.nodes[$0] })
                for (from, to) in requiredArms {
                    let matches = sourceSections.filter { feature in
                        feature.properties.operator == "四国旅客鉄道"
                            && feature.properties.lineName == "本四備讃線"
                            && RouteGraph.RailValidity.isValid(
                                validFrom: feature.properties.validFrom,
                                validTo: feature.properties.validTo, on: "2026-10-03")
                            && feature.quantisedLines.contains { line in
                                (line.first == from && line.last == to)
                                    || (line.first == to && line.last == from)
                            }
                    }
                    #expect(matches.count == 1)
                    let feature = try #require(matches.first)
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
