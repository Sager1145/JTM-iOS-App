import Foundation
import Testing

@testable import RailCore

struct ContinuousStrokeLiteralSpanTests {
    typealias Point = ContinuousStroke.Point
    typealias LiteralSpan = ContinuousStroke.LiteralSpan

    private let source: [Point] = [
        Point(x: 0, y: -40), Point(x: 100, y: -15),
        Point(x: 230, y: -3), Point(x: 360, y: 0),
        Point(x: 3360, y: 0), Point(x: 3490, y: 5),
        Point(x: 3620, y: 24), Point(x: 3720, y: 50),
    ]
    // Deliberately not pixel arclength: derivatives belong to the caller's ruler.
    private let measures: [Double] = [31, 151, 301, 561, 8061, 8301, 8561, 8761]

    private var literal: LiteralSpan {
        LiteralSpan(edgeIndex: 3, witnesses: Array(source[2...5]))
    }

    private func options(_ spans: [LiteralSpan] = []) -> ContinuousStroke.Options {
        .init(
            measures: measures, rows: [], totalMetres: 8730,
            laneGapPx: 3, minRampPx: 24, cornerRadiusPx: 3.6,
            anchors: [0, 7], literalSpans: spans)
    }

    private func assertLiteralBodyAndCurvedShoulders(
        _ points: [Point], _ ruler: [Double]
    ) throws {
        let a = try #require(ruler.firstIndex(of: 561))
        let b = try #require(ruler.firstIndex(of: 8061))
        #expect(points[a] == Point(x: 360, y: 0))
        #expect(points[b] == Point(x: 3360, y: 0))
        #expect(points[a...b].allSatisfy { abs($0.y) < 1e-12 })
        let left = points.indices.filter { ruler[$0] > 301 && ruler[$0] < 561 }
        let right = points.indices.filter { ruler[$0] > 8061 && ruler[$0] < 8301 }
        #expect(!left.isEmpty && !right.isEmpty)
        // The shoulders must remain actual curves, not three literal chords.
        #expect(left.contains { abs(points[$0].y - (-3 + 3 * (points[$0].x - 230) / 130)) > 0.01 })
        #expect(right.contains { abs(points[$0].y - 5 * (points[$0].x - 3360) / 130) > 0.01 })
    }

    @Test func literalBodySurvivesFinalStrokeWithoutCreatingStationAnchors() throws {
        let original = source
        let originalMeasures = measures
        let requested = options([literal])
        let result = ContinuousStroke.buildStroke(source, options: requested)

        try assertLiteralBodyAndCurvedShoulders(result.points, result.measures)
        #expect(result.appliedLiteralSpanEdges == [3])
        #expect(result.anchors == [Point(x: 0, y: -40), Point(x: 3720, y: 50)])
        #expect(result.anchorMeasures == [31, 8761])
        #expect(result.measures.count == result.points.count)
        #expect(result.measures.allSatisfy { $0.isFinite })
        #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy(<=))
        #expect(source == original && measures == originalMeasures)
        #expect(requested.anchors == [0, 7])
        #expect(requested.literalSpans[0].witnesses == Array(original[2...5]))
    }

    @Test func shoulderEndpointDerivativesMatchLiteralVelocityOnCallerRuler() throws {
        let result = ContinuousStroke.smoothCentreline(
            source, measures: measures, literalSpans: [literal])
        try assertLiteralBodyAndCurvedShoulders(result.points, result.measures)
        let a = try #require(result.measures.firstIndex(of: 561))
        let b = try #require(result.measures.firstIndex(of: 8061))
        #expect(a >= 3 && b + 3 < result.points.count)
        guard a >= 3, b + 3 < result.points.count else { return }
        #expect(result.measures[a - 3] >= 301)
        #expect(result.measures[b + 3] <= 8301)
        // Differentiate the observable cubic samples with a four-node finite
        // approximation. This avoids equating a coarse final chord with C1.
        let incoming = derivative(result.points, result.measures, Array((a - 3)...a), at: 561)
        let outgoing = derivative(result.points, result.measures, Array(b...(b + 3)), at: 8061)
        #expect(abs(incoming.x - 0.4) < 1e-8)
        #expect(abs(incoming.y) < 1e-8)
        #expect(abs(outgoing.x - 0.4) < 1e-8)
        #expect(abs(outgoing.y) < 1e-8)
    }

