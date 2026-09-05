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
            let measures: [Double]
            let anchorMeasures: [Double]
        }
        struct FollowCase: Decodable {
            let from: Double
            let to: Double
            let canonFrom: Double
            let canonTo: Double
            let points: [[Double]]
            let measures: [Double]
        }
        struct JoinCase: Decodable {
            let lane: Double
            let incoming: [Double]
            let outgoing: [Double]
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
            let minCornerRadiusPx: Double?
            let anchors: [Int]
            let joinStart: JoinCase?
            let joinEnd: JoinCase?
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
            let joinStart: Double?
            let joinEnd: Double?
            let profile: [Plateau]
            let samples: [Sample]
        }
        struct Projection: Decodable {
            let lonLat: [Double]
            let zoom: Double
            let px: [Double]
            let back: [Double]
        }
        struct Slice: Decodable {
            let caseIndex: Int
            let from: Double
            let to: Double
            let expected: [[Double]]
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
            let STROKE_SIMPLIFY_TOLERANCE_PX: Double
            let MITER_LIMIT: Double
            let LANE_JOIN_EXTENT_METRES: Double
        }
        struct WindowSpanRow: Decodable {
            let from: Double
            let to: Double
            let groupId: String
        }
        struct RangeRow: Decodable {
            let from: Double
            let to: Double
        }
        struct FamilyPartitionExpected: Decodable {
            let base: [RangeRow]
            let family: [WindowSpanRow]
        }
        struct FamilyPartitionCase: Decodable {
            let note: String
            let totalMetres: Double
            let measureStart: Double?
            let measureEnd: Double?
            let tenantWindows: [WindowSpanRow]
            let landlordWindows: [WindowSpanRow]
            let expected: FamilyPartitionExpected
        }
        struct ClipToComplementCase: Decodable {
            let note: String
            let ranges: [RangeRow]
            let tenantWindows: [WindowSpanRow]
            let expected: [RangeRow]
        }
        let constants: Constants
        let profiles: [Profile]
        let projections: [Projection]
        let cases: [Case]
        let slices: [Slice]
        let familyPartitions: [FamilyPartitionCase]
        let clipsToComplement: [ClipToComplementCase]
    }

    static func fixture() throws -> Fixture {
        try PortFixtures.decode(Fixture.self, "continuous-stroke.json")
    }

    static func rows(_ rows: [Fixture.Row]) -> [ContinuousStroke.LaneRow] {
        rows.map { ContinuousStroke.LaneRow(from: $0.from, to: $0.to, lane: $0.lane) }
    }

    static func points(_ points: [[Double]]) -> [ContinuousStroke.Point] {
        points.map { ContinuousStroke.Point(x: $0[0], y: $0[1]) }
    }

    static func join(_ join: Fixture.JoinCase?) -> ContinuousStroke.Join? {
        guard let join else { return nil }
        return ContinuousStroke.Join(
            lane: join.lane,
            incoming: ContinuousStroke.Point(x: join.incoming[0], y: join.incoming[1]),
            outgoing: ContinuousStroke.Point(x: join.outgoing[0], y: join.outgoing[1]))
    }

    /// The options one fixture case asks for, in one place: every test below
    /// builds its stroke through this, so a new option cannot be honoured by
    /// one test and forgotten by the next.
    static func options(
        _ probe: Fixture.Case, joined: Bool = true, floored: Bool = true,
        radiusPx: Double? = nil
    ) -> ContinuousStroke.Options {
        .init(
            measures: probe.measures ?? [],
            rows: rows(probe.rows), totalMetres: probe.totalMetres,
            laneGapPx: probe.laneGapPx, minRampPx: probe.minRampPx,
            cornerRadiusPx: radiusPx ?? probe.cornerRadiusPx,
            minCornerRadiusPx: floored ? (probe.minCornerRadiusPx ?? 0) : 0,
            anchors: probe.anchors,
            follows: (probe.follows ?? []).map { follow in
                ContinuousStroke.Follow(
                    from: follow.from, to: follow.to,
                    canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                    points: points(follow.points), measures: follow.measures)
            },
            joinStart: joined ? join(probe.joinStart) : nil,
            joinEnd: joined ? join(probe.joinEnd) : nil)
    }

    static func stroke(
        _ probe: Fixture.Case, joined: Bool = true, floored: Bool = true,
        radiusPx: Double? = nil
    ) -> ContinuousStroke.Stroke {
        ContinuousStroke.buildStroke(
            points(probe.points),
            options: options(probe, joined: joined, floored: floored, radiusPx: radiusPx))
    }

    /// The deflection at interior vertex `index`, in degrees.
    static func turnDegrees(_ points: [ContinuousStroke.Point], _ index: Int) -> Double {
        let ax = points[index].x - points[index - 1].x
        let ay = points[index].y - points[index - 1].y
        let bx = points[index + 1].x - points[index].x
        let by = points[index + 1].y - points[index].y
        let la = hypot(ax, ay)
        let lb = hypot(bx, by)
        guard la > 0, lb > 0 else { return 0 }
        return acos(max(-1, min(1, (ax * bx + ay * by) / (la * lb)))) * 180 / Double.pi
    }

    // MARK: - properties of the DRAWN output
    //
    // The parity tests above pin the stroke against the JS answer coordinate
    // by coordinate; these two pin what that answer has to BE, whatever both
    // ports agree it is. They are the tests a change to the fillet cannot
    // satisfy by regenerating the fixture, and `continuous-stroke-geometry.
    // test.mjs` asserts the identical two properties over the identical cases
    // on the JS side.

    /// Nothing malformed reaches the renderer: no NaN, no measure that runs
    /// backwards, no zero-length edge.
    @Test func everyStrokeIsWellFormed() throws {
        for (index, probe) in try Self.fixture().cases.enumerated() {
            let stroke = Self.stroke(probe)
            let where_ = "case \(index): \(probe.note)"
            for point in stroke.points + stroke.anchors {
                #expect(point.x.isFinite && point.y.isFinite, "\(where_) — non-finite point")
            }
            for measure in stroke.measures + stroke.anchorMeasures {
                #expect(measure.isFinite, "\(where_) — non-finite measure")
            }
            #expect(stroke.measures.count == stroke.points.count, "\(where_) — measure count")
            var backwards = -1
            for at in 1..<stroke.measures.count
            where stroke.measures[at] < stroke.measures[at - 1] && backwards < 0 {
                backwards = at
            }
            #expect(backwards < 0, "\(where_) — measure runs backwards at \(backwards)")
            // A part of fewer than two distinct vertices degenerates, on
            // purpose, to two copies of its only point (see buildStroke's
            // early return); every other stroke owes us distinct neighbours.
            guard stroke.points.count > 2 else { continue }
            var duplicate = -1
            for at in 1..<stroke.points.count
            where stroke.points[at].x == stroke.points[at - 1].x
                && stroke.points[at].y == stroke.points[at - 1].y && duplicate < 0 {
                duplicate = at
            }
            #expect(duplicate < 0, "\(where_) — duplicate point at \(duplicate)")
        }
    }

    /// A rounded corner is sampled at most ``filletStepDegrees`` of turn at a
    /// time — the promise the sample count has always made, and the one the
    /// quadratic Bézier this fillet used to draw could not keep: sampled
    /// uniformly in u it concentrated the rotation mid-arc, reaching 14.3
    /// degrees at a 90-degree corner, 19.7 at 120, and 28.8 on the shipped
    /// `cta-orange-line` case.
    ///
    /// Two kinds of vertex are exempt, and both are geometry the fillet is
    /// forbidden to touch rather than geometry it drew badly: a surveyed
    /// reversal (turn >= ``filletMaxTurnDegrees`` — a switchback is not a
    /// corner) and a station anchor, whose arc is drawn THROUGH the platform
    /// vertex and therefore meets the edges either side at an angle of its
    /// own. They are excluded by POSITION, within two radii, because the
    /// output has no index back to the input.
    @Test func roundedCornersHonourTheSamplingStep() throws {
        let ceiling = ContinuousStroke.filletStepDegrees + 0.5
        for (index, probe) in try Self.fixture().cases.enumerated() {
            guard probe.cornerRadiusPx > 0 else { continue }
            let stroke = Self.stroke(probe)
            guard stroke.points.count >= 3 else { continue }
            // The polyline the fillet pass actually saw: the identical build
            // with the rounding switched off, which is exactly what
            // `fillet` receives (it returns its input unchanged at radius 0).
            let pre = Self.stroke(probe, radiusPx: 0).points
            var exempt = stroke.anchors
            if pre.count >= 3 {
                for at in 1..<(pre.count - 1)
                where Self.turnDegrees(pre, at) >= ContinuousStroke.filletMaxTurnDegrees {
                    exempt.append(pre[at])
                }
            }
            let reach = 2 * probe.cornerRadiusPx
            var worst = 0.0
            var worstAt = -1
            for at in 1..<(stroke.points.count - 1) {
                let vertex = stroke.points[at]
                if exempt.contains(where: { hypot($0.x - vertex.x, $0.y - vertex.y) <= reach }) {
                    continue
                }
                let turn = Self.turnDegrees(stroke.points, at)
                if turn > worst {
                    worst = turn
                    worstAt = at
                }
            }
            #expect(
                worst <= ceiling,
                "case \(index): \(probe.note) — \(worst)° facet at vertex \(worstAt)")
        }
    }

    static func find(_ note: String, in fixture: Fixture) throws -> Fixture.Case {
        guard let probe = fixture.cases.first(where: { $0.note == note }) else {
            Issue.record("fixture case not found: \(note)")
            throw CocoaError(.fileNoSuchFile)
        }
        return probe
    }

    // MARK: - measuring a drawn corner
    //
    // The radius a corner PRESENTS, sampled ± `window` px of arc length either
    // side of a vertex rather than through its two neighbouring vertices: at
    // the density a rail survey is drawn at, three adjacent vertices measure
    // how finely the line was sampled, not how sharply it turns.

    static func cumulative(_ points: [ContinuousStroke.Point]) -> [Double] {
        var out = [0.0]
        for index in 1..<points.count {
            out.append(
                out[index - 1]
                    + hypot(points[index].x - points[index - 1].x,
                            points[index].y - points[index - 1].y))
        }
        return out
    }

    static func pointAt(
        _ points: [ContinuousStroke.Point], _ cumulative: [Double], _ s: Double
    ) -> ContinuousStroke.Point {
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = Int((Double(low + high) / 2).rounded(.up))
            if cumulative[mid] <= s { low = mid } else { high = mid - 1 }
        }
        let index = min(low, points.count - 2)
        let span = cumulative[index + 1] - cumulative[index]
        let t = span > 0 ? (s - cumulative[index]) / span : 0
        let a = points[index]
        let b = points[index + 1]
        return ContinuousStroke.Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// The smallest windowed radius anywhere on a stroke, in pixels.
    static func minimumWindowedRadius(
        _ points: [ContinuousStroke.Point], window: Double
    ) -> Double {
        guard points.count >= 3 else { return .infinity }
        let cum = cumulative(points)
        let total = cum[cum.count - 1]
        var smallest = Double.infinity
        for index in 1..<(points.count - 1) {
            let s = cum[index]
            if s - window < 0 || s + window > total { continue }
            let a = pointAt(points, cum, s - window)
            let b = points[index]
            let c = pointAt(points, cum, s + window)
            let ax = b.x - a.x, ay = b.y - a.y, bx = c.x - b.x, by = c.y - b.y
            let cross = ax * by - ay * bx
            if abs(cross) < 1e-15 { continue }
            let radius = hypot(ax, ay) * hypot(bx, by) * hypot(c.x - a.x, c.y - a.y)
                / (2 * abs(cross))
            smallest = min(smallest, radius)
        }
        return smallest
    }

    static func worstTurnDegrees(_ points: [ContinuousStroke.Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        var worst = 0.0
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            let ax = b.x - a.x, ay = b.y - a.y, bx = c.x - b.x, by = c.y - b.y
            worst = max(worst, abs(atan2(ax * by - ay * bx, ax * bx + ay * by)) * 180 / .pi)
        }
        return worst
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
        #expect(
            ContinuousStroke.strokeSimplifyTolerancePx == c.STROKE_SIMPLIFY_TOLERANCE_PX)
        #expect(ContinuousStroke.miterLimit == c.MITER_LIMIT)
        #expect(ContinuousStroke.laneJoinExtentMetres == c.LANE_JOIN_EXTENT_METRES)
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
            let plateaus = ContinuousStroke.laneProfile(
                rows: Self.rows(profile.rows), total: profile.total,
                joinStart: profile.joinStart, joinEnd: profile.joinEnd)
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
            let stroke = Self.stroke(probe)
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
            #expect(stroke.measures.count == probe.expected.measures.count, Comment(rawValue: probe.note))
            for index in 1..<stroke.measures.count {
                #expect(
                    stroke.measures[index] >= stroke.measures[index - 1],
                    Comment(rawValue: "\(probe.note): measures decreased at \(index)"))
            }
            var worstMeasure = 0.0
            for (held, expected) in zip(stroke.measures, probe.expected.measures) {
                worstMeasure = max(worstMeasure, abs(held - expected))
            }
            #expect(worstMeasure < 1e-6, Comment(rawValue: "\(probe.note): worst measure \(worstMeasure)"))
            #expect(
                stroke.anchorMeasures.count == probe.expected.anchorMeasures.count,
                Comment(rawValue: probe.note))
            for (held, expected) in zip(stroke.anchorMeasures, probe.expected.anchorMeasures) {
                #expect(abs(held - expected) < 1e-6, Comment(rawValue: probe.note))
            }
        }
    }

    @Test func slicesMatchTheJavaScript() throws {
        let fixture = try Self.fixture()
        for slice in fixture.slices {
            let probe = fixture.cases[slice.caseIndex]
            let stroke = Self.stroke(probe)
            let sliced = ContinuousStroke.slice(
                points: stroke.points, measures: stroke.measures, from: slice.from, to: slice.to)
            let label = "case \(slice.caseIndex) (\(probe.note)) slice \(slice.from)…\(slice.to)"
            #expect(sliced.count == slice.expected.count, Comment(rawValue: label))
            var worst = 0.0
            for (held, expected) in zip(sliced, slice.expected) {
                worst = max(worst, abs(held.x - expected[0]), abs(held.y - expected[1]))
            }
            #expect(worst < 1e-6, Comment(rawValue: "\(label): worst vertex \(worst) px"))
        }
    }

    /// A corridor follow onto a canonical with its own seam jog: the
    /// canonical must be tapered before any follower draws from it, or the
    /// jog reappears untapered on the follower. Not just JS/Swift parity —
    /// both ports could carry the same bug — so this checks the actual
    /// geometric property directly: no interior turn above 15° anywhere in
    /// the follower's output.
    @Test func followOntoJoggedCanonicalIsTapered() throws {
        let note = "corridor follow onto a jogged canonical: the canonical's own seam jog is tapered before any follower draws from it"
        let fixture = try Self.fixture()
        let probe = try Self.find(note, in: fixture)
        let worst = Self.worstTurnDegrees(Self.stroke(probe).points)
        #expect(worst < 15, Comment(rawValue: "worst turn \(worst)°"))
    }

    /// THE MINIMUM RADIUS IS AN OPERATION, NOT A PROMISE.
    ///
    /// Four vertices carry 70° of turn between two 60 px edges. Rounded one at
    /// a time, each fillet may borrow only 0.45 of the tiny edge beside it, so
    /// the corner the reader sees is a bare kink whatever radius was asked
    /// for. Rounded as ONE corner it reaches the full radius.
    ///
    /// Two spacings, because `buildStroke` now decimates to
    /// ``strokeSimplifyTolerancePx`` BEFORE it rounds anything:
    ///
    ///   * 0.03 px apart the four vertices are far under that tolerance and
    ///     are removed outright — a split that fine is a survey artefact, not
    ///     a corner, and the floored and unfloored answers are now the same
    ///     one, both reaching the radius;
    ///   * 0.3 px apart they survive decimation and still starve a per-vertex
    ///     fillet (0.45 of 0.3 px is 0.135 px), which is the case that holds
    ///     the run merge to its job.
    ///
    /// Not a parity check — both ports could carry the same bug — so this
    /// measures the radius the OUTPUT actually presents, sampled ±0.5 px of
    /// arc length either side of every vertex, and compares the floored answer
    /// against the unfloored one built from the same points.
    @Test func splitCornerReachesTheMinimumRadius() throws {
        let note = "a corner split coarser than the simplification tolerance is still rounded as ONE corner"
        let fixture = try Self.fixture()
        let probe = try Self.find(note, in: fixture)
        let floored = Self.stroke(probe)
        let loose = Self.stroke(probe, floored: false)
        let flooredRadius = Self.minimumWindowedRadius(floored.points, window: 0.5)
        let looseRadius = Self.minimumWindowedRadius(loose.points, window: 0.5)
        #expect(
            flooredRadius >= probe.minCornerRadiusPx ?? 0,
            Comment(rawValue: "windowed radius \(flooredRadius) px under the floor"))
        #expect(
            looseRadius < probe.minCornerRadiusPx ?? 0,
            Comment(rawValue: "the unfloored corner should still collapse; got \(looseRadius) px"))
        // The sub-pixel spelling of the same corner: decimated away before the
        // fillet, so the floor has nothing left to rescue and both answers
        // reach the radius on their own.
        let fine = try Self.find(
            "a corner split across near-coincident vertices is rounded as ONE corner to the minimum radius",
            in: fixture)
        let fineFloor = fine.minCornerRadiusPx ?? 0
        #expect(
            Self.minimumWindowedRadius(Self.stroke(fine).points, window: 0.5) >= fineFloor)
        #expect(
            Self.minimumWindowedRadius(Self.stroke(fine, floored: false).points, window: 0.5)
                >= fineFloor)
        // Bounded: nothing the run swallowed may end up further from the drawn
        // line than the radius the corner was given.
        let inputs = Self.points(probe.points)
        var worst = 0.0
        for point in inputs {
            worst = max(worst, ContinuousStroke.distanceToPolyline(point, floored.points))
        }
        #expect(
            worst <= probe.minCornerRadiusPx ?? 0,
            Comment(rawValue: "a vertex moved \(worst) px"))
        // And the line is not shortened by more than the corner it cut.
        let before = Self.cumulative(inputs).last ?? 0
        let after = Self.cumulative(floored.points).last ?? 0
        #expect(before - after < 4 * (probe.minCornerRadiusPx ?? 0))
        #expect(floored.points.first == inputs.first)
        #expect(floored.points.last == inputs.last)
    }

    /// A platform is a place a train stops. It may not be swallowed by a
    /// corner, so a run stops at it — and its bead stays exactly on it.
    @Test func anchorInsideASplitCornerNeverMoves() throws {
        let note = "a station anchor inside a split corner is never swallowed by the run"
        let fixture = try Self.fixture()
        let probe = try Self.find(note, in: fixture)
        let stroke = Self.stroke(probe)
        let anchorIndex = probe.anchors[0]
        let asked = Self.points(probe.points)[anchorIndex]
        #expect(stroke.anchors.first == asked)
        #expect(stroke.points.contains(asked), Comment(rawValue: "the platform vertex was rounded away"))
    }

    /// THE BEAD MUST BE BIT-IDENTICAL, NOT MERELY NEAR.
    ///
    /// A station platform's own vertex may now be rounded THROUGH (rules
    /// §10.9) instead of left sharp, but an anchor's returned coordinate is
    /// read from the pre-fillet polyline — before the fillet ever runs (see
    /// `buildStroke`'s `anchors` map). An ordinary fillet corner is a
    /// quadratic Bézier whose control point is the vertex, and such a curve
    /// does NOT pass through its control point — so an anchor corner is
    /// built differently: a circular arc through three points (the two
    /// tangent points and the vertex itself), with the sample nearest the
    /// vertex's true angular position forced to the vertex exactly. That is
    /// checked here for every anchor-corner fixture case: the bead
    /// `buildStroke` returns is present, bit-identical, as a point in the
    /// drawn line — not merely within 1e-6 of one. Three of the four cases
    /// carry no lane offset, so their bead is additionally the original
    /// input vertex exactly, unmoved by anything upstream of the fillet;
    /// the fourth reuses the offset-and-laned "right angle" case, where the
    /// bead is legitimately the OFFSET position, not the raw vertex.
    @Test func anchorFilletApexIsExactlyOnTheLine() throws {
        let fixture = try Self.fixture()
        let notes = [
            "right angle on a station anchor: rounded through the anchor by an arc, the bead stays on the line",
            "30 degree turn on a station anchor: rounded through the anchor by an arc, the bead stays on the line",
            "a station anchor at a chain end is never filleted, whatever the radius asks for",
            "a station anchor beside a very short edge still rounds through the anchor, the tangent capped by that edge",
        ]
        for note in notes {
            let probe = try Self.find(note, in: fixture)
            let stroke = Self.stroke(probe)
            #expect(stroke.anchors.count == probe.anchors.count, Comment(rawValue: note))
            let laned = probe.rows.contains { $0.lane != 0 }
            for (k, anchorIndex) in probe.anchors.enumerated() {
                #expect(
                    stroke.points.contains(stroke.anchors[k]),
                    Comment(rawValue: "\(note): bead is not bit-identical to any drawn point"))
                if !laned {
                    let inputVertex = Self.points(probe.points)[anchorIndex]
                    #expect(
                        stroke.anchors[k] == inputVertex,
                        Comment(rawValue: "\(note): bead moved off the surveyed vertex"))
                }
            }
        }
    }

    /// Change 1: fold removal may drop the offset vertex an anchor reads
    /// from. The bead is then the nearest point on the surviving edge that
    /// replaced it — not necessarily a discrete output vertex, but always
    /// exactly ON the drawn line (the projection is the same clamped
    /// nearest-point-on-segment computation `distanceToPolyline` uses, so
    /// the distance is exactly zero, not merely under a tolerance).
    @Test func anchorSurvivesAnOffsetFoldOnItsOwnVertex() throws {
        let note = "lane offset folds exactly at an anchor vertex: the bead is read from the surviving edge, not the discarded offset point"
        let fixture = try Self.fixture()
        let probe = try Self.find(note, in: fixture)
        let stroke = Self.stroke(probe)
        #expect(stroke.anchors.count == 1, Comment(rawValue: note))
        let distance = ContinuousStroke.distanceToPolyline(stroke.anchors[0], stroke.points)
        #expect(distance == 0, Comment(rawValue: "\(note): bead sits \(distance) px off the drawn line"))
    }

    /// A switchback is not a corner. A reversal among near-coincident vertices
    /// must survive the run merge unrounded.
    ///
    /// Unrounded, not unmoved: the three vertices around the apex are
    /// hundredths of a pixel apart, and `buildStroke`'s pre-fillet decimation
    /// collapses them onto the outermost one. That SHARPENS the reversal
    /// rather than softening it, and leaves the drawn line inside
    /// ``strokeSimplifyTolerancePx`` of every surveyed vertex — which is the
    /// same epsilon both renderers used to spend below this pass, where no
    /// test could see it. What may never happen is a fillet: the deflection
    /// stays above ``filletMaxTurnDegrees``, so nothing draws a curve the
    /// railway does not have.
    @Test func hairpinAmongNearCoincidentVerticesStaysSharp() throws {
        let note = "a hairpin among near-coincident vertices is never rounded"
        let fixture = try Self.fixture()
        let probe = try Self.find(note, in: fixture)
        let stroke = Self.stroke(probe)
        let inputs = Self.points(probe.points)
        let surveyed = Self.worstTurnDegrees(inputs)
        #expect(surveyed > ContinuousStroke.filletMaxTurnDegrees)
        let drawn = Self.worstTurnDegrees(stroke.points)
        #expect(
            drawn > ContinuousStroke.filletMaxTurnDegrees,
            Comment(rawValue: "the reversal was rounded: \(drawn)°"))
        for point in inputs {
            let off = ContinuousStroke.distanceToPolyline(point, stroke.points)
            #expect(
                off <= ContinuousStroke.strokeSimplifyTolerancePx,
                Comment(rawValue: "a surveyed vertex sits \(off) px off the drawn line"))
        }
    }

    /// ONE LINE CANNOT COME APART AT A PART BOUNDARY.
    ///
    /// The two halves of a line that reverses meet at one surveyed vertex.
    /// Each is offset by its own rows, and each sees the joint from the
    /// opposite direction, so without a `Join` the two strokes end 5.4 px
    /// apart — a visible break in what is one railway. With it both halves
    /// read the same lane at the joint (the kernel evaluates the terminal step
    /// at exactly one half on both sides, whatever width either used) and
    /// mitre it against the same pair of tangents, so the shared vertex is one
    /// point.
    @Test func jointIsContinuous() throws {
        let fixture = try Self.fixture()
        let arriving = try Self.find(
            "joint before a reversal: the part that arrives, carrying the next part's lane and the joint's tangents",
            in: fixture)
        let leaving = try Self.find(
            "joint after a reversal: the part that leaves, carrying the previous part's lane and the same joint",
            in: fixture)
        let joinedEnd = Self.stroke(arriving).points.last
        let joinedStart = Self.stroke(leaving).points.first
        #expect(joinedEnd == joinedStart, Comment(rawValue: "\(String(describing: joinedEnd)) vs \(String(describing: joinedStart))"))
        // The control: the same two parts without the join do come apart, so
        // the assertion above is testing the join and not the geometry.
        let looseEnd = Self.stroke(arriving, joined: false).points.last
        let looseStart = Self.stroke(leaving, joined: false).points.first
        let apart = hypot(looseEnd!.x - looseStart!.x, looseEnd!.y - looseStart!.y)
        #expect(apart > 1, Comment(rawValue: "unjoined parts should separate; got \(apart) px"))
    }

    /// NOR CAN A CORRIDOR FOLLOW PULL IT APART THERE.
    ///
    /// The other way the two halves separate at the vertex they share: each
    /// borrows a canonical alignment, and `canonFrom`/`canonTo` are a linear
    /// correspondence with metres of slack in it, so the SAME surveyed vertex
    /// substitutes to two different points. On the shipped packages that was
    /// 9.5 px at Jamaica (mta-…-city-terminal-zone, whose alignment is
    /// coincident with its canonical to 0.0 m — the whole gap is along-track
    /// slack) and 37.3 px at Exhibition Loop (ttc-509, whose follow
    /// over-reaches onto a loop track ttc-511 does not share). A `Join` holds
    /// every follow back one blend width from the joint, so the shared vertex
    /// is drawn where the survey put it — the one answer both halves reach.
    @Test func followedJointIsContinuous() throws {
        let fixture = try Self.fixture()
        let arriving = try Self.find(
            "followed joint: the part that arrives, its corridor follow reaching the shared vertex",
            in: fixture)
        let leaving = try Self.find(
            "followed joint: the part that leaves, its own corridor follow reaching the same vertex",
            in: fixture)
        let surveyed = Self.points(arriving.points).last!
        let joinedEnd = Self.stroke(arriving).points.last
        let joinedStart = Self.stroke(leaving).points.first
        #expect(joinedEnd == joinedStart, Comment(rawValue: "\(String(describing: joinedEnd)) vs \(String(describing: joinedStart))"))
        // Not merely equal: equal to the vertex the two parts actually share.
        #expect(joinedEnd == surveyed, Comment(rawValue: "\(String(describing: joinedEnd)) vs surveyed \(surveyed)"))
        // The control: without the join both follows reach the joint and the
        // two halves substitute it to two different alignments.
        let looseEnd = Self.stroke(arriving, joined: false).points.last
        let looseStart = Self.stroke(leaving, joined: false).points.first
        let apart = hypot(looseEnd!.x - looseStart!.x, looseEnd!.y - looseStart!.y)
        #expect(apart > 1, Comment(rawValue: "unjoined followed parts should separate; got \(apart) px"))
    }

    /// A follow with nothing left after the hold-back does not draw at all.
    ///
    /// ttc-509's Exhibition Loop stub is 57 m long and entirely a follow;
    /// drawing it from the canonical put its stop bead 31.6 m off the surveyed
    /// platform. Held back a full blend width from the joint, the stub keeps
    /// its own survey and its bead stays put.
    @Test func followShorterThanTheHoldBackIsDropped() throws {
        let fixture = try Self.fixture()
        let stub = try Self.find(
            "followed joint: a stub shorter than the hold-back keeps its own survey entire",
            in: fixture)
        let surveyed = Self.points(stub.points)
        #expect(Self.stroke(stub).points == surveyed)
        #expect(Self.stroke(stub).anchors == [surveyed[1]])
        // The control: unheld, the whole stub is drawn from the canonical and
        // the bead goes with it.
        let loose = Self.stroke(stub, joined: false)
        #expect(loose.points != surveyed)
        #expect(loose.anchors[0].y != surveyed[1].y)
    }

    /// `ContinuousStroke.familyPartition` against rail-stroke.js's own
    /// `familyPartition` (`port-fixtures/continuous-stroke.json`'s
    /// `familyPartitions`) over synthetic boundary probes — end-to-end
    /// windows, a window pinned to a terminal, a tenant window covering the
    /// whole part, overlapping windows, reversed inputs, and a
    /// `measureStart`/`measureEnd` narrower than `[0, totalMetres]`.
    /// Compared to 1e-9 m, the tolerance the review asked this function be
    /// answer-identical to.
    @Test func familyPartitionMatchesTheJavaScript() throws {
        let fixture = try Self.fixture()
        for probe in fixture.familyPartitions {
            let tenant = probe.tenantWindows.map {
                ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupId)
            }
            let landlord = probe.landlordWindows.map {
                ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupId)
            }
            let result = ContinuousStroke.familyPartition(
                totalMetres: probe.totalMetres, tenantWindows: tenant, landlordWindows: landlord,
                measureStart: probe.measureStart, measureEnd: probe.measureEnd)
            let label = Comment(rawValue: probe.note)
            #expect(result.base.count == probe.expected.base.count, label)
            for (got, want) in zip(result.base, probe.expected.base) {
                #expect(abs(got.from - want.from) < 1e-9, label)
                #expect(abs(got.to - want.to) < 1e-9, label)
            }
            #expect(result.family.count == probe.expected.family.count, label)
            for (got, want) in zip(result.family, probe.expected.family) {
                #expect(abs(got.from - want.from) < 1e-9, label)
                #expect(abs(got.to - want.to) < 1e-9, label)
                #expect(got.groupID == want.groupId, label)
            }
        }
    }

    /// `ContinuousStroke.clipRangesToComplement` against rail-stroke.js's own
    /// `clipRangesToComplement` (`clipsToComplement`) — a withheld span
    /// clipped to the complement of the line's own tenant windows, probing a
    /// span straddling a tenant edge on either side, a window entirely
    /// inside the span, a span entirely swallowed by a window, two separate
    /// windows, and a reversed span.
    @Test func clipRangesToComplementMatchesTheJavaScript() throws {
        let fixture = try Self.fixture()
        for probe in fixture.clipsToComplement {
            let ranges = probe.ranges.map { ContinuousStroke.Interval(from: $0.from, to: $0.to) }
            let tenant = probe.tenantWindows.map {
                ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupId)
            }
            let result = ContinuousStroke.clipRangesToComplement(ranges, tenantWindows: tenant)
            let label = Comment(rawValue: probe.note)
            #expect(result.count == probe.expected.count, label)
            for (got, want) in zip(result, probe.expected) {
                #expect(abs(got.from - want.from) < 1e-9, label)
                #expect(abs(got.to - want.to) < 1e-9, label)
            }
        }
    }
}
