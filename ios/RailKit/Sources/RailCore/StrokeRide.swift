import Foundation

/// One display chain's own geometry, in WGS84 — exactly what
/// `RailMapView`'s continuous-stroke build joins a line's intervals into
/// before projecting them to screen pixels, handed back here so a ride's
/// drawn segment can be matched against the SAME chain the map itself
/// draws, rather than against the compact package's `RouteNetwork.Line`
/// parts.
///
/// A prior version of this feature resolved a ride against
/// `RouteNetwork.Line.parts`, reasoning that the display build's alignment
/// gate splits a line's parts the same way it splits continuous chains.
/// That reasoning was wrong on the load-bearing case: `RouteNetwork.Line`
/// comes from `DisplayParts.parts(for:topology:)` run on the COMPACT
/// package, which carries no blocked intervals at all — the display
/// network's own alignment gate runs later, in the display build, over
/// geometry `RouteNetwork` never sees. So for every NA line with a withheld
/// interval, every ride resolved `partIndex == 0` and sliced out of chain
/// 0 regardless of which chain it actually ran on, a branch line's several
/// web parts keyed chains that did not exist, and the vertex indices
/// `fromAnchor`/`toAnchor` named were in the part's own numbering, not the
/// display chain's. `ChainRef` and ``StrokeRide/resolve(segment:chains:)``
/// below match against the display chains themselves — the only geometry
/// that is actually correct to slice a ride's own drawn pixels out of.
public struct ChainRef: Sendable {
    /// The display line's own id — stable within one rebuild, and the same
    /// identity a continuous-stroke build's pixel geometry is keyed by, so a
    /// resolved ``StrokeRef/chainID`` names exactly the entry a renderer
    /// already holds.
    public var id: String
    /// The chain's intervals, joined at their shared station anchors — one
    /// vertex per point, in the SAME order and count as ``measures`` and as
    /// the pixel geometry a renderer projects from this same coordinate
    /// list.
    public var points: [Coordinate]
    /// Cumulative metres along `points`, on the equirectangular ruler
    /// `rail-network.js`'s own `distanceMeters` uses: longitude scaled by
    /// the cosine of the midpoint latitude, both axes at 111 320 m/°.
    /// `measures[0] == 0`; `measures.count == points.count`.
    public var measures: [Double]
    /// Vertex indices into `points` where a platform sits — the same
    /// indices `ContinuousStroke.buildStroke`'s own `anchors` parameter
    /// takes, so a snapped endpoint's index is usable against the built
    /// stroke's `anchors` array without translation.
    public var anchors: [Int]

    public init(id: String, points: [Coordinate], measures: [Double], anchors: [Int]) {
        self.id = id
        self.points = points
        self.measures = measures
        self.anchors = anchors
    }
}

/// Where a ride's own drawn segment sits on a continuous-stroke display
/// chain, as found by ``StrokeRide/resolve(segment:chains:)``.
public struct StrokeRef: Sendable, Equatable {
    /// The chain's own id — ``ChainRef/id``.
    public var chainID: String
    /// Metres along the chain, on ``ChainRef/measures``' own ruler. `from`
    /// is where the ride starts and `to` where it ends, so `from > to` when
    /// the ride runs against the chain's own digitised direction —
    /// `ContinuousStroke.slice(points:measures:from:to:)` reads the sign the
    /// same way.
    public var from: Double
    public var to: Double
    /// The chain vertex index (into `ChainRef.points`/`.anchors`) the
    /// `from`/`to` endpoint snapped to, when it landed within
    /// `StrokeRide.anchorSnapMeters` of a platform. `nil` when the endpoint
    /// is a plain interpolation on open track.
    public var fromAnchor: Int?
    public var toAnchor: Int?

    public init(
        chainID: String, from: Double, to: Double,
        fromAnchor: Int? = nil, toAnchor: Int? = nil
    ) {
        self.chainID = chainID
        self.from = from
        self.to = to
        self.fromAnchor = fromAnchor
        self.toAnchor = toAnchor
    }
}

