import Foundation

/// Which rides a tap landed on.
///
/// A finger has no hover stage, so a tap over crossing lines is ambiguous in a
/// way a pointer's never is: the web app answers it by handing every train
/// under a coarse-pointer tap to `handleDeckRouteChoices` and asking. This is
/// the half of that decision that can be checked — given points already in
/// screen space, which rides are within the tap's reach, and in what order.
///
/// It lives here rather than in the map's coordinator because a decision made
/// inside a `UIViewRepresentable`'s delegate callbacks is a decision nothing
/// can run: `MKMapView.convert(_:toPointTo:)` needs a live map view, a window
/// and a layout pass. Splitting the projection from the arithmetic leaves the
/// arithmetic testable, which is where the off-by-one lives — the distance to a
/// SEGMENT is not the distance to its nearer endpoint, and a ride whose two
/// vertices straddle the tap is exactly the case a naïve version misses.
public enum RideTapResolver {

    /// A point in the map view's own coordinate space, in points.
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// One ride, already projected into screen space.
    public struct Candidate: Sendable {
        public var id: String
        /// One entry per drawn stroke; a stroke of fewer than two points can
        /// draw nothing and is ignored.
        public var strokes: [[Point]]

        public init(id: String, strokes: [[Point]]) {
            self.id = id
            self.strokes = strokes
        }
    }

    /// How near a tap has to fall, in points.
    ///
    /// 18 pt against the 44 pt of a button, because a railway line is a target
    /// the reader aims at with a visible mark under the finger rather than a
    /// control they hit blind — and because two parallel rides 20 pt apart are
    /// a normal sight on this map, where a 44 pt reach would make every tap
    /// ambiguous.
    public static let defaultTolerance: Double = 18

    /// Every ride within `tolerance` of the tap, nearest first.
    ///
    /// Duplicates are removed — a ride is one answer however many of its
    /// strokes are under the finger — and the order is the one the chooser
    /// shows, so the nearest ride is the first thing the reader reads.
    public static func hits(
        at point: Point, among candidates: [Candidate],
        tolerance: Double = defaultTolerance
    ) -> [String] {
        var scored: [(id: String, distance: Double)] = []
        for candidate in candidates {
            var best = Double.infinity
            for stroke in candidate.strokes where stroke.count >= 2 {
                var previous = stroke[0]
                for next in stroke.dropFirst() {
                    best = min(best, distance(from: point, to: previous, next))
                    previous = next
                }
            }
            if best <= tolerance { scored.append((candidate.id, best)) }
        }
        // Sorted by distance, and by id where two rides are equidistant —
        // which they are exactly when they share the metres under the finger,
        // the case this whole resolver exists for. Without the tiebreak the
        // chooser's order would depend on the order the rides happened to be
        // built in, and the same tap would list them differently twice.
        scored.sort { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
        var seen = Set<String>()
        return scored.compactMap { seen.insert($0.id).inserted ? $0.id : nil }
    }

    /// Distance from a point to a line SEGMENT — not to the infinite line, and
    /// not to the nearer endpoint.
    static func distance(from point: Point, to a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let denominator = dx * dx + dy * dy
        // A zero-length segment is a point: two identical vertices are common
        // where a stroke was cut at a station, and dividing by their length
        // would answer NaN, which compares false against every tolerance and
        // silently drops the ride.
        let ratio = denominator > 0
            ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / denominator, 0), 1)
            : 0
        return hypot(point.x - (a.x + ratio * dx), point.y - (a.y + ratio * dy))
    }
}

// MARK: - culling

