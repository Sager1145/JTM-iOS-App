import Foundation
import Testing

@testable import RailCore

struct ContinuousStrokeMinimumRadiusTests {
    typealias Point = ContinuousStroke.Point

    private func rounded(_ points: [Point], radius: Double = 8, floor: Double = 4,
                         anchors: Set<Int> = []) -> (points: [Point], measures: [Double]) {
        ContinuousStroke.fillet(points, radius: radius, floorRadius: floor,
                                anchors: anchors,
                                measures: ContinuousStroke.cumulativeLengths(points),
                                enforceMinimumRadius: true)
    }

    @Test func floorOverridesSmallerRequestedRadius() {
        let input = [Point(x: -100, y: 0), Point(x: 0, y: 0), Point(x: 0, y: 100)]
        let result = rounded(input, radius: 1, floor: 4)
        #expect(result.points.count > input.count)
        // For a right angle the tangent distance equals the actual radius.
        #expect(abs(result.points[1].x + 4) < 1e-8)
        #expect(abs(result.points[result.points.count - 2].y - 4) < 1e-8)
    }

    @Test func infeasibleFloorDoesNotEmitTinyArc() {
        let input = [Point(x: -1, y: 0), Point(x: 0, y: 0), Point(x: 0, y: 1)]
        #expect(rounded(input).points == input)
    }

    @Test func anchorsNeverCreateReflexLoops() {
        for degrees in [30.0, 90, 120, 149] {
            let angle = degrees * .pi / 180
            let input = [Point(x: -100, y: 0), Point(x: 0, y: 0),
                         Point(x: 100 * cos(angle), y: 100 * sin(angle))]
            // A circle through the apex cannot also be tangent to both
            // incident edges. Keep the real anchor instead of drawing a loop.
            let result = rounded(input, anchors: [1])
            #expect(result.points == input)
            #expect(result.measures == ContinuousStroke.cumulativeLengths(input))
        }
    }

    @Test func roundedCornersStayPositiveAcrossZoomAndLaneSides() {
        for scale in [0.1, 0.5, 1, 2, 8] {
            for lane in [-2.0, -1, 0, 1, 2] {
                let input = [Point(x: -100 * scale, y: 0), Point(x: 0, y: 0),
                             Point(x: 0, y: 100 * scale)]
                let result = ContinuousStroke.buildStroke(input, options: .init(
                    measures: [0, 1_000, 2_000],
                    rows: [.init(from: 0, to: 2_000, lane: lane)], totalMetres: 2_000,
                    laneGapPx: 3, minRampPx: 10, cornerRadiusPx: 8,
                    minCornerRadiusPx: 4, anchors: [0, 2], enforceMinimumCornerRadius: true))
                #expect(result.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy { $0 <= $1 })
                #expect(result.anchors == [result.points.first!, result.points.last!])
                if result.points.count > 3 {
                    // Interior arc triples must all have the same turn sign
                    // and a circumradius at least the requested pixel floor.
                    for i in 2..<(result.points.count - 2) {
                        let a = result.points[i - 1], b = result.points[i], c = result.points[i + 1]
                        let cross = (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x)
                        #expect(cross > 0)
                        let r = hypot(b.x-a.x,b.y-a.y)*hypot(c.x-b.x,c.y-b.y)*hypot(c.x-a.x,c.y-a.y)/(2*abs(cross))
                        #expect(r >= 4 - 1e-7)
                    }
                }
            }
        }
    }