/// Matching a ridden segment's own drawn geometry against the display
/// chains a continuous-stroke region actually draws.
///
/// Pure point-matching over geometry the caller already built for
/// rendering: nothing here reads a package, a topology or a route graph, so
/// a ride ends up sliced on the SAME polyline the network itself draws —
/// never a second, independently decimated one that could disagree with it
/// pixel for pixel.
public enum StrokeRide {
    /// Prepared once per immutable display-network generation. Blocks retain
    /// edge order, so equal-distance projections and first-chain ties have
    /// exactly the same answer as the exhaustive matcher.
    public struct Index: Sendable {
        private struct Bounds: Sendable {
            let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

            init(_ points: ArraySlice<Coordinate>) {
                minLat = points.map(\.lat).min() ?? 0
                maxLat = points.map(\.lat).max() ?? 0
                minLon = points.map(\.lon).min() ?? 0
                maxLon = points.map(\.lon).max() ?? 0
            }

            func contains(_ point: Coordinate, pad: Double) -> Bool {
                point.lat >= minLat - pad && point.lat <= maxLat + pad
                    && point.lon >= minLon - pad && point.lon <= maxLon + pad
            }

            func distance(to point: Coordinate, sx: Double) -> Double {
                let dx = max(minLon - point.lon, 0, point.lon - maxLon) * abs(sx)
                let dy = max(minLat - point.lat, 0, point.lat - maxLat) * 111_320
                return hypot(dx, dy)
            }
        }

        private struct Entry: Sendable {
            let chain: ChainRef
            let bounds: Bounds
            let blocks: [(edges: Range<Int>, bounds: Bounds)]

            init(_ chain: ChainRef) {
                self.chain = chain
                bounds = Bounds(chain.points[...])
                blocks = stride(from: 1, to: chain.points.count, by: 32).map { start in
                    let end = min(start + 32, chain.points.count)
                    return (start..<end, Bounds(chain.points[(start - 1)..<end]))
                }
            }

            func project(_ point: Coordinate, tolerance: Double) -> Projection? {
                let sx = 111_320.0 * cos(point.lat * .pi / 180)
                var best: Projection?
                for block in blocks {
                    // Small rounding allowance keeps an edge on the exact
                    // tolerance boundary eligible for the precise test.
                    guard block.bounds.distance(to: point, sx: sx)
                        <= (best?.distance ?? tolerance) + 0.000001 else { continue }
                    if let candidate = StrokeRide.project(
                        point, onto: chain.points, measures: chain.measures, edges: block.edges),
                        candidate.distance <= tolerance,
                        best == nil || candidate.distance < best!.distance {
                        best = candidate
                    }
                }
                return best
            }
        }

        private let entries: [Entry]

        public init(chains: [ChainRef]) {
            entries = chains.filter {
                $0.points.count >= 2 && $0.points.count == $0.measures.count
            }.map(Entry.init)
        }

        public func resolve(segment: [Coordinate]) -> StrokeRef? {
            guard segment.count >= 2 else { return nil }
            let first = segment[0], last = segment[segment.count - 1]
            let length = StrokeRide.polylineLength(segment)
            for entry in entries {
                guard entry.bounds.contains(first, pad: boundsPadDegrees),
                    entry.bounds.contains(last, pad: boundsPadDegrees),
                    let p1 = entry.project(first, tolerance: endpointToleranceMeters),
                    let p2 = entry.project(last, tolerance: endpointToleranceMeters),
                    abs(abs(p2.measure - p1.measure) - length) <= max(0.25 * length, 500)
                else { continue }
                let step = max(1, (segment.count - 2) / maxMiddleSamples)
                guard stride(from: 1, to: segment.count - 1, by: step).allSatisfy({
                    entry.project(segment[$0], tolerance: middleToleranceMeters) != nil
                }) else { continue }
                let (from, fromAnchor) = StrokeRide.snap(p1, chain: entry.chain)
                let (to, toAnchor) = StrokeRide.snap(p2, chain: entry.chain)
                return StrokeRef(chainID: entry.chain.id, from: from, to: to,
                    fromAnchor: fromAnchor, toAnchor: toAnchor)
            }
            return nil
        }
    }

