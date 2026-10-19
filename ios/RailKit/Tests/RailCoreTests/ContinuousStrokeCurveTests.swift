import Foundation
import Testing

@testable import RailCore

struct ContinuousStrokeCurveTests {
    typealias Point = ContinuousStroke.Point

    private func point(_ radius: Double, _ angle: Double) -> Point {
        Point(x: radius * sin(angle), y: radius * (1 - cos(angle)))
    }

    private func turnDegrees(_ points: [Point], at index: Int) -> Double {
        let a = points[index - 1]
        let b = points[index]
        let c = points[index + 1]
        let incoming = Point(x: b.x - a.x, y: b.y - a.y)
        let outgoing = Point(x: c.x - b.x, y: c.y - b.y)
        return abs(atan2(
            incoming.x * outgoing.y - incoming.y * outgoing.x,
            incoming.x * outgoing.x + incoming.y * outgoing.y
        )) * 180 / .pi
    }

    private func signedTurn(_ points: [Point], at index: Int) -> Double {
        let a = points[index - 1]
        let b = points[index]
        let c = points[index + 1]
        let incoming = Point(x: b.x - a.x, y: b.y - a.y)
        let outgoing = Point(x: c.x - b.x, y: c.y - b.y)
        return atan2(
            incoming.x * outgoing.y - incoming.y * outgoing.x,
            incoming.x * outgoing.x + incoming.y * outgoing.y
        )
    }

    private func distance(_ a: Point, _ b: Point) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func options(
        measures: [Double], rows: [ContinuousStroke.LaneRow] = [],
        laneGap: Double = 0, anchors: [Int]
    ) -> ContinuousStroke.Options {
        .init(
            measures: measures,
            rows: rows,
            totalMetres: measures.last! - measures.first!,
            laneGapPx: laneGap,
            minRampPx: 24,
            cornerRadiusPx: 3.6,
            minCornerRadiusPx: 0,
            anchors: anchors,
            enforceMinimumCornerRadius: false
        )
    }

    @Test func hundredMetreChordsOnFourHundredMetreRadiusAreSmoothAndBounded() {
        let radius = 400.0
        let chord = 100.0
        let angleStep = 2 * asin(chord / (2 * radius))
        let source = (0...8).map { point(radius, Double($0) * angleStep) }
        let measures = (0...8).map { Double($0) * chord }

        let result = ContinuousStroke.smoothCentreline(source, measures: measures)

        #expect(result.points.count > source.count)
        #expect(result.points.first == source.first)
        #expect(result.points.last == source.last)
        #expect(result.measures.first == measures.first)
        #expect(result.measures.last == measures.last)
        let maximumTurn = (1..<(result.points.count - 1))
            .map { turnDegrees(result.points, at: $0) }
            .max() ?? 0
        #expect(maximumTurn <= ContinuousStroke.curveMaxStepDegrees + 1e-9)

        let sagitta = radius - sqrt(radius * radius - chord * chord / 4)
        let maximumDeviation = result.points
            .map { ContinuousStroke.distanceToPolyline($0, source) }
            .max() ?? 0
        #expect(maximumDeviation <= sagitta + 1e-9)
    }

    @Test func sCurvePreservesBothDirectionsAndMonotonicMeasures() {
        let source = [
            Point(x: 0, y: 0), Point(x: 100, y: 18), Point(x: 200, y: 42),
            Point(x: 300, y: 42), Point(x: 400, y: 18), Point(x: 500, y: 0),
        ]
        let measures = (0..<source.count).map { Double($0) * 100 }

        let result = ContinuousStroke.smoothCentreline(source, measures: measures)

        #expect(result.points.count > source.count)
        #expect(result.points.first == source.first && result.points.last == source.last)
        #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy(<=))
        let turns = (1..<(result.points.count - 1)).map { signedTurn(result.points, at: $0) }
        #expect(turns.contains { $0 > 1e-6 })
        #expect(turns.contains { $0 < -1e-6 })
        #expect(turns.map { abs($0) * 180 / .pi }.max()! <= ContinuousStroke.curveMaxStepDegrees + 1e-9)
    }

