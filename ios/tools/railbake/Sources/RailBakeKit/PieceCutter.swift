import Foundation
import RailCore

/// Cuts one baked chain into the pieces a pack stores (spec section 2.5).
///
/// A chain's finished geometry is its whole built stroke plus metre windows over it (solid runs,
/// withheld dashes, landlord family runs, tenant fallback ink). The cutter lays those windows over
/// the stroke and partitions it:
///
///  1. at every change of drawing attributes: where a window of another kind takes over, with
///     withheld above landlord above tenant fallback above the chain's own solid run, and a gap
///     where nothing draws (kept so a trip still has geometry there);
///  2. so that no normal piece's bounding box exceeds ``maxExtent(mapPointsPerPoint:)`` on either
///     axis. Cuts fall on existing vertices; a segment longer than that gets collinear vertices
///     inserted first.
///
/// Neighbouring pieces share their boundary vertex bit for bit (every cut is one interpolation of
/// the one stroke), so the pieces of a chain rejoin to the stroke exactly. Dashed runs (withheld
/// spans, and every piece of a dated chain) are marked long and never cut.
public enum PieceCutter {

    /// Largest bounding-box side of a normal piece, in points: a tile, less four quanta so that
    /// quantising a vertex relative to its home tile centre cannot step past the Int16 half range.
    public static let maxExtentPoints = RailPackFormat.tilePoints - 4 / RailPackFormat.quantaPerPoint

    /// Largest bounding-box side of a normal piece, in map points.
    public static func maxExtent(mapPointsPerPoint: Double) -> Double {
        maxExtentPoints * mapPointsPerPoint
    }

    /// Metres closer than this are one boundary.
    public static let boundaryEpsilonMetres = 1e-6

    /// A polyline with the stroke ruler's measure of every vertex.
    public struct Polyline: Equatable, Sendable {
        public var points: [StrokePoint]
        public var measures: [Double]
        public init(points: [StrokePoint], measures: [Double]) {
            precondition(points.count == measures.count)
            self.points = points
            self.measures = measures
        }
    }

    /// What a piece draws as.
    public enum Kind: Hashable, Sendable {
        /// The chain's own solid ink.
        case base
        /// A withheld span: dashed, in this line's colour or a landlord family's tint.
        case withheld(colorHex: String, colorDarkHex: String)
        /// This chain drawing a shared family stroke in the family colour.
        case landlord(groupID: String, colorHex: String, colorDarkHex: String)
        /// This chain's own geometry inside a tenant window, drawn in the family colour only while
        /// no landlord covers it.
        case fallback(groupID: String, colorHex: String, colorDarkHex: String)
        /// Stroke no window draws; present for trips only.
        case gap
    }

    public struct Piece: Equatable, Sendable {
        public var kind: Kind
        /// Part (interval) index for a non-continuous line; 0 for a continuous chain.
        public var part: Int
        /// A dashed run: stored whole, with Int32 vertices, never cut.
        public var isLong: Bool
        public var line: Polyline
        public var from: Double { line.measures.first ?? 0 }
        public var to: Double { line.measures.last ?? 0 }
    }

    /// Cuts `chain` (baked at `mapPointsPerPoint`). `dated(part)` says a part (0 for a continuous
    /// chain) is stamped with a date span: the device decides solid or dashed by the era, so none
    /// of its own ink may be cut.
    public static func cut(
        _ chain: NetworkStrokeBake.Chain, mapPointsPerPoint: Double, dated: (Int) -> Bool
    ) -> [Piece] {
        let extent = maxExtent(mapPointsPerPoint: mapPointsPerPoint)
        guard chain.continuous, chain.strokePoints.count >= 2,
              chain.strokePoints.count == chain.strokeMeasures.count else {
            // No whole stroke (a non-continuous line): its runs are the geometry, one piece each,
            // measured on their part's own ruler (`Run.measures`).
            var pieces: [Piece] = []
            for run in chain.runs where run.vertices.count >= 2 {
                let measures = run.measures.count == run.vertices.count
                    ? run.measures : [Double](repeating: 0, count: run.vertices.count)
                let line = Polyline(points: run.vertices, measures: measures)
                pieces.append(contentsOf: finish(line, kind: .base, part: run.part, long: dated(run.part), extent: extent))
            }
            return pieces
        }
        let stroke = Polyline(points: chain.strokePoints, measures: chain.strokeMeasures)
        var pieces: [Piece] = []
        for span in partition(chain) {
            let line = slice(stroke, from: span.from, to: span.to)
            guard line.points.count >= 2 else { continue }
            let long: Bool
            switch span.kind {
            case .withheld: long = true
            case .base: long = dated(0)
            default: long = false
            }
            pieces.append(contentsOf: finish(line, kind: span.kind, part: 0, long: long, extent: extent))
        }
        return pieces
    }