    /// Both endpoints must land on one chain within this many metres —
    /// generous enough for a platform whose recorded stop and the display
    /// line's own survey disagree by a station's width, tight enough that a
    /// parallel line two tracks over is never mistaken for this one.
    public static let endpointToleranceMeters = 60.0
    /// How far a middle vertex may drift from the matched chain before the
    /// match is rejected — the other half of the chord/loop guard below: a
    /// hop whose two ENDS sit on the chain but whose middle bows away from
    /// it is not actually running on that chain's own track.
    public static let middleToleranceMeters = 150.0
    /// How close an endpoint must land to one of the chain's own platform
    /// anchors to be treated as boarding/alighting there, rather than at an
    /// open-track interpolation.
    public static let anchorSnapMeters = 150.0
    /// At most this many interior vertices are sampled — enough to catch a
    /// bow away from the chain without walking every vertex of a segment
    /// that can run to hundreds of them.
    public static let maxMiddleSamples = 20
    /// A coarse, generous prefilter pad in degrees (roughly 1.1 km) — cheap
    /// enough to run before a single projection, and wide enough that it
    /// never rejects a chain the precise check below would have accepted.
    private static let boundsPadDegrees = 0.01

    /// Where a ride's own drawn segment sits on one of `chains`, or `nil`
    /// when no chain both endpoints land on also passes the length and
    /// mid-vertex checks.
    ///
    /// Three gates, in order, each cheaper than the next: a bounding-box
    /// prefilter; both endpoints within ``endpointToleranceMeters`` of the
    /// SAME chain; the chain's own measured span between those endpoints
    /// agreeing with the segment's own polyline length within 25% or 500 m
    /// (rejects a wrapping loop hop, whose endpoints land near opposite ends
    /// of the chain's measure range though they sit close together on the
    /// ground, and a RouteGraph chord that cuts a corner the chain does not
    /// run straight through); and every interior vertex staying within
    /// ``middleToleranceMeters`` of the chain (the other half of that same
    /// guard, for a hop whose two ends qualify but whose middle bows away).
    /// Chains are tried in the order given, and the first that passes every
    /// gate wins — a caller that cares about ties orders `chains`
    /// accordingly.
    public static func resolve(segment: [Coordinate], chains: [ChainRef]) -> StrokeRef? {
        guard segment.count >= 2 else { return nil }
        let first = segment[0]
        let last = segment[segment.count - 1]
        let segmentLength = polylineLength(segment)

        for chain in chains where chain.points.count >= 2 && chain.points.count == chain.measures.count {
            guard withinBounds(first: first, last: last, chain: chain) else { continue }
            guard let p1 = project(first, onto: chain.points, measures: chain.measures),
                p1.distance <= endpointToleranceMeters,
                let p2 = project(last, onto: chain.points, measures: chain.measures),
                p2.distance <= endpointToleranceMeters
            else { continue }

            let chainSpan = abs(p2.measure - p1.measure)
            guard abs(chainSpan - segmentLength) <= max(0.25 * segmentLength, 500) else { continue }

            guard middleFits(segment, chain: chain) else { continue }

            let (from, fromAnchor) = snap(p1, chain: chain)
            let (to, toAnchor) = snap(p2, chain: chain)
            return StrokeRef(
                chainID: chain.id, from: from, to: to, fromAnchor: fromAnchor, toAnchor: toAnchor)
        }
        return nil
    }

    // MARK: - projection

    private struct Projection {
        var distance: Double
        var measure: Double
        var point: Coordinate
    }

