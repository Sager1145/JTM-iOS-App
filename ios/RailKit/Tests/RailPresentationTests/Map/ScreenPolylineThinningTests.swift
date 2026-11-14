import Foundation
import RailPresentation
import Testing

struct ScreenPolylineThinningTests {
    private func thin(_ points: [(Double, Double)], step: Double = 0.5) -> [(Double, Double)] {
        ScreenPolylineThinning.thinned(
            points.map { [$0.0, $0.1] }, x: points.map(\.0), y: points.map(\.1), stepPx: step
        ).map { ($0[0], $0[1]) }
    }

    private func distance(_ p: (Double, Double), toSegment a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let length2 = dx * dx + dy * dy
        let t = length2 == 0 ? 0 : max(0, min(1, ((p.0 - a.0) * dx + (p.1 - a.1) * dy) / length2))
        return hypot(p.0 - (a.0 + t * dx), p.1 - (a.1 + t * dy))
    }

    /// Largest distance from any original vertex to the thinned polyline.
    private func maxDeviation(original: [(Double, Double)], thinned: [(Double, Double)]) -> Double {
        original.map { p in
            (1..<thinned.count).map { distance(p, toSegment: thinned[$0 - 1], thinned[$0]) }.min() ?? 0
        }.max() ?? 0
    }

    private var circle: [(Double, Double)] {
        (0...2_000).map { i in
            let a = Double(i) / 2_000 * 2 * .pi
            return (40 * cos(a), 40 * sin(a))
        }
    }

    private var zigZag: [(Double, Double)] {
        (0..<400).map { i in (Double(i) * 0.1, i % 2 == 0 ? 0 : 0.3) }
    }

    @Test func endpointsAreKept() {
        for polyline in [circle, zigZag, [(0, 0), (0.01, 0), (0.02, 0)], [(0, 0), (0.1, 0)]] {
            let result = thin(polyline)
            #expect(result.first! == polyline.first! && result.last! == polyline.last!)
        }
        #expect(ScreenPolylineThinning.keptIndices(x: [], y: []).isEmpty)
        #expect(ScreenPolylineThinning.keptIndices(x: [1], y: [2]) == [0])
    }

    @Test func deviationStaysWithinHalfPixel() {
        for polyline in [circle, zigZag] {
            let result = thin(polyline)
            #expect(result.count < polyline.count)
            #expect(maxDeviation(original: polyline, thinned: result) <= 0.5 + 1e-9)
        }
    }

    @Test func tinyStepsAroundACurveKeepAVertexPerHalfPixelOfTravel() {
        let result = thin(circle)
        for index in 1..<(result.count - 1) {
            let step = hypot(result[index].0 - result[index - 1].0, result[index].1 - result[index - 1].1)
            #expect(step >= 0.5)
        }
        // 2 * pi * 40 = 251 px of circumference: about 500 vertices, not 2,001.
        #expect(result.count > 400 && result.count < 520)
    }

    @Test func isIdempotent() {
        for polyline in [circle, zigZag] {
            let once = thin(polyline)
            let twice = thin(once)
            #expect(once.count == twice.count)
            #expect(zip(once, twice).allSatisfy { $0 == $1 })
        }
    }

    @Test func straightRunOfTinyStepsCollapses() {
        let run = (0...1_000).map { (Double($0) * 0.01, 0.0) }  // 10 px long
        let result = thin(run)
        #expect(result.count <= 22)
        #expect(result.first! == run.first! && result.last! == run.last!)
        #expect(maxDeviation(original: run, thinned: result) <= 0.5 + 1e-9)
    }

    @Test func piecesKeepTheirOwnEnds() {
        // Each dash-pattern run, chunk and family window is thinned as its own
        // piece, so every piece boundary survives.
        let pieces = (0..<5).map { piece in
            (0...50).map { (Double(piece) * 100 + Double($0) * 0.02, 0.0) }
        }
        for piece in pieces {
            let result = thin(piece)
            #expect(result.first! == piece.first! && result.last! == piece.last!)
        }
    }

    @Test func networkBuildThinsBeforeFitToBudget() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let source = try String(
            contentsOf: root.appendingPathComponent("ios/RailMap/Map/MapLineGeometry.swift"), encoding: .utf8)
        // The network build thins every drawn polyline (solid, historical and
        // family windows) before any chunk reaches a MapKit vertex count.
        #expect(source.contains("ScreenPolylineThinning.thinned"))
        let prepare = try #require(source.range(of: "static func prepare("))
        let body = String(source[prepare.lowerBound...])
        let lane = try #require(body.range(of: "parallelLaneCoordinates("))
        // Thinning is the argument of the chunking call: it runs after the lane
        // offset and rounding and before any chunk becomes a counted polyline.
        let flat = body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(flat.contains("mapCoordinateChunks( thinnedForNetwork(points,"))
        #expect(lane.lowerBound < (try #require(body.range(of: "thinnedForNetwork(points"))).lowerBound)
        let coordinator = try String(
            contentsOf: root.appendingPathComponent("ios/RailMap/Map/RailMapCoordinator.swift"), encoding: .utf8)
        #expect(coordinator.contains("NetworkLOD.fitToBudget"))
        let lod = try String(
            contentsOf: root.appendingPathComponent("ios/RailMap/Map/NetworkLOD.swift"), encoding: .utf8)
        #expect(lod.contains("static let vertexBudget = 64_000"))
    }
}
