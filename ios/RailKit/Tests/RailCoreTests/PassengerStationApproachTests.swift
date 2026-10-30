import Foundation
import Testing
@testable import RailCore

struct PassengerStationApproachTests {
    @Test func reviewedSourceCurveKeepsItsOwnStationApproach() throws {
        let line = try sourceApproachFixture()
        let expected = [[135.0, 35.0], [135.001, 35.0], [135.002, 35.0],
                        [135.003, 35.001], [135.004, 35.0], [135.005, 35.0],
                        [135.006, 35.0]].map { Coordinate(lon: $0[0], lat: $0[1]) }
        // The source curve reaches the station. A chord across that curve
        // must not be mistaken for a displaced station and rebuilt.
        #expect(DisplayParts.parts(for: line) == [expected])
    }

    @Test(arguments: ["absent", "empty", "unknown", "terminal", "missingAlias", "missingSide", "mismatchedEnd"])
    func incompleteSourceAuthorityKeepsOrdinaryAnchoring(caseName: String) throws {
        let line = try sourceApproachFixture(invalid: caseName)
        let beforeCurve = Coordinate(lon: 135.002, lat: 35)
        #expect(!DisplayParts.parts(for: line).flatMap { $0 }.contains(beforeCurve))
    }

    private func sourceApproachFixture(invalid: String? = nil) throws -> CompactPackage.Line {
        let incoming = [[135.0, 35.0], [135.001, 35.0], [135.002, 35.0], [135.003, 35.001]]
        let outgoing = [[135.003, 35.001], [135.004, 35.0], [135.005, 35.0], [135.006, 35.0]]
        var row: [String: Any] = [
            "id": "source-defined-approach", "name": "Source curve", "rank": 3,
            "stations": [["A", "A", 135.0, 35.0], ["S", "S", 135.003, 35.001],
                         ["B", "B", 135.006, 35.0]],
            "segments": [[1, 1, Array(incoming.dropFirst())], [1, 1, Array(outgoing.dropFirst())]],
            "displayIntervalCoordinates": ["0": incoming, "1": outgoing],
            "displayStationCoordinates": ["S": [135.003, 35.001]],
            "displaySourceAnchoredStationCodes": ["S"]
        ]
        switch invalid {
        case "absent": row.removeValue(forKey: "displaySourceAnchoredStationCodes")
        case "empty": row["displaySourceAnchoredStationCodes"] = [String]()
        case "unknown": row["displaySourceAnchoredStationCodes"] = ["unknown"]
        case "terminal": row["displaySourceAnchoredStationCodes"] = ["A"]
        case "missingAlias": row.removeValue(forKey: "displayStationCoordinates")
        case "missingSide": row["displayIntervalCoordinates"] = ["0": incoming]
        case "mismatchedEnd":
            var changed = incoming
            changed[changed.count - 1] = [135.003, 35.0011]
            row["displayIntervalCoordinates"] = ["0": changed, "1": outgoing]
        default: break
        }
        return try JSONDecoder().decode(CompactPackage.Line.self,
                                        from: JSONSerialization.data(withJSONObject: row))
    }

