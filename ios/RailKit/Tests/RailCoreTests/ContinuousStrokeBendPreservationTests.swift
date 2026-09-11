import Foundation
import Testing

@testable import RailCore

struct ContinuousStrokeBendPreservationTests {
    typealias Point = ContinuousStroke.Point

    @Test func innerHairpinCannotCrossItsOppositeLeg() {
        // Surveyed Hakone window at app z13, translated to a local origin.
        let survey = [
            Point(x: -1.773326222, y: -3.090848045), Point(x: -2.239360000, y: -1.807039505),
            Point(x: -2.821902222, y: -0.451911359), Point(x: -3.113173333, y: 0.403957414),
            Point(x: -3.287936000, y: 0.903213613), Point(x: -3.404444444, y: 1.616436007),
            Point(x: -3.462698667, y: 2.258335410), Point(x: -3.404444444, y: 3.185522179),
            Point(x: -3.113173333, y: 4.540638630), Point(x: -2.763648000, y: 5.539143457),
            Point(x: -2.763648000, y: 6.252360136), Point(x: -3.695715555, y: 5.396500016),
            Point(x: -4.394766222, y: 4.683282282), Point(x: -4.977308444, y: 4.326673086),
            Point(x: -5.326833778, y: 4.112707462), Point(x: -5.734613333, y: 3.827419841),
            Point(x: -6.025884445, y: 3.684775978), Point(x: -6.433664000, y: 3.542132079),
            Point(x: -6.899697778, y: 3.328166165), Point(x: -7.249223111, y: 3.185522179),
            Point(x: -8.530816000, y: 2.828912059), Point(x: -10.278442667, y: 2.614945882),
            Point(x: -11.909560889, y: 2.614945882)]
        func side(_ a: Point, _ b: Point, _ c: Point) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for scale in [0.5, 1.0, 2, 4] {
            for reflection in [-1.0, 1] {
                let source = survey.map { Point(x: $0.x * scale, y: $0.y * scale * reflection) }
                let measures = ContinuousStroke.cumulativeLengths(source)
                let stroke = ContinuousStroke.buildStroke(source, options: .init(
                    measures: measures, rows: [.init(from: 0, to: measures.last!, lane: reflection * 0.5)],
                    totalMetres: measures.last!, laneGapPx: 2.7, minRampPx: 24,
                    cornerRadiusPx: 3.6, minCornerRadiusPx: 3, anchors: [0, source.count - 1],
                    enforceMinimumCornerRadius: true))
                #expect(ContinuousStroke.distanceToPolyline(source[10], stroke.points) < 0.5 * scale)
                for i in 1..<stroke.points.count {
                    guard i + 2 < stroke.points.count else { continue }
                    for j in (i + 2)..<stroke.points.count {
                        let a = stroke.points[i - 1], b = stroke.points[i]
                        let c = stroke.points[j - 1], d = stroke.points[j]
                        #expect(!(side(a, b, c) * side(a, b, d) < -1e-12
                                  && side(c, d, a) * side(c, d, b) < -1e-12))
                    }
                }
            }
        }
    }

    @Test func compressedHairpinLanesKeepTheirOrder() {
        let points = [Point(x: -1, y: 0), Point(x: 0, y: 0), Point(x: -0.8, y: 0.6)]
        let lengths = ContinuousStroke.cumulativeLengths(points)
        var previous = 0.0
        for lane in 1...16 {
            let distance = Double(lane) * 2.7
            let constrained = ContinuousStroke.constrainedInnerBendDistances(
                points, support: [0, 1, 2], lengths: lengths, distances: [distance, distance, distance],
                preserveStart: true, preserveEnd: true)
            #expect(constrained[1] > previous && constrained[1] < 0.2)
            #expect(constrained.first == distance && constrained.last == distance)
            let outer = ContinuousStroke.constrainedInnerBendDistances(
                points, support: [0, 1, 2], lengths: lengths, distances: [-distance, -distance, -distance])
            #expect(outer == [-distance, -distance, -distance])
            let free = ContinuousStroke.constrainedInnerBendDistances(
                points, support: [0, 1, 2], lengths: lengths, distances: [distance, distance, distance])
            #expect(free[0] < 0.3 && free[2] < 0.3)
            previous = constrained[1]
        }
    }

    /// Orange's reversed shared-track correspondence inserts a collinear
    /// sample 2.233 m after each canonical bend (about 0.154 px at z12).
    /// Offset miters used to overshoot these samples; repeated fold removal
    /// then deleted the real bends together with the added samples.
    @Test func nearBendSamplesCannotEraseTheCurveAcrossZoomAndLaneSides() {
        for scale in [0.25, 0.5, 1.0, 2, 4] {
            for winding in [-1.0, 1] {
                let coarse = (0...12).map { index -> Point in
                    let angle = Double(index) * .pi / 12
                    return Point(x: 100 * scale * sin(angle),
                                 y: winding * 100 * scale * (1 - cos(angle)))
                }
                var dense: [Point] = []
                for index in coarse.indices {
                    dense.append(coarse[index])
                    if index + 1 < coarse.count {
                        let a = coarse[index], b = coarse[index + 1]
                        let t = 0.01 / hypot(b.x - a.x, b.y - a.y)
                        dense.append(Point(x: a.x + (b.x - a.x) * t,
                                           y: a.y + (b.y - a.y) * t))
                    }
                }
                for lane in [-7.5, -3.0, 1, 3, 7.5] {
                    let distance = lane * 2.7
                    let reference = ContinuousStroke.offsetPolyline(coarse) { _ in distance }
                    let measures = ContinuousStroke.cumulativeLengths(dense)
                    let total = measures.last!
                    let result = ContinuousStroke.buildStroke(dense, options: .init(
                        measures: measures, rows: [.init(from: 0, to: total, lane: lane)],
                        totalMetres: total, laneGapPx: 2.7, minRampPx: 24,
                        cornerRadiusPx: 0, anchors: [0, dense.count - 1],
                        enforceMinimumCornerRadius: true))
                    // The full bent reference must remain on the drawn ink;
                    // endpoints alone would let a straight chord pass this check.
                    for bend in reference {
                        #expect(ContinuousStroke.distanceToPolyline(bend, result.points) < 0.126)
                    }
                    #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy { $0 <= $1 })
                    #expect(result.anchors == [result.points.first!, result.points.last!])
                }
            }
        }
    }

    @Test func stableTangentsKeepInteriorAnchorsAndBothSharedJoins() {
        let points = [Point(x: -100, y: 0), Point(x: 0, y: 0),
                      Point(x: 0.01, y: 0.01), Point(x: 100, y: 100)]
        let join = ContinuousStroke.Join(lane: 1, incoming: Point(x: 1, y: 0),
                                        outgoing: Point(x: 0, y: 1))
        let result = ContinuousStroke.offsetPolyline(
            points, joinStart: join, joinEnd: join, stableSegments: true) { _ in 3 }
        let legacy = ContinuousStroke.offsetPolyline(points, joinStart: join, joinEnd: join) { _ in 3 }
        #expect(result.count == points.count)
        #expect(result.first == legacy.first)
        #expect(result.last == legacy.last)
        let stroke = ContinuousStroke.buildStroke(points, options: .init(
            rows: [.init(from: 0, to: 1_000, lane: 1)], totalMetres: 1_000,
            laneGapPx: 3, minRampPx: 24, cornerRadiusPx: 3.6,
            minCornerRadiusPx: 3, anchors: [0, 1, 2, 3], enforceMinimumCornerRadius: true))
        for anchor in stroke.anchors {
            #expect(ContinuousStroke.distanceToPolyline(anchor, stroke.points) < 1e-8)
        }
    }

    @Test func surveyedHairpinSurvivesCascadingNeighbourFolds() {
        // Hakone at app z13: the 133-degree surveyed apex must survive even
        // when inner-lane overlap reverses the neighbouring vertices.
        let original = [
            Point(x: -3.404444444, y: 1.616436007), Point(x: -3.462698667, y: 2.258335410),
            Point(x: -3.404444444, y: 3.185522179), Point(x: -3.113173333, y: 4.540638630),
            Point(x: -2.763648000, y: 5.539143457), Point(x: -2.763648000, y: 6.252360136),
            Point(x: -3.695715555, y: 5.396500016), Point(x: -4.394766222, y: 4.683282282),
            Point(x: -4.977308444, y: 4.326673086), Point(x: -5.326833778, y: 4.112707462)]
        let offset = [
            Point(x: -4.754444445, y: 1.506897326), Point(x: -4.812698667, y: 2.252421557),
            Point(x: -4.754444445, y: 3.328969754), Point(x: -4.415275378, y: 4.906927760),
            Point(x: -4.113648000, y: 5.768600332), Point(x: -4.085364010, y: 3.146930731),
            Point(x: -3.809524453, y: 3.431099476), Point(x: -3.555277431, y: 3.617608939),
            Point(x: -4.227276007, y: 3.203857154), Point(x: -4.630475160, y: 2.955605972)]
        for scale in [0.5, 1.0, 2] {
            for reflection in [-1.0, 1] {
                let source = original.map { Point(x: $0.x * scale, y: $0.y * scale * reflection) }
                let shifted = offset.map { Point(x: $0.x * scale, y: $0.y * scale * reflection) }
                let result = ContinuousStroke.removeOffsetFolds(shifted, original: source, preserveBends: true)
                #expect(result.map[5] >= 0)
                #expect(result.points.contains(shifted[5]))
                #expect(result.points.first == shifted.first && result.points.last == shifted.last)
                #expect(result.map.filter { $0 >= 0 } == Array(result.points.indices))
            }
        }
    }

    @Test func overlappingInnerCornersRetainTheDominantSurveyedBend() {
        // Miami DML at app z13: the 6.192 m connector is only 0.353 px.
        // Unlike Orange's collinear samples these are two real turns, so
        // stable tangent support alone cannot prevent their inner overlap.
        let original = [
            Point(x: -0.433396840, y: 12.258449098), Point(x: 0.677791799, y: 19.707204146),
            Point(x: 3.790065004, y: 24.153348835), Point(x: 4.048965632, y: 24.410001124),
            Point(x: 6.955986172, y: 26.682990085), Point(x: 7.303511254, y: 26.742479105),
            Point(x: 30.641720889, y: 27.541844150)]
        let offset = [
            Point(x: -0.429009881, y: 12.134365803), Point(x: 0.616944393, y: 19.145828038),
            Point(x: 3.435434839, y: 23.172279285), Point(x: 3.656240109, y: 23.398492538),
            Point(x: 6.177645273, y: 25.363366258), Point(x: 6.091978464, y: 25.348701894),
            Point(x: 29.396286704, y: 26.146905771)]
        let result = ContinuousStroke.removeOffsetFolds(offset, original: original, preserveBends: true)
        #expect(result.map[4] >= 0) // retain the real 28-degree turn
        #expect(result.map[5] == -1) // resolve its weaker 8-degree overlap
        #expect(result.points.contains(offset[4]))
        for index in 1..<(result.points.count - 1) {
            #expect(abs(ContinuousStroke.turnAt(result.points, index)) < .pi * 150 / 180)
        }
        let anchored = ContinuousStroke.removeOffsetFolds(
            offset, original: original, preserveBends: true, anchors: [4, 5])
        #expect(anchored.map[4] >= 0 && anchored.map[5] >= 0)
    }

    @Test func surveyedCompoundBendsAndNarrowReturnsNeverSelfIntersect() {
        // Production source windows: Hakone's 168-degree return approach,
        // and the Shinkansen's adjacent 77/50-degree station approach turns.
        let fixtures: [(points: [Point], lane: Double)] = [
            (points: [
                Point(x: 0.000000000, y: 0.000000000),
                Point(x: -0.757304889, y: 0.285280376),
                Point(x: -1.281592889, y: 0.641880649),
                Point(x: -2.155406222, y: 1.497720405),
                Point(x: -3.029219556, y: 2.710157894),
                Point(x: -3.611761778, y: 3.565994591),
                Point(x: -4.019541333, y: 4.493149584),
                Point(x: -4.194304000, y: 5.206344722),
                Point(x: -4.077795556, y: 6.276135780),
                Point(x: -3.262236445, y: 7.203286430),
                Point(x: -2.271914667, y: 8.273073795),
                Point(x: -1.106830222, y: 9.414178138),
                Point(x: 0.000000000, y: 10.412642592),
                Point(x: 0.815559111, y: 11.339786613),
                Point(x: 1.980643556, y: 12.195610545),
                Point(x: 2.796202667, y: 12.552203476),
                Point(x: 3.553507556, y: 12.908796188),
                Point(x: 4.776846222, y: 13.194070199),
                Point(x: -1.048576000, y: 13.122751709),
                Point(x: -2.679694222, y: 13.336707151),
                Point(x: -4.369066667, y: 13.265388679),
                Point(x: -6.000184889, y: 13.408025615),
                Point(x: -7.806065778, y: 13.764617799),
                Point(x: -8.912896000, y: 14.406483176),
                Point(x: -10.369251556, y: 14.905711311),
                Point(x: -11.709098667, y: 15.618893613),
            ], lane: 0.5),
            (points: [
                Point(x: 0.000000000, y: 0.000000000),
                Point(x: 2.679694222, y: -14.333551683),
                Point(x: 4.252558222, y: -22.002149063),
                Point(x: 4.338550911, y: -22.420295249),
                Point(x: 4.597861066, y: -23.684716908),
                Point(x: 4.857059771, y: -24.954485913),
                Point(x: 5.116178869, y: -26.228075280),
                Point(x: 5.375250201, y: -27.503958012),
                Point(x: 5.474966750, y: -27.995362425),
                Point(x: 5.590556043, y: -28.788332298),
                Point(x: 5.591276338, y: -28.793273079),
                Point(x: 5.824062430, y: -29.736057644),
                Point(x: 5.887087133, y: -30.055629353),
                Point(x: 6.138917123, y: -31.330707753),
                Point(x: 6.390826721, y: -32.601971400),
                Point(x: 6.658457600, y: -33.849258733),
                Point(x: 7.085864454, y: -33.857801827),
                Point(x: 7.653297506, y: -33.208482658),
                Point(x: 8.502827696, y: -32.232144863),
                Point(x: 8.727183863, y: -31.973616860),
                Point(x: 8.913568773, y: -32.893368646),
                Point(x: 9.166874738, y: -34.141293454),
                Point(x: 9.420196627, y: -35.388457458),
                Point(x: 9.673502593, y: -36.636387701),
                Point(x: 9.926760794, y: -37.886611237),
                Point(x: 10.179939388, y: -39.140655135),
                Point(x: 10.433006531, y: -40.400046478),
                Point(x: 10.928492089, y: -42.872720762),
                Point(x: 11.636863431, y: -45.768285955),
                Point(x: 13.308177067, y: -51.768746352),
            ], lane: 2.5),
            // Ansan connecting line at app zoom 11.
            (points: [
                Point(x: 0.000000000, y: 0.000000000),
                Point(x: -0.205054862, y: 0.715271972),
                Point(x: -0.453217849, y: 1.341360798),
                Point(x: -0.740265529, y: 1.885226230),
                Point(x: -0.926824676, y: 2.156791902),
                Point(x: -1.414121244, y: 2.729037435),
                Point(x: -2.066714169, y: 3.329297552),
                Point(x: -2.469833387, y: 3.627412342),
                Point(x: -3.429134791, y: 4.219794545),
                Point(x: -2.989752320, y: 4.771888800),
                Point(x: -2.400510862, y: 4.725194347),
                Point(x: -0.484383858, y: 4.320874654),
                Point(x: -0.019952071, y: 4.200017993),
                Point(x: 0.790218524, y: 3.900805743),
                Point(x: 1.461889707, y: 3.511865470),
                Point(x: 2.053024427, y: 2.995657261),
                Point(x: 2.554302009, y: 2.364082399),
            ], lane: -0.5),
            // Ansan connecting line at app zoom 12.
            (points: [
                Point(x: 0.000000000, y: 0.000000000),
                Point(x: -0.410109724, y: 1.430543944),
                Point(x: -0.906435698, y: 2.682721596),
                Point(x: -1.480531058, y: 3.770452460),
                Point(x: -1.853649351, y: 4.313583805),
                Point(x: -2.828242489, y: 5.458074870),
                Point(x: -4.133428338, y: 6.658595104),
                Point(x: -4.939666773, y: 7.254824684),
                Point(x: -6.858269582, y: 8.439589090),
                Point(x: -5.979504640, y: 9.543777601),
                Point(x: -4.801021724, y: 9.450388694),
                Point(x: -0.968767716, y: 8.641749308),
                Point(x: -0.039904142, y: 8.400035986),
                Point(x: 1.580437049, y: 7.801611487),
                Point(x: 2.923779413, y: 7.023730940),
                Point(x: 4.106048853, y: 5.991314522),
                Point(x: 5.108604018, y: 4.728164798),
            ], lane: -0.5),
        ]
        func side(_ a: Point, _ b: Point, _ c: Point) -> Double {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for fixture in fixtures {
            for reflection in [-1.0, 1] {
                let source = fixture.points.map { Point(x: $0.x, y: $0.y * reflection) }
                let measures = ContinuousStroke.cumulativeLengths(source)
                let result = ContinuousStroke.buildStroke(source, options: .init(
                    measures: measures, rows: [.init(from: 0, to: measures.last!, lane: fixture.lane * reflection)],
                    totalMetres: measures.last!, laneGapPx: 2.7, minRampPx: 24,
                    cornerRadiusPx: 3.6, minCornerRadiusPx: 3, anchors: [0, source.count - 1],
                    enforceMinimumCornerRadius: true))
                #expect(zip(result.measures, result.measures.dropFirst()).allSatisfy { $0 <= $1 })
                for i in 1..<result.points.count {
                    guard i + 2 < result.points.count else { continue }
                    for j in (i + 2)..<result.points.count {
                        let a = result.points[i - 1], b = result.points[i]
                        let c = result.points[j - 1], d = result.points[j]
                        #expect(!(side(a, b, c) * side(a, b, d) < -1e-12
                                  && side(c, d, a) * side(c, d, b) < -1e-12))
                    }
                }
            }
        }
    }
}
