import Foundation
import RailCore
import Testing
@testable import RailBakeKit

/// The piece cutter on plain polylines: rejoin, extent, shared boundaries, nodes.
@Suite("PieceCutter")
struct PieceCutterTests {

    /// A reproducible zigzag with a few segments far longer than `extent`.
    static func polyline(extent: Double, seed: UInt64 = 7) -> PieceCutter.Polyline {
        var state = seed
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        var points = [StrokePoint(x: 1000, y: -500)]
        var measures = [0.0]
        for index in 1..<400 {
            let scale = index % 37 == 0 ? extent * 3.4 : extent * 0.18
            let p = points[index - 1]
            let q = StrokePoint(x: p.x + (next() - 0.35) * scale, y: p.y + (next() - 0.5) * scale)
            points.append(q)
            measures.append(measures[index - 1] + hypot(q.x - p.x, q.y - p.y))
        }
        return PieceCutter.Polyline(points: points, measures: measures)
    }

    static func box(_ line: PieceCutter.Polyline) -> (w: Double, h: Double) {
        let xs = line.points.map(\.x), ys = line.points.map(\.y)
        return (xs.max()! - xs.min()!, ys.max()! - ys.min()!)
    }

    @Test("pieces are at most the extent on each axis and share their boundary vertex")
    func extentAndBoundaries() {
        let extent = 100.0
        let line = Self.polyline(extent: extent)
        let pieces = PieceCutter.cutByExtent(line, maxExtent: extent)
        #expect(pieces.count > 10)
        for piece in pieces {
            let b = Self.box(piece)
            #expect(b.w <= extent && b.h <= extent)
            #expect(piece.points.count >= 2)
        }
        for (a, b) in zip(pieces, pieces.dropFirst()) {
            #expect(a.points.last == b.points.first, "adjacent pieces share the boundary vertex bit for bit")
            #expect(a.measures.last == b.measures.first)
        }
    }

    @Test("pieces rejoin to the original polyline: every original vertex kept, extra vertices collinear")
    func rejoin() {
        let extent = 100.0
        let line = Self.polyline(extent: extent)
        let pieces = PieceCutter.cutByExtent(line, maxExtent: extent)
        var joined: [StrokePoint] = []
        for piece in pieces { joined.append(contentsOf: joined.isEmpty ? piece.points : Array(piece.points.dropFirst())) }
        // Original vertices appear in order, untouched.
        var cursor = 0
        for original in line.points {
            while cursor < joined.count, joined[cursor] != original { cursor += 1 }
            #expect(cursor < joined.count, "original vertex missing from the rejoined polyline")
            if cursor >= joined.count { return }
        }
        #expect(joined.first == line.points.first && joined.last == line.points.last)
        // Inserted vertices lie on the polyline, and its length is unchanged.
        func length(_ points: [StrokePoint]) -> Double {
            var total = 0.0
            for (a, b) in zip(points, points.dropFirst()) { total += hypot(b.x - a.x, b.y - a.y) }
            return total
        }
        #expect(abs(length(joined) - length(line.points)) < 1e-6 * length(line.points))
        for p in joined {
            var nearest = Double.infinity
            for (s, e) in zip(line.points, line.points.dropFirst()) {
                let dx = e.x - s.x, dy = e.y - s.y
                let l2 = dx * dx + dy * dy
                let t = l2 > 0 ? min(max(((p.x - s.x) * dx + (p.y - s.y) * dy) / l2, 0), 1) : 0
                nearest = min(nearest, hypot(s.x + dx * t - p.x, s.y + dy * t - p.y))
            }
            #expect(nearest < 1e-6)
        }
    }

    @Test("a single segment longer than the extent is divided by inserted vertices")
    func longSegment() {
        let line = PieceCutter.Polyline(
            points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 1000, y: 10)], measures: [0, 1000.05])
        let pieces = PieceCutter.cutByExtent(line, maxExtent: 100)
        #expect(pieces.count == 10)
        #expect(pieces.first?.points.first == line.points.first)
        #expect(pieces.last?.points.last == line.points.last)
        for piece in pieces { #expect(Self.box(piece).w <= 100) }
    }

    @Test("slices of one stroke share their boundary exactly and cover it")
    func slicing() {
        let line = Self.polyline(extent: 100)
        let total = line.measures.last!
        let cuts = [0, total * 0.21, total * 0.5, total * 0.5000001, total * 0.9, total]
        let slices = zip(cuts, cuts.dropFirst()).map { PieceCutter.slice(line, from: $0, to: $1) }
        for (a, b) in zip(slices, slices.dropFirst()) {
            #expect(a.points.last == b.points.first)
        }
        #expect(slices.first?.points.first == line.points.first)
        #expect(slices.last?.points.last == line.points.last)
        let count = slices.reduce(0) { $0 + $1.points.count - 1 } + 1
        // Every original vertex is in exactly one slice (plus one interpolated vertex per cut).
        #expect(count == line.points.count + cuts.count - 2)
    }

    @Test("a node reuses a vertex within a quantum or is inserted on the segment")
    func nodes() {
        let line = PieceCutter.Polyline(
            points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0), StrokePoint(x: 100, y: 100)],
            measures: [0, 100, 200])
        var pieces = PieceCutter.cutByExtent(line, maxExtent: 60).map {
            PieceCutter.Piece(kind: .base, part: 0, isLong: false, line: $0)
        }
        let before = pieces.reduce(0) { $0 + $1.line.points.count }
        let slots = PieceCutter.place(
            nodes: [(id: 1, measure: 100), (id: 2, measure: 130), (id: 3, measure: 130.001), (id: 4, measure: 0)],
            stroke: line, pieces: &pieces, quantum: 0.01)
        #expect(slots.count == 4)
        func position(_ id: Int) -> StrokePoint {
            let slot = slots[id]!
            return pieces[slot.piece].line.points[slot.vertex]
        }
        #expect(position(1) == StrokePoint(x: 100, y: 0))
        #expect(position(2) == StrokePoint(x: 100, y: 30))
        #expect(slots[2] == slots[3], "two nodes within a quantum share their vertex")
        #expect(position(4) == StrokePoint(x: 0, y: 0))
        #expect(pieces.reduce(0) { $0 + $1.line.points.count } == before + 1)
        for piece in pieces { #expect(piece.line.points.count == piece.line.measures.count) }
    }
}
