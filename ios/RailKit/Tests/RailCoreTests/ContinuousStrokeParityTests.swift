import Foundation
import Testing

@testable import RailCore

/// `RailCore.ContinuousStroke` against `port-fixtures/continuous-stroke.json`.
///
/// Every expected answer is what `rail-stroke.js` returns today, produced by
/// calling its exported functions over real North American parts projected at
/// several zooms and over synthetic probes for the branches a real corridor
/// may not reach. Pixel space in, pixel space out, compared to 1e-6 px.
struct ContinuousStrokeParityTests {

    struct Fixture: Decodable {
        struct Row: Decodable {
            let from: Double
            let to: Double
            let lane: Double
        }
        struct Expected: Decodable {
            let points: [[Double]]
            let anchors: [[Double]]
        }
        struct FollowCase: Decodable {
            let from: Double
            let to: Double
            let canonFrom: Double
            let canonTo: Double
            let points: [[Double]]
            let measures: [Double]
        }
        struct Case: Decodable {
            let note: String
            let follows: [FollowCase]?
            let measures: [Double]?
            let points: [[Double]]
            let rows: [Row]
            let totalMetres: Double
            let laneGapPx: Double
            let minRampPx: Double
            let cornerRadiusPx: Double
            let anchors: [Int]
            let expected: Expected
        }
        struct Plateau: Decodable {
            let from: Double
            let to: Double
            let lane: Double
        }
        struct Sample: Decodable {
            let measure: Double
            let atWidth300: Double
            let atWidth0: Double
        }
        struct Profile: Decodable {
            let rows: [Row]
            let total: Double
            let profile: [Plateau]
            let samples: [Sample]
        }
        struct Projection: Decodable {
            let lonLat: [Double]
            let zoom: Double
            let px: [Double]
            let back: [Double]
        }
        struct Constants: Decodable {
            let LANE_RAMP_HALF_WIDTH_METRES: Double
            let LANE_PLATEAU_MIN_METRES: Double
            let FOLLOW_BLEND_METRES: Double
            let JOG_MIN_TURN_DEGREES: Double
            let JOG_MAX_TURN_DEGREES: Double
            let JOG_MAX_RUN_METRES: Double
            let JOG_MAX_NET_TURN_DEGREES: Double
            let JOG_MIN_LATERAL_METRES: Double
            let JOG_TAPER_METRES: Double
            let JOG_MIN_TAPER_METRES: Double
            let JOG_TAPER_SAMPLES: Int
            let FOLD_TURN_DEGREES: Double
            let FILLET_MIN_TURN_DEGREES: Double
            let FILLET_MAX_TURN_DEGREES: Double
            let FILLET_MAX_TANGENT_SHARE: Double
            let FILLET_STEP_DEGREES: Double
            let MITER_LIMIT: Double
        }
        let constants: Constants
        let profiles: [Profile]
        let projections: [Projection]
        let cases: [Case]
    }

    static func fixture() throws -> Fixture {
        try PortFixtures.decode(Fixture.self, "continuous-stroke.json")
    }

    static func rows(_ rows: [Fixture.Row]) -> [ContinuousStroke.LaneRow] {
        rows.map { ContinuousStroke.LaneRow(from: $0.from, to: $0.to, lane: $0.lane) }
    }

    @Test func constantsMatchTheJavaScript() throws {
        let c = try Self.fixture().constants
        #expect(ContinuousStroke.laneRampHalfWidthMetres == c.LANE_RAMP_HALF_WIDTH_METRES)
        #expect(ContinuousStroke.lanePlateauMinMetres == c.LANE_PLATEAU_MIN_METRES)
        #expect(ContinuousStroke.followBlendMetres == c.FOLLOW_BLEND_METRES)
        #expect(ContinuousStroke.jogMinTurnDegrees == c.JOG_MIN_TURN_DEGREES)
        #expect(ContinuousStroke.jogMaxTurnDegrees == c.JOG_MAX_TURN_DEGREES)
        #expect(ContinuousStroke.jogMaxRunMetres == c.JOG_MAX_RUN_METRES)
        #expect(ContinuousStroke.jogMaxNetTurnDegrees == c.JOG_MAX_NET_TURN_DEGREES)
        #expect(ContinuousStroke.jogMinLateralMetres == c.JOG_MIN_LATERAL_METRES)
        #expect(ContinuousStroke.jogTaperMetres == c.JOG_TAPER_METRES)
        #expect(ContinuousStroke.jogMinTaperMetres == c.JOG_MIN_TAPER_METRES)
        #expect(ContinuousStroke.jogTaperSamples == c.JOG_TAPER_SAMPLES)
        #expect(ContinuousStroke.foldTurnDegrees == c.FOLD_TURN_DEGREES)
        #expect(ContinuousStroke.filletMinTurnDegrees == c.FILLET_MIN_TURN_DEGREES)
        #expect(ContinuousStroke.filletMaxTurnDegrees == c.FILLET_MAX_TURN_DEGREES)
        #expect(ContinuousStroke.filletMaxTangentShare == c.FILLET_MAX_TANGENT_SHARE)
        #expect(ContinuousStroke.filletStepDegrees == c.FILLET_STEP_DEGREES)
        #expect(ContinuousStroke.miterLimit == c.MITER_LIMIT)
    }

