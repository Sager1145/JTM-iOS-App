import Foundation
import Testing

@testable import RailCore

@Suite("trip note route geometry")
struct TripNoteRouteTests {
    // Three stops along the equator-ish: A at 0, B at 0.01°, C at 0.03° lon.
    static let a = Coordinate(lon: 139.00, lat: 35.0)
    static let b = Coordinate(lon: 139.01, lat: 35.0)
    static let c = Coordinate(lon: 139.03, lat: 35.0)

    static let stops = [
        Stop(name: "A", stopType: "origin", rideSegment: true, stationID: "a"),
        Stop(name: "B", stopType: "passenger_stop", rideSegment: true, stationID: "b"),
        Stop(name: "C", stopType: "destination", rideSegment: true, stationID: "c"),
    ]

    static var mapped: TripNoteRoute {
        TripNoteRoute(intervalStrokes: [
            (0, [a, b]),
            // Interval 1 drawn as two parts with a gap: the gap adds no length.
            (1, [b, Coordinate(lon: 139.02, lat: 35.0)]),
            (1, [Coordinate(lon: 139.02, lat: 35.0), c]),
        ], stopCount: 3)
    }

    @Test("stop arcs come from the interval mapping")
    func mappedArcs() throws {
        let route = Self.mapped
        let arcs = route.stopArcs.compactMap { $0 }
        #expect(arcs.count == 3)
        #expect(arcs[0] == 0)
        #expect(abs(arcs[2] - route.length) < 1e-6)
        #expect(abs(arcs[1] / route.length - 1.0 / 3.0) < 0.01)
    }

    @Test("point at fraction and projection are inverses")
    func inverse() throws {
        let route = Self.mapped
        let point = try #require(route.point(fromStop: 1, toStop: 2, fraction: 0.25))
        #expect(abs(point.lon - 139.015) < 1e-4)
        let projection = try #require(route.project(Coordinate(lon: 139.015, lat: 35.0005), maxMeters: 200))
        #expect(projection.fromStop == 1 && projection.toStop == 2)
        #expect(abs(projection.fraction - 0.25) < 0.01)
        #expect(projection.distanceMeters < 60)
        #expect(route.project(Coordinate(lon: 139.015, lat: 35.05), maxMeters: 200) == nil)
    }

    @Test("a point near a stop snaps to a station anchor")
    func stationSnap() throws {
        let route = Self.mapped
        let projection = try #require(
            route.project(Coordinate(lon: 139.0101, lat: 35.0), maxMeters: 200, stationSnapMeters: 150))
        #expect(projection.nearStop == 1)
        let anchor = route.anchor(for: projection, stops: Self.stops, fallback: nil)
        #expect(anchor == .station(TripNoteStation(stop: Self.stops[1]), fallback: nil))
        let mid = try #require(route.project(Coordinate(lon: 139.005, lat: 35.0), maxMeters: 200,
                                             stationSnapMeters: 150))
        guard case .interval(let from, let to, let fraction, _)? =
                route.anchor(for: mid, stops: Self.stops, fallback: nil) else {
            Issue.record("expected an interval anchor"); return
        }
        #expect(from.name == "A" && to.name == "B" && abs(fraction - 0.5) < 0.01)
    }

    @Test("without a mapping, stops are placed by projecting them in order")
    func projectedStops() throws {
        let route = TripNoteRoute(strokes: [[Self.a, Self.b, Self.c]],
                                  projectingStops: [Self.a, Self.b, Self.c])
        let arcs = route.stopArcs.compactMap { $0 }
        #expect(arcs.count == 3)
        #expect(abs(arcs[1] / route.length - 1.0 / 3.0) < 0.01)
        // A stop far from the line is left unplaced, and intervals span past it.
        let sparse = TripNoteRoute(strokes: [[Self.a, Self.b, Self.c]],
                                   projectingStops: [Self.a, Coordinate(lon: 140, lat: 36), Self.c])
        #expect(sparse.stopArcs[1] == nil)
        #expect(sparse.point(fromStop: 0, toStop: 2, fraction: 0.5) != nil)
        #expect(sparse.point(fromStop: 0, toStop: 1, fraction: 0.5) == nil)
    }

    @Test("a re-solved route moves the note with its interval")
    func resolveMovesNote() throws {
        let note = TripNoteAnchor.interval(from: TripNoteStation(stop: Self.stops[1]),
                                           to: TripNoteStation(stop: Self.stops[2]),
                                           fraction: 0.5, fallback: Self.b)
        let placement = TripNotePlacement.resolve(note, stops: Self.stops)
        let before = try #require(Self.mapped.coordinate(for: placement))
        // Same stations, different (detoured) geometry.
        let detour = TripNoteRoute(intervalStrokes: [
            (0, [Self.a, Self.b]),
            (1, [Self.b, Coordinate(lon: 139.02, lat: 35.01), Self.c]),
        ], stopCount: 3)
        let after = try #require(detour.coordinate(for: placement))
        #expect(before != after)
        #expect(after.lat > 35.005)
    }

    @Test("midpoint is half the drawn length")
    func midpoint() throws {
        let mid = try #require(Self.mapped.midpoint())
        #expect(abs(mid.lon - 139.015) < 1e-4)
    }
}
