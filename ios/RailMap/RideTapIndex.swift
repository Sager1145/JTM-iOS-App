import Foundation
import MapKit
import RailCore
import RailPresentation

/// Which parts of which rides a tap could possibly have landed on.
///
/// ## What this replaces
///
/// `handleMapTap` projected **every vertex of every ride** into screen space
/// and handed the lot to ``RideTapResolver``. On the national sample that is
/// 180,447 `MKMapView.convert(_:toPointTo:)` calls and 2,303 freshly allocated
/// point arrays — for every tap, including the ones that land on empty sea and
/// the ones whose only job is to clear the selection. The cost is a function
/// of how much the reader has ridden, not of what is under their finger, which
/// is the wrong shape for a gesture.
///
/// Measured over the same geometry with the projection modelled as plain
/// arithmetic (`ios/tools/bench`, release, Apple silicon):
///
/// | | projections per tap | 9 taps |
/// | --- | ---: | ---: |
/// | project everything | 180,447 | 17.5 ms |
/// | cull, then project | ≤ 674 | 0.084 ms |
///
/// The real conversions are dearer than the modelled ones — MapKit's crosses
/// into VectorKit and takes the map view's own lock — so the ratio understates
/// the device. The *count* carries over exactly.
///
/// ## Why the answer cannot change
///
/// The cull is conservative, not approximate, and that rests on two facts.
///
/// A chunk's box contains every vertex of the chunk, and a box is convex, so
/// no point of any segment between two of those vertices can be nearer to the
/// tap than the box is. A chunk the box rejects therefore could not have
/// produced a hit. And because `RideTapResolver.hits` scores a ride by the
/// **minimum** distance over its segments, dropping only segments that are
/// further away than the tolerance leaves that minimum unchanged whenever it
/// is within the tolerance — which is the only case where it is read.
///
/// The second fact is about the space the boxes are measured in. On an
/// unpitched map, `MKMapPoint` → view point is a similarity: one rotation, one
/// uniform scale, one translation. A distance in map points is therefore a
/// fixed multiple of the same distance in view points *everywhere on screen*,
/// so a tolerance converted once is exact for the whole view. A pitched camera
/// breaks that — the scale varies up the screen — so a pitched map does not
/// take this path at all and projects everything, as before. Pitch arrives
/// only from a deliberate two-finger drag, and correctness is not worth
/// trading for the frames it would save there.
struct RideTapIndex {

    /// One run of a stroke, with the box its vertices fall in.
    private struct Chunk {
        let ride: Int
        let stroke: Int
        let range: Range<Int>
        /// In `MKMapPoint` space. Independent of the camera, so the index
        /// survives every pan and zoom and is rebuilt only when the rides are.
        let bounds: RideTapResolver.Bounds
    }

    /// Every stroke, in the order `DrawnRide.strokes` produces them, so that
    /// what is projected here is what the previous implementation projected.
    private let strokes: [[[Coordinate]]]
    private let ids: [String]
    private let chunks: [Chunk]

    /// How many vertices the index holds, for the signpost that reports what a
    /// tap avoided.
    let vertexCount: Int

    init(rides: [RiddenRouteStore.DrawnRide]) {
        var strokes: [[[Coordinate]]] = []
        var ids: [String] = []
        var chunks: [Chunk] = []
        var vertices = 0
        strokes.reserveCapacity(rides.count)
        ids.reserveCapacity(rides.count)
        for (rideIndex, ride) in rides.enumerated() {
            // `strokes` is a computed property that rebuilds its outer array
            // on every read; read it once here and never again per tap.
            let rideStrokes = ride.strokes
            for (strokeIndex, stroke) in rideStrokes.enumerated() {
                vertices += stroke.count
                for range in RideTapResolver.chunkRanges(count: stroke.count) {
                    guard let bounds = Self.bounds(of: stroke, in: range) else { continue }
                    chunks.append(Chunk(
                        ride: rideIndex, stroke: strokeIndex,
                        range: range, bounds: bounds))
                }
            }
            strokes.append(rideStrokes)
            ids.append(ride.id)
        }
        self.strokes = strokes
        self.ids = ids
        self.chunks = chunks
        vertexCount = vertices
    }