    @Test("Hakone tunnel display follows the reviewed Apple cartographic arc without changing physical geometry")
    func hakoneTunnelCartographicArcKeepsFrozenSourceBounds() throws {
        let root = try PortFixtures.repositoryRoot()
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let line = try #require(loaded.package.lines.first { $0.id == "jp-小田急箱根-鉄道線" })
        let evidenceData = try Data(contentsOf: root.appending(
            path: "app/scripts/railway/hakone-passenger-corridor-evidence.json"))
        let evidence = try #require(JSONSerialization.jsonObject(with: evidenceData) as? [String: Any])
        let baseline = try JSONDecoder().decode(CompactPackage.Line.self, from:
            JSONSerialization.data(withJSONObject: try #require(evidence["baselineLine"])))
        let coordinates = try #require(evidence["coordinates"] as? [String: [[Double]]])
        let source = try #require(coordinates["6"]).map { Coordinate(lon: $0[0], lat: $0[1]) }
        let display = CompactPackage.decodeDisplayIntervals(line)[6]
        let east = source[47], west = source[54]
        let first = try #require(display.firstIndex(of: east))
        let last = try #require(display.firstIndex(of: west))
        #expect(Array(display[...first]) == Array(source[...47]))
        #expect(Array(display[last...]) == Array(source[54...]))
        #expect(CompactPackage.decodeIntervals(line) == CompactPackage.decodeIntervals(baseline))
        #expect(line.stations.map(\.coordinate) == baseline.stations.map(\.coordinate))
        #expect(line.stations.map(\.id) == baseline.stations.map(\.id))
        #expect(line.segments.map(\.distanceKm) == baseline.segments.map(\.distanceKm))
        // Independently traced pixels [460,390], [680,420], [800,410] on the
        // original Apple rail in current-hakone6-tunnel-context-z18-basemap.png.
        // AX bounds [139.068351,35.234867,139.073710,35.237890] map to
        // screenshot rectangle [255,149,769,530]. These are cartographic
        // reference points, not measured underground railway coordinates.
        let references = [
            Coordinate(lon: 139.06977960208064, lat: 35.23651539056604),
            Coordinate(lon: 139.07131273602081, lat: 35.23634427735849),
            Coordinate(lon: 139.0721489908973, lat: 35.23640131509434)
        ]
        func residual(_ reference: Coordinate, path: [Coordinate]) -> Double {
            let longitudeScale = 111_320 * cos(reference.lat * .pi / 180)
            let points = path.map { ContinuousStroke.Point(
                x: ($0.lon - reference.lon) * longitudeScale,
                y: ($0.lat - reference.lat) * 111_320) }
            return ContinuousStroke.distanceToPolyline(.init(x: 0, y: 0), points)
        }
        #expect(residual(references[0], path: source) > 5)
        for reference in references {
            #expect(residual(reference, path: Array(display[first...last])) < 1.5)
        }
        #expect(line.displayReversalBranches.count == 2)
        let branches = try #require(
            (evidence["displayReversalBranches"] as? [[[Double]]])?.map {
                $0.map { Coordinate(lon: $0[0], lat: $0[1]) }
            })
        #expect(line.displayReversalBranches == branches)
    }

    @Test("Passenger display anchors weld both approaches without changing physical station identity",
          arguments: ["005260", "005269", "005725"])
    func displayApproachesRemainSeparateFromPhysicalTopology(stationID: String) throws {
        let root = try PortFixtures.repositoryRoot()
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let hakone = stationID != "005725"
        let lineID = hakone ? "jp-小田急箱根-鉄道線" : "jp-西日本旅客鉄道-木次線"
        let line = try #require(loaded.package.lines.first { $0.id == lineID })
        let index = try #require(line.stations.firstIndex { $0.id == stationID })
        let sourcePoint = stationID == "005269"
            ? Coordinate(lon: 139.094025, lat: 35.23446)
            : hakone ? Coordinate(lon: 139.07386, lat: 35.239065)
            : Coordinate(lon: 133.116475, lat: 35.09123)
        let displayPoint = try #require(line.displayStationCoordinates[stationID])
        let physical = CompactPackage.decodeIntervals(line)
        let display = CompactPackage.decodeDisplayIntervals(line)
        #expect(line.stations[index].coordinate == sourcePoint)
        #expect(physical[index - 1].last == sourcePoint)
        #expect(physical[index].first == sourcePoint)
        #expect(displayPoint != sourcePoint)
        #expect(display[index - 1].last == displayPoint)
        #expect(display[index].first == displayPoint)
        #expect(Set(line.displayStationCoordinates.keys) == (hakone ? ["005260", "005269"] : [stationID]))
        let repairedIntervals: Set<Int> = hakone ? [4, 5, 6, 7, 8, 9] : [index - 1, index]
        #expect(Set(line.displayIntervalCoordinates.keys) == repairedIntervals)
        for other in physical.indices where !repairedIntervals.contains(other) {
            #expect(display[other] == physical[other])
        }
        if stationID == "005269" {
            #expect(displayPoint == Coordinate(lon: 139.09405786781113, lat: 35.234538053387034))
            let surveySeam = Coordinate(lon: 139.09404611096102, lat: 35.23451069549255)
            #expect(display[index - 1].dropLast().last == surveySeam)
            #expect(display[index].dropFirst().first == surveySeam)
        } else if hakone {
            let spurSwitch = Coordinate(lon: 139.074289, lat: 35.2385735)
            let incoming = try #require(display[index - 1].firstIndex(of: spurSwitch))
            let outgoing = try #require(display[index].firstIndex(of: spurSwitch))
            #expect(Array(display[index - 1][incoming...]) == Array(display[index][...outgoing].reversed()))
            #expect(display[index].contains(Coordinate(lon: 139.0757745, lat: 35.2347961)))
        } else {
            #expect(display[index - 1].contains(Coordinate(lon: 133.11333, lat: 35.10687)))
        }
    }
}