    @Test func invalidWitnessesAndConflictingFootprintsReturnExactOrdinaryStroke() {
        let ordinary = ContinuousStroke.buildStroke(source, options: options())
        var changed = Array(source[2...5])
        changed[0].y += 0.001
        let unsupported: [[LiteralSpan]] = [
            [LiteralSpan(edgeIndex: -1, witnesses: Array(source[2...5]))],
            [LiteralSpan(edgeIndex: 3, witnesses: changed)],
            [LiteralSpan(edgeIndex: 3, witnesses: Array(source[2...4]))],
            [literal, literal],
            [literal, LiteralSpan(edgeIndex: 4, witnesses: Array(source[3...6]))],
        ]
        for spans in unsupported {
            let result = ContinuousStroke.buildStroke(source, options: options(spans))
            #expect(result == ordinary)
            #expect(result.appliedLiteralSpanEdges.isEmpty)
        }
        #expect(ordinary.appliedLiteralSpanEdges.isEmpty)
    }

    @Test func activeOffsetOrFollowFallsBackAtomicallyToOrdinaryStroke() {
        var offset = options()
        offset.rows = [.init(from: 31, to: 8761, lane: 1)]
        var follow = options()
        follow.follows = [.init(
            from: 31, to: 8761, canonFrom: 31, canonTo: 8761,
            points: source.map { Point(x: $0.x, y: $0.y + 2) }, measures: measures)]
        for ordinaryOptions in [offset, follow] {
            let ordinary = ContinuousStroke.buildStroke(source, options: ordinaryOptions)
            var hintedOptions = ordinaryOptions
            hintedOptions.literalSpans = [literal]
            let hinted = ContinuousStroke.buildStroke(source, options: hintedOptions)
            #expect(hinted == ordinary)
            #expect(hinted.appliedLiteralSpanEdges.isEmpty)
        }
    }

    @Test func zeroPixelGapCannotAdmitSemanticLaneOffsets() {
        var row = options()
        row.laneGapPx = 0
        row.rows = [.init(from: 31, to: 8761, lane: 1)]
        var inheritedLane = options()
        inheritedLane.laneGapPx = 0
        inheritedLane.joinStart = .init(
            lane: 1, incoming: Point(x: 1, y: 0), outgoing: Point(x: 1, y: 0))
        var inheritedTarget = options()
        inheritedTarget.laneGapPx = 0
        inheritedTarget.joinEnd = .init(
            lane: 0, incoming: Point(x: 1, y: 0), outgoing: Point(x: 1, y: 0), targetLane: 1)
        for ordinaryOptions in [row, inheritedLane, inheritedTarget] {
            let ordinary = ContinuousStroke.buildStroke(source, options: ordinaryOptions)
            var hintedOptions = ordinaryOptions
            hintedOptions.literalSpans = [literal]
            let hinted = ContinuousStroke.buildStroke(source, options: hintedOptions)
            #expect(hinted == ordinary)
            #expect(hinted.appliedLiteralSpanEdges.isEmpty)
        }
    }

    @Test func hardShoulderRejectsWholeLiteralConstruction() {
        let ordinary = ContinuousStroke.smoothCentreline(source, measures: measures, hardMeasures: [561])
        let hinted = ContinuousStroke.smoothCentreline(
            source, measures: measures, hardMeasures: [561], literalSpans: [literal])
        #expect(hinted.points == ordinary.points)
        #expect(hinted.measures == ordinary.measures)
    }