    private static func finish(_ line: Polyline, kind: Kind, part: Int, long: Bool, extent: Double) -> [Piece] {
        if long { return [Piece(kind: kind, part: part, isLong: true, line: line)] }
        return cutByExtent(line, maxExtent: extent).map { Piece(kind: kind, part: part, isLong: false, line: $0) }
    }

    // MARK: Attribute partition

    struct Span: Equatable {
        var from: Double
        var to: Double
        var kind: Kind
    }

    /// The stroke's metre range split where the drawing kind changes, in ascending order, covering
    /// the whole stroke.
    static func partition(_ chain: NetworkStrokeBake.Chain) -> [Span] {
        let low = chain.strokeMeasures.first ?? 0, high = chain.strokeMeasures.last ?? 0
        // Highest priority first.
        var windows: [Span] = []
        for run in chain.withheld {
            windows.append(Span(from: run.from, to: run.to, kind: .withheld(colorHex: run.colorHex, colorDarkHex: run.colorDarkHex)))
        }
        for run in chain.landlord {
            windows.append(Span(from: run.from, to: run.to, kind: .landlord(
                groupID: run.groupID ?? "", colorHex: run.colorHex, colorDarkHex: run.colorDarkHex)))
        }
        for run in chain.tenantFallback {
            windows.append(Span(from: run.from, to: run.to, kind: .fallback(
                groupID: run.groupID ?? "", colorHex: run.colorHex, colorDarkHex: run.colorDarkHex)))
        }
        for run in chain.runs { windows.append(Span(from: run.from, to: run.to, kind: .base)) }

        var cuts: [Double] = [low, high]
        for window in windows {
            cuts.append(min(max(window.from, low), high))
            cuts.append(min(max(window.to, low), high))
        }
        cuts.sort()
        var boundaries: [Double] = []
        for cut in cuts where boundaries.last.map({ cut - $0 > boundaryEpsilonMetres }) ?? true {
            boundaries.append(cut)
        }
        func rank(_ kind: Kind) -> Int {
            switch kind {
            case .withheld: 0
            case .landlord: 1
            case .fallback: 2
            case .base: 3
            case .gap: 4
            }
        }
        var spans: [Span] = []
        for index in 0..<max(0, boundaries.count - 1) {
            let from = boundaries[index], to = boundaries[index + 1]
            let middle = (from + to) / 2
            var best: Kind = .gap
            for window in windows where window.from <= middle && middle <= window.to && rank(window.kind) < rank(best) {
                best = window.kind
            }
            if let last = spans.last, last.kind == best {
                spans[spans.count - 1].to = to
            } else {
                spans.append(Span(from: from, to: to, kind: best))
            }
        }
        return spans
    }

    // MARK: Slicing

