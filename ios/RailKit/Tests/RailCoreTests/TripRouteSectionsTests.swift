import Foundation
import Testing
@testable import RailCore

struct TripRouteSectionsTests {
    @Test("Vias cut the trip into station-to-station sections; only the ends keep their lines")
    func sectionSplit() {
        let request = TripRoutePlanner.Request(
            originCode: "A", destinationCode: "B", originLineID: "first", destinationLineID: "last")
        let sections = TripRoutePlanner.sectionRequests(request, viaCodes: ["X", "X", "", "Y"])
        #expect(sections.map(\.originCode) == ["A", "X", "Y"])
        #expect(sections.map(\.destinationCode) == ["X", "Y", "B"])
        #expect(sections.map(\.originLineID) == ["first", nil, nil])
        #expect(sections.map(\.destinationLineID) == [nil, nil, "last"])
        #expect(TripRoutePlanner.sectionRequests(request, viaCodes: []).count == 1)
    }

    @Test("Only the section with two paths is ambiguous; the others settle alone")
    func ambiguityIsPerSection() throws {
        // A→M: two parallel lines. M→B: one line.
        let package = try fixture([line("long", ["A", "X", "M"], distance: 3),
                                   line("short", ["A", "Y", "M"]),
                                   line("tail", ["M", "N", "B"])])
        let sections = TripRoutePlanner.sectionRequests(
            .init(originCode: "A", destinationCode: "B", allowUnverifiedConnections: true), viaCodes: ["M"])
        let outcomes = try sections.map { try corridors(package, $0) }
        #expect(outcomes.map(\.count) == [2, 1])
        let joined = TripRoutePlanner.joining(
            [outcomes[0][0], outcomes[1][0]], allowUnverifiedConnections: true) { $0 }
        guard case .corridors(let route) = joined else { Issue.record("Expected a joined route"); return }
        #expect(route[0].choice.stations.map(\.code).first == "A")
        #expect(route[0].choice.stations.map(\.code).last == "B")
        #expect(route[0].distanceKm == outcomes[0][0].distanceKm + outcomes[1][0].distanceKm)
    }

