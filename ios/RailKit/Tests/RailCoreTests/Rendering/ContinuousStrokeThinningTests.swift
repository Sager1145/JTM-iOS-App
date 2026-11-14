import Foundation
import Testing

@testable import RailCore

/// Guard for the viewport vertex budget: a curved continuous stroke is thinned
/// within `strokeSimplifyTolerancePx` like every other stroke. Before this, a
/// dense survey at a wide zoom emitted every spline sample, and the 40,000
/// vertex budget (NetworkLOD.fitToBudget) then dropped whole railway lines.
struct ContinuousStrokeThinningTests {
    typealias Point = ContinuousStroke.Point

    /// A 450 px arc surveyed every 0.05 px: far denser than the screen can show.
    private static let radius = 300.0
    private static let count = 9_001
    private static let anchorIndex = 4_000

    private func source() -> (points: [Point], measures: [Double]) {
        let angleStep = 1.5 / Double(Self.count - 1)
        let points = (0..<Self.count).map { index -> Point in
            let angle = Double(index) * angleStep
            return Point(x: Self.radius * sin(angle), y: Self.radius * (1 - cos(angle)))
        }
        // 5 m per pixel keeps the spline deviation allowance at its pixel floor.
        var measures = [0.0]
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            measures.append(measures[index - 1] + hypot(b.x - a.x, b.y - a.y) * 5)
        }
        return (points, measures)
    }

    private func stroke(anchors: [Int]) -> (stroke: ContinuousStroke.Stroke, source: [Point]) {
        let (points, measures) = source()
        let options = ContinuousStroke.Options(
            measures: measures, rows: [], totalMetres: measures.last! - measures.first!,
            laneGapPx: 0, minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: 0,
            anchors: anchors, enforceMinimumCornerRadius: false)
        return (ContinuousStroke.buildStroke(points, options: options), points)
    }

    @Test func denseCurvedChainEmitsBoundedVertexCount() {
        let built = stroke(anchors: [0, Self.anchorIndex, Self.count - 1])
        // 9,001 surveyed vertices; a 450 px arc needs a few hundred at most.
        #expect(built.stroke.points.count < 600)
        #expect(built.stroke.points.count >= 3)
    }

    @Test func thinnedCurvedChainKeepsEndsAndAnchorsExactly() {
        let built = stroke(anchors: [0, Self.anchorIndex, Self.count - 1])
        let points = built.stroke.points
        #expect(points.first == built.source.first)
        #expect(points.last == built.source.last)
        let anchor = built.stroke.anchors[1]
        #expect(anchor == built.source[Self.anchorIndex])
        // The bead is a drawn vertex, not merely near the ink.
        #expect(points.contains(anchor))
        #expect(ContinuousStroke.distanceToPolyline(anchor, points) == 0)
        #expect(built.stroke.anchorMeasures.count == 3)
    }

    @Test func thinnedCurvedChainStaysWithinToleranceOfTheUnthinnedCurve() {
        let built = stroke(anchors: [0, Self.anchorIndex, Self.count - 1])
        // Slack covers the fillet's own sub-pixel rounding of a 450 px arc.
        let allowance = ContinuousStroke.strokeSimplifyTolerancePx + 0.0625
        let worstSourceToStroke = built.source
            .map { ContinuousStroke.distanceToPolyline($0, built.stroke.points) }.max() ?? .infinity
        let worstStrokeToSource = built.stroke.points
            .map { ContinuousStroke.distanceToPolyline($0, built.source) }.max() ?? .infinity
        #expect(worstSourceToStroke <= allowance)
        #expect(worstStrokeToSource <= allowance)
    }

    @Test func simplifyForcedVerticesSurviveWithoutBecomingAnchors() {
        let points = (0...100).map { Point(x: Double($0), y: 0) }
        let measures = (0...100).map(Double.init)
        let result = ContinuousStroke.simplifyForFillet(
            points, measures: measures, anchors: [30], forced: [60], tolerance: 0.0625)
        #expect(result.measures == [0, 30, 60, 100])
        #expect(result.anchors == [1])
    }
}
