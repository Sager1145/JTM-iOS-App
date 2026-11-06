import Foundation
import Testing
@testable import RailCore

struct PrecomputedRouteDisplayTests {
    static func network(_ lines: [CompactPackage.Line]) -> RouteNetwork {
        RouteNetwork(lines: lines.map { line in
            .init(lineId: line.id, name: line.name, operator: line.operator,
                  isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                  parts: DisplayParts.parts(for: line), intervals: RailIntervalCodes.intervals(for: line),
                  compactLine: line)
        })
    }

    @Test("cached Oedo ride follows the surveyed curve while retaining its source")
    func oedoPrecomputeCurve() throws {
        let package = try PortFixtures.package(country: "jp")
        let line = try #require(package.lines.first { $0.id == "jp-東京都-12号線大江戸線-2" })
        let url = try PortFixtures.repositoryRoot().appending(path: "app/tests/fixtures/tokyo-oedo-cached-route.json")
        let part = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let route = try #require(part["route"] as? [String: Any])
        let feature = try #require((route["features"] as? [[String: Any]])?.first)
        let geometry = try #require(feature["geometry"] as? [String: Any])
        let pairs = try #require(geometry["coordinates"] as? [[Double]])
        let raw = pairs.compactMap(Coordinate.init(pair:))
        #expect(raw.count == 15)
        let network = Self.network([line])
        for reverse in [false, true] {
            let source = reverse ? Array(raw.reversed()) : raw
            let hints = RouteHints(requiredLineNames: [line.name], requiredOperatorNames: [line.operator],
                                   fromStationCode: reverse ? "003954" : "003939",
                                   toStationCode: reverse ? "003939" : "003954")
            var cache = RouteProjectionCache()
            let parts = network.precomputedDisplayParts(source: source, hints: hints, cache: &cache)
            let display = try #require(parts.first)
            #expect(parts.count == 1)
            #expect(display.sourceCoordinates == source)
            #expect(display.displayLineIDs == [line.id])
            #expect(display.coordinates.count == 29)
            #expect(display.coordinates.contains(Coordinate(lon: 139.74885, lat: 35.65384)))
            #expect(!source.contains(Coordinate(lon: 139.74885, lat: 35.65384)))
            let historical = network.precomputedDisplayParts(
                source: source, hints: hints, temporalKind: .historical, cache: &cache)
            #expect(historical.first?.coordinates == source)
            #expect(historical.first?.sourceCoordinates == source)
            #expect(historical.first?.displayLineIDs.isEmpty == true)
            #expect(historical.first?.matchedSectionCodes.isEmpty == true)
        }
    }

    @Test("Osaki local display has one station/north owner without capped branch leads")
    func osakiSurveyedMain() throws {
        let package = try PortFixtures.package(country: "jp")
        let branches = package.lines.filter { $0.name == "大崎支線" }
        #expect(branches.count == 2)
        let main = try #require(branches.first { $0.alignmentOf == nil })
        let parts = DisplayParts.parts(for: main)
        #expect(parts.count == 1)
        let yamanote = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-山手線" })
        let trunk = DisplayParts.parts(for: yamanote).flatMap { $0 }
        for branch in branches {
            #expect(branch.displayBranchLeadIns.isEmpty)
            let anchor = branch.displayCoordinate(for: branch.stations[0])
            #expect(anchor == yamanote.displayCoordinate(for: yamanote.stations[1]))
            #expect(DisplayParts.parts(for: branch).first?.first == anchor)
            #expect(trunk.contains(anchor))
        }
    }

    @Test("NEX Shimbashi display approaches keep the underground tangent in both directions")
    func nexShimbashiTangentAndStroke() throws {
        let package = try PortFixtures.package(country: "jp")
        let line = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-総武線-3" })
        let network = Self.network(package.lines)
        let intervals = RailIntervalCodes.intervals(for: line)
        let station = line.displayCoordinate(for: line.stations[1])
        for reverse in [false, true] {
            var displayed: [[Coordinate]] = []
            for index in reverse ? [1, 0] : [0, 1] {
                let interval = intervals[index]
                let source = reverse ? Array(interval.coordinates.reversed()) : interval.coordinates
                let hints = RouteHints(requiredLineIDs: [line.id], sectionCodes: [interval.code],
                                       fromStationCode: reverse ? interval.toStationCode : interval.fromStationCode,
                                       toStationCode: reverse ? interval.fromStationCode : interval.toStationCode)
                var cache = RouteProjectionCache()
                let part = try #require(network.precomputedDisplayParts(
                    source: source, hints: hints, cache: &cache).first)
                #expect(part.sourceCoordinates == source)
                #expect(part.displayLineIDs == [line.id])
                #expect(part.matchedSectionCodes == [interval.code])
                displayed.append(part.coordinates)
            }
            let incoming = try #require(displayed.first)
            let outgoing = try #require(displayed.last)
            #expect(incoming.last == station)
            #expect(outgoing.first == station)
            let a = incoming[incoming.count - 2], b = outgoing[1]
            let u = (x: (station.lon - a.lon) * cos(station.lat * .pi / 180), y: station.lat - a.lat)
            let v = (x: (b.lon - station.lon) * cos(station.lat * .pi / 180), y: b.lat - station.lat)
            let angle = acos(max(-1, min(1, (u.x * v.x + u.y * v.y) / hypot(u.x, u.y) / hypot(v.x, v.y))))
            #expect(angle * 180 / .pi < 2)

