import Foundation
import Testing
@testable import RailCore

struct TripRouteViaTests {
    @Test("A via station picks one of several parallel corridors")
    func viaNarrowsParallelCorridors() throws {
        let package = try fixture([line("long", ["A", "X", "B"], distance: 3),
                                   line("short", ["A", "Y", "B"])])
        guard case .corridors(let all) = try TripRoutePlanner.plan(
            package: package, request: .init(originCode: "A", destinationCode: "B")) else {
            Issue.record("Expected corridors"); return
        }
        #expect(all.count == 2)
        let found = try corridors(package, from: "A", to: "B", via: ["X"])
        #expect(found.count == 1)
        #expect(found[0].choice.stations.map(\.code) == ["A", "X", "B"])
        #expect(found[0].choice.lineIDs == ["long"])
        #expect(found[0].distanceKm == 6)
        #expect(found[0].junctions.isEmpty)
        #expect(found[0].id == found[0].choice.id)
    }

    @Test("A via on the same line yields the direct corridor's physical sections")
    func viaOnSameLine() throws {
        let package = try fixture([line("one", ["A", "M", "B"], distance: 2)])
        let direct = try corridors(package, from: "A", to: "B", via: [])
        let via = try corridors(package, from: "A", to: "B", via: ["M"])
        #expect(via.count == 1)
        #expect(via[0].choice.sectionCodes == direct[0].choice.sectionCodes)
        #expect(via[0].choice.routeSections == direct[0].choice.routeSections)
        #expect(via[0].choice.stations == direct[0].choice.stations)
        #expect(via[0].lineNames == ["one"])
        #expect(via[0].operatorNames == ["Operator"])
        #expect(via[0].distanceKm == direct[0].distanceKm)
        #expect(via[0].passStationCount == 1)
    }