    @Test func finalRoundingThatChangesFootprintReturnsExactOrdinaryStroke() {
        let small = source.map { Point(x: $0.x * 0.01, y: $0.y * 0.01) }
        let ordinaryOptions = options()
        var hintedOptions = ordinaryOptions
        hintedOptions.literalSpans = [LiteralSpan(edgeIndex: 3, witnesses: Array(small[2...5]))]
        let smooth = ContinuousStroke.smoothCentreline(
            small, measures: measures, literalSpans: hintedOptions.literalSpans)
        #expect(smooth.points.contains(Point(x: 3.6, y: 0)))
        let ordinary = ContinuousStroke.buildStroke(small, options: ordinaryOptions)
        let hinted = ContinuousStroke.buildStroke(small, options: hintedOptions)
        #expect(hinted == ordinary)
        #expect(hinted.appliedLiteralSpanEdges.isEmpty)
    }

    @Test func deduplicationCannotBorrowAnotherWitnessMeasure() {
        var repeated = source
        repeated[1] = repeated[2]
        var hintedOptions = options()
        hintedOptions.literalSpans = [LiteralSpan(edgeIndex: 3, witnesses: Array(repeated[2...5]))]
        let ordinary = ContinuousStroke.buildStroke(repeated, options: options())
        let hinted = ContinuousStroke.buildStroke(repeated, options: hintedOptions)
        #expect(hinted == ordinary)
        #expect(hinted.appliedLiteralSpanEdges.isEmpty)
    }

    @Test func actualYamadaTwoCornersKeepSourceShoulderAndReleaseQ() throws {
        // Actual Y4 raw i12[62...72], complete DISPLAY part[1998...2008].
        let coordinates: [[Double]] = [
            [141.87926811665955,39.631810221068676], [141.8796380566901,39.63198257268963],
            [141.88064230029045,39.63241183090143], [141.88093197886406,39.632488262131695],
            [141.88220370592762,39.632742771241496], [141.88461769404103,39.63238333847553],
            [141.88483227076222,39.63238333847553], [141.8857792256776,39.63257844481797],
            [141.88669606726353,39.632906239404996], [141.88692721113597,39.63299365029543],
            [141.88723675482936,39.63310838250123]
        ]
        let points = coordinates.map { pair in
            Point(x: pow(2, 26) * (pair[0] + 180) / 360,
                  y: pow(2, 25) * (1 - asinh(tan(pair[1] * .pi / 180)) / .pi))
        }
        var ruler = [0.0]
        for i in 1..<points.count {
            ruler.append(ruler.last! + hypot(points[i].x - points[i - 1].x,
                                            points[i].y - points[i - 1].y) * 0.45923414993959905)
        }
        let ordinaryOptions = ContinuousStroke.Options(
            measures: ruler, rows: [], totalMetres: ruler.last!, laneGapPx: 3, minRampPx: 24,
            cornerRadiusPx: 3.6, minCornerRadiusPx: 3, anchors: [0, 10], enforceMinimumCornerRadius: true)
        let ordinary = ContinuousStroke.buildStroke(points, options: ordinaryOptions)
        var literalOptions = ordinaryOptions
        literalOptions.literalSpans = [.init(edgeIndex: 4, witnesses: Array(points[3...6]))]
        let literal = ContinuousStroke.buildStroke(points, options: literalOptions)
        var cornerOptions = literalOptions
        cornerOptions.literalSpans[0].mode = "source-corners-v1"
        let result = ContinuousStroke.buildStroke(points, options: cornerOptions)
        func departure(_ stroke: ContinuousStroke.Stroke, _ lo: Int, _ hi: Int) -> Double {
            let a = points[lo], b = points[hi], dx = b.x - a.x, dy = b.y - a.y
            return stroke.points.indices.filter { stroke.measures[$0] >= ruler[lo] && stroke.measures[$0] <= ruler[hi] }
                .reduce(0) { max($0, -((stroke.points[$1].y - a.y) * dx - (stroke.points[$1].x - a.x) * dy) / hypot(dx, dy)) }
        }
        #expect(departure(ordinary, 4, 5) > 10)
        #expect(departure(literal, 3, 4) > 15)
        #expect(departure(result, 4, 5) < 1e-6)
        #expect(departure(result, 3, 4) < 1e-6)
        for index in [4, 5] {
            let emitted = try #require(result.measures.firstIndex(of: ruler[index]))
            #expect(result.points[emitted] == points[index])
        }
        #expect(result.appliedSourceCornerEdges == [4])
        #expect(result.appliedLiteralSpanEdges.isEmpty)
        #expect(result.anchors == ordinary.anchors)
        #expect(result.anchorMeasures == ordinary.anchorMeasures)
        #expect(result.measures.filter { $0 > ruler[6] && $0 < ruler[7] }.count > 2)
    }