    @Test func reversalOverOneHundredFiftyDegreesStaysHard() {
        let apex = Point(x: 200, y: 0)
        let source = [
            Point(x: 0, y: 0), Point(x: 100, y: 0), apex,
            Point(x: 100, y: 10), Point(x: 0, y: 20),
        ]
        let measures = (0..<source.count).map { Double($0) * 100 }

        let result = ContinuousStroke.smoothCentreline(source, measures: measures)

        #expect(result.points.first == source.first && result.points.last == source.last)
        let apexIndex = result.points.firstIndex(of: apex)
        #expect(apexIndex != nil)
        if let apexIndex {
            #expect(apexIndex > 0 && apexIndex + 1 < result.points.count)
            #expect(turnDegrees(result.points, at: apexIndex) > 150)
        }
    }

    @Test func midCurveStationIsProjectedOntoTheFinalStrokeByMeasure() {
        let source = [
            Point(x: 0, y: 0), Point(x: 100, y: 8), Point(x: 200, y: 28),
            Point(x: 300, y: 58), Point(x: 400, y: 96), Point(x: 500, y: 140),
        ]
        let measures = (0..<source.count).map { Double($0) * 100 }
        let stationIndex = 3

        let stroke = ContinuousStroke.buildStroke(
            source,
            options: options(measures: measures, anchors: [0, stationIndex, source.count - 1])
        )

        #expect(stroke.points.first == source.first)
        #expect(stroke.points.last == source.last)
        #expect(stroke.anchorMeasures == [0, measures[stationIndex], measures.last!])
        #expect(ContinuousStroke.distanceToPolyline(stroke.anchors[1], stroke.points) <= 0.25)
        let expected = ContinuousStroke.pointAtMeasure(
            stroke.points, stroke.measures, measures[stationIndex]
        )
        #expect(distance(stroke.anchors[1], expected) < 1e-9)
    }

    @Test func constantLaneOffsetStaysParallelOutsideRamps() {
        let source = [
            Point(x: 0, y: 0), Point(x: 100, y: 6), Point(x: 200, y: 20),
            Point(x: 300, y: 42), Point(x: 400, y: 70), Point(x: 500, y: 104),
        ]
        let measures = (0..<source.count).map { Double($0) * 100 }
        let gap = 3.0
        let centre = ContinuousStroke.buildStroke(
            source, options: options(measures: measures, anchors: [0, source.count - 1]))
        let lane = ContinuousStroke.buildStroke(
            source,
            options: options(
                measures: measures,
                rows: [.init(from: 0, to: measures.last!, lane: 1)],
                laneGap: gap,
                anchors: [0, source.count - 1]
            )
        )

        let spacingErrors = lane.points.dropFirst().dropLast().map {
            abs(ContinuousStroke.distanceToPolyline($0, centre.points) - gap)
        }
        #expect(spacingErrors.max()! <= 0.25)
        #expect(zip(lane.measures, lane.measures.dropFirst()).allSatisfy(<=))
    }

    @Test func branchTangentIgnoresSurveyDirection() throws {
        let main = [Point(x: -200, y: 0), Point(x: 0, y: 0), Point(x: 200, y: 0)]
        let departure = [Point(x: 0, y: 0), Point(x: 100, y: 10), Point(x: 200, y: 30)]
        for branch in [departure, departure.map { Point(x: -$0.x, y: $0.y) }] {
            for atEnd in [false, true] {
                let points = atEnd ? Array(branch.reversed()) : branch
                let forward = try #require(ContinuousStroke.tangentJoin(points, mainChain: main, atEnd: atEnd, lane: 0))
                let reverse = try #require(ContinuousStroke.tangentJoin(points, mainChain: Array(main.reversed()), atEnd: atEnd, lane: 0))
                #expect(forward.mainTangent == reverse.mainTangent)
            }
        }
        #expect(ContinuousStroke.tangentJoin([Point(x: 0, y: 0), Point(x: 100, y: 100)], mainChain: main, atEnd: false, lane: 0) == nil)
        #expect(ContinuousStroke.tangentJoin([Point(x: 0, y: 0.001), Point(x: 100, y: 10)], mainChain: main, atEnd: false, lane: 0) == nil)
    }