    @Test("A line change at a via needs the same override as any other change")
    func viaLineChangeIsDisconnected() throws {
        let package = try fixture([line("first", ["A", "J"]), line("second", ["J", "C"])])
        guard case .disconnected(let changes) = try TripRoutePlanner.plan(
            package: package, request: .init(originCode: "A", destinationCode: "C"), viaCodes: ["J"])
        else { Issue.record("Expected disconnected via change"); return }
        #expect(changes.map(\.stationCode) == ["J"])
        #expect(changes.first?.link == TripConnectivity.Link.none)
        guard case .corridors(let found) = try TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: "A", destinationCode: "C", allowUnverifiedConnections: true),
            viaCodes: ["J"])
        else { Issue.record("Expected overridden corridor"); return }
        #expect(found.count == 1)
        #expect(found[0].choice.lineIDs == ["first", "second"])
        #expect(found[0].junctions.map(\.stationCode) == ["J"])
    }

    @Test("A leg without a route reports that leg's outcome")
    func unreachableVia() throws {
        let package = try fixture([line("one", ["A", "B"]), line("island", ["P", "Q"])])
        let outcome = try TripRoutePlanner.plan(
            package: package, request: .init(originCode: "A", destinationCode: "B"), viaCodes: ["P"])
        #expect(outcome != .sameStation)
        if case .corridors = outcome { Issue.record("An island via cannot form a corridor") }
    }

    @Test("Via codes drop endpoints and immediate repeats")
    func waypointCleanup() {
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "B")
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["A", "X", "X", "", "Y", "B"]) == ["X", "Y"])
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["B"]).isEmpty)
        // An endpoint repeated mid-list would force the trip to double back.
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["B", "X", "A"]) == ["X"])
    }

    @Test("No via stations is exactly the ordinary plan")
    func emptyViaMatchesPlan() throws {
        let package = try fixture([line("long", ["A", "X", "B"], distance: 3),
                                   line("short", ["A", "Y", "B"])])
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "B")
        #expect(try TripRoutePlanner.plan(package: package, request: request, viaCodes: ["A", "B"])
            == TripRoutePlanner.plan(package: package, request: request))
    }

    @Test("Joining refuses a corridor that doubles back over a station")
    func joinRejectsRevisits() throws {
        let package = try fixture([line("one", ["A", "M", "B"])])
        // B is reached first, then the trip would have to return through M.
        let outcome = try TripRoutePlanner.plan(
            package: package, request: .init(originCode: "A", destinationCode: "M"), viaCodes: ["B"])
        if case .corridors = outcome { Issue.record("A doubled-back route must not be offered") }
    }

    @Test("Geometry follows interval track in travel direction and merges one line")
    func geometryFollowsTrack() throws {
        let package = try fixture([bent("one", ["A", "M", "B"])])
        let forward = try corridors(package, from: "A", to: "B", via: [])[0]
        let cache = TripRouteGeometry.Cache(package: package)
        let pieces = TripRouteGeometry.pieces(for: forward.choice, cache: cache)
        #expect(pieces.count == 1)
        #expect(pieces[0].isConnector == false)
        #expect(pieces[0].lineID == "one")
        // Two intervals with a bend vertex each, sharing the M vertex once.
        #expect(pieces[0].coordinates.map(\.lon) == [0, 0.5, 1, 1.5, 2])
        #expect(pieces[0].coordinates.map(\.lat) == [0, 1, 0, 1, 0])

        let backward = try corridors(package, from: "B", to: "A", via: [])[0]
        let reversed = TripRouteGeometry.pieces(for: backward.choice, cache: cache)
        #expect(reversed.first?.coordinates.map(\.lon) == [2, 1.5, 1, 0.5, 0])
        let stations = TripRouteGeometry.stationCoordinates(for: backward.choice, cache: cache)
        #expect(stations.map { $0?.lon } == [2, 1, 0])
    }

    @Test("Each line of a joined route is its own geometry piece")
    func geometryPerLine() throws {
        let package = try fixture([line("first", ["A", "J"]), line("second", ["J", "C"])])
        let found = try corridors(package, from: "A", to: "C", via: ["J"], allowUnverified: true)
        let pieces = TripRouteGeometry.pieces(for: found[0].choice, cache: .init(package: package))
        #expect(pieces.map(\.lineID) == ["first", "second"])
        #expect(pieces.allSatisfy { !$0.isConnector })
    }

    @Test("A via on one side of the Osaka Loop leaves only that direction")
    func osakaLoopVia() throws {
        let package = try PortFixtures.package(country: "jp")
        let loop = "jp-西日本旅客鉄道-大阪環状線"
        let request = TripRoutePlanner.Request(
            originCode: "007068", destinationCode: "007439",
            originLineID: loop, destinationLineID: loop)
        guard case .corridors(let both) = try TripRoutePlanner.plan(package: package, request: request),
              both.count == 2 else {
            Issue.record("Expected both loop directions"); return
        }
        let first = Set(both[0].choice.stations.map(\.code))
        guard let via = both[1].choice.stations.dropFirst().first(where: { !first.contains($0.code) }) else {
            Issue.record("Expected a station only on the second direction"); return
        }
        guard case .corridors(let narrowed) = try TripRoutePlanner.plan(
            package: package, request: request, viaCodes: [via.code]) else {
            Issue.record("Expected a corridor through \(via.name)"); return
        }
        #expect(narrowed.count == 1)
        #expect(narrowed[0].choice.stations == both[1].choice.stations)
        #expect(narrowed[0].choice.routeSections == both[1].choice.routeSections)
        let pieces = TripRouteGeometry.pieces(for: narrowed[0].choice, cache: .init(package: package))
        #expect(pieces.count == 1)
        #expect((pieces.first?.coordinates.count ?? 0) > narrowed[0].choice.stations.count)
    }

    private func corridors(_ package: CompactPackage, from: String, to: String, via: [String],
                           allowUnverified: Bool = false) throws -> [TripRoutePlanner.Corridor] {
        let outcome = try TripRoutePlanner.plan(
            package: package,
            request: .init(originCode: from, destinationCode: to, allowUnverifiedConnections: allowUnverified),
            viaCodes: via)
        guard case .corridors(let values) = outcome else {
            Issue.record("Expected corridors, got \(outcome)")
            return []
        }
        return values
    }

    private func line(_ id: String, _ codes: [String], distance: Double = 1,
                      operatorName: String = "Operator") -> [String: Any] {
        ["id": id, "name": id, "operator": operatorName, "rank": 3, "kind": "jr_conventional",
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [distance, 0, [[Double($0), 0], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    /// Each interval has a bend vertex half way, one degree north.
    private func bent(_ id: String, _ codes: [String]) -> [String: Any] {
        ["id": id, "name": id, "operator": "Operator", "rank": 3, "kind": "jr_conventional",
         "stations": codes.enumerated().map { [$0.element, $0.element, Double($0.offset), 0] as [Any] },
         "segments": (0..<(codes.count - 1)).map {
             [1, 0, [[Double($0), 0], [Double($0) + 0.5, 1], [Double($0 + 1), 0]]] as [Any]
         }]
    }

    private func fixture(_ lines: [[String: Any]]) throws -> CompactPackage {
        let data = try JSONSerialization.data(withJSONObject: [
            "format": "compact-v1", "version": "test", "country": "jp", "lines": lines])
        return try JSONDecoder().decode(CompactPackage.self, from: data)
    }
}