    /// The stroke between two measures: the interpolated start, every vertex strictly between, the
    /// interpolated end. Equal measures on both sides of a boundary give the same bits, so
    /// neighbouring slices share their boundary vertex exactly.
    public static func slice(_ stroke: Polyline, from: Double, to: Double) -> Polyline {
        guard stroke.points.count >= 2, let low = stroke.measures.first, let high = stroke.measures.last else {
            return Polyline(points: [], measures: [])
        }
        let a = min(max(from, low), high), b = min(max(to, low), high)
        guard b > a else { return Polyline(points: [], measures: []) }
        var points = [point(on: stroke, at: a)]
        var measures = [a]
        // First vertex with measure strictly above a.
        var lo = 0, hi = stroke.measures.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if stroke.measures[mid] > a { hi = mid } else { lo = mid + 1 }
        }
        var index = lo
        while index < stroke.points.count, stroke.measures[index] < b {
            if stroke.points[index] != points[points.count - 1] || stroke.measures[index] != measures[measures.count - 1] {
                points.append(stroke.points[index])
                measures.append(stroke.measures[index])
            }
            index += 1
        }
        let end = point(on: stroke, at: b)
        if end != points[points.count - 1] || b != measures[measures.count - 1] {
            points.append(end)
            measures.append(b)
        }
        return Polyline(points: points, measures: measures)
    }

    /// The position at a measure on the stroke.
    public static func point(on stroke: Polyline, at measure: Double) -> StrokePoint {
        let count = stroke.points.count
        if measure <= stroke.measures[0] { return stroke.points[0] }
        if measure >= stroke.measures[count - 1] { return stroke.points[count - 1] }
        var lo = 0, hi = count - 1  // measures[lo] <= measure < measures[hi]
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if stroke.measures[mid] <= measure { lo = mid } else { hi = mid }
        }
        let a = stroke.measures[lo], b = stroke.measures[hi]
        if measure == a || b <= a { return stroke.points[lo] }
        let t = (measure - a) / (b - a)
        let p = stroke.points[lo], q = stroke.points[hi]
        return StrokePoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)
    }

    // MARK: Extent cut

    /// Splits a polyline into pieces whose bounding box is at most `maxExtent` on each axis. Pieces
    /// share their boundary vertex; a segment longer than `maxExtent` is first divided by collinear
    /// vertices (their measures interpolated).
    public static func cutByExtent(_ line: Polyline, maxExtent: Double) -> [Polyline] {
        guard line.points.count >= 2 else { return [] }
        let dense = densify(line, maxExtent: maxExtent)
        var result: [Polyline] = []
        var points = [dense.points[0]], measures = [dense.measures[0]]
        var minX = points[0].x, maxX = minX, minY = points[0].y, maxY = minY
        var index = 1
        while index < dense.points.count {
            let p = dense.points[index]
            let nMinX = min(minX, p.x), nMaxX = max(maxX, p.x), nMinY = min(minY, p.y), nMaxY = max(maxY, p.y)
            if nMaxX - nMinX <= maxExtent, nMaxY - nMinY <= maxExtent {
                points.append(p)
                measures.append(dense.measures[index])
                (minX, maxX, minY, maxY) = (nMinX, nMaxX, nMinY, nMaxY)
                index += 1
            } else {
                // `points` holds at least one segment here: every densified segment fits alone.
                result.append(Polyline(points: points, measures: measures))
                let last = points[points.count - 1], lastMeasure = measures[measures.count - 1]
                points = [last]
                measures = [lastMeasure]
                (minX, maxX, minY, maxY) = (last.x, last.x, last.y, last.y)
            }
        }
        if points.count >= 2 { result.append(Polyline(points: points, measures: measures)) }
        return result
    }

    static func densify(_ line: Polyline, maxExtent: Double) -> Polyline {
        var points = [line.points[0]], measures = [line.measures[0]]
        for index in 1..<line.points.count {
            let p = line.points[index - 1], q = line.points[index]
            let longest = max(abs(q.x - p.x), abs(q.y - p.y))
            if longest > maxExtent {
                let parts = Int((longest / maxExtent).rounded(.up))
                let m0 = line.measures[index - 1], m1 = line.measures[index]
                for k in 1..<parts {
                    let t = Double(k) / Double(parts)
                    points.append(StrokePoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
                    measures.append(m0 + (m1 - m0) * t)
                }
            }
            points.append(q)
            measures.append(line.measures[index])
        }
        return Polyline(points: points, measures: measures)
    }

    // MARK: Station nodes

    /// Where a node landed: the piece and the vertex of that piece.
    public struct Slot: Equatable, Sendable {
        public var piece: Int
        public var vertex: Int
    }

    /// Makes sure every node has a vertex: reuses a vertex of the piece holding its measure when one
    /// lies within `quantum`, otherwise inserts the node's position into the nearest segment of that
    /// piece (a collinear insertion, which cannot grow the piece's box). The first piece whose range
    /// holds the measure wins, so a node on a shared boundary sits at the end of the earlier piece.
    ///
    /// - Parameter nodes: `(id, measure)` on the stroke ruler.
    public static func place(
        nodes: [(id: Int, measure: Double)], stroke: Polyline, pieces: inout [Piece], quantum: Double
    ) -> [Int: Slot] {
        struct Insertion { var id: Int; var segment: Int; var t: Double; var point: StrokePoint; var measure: Double }
        var reuse: [Int: [(id: Int, vertex: Int)]] = [:]
        var insertions: [Int: [Insertion]] = [:]
        for node in nodes.sorted(by: { ($0.measure, $0.id) < ($1.measure, $1.id) }) {
            guard !pieces.isEmpty else { break }
            let m = node.measure
            let owner = pieces.firstIndex { $0.from - boundaryEpsilonMetres <= m && m <= $0.to + boundaryEpsilonMetres }
                ?? (m < pieces[0].from ? 0 : pieces.count - 1)
            let target = point(on: stroke, at: m)
            let vertices = pieces[owner].line.points
            var nearest = 0, nearestDistance = Double.infinity
            for (index, v) in vertices.enumerated() {
                let d = hypot(v.x - target.x, v.y - target.y)
                if d < nearestDistance { nearest = index; nearestDistance = d }
            }
            if nearestDistance <= quantum {
                reuse[owner, default: []].append((node.id, nearest))
                continue
            }
            var bestSegment = 0, bestT = 0.0, bestDistance = Double.infinity
            for k in 0..<(vertices.count - 1) {
                let p = vertices[k], q = vertices[k + 1]
                let dx = q.x - p.x, dy = q.y - p.y
                let lengthSquared = dx * dx + dy * dy
                let t = lengthSquared > 0 ? min(max(((target.x - p.x) * dx + (target.y - p.y) * dy) / lengthSquared, 0), 1) : 0
                let d = hypot(p.x + dx * t - target.x, p.y + dy * t - target.y)
                if d < bestDistance { bestSegment = k; bestT = t; bestDistance = d }
            }
            let measures = pieces[owner].line.measures
            let p = vertices[bestSegment], q = vertices[bestSegment + 1]
            let onSegment = StrokePoint(x: p.x + (q.x - p.x) * bestT, y: p.y + (q.y - p.y) * bestT)
            insertions[owner, default: []].append(Insertion(
                id: node.id, segment: bestSegment, t: bestT, point: onSegment,
                measure: measures[bestSegment] + (measures[bestSegment + 1] - measures[bestSegment]) * bestT))
        }
        var slots: [Int: Slot] = [:]
        for owner in Set(reuse.keys).union(insertions.keys).sorted() {
            let original = pieces[owner].line
            let ordered = (insertions[owner] ?? []).sorted { ($0.segment, $0.t, $0.id) < ($1.segment, $1.t, $1.id) }
            // Collapse insertions within a quantum of the previous one on the same segment.
            var unique: [Insertion] = []
            var ownerOf: [Int: Int] = [:]  // node id -> index in `unique`
            for insertion in ordered {
                if let last = unique.last, last.segment == insertion.segment,
                   hypot(last.point.x - insertion.point.x, last.point.y - insertion.point.y) <= quantum {
                    ownerOf[insertion.id] = unique.count - 1
                } else {
                    ownerOf[insertion.id] = unique.count
                    unique.append(insertion)
                }
            }
            var points: [StrokePoint] = [], measures: [Double] = []
            var newIndexOfOriginal = [Int](repeating: 0, count: original.points.count)
            var newIndexOfInsertion = [Int](repeating: 0, count: unique.count)
            var cursor = 0
            for index in original.points.indices {
                newIndexOfOriginal[index] = points.count
                points.append(original.points[index])
                measures.append(original.measures[index])
                while cursor < unique.count, unique[cursor].segment == index {
                    newIndexOfInsertion[cursor] = points.count
                    points.append(unique[cursor].point)
                    measures.append(unique[cursor].measure)
                    cursor += 1
                }
            }
            pieces[owner].line = Polyline(points: points, measures: measures)
            for entry in reuse[owner] ?? [] { slots[entry.id] = Slot(piece: owner, vertex: newIndexOfOriginal[entry.vertex]) }
            for (id, index) in ownerOf { slots[id] = Slot(piece: owner, vertex: newIndexOfInsertion[index]) }
        }
        return slots
    }
}