            // The final renderer resolves rides against ALL displayed chains.
            // The tunnel remains distinct until the Shinagawa station throat.
            let chains = network.lines.flatMap { candidate in
                candidate.parts.enumerated().map { index, points in
                    ChainRef(id: "\(candidate.lineId)#\(index)", points: points,
                             measures: RouteNetwork.cumulativeMeasures(points), anchors: [])
                }
            }
            let strokeIndex = StrokeRide.Index(chains: chains)
            for points in displayed {
                let ref = try #require(strokeIndex.resolve(segment: points))
                #expect(ref.chainID == "\(line.id)#0")
            }
        }
    }

    // MARK: ridden routes draw on the repaired display interval

    /// Rides the given consecutive intervals (package order) of `line`,
    /// optionally reversed, exactly as a cached route carries them.
    static func ride(_ line: CompactPackage.Line, intervals range: ClosedRange<Int>, reverse: Bool)
        throws -> (display: [Coordinate], part: RouteNetwork.PrecomputedDisplayPart, expected: [[Coordinate]]) {
        let physical = RailIntervalCodes.intervals(for: line)
        let ordered = reverse ? Array(range.reversed()) : Array(range)
        var source: [Coordinate] = []
        for index in ordered {
            let path = reverse ? Array(physical[index].coordinates.reversed()) : physical[index].coordinates
            source += source.isEmpty ? path : Array(path.dropFirst())
        }
        let first = physical[ordered.first!], last = physical[ordered.last!]
        let hints = RouteHints(
            requiredLineIDs: [line.id], sectionCodes: ordered.map { physical[$0].code },
            fromStationCode: reverse ? first.toStationCode : first.fromStationCode,
            toStationCode: reverse ? last.fromStationCode : last.toStationCode)
        var cache = RouteProjectionCache()
        let part = try #require(network([line]).precomputedDisplayParts(
            source: source, hints: hints, cache: &cache).first)
        let reviewed = CompactPackage.decodeDisplayIntervals(line)
        let expected = ordered.map { reverse ? Array(reviewed[$0].reversed()) : reviewed[$0] }
        return (source, part, expected)
    }

    static func expectDrawsReviewed(
        _ line: CompactPackage.Line, intervals range: ClosedRange<Int>, reverse: Bool,
        from: String, to: String
    ) throws {
        let (source, part, expected) = try ride(line, intervals: range, reverse: reverse)
        #expect(part.sourceCoordinates == source)
        #expect(part.coordinates != source)
        let startAlias = try #require(line.displayStationCoordinates[from])
        let endAlias = try #require(line.displayStationCoordinates[to])
        #expect(Geometry.distanceMeters(part.coordinates.first!, startAlias) <= 0.5)
        #expect(Geometry.distanceMeters(part.coordinates.last!, endAlias) <= 0.5)
        for vertex in expected.flatMap({ $0 }) {
            let nearest = part.coordinates.map { Geometry.distanceMeters($0, vertex) }.min() ?? .infinity
            #expect(nearest <= 0.5)
        }
    }

    @Test("Iyotetsu Yokogawara rides draw the repaired display intervals")
    func iyotetsuRidesUseDisplayIntervals() throws {
        let line = try #require(try PortFixtures.package(country: "jp").lines
            .first { $0.id == "jp-伊予鉄道-横河原線" })
        // 北久米 -> 福音寺 -> いよ立花 -> 石手川公園 (intervals 10...12)
        try Self.expectDrawsReviewed(line, intervals: 10...12, reverse: false, from: "008795", to: "008780")
        try Self.expectDrawsReviewed(line, intervals: 11...12, reverse: true, from: "008780", to: "008791")
        try Self.expectDrawsReviewed(line, intervals: 11...11, reverse: false, from: "008791", to: "008784")
        try Self.expectDrawsReviewed(line, intervals: 11...11, reverse: true, from: "008784", to: "008791")
    }

    @Test("a display interval far from its physical interval is used, not the physical fallback")
    func offsetDisplayIntervalIsNotDropped() throws {
        let root = try PortFixtures.repositoryRoot()
        let data = try Data(contentsOf: root.appending(path: "app/public/rail/jp-2025.json"))
        let package = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var row = try #require((package["lines"] as? [[String: Any]])?
            .first { $0["id"] as? String == "jp-伊予鉄道-横河原線" })
        // Push every reviewed display coordinate ~100 m north of the physical track.
        func shifted(_ pair: [Double]) -> [Double] { [pair[0], pair[1] + 0.0009] }
        let stations = try #require(row["displayStationCoordinates"] as? [String: [Double]])
        row["displayStationCoordinates"] = stations.mapValues(shifted)
        let intervals = try #require(row["displayIntervalCoordinates"] as? [String: [[Double]]])
        row["displayIntervalCoordinates"] = intervals.mapValues { $0.map(shifted) }
        let line = try JSONDecoder().decode(
            CompactPackage.Line.self, from: JSONSerialization.data(withJSONObject: row))
        let physical = RailIntervalCodes.intervals(for: line)
        let offset = Geometry.distanceMeters(
            CompactPackage.decodeDisplayIntervals(line)[11][1], physical[11].coordinates[1])
        #expect(offset > 60)
        try Self.expectDrawsReviewed(line, intervals: 10...12, reverse: false, from: "008795", to: "008780")
        try Self.expectDrawsReviewed(line, intervals: 11...11, reverse: true, from: "008784", to: "008791")
    }
}
