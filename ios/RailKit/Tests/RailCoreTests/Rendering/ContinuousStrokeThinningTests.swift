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

    private func source(radius: Double = radius) -> (points: [Point], measures: [Double]) {
        let angleStep = 1.5 / Double(Self.count - 1)
        let points = (0..<Self.count).map { index -> Point in
            let angle = Double(index) * angleStep
            return Point(x: radius * sin(angle), y: radius * (1 - cos(angle)))
        }
        // 5 m per pixel keeps the spline deviation allowance at its pixel floor.
        var measures = [0.0]
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            measures.append(measures[index - 1] + hypot(b.x - a.x, b.y - a.y) * 5)
        }
        return (points, measures)
    }

    private func stroke(anchors: [Int], radius: Double = radius) -> (stroke: ContinuousStroke.Stroke, source: [Point]) {
        let (points, measures) = source(radius: radius)
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

    /// Thinning must not rebuild the facets `sampleCubic` removed: no vertex may
    /// turn more than `curveMaxStepDegrees` between two edges longer than
    /// `curveFacetEdgePx`. A bare 0.0625 px chord tolerance on a 100 px radius
    /// keeps vertices turning 3-5 degrees between 3-14 px edges.
    @Test(arguments: [100.0, 160.0, 400.0])
    func thinnedCurvedChainKeepsTheFacetRule(radius: Double) {
        let built = stroke(anchors: [0, Self.anchorIndex, Self.count - 1], radius: radius)
        let points = built.stroke.points
        #expect(points.count >= 3)
        #expect(points.count < 1_500)
        var worst = 0.0
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            guard hypot(b.x - a.x, b.y - a.y) > ContinuousStroke.curveFacetEdgePx,
                  hypot(c.x - b.x, c.y - b.y) > ContinuousStroke.curveFacetEdgePx else { continue }
            let turn = ContinuousStroke.vectorAngle(
                Point(x: b.x - a.x, y: b.y - a.y), Point(x: c.x - b.x, y: c.y - b.y))
            worst = max(worst, turn)
        }
        #expect(worst <= ContinuousStroke.curveMaxStepDegrees + 1e-6)
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