    @Test func sixteenLanesKeepOrderAndForwardDirectionAcrossZoom() {
        for degrees in [30.0, 90, 140] {
            let angle = degrees * .pi / 180
            let forward = Point(x: cos(angle / 2), y: sin(angle / 2))
            for scale in [0.5, 1.0, 2, 8] {
                var previous: ContinuousStroke.Stroke?
                for slot in 0..<16 {
                    let lane = Double(slot) - 7.5
                    let input = [Point(x: -300 * scale, y: 0), Point(x: 0, y: 0),
                                 Point(x: 300 * scale * cos(angle), y: 300 * scale * sin(angle))]
                    let result = ContinuousStroke.buildStroke(input, options: .init(
                        measures: [0, 1_000, 2_000],
                        rows: [.init(from: 0, to: 2_000, lane: lane)], totalMetres: 2_000,
                        laneGapPx: 3, minRampPx: 10, cornerRadiusPx: 8,
                        minCornerRadiusPx: 4, anchors: [0, 2], enforceMinimumCornerRadius: true))
                    #expect(result.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                    for (a, b) in zip(result.points, result.points.dropFirst()) {
                        #expect((b.x-a.x)*forward.x + (b.y-a.y)*forward.y > 0)
                    }
                    for i in 2..<(result.points.count - 2) {
                        let a = result.points[i - 1], b = result.points[i], c = result.points[i + 1]
                        let cross = (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x)
                        #expect(cross > 0)
                        let r = hypot(b.x-a.x,b.y-a.y)*hypot(c.x-b.x,c.y-b.y)*hypot(c.x-a.x,c.y-a.y)/(2*abs(cross))
                        #expect(r >= 4 - 1e-7)
                    }
                    if let previous {
                        // Equal, feasible fillets have corresponding
                        // samples: every lane stays exactly one gap beside its neighbour.
                        #expect(previous.points.count == result.points.count)
                        for (a, b) in zip(previous.points, result.points) {
                            #expect(-(b.x-a.x)*forward.y + (b.y-a.y)*forward.x > 0)
                            #expect(hypot(b.x-a.x, b.y-a.y) >= 3 - 1e-8)
                        }
                    }
                    previous = result
                }
            }
        }
    }

    @Test func overlappingRampsRetainAnchorsAndApproximateTheCombinedKernel() {
        let input = [Point(x: 0, y: 0), Point(x: 475, y: 0), Point(x: 1_000, y: 0)]
        let measures = [0.0, 475, 1_000]
        let rows = (0..<10).map { index in
            ContinuousStroke.LaneRow(from: Double(index) * 100, to: Double(index + 1) * 100,
                                     lane: index.isMultiple(of: 2) ? -7.5 : 7.5)
        }
        let profile = ContinuousStroke.laneProfile(rows: rows, total: 1_000)
        let sampled = ContinuousStroke.sampleLaneRamps(
            input, measures: measures, profile: profile, width: 300, gap: 3)
        for index in input.indices {
            #expect(sampled.points[sampled.map[index]] == input[index])
            #expect(sampled.measures[sampled.map[index]] == measures[index])
        }
        let result = ContinuousStroke.buildStroke(input, options: .init(
            measures: measures, rows: rows, totalMetres: 1_000,
            laneGapPx: 3, minRampPx: 10, cornerRadiusPx: 0,
            anchors: [0, 1, 2], enforceMinimumCornerRadius: true))
        for anchor in result.anchors {
            #expect(ContinuousStroke.distanceToPolyline(anchor, result.points) < 1e-8)
        }
        for measure in stride(from: 0.0, through: 1_000, by: 7) {
            let target = Point(x: measure,
                y: ContinuousStroke.laneAt(profile: profile, measure: measure, width: 300) * 3)
            #expect(ContinuousStroke.distanceToPolyline(target, result.points) <= 0.126)
        }
    }

    @Test func sparseSurveyIncludesEntireLaneExcursionAtEveryZoom() {
        let rows: [ContinuousStroke.LaneRow] = [
            .init(from: 0, to: 1_000, lane: 0),
            .init(from: 1_000, to: 3_000, lane: 15),
            .init(from: 3_000, to: 4_000, lane: 0)]
        for scale in [0.25, 1.0, 4] {
            let result = ContinuousStroke.buildStroke(
                [Point(x: 0, y: 0), Point(x: 4_000 * scale, y: 0)], options: .init(
                    measures: [0, 4_000], rows: rows, totalMetres: 4_000,
                    laneGapPx: 3, minRampPx: 10, cornerRadiusPx: 0,
                    anchors: [0, 1], enforceMinimumCornerRadius: true))
            #expect(result.points.contains { abs($0.y - 45) < 1e-8 })
            #expect(result.anchors == [Point(x: 0, y: 0), Point(x: 4_000 * scale, y: 0)])
            #expect(zip(result.points, result.points.dropFirst()).allSatisfy { $0.x < $1.x })
            let profile = ContinuousStroke.laneProfile(rows: rows, total: 4_000)
            // Check the drawn interpolation, not merely its sampled vertices.
            for measure in stride(from: 0.0, through: 4_000, by: 17) {
                let target = Point(x: measure * scale,
                    y: ContinuousStroke.laneAt(profile: profile, measure: measure, width: 300) * 3)
                #expect(ContinuousStroke.distanceToPolyline(target, result.points) <= 0.126)
            }
        }
    }

    @Test func strictGeometryPreservesFixtureMeasuresAndAnchorAttachment() throws {
        for probe in try ContinuousStrokeParityTests.fixture().cases {
            var options = ContinuousStrokeParityTests.options(probe)
            options.enforceMinimumCornerRadius = true
            options.minCornerRadiusPx = 4
            let result = ContinuousStroke.buildStroke(
                ContinuousStrokeParityTests.points(probe.points), options: options)
            #expect(result.points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy { $0 <= $1 },
                    Comment(rawValue: probe.note))
            if result.points.count >= 2 {
                for anchor in result.anchors {
                    #expect(ContinuousStroke.distanceToPolyline(anchor, result.points) < 1e-6,
                            Comment(rawValue: probe.note))
                }
            }
        }
    }

    @Test func windowedLaneSamplingMatchesFullKernel() {
        var rows: [ContinuousStroke.LaneRow] = []
        for index in 0..<200 {
            rows.append(.init(from: Double(index) * 100, to: Double(index + 1) * 100,
                              lane: Double(index % 7) - 3))
        }
        let profile = ContinuousStroke.laneProfile(rows: rows, total: 20_000)
        for width in [1.0, 300, 20_000] {
            for measure in stride(from: -1_000.0, through: 21_000, by: 37) {
                var expected = 0.0
                for (i, plateau) in profile.enumerated() {
                    let start = i == 0 ? 1 : ContinuousStroke.kernelCumulative(measure - plateau.from, width: width)
                    let end = i == profile.count - 1 ? 0 : ContinuousStroke.kernelCumulative(measure - plateau.to, width: width)
                    expected += plateau.lane * (start - end)
                }
                #expect(abs(ContinuousStroke.laneAt(profile: profile, measure: measure, width: width) - expected) < 1e-10)
            }
        }
    }
}
