import Foundation
import RailCore
import Testing

/// `StrokeRide.resolve` matches a ridden segment's own drawn geometry
/// against a region's display chains — see the type's own doc for why this
/// replaced an earlier version that matched against `RouteNetwork.Line`
/// parts instead, which are not the same split as the display chains a
/// continuous-stroke renderer actually draws.
struct StrokeRideTests {

    /// The equirectangular ruler `ChainRef.measures` and `StrokeRide` are
    /// both built on: longitude scaled by the cosine of the midpoint
    /// latitude, both axes at 111 320 m/°. Duplicated here rather than
    /// exposed from `StrokeRide` because a fixture builder computing its own
    /// expected measures independently of the code under test is the point.
    private static func planarDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat = ((a.lat + b.lat) / 2) * Double.pi / 180
        let dx = (b.lon - a.lon) * 111_320 * cos(lat)
        let dy = (b.lat - a.lat) * 111_320
        return hypot(dx, dy)
    }

    private static func chain(id: String, points: [Coordinate], anchors: [Int] = []) -> ChainRef {
        var measures = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            measures[index] = measures[index - 1] + planarDistance(points[index - 1], points[index])
        }
        return ChainRef(id: id, points: points, measures: measures, anchors: anchors)
    }

    /// A straight five-vertex chain, evenly spaced north from
    /// (-100.000, 40.000) to (-100.000, 40.010) — about 1113 m — with
    /// platform anchors at both ends.
    private static func straightChain() -> ChainRef {
        let points = stride(from: 40.000, through: 40.010, by: 0.0025).map {
            Coordinate(lon: -100.000, lat: $0)
        }
        return chain(id: "chain-a", points: points, anchors: [0, points.count - 1])
    }

    @Test("both endpoints on the same chain resolve, snapped to its anchors")
    func sameChainHitWithSnappedAnchors() throws {
        let a = Self.straightChain()
        let segment = [a.points[0], a.points[a.points.count - 1]]

        let ref = try #require(StrokeRide.resolve(segment: segment, chains: [a]))

        #expect(ref.chainID == "chain-a")
        #expect(ref.from == a.measures[0])
        #expect(ref.to == a.measures[a.measures.count - 1])
        #expect(ref.fromAnchor == 0)
        #expect(ref.toAnchor == a.points.count - 1)
    }

    @Test("endpoints that each belong to a different chain resolve to nothing")
    func endpointsOnDifferentChainsAreRejected() {
        let a = Self.straightChain()
        // Far enough west of `a` (about 4.3 km at this latitude) that neither
        // chain's bounding box, let alone its endpoint tolerance, reaches the
        // other chain's own vertices.
        let bPoints = stride(from: 40.000, through: 40.010, by: 0.0025).map {
            Coordinate(lon: -100.050, lat: $0)
        }
        let b = Self.chain(id: "chain-b", points: bPoints)

        let segment = [a.points[0], b.points[b.points.count - 1]]

        #expect(StrokeRide.resolve(segment: segment, chains: [a, b]) == nil)
    }

    @Test("a short hop across a loop's own seam does not wrap onto the far end")
    func wrappingLoopHopIsRejected() {
        // A small loop whose last vertex lands a few metres from its first —
        // the loop closes on the ground but NOT on the chain's own measure
        // ruler, which still runs 0…totalLength around it. A real short hop
        // across that seam must not be read as a hop across the whole loop.
        let loop = Self.chain(
            id: "loop", points: [
                Coordinate(lon: -100.00000, lat: 40.00000),
                Coordinate(lon: -100.00000, lat: 40.00500),
                Coordinate(lon: -99.99400, lat: 40.00500),
                Coordinate(lon: -99.99400, lat: 40.00005),
                Coordinate(lon: -100.00005, lat: 40.00002),
            ])
        // The two ends of the loop are only a few metres apart on the
        // ground.
        #expect(Self.planarDistance(loop.points[0], loop.points[4]) < 10)
        // But hundreds of times further apart on the chain's own ruler.
        #expect(loop.measures[4] - loop.measures[0] > 2_000)

        let segment = [loop.points[0], loop.points[4]]

        #expect(StrokeRide.resolve(segment: segment, chains: [loop]) == nil)
    }

    @Test("a straight chord across a bend is rejected on length, not just distance")
    func chordAcrossABendIsRejected() {
        // An L-shaped chain; both endpoints sit exactly on its two ends, so
        // the endpoint-distance gate alone would accept this. The chain's
        // own measured path around the corner is materially longer than the
        // segment's straight-line chord between the same two points, which
        // is the guard this exercises.
        let corner = Self.chain(
            id: "corner", points: [
                Coordinate(lon: -100.00000, lat: 40.00000),
                Coordinate(lon: -100.00000, lat: 40.01000),
                Coordinate(lon: -99.99000, lat: 40.01000),
            ])
        let segment = [corner.points[0], corner.points[2]]

        let chordLength = Self.planarDistance(corner.points[0], corner.points[2])
        let chainSpan = corner.measures[2] - corner.measures[0]
        #expect(chainSpan - chordLength > 500.0)

        #expect(StrokeRide.resolve(segment: segment, chains: [corner]) == nil)
    }

    @Test("a hop running against the chain's own digitised direction still resolves")
    func reversedDirectionResolves() throws {
        let a = Self.straightChain()
        // Travelled from the chain's own end back to its own start.
        let segment = [a.points[a.points.count - 1], a.points[0]]

        let ref = try #require(StrokeRide.resolve(segment: segment, chains: [a]))

        #expect(ref.chainID == "chain-a")
        #expect(ref.from > ref.to)
        #expect(ref.fromAnchor == a.points.count - 1)
        #expect(ref.toAnchor == 0)
    }
}
