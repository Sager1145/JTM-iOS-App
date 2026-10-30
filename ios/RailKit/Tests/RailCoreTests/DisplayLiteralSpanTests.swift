import Foundation
import Testing
@testable import RailCore

struct DisplayLiteralSpanTests {
    private let pairs: [[Double]] = [
        [135, 34.9996], [135.001, 34.99985], [135.0023, 34.99997],
        [135.0036, 35], [135.0336, 35], [135.0349, 35.00005],
        [135.0362, 35.00024], [135.0372, 35.0005]
    ]

    private func row() -> [String: Any] {
        ["id": "jp-literal-fixture", "name": "Literal", "rank": 3,
         "stations": [["A", "A", pairs[0][0], pairs[0][1]],
                      ["B", "B", pairs[7][0], pairs[7][1]]],
         "segments": [[1, 1, Array(pairs.dropFirst())]],
         "displayIntervalCoordinates": ["0": pairs],
         "displayInterpolation": ["contract": "display-literal-spans-v1", "spans": [
            ["intervalIndex": 0, "sourceEdgeIndex": 3, "endpoints": [pairs[3], pairs[4]]]
         ]]]
    }

    private func decode(_ row: [String: Any]) throws -> CompactPackage.Line {
        try JSONDecoder().decode(CompactPackage.Line.self,
                                 from: JSONSerialization.data(withJSONObject: row))
    }