    @Test func projectionRoundTrips() throws {
        for probe in try Self.fixture().projections {
            let px = ContinuousStroke.project(lon: probe.lonLat[0], lat: probe.lonLat[1], zoom: probe.zoom)
            #expect(abs(px.x - probe.px[0]) < 1e-6)
            #expect(abs(px.y - probe.px[1]) < 1e-6)
            let back = ContinuousStroke.unproject(px, zoom: probe.zoom)
            #expect(abs(back.lon - probe.back[0]) < 1e-9)
            #expect(abs(back.lat - probe.back[1]) < 1e-9)
        }
    }

    @Test func laneProfilesAndKernelMatch() throws {
        for profile in try Self.fixture().profiles {
            let plateaus = ContinuousStroke.laneProfile(rows: Self.rows(profile.rows), total: profile.total)
            #expect(plateaus.count == profile.profile.count)
            for (held, expected) in zip(plateaus, profile.profile) {
                #expect(abs(held.from - expected.from) < 1e-9)
                #expect(abs(held.to - expected.to) < 1e-9)
                #expect(held.lane == expected.lane)
            }
            for sample in profile.samples {
                let smooth = ContinuousStroke.laneAt(profile: plateaus, measure: sample.measure, width: 300)
                let step = ContinuousStroke.laneAt(profile: plateaus, measure: sample.measure, width: 0)
                #expect(abs(smooth - sample.atWidth300) < 1e-9, Comment(rawValue: "\(profile.rows.count) rows at \(sample.measure)"))
                #expect(abs(step - sample.atWidth0) < 1e-9)
            }
        }
    }

    @Test func strokesMatchTheJavaScript() throws {
        for probe in try Self.fixture().cases {
            let points = probe.points.map { ContinuousStroke.Point(x: $0[0], y: $0[1]) }
            let stroke = ContinuousStroke.buildStroke(
                points,
                options: .init(
                    measures: probe.measures ?? [],
                    rows: Self.rows(probe.rows), totalMetres: probe.totalMetres,
                    laneGapPx: probe.laneGapPx, minRampPx: probe.minRampPx,
                    cornerRadiusPx: probe.cornerRadiusPx, anchors: probe.anchors,
                    follows: (probe.follows ?? []).map { follow in
                        ContinuousStroke.Follow(
                            from: follow.from, to: follow.to,
                            canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                            points: follow.points.map { ContinuousStroke.Point(x: $0[0], y: $0[1]) },
                            measures: follow.measures)
                    }))
            #expect(stroke.points.count == probe.expected.points.count, Comment(rawValue: probe.note))
            var worst = 0.0
            for (held, expected) in zip(stroke.points, probe.expected.points) {
                worst = max(worst, abs(held.x - expected[0]), abs(held.y - expected[1]))
            }
            #expect(worst < 1e-6, Comment(rawValue: "\(probe.note): worst vertex \(worst) px"))
            #expect(stroke.anchors.count == probe.expected.anchors.count, Comment(rawValue: probe.note))
            for (held, expected) in zip(stroke.anchors, probe.expected.anchors) {
                #expect(abs(held.x - expected[0]) < 1e-6, Comment(rawValue: probe.note))
                #expect(abs(held.y - expected[1]) < 1e-6, Comment(rawValue: probe.note))
            }
        }
    }
}