    /// The bounding-box prefilter. Padded generously and in plain degrees —
    /// this only ever has to be cheap and safe, never precise; the real
    /// distance test is ``project(_:onto:measures:)``.
    private static func withinBounds(first: Coordinate, last: Coordinate, chain: ChainRef) -> Bool {
        var minLat = chain.points[0].lat, maxLat = chain.points[0].lat
        var minLon = chain.points[0].lon, maxLon = chain.points[0].lon
        for point in chain.points {
            minLat = min(minLat, point.lat)
            maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon)
            maxLon = max(maxLon, point.lon)
        }
        minLat -= boundsPadDegrees; maxLat += boundsPadDegrees
        minLon -= boundsPadDegrees; maxLon += boundsPadDegrees
        func inside(_ point: Coordinate) -> Bool {
            point.lat >= minLat && point.lat <= maxLat
                && point.lon >= minLon && point.lon <= maxLon
        }
        return inside(first) && inside(last)
    }

    /// The closest point on `points` to `point`, its distance and its
    /// interpolated measure — perpendicular distance under a local
    /// equirectangular scaling, the same ruler ``ChainRef/measures`` and
    /// `rail-network.js`'s own `distanceMeters` use.
    private static func project(
        _ point: Coordinate, onto points: [Coordinate], measures: [Double],
        edges: Range<Int>? = nil
    ) -> Projection? {
        guard points.count >= 2 else { return nil }
        let sx = 111_320.0 * cos(point.lat * .pi / 180)
        let sy = 111_320.0
        let px = point.lon * sx, py = point.lat * sy
        var best: Projection?
        for index in edges ?? 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let ax = a.lon * sx, ay = a.lat * sy
            let bx = b.lon * sx, by = b.lat * sy
            let dx = bx - ax, dy = by - ay
            let length2 = dx * dx + dy * dy
            var t = length2 == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / length2
            t = min(1, max(0, t))
            let cx = ax + t * dx, cy = ay + t * dy
            let distance = hypot(px - cx, py - cy)
            if best == nil || distance < best!.distance {
                let measure = measures[index - 1] + t * (measures[index] - measures[index - 1])
                let closest = Coordinate(
                    lon: a.lon + t * (b.lon - a.lon), lat: a.lat + t * (b.lat - a.lat))
                best = Projection(distance: distance, measure: measure, point: closest)
            }
        }
        return best
    }

    /// Every interior vertex of `segment`, sampled up to
    /// ``maxMiddleSamples``, stays within ``middleToleranceMeters`` of
    /// `chain`.
    private static func middleFits(_ segment: [Coordinate], chain: ChainRef) -> Bool {
        guard segment.count > 2 else { return true }
        let interior = Array(segment[1..<(segment.count - 1)])
        let step = max(1, interior.count / maxMiddleSamples)
        var index = 0
        while index < interior.count {
            guard let projected = project(interior[index], onto: chain.points, measures: chain.measures),
                projected.distance <= middleToleranceMeters
            else { return false }
            index += step
        }
        return true
    }

    /// The segment's own polyline length, on the same equirectangular ruler
    /// ``project(_:onto:measures:)`` and ``ChainRef/measures`` use.
    private static func polylineLength(_ points: [Coordinate]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += planarDistance(points[index - 1], points[index])
        }
        return total
    }

    private static func planarDistance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat = ((a.lat + b.lat) / 2) * Double.pi / 180
        return hypot((b.lon - a.lon) * 111_320 * cos(lat), (b.lat - a.lat) * 111_320)
    }

    /// The endpoint's measure, snapped to the nearest platform anchor when
    /// one is close enough — see ``anchorSnapMeters``.
    private static func snap(_ projection: Projection, chain: ChainRef) -> (measure: Double, anchor: Int?) {
        var nearest: (index: Int, distance: Double)?
        for anchor in chain.anchors where chain.points.indices.contains(anchor) {
            let distance = planarDistance(projection.point, chain.points[anchor])
            if nearest == nil || distance < nearest!.distance {
                nearest = (anchor, distance)
            }
        }
        guard let nearest, nearest.distance <= anchorSnapMeters else {
            return (projection.measure, nil)
        }
        return (chain.measures[nearest.index], nearest.index)
    }
}
