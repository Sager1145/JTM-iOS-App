import Foundation

/// The continuous screen-space stroke of one railway part — the port of
/// `app/public/rail-stroke.js`, checked against `port-fixtures/continuous-stroke.json`.
///
/// A railway that shares a corridor with another is drawn beside it in a
/// screen-space lane: a fixed number of points off the surveyed centreline,
/// the same number at every zoom. This pass bakes that offset into the
/// vertices themselves, in a pixel space the caller projects into, through a
/// lane profile that is a continuous function of the distance along the part.
/// One part is therefore ONE polyline, whatever its lanes do, and nothing about
/// panning can break it; zooming changes how many pixels a metre is, so the
/// caller rebuilds when the zoom has moved far enough for the gap to drift.
///
/// The same pass rounds every interior corner that is neither a station
/// anchor nor a reversal, to a screen-space radius.
///
/// Everything is plain arithmetic in an abstract 2-D space — no MapKit, no
/// CoreGraphics — so that the JavaScript and this file can be run over the
/// same fixtures. Keep it that way.
public enum ContinuousStroke {

    // MARK: - tokens (rail-stroke.js, restated for the parity test to pin)

    /// A lane change drifts over this half-width, in metres, or the pixel
    /// floor the caller adds when the zoom makes it under a pixel.
    public static let laneRampHalfWidthMetres: Double = 300
    /// A stretch shorter than the sampling the rows were measured at is not
    /// evidence of a lane; it is absorbed into its longer neighbour.
    public static let lanePlateauMinMetres: Double = 60
    /// A line cut into parts at a reversal or a retrace is still ONE railway,
    /// and the two pieces meet at one surveyed vertex. Each piece is offset by
    /// its own rows, and at a shared vertex the two answers have to be the
    /// same answer or the line comes apart there. A ``Join`` carries the
    /// neighbour's terminal lane in as a plateau reaching this far past this
    /// part's own end — far enough that no kernel sees its far side — so both
    /// pieces read the terminal step as the same half-way value whatever zoom
    /// either was built at. See ``laneProfile(rows:total:joinStart:joinEnd:)``.
    public static let laneJoinExtentMetres: Double = 1e7
    /// A corridor follow is blended in and out over this half-width, in
    /// metres, with the same kernel as a lane change.
    ///
    /// A follow may NOT reach a joint. `canonFrom`/`canonTo` are a LINEAR
    /// correspondence between two measure rulers, reviewed and stored to a
    /// tenth of a metre, and the two alignments are rarely the same length
    /// over the stretch — so the measure a follower's vertex maps to on the
    /// canonical is right to a few metres, no better. In the middle of a
    /// stretch that slack slides a vertex a metre or two ALONG a corridor the
    /// follower is coincident with, which is invisible. At the vertex two
    /// parts of one line SHARE it is fatal: the neighbour has its own
    /// correspondence, or none at all, and the two answers cannot agree — the
    /// shipped US/CA packages separated mta-…-city-terminal-zone by 9.5 px at
    /// Jamaica (the two alignments are coincident to 0.0 m there; the whole
    /// gap is 8.6 m of along-track slack in `canonTo`) and ttc-509 by 37.3 px
    /// at Exhibition Loop (where the follow over-reaches by 270 m onto a loop
    /// track ttc-511 does not share). So each follow's WEIGHT is held back one
    /// blend width from a joint — the correspondence itself is untouched — and
    /// the shared vertex is drawn where the survey put it, which is the one
    /// answer both parts can reach. See
    /// ``substituteFollows(_:measures:anchors:follows:jointStart:jointEnd:)``.
    public static let followBlendMetres: Double = 300
    /// A survey seam welded sideways leaves a Z: two opposite bends within a
    /// few tens of metres, the same heading either side, the track a few
    /// tens of metres over. It is redrawn as a taper (see `taperJogs`).
    public static let jogMinTurnDegrees: Double = 25
    public static let jogMaxTurnDegrees: Double = 100
    public static let jogMaxRunMetres: Double = 60
    public static let jogMaxNetTurnDegrees: Double = 15
    public static let jogMinLateralMetres: Double = 8
    public static let jogTaperMetres: Double = 150
    public static let jogMinTaperMetres: Double = 40
    public static let jogTaperSamples: Int = 8
    /// An offset vertex that turned into a reversal the survey did not have
    /// is a fold, and is dropped (see `removeOffsetFolds`).
    public static let foldTurnDegrees: Double = 150
    /// Below this deflection the round join already draws the corner.
    public static let filletMinTurnDegrees: Double = 6
    /// Above this the vertex is a reversal and is left exactly as surveyed.
    public static let filletMaxTurnDegrees: Double = 150
    /// A fillet may borrow at most this share of each edge it sits on, so two
    /// fillets on one edge can never cross.
    ///
    /// That cap is also how the radius used to collapse: where a survey leaves
    /// two vertices a hundredth of a pixel apart, 0.45 of the shorter edge is
    /// a hundredth of a pixel too. Measured over every US and CA part at
    /// z10/13/15/17, 8.4 % of rounded corners were capped by this share and
    /// 3.7 % came out under one stroke width. The fix is not a bigger share —
    /// two fillets would cross — but to round such a RUN of vertices as ONE
    /// corner; see ``fillet(_:radius:floorRadius:anchors:measures:)``.
    public static let filletMaxTangentShare: Double = 0.45
    /// One curve vertex per this many degrees of turn.
    public static let filletStepDegrees: Double = 12
    /// The bisector offset factor 1/cos(θ/2) is clamped here.
    public static let miterLimit: Double = 2.5
    /// Two vertices closer than this, in pixels, are one vertex.
    static let degenerateEdge: Double = 1e-6

    static let worldPixelsAtZoomZero: Double = 512

