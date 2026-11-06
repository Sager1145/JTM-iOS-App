import Foundation
import Testing
@testable import RailCore

struct ContinuousStrokeDenseCornerTests {
    typealias Point = ContinuousStroke.Point

    @Test func finalInkRetainsAnIsolatedSurveyedCorner() {
        let source = [Point(x: -100, y: 0), Point(x: 0, y: 0),
                      Point(x: 0, y: 100), Point(x: 0, y: 200)]
        assertCorners(source, indices: [1])
    }

    @Test func neighbouringOppositeCornersDoNotCancelIntoACurve() {
        // A short diagonal between two long parallel approaches. Both
        // 45-degree bends are real, rather than facets of one gentle arc.
        let source = [Point(x: -100, y: 0), Point(x: 0, y: 0),
                      Point(x: 5, y: 5), Point(x: 105, y: 5)]
        assertCorners(source, indices: [1, 2])
    }

    @Test func ambiguousShortConnectorIsNotAssumedToBeASurveySeam() {
        // Geometry alone cannot distinguish this from real closely spaced
        // railway bends. Preserve it until a surveyed display repair exists.
        assertCorners([Point(x: -100, y: 0), Point(x: 0, y: 0),
                       Point(x: 10, y: 10), Point(x: 110, y: 10)], indices: [1, 2])
    }

    @Test func localizedModerateCornerKeepsItsDeflection() {
        let angle = Double.pi * 35 / 180
        assertCorners([Point(x: -100, y: 0), Point(x: 0, y: 0),
                       Point(x: 100 * cos(angle), y: 100 * sin(angle)),
                       Point(x: 200 * cos(angle), y: 200 * sin(angle))], indices: [1])
    }

    private func assertCorners(_ source: [Point], indices: [Int]) {
        for scale in [0.25, 1.0, 4.0] {
            let p = source.map { Point(x: $0.x * scale, y: $0.y * scale) }
            let metres = ContinuousStroke.cumulativeLengths(source)
            for minimum in [0.0, 3.0] {
                let result = ContinuousStroke.buildStroke(p, options: .init(
                    measures: metres, rows: [], totalMetres: metres.last!, laneGapPx: 0,
                    minRampPx: 24, cornerRadiusPx: 3.6, minCornerRadiusPx: minimum,
                    anchors: [0, p.count - 1], enforceMinimumCornerRadius: minimum > 0))
                for i in indices {
                    #expect(result.points.contains(p[i]))
                    if let at = result.points.firstIndex(of: p[i]), at > 0, at + 1 < result.points.count {
                        #expect(abs(ContinuousStroke.turnAt(result.points, at)
                            - ContinuousStroke.turnAt(p, i)) < 1e-9)
                    }
                }
                #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy { $0 <= $1 })
            }
        }
    }
}