    @Test("A via narrows parallel corridors to the one through it, as the whole-trip plan proves")
    func viaNarrowsParallelCorridors() throws {
        let package = try fixture([line("long", ["A", "X", "B"], distance: 3),
                                   line("short", ["A", "Y", "B"])])
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "B")
        let whole = try corridors(package, request)
        #expect(whole.count == 2)
        let sections = try TripRoutePlanner.sectionRequests(request, viaCodes: ["X"]).map { try corridors(package, $0) }
        #expect(sections.map(\.count) == [1, 1])
        guard case .corridors(let route) = TripRoutePlanner.joining(
            sections.map { $0[0] }, wholeTrip: whole, allowUnverifiedConnections: false, lineName: { $0 })
        else { Issue.record("Expected the proven corridor"); return }
        #expect(route[0].choice.stations.map(\.code) == ["A", "X", "B"])
        #expect(route[0].junctions.isEmpty)
        #expect(route[0] == whole.first { $0.choice.lineIDs == ["long"] })
    }

    @Test("A line change at a via needs the same override as any other change")
    func viaLineChangeIsDisconnected() throws {
        let package = try fixture([line("first", ["A", "J"]), line("second", ["J", "C"])])
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "C")
        let sections = try TripRoutePlanner.sectionRequests(request, viaCodes: ["J"]).map { try corridors(package, $0)[0] }
        guard case .disconnected(let changes) = TripRoutePlanner.joining(
            sections, allowUnverifiedConnections: false, lineName: { $0 })
        else { Issue.record("Expected disconnected via change"); return }
        #expect(changes.map(\.stationCode) == ["J"])
        #expect(changes.first?.link == TripConnectivity.Link.none)
        guard case .corridors(let found) = TripRoutePlanner.joining(
            sections, allowUnverifiedConnections: true, lineName: { $0 })
        else { Issue.record("Expected overridden corridor"); return }
        #expect(found[0].choice.lineIDs == ["first", "second"])
        #expect(found[0].junctions.map(\.stationCode) == ["J"])
        #expect(found[0].choice.lineNames == ["first", "second"])
    }

    @Test("Via codes drop endpoints and immediate repeats")
    func waypointCleanup() {
        let request = TripRoutePlanner.Request(originCode: "A", destinationCode: "B")
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["A", "X", "X", "", "Y", "B"]) == ["X", "Y"])
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["B"]).isEmpty)
        // An endpoint repeated mid-list would force the trip to double back.
        #expect(TripRoutePlanner.waypointCodes(request: request, viaCodes: ["B", "X", "A"]) == ["X"])
    }

    @Test("Joining refuses a route that doubles back over a station")
    func joinRejectsRevisits() throws {
        let package = try fixture([line("one", ["A", "M", "B"])])
        let sections = try TripRoutePlanner.sectionRequests(
            .init(originCode: "A", destinationCode: "M"), viaCodes: ["B"]).map { try corridors(package, $0)[0] }
        #expect(TripRoutePlanner.joining(sections, allowUnverifiedConnections: true, lineName: { $0 }) == .noRoute)
    }

    @Test("Passing stations fill between the reader's stops, keep their clocks, and refill one section alone")
    func passingStationFill() throws {
        let package = try fixture([line("long", ["A", "X", "M"], distance: 3),
                                   line("short", ["A", "Y", "M"]),
                                   line("tail", ["M", "N", "B"])])
        let sections = TripRoutePlanner.sectionRequests(
            .init(originCode: "A", destinationCode: "B", allowUnverifiedConnections: true), viaCodes: ["M"])
        let options = try sections.map { try corridors(package, $0) }
        var record = Train(id: "t", number: "T", origin: "A", destination: "B", stops: [
            Stop(name: "A", n02StationCode: "A", departure: "9:00", stopType: "origin", rideSegment: true),
            Stop(name: "M", n02StationCode: "M", arrival: "9:30", departure: "9:32",
                 stopType: "passenger_stop", rideSegment: true),
            Stop(name: "B", n02StationCode: "B", arrival: "10:00", stopType: "destination", rideSegment: true),
        ])
        record.stops[1].platformNumber = 4
        func filled(_ first: Int) throws -> Train {
            guard case .corridors(let route) = TripRoutePlanner.joining(
                [options[0][first], options[1][0]], allowUnverifiedConnections: true, lineName: { $0 })
            else { throw CancellationError() }
            return try #require(LocalJourneyAutofill.proposal(train: record, choice: route[0].choice)).train
        }
        let viaX = try filled(options[0].firstIndex { $0.choice.lineIDs == ["long"] } ?? 0)
        let viaY = try filled(options[0].firstIndex { $0.choice.lineIDs == ["short"] } ?? 1)
        #expect(viaX.stops.map(\.n02StationCode) == ["A", "X", "M", "N", "B"])
        #expect(viaY.stops.map(\.n02StationCode) == ["A", "Y", "M", "N", "B"])
        for train in [viaX, viaY] {
            let m = try #require(train.stops.first { $0.n02StationCode == "M" })
            #expect(m.arrival == "9:30")
            #expect(m.platformNumber == 4)
            #expect(train.stops.first?.departure == "9:00")
            // Filled stations are marked as generated, the reader's are not.
            #expect(train.stops.filter { $0.routeEditing?.generatedBy != nil }.map(\.n02StationCode).count == 2)
        }
        // The second section did not change between the two choices.
        #expect(viaX.stops.suffix(3).map(\.n02StationCode) == viaY.stops.suffix(3).map(\.n02StationCode))
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
        let sections = try TripRoutePlanner.sectionRequests(
            .init(originCode: "A", destinationCode: "C"), viaCodes: ["J"]).map { try corridors(package, $0)[0] }
        guard case .corridors(let found) = TripRoutePlanner.joining(
            sections, allowUnverifiedConnections: true, lineName: { $0 }) else { Issue.record("join"); return }
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
        let sections = try TripRoutePlanner.sectionRequests(request, viaCodes: [via.code])
            .map { try corridors(package, $0) }
        // Planned alone, a loop section can go either way round. The way that
        // runs through the trip's other end is not a real choice.
        #expect(sections.allSatisfy { !$0.isEmpty })
        let waypoints = [request.originCode, via.code, request.destinationCode]
        let settled = sections.map { TripRoutePlanner.plausible($0, waypoints: waypoints) }
        #expect(settled.allSatisfy { $0.count == 1 }, "A via on one side settles both sections")
        guard case .corridors(let narrowed) = TripRoutePlanner.joining(
            settled.map { $0[0] }, wholeTrip: both, allowUnverifiedConnections: false, lineName: { $0 }) else {
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
        precondition(via.isEmpty, "Vias are sections; plan each with corridors(_:_:)")
        return try corridors(package, .init(
            originCode: from, destinationCode: to, allowUnverifiedConnections: allowUnverified))
    }

    private func corridors(_ package: CompactPackage, _ request: TripRoutePlanner.Request) throws -> [TripRoutePlanner.Corridor] {
        let outcome = try TripRoutePlanner.plan(package: package, request: request)
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