    // MARK: - types

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// One reviewed lane stretch, in metres along the part.
    public struct LaneRow: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public var lane: Double
        public init(from: Double, to: Double, lane: Double) {
            self.from = from
            self.to = to
            self.lane = lane
        }
    }

    /// A plateau of the lane profile.
    public struct Plateau: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public var lane: Double
    }

    /// Over `from…to` (metres along the follower) the stroke is drawn from
    /// the canonical part's alignment between `canonFrom…canonTo` (metres
    /// along that part, reversed when digitised against each other), whose
    /// vertices are given in the follower's pixel space.
    public struct Follow: Sendable {
        public var from: Double
        public var to: Double
        public var canonFrom: Double
        public var canonTo: Double
        public var points: [Point]
        /// Cumulative metres along the canonical part at each of `points`.
        public var measures: [Double]
        public init(
            from: Double, to: Double, canonFrom: Double, canonTo: Double,
            points: [Point], measures: [Double]
        ) {
            self.from = from
            self.to = to
            self.canonFrom = canonFrom
            self.canonTo = canonTo
            self.points = points
            self.measures = measures
        }
    }

    /// The joint a part shares with the neighbouring part of the same line.
    ///
    /// `lane` is the neighbour's lane at that vertex; `incoming` and
    /// `outgoing` are the pair of unit directions at the joint, derived by
    /// BOTH parts from the same two raw edges, so both offset the shared
    /// vertex to the same point however each of them was sampled.
    public struct Join: Equatable, Sendable {
        public var lane: Double
        public var incoming: Point
        public var outgoing: Point
        public init(lane: Double, incoming: Point, outgoing: Point) {
            self.lane = lane
            self.incoming = incoming
            self.outgoing = outgoing
        }
    }

    public struct Options: Sendable {
        /// Cumulative metres along the part at every vertex — the ruler the
        /// rows are measured with. Empty means "scale the pixel length by
        /// `totalMetres`", which is only right for a part at one latitude.
        public var measures: [Double]
        public var rows: [LaneRow]
        public var totalMetres: Double
        public var laneGapPx: Double
        public var minRampPx: Double
        public var cornerRadiusPx: Double
        /// The radius a corner is rounded to AT WORST, in pixels. Where no
        /// single vertex's edges can carry it, the run of vertices is rounded
        /// as one corner. 0 keeps the older per-vertex-only behaviour.
        public var minCornerRadiusPx: Double
        public var anchors: [Int]
        public var follows: [Follow]
        /// The joint with the neighbouring part of the same line at this
        /// part's first / last vertex, when the two share it. Their PRESENCE
        /// also holds every corridor follow back one blend width from that
        /// vertex, so no borrowed alignment can move it. See
        /// ``followBlendMetres``.
        public var joinStart: Join?
        public var joinEnd: Join?
        public init(
            measures: [Double] = [], rows: [LaneRow], totalMetres: Double, laneGapPx: Double,
            minRampPx: Double, cornerRadiusPx: Double, minCornerRadiusPx: Double = 0,
            anchors: [Int], follows: [Follow] = [],
            joinStart: Join? = nil, joinEnd: Join? = nil
        ) {
            self.measures = measures
            self.rows = rows
            self.totalMetres = totalMetres
            self.laneGapPx = laneGapPx
            self.minRampPx = minRampPx
            self.cornerRadiusPx = cornerRadiusPx
            self.minCornerRadiusPx = minCornerRadiusPx
            self.anchors = anchors
            self.follows = follows
            self.joinStart = joinStart
            self.joinEnd = joinEnd
        }
    }

    public struct Stroke: Equatable, Sendable {
        public var points: [Point]
        /// `anchors[i]` is the offset position of `points[options.anchors[i]]`.
        public var anchors: [Point]
        /// `measures[i]` is the metre measure of `points[i]`, non-decreasing.
        public var measures: [Double]
        /// `anchorMeasures[i]` is the (post-dedupe input) measure of the
        /// vertex `options.anchors[i]` was read from.
        public var anchorMeasures: [Double]
    }

    // MARK: - projection (web mercator, 512-px tiles, y grows south)

    public static func worldSize(zoom: Double) -> Double {
        worldPixelsAtZoomZero * pow(2, zoom)
    }

    public static func project(lon: Double, lat: Double, zoom: Double) -> Point {
        let size = worldSize(zoom: zoom)
        let clamped = max(-85.051129, min(85.051129, lat))
        let s = sin(clamped * Double.pi / 180)
        return Point(
            x: ((lon + 180) / 360) * size,
            y: (0.5 - log((1 + s) / (1 - s)) / (4 * Double.pi)) * size)
    }

    public static func unproject(_ point: Point, zoom: Double) -> (lon: Double, lat: Double) {
        let size = worldSize(zoom: zoom)
        let lon = (point.x / size) * 360 - 180
        let n = Double.pi - (2 * Double.pi * point.y) / size
        let lat = (180 / Double.pi) * atan(0.5 * (exp(n) - exp(-n)))
        return (lon, lat)
    }

    // MARK: - lane profile

    /// `joinStart` / `joinEnd`, when given, are the lane the NEIGHBOURING part
    /// of the same line holds at the vertex this part shares with it. Each is
    /// added as a plateau reaching ``laneJoinExtentMetres`` beyond this part's
    /// own end, so the terminal step is evaluated by the kernel rather than
    /// held flat — and because `kernelCumulative(0, width) = 1/2` for every
    /// width, both parts read exactly (own + neighbour) / 2 at the joint
    /// whatever zoom either of them was built at. When the two agree the
    /// plateaus coalesce and the answer is the flat terminal lane as before.
    public static func laneProfile(
        rows: [LaneRow], total: Double, joinStart: Double? = nil, joinEnd: Double? = nil
    ) -> [Plateau] {
        guard total > 0 else { return [] }
        var plateaus: [Plateau] = []
        var cursor = 0.0
        // Ties broken by input order explicitly, so both ports agree whatever
        // their sort's stability guarantees.
        let sorted = rows.enumerated().sorted {
            $0.element.from < $1.element.from
                || ($0.element.from == $1.element.from && $0.offset < $1.offset)
        }.map(\.element)
        for row in sorted {
            let from = max(cursor, min(row.from, total))
            let to = max(from, min(row.to, total))
            if from > cursor { plateaus.append(Plateau(from: cursor, to: from, lane: 0)) }
            if to > from { plateaus.append(Plateau(from: from, to: to, lane: row.lane)) }
            cursor = to
        }
        if cursor < total { plateaus.append(Plateau(from: cursor, to: total, lane: 0)) }
        if let joinStart {
            plateaus.insert(
                Plateau(from: -laneJoinExtentMetres, to: 0, lane: joinStart), at: 0)
        }
        if let joinEnd {
            plateaus.append(
                Plateau(from: total, to: total + laneJoinExtentMetres, lane: joinEnd))
        }
        return coalesce(plateaus)
    }

    /// The lane a part holds at its own two ends, which is what a neighbouring
    /// part needs for its ``Join``. Read off the part's own rows so both sides
    /// of a joint compute it the same way from the same package.
    public static func terminalLanes(rows: [LaneRow], total: Double) -> (start: Double, end: Double) {
        let profile = laneProfile(rows: rows, total: total)
        guard let first = profile.first, let last = profile.last else { return (0, 0) }
        return (first.lane, last.lane)
    }

    static func coalesce(_ plateaus: [Plateau]) -> [Plateau] {
        var held = plateaus
        while held.count >= 2 {
            var at = -1
            for index in held.indices {
                let span = held[index].to - held[index].from
                if span >= lanePlateauMinMetres { continue }
                if at < 0 || span < held[at].to - held[at].from { at = index }
            }
            if at < 0 { break }
            let hasPrevious = at > 0
            let hasNext = at + 1 < held.count
            let intoPrevious = hasPrevious
                && (!hasNext
                    || held[at - 1].to - held[at - 1].from >= held[at + 1].to - held[at + 1].from)
            if intoPrevious {
                held[at - 1].to = held[at].to
            } else {
                held[at + 1].from = held[at].from
            }
            held.remove(at: at)
        }
        var out: [Plateau] = []
        for plateau in held {
            if let last = out.last, last.lane == plateau.lane {
                out[out.count - 1].to = plateau.to
            } else {
                out.append(plateau)
            }
        }
        return out
    }

    static func kernelCumulative(_ x: Double, width: Double) -> Double {
        if x <= -width { return 0 }
        if x >= width { return 1 }
        if x <= 0 {
            let t = x + width
            return (t * t) / (2 * width * width)
        }
        let t = width - x
        return 1 - (t * t) / (2 * width * width)
    }

    /// The lane at one measure: the plateau step function seen through a
    /// triangular kernel of half-width `width` (metres). Width 0 reads the
    /// step function itself.
    public static func laneAt(profile: [Plateau], measure: Double, width: Double) -> Double {
        guard !profile.isEmpty else { return 0 }
        guard width > 0 else {
            for plateau in profile where measure <= plateau.to { return plateau.lane }
            return profile[profile.count - 1].lane
        }
        var lane = 0.0
        let last = profile.count - 1
        for index in 0...last {
            let plateau = profile[index]
            if plateau.lane == 0 { continue }
            let start = index == 0 ? 1 : kernelCumulative(measure - plateau.from, width: width)
            let end = index == last ? 0 : kernelCumulative(measure - plateau.to, width: width)
            lane += plateau.lane * (start - end)
        }
        return lane
    }

    static func profileIsFlat(_ profile: [Plateau]) -> Bool {
        profile.allSatisfy { $0.lane == 0 }
    }

    // MARK: - the stroke

    public static func buildStroke(_ points: [Point], options: Options) -> Stroke {
        guard points.count >= 2 else {
            let only = points.last ?? Point(x: 0, y: 0)
            let measures = options.measures.count == points.count
                ? options.measures
                : points.map { _ in 0.0 }
            let lastMeasure = measures.last ?? 0
            return Stroke(
                points: points, anchors: options.anchors.map { _ in only },
                measures: measures, anchorMeasures: options.anchors.map { _ in lastMeasure })
        }
        let inputMeasures: [Double]
        if options.measures.count == points.count {
            inputMeasures = options.measures
        } else {
            let raw = cumulativeLengths(points)
            let rawTotalPx = raw[raw.count - 1]
            let scale = rawTotalPx > 0 && options.totalMetres > 0 ? options.totalMetres / rawTotalPx : 0
            inputMeasures = raw.map { $0 * scale }
        }
        let (clean, cleanMeasures, anchorMap, anchorSet) = dedupe(
            points, measures: inputMeasures, anchors: options.anchors)
        let anchorMeasures = options.anchors.map { index -> Double in
            guard index >= 0, index < anchorMap.count else { return cleanMeasures[cleanMeasures.count - 1] }
            return cleanMeasures[anchorMap[index]]
        }
        guard clean.count >= 2 else {
            let only = clean.first ?? points[0]
            let m = cleanMeasures[0]
            return Stroke(
                points: [only, only], anchors: options.anchors.map { _ in only },
                measures: [m, m], anchorMeasures: anchorMeasures)
        }
        let gap = options.laneGapPx
        let cleanCumulative = cumulativeLengths(clean)
        let cleanTotalPx = cleanCumulative[cleanCumulative.count - 1]
        let totalMetres = cleanMeasures[cleanMeasures.count - 1] - cleanMeasures[0]
        let metresPerPx = cleanTotalPx > 0 && totalMetres > 0 ? totalMetres / cleanTotalPx : 0
        let substituted = substituteFollows(
            clean, measures: cleanMeasures, anchors: anchorSet, follows: options.follows,
            jointStart: options.joinStart != nil, jointEnd: options.joinEnd != nil)
        var followed = substituted
        if substituted.points.count != clean.count || substituted.points != clean {
            let foldTurn = foldTurnDegrees * Double.pi / 180
            var cleanReversal = [Bool](repeating: false, count: clean.count)
            if clean.count >= 3 {
                for index in 1..<(clean.count - 1) {
                    cleanReversal[index] = abs(turnAt(clean, index)) > foldTurn
                }
            }
            var reversal = [Bool](repeating: false, count: substituted.points.count)
            for (index, at) in substituted.map.enumerated() where at >= 0 {
                reversal[at] = cleanReversal[index] || anchorSet.contains(index)
            }
            let unfolded = removeFolds(substituted.points, reversal: reversal)
            // Measures follow the kept vertices, in order.
            let measures = unfolded.map.enumerated().compactMap { index, at in
                at >= 0 ? (at, substituted.measures[index]) : nil
            }.sorted { $0.0 < $1.0 }.map { $0.1 }
            followed = (
                points: unfolded.points,
                measures: measures,
                map: substituted.map.map { $0 < 0 ? -1 : unfolded.map[$0] })
        }
        var followedAnchors = Set<Int>()
        for index in anchorSet where followed.map[index] >= 0 {
            followedAnchors.insert(followed.map[index])
        }
        let taperedStep = taperJogs(
            followed.points, measures: followed.measures, anchors: followedAnchors,
            metresPerPx: metresPerPx)
        let tapered = (
            points: taperedStep.points,
            measures: taperedStep.measures,
            map: followed.map.map { $0 < 0 ? -1 : taperedStep.map[$0] })
        let base = tapered.points
        var taperedAnchors = Set<Int>()
        for index in anchorSet where tapered.map[index] >= 0 {
            taperedAnchors.insert(tapered.map[index])
        }
        var offset = base
        var offsetApplied = false
        let joinLaneStart = options.joinStart?.lane
        let joinLaneEnd = options.joinEnd?.lane
        // A neighbour's lane at the joint is as much a reason to leave the
        // centreline as a row of this part's own is: without it the two parts
        // meet at a step.
        let laned = options.rows.contains(where: { $0.lane != 0 })
            || (joinLaneStart ?? 0) != 0 || (joinLaneEnd ?? 0) != 0
        if gap != 0, laned, totalMetres > 0 {
            let profile = laneProfile(
                rows: options.rows, total: totalMetres,
                joinStart: joinLaneStart, joinEnd: joinLaneEnd)
            let width = max(laneRampHalfWidthMetres, options.minRampPx * metresPerPx)
            if !profileIsFlat(profile) {
                offset = offsetPolyline(
                    base, joinStart: options.joinStart, joinEnd: options.joinEnd
                ) { index in
                    laneAt(profile: profile, measure: tapered.measures[index], width: width) * gap
                }
                offsetApplied = true
            }
        }
        let cleaned = offsetApplied
            ? removeOffsetFolds(offset, original: base)
            : (points: base, map: Array(0..<base.count))
        // Measures follow the kept vertices, in order — the same map-driven
        // carry used above for the corridor fold pass.
        let cleanedMeasures = cleaned.map.enumerated().compactMap { index, at in
            at >= 0 ? (at, tapered.measures[index]) : nil
        }.sorted { $0.0 < $1.0 }.map { $0.1 }
        var finalAnchors = Set<Int>()
        for index in taperedAnchors where cleaned.map[index] >= 0 {
            finalAnchors.insert(cleaned.map[index])
        }
        // Computed BEFORE the anchor beads below so a fold-dropped anchor
        // can be projected onto the line actually drawn, not the
        // pre-fillet edge (see nearestOnMeasureSpan). A SURVIVING anchor
        // needs no such lookup: it forces a hard vertex in fillet(), so its
        // own position passes through unchanged either way —
        // cleaned.points[resolved] already is the emitted point.
        let filleted = fillet(
            cleaned.points, radius: options.cornerRadiusPx,
            floorRadius: options.minCornerRadiusPx, anchors: finalAnchors,
            measures: cleanedMeasures)
        let anchors = options.anchors.map { index -> Point in
            guard index >= 0, index < anchorMap.count else { return offset[offset.count - 1] }
            let moved = tapered.map[anchorMap[index]]
            if moved < 0 { return offset[offset.count - 1] }
            let resolved = cleaned.map[moved]
            if resolved >= 0 { return cleaned.points[resolved] }
            // Fold removal dropped this vertex: the bead goes on the
            // surviving edge that replaced it, nearest the offset position
            // it was reading from — not the vertex the fold pass threw
            // away — and projected onto the FINAL emitted (post-fillet)
            // line: a fillet at either endpoint of that edge trims it, so
            // projecting onto the pre-fillet edge can land off the drawn
            // ink whenever cornerRadiusPx > 0.
            var prev = moved
            while prev > 0 && cleaned.map[prev] < 0 { prev -= 1 }
            var next = moved
            while next < cleaned.map.count - 1 && cleaned.map[next] < 0 { next += 1 }
            let aIndex = cleaned.map[prev]
            let bIndex = cleaned.map[next]
            let target = offset[moved]
            if let projected = nearestOnMeasureSpan(
                target, polyline: filleted.points, measures: filleted.measures,
                mLo: cleanedMeasures[aIndex], mHi: cleanedMeasures[bIndex])
            {
                return projected
            }
            let a = cleaned.points[aIndex]
            let b = cleaned.points[bIndex]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let square = dx * dx + dy * dy
            var t = square > 0 ? ((target.x - a.x) * dx + (target.y - a.y) * dy) / square : 0
            t = max(0, min(1, t))
            return Point(x: a.x + dx * t, y: a.y + dy * t)
        }
        // A fillet at a vertex whose neighbour edge is tiny can overshoot its
        // predecessor by float noise; clamp so the measures stay non-decreasing.
        var finalMeasures = filleted.measures
        for index in 1..<finalMeasures.count where finalMeasures[index] < finalMeasures[index - 1] {
            finalMeasures[index] = finalMeasures[index - 1]
        }
        return Stroke(
            points: filleted.points, anchors: anchors, measures: finalMeasures,
            anchorMeasures: anchorMeasures)
    }

    /// The polyline between two metre measures of a `buildStroke` result, in
    /// the same pixel space. Both endpoints are interpolated exactly inside
    /// their containing interval; every intermediate vertex is included; the
    /// measures are clamped to the stroke's own range; the order is reversed
    /// when `from > to`. `measures` must be non-decreasing and the same
    /// length as `points`.
    public static func slice(points: [Point], measures: [Double], from: Double, to: Double) -> [Point] {
        let count = points.count
        guard count >= 2, measures.count == count else { return [] }
        let lo = measures[0]
        let hi = measures[count - 1]
        func clamp(_ v: Double) -> Double { max(lo, min(hi, v)) }
        let a = clamp(from)
        let b = clamp(to)
        let lowM = min(a, b)
        let highM = max(a, b)
        guard highM - lowM >= 1e-9 else { return [] }
        // Rightmost index whose measure is ≤ the target, clamped to count-2
        // so the returned index always starts a valid segment.
        func locate(_ m: Double) -> Int {
            var low = 0
            var high = count - 1
            while low < high {
                let mid = Int((Double(low + high) / 2).rounded(.up))
                if measures[mid] <= m { low = mid } else { high = mid - 1 }
            }
            return min(low, count - 2)
        }
        func pointAt(_ index: Int, _ m: Double) -> Point {
            let denom = measures[index + 1] - measures[index]
            let t = denom > 0 ? (m - measures[index]) / denom : 0
            let p0 = points[index]
            let p1 = points[index + 1]
            return Point(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
        }
        let iLow = locate(lowM)
        let iHigh = locate(highM)
        var out: [Point] = [pointAt(iLow, lowM)]
        if iLow + 1 <= iHigh {
            for index in (iLow + 1)...iHigh where measures[index] < highM {
                out.append(points[index])
            }
        }
        out.append(pointAt(iHigh, highM))
        guard out.count >= 2 else { return [] }
        if from > to { out.reverse() }
        return out
    }

    // MARK: - family-collapse partition (rail-stroke.js `familyPartition` /
    // `clipRangesToComplement` — answer-identical to 1e-9 m; a change on
    // either side must be mirrored on the other)

    /// A piece of a ``familyPartition(totalMetres:tenantWindows:landlordWindows:measureStart:measureEnd:)``
    /// or ``clipRangesToComplement(_:tenantWindows:)`` result shorter than
    /// this, in METRES, is boundary noise rather than evidence of a piece
    /// either renderer should draw.
    public static let familyPartitionEpsilonMetres: Double = 1e-6

    /// A metre range with no other payload — a base piece, or one side of a
    /// ``clipRangesToComplement(_:tenantWindows:)`` input/output.
    public struct Interval: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public init(from: Double, to: Double) {
            self.from = from
            self.to = to
        }
    }

    /// A family-collapse window: a stretch a chain shares its stroke with a
    /// sibling railway of the same operator collapse. Tenant vs. landlord is
    /// carried by which array a `WindowSpan` sits in, not by a field on it —
    /// see ``familyPartition(totalMetres:tenantWindows:landlordWindows:measureStart:measureEnd:)``.
    public struct WindowSpan: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public var groupID: String
        public init(from: Double, to: Double, groupID: String) {
            self.from = from
            self.to = to
            self.groupID = groupID
        }
    }

    public struct FamilyPartition: Equatable, Sendable {
        public var base: [Interval]
        public var family: [WindowSpan]
        public init(base: [Interval], family: [WindowSpan]) {
            self.base = base
            self.family = family
        }
    }

    /// Partition a part's measure range at its family-collapse windows: BASE
    /// pieces (this line's own colour) cover the complement of every
    /// tenant ∪ landlord window; a FAMILY piece covers each landlord window.
    /// Reproduces rail-stroke.js's `familyPartition` (the web port of
    /// railmap.js's `_applyContinuousStrokes` family-window branch) — see
    /// that file's header note.
    ///
    /// `tenantWindows`/`landlordWindows` are reviewed non-overlapping WITHIN
    /// each list, but not necessarily against each other before clamping —
    /// a window with `from > to` is normalised first. `measureStart`/
    /// `measureEnd` are the STROKE's own measure range
    /// (`stroke.measures.first`/`.last`), not `[0, totalMetres]`: a joint's
    /// extension or a follow's own vertices can leave the built stroke short
    /// of the part's nominal total, and clamping to the wrong bound there
    /// would manufacture a sliver of base colour past geometry that does not
    /// exist. Both default to `[0, totalMetres]` when omitted.
    ///
    /// Both output arrays are sorted by `from`; a piece below
    /// ``familyPartitionEpsilonMetres`` is dropped from EITHER array. `family`
    /// holds one piece per surviving landlord window (never merged with a
    /// neighbour, even a contiguous one), each still carrying its own
    /// `groupID` so the caller can look up that group's colour.
    public static func familyPartition(
        totalMetres: Double,
        tenantWindows: [WindowSpan],
        landlordWindows: [WindowSpan],
        measureStart: Double? = nil,
        measureEnd: Double? = nil
    ) -> FamilyPartition {
        let lower = measureStart ?? 0
        let upper = measureEnd ?? totalMetres
        func clamp(_ value: Double) -> Double { max(lower, min(upper, value)) }
        struct Excluded {
            let from: Double
            let to: Double
            let groupID: String
            let isLandlord: Bool
        }
        func normalise(_ window: WindowSpan, isLandlord: Bool) -> Excluded {
            Excluded(
                from: clamp(min(window.from, window.to)),
                to: clamp(max(window.from, window.to)),
                groupID: window.groupID, isLandlord: isLandlord)
        }
        let excluded = (tenantWindows.map { normalise($0, isLandlord: false) }
            + landlordWindows.map { normalise($0, isLandlord: true) })
            .sorted { $0.from < $1.from }
        var base: [Interval] = []
        var family: [WindowSpan] = []
        var cursor = lower
        for window in excluded {
            guard window.to - window.from > familyPartitionEpsilonMetres else { continue }
            if window.from - cursor > familyPartitionEpsilonMetres {
                base.append(Interval(from: cursor, to: window.from))
            }
            if window.isLandlord {
                family.append(WindowSpan(from: window.from, to: window.to, groupID: window.groupID))
            }
            cursor = max(cursor, window.to)
        }
        if upper - cursor > familyPartitionEpsilonMetres {
            base.append(Interval(from: cursor, to: upper))
        }
        return FamilyPartition(base: base, family: family)
    }

    /// Clip `ranges` to the complement of `tenantWindows` — the stretch(es)
    /// of each range NOT covered by any tenant window. Used for a withheld
    /// span: a span straddling a tenant window's edge is drawn only on the
    /// piece(s) that are still this line's own track — the piece inside the
    /// tenant window is the sibling landlord's own stroke to draw, not this
    /// line's. Reproduces rail-stroke.js's `clipRangesToComplement`.
    ///
    /// A reversed range (`from > to`) is normalised first; tenant windows
    /// are sorted by `from` before clipping. Output is sorted by `from`,
    /// with any piece below ``familyPartitionEpsilonMetres`` dropped.
    public static func clipRangesToComplement(
        _ ranges: [Interval], tenantWindows: [WindowSpan]
    ) -> [Interval] {
        let windows = tenantWindows
            .map { (from: min($0.from, $0.to), to: max($0.from, $0.to)) }
            .sorted { $0.from < $1.from }
        var out: [Interval] = []
        for raw in ranges {
            let rangeFrom = min(raw.from, raw.to)
            let rangeTo = max(raw.from, raw.to)
            var cursor = rangeFrom
            for window in windows {
                let from = max(window.from, rangeFrom)
                let to = min(window.to, rangeTo)
                guard to > from else { continue }
                if from > cursor { out.append(Interval(from: cursor, to: from)) }
                cursor = max(cursor, to)
            }
            if rangeTo > cursor { out.append(Interval(from: cursor, to: rangeTo)) }
        }
        return out
            .filter { $0.to - $0.from > familyPartitionEpsilonMetres }
            .sorted { $0.from < $1.from }
    }

    static func dedupe(
        _ points: [Point], measures: [Double], anchors: [Int]
    ) -> ([Point], [Double], [Int], Set<Int>) {
        var kept: [Point] = []
        var keptMeasures: [Double] = []
        var map = [Int](repeating: 0, count: points.count)
        for (index, point) in points.enumerated() {
            if let previous = kept.last,
               abs(previous.x - point.x) <= degenerateEdge,
               abs(previous.y - point.y) <= degenerateEdge {
                map[index] = kept.count - 1
                continue
            }
            map[index] = kept.count
            kept.append(point)
            keptMeasures.append(measures[index])
        }
        var anchorSet = Set<Int>()
        for index in anchors where index >= 0 && index < points.count {
            anchorSet.insert(map[index])
        }
        return (kept, keptMeasures, map, anchorSet)
    }

    static func cumulativeLengths(_ points: [Point]) -> [Double] {
        var out = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            out[index] = out[index - 1]
                + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return out
    }

    static func smoothstep(_ t: Double) -> Double {
        let u = t <= 0 ? 0 : (t >= 1 ? 1 : t)
        return u * u * (3 - 2 * u)
    }

    /// Signed turn at an interior vertex, radians.
    static func turnAt(_ points: [Point], _ index: Int) -> Double {
        let a = points[index - 1]
        let b = points[index]
        let c = points[index + 1]
        let ax = b.x - a.x
        let ay = b.y - a.y
        let bx = c.x - b.x
        let by = c.y - b.y
        return atan2(ax * by - ay * bx, ax * bx + ay * by)
    }

    /// The point at measure `s` along the polyline between `low` and `high`,
    /// or beyond either end along that end edge's own direction.
    static func pointAlong(
        _ points: [Point], _ cumulative: [Double], _ s: Double, low: Int, high: Int
    ) -> Point {
        if s <= cumulative[low] {
            let a = points[low]
            let b = points[low + 1]
            var length = cumulative[low + 1] - cumulative[low]
            if length == 0 { length = 1 }
            let t = (s - cumulative[low]) / length
            return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        if s >= cumulative[high] {
            let a = points[high - 1]
            let b = points[high]
            var length = cumulative[high] - cumulative[high - 1]
            if length == 0 { length = 1 }
            let t = (s - cumulative[high]) / length
            return Point(x: b.x + (b.x - a.x) * t, y: b.y + (b.y - a.y) * t)
        }
        var index = low + 1
        while index < high && cumulative[index] < s { index += 1 }
        let a = points[index - 1]
        let b = points[index]
        var length = cumulative[index] - cumulative[index - 1]
        if length == 0 { length = 1 }
        let t = (s - cumulative[index - 1]) / length
        return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Draw the follower from its canonical alignments over its follow
    /// stretches. Returns the new polyline and each original vertex's new
    /// index (-1 where it did not survive).
    static func substituteFollows(
        _ points: [Point], measures: [Double], anchors: Set<Int>, follows: [Follow],
        jointStart: Bool = false, jointEnd: Bool = false
    ) -> (points: [Point], measures: [Double], map: [Int]) {
        let count = points.count
        let identity = (points: points, measures: measures, map: Array(0..<count))
        guard !follows.isEmpty, count >= 2 else { return identity }
        let cumulative = measures
        let first = cumulative[0]
        let totalPx = cumulative[count - 1]
        let blend = followBlendMetres
        // Where this part's end is a JOINT — the vertex it shares with the
        // next part of the same line — no follow may weigh on it. See
        // ``followBlendMetres``.
        let weightFloor = jointStart ? first + blend : -Double.infinity
        let weightCeiling = jointEnd ? totalPx - blend : Double.infinity
        struct Prepared {
            let from: Double
            let to: Double
            let weightFrom: Double
            let weightTo: Double
            let canonFrom: Double
            let canonTo: Double
            let canon: [Point]
            let canonCumulative: [Double]
            let canonTotalPx: Double
        }
        // A follower is drawn from the canonical's own stroke, not its raw
        // survey: a seam jog on the canonical is tapered on the canonical's
        // own pass, and every follower must draw from that tapered shape, or
        // the jog reappears untapered on each of them. Cached per distinct
        // canonical array (by value, `Point`/`Double` arrays have no
        // reference identity in Swift) so N follows onto one canonical taper
        // it once.
        struct TaperedCanonical {
            let rawPoints: [Point]
            let rawMeasures: [Double]
            let points: [Point]
            let measures: [Double]
        }
        var taperedCanonicals: [TaperedCanonical] = []
        func taperedCanonical(_ canon: [Point], _ canonCumulative: [Double]) -> (points: [Point], measures: [Double]) {
            if let cached = taperedCanonicals.first(where: {
                $0.rawPoints == canon && $0.rawMeasures == canonCumulative
            }) {
                return (cached.points, cached.measures)
            }
            let canonPxTotal = cumulativeLengths(canon).last ?? 0
            let canonMetresTotal = canonCumulative[canonCumulative.count - 1] - canonCumulative[0]
            let metresPerPx = canonPxTotal > 0 && canonMetresTotal > 0 ? canonMetresTotal / canonPxTotal : 0
            let tapered = taperJogs(canon, measures: canonCumulative, anchors: Set<Int>(), metresPerPx: metresPerPx)
            taperedCanonicals.append(TaperedCanonical(
                rawPoints: canon, rawMeasures: canonCumulative,
                points: tapered.points, measures: tapered.measures))
            return (tapered.points, tapered.measures)
        }
        var prepared: [Prepared] = []
        for follow in follows {
            let rawCanon = follow.points
            guard rawCanon.count >= 2, follow.to > follow.from,
                  follow.measures.count == rawCanon.count else { continue }
            let rawCanonCumulative = follow.measures
            let rawCanonTotal = rawCanonCumulative[rawCanonCumulative.count - 1]
            guard rawCanonTotal > 0 else { continue }
            // The stretch the follow WEIGHS over, held back from a joint. The
            // correspondence below (`from`/`to` against `canonFrom`/`canonTo`)
            // keeps its reviewed bounds: holding the weight back moves where
            // the substitution applies, never which canonical measure a vertex
            // maps to.
            let weightFrom = max(follow.from, weightFloor)
            let weightTo = min(follow.to, weightCeiling)
            guard weightTo > weightFrom else { continue }
            let (canon, canonCumulative) = taperedCanonical(rawCanon, rawCanonCumulative)
            let canonTotalPx = canonCumulative[canonCumulative.count - 1]
            prepared.append(Prepared(
                from: follow.from, to: follow.to,
                weightFrom: weightFrom, weightTo: weightTo,
                canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                canon: canon, canonCumulative: canonCumulative, canonTotalPx: canonTotalPx))
        }
        guard !prepared.isEmpty else { return identity }
        prepared = prepared.enumerated().sorted {
            $0.element.from < $1.element.from
                || ($0.element.from == $1.element.from && $0.offset < $1.offset)
        }.map(\.element)
        // A follow that begins at the part's own start (or ends at its end) is
        // whole from that end: the kernel would otherwise weight the terminal
        // vertex by half and leave the platform bead between two alignments. A
        // JOINT is the exception, and holding the weight back one blend width
        // is what makes it one: the held-back bound can no longer reach either
        // test, so the kernel runs a full ramp from zero AT the shared vertex.
        func weightsAt(_ s: Double) -> [(w: Double, follow: Prepared)] {
            var held: [(w: Double, follow: Prepared)] = []
            var sum = 0.0
            for follow in prepared {
                let rise = follow.weightFrom <= first + degenerateEdge
                    ? 1 : kernelCumulative(s - follow.weightFrom, width: blend)
                let fall = follow.weightTo >= totalPx - degenerateEdge
                    ? 0 : kernelCumulative(s - follow.weightTo, width: blend)
                let w = rise - fall
                if w > 0 {
                    held.append((w, follow))
                    sum += w
                }
            }
            if sum > 1 { held = held.map { ($0.w / sum, $0.follow) } }
            return held
        }
        func canonPoint(_ follow: Prepared, _ s: Double) -> Point {
            let span = follow.to - follow.from
            let t = span > 0 ? (s - follow.from) / span : 0
            let sc = follow.canonFrom + (follow.canonTo - follow.canonFrom) * t
            let clamped = max(0, min(follow.canonTotalPx, sc))
            return pointAlong(follow.canon, follow.canonCumulative, clamped, low: 0, high: follow.canon.count - 1)
        }
        var extra: [Double] = []
        for follow in prepared {
            let low = min(follow.canonFrom, follow.canonTo)
            let high = max(follow.canonFrom, follow.canonTo)
            let span = follow.canonTo - follow.canonFrom
            if span == 0 { continue }
            for index in 0..<follow.canon.count {
                let sc = follow.canonCumulative[index]
                if sc <= low || sc >= high { continue }
                let s = follow.from + ((sc - follow.canonFrom) / span) * (follow.to - follow.from)
                if s > 0, s < totalPx { extra.append(s) }
            }
        }
        extra.sort()
        var out: [Point] = []
        var outMeasures: [Double] = []
        var map = [Int](repeating: -1, count: count)
        var extraAt = 0
        func emit(_ s: Double, _ own: Point?, _ index: Int) {
            let held = weightsAt(s)
            guard !held.isEmpty else {
                if let own {
                    map[index] = out.count
                    out.append(own)
                    outMeasures.append(s)
                }
                return
            }
            let base = own ?? pointAlong(points, cumulative, s, low: 0, high: count - 1)
            var x = base.x
            var y = base.y
            for entry in held {
                let target = canonPoint(entry.follow, s)
                x += (target.x - base.x) * entry.w
                y += (target.y - base.y) * entry.w
            }
            if own != nil { map[index] = out.count }
            out.append(Point(x: x, y: y))
            outMeasures.append(s)
        }
        for index in 0..<count {
            let s = cumulative[index]
            while extraAt < extra.count, extra[extraAt] < s - degenerateEdge {
                emit(extra[extraAt], nil, -1)
                extraAt += 1
            }
            while extraAt < extra.count, extra[extraAt] <= s + degenerateEdge { extraAt += 1 }
            emit(s, points[index], index)
        }
        return (points: out, measures: outMeasures, map: map)
    }

    /// Redraw every seam jog as a taper. Returns the new polyline and, for
    /// each ORIGINAL vertex that survives, its new index (-1 where it did not).
    static func taperJogs(
        _ points: [Point], measures: [Double], anchors anchorSet: Set<Int>, metresPerPx: Double
    ) -> (points: [Point], measures: [Double], map: [Int]) {
        let count = points.count
        let identity = (points: points, measures: measures, map: Array(0..<count))
        guard count >= 4, metresPerPx > 0 else { return identity }
        let toPx = 1 / metresPerPx
        let minTurn = jogMinTurnDegrees * Double.pi / 180
        let maxTurn = jogMaxTurnDegrees * Double.pi / 180
        let maxNet = jogMaxNetTurnDegrees * Double.pi / 180
        let maxRun = jogMaxRunMetres * toPx
        let minLateral = jogMinLateralMetres * toPx
        let taper = jogTaperMetres * toPx
        let minTaper = jogMinTaperMetres * toPx
        let cumulative = cumulativeLengths(points)
        var turns = [Double](repeating: 0, count: count)
        for index in 1..<(count - 1) { turns[index] = turnAt(points, index) }
        let anchorsSorted = anchorSet.sorted()
        var windows: [(a: Int, b: Int, i: Int, j: Int)] = []
        var lastEnd = 0
        var i = 1
        while i + 1 < count {
            defer { i += 1 }
            let first = turns[i]
            if abs(first) < minTurn || abs(first) > maxTurn { continue }
            var found: Int? = nil
            var net = first
            var j = i + 1
            while j + 1 < count {
                if cumulative[j] - cumulative[i] > maxRun { break }
                let second = turns[j]
                net += second
                if abs(second) >= minTurn, abs(second) <= maxTurn,
                   (second < 0) != (first < 0), second != 0 {
                    if abs(net) <= maxNet { found = j }
                    break
                }
                if abs(second) >= minTurn { break }
                j += 1
            }
            guard let j = found else { continue }
            let a0 = points[i - 1]
            let a1 = points[i]
            let ex = a1.x - a0.x
            let ey = a1.y - a0.y
            var el = hypot(ex, ey)
            if el == 0 { el = 1 }
            let px = points[j].x - a1.x
            let py = points[j].y - a1.y
            let lateral = abs(ex * py - ey * px) / el
            if lateral < minLateral { continue }
            if anchorsSorted.contains(where: { $0 >= i && $0 <= j }) { continue }
            var a = i - 1
            while a > lastEnd, cumulative[i] - cumulative[a - 1] <= taper { a -= 1 }
            // Never back over the previous window.
            if a < lastEnd { a = lastEnd }
            if let anchorBefore = anchorsSorted.last(where: { $0 < i }), anchorBefore > a {
                a = anchorBefore
            }
            var b = j + 1
            while b + 1 < count, cumulative[b + 1] - cumulative[j] <= taper { b += 1 }
            if let anchorAfter = anchorsSorted.first(where: { $0 > j }), anchorAfter < b {
                b = anchorAfter
            }
            if cumulative[i] - cumulative[a] < minTaper || cumulative[b] - cumulative[j] < minTaper {
                continue
            }
            windows.append((a: a, b: b, i: i, j: j))
            lastEnd = b
            i = b - 1
        }
        if windows.isEmpty { return identity }
        var out: [Point] = []
        var outMeasures: [Double] = []
        var map = [Int](repeating: -1, count: count)
        var cursor = 0
        for window in windows {
            for index in cursor...window.a {
                map[index] = out.count
                out.append(points[index])
                outMeasures.append(measures[index])
            }
            let measureStart = measures[window.a]
            let measureEnd = measures[window.b]
            let start = cumulative[window.a]
            let end = cumulative[window.b]
            let span = end - start
            var sampleMeasures = Set<Double>()
            if window.a + 1 < window.b {
                for index in (window.a + 1)..<window.b { sampleMeasures.insert(cumulative[index]) }
            }
            for sample in 1..<jogTaperSamples {
                sampleMeasures.insert(start + (span * Double(sample)) / Double(jogTaperSamples))
            }
            let ordered = sampleMeasures.filter { $0 > start && $0 < end }.sorted()
            for s in ordered {
                let w = smoothstep((s - start) / span)
                let from = pointAlong(points, cumulative, s, low: window.a, high: window.i)
                let to = pointAlong(points, cumulative, s, low: window.j, high: window.b)
                out.append(Point(x: from.x + (to.x - from.x) * w, y: from.y + (to.y - from.y) * w))
                outMeasures.append(measureStart + (measureEnd - measureStart) * ((s - start) / span))
            }
            cursor = window.b
        }
        for index in cursor..<count {
            map[index] = out.count
            out.append(points[index])
            outMeasures.append(measures[index])
        }
        return (points: out, measures: outMeasures, map: map)
    }

    /// Drop every vertex the offset turned into a reversal the survey did
    /// not have, in passes, until none remain.
    static func removeOffsetFolds(_ offset: [Point], original: [Point]) -> (points: [Point], map: [Int]) {
        let count = offset.count
        let foldTurn = foldTurnDegrees * Double.pi / 180
        var reversal = [Bool](repeating: false, count: count)
        if count >= 3 {
            for index in 1..<(count - 1) { reversal[index] = abs(turnAt(original, index)) > foldTurn }
        }
        return removeFolds(offset, reversal: reversal)
    }

    /// The same pass over a polyline whose surveyed reversals are already
    /// known per vertex.
    static func removeFolds(_ offset: [Point], reversal: [Bool]) -> (points: [Point], map: [Int]) {
        let count = offset.count
        let foldTurn = foldTurnDegrees * Double.pi / 180
        var kept = Array(0..<count)
        for _ in 0..<8 {
            var next: [Int] = []
            var dropped = 0
            for at in 0..<kept.count {
                let index = kept[at]
                if at > 0, at + 1 < kept.count, !reversal[index] {
                    let a = offset[kept[at - 1]]
                    let b = offset[index]
                    let c = offset[kept[at + 1]]
                    let ax = b.x - a.x
                    let ay = b.y - a.y
                    let bx = c.x - b.x
                    let by = c.y - b.y
                    if abs(atan2(ax * by - ay * bx, ax * bx + ay * by)) > foldTurn {
                        dropped += 1
                        continue
                    }
                }
                next.append(index)
            }
            kept = next
            if dropped == 0 { break }
        }
        var map = [Int](repeating: -1, count: count)
        for (at, index) in kept.enumerated() { map[index] = at }
        return (points: kept.map { offset[$0] }, map: map)
    }

    /// `joinStart` / `joinEnd` supply the MISSING tangent at a terminal vertex
    /// a part shares with the neighbouring part of the same line: the pair
    /// (incoming, outgoing) at that vertex, derived from the two parts' raw
    /// pixels so both derive the same pair. With it the terminal vertex is
    /// mitred like an interior one instead of taking the one-sided normal, and
    /// the neighbour — which sees the identical pair — lands on the identical
    /// point.
    static func offsetPolyline(
        _ points: [Point], joinStart: Join? = nil, joinEnd: Join? = nil,
        distanceAt: (Int) -> Double
    ) -> [Point] {
        let count = points.count
        var out = [Point](repeating: Point(x: 0, y: 0), count: count)
        for index in 0..<count {
            let point = points[index]
            let d = distanceAt(index)
            if d == 0 {
                out[index] = point
                continue
            }
            var nx = 0.0
            var ny = 0.0
            var scale = 1.0
            var t0: (Double, Double)? = nil
            var t1: (Double, Double)? = nil
            let join = index == 0 ? joinStart : (index == count - 1 ? joinEnd : nil)
            if let join {
                // Both tangents from the joint, so the neighbouring part —
                // which computes the same pair — offsets this vertex to the
                // same place.
                t0 = (join.incoming.x, join.incoming.y)
                t1 = (join.outgoing.x, join.outgoing.y)
            } else {
                if index > 0 {
                    let before = points[index - 1]
                    let dx = point.x - before.x
                    let dy = point.y - before.y
                    var length = hypot(dx, dy)
                    if length == 0 { length = 1 }
                    t0 = (dx / length, dy / length)
                }
                if index + 1 < count {
                    let after = points[index + 1]
                    let dx = after.x - point.x
                    let dy = after.y - point.y
                    var length = hypot(dx, dy)
                    if length == 0 { length = 1 }
                    t1 = (dx / length, dy / length)
                }
            }
            if let t0, let t1 {
                let bx = -t0.1 - t1.1
                let by = t0.0 + t1.0
                let length = hypot(bx, by)
                if length > 1e-9 {
                    nx = bx / length
                    ny = by / length
                    let cosHalf = max(1e-6, length / 2)
                    scale = min(miterLimit, 1 / cosHalf)
                } else {
                    nx = -t0.1
                    ny = t0.0
                }
            } else {
                let t = t0 ?? t1 ?? (1, 0)
                nx = -t.1
                ny = t.0
            }
            out[index] = Point(x: point.x + nx * d * scale, y: point.y + ny * d * scale)
        }
        return out
    }

    /// `measures` (aligned with `points`) is carried along: the tangent
    /// start and end get the measure that far from the vertex's own
    /// measure, along each edge, and every interior curve sample is the
    /// linear interpolation between those two in the curve parameter `u`.
    ///
    /// A CORNER IS A RUN, NOT ALWAYS A VERTEX. `radius` is what a corner is
    /// rounded to when its two edges can carry it; `floorRadius` is what it is
    /// rounded to at worst. Where consecutive vertices sit closer together
    /// than the pen is wide — a welded survey duplicate, a real curve sampled
    /// every 20 m and drawn at a regional zoom — no single one of them has an
    /// edge long enough to carry even the floor, and rounding each in
    /// isolation draws the bare kink this file exists to remove. So the run is
    /// rounded AS ONE CORNER: the arc is tangent to the edge arriving at the
    /// run and to the edge leaving it, about their intersection.
    ///
    /// The merge is deliberately narrow, because a corner cut across real
    /// geometry is worse than a kink: a station anchor is never inside a run
    /// and never moves; a surveyed reversal (turn > ``filletMaxTurnDegrees``)
    /// is never inside a run and stays exactly as surveyed; a run grows
    /// toward the RADIUS it is promising, not the floor it would settle
    /// for — it keeps absorbing edges only while a longer run could still
    /// carry more of `radius` (bounded, as any single-vertex corner is, by
    /// `filletMaxTangentShare` of the run's own outer edges), so it may span
    /// at most `radius` of arc length; and the arc is rejected outright
    /// unless every vertex it replaces ends up within `floorRadius` of it.
    /// With `floorRadius` 0 no run is ever formed and every corner is exactly
    /// the single-vertex fillet this function has always drawn.
    static func fillet(
        _ points: [Point], radius: Double, floorRadius: Double, anchors: Set<Int>,
        measures: [Double]
    ) -> (points: [Point], measures: [Double]) {
        let count = points.count
        guard radius > 0, count >= 3 else { return (points, measures) }
        let minTurn = filletMinTurnDegrees * Double.pi / 180
        let maxTurn = filletMaxTurnDegrees * Double.pi / 180
        let step = filletStepDegrees * Double.pi / 180
        let floor = floorRadius > 0 ? min(floorRadius, radius) : 0
        // Which interior vertices may not be swallowed by a run, and how
        // sharply each one turns.
        var turns = [Double](repeating: 0, count: count)
        var hard = [Bool](repeating: false, count: count)
        for index in 1..<(count - 1) {
            let ax = points[index].x - points[index - 1].x
            let ay = points[index].y - points[index - 1].y
            let bx = points[index + 1].x - points[index].x
            let by = points[index + 1].y - points[index].y
            let la = hypot(ax, ay)
            let lb = hypot(bx, by)
            if la <= degenerateEdge || lb <= degenerateEdge {
                hard[index] = true
                continue
            }
            let dot = max(-1, min(1, (ax * bx + ay * by) / (la * lb)))
            turns[index] = acos(dot)
            if turns[index] > maxTurn { hard[index] = true }
        }
        for index in anchors where index > 0 && index + 1 < count { hard[index] = true }
        let cumulative = cumulativeLengths(points)
        var out: [Point] = [points[0]]
        var outMeasures: [Double] = [measures[0]]
        // Where the previous corner left the polyline: the edge it ended on
        // (by its start vertex) and how far along that edge. A corner never
        // starts before it, so two corners can never cross however the runs
        // fell.
        var guardEdge = -1
        var guardOffset = 0.0

        struct Corner {
            let last: Int
            let curve: [Point]
            let achieved: Double
            let endOffset: Double
            let mStart: Double
            let mEnd: Double
        }

        func cornerOf(_ first: Int, _ last: Int) -> Corner? {
            let before = points[first - 1]
            let after = points[last + 1]
            let ax = points[first].x - before.x
            let ay = points[first].y - before.y
            let la = hypot(ax, ay)
            if la <= degenerateEdge { return nil }
            let t0x = ax / la
            let t0y = ay / la
            let bx = after.x - points[last].x
            let by = after.y - points[last].y
            let lb = hypot(bx, by)
            if lb <= degenerateEdge { return nil }
            let t1x = bx / lb
            let t1y = by / lb
            let dot = max(-1, min(1, t0x * t1x + t0y * t1y))
            let turn = acos(dot)
            if turn < minTurn || turn > maxTurn { return nil }
            // The corner's apex: where the two tangent lines meet, given as
            // its offset from the run's first vertex along the incoming
            // tangent and from its last along the outgoing one. For a run of
            // one both are exactly zero and the apex is the vertex itself, so
            // a single corner stays bit-for-bit the fillet this function has
            // always drawn.
            var apex = points[first]
            var apexBack = 0.0
            var apexForward = 0.0
            if last > first {
                let cross = t0x * t1y - t0y * t1x
                if !(abs(cross) > degenerateEdge) { return nil }
                let rx = after.x - points[first].x
                let ry = after.y - points[first].y
                apexBack = (rx * t1y - ry * t1x) / cross
                apex = Point(
                    x: points[first].x + t0x * apexBack, y: points[first].y + t0y * apexBack)
                apexForward = (apex.x - points[last].x) * t1x + (apex.y - points[last].y) * t1y
            }
            let back = la + apexBack
            let forward = lb - apexForward
            if !(back > 0) || !(forward > 0) { return nil }
            let half = tan(turn / 2)
            var tangent = min(
                radius * half, filletMaxTangentShare * back, filletMaxTangentShare * forward)
            if guardEdge == first - 1, back - tangent < guardOffset {
                tangent = back - guardOffset
            }
            if !(tangent > degenerateEdge) { return nil }
            let start = Point(x: apex.x - t0x * tangent, y: apex.y - t0y * tangent)
            let end = Point(x: apex.x + t1x * tangent, y: apex.y + t1y * tangent)
            let samples = max(2, Int((turn / step).rounded(.up)))
            var curve: [Point] = [start]
            if samples > 1 {
                for sample in 1..<samples {
                    let u = Double(sample) / Double(samples)
                    let v = 1 - u
                    curve.append(Point(
                        x: v * v * start.x + 2 * u * v * apex.x + u * u * end.x,
                        y: v * v * start.y + 2 * u * v * apex.y + u * u * end.y))
                }
            }
            curve.append(end)
            // Nothing a run swallows may end up further than the floor from
            // the arc that replaced it.
            if last > first {
                for index in first...last
                where distanceToPolyline(points[index], curve) > floor {
                    return nil
                }
            }
            let dStart = apexBack - tangent
            let dEnd = apexForward + tangent
            return Corner(
                last: last, curve: curve, achieved: tangent / half, endOffset: dEnd,
                mStart: measures[first] + (dStart * (measures[first] - measures[first - 1])) / la,
                mEnd: measures[last] + (dEnd * (measures[last + 1] - measures[last])) / lb)
        }

        // A station platform's vertex must not turn sharply into its dot
        // (rules §10.9), but it also must not move: the anchor's bead is
        // read from this exact coordinate before this function ever runs
        // (see buildStroke). So a lone anchor corner is not CUT AWAY like
        // an ordinary fillet — it is replaced by a circular arc that passes
        // THROUGH the vertex: three points on one circle, the tangent
        // points T1/T2 on the incoming and outgoing edges and the vertex
        // itself between them. The tangent length reuses the ordinary
        // corner's rule. T1, vertex and T2 form an isosceles triangle (two
        // sides the tangent length, apex angle π − turn at the vertex), so
        // the circumradius has the closed form tangent / (2·sin(turn / 2))
        // — but the centre and the sweep direction are still solved
        // generally, the same way for every turn from filletMinTurnDegrees
        // to filletMaxTurnDegrees.
        func anchorCornerOf(_ index: Int) -> Corner? {
            let before = points[index - 1]
            let after = points[index + 1]
            let ax = points[index].x - before.x
            let ay = points[index].y - before.y
            let la = hypot(ax, ay)
            if la <= degenerateEdge { return nil }
            let t0x = ax / la
            let t0y = ay / la
            let bx = after.x - points[index].x
            let by = after.y - points[index].y
            let lb = hypot(bx, by)
            if lb <= degenerateEdge { return nil }
            let t1x = bx / lb
            let t1y = by / lb
            let dot = max(-1, min(1, t0x * t1x + t0y * t1y))
            let turn = acos(dot)
            if turn < minTurn || turn > maxTurn { return nil }
            let half = tan(turn / 2)
            var tangent = min(
                radius * half, filletMaxTangentShare * la, filletMaxTangentShare * lb)
            if guardEdge == index - 1, la - tangent < guardOffset {
                tangent = la - guardOffset
            }
            if !(tangent > degenerateEdge) { return nil }
            // tangent <= filletMaxTangentShare * la (0.45 * la) and likewise
            // for lb by construction above, and the guardEdge clamp above
            // only ever shrinks tangent further — so la >= 2*tangent and
            // lb >= 2*tangent always hold; neither edge can be shorter than
            // twice what the arc borrows from it.
            let vertex = points[index]
            let t1Point = Point(x: vertex.x - t0x * tangent, y: vertex.y - t0y * tangent)
            let t2Point = Point(x: vertex.x + t1x * tangent, y: vertex.y + t1y * tangent)
            // Circumcircle of t1Point, vertex, t2Point, solved relative to
            // the vertex rather than in absolute (web-mercator, ~1e7)
            // coordinates: the three points are only `tangent` (a few
            // pixels) apart, so solving in absolute space subtracts
            // nearly-equal huge numbers and is ill conditioned. Translating
            // the vertex to the origin first keeps the arithmetic well
            // behaved at any zoom or tile offset; the centre is translated
            // back to absolute space afterwards.
            let p1x = -t0x * tangent, p1y = -t0y * tangent
            let p2x = 0.0, p2y = 0.0
            let p3x = t1x * tangent, p3y = t1y * tangent
            let d = 2 * (p1x * (p2y - p3y) + p2x * (p3y - p1y) + p3x * (p1y - p2y))
            if !(abs(d) > 0) { return nil }
            let sq1 = p1x * p1x + p1y * p1y
            let sq2 = p2x * p2x + p2y * p2y
            let sq3 = p3x * p3x + p3y * p3y
            let cxRel = (sq1 * (p2y - p3y) + sq2 * (p3y - p1y) + sq3 * (p1y - p2y)) / d
            let cyRel = (sq1 * (p3x - p2x) + sq2 * (p1x - p3x) + sq3 * (p2x - p1x)) / d
            let cx = vertex.x + cxRel
            let cy = vertex.y + cyRel
            let arcRadius = hypot(p2x - cxRel, p2y - cyRel)
            let a1 = atan2(p1y - cyRel, p1x - cxRel)
            let aV = atan2(p2y - cyRel, p2x - cxRel)
            let a2 = atan2(p3y - cyRel, p3x - cxRel)
            func angleDiff(_ from: Double, _ to: Double) -> Double {
                var delta = to - from
                while delta <= -Double.pi { delta += 2 * Double.pi }
                while delta > Double.pi { delta -= 2 * Double.pi }
                return delta
            }
            let short = angleDiff(a1, a2)
            let toApex = angleDiff(a1, aV)
            let sameSign = (short >= 0 && toApex >= 0) || (short <= 0 && toApex <= 0)
            let sweep =
                sameSign && abs(toApex) <= abs(short)
                ? short
                : short - (short == 0 ? 1 : short.sign == .minus ? -1 : 1) * 2 * Double.pi
            // An anchor arc always uses an EVEN sample count (twice the
            // number of FILLET_STEP_DEGREES-sized half-steps the turn
            // needs), so the forced apex sample below lands at index
            // samples/2 exactly — the true analytic midpoint (u = 0.5) of
            // the arc, not an approximation of it.
            let samples = 2 * max(1, Int((turn / (2 * step)).rounded(.up)))
            var curve: [Point] = [t1Point]
            for sample in 1..<samples {
                let u = Double(sample) / Double(samples)
                let angle = a1 + sweep * u
                curve.append(Point(x: cx + arcRadius * cos(angle), y: cy + arcRadius * sin(angle)))
            }
            curve.append(t2Point)
            // The apex sample is forced to the vertex exactly — the bead
            // (the same coordinate, read in buildStroke before this
            // function ever runs) must sit ON the drawn line to the bit,
            // not merely near it. Plain integer arithmetic (not a ratio of
            // trig results, which can differ between JS's and Swift's
            // atan2 by float noise) so both ports pick the identical index.
            let apexIndex = samples / 2
            curve[apexIndex] = Point(x: vertex.x, y: vertex.y)
            return Corner(
                last: index, curve: curve, achieved: tangent / half, endOffset: tangent,
                mStart: measures[index] - (tangent * (measures[index] - measures[index - 1])) / la,
                mEnd: measures[index] + (tangent * (measures[index + 1] - measures[index])) / lb)
        }

        var index = 1
        while index + 1 < count {
            if anchors.contains(index), let arc = anchorCornerOf(index) {
                for sample in 0..<arc.curve.count {
                    let u = Double(sample) / Double(arc.curve.count - 1)
                    out.append(arc.curve[sample])
                    outMeasures.append(arc.mStart + (arc.mEnd - arc.mStart) * u)
                }
                guardEdge = arc.last
                guardOffset = arc.endOffset
                index += 1
                continue
            }
            if hard[index] || turns[index] < minTurn {
                out.append(points[index])
                outMeasures.append(measures[index])
                index += 1
                continue
            }
            // Grow the run toward the promised radius, not the floor — the
            // floor only gates whether merging is attempted at all (0
            // disables it, run stays a single vertex, exactly as before).
            // Stop as soon as a candidate reaches `radius`, the next vertex
            // is off limits (a station anchor, a reversal, or the part's own
            // end), or the run has already grown past `radius` of arc
            // length — beyond that its own outer edges (capped by
            // `filletMaxTangentShare`) cannot feed the fillet any further,
            // so growing more only risks cutting across real geometry for
            // no gain. Keep the best corner any candidate managed.
            //
            // "Reaches `radius`" is asked with a `degenerateEdge` allowance,
            // not bit-exactly: `achieved` is `tangent / half` where `tangent`
            // was itself `min(radius * half, …)`, and dividing back out does
            // not always return exactly `radius` — the multiply-then-divide
            // round trip can land a couple of ULPs short. `half` is `tan` of
            // a turn this port and rail-stroke.js's do not compute through
            // identical library code, so the two can even disagree on which
            // side of exact `radius` that round trip lands on. Without the
            // allowance, one port stops the run at this vertex while the
            // other — reading the same `achieved` as "not quite there yet" —
            // keeps absorbing the next one, so a single vertex ends up
            // rounded on one side and merged into a two-vertex run on the
            // other. An allowance many orders below any real geometric
            // radius removes the tie without weakening what "reaches" means.
            var best: Corner? = nil
            var last = index
            while true {
                if let corner = cornerOf(index, last),
                   best == nil || corner.achieved > best!.achieved {
                    best = corner
                }
                if let best, best.achieved >= radius - degenerateEdge { break }
                if !(floor > 0) { break }
                if last + 1 >= count - 1 || hard[last + 1] { break }
                if cumulative[last + 1] - cumulative[index] > radius { break }
                last += 1
            }
            guard let corner = best else {
                out.append(points[index])
                outMeasures.append(measures[index])
                index += 1
                continue
            }
            for sample in 0..<corner.curve.count {
                let u = Double(sample) / Double(corner.curve.count - 1)
                out.append(corner.curve[sample])
                outMeasures.append(corner.mStart + (corner.mEnd - corner.mStart) * u)
            }
            guardEdge = corner.last
            guardOffset = corner.endOffset
            index = corner.last + 1
        }
        out.append(points[count - 1])
        outMeasures.append(measures[measures.count - 1])
        return (out, outMeasures)
    }

    /// The distance from a point to a polyline, in the same pixel space.
    static func distanceToPolyline(_ point: Point, _ polyline: [Point]) -> Double {
        var best = Double.infinity
        for index in 0..<(polyline.count - 1) {
            let a = polyline[index]
            let b = polyline[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let square = dx * dx + dy * dy
            var t = square > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / square : 0
            t = max(0, min(1, t))
            let held = hypot(point.x - a.x - dx * t, point.y - a.y - dy * t)
            if held < best { best = held }
        }
        return best
    }

    /// The nearest point on `polyline` to `target`, restricted to the
    /// segments whose measure range overlaps [mLo, mHi]. Used to project a
    /// fold-dropped anchor onto the FINAL emitted (post-fillet) line rather
    /// than the raw pre-fillet edge: a fillet at either endpoint of that
    /// edge trims it, so searching the whole edge's original span would
    /// still land on ink the fillet has since replaced. Restricting by
    /// measure (rather than searching the whole line) also keeps this from
    /// snapping to an unrelated, nearer part of a line that loops back on
    /// itself. Returns nil only if `polyline` has fewer than two points.
    static func nearestOnMeasureSpan(
        _ target: Point, polyline: [Point], measures: [Double], mLo: Double, mHi: Double
    ) -> Point? {
        let lo = min(mLo, mHi)
        let hi = max(mLo, mHi)
        var best: Point? = nil
        var bestDistSq = Double.infinity
        guard polyline.count >= 2 else { return nil }
        for index in 0..<(polyline.count - 1) {
            if measures[index + 1] < lo || measures[index] > hi { continue }
            let a = polyline[index]
            let b = polyline[index + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let square = dx * dx + dy * dy
            var t = square > 0 ? ((target.x - a.x) * dx + (target.y - a.y) * dy) / square : 0
            t = max(0, min(1, t))
            let px = a.x + dx * t
            let py = a.y + dy * t
            let distX = target.x - px
            let distY = target.y - py
            let distSq = distX * distX + distY * distY
            if distSq < bestDistSq {
                bestDistSq = distSq
                best = Point(x: px, y: py)
            }
        }
        return best
    }
}