    @Test func sourceCornersRejectStationHardBoundaryLaneFollowAndUnknownMode() {
        let span = LiteralSpan(edgeIndex: 3, witnesses: Array(source[2...5]), mode: "source-corners-v1")
        var station = options(); station.anchors = [0, 2, 7]
        var hard = options(); hard.shapeBoundaryMeasures = [measures[5]]
        var lane = options(); lane.laneGapPx = 0; lane.rows = [.init(from: 31, to: 8761, lane: 1)]
        var follow = options(); follow.follows = [.init(
            from: 31, to: 8761, canonFrom: 31, canonTo: 8761, points: source, measures: measures)]
        for ordinaryOptions in [station, hard, lane, follow] {
            let ordinary = ContinuousStroke.buildStroke(source, options: ordinaryOptions)
            var requested = ordinaryOptions; requested.literalSpans = [span]
            #expect(ContinuousStroke.buildStroke(source, options: requested) == ordinary)
        }
        var unknown = options(); unknown.literalSpans = [.init(edgeIndex: 3, witnesses: Array(source[2...5]), mode: "future")]
        #expect(ContinuousStroke.buildStroke(source, options: unknown) == ContinuousStroke.buildStroke(source, options: options()))
        var duplicate = options(); duplicate.literalSpans = [span, span]
        #expect(ContinuousStroke.buildStroke(source, options: duplicate) == ContinuousStroke.buildStroke(source, options: options()))
        var overlap = options(); overlap.literalSpans = [span, .init(edgeIndex: 4, witnesses: Array(source[3...6]), mode: "source-corners-v1")]
        #expect(ContinuousStroke.buildStroke(source, options: overlap) == ContinuousStroke.buildStroke(source, options: options()))
        var changed = span; changed.witnesses[0].y += 0.001
        var substituted = options(); substituted.literalSpans = [changed]
        #expect(ContinuousStroke.buildStroke(source, options: substituted) == ContinuousStroke.buildStroke(source, options: options()))
        var repeated = source; repeated[1] = repeated[2]
        var requested = options(); requested.literalSpans = [span]
        #expect(ContinuousStroke.buildStroke(repeated, options: requested) == ContinuousStroke.buildStroke(repeated, options: options()))
    }

    /// Derivative of the interpolating cubic, evaluated from public samples.
    /// Lagrange weights allow the sampler to change its spacing or density.
    private func derivative(_ points: [Point], _ ruler: [Double], _ indices: [Int], at value: Double) -> Point {
        var result = Point(x: 0, y: 0)
        for i in indices {
            var weight = 0.0
            for j in indices where j != i {
                var term = 1 / (ruler[i] - ruler[j])
                for k in indices where k != i && k != j {
                    term *= (value - ruler[k]) / (ruler[i] - ruler[k])
                }
                weight += term
            }
            // Relative coordinates keep the finite approximation well scaled.
            result.x += weight * (points[i].x - points[indices[0]].x)
            result.y += weight * (points[i].y - points[indices[0]].y)
        }
        return result
    }
}