    /// The box a run of coordinates falls in, in `MKMapPoint` space.
    ///
    /// Computed from the run's longitude and latitude extremes rather than by
    /// projecting every vertex, which it is allowed to do because the
    /// projection is monotone on each axis independently — `x` rises with
    /// longitude and `y` falls as latitude rises — so the corners of the
    /// lon/lat box are the corners of the map-point box. That takes the index
    /// build from one Mercator per vertex to two per chunk.
    ///
    /// A run spanning more than half the world in longitude would wrap, and
    /// the two corners would no longer bracket it. Nothing in these five
    /// packages does, and the answer if something ever did is to decline to
    /// cull it rather than to cull it wrongly — hence `nil`, which the caller
    /// reads as "this chunk is always a candidate" by simply not recording a
    /// box for it… except that a chunk with no box would then be invisible.
    /// So the wrap case returns an unbounded box instead, which every tap
    /// matches and which therefore falls back to projecting it.
    private static func bounds(
        of stroke: [Coordinate], in range: Range<Int>
    ) -> RideTapResolver.Bounds? {
        guard range.count >= 2 else { return nil }
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        for index in range {
            let coordinate = stroke[index]
            minLon = Swift.min(minLon, coordinate.lon)
            maxLon = Swift.max(maxLon, coordinate.lon)
            minLat = Swift.min(minLat, coordinate.lat)
            maxLat = Swift.max(maxLat, coordinate.lat)
        }
        guard minLon.isFinite, maxLon.isFinite, minLat.isFinite, maxLat.isFinite else {
            return .unbounded
        }
        guard maxLon - minLon < 180 else { return .unbounded }
        let topLeft = MKMapPoint(
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let bottomRight = MKMapPoint(
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        return RideTapResolver.Bounds(
            minX: Swift.min(topLeft.x, bottomRight.x),
            minY: Swift.min(topLeft.y, bottomRight.y),
            maxX: Swift.max(topLeft.x, bottomRight.x),
            maxY: Swift.max(topLeft.y, bottomRight.y))
    }

    /// Every ride the tap could have landed on, carrying only the runs of
    /// geometry that could have carried it.
    ///
    /// `nil` means the cull declined to answer — a pitched camera, or a
    /// projection whose scale could not be measured — and the caller must
    /// project everything, which is what ``allCandidates(projecting:)`` is
    /// for. Declining is the safe answer and it is why this returns an
    /// optional rather than an empty array.
    @MainActor
    func candidates(
        at point: CGPoint, on mapView: MKMapView,
        tolerance: Double = RideTapResolver.defaultTolerance
    ) -> [RideTapResolver.Candidate]? {
        guard let scale = Self.mapPointsPerViewPoint(on: mapView) else { return nil }
        let tapMap = MKMapPoint(mapView.convert(point, toCoordinateFrom: mapView))
        let tap = RideTapResolver.Point(x: tapMap.x, y: tapMap.y)
        // A hair of slack over the exact conversion. The scale is measured
        // through two `convert` round trips and the boxes through a second
        // Mercator, so the two disagree in the last bits; a tolerance that is
        // a fraction of a point too generous costs one more chunk to project,
        // and one that is a fraction too tight is a tap that misses a line the
        // reader can see under their finger.
        let reach = tolerance * scale * 1.001 + 1

        var strokesByRide: [Int: [[RideTapResolver.Point]]] = [:]
        for chunk in chunks where chunk.bounds.mayContain(tap, within: reach) {
            let stroke = strokes[chunk.ride][chunk.stroke]
            var projected: [RideTapResolver.Point] = []
            projected.reserveCapacity(chunk.range.count)
            for index in chunk.range {
                let screen = mapView.convert(
                    stroke[index].clLocation, toPointTo: mapView)
                projected.append(
                    RideTapResolver.Point(x: screen.x, y: screen.y))
            }
            strokesByRide[chunk.ride, default: []].append(projected)
        }
        return strokesByRide.map { ride, strokes in
            RideTapResolver.Candidate(id: ids[ride], strokes: strokes)
        }
    }

    /// The whole geometry, projected — the path a pitched camera takes.
    @MainActor
    func allCandidates(on mapView: MKMapView) -> [RideTapResolver.Candidate] {
        strokes.enumerated().map { rideIndex, rideStrokes in
            RideTapResolver.Candidate(
                id: ids[rideIndex],
                strokes: rideStrokes.map { stroke in
                    stroke.map { coordinate in
                        let screen = mapView.convert(
                            coordinate.clLocation, toPointTo: mapView)
                        return RideTapResolver.Point(x: screen.x, y: screen.y)
                    }
                })
        }
    }

    /// How many `MKMapPoint` units one view point is, or `nil` when the
    /// question has no single answer.
    ///
    /// Measured rather than derived from `visibleMapRect / bounds`, because
    /// that ratio is wrong the moment the map has a heading: `visibleMapRect`
    /// is then the bounding box of a rotated rectangle and is larger than the
    /// span the view actually covers. Two points a hundred apart on the same
    /// screen row answer it under rotation as well as without.
    ///
    /// `nil` for a pitched camera, where there is no single answer at all —
    /// the scale grows towards the horizon — and for a degenerate measurement,
    /// which is what a view that has not been laid out yet gives.
    @MainActor
    private static func mapPointsPerViewPoint(on mapView: MKMapView) -> Double? {
        guard mapView.camera.pitch == 0, mapView.bounds.width > 1 else { return nil }
        // A view straddling the antimeridian has no single `x` for a place:
        // MapKit reports such a rect as running past the world's width, and
        // the same metre of railway is then either side of the seam depending
        // on which way the reader panned. Boxes and taps compared across it
        // would be a whole world apart in a space where they are adjacent, and
        // the cull would drop a line under the finger. Nothing in these five
        // packages is within a screen of 180°, so this is a guard against a
        // case that cannot arise rather than one that is expected — and the
        // answer to a case that cannot arise is to decline, not to guess.
        let visible = mapView.visibleMapRect
        guard visible.minX >= 0, visible.maxX <= MKMapSize.world.width else { return nil }
        let origin = mapView.convert(.zero, toCoordinateFrom: mapView)
        let span = min(100, Double(mapView.bounds.width))
        let across = mapView.convert(
            CGPoint(x: span, y: 0), toCoordinateFrom: mapView)
        guard CLLocationCoordinate2DIsValid(origin),
              CLLocationCoordinate2DIsValid(across) else { return nil }
        let a = MKMapPoint(origin)
        let b = MKMapPoint(across)
        let distance = (pow(b.x - a.x, 2) + pow(b.y - a.y, 2)).squareRoot()
        let scale = distance / span
        guard scale.isFinite, scale > 0 else { return nil }
        return scale
    }
}

extension RideTapResolver.Bounds {
    /// A box every tap matches, for geometry the cull declines to reason about.
    static let unbounded = RideTapResolver.Bounds(
        minX: -.infinity, minY: -.infinity, maxX: .infinity, maxY: .infinity)
}
