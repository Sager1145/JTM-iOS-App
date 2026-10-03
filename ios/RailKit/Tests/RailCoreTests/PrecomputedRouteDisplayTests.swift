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

    @Test("Osaki north forks join the legacy N02 representative without an appended main")
    func osakiSurveyedMain() throws {
        let package = try PortFixtures.package(country: "jp")
        let branches = package.lines.filter { $0.name == "大崎支線" }
        #expect(branches.count == 2)
        let main = try #require(branches.first { $0.alignmentOf == nil })
        let parts = DisplayParts.parts(for: main)
        #expect(parts.count == 2)
        let yamanote = try #require(package.lines.first { $0.id == "jp-東日本旅客鉄道-山手線" })
        let trunk = DisplayParts.parts(for: yamanote).flatMap { $0 }
        for branch in branches {
            let lead = try #require(branch.displayBranchLeadIns.first)
            #expect(lead.last == branch.displayCoordinate(for: branch.stations[0]))
            #expect(trunk.contains(try #require(lead.first)))
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
}
