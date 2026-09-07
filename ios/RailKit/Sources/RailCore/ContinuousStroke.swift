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
    /// A corridor follow is blended in and out over this half-width, in
    /// metres, with the same kernel as a lane change.
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
    /// A fillet may borrow at most this share of each edge it sits on.
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
        public var anchors: [Int]
        public var follows: [Follow]
        public init(
            measures: [Double] = [], rows: [LaneRow], totalMetres: Double, laneGapPx: Double,
            minRampPx: Double, cornerRadiusPx: Double, anchors: [Int],
            follows: [Follow] = []
        ) {
            self.measures = measures
            self.rows = rows
            self.totalMetres = totalMetres
            self.laneGapPx = laneGapPx
            self.minRampPx = minRampPx
            self.cornerRadiusPx = cornerRadiusPx
            self.anchors = anchors
            self.follows = follows
        }
    }

    public struct Stroke: Equatable, Sendable {
        public var points: [Point]
        /// `anchors[i]` is the offset position of `points[options.anchors[i]]`.
        public var anchors: [Point]
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

    public static func laneProfile(rows: [LaneRow], total: Double) -> [Plateau] {
        guard total > 0 else { return [] }
        var plateaus: [Plateau] = []
        var cursor = 0.0
        // JavaScript's sort is stable; so is Swift's since 5.
        let sorted = rows.sorted { $0.from < $1.from }
        for row in sorted {
            let from = max(cursor, min(row.from, total))
            let to = max(from, min(row.to, total))
            if from > cursor { plateaus.append(Plateau(from: cursor, to: from, lane: 0)) }
            if to > from { plateaus.append(Plateau(from: from, to: to, lane: row.lane)) }
            cursor = to
        }
        if cursor < total { plateaus.append(Plateau(from: cursor, to: total, lane: 0)) }
        return coalesce(plateaus)
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
            return Stroke(points: points, anchors: [])
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
        guard clean.count >= 2 else {
            let only = clean.first ?? points[0]
            return Stroke(points: [only, only], anchors: options.anchors.map { _ in only })
        }
        let gap = options.laneGapPx
        let cleanCumulative = cumulativeLengths(clean)
        let cleanTotalPx = cleanCumulative[cleanCumulative.count - 1]
        let totalMetres = cleanMeasures[cleanMeasures.count - 1] - cleanMeasures[0]
        let metresPerPx = cleanTotalPx > 0 && totalMetres > 0 ? totalMetres / cleanTotalPx : 0
        let substituted = substituteFollows(
            clean, measures: cleanMeasures, anchors: anchorSet, follows: options.follows)
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
                reversal[at] = cleanReversal[index]
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
        if gap != 0, options.rows.contains(where: { $0.lane != 0 }), totalMetres > 0 {
            let profile = laneProfile(rows: options.rows, total: totalMetres)
            let width = max(laneRampHalfWidthMetres, options.minRampPx * metresPerPx)
            if !profileIsFlat(profile) {
                offset = offsetPolyline(base) { index in
                    laneAt(profile: profile, measure: tapered.measures[index], width: width) * gap
                }
                offsetApplied = true
            }
        }
        let cleaned = offsetApplied
            ? removeOffsetFolds(offset, original: base)
            : (points: base, map: Array(0..<base.count))
        var finalAnchors = Set<Int>()
        for index in taperedAnchors where cleaned.map[index] >= 0 {
            finalAnchors.insert(cleaned.map[index])
        }
        let anchors = options.anchors.map { index -> Point in
            guard index >= 0, index < anchorMap.count else { return offset[offset.count - 1] }
            let moved = tapered.map[anchorMap[index]]
            return moved < 0 ? offset[offset.count - 1] : offset[moved]
        }
        let rounded = fillet(cleaned.points, radius: options.cornerRadiusPx, anchors: finalAnchors)
        return Stroke(points: rounded, anchors: anchors)
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
        _ points: [Point], measures: [Double], anchors: Set<Int>, follows: [Follow]
    ) -> (points: [Point], measures: [Double], map: [Int]) {
        let count = points.count
        let identity = (points: points, measures: measures, map: Array(0..<count))
        guard !follows.isEmpty, count >= 2 else { return identity }
        let cumulative = measures
        let totalPx = cumulative[count - 1]
        let blend = followBlendMetres
        struct Prepared {
            let from: Double
            let to: Double
            let canonFrom: Double
            let canonTo: Double
            let canon: [Point]
            let canonCumulative: [Double]
            let canonTotalPx: Double
        }
        var prepared: [Prepared] = []
        for follow in follows {
            let canon = follow.points
            guard canon.count >= 2, follow.to > follow.from,
                  follow.measures.count == canon.count else { continue }
            let canonCumulative = follow.measures
            let canonTotalPx = canonCumulative[canonCumulative.count - 1]
            guard canonTotalPx > 0 else { continue }
            prepared.append(Prepared(
                from: follow.from, to: follow.to,
                canonFrom: follow.canonFrom, canonTo: follow.canonTo,
                canon: canon, canonCumulative: canonCumulative, canonTotalPx: canonTotalPx))
        }
        guard !prepared.isEmpty else { return identity }
        prepared.sort { $0.from < $1.from }
        let first = cumulative[0]
        func weightsAt(_ s: Double) -> [(w: Double, follow: Prepared)] {
            var held: [(w: Double, follow: Prepared)] = []
            var sum = 0.0
            for follow in prepared {
                let rise = follow.from <= first + degenerateEdge
                    ? 1 : kernelCumulative(s - follow.from, width: blend)
                let fall = follow.to >= totalPx - degenerateEdge
                    ? 0 : kernelCumulative(s - follow.to, width: blend)
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

    static func offsetPolyline(_ points: [Point], distanceAt: (Int) -> Double) -> [Point] {
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

    static func fillet(_ points: [Point], radius: Double, anchors: Set<Int>) -> [Point] {
        guard radius > 0, points.count >= 3 else { return points }
        let minTurn = filletMinTurnDegrees * Double.pi / 180
        let maxTurn = filletMaxTurnDegrees * Double.pi / 180
        let step = filletStepDegrees * Double.pi / 180
        var out: [Point] = [points[0]]
        var index = 1
        while index + 1 < points.count {
            defer { index += 1 }
            let point = points[index]
            if anchors.contains(index) {
                out.append(point)
                continue
            }
            let before = points[index - 1]
            let after = points[index + 1]
            let ax = point.x - before.x
            let ay = point.y - before.y
            let bx = after.x - point.x
            let by = after.y - point.y
            let la = hypot(ax, ay)
            let lb = hypot(bx, by)
            if la <= degenerateEdge || lb <= degenerateEdge {
                out.append(point)
                continue
            }
            let t0x = ax / la
            let t0y = ay / la
            let t1x = bx / lb
            let t1y = by / lb
            let dot = max(-1, min(1, t0x * t1x + t0y * t1y))
            let turn = acos(dot)
            if turn < minTurn || turn > maxTurn {
                out.append(point)
                continue
            }
            let tangent = min(radius * tan(turn / 2), filletMaxTangentShare * min(la, lb))
            if !(tangent > degenerateEdge) {
                out.append(point)
                continue
            }
            let start = Point(x: point.x - t0x * tangent, y: point.y - t0y * tangent)
            let end = Point(x: point.x + t1x * tangent, y: point.y + t1y * tangent)
            let samples = max(2, Int((turn / step).rounded(.up)))
            out.append(start)
            if samples > 1 {
                for sample in 1..<samples {
                    let u = Double(sample) / Double(samples)
                    let v = 1 - u
                    out.append(Point(
                        x: v * v * start.x + 2 * u * v * point.x + u * u * end.x,
                        y: v * v * start.y + 2 * u * v * point.y + u * u * end.y))
                }
            }
            out.append(end)
        }
        out.append(points[points.count - 1])
        return out
    }
}