    @Test func exactOwnedSourceResolvesWithoutChangingGeometry() throws {
        let line = try decode(row())
        let coordinates = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        #expect(line.displayLiteralSpans.count == 1)
        let resolved = DisplayLiteralSpans.resolve(line, parts: [coordinates])
        #expect(resolved.count == 1 && resolved[0].count == 1)
        #expect(resolved[0][0].edgeIndex == 3)
        #expect(resolved[0][0].witnesses == Array(coordinates[2...5]))
        let projected = DisplayLiteralSpans.projected(resolved[0], coordinates: coordinates) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }
        #expect(projected.count == 1 && projected[0].edgeIndex == 3)
        #expect(line.displayIntervalCoordinates[0] == coordinates)
        #expect(line.stations.map(\.id) == ["A", "B"])
    }

    @Test(arguments: ["absent", "wrongType", "unknown", "missingDisplay", "wrongEdge", "duplicate", "overlap"],
          ["display-literal-spans-v1", "display-source-corners-v1"])
    func invalidOptionalAuthorityRetainsOrdinaryDecode(kind: String, contract: String) throws {
        var input = row()
        var declaration = input["displayInterpolation"] as! [String: Any]
        declaration["contract"] = contract
        input["displayInterpolation"] = declaration
        let span = (declaration["spans"] as! [[String: Any]])[0]
        switch kind {
        case "absent": input.removeValue(forKey: "displayInterpolation")
        case "wrongType": input["displayInterpolation"] = "invalid"
        case "unknown": declaration["contract"] = "future"; input["displayInterpolation"] = declaration
        case "missingDisplay": input.removeValue(forKey: "displayIntervalCoordinates")
        case "wrongEdge":
            var changed = span; changed["sourceEdgeIndex"] = 2
            declaration["spans"] = [changed]; input["displayInterpolation"] = declaration
        case "duplicate": declaration["spans"] = [span, span]; input["displayInterpolation"] = declaration
        case "overlap":
            var changed = span; changed["sourceEdgeIndex"] = 4
            changed["endpoints"] = [pairs[4], pairs[5]]
            declaration["spans"] = [span, changed]; input["displayInterpolation"] = declaration
        default: break
        }
        let line = try decode(input)
        #expect(line.displayLiteralSpans.isEmpty)
        #expect(line.stations.count == 2 && line.segments.count == 1)
    }

    @Test func coordinateCompactionCannotInventRawAdjacency() throws {
        var input = row()
        var source = pairs
        source.insert([135], at: 4)
        input["displayIntervalCoordinates"] = ["0": source]
        let line = try decode(input)
        #expect(line.displayIntervalCoordinates[0]?.count == pairs.count)
        #expect(line.displayLiteralSpans.isEmpty)
    }

    @Test func changedOrRepeatedConstructedFootprintsCannotOptIn() throws {
        let line = try decode(row())
        let source = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        var changed = source
        changed[2] = Coordinate(lon: source[2].lon + 0.00001, lat: source[2].lat)
        #expect(DisplayLiteralSpans.resolve(line, parts: [changed])[0].isEmpty)
        #expect(DisplayLiteralSpans.resolve(line, parts: [source, source]).allSatisfy { $0.isEmpty })
    }

    @Test func displayStationAliasCannotBecomeLiteralShoulder() throws {
        var input = row()
        input["displayStationCoordinates"] = ["B": pairs[5]]
        let line = try decode(input)
        #expect(line.displayLiteralSpans.isEmpty)
    }

    @Test func packedWitnessesBindToActualWrittenCoordinates() throws {
        let written = pairs.map { $0.map { ($0 * 10_000_000).rounded() / 10_000_000 } }
        let data = try JSONSerialization.data(withJSONObject: [3, Array(written[2...5])])
        let span = try JSONDecoder().decode(DisplayLiteralSpans.Span.self, from: data)
        let source = written.map { Coordinate(lon: $0[0], lat: $0[1]) }
        #expect(DisplayLiteralSpans.projected([span], coordinates: source) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }.count == 1)
        var changed = source
        changed[4] = Coordinate(lon: source[4].lon + 0.00000001, lat: source[4].lat)
        #expect(DisplayLiteralSpans.projected([span], coordinates: changed) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }.isEmpty)
    }

    @Test func extremeOptionalIndicesRetainOrdinaryGeometry() throws {
        var input = row()
        input["displayInterpolation"] = ["contract": "display-literal-spans-v1", "spans": [
            ["intervalIndex": 0, "sourceEdgeIndex": Int.max, "endpoints": [pairs[3], pairs[4]]]
        ]]
        let line = try decode(input)
        #expect(line.displayLiteralSpans.isEmpty)
        #expect(line.stations.count == 2 && line.segments.count == 1)

        let data = try JSONSerialization.data(withJSONObject: [Int.max, Array(pairs[2...5])])
        let span = try JSONDecoder().decode(DisplayLiteralSpans.Span.self, from: data)
        let coordinates = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        #expect(DisplayLiteralSpans.projected([span], coordinates: coordinates) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }.isEmpty)
    }

    @Test func sharedShoulderCannotClaimUniqueConstructedOwnership() throws {
        let line = try decode(row())
        let source = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        let branch = [source[2], Coordinate(lon: 140, lat: 36)]
        #expect(DisplayLiteralSpans.resolve(line, parts: [source, branch]).allSatisfy { $0.isEmpty })
        let span = DisplayLiteralSpans.Span(edgeIndex: 3, witnesses: Array(source[2...5]))
        #expect(DisplayLiteralSpans.projected([span], coordinates: source + branch) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }.isEmpty)
    }

    @Test func stationAliasCannotHidePhysicalStationShoulder() throws {
        var input = row()
        input["stations"] = [["A", "A", pairs[0][0], pairs[0][1]],
                             ["B", "B", pairs[5][0], pairs[5][1]]]
        input["displayStationCoordinates"] = ["B": pairs[7]]
        #expect(try decode(input).displayLiteralSpans.isEmpty)
    }
    @Test func sourceCornerModeSurvivesRawResolvedProjectedAndPackedBinding() throws {
        var input = row()
        var declaration = input["displayInterpolation"] as! [String: Any]
        declaration["contract"] = "display-source-corners-v1"
        input["displayInterpolation"] = declaration
        let line = try decode(input)
        #expect(line.displayLiteralSpans.count == 1)
        #expect(line.displayLiteralSpans[0].mode == "source-corners-v1")
        let source = pairs.map { Coordinate(lon: $0[0], lat: $0[1]) }
        let spans = DisplayLiteralSpans.resolve(line, parts: [source])
        #expect(spans[0].count == 1 && spans[0][0].mode == "source-corners-v1")
        let projected = DisplayLiteralSpans.projected(spans[0], coordinates: source) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }
        #expect(projected.count == 1 && projected[0].mode == "source-corners-v1")
        let data = try JSONSerialization.data(withJSONObject: [3, Array(pairs[2...5]), "source-corners-v1"])
        let packed = try JSONDecoder().decode(DisplayLiteralSpans.Span.self, from: data)
        #expect(packed == spans[0][0])
        let unknown = try JSONSerialization.data(withJSONObject: [3, Array(pairs[2...5]), "future"])
        #expect(throws: (any Error).self) { try JSONDecoder().decode(DisplayLiteralSpans.Span.self, from: unknown) }
        var changed = source; changed[5] = Coordinate(lon: source[5].lon + 1e-8, lat: source[5].lat)
        #expect(DisplayLiteralSpans.projected([packed], coordinates: changed) {
            ContinuousStroke.Point(x: $0.lon, y: $0.lat)
        }.isEmpty)
        input["displayStationCoordinates"] = ["B": pairs[5]]
        #expect(try decode(input).displayLiteralSpans.isEmpty)
        let branch = [source[2], Coordinate(lon: 140, lat: 36)]
        #expect(DisplayLiteralSpans.resolve(line, parts: [source, branch]).allSatisfy { $0.isEmpty })
    }

}