    @Test func branchEndpointInheritsMainLane() throws {
        let main = [Point(x: -200, y: 0), Point(x: 0, y: 0), Point(x: 200, y: 0)]
        let branch = [Point(x: 0, y: 0), Point(x: 100, y: 10), Point(x: 200, y: 30)]
        for reversed in [false, true] {
            let join = try #require(ContinuousStroke.tangentJoin(
                branch, mainChain: reversed ? Array(main.reversed()) : main,
                atEnd: false, lane: -1, mainLane: reversed ? -2 : 2))
            let stroke = ContinuousStroke.buildStroke(branch, options: .init(
                measures: [0, 200, 400], rows: [.init(from: 0, to: 400, lane: -1)],
                totalMetres: 400, laneGapPx: 10, minRampPx: 0, cornerRadiusPx: 0,
                anchors: [], joinStart: join))
            #expect(abs(stroke.points[0].y - 20) < 1e-10)
        }
    }

    @Test func confirmedEndpointJunctionMeetsPhysicalSwitch() throws {
        let departure = [Point(x: 0, y: 0), Point(x: 100, y: 10), Point(x: 200, y: 30)]
        let main = [Point(x: -200, y: 0), Point(x: 0, y: 0)]
        for atEnd in [false, true] {
            for reverseMain in [false, true] {
                let points = atEnd ? Array(departure.reversed()) : departure
                let chain = reverseMain ? Array(main.reversed()) : main
                #expect(ContinuousStroke.tangentJoin(
                    points, mainChain: chain, atEnd: atEnd, lane: 2, mainLane: 0) == nil)
                let join = try #require(ContinuousStroke.tangentJoin(
                    points, mainChain: chain, atEnd: atEnd, lane: 2, mainLane: 0, allowMainEndpoint: true))
                #expect(join.mainChain == chain)
                let stroke = ContinuousStroke.buildStroke(points, options: .init(
                    measures: [0, 200, 400], rows: [.init(from: 0, to: 400, lane: 2)],
                    totalMetres: 400, laneGapPx: 10, minRampPx: 24, cornerRadiusPx: 3.6,
                    anchors: [], joinStart: atEnd ? nil : join, joinEnd: atEnd ? join : nil))
                let endpoint = try #require(atEnd ? stroke.points.last : stroke.points.first)
                #expect(hypot(endpoint.x, endpoint.y) < 1e-9)
            }
        }
        #expect(ContinuousStroke.tangentJoin(
            [Point(x: 0, y: 0), Point(x: 100, y: 100)], mainChain: main,
            atEnd: false, lane: 0, mainLane: 0, allowMainEndpoint: true) == nil)
        #expect(ContinuousStroke.tangentJoin(
            [Point(x: 0, y: 0.001), Point(x: 100, y: 10)], mainChain: main,
            atEnd: false, lane: 0, mainLane: 0, allowMainEndpoint: true) == nil)
    }

    @Test func branchEndpointSurvivesNearbyLaneChangeAndPixelFloor() throws {
        for pixelScale in [1.0, 0.02] {
            for atEnd in [false, true] {
                let points = [Point(x: 0, y: 0), Point(x: 100 * pixelScale, y: 0),
                              Point(x: 1000 * pixelScale, y: 0)]
                let endpoint = atEnd ? points[2] : points[0]
                let main = [Point(x: endpoint.x - 2000, y: 0), endpoint,
                            Point(x: endpoint.x + 2000, y: 0)]
                let rows: [ContinuousStroke.LaneRow] = atEnd
                    ? [.init(from: 900, to: 1000, lane: -1)]
                    : [.init(from: 0, to: 100, lane: -1)]
                let join = try #require(ContinuousStroke.tangentJoin(
                    points, mainChain: main, atEnd: atEnd, lane: -1, mainLane: 2))
                let stroke = ContinuousStroke.buildStroke(points, options: .init(
                    measures: [0, 100, 1000], rows: rows, totalMetres: 1000,
                    laneGapPx: 10, minRampPx: 24, cornerRadiusPx: 0, anchors: [],
                    joinStart: atEnd ? nil : join, joinEnd: atEnd ? join : nil))
                let drawnEndpoint = try #require(atEnd ? stroke.points.last : stroke.points.first)
                #expect(abs(drawnEndpoint.y - 20) < 1e-9)
            }
        }
    }

    @Test func bothBranchTargetsSurviveOverlappingAndCoalescedRamps() throws {
        for total in [40.0, 100.0] {
            let points = [Point(x: 0, y: 0), Point(x: total / 2, y: 0), Point(x: total, y: 0)]
            let start = try #require(ContinuousStroke.tangentJoin(
                points, mainChain: [Point(x: -100, y: 0), points[0], Point(x: 100, y: 0)],
                atEnd: false, lane: 0, mainLane: 2))
            let end = try #require(ContinuousStroke.tangentJoin(
                points, mainChain: [Point(x: total - 100, y: 0), points[2], Point(x: total + 100, y: 0)],
                atEnd: true, lane: 0, mainLane: -1))
            let stroke = ContinuousStroke.buildStroke(points, options: .init(
                measures: [0, total / 2, total], rows: [], totalMetres: total,
                laneGapPx: 10, minRampPx: 0, cornerRadiusPx: 0, anchors: [], joinStart: start, joinEnd: end))
            let last = try #require(stroke.points.last)
            #expect(abs(stroke.points[0].y - 20) < 1e-9)
            #expect(abs(last.y + 10) < 1e-9)
        }
    }

    @Test func tangentJunctionBlendsButFortyFiveDegreeJunctionDoesNot() {
        func branch(angleDegrees: Double) -> [Point] {
            let angle = angleDegrees * .pi / 180
            return (0...4).map { index in
                let distance = Double(index) * 100
                return Point(x: distance * cos(angle), y: distance * sin(angle))
            }
        }
        let measures = (0...4).map { Double($0) * 100 }
        func joined(_ source: [Point]) -> (points: [Point], measures: [Double]) {
            ContinuousStroke.blendJunction(
                source,
                measures: measures,
                join: .init(
                    lane: 0,
                    incoming: Point(x: 1, y: 0),
                    outgoing: Point(x: 1, y: 0),
                    mainTangent: Point(x: 1, y: 0),
                    mainChain: []
                ),
                atEnd: false,
                intervalMetres: 500,
                gap: 3
            )
        }

        let tangent = branch(angleDegrees: 20)
        let blended = joined(tangent)
        #expect(blended.points != tangent)
        #expect(blended.points.count > tangent.count)
        #expect(blended.points.first == tangent.first && blended.points.last == tangent.last)
        #expect(blended.measures.first == measures.first && blended.measures.last == measures.last)
        let firstDirection = Point(
            x: blended.points[1].x - blended.points[0].x,
            y: blended.points[1].y - blended.points[0].y
        )
        #expect(abs(atan2(firstDirection.y, firstDirection.x) * 180 / .pi) <= 2)

        let steep = branch(angleDegrees: 45)
        let unblended = joined(steep)
        #expect(unblended.points == steep)
        #expect(unblended.measures == measures)
    }
    @Test func shallowSurveyedCurveRemainsAnInterpolationSupport() {
        let source = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10.1, y: 0.01),
                      Point(x: 20, y: 0), Point(x: 30, y: 0.2), Point(x: 40, y: 0.4), Point(x: 50, y: 0.6)]
        let measures = ContinuousStroke.cumulativeLengths(source)
        let curved = ContinuousStroke.smoothCentreline(source, measures: measures)
        for index in [1, 2] {
            let at = curved.measures.firstIndex(of: measures[index])
            #expect(at != nil)
            if let at { #expect(curved.points[at] == source[index]) }
        }
        let stroke = ContinuousStroke.buildStroke(source, options: .init(
            measures: measures, rows: [], totalMetres: measures.last!, laneGapPx: 0,
            minRampPx: 0, cornerRadiusPx: 3, anchors: []))
        #expect(stroke.points.contains { $0.x > 10 && $0.x < 10.2 && $0.y >= 0.009 })
    }

}