/// The half of a tap that does not need every vertex projected.
///
/// ``RideTapResolver/hits(at:among:tolerance:)`` is exact and cheap per
/// vertex, and that was never the problem: the problem is that the caller has
/// to PROJECT every vertex of every ride before it can call, and a projection
/// is a `MKMapView.convert(_:toPointTo:)` per point. The national sample is
/// 180,447 ridden vertices, so every tap on the map — including the ones that
/// land on nothing — did 180,447 MapKit conversions and allocated 2,303 arrays
/// to hold the answers.
///
/// What is added here is the arithmetic that lets the caller skip almost all
/// of them: a stroke is cut into chunks, each chunk keeps the box its vertices
/// fall in, and a chunk whose box is further than the tolerance from the tap
/// cannot contain a hit and is never projected.
///
/// It is expressed over a planar space rather than over coordinates because
/// that is what makes it both testable and correct. The caller supplies the
/// tap and the boxes in ONE linear space — on iOS, `MKMapPoint`, where a
/// distance is the same number of units everywhere on an unpitched map — and
/// this decides. Nothing here knows about MapKit, and nothing here has to.
extension RideTapResolver {

    /// An axis-aligned box in the same planar space as ``Point``.
    public struct Bounds: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        /// The box a run of points falls in, or `nil` for an empty run.
        public init?(_ points: some Sequence<Point>) {
            var iterator = points.makeIterator()
            guard let first = iterator.next() else { return nil }
            var box = Bounds(
                minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
            while let point = iterator.next() {
                box.minX = Swift.min(box.minX, point.x)
                box.minY = Swift.min(box.minY, point.y)
                box.maxX = Swift.max(box.maxX, point.x)
                box.maxY = Swift.max(box.maxY, point.y)
            }
            self = box
        }

        /// The distance from `point` to the nearest part of the box, or zero
        /// when it is inside.
        ///
        /// This is what makes the cull *conservative rather than approximate*:
        /// every vertex of the chunk lies inside the box, so no point of the
        /// chunk — and therefore no point of any segment between two of its
        /// vertices, the box being convex — can be nearer to the tap than
        /// this. A chunk rejected here is a chunk that could not have won.
        public func distance(to point: Point) -> Double {
            let dx = Swift.max(minX - point.x, 0, point.x - maxX)
            let dy = Swift.max(minY - point.y, 0, point.y - maxY)
            if dx == 0 { return dy }
            if dy == 0 { return dx }
            return (dx * dx + dy * dy).squareRoot()
        }

        /// Whether a chunk in this box can hold a point within `tolerance`.
        public func mayContain(_ point: Point, within tolerance: Double) -> Bool {
            distance(to: point) <= tolerance
        }
    }

    /// How many segments a chunk covers.
    ///
    /// Chosen against the shape of the data rather than by taste: the national
    /// sample averages 78 vertices per stroke, and a chunk far larger than a
    /// stroke culls nothing extra while a chunk of a handful of vertices pays
    /// for a box per corner of a station approach. 64 leaves a long
    /// trans-Honshū section — 5,000 vertices in one stroke — split into
    /// eighty boxes, which is what stops one such section from defeating the
    /// whole cull.
    public static let defaultChunkSegments = 64

    /// The vertex ranges a stroke of `count` points is cut into.
    ///
    /// Consecutive ranges OVERLAP BY ONE VERTEX, and that is the whole
    /// correctness argument: a range `a..<b` covers the segments `a` through
    /// `b - 2`, so without the shared vertex the segment straddling a chunk
    /// boundary would belong to no chunk and a tap on it would silently miss.
    /// Every segment of the stroke lies in exactly one range, and a range
    /// carrying fewer than two vertices draws nothing and is dropped.
    public static func chunkRanges(
        count: Int, segmentsPerChunk: Int = defaultChunkSegments
    ) -> [Range<Int>] {
        guard count >= 2 else { return [] }
        let stride = Swift.max(1, segmentsPerChunk)
        guard count > stride + 1 else { return [0..<count] }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity((count - 1 + stride - 1) / stride)
        var start = 0
        while start < count - 1 {
            let end = Swift.min(count, start + stride + 1)
            ranges.append(start..<end)
            start += stride
        }
        return ranges
    }
}
