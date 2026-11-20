import Foundation
import Testing
@testable import RailCore

/// Permanent guard: the corner survey of a stroke's followed chain runs once
/// per `buildStroke` and is shared by every pass over that chain. It used to
/// run on the full chain three times (plus once on the kept subset), which
/// dominated `map.geometry.prepare.strokes`. Output is pinned bit-for-bit by
/// the exact golden suites (StrokeBakeEquality, ContinuousStrokeParity).
#if DEBUG
struct RegressionGuardSurveyOncePerStrokeTests {
    typealias Point = ContinuousStroke.Point

    /// A long chain with sharp corners and arcs, so every pass is exercised.
    private static func chain() -> [Point] {
        var points = [Point(x: 0, y: 0)]
        var heading = 0.0
        for i in 1..<240 {
            if i % 37 == 0 { heading += (i % 2 == 0 ? 1 : -1) * 1.1 } else { heading += 0.03 * sin(Double(i)) }
            let last = points.last!
            points.append(Point(x: last.x + 2.5 * cos(heading), y: last.y + 2.5 * sin(heading)))
        }
        return points
    }

    @Test func surveyRunsOncePerChainPerStroke() {
        let source = Self.chain()
        let measures = ContinuousStroke.cumulativeLengths(source)
        var stroke: ContinuousStroke.Stroke?
        let calls = ContinuousStroke.SurveyProbe.capture {
            stroke = ContinuousStroke.buildStroke(source, options: .init(
                measures: measures, rows: [.init(from: 0, to: measures.last!, lane: 0.5)],
                totalMetres: measures.last!, laneGapPx: 2.7, minRampPx: 24,
                cornerRadiusPx: 3.6, minCornerRadiusPx: 3, anchors: [0, source.count - 1],
                enforceMinimumCornerRadius: true))
        }
        #expect(stroke != nil)
        // One survey of the full chain, shared by every pass, plus the one on
        // the kept subset of that chain (a different polyline). It used to be
        // four. The subset can keep every point, so count calls, not sizes.
        #expect(calls.count == 2, "surveys: \(calls)")
        #expect(calls.first == source.count, "surveys: \(calls)")
    }
}
#endif
