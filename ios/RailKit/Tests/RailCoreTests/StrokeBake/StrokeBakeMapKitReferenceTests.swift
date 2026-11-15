import CoreLocation
import Foundation
import MapKit
import Testing
@testable import RailCore

/// Projection parity on the vertices the engine draws, now that the goldens in
/// `StrokeBakeEqualityTests` were captured on `StrokeProjection` (`Fixtures/README.md`,
/// "Projection"): `MKMapPoint` and `StrokeProjection` are compared at every drawn vertex and at a
/// lane-0 parallel line's ends, within 1e-6 map point. This is the same projection check as
/// `StrokeProjectionParityTests`, on the engine's own point set; it cannot tell whether the engine
/// uses the projection correctly.
@Suite("StrokeBakeMapKitReference")
struct StrokeBakeMapKitReferenceTests {

    static let zooms: [Double] = [5, 10.5, 13, 17]
    /// `StrokeProjectionParityTests.pointParity`.
    static let projectionTolerance = 1e-6

    static func mapKit(_ c: Coordinate) -> (x: Double, y: Double) {
        let p = MKMapPoint(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon))
        return (p.x, p.y)
    }

    static func network() throws -> NetworkStrokeBake.Network {
        StrokeBakeFixtures.network(try StrokeBakeFixtures.load())
    }

    @Test("projection parity on every vertex the engine draws")
    func drawnVertexProjectionParity() throws {
        let network = try Self.network()
        let byID = Dictionary(network.lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var worst = 0.0
        var vertices = 0
        for zoom in Self.zooms {
            let joined = JoinedChainCache()
            let prepared = try StrokeBake.prepare(
                lines: network.lines, strokes: network.lines.filter(\.continuous),
                allLines: byID, anchors: network.anchors, cachedStrokes: [:],
                joinedChains: joined, chainPixels: ChainPixelCache(joinedChains: joined),
                frame: StrokeBake.Frame(appZoom: zoom), partStyle: { _, _ in .solid })
            var chunks: [[Coordinate]] = []
            for line in prepared.lines.values {
                chunks += line.coordinateChunks + line.historicalCoordinateChunks
                chunks += line.familyCoordinateChunks.values.flatMap(\.coordinateChunks)
                chunks += line.familyFallbacks.flatMap(\.family.coordinateChunks)
            }
            for c in chunks.joined() {
                let mine = StrokeProjection.point(c)
                let apple = Self.mapKit(c)
                worst = max(worst, abs(mine.x - apple.x), abs(mine.y - apple.y))
                vertices += 1
            }
        }
        #expect(vertices > 100_000, "only \(vertices) vertices were compared")
        #expect(worst <= Self.projectionTolerance, "worst difference \(worst) map point over \(vertices) vertices")
    }

    @Test("a lane-0 parallel line keeps its end vertices where MapKit projects the source ends")
    func parallelEndsMatchMapKit() throws {
        let network = try Self.network()
        var worst = 0.0
        var compared = 0
        for zoom in Self.zooms {
            let frame = StrokeBake.Frame(appZoom: zoom)
            for line in network.lines where !line.continuous {
                for interval in line.intervals where interval.count >= 2 {
                    let out = StrokeBake.parallelLaneCoordinates(
                        interval, lane: 0, mapPointsPerPoint: frame.mapPointsPerPoint, scale: frame.scale)
                    guard let first = out.first, let last = out.last else { continue }
                    for (drawn, source) in [(first, interval[0]), (last, interval[interval.count - 1])] {
                        let want = Self.mapKit(source)
                        let got = Self.mapKit(drawn)
                        worst = max(worst, abs(got.x - want.x), abs(got.y - want.y))
                        compared += 1
                    }
                }
            }
        }
        #expect(compared > 200, "only \(compared) end vertices were compared")
        print("StrokeBakeMapKitReference: \(compared) parallel end vertices, worst \(worst) map point")
        // The end vertices are anchors: they survive the round trip through pixel space, so they
        // agree with MapKit to the projection tolerance (measured 9e-8).
        #expect(worst <= Self.projectionTolerance, "worst difference \(worst) map point")
    }
}
