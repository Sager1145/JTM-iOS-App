import MapKit
import RailCore
import Testing
@testable import RailMap

@MainActor
struct MapWithheldPolylineCacheTests {
    private let run = [Coordinate(lon: 139.0, lat: 35.0), Coordinate(lon: 139.1, lat: 35.1)]

    @Test func sameFrameAndRunReturnsTheIdenticalPolyline() throws {
        let cache = MapNetworkGeometryCache()
        cache.beginFrame(key: "a")
        let first = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run))
        let second = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run))
        #expect(first === second)
    }

    @Test func frameChangeBuildsANewPolylineAndReturningReusesTheOldOne() throws {
        let cache = MapNetworkGeometryCache()
        cache.beginFrame(key: "a")
        let a = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run))
        cache.beginFrame(key: "b")
        let b = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run))
        #expect(a !== b)
        cache.beginFrame(key: "a")
        #expect(try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run)) === a)
    }

    @Test func changedContentOrDroppedLineBuildsANewPolyline() throws {
        let cache = MapNetworkGeometryCache()
        cache.beginFrame(key: "a")
        let original = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: run))
        let longer = run + [Coordinate(lon: 139.2, lat: 35.2)]
        let changed = try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: longer))
        #expect(changed !== original)
        cache.retainLineBuilds(withIDs: [])
        #expect(try #require(cache.withheldPolyline(lineID: "L", runIndex: 0, coordinates: longer)) !== changed)
    }
}
