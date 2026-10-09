import Foundation

// ─────────────────────────────────────────────────────────────────────────
//  canonicalizeRouteFeature — the pixels of a ride.
//
//  Ported from `app/public/rail-network.js`. The route solver has already
//  decided WHICH railway a train used; this decides what gets drawn. It
//  projects the solved endpoints onto the already-built complete display line
//  and returns an exact slice of that same LineString, which is the only
//  reason the ridden layer and the all-railways layer cannot drift apart,
//  disagree at a station, or apply different micro-kink grooming — they are
//  literally the same vertices.
//
//  Almost every rule below exists because of a specific railway. Those names
//  are kept: they are the evidence, and a rule whose reason has been filed off
//  is a rule the next reader will "simplify".
// ─────────────────────────────────────────────────────────────────────────

/// A GeoJSON geometry in the two shapes the route pipeline produces.
///
/// The distinction survives the function: a MultiLineString in is a
/// MultiLineString out, because the caller uses that type to mean "one path
/// with gaps in it" (`geometry_role: single_path_with_gaps`) and collapsing it
/// would join two strokes the solver deliberately left apart.
public enum RouteGeometry: Sendable, Equatable {
    case lineString([Coordinate])
    case multiLineString([[Coordinate]])

    /// `routeGeometryLines` — every geometry read as a list of strokes.
    public var lines: [[Coordinate]] {
        switch self {
        case .lineString(let coordinates): return [coordinates]
        case .multiLineString(let coordinates): return coordinates
        }
    }
}

/// The solver's line and operator hints, in the order the JavaScript reads
/// them.
///
/// In the JavaScript the `used_*` fields are OBJECTS — `{"東海道線": 508}`,
/// the number being how many of the path's coordinates came off that railway —
/// and `routeHintValues` collects their keys with `Object.keys`. That
/// iteration order decides the order candidate lines are gathered in, and
/// `bestFitFor` keeps the FIRST candidate when two score equally, so the order
/// can decide which railway a ride is drawn on. Swift's `JSONDecoder` returns
/// an unordered `Dictionary`, so this type takes the key sequence directly and
/// the fixture generator freezes it with `Object.keys` itself.
///
/// The `required_*` / `preferred_*` fields really are arrays, and really do
/// contain nulls and empty strings in hand-written features, which is why the
/// element type is optional.
public struct RouteHints: Sendable, Equatable {
    public var requiredLineNames: [String?]
    public var preferredLineNames: [String?]
    public var usedLineNames: [String]
    public var requiredOperatorNames: [String?]
    public var preferredOperatorNames: [String?]
    public var usedOperatorNames: [String]
    public var requiredLineIDs: [String]
    public var sectionCodes: [String]
    public var fromStationCode: String?
    public var toStationCode: String?

    public init(
        requiredLineNames: [String?] = [],
        preferredLineNames: [String?] = [],
        usedLineNames: [String] = [],
        requiredOperatorNames: [String?] = [],
        preferredOperatorNames: [String?] = [],
        usedOperatorNames: [String] = [],
        requiredLineIDs: [String] = [], sectionCodes: [String] = [],
        fromStationCode: String? = nil, toStationCode: String? = nil
    ) {
        self.requiredLineNames = requiredLineNames
        self.preferredLineNames = preferredLineNames
        self.usedLineNames = usedLineNames
        self.requiredOperatorNames = requiredOperatorNames
        self.preferredOperatorNames = preferredOperatorNames
        self.usedOperatorNames = usedOperatorNames
        self.requiredLineIDs = requiredLineIDs
        self.sectionCodes = sectionCodes
        self.fromStationCode = fromStationCode
        self.toStationCode = toStationCode
    }
}

/// One solved hop: the path the solver walked, and what it says it walked on.
///
/// The JavaScript passes a whole GeoJSON Feature and returns a copy of it with
/// two properties added, so every other property rides through untouched. That
/// spread is the one part of the function with nothing to port — a Swift
/// caller keeps its own feature and attaches ``CanonicalRoute`` to it — so this
/// type carries only what the function actually reads.
public struct RouteFeature: Sendable, Equatable {
    public var geometry: RouteGeometry?
    public var hints: RouteHints

    public init(geometry: RouteGeometry?, hints: RouteHints = RouteHints()) {
        self.geometry = geometry
        self.hints = hints
    }
}

/// What the function adds to a feature it could canonicalise.
public struct CanonicalRoute: Sendable, Equatable {
    public var geometry: RouteGeometry
    /// `display_line_ids` — deduplicated in first-seen order.
    public var displayLineIds: [String]
    public var matchedSectionCodes: [String] = []
    public var directionCorrected: Bool = false
    /// `display_geometry_source`. A constant, and a promise: these coordinates
    /// came off the complete display line rather than the solver's own path.
    public var displayGeometrySource: String { "all-railways-complete-line" }
}

/// A memo of point-onto-part projections, owned by the caller.
///
/// The JavaScript hangs this on the network object (`routeProjectionCache`) and
/// it survives across calls, which matters when a whole itinerary is drawn: the
/// same station point is projected onto the same part by every hop that touches
/// it. `RouteNetwork` is a value type and must stay `Sendable`, so the cache is
/// passed in rather than hidden inside it — same lifetime, visible ownership.
///
/// It cannot change an answer. The key rounds the point to seven decimals, so
/// two DIFFERENT points would have to fall within about a centimetre of each
/// other, on the same part, in the same call chain, for the memo to answer for
/// the wrong one. Nothing in the shipped packages comes close, and the fixture
/// runs every case with a fresh cache so that the frozen answers cannot depend
/// on which case ran before.
public struct RouteProjectionCache: Sendable {
    var storage: [String: RouteNetwork.Projection] = [:]
    public init() {}
}

// ─────────────────────────────────────────────────────────────────────────

/// The drawn railway, indexed the way `canonicalizeRouteFeature` reads it.
///
/// This is the part of `buildNetworkFromCompactPackage` the function touches:
/// the display lines, and the two name indexes over them. `parts` is the drawn
/// geometry — a line that carries branches renders as several DISJOINT strokes
/// that meet at a station, so that nothing can draw or slice straight through
/// a junction — and it arrives here already built, because the pass that builds
/// it (`displayPartsForLine`: station anchoring, branch cutting, fold trimming,
/// micro-kink smoothing) is not ported yet.
public struct RouteNetwork: Sendable {

    public struct Line: Sendable {
        public let lineId: String
        public let name: String?
        public let `operator`: String?
        /// A closed line. Only ever acted on when the whole line is ONE part:
        /// a split line's parts are open strokes even when the package marks
        /// the line as a loop.
        public let isLoop: Bool
        /// `"up"` / `"down"` when the package carries a SOURCED direction for
        /// a paired alignment, `"unassigned"` when it has the pair but not the
        /// direction, `nil` when the line is not one half of a pair.
        public let alignmentDirection: String?
        /// One entry per disjoint drawn stroke.
        public let parts: [[Coordinate]]
        public let intervals: [RailIntervalCodes.Interval]
        public let compactLine: CompactPackage.Line?

        public init(
            lineId: String,
            name: String?,
            operator operatorName: String?,
            isLoop: Bool,
            alignmentDirection: String?,
            parts: [[Coordinate]],
            intervals: [RailIntervalCodes.Interval] = [],
            compactLine: CompactPackage.Line? = nil
        ) {
            self.lineId = lineId
            self.name = name
            self.operator = operatorName
            self.isLoop = isLoop
            self.alignmentDirection = alignmentDirection
            self.parts = parts
            self.intervals = intervals
            self.compactLine = compactLine
        }
    }

    public let lines: [Line]
    /// `linesByName` / `linesByOperator`, holding indexes into `lines`.
    ///
    /// Insertion order inside a bucket is the package's own line order and is
    /// load-bearing: 東鐵綫 is three strokes under one name, and the first one
    /// to reach a given score is the one that wins.
    let linesByName: [String: [Int]]
    let linesByOperator: [String: [Int]]
    /// One metric per line per display part, built once. The JavaScript
    /// memoises this onto the line object the first time it is asked for;
    /// building it up front is the same numbers with no hidden mutation.
    let metrics: [[PartMetric]]
    let intervalByCode: [String: (lineIndex: Int, intervalIndex: Int, interval: RailIntervalCodes.Interval)]
    let knownStationCodes: Set<String>
    let stationLineIndices: [String: Set<Int>]
    let familyLineIndices: [String: [Int]]
    let sourceMetrics: [[SourceMetric]]

    public init(lines: [Line]) {
        self.lines = lines
        var byName: [String: [Int]] = [:]
        var byOperator: [String: [Int]] = [:]
        for (index, line) in lines.enumerated() {
            // `addIndexValue` refuses a falsy key, so a line with no name is
            // reachable only through the operator index — or not at all.
            if let name = line.name, !name.isEmpty { byName[name, default: []].append(index) }
            if let op = line.operator, !op.isEmpty { byOperator[op, default: []].append(index) }
        }
        linesByName = byName
        linesByOperator = byOperator
        var intervalIndex: [String: (lineIndex: Int, intervalIndex: Int, interval: RailIntervalCodes.Interval)] = [:]
        var stationCodes: Set<String> = []
        var stationLines: [String: Set<Int>] = [:]
        for (index, line) in lines.enumerated() {
            for (offset, interval) in line.intervals.enumerated() {
                if intervalIndex[interval.code] == nil { intervalIndex[interval.code] = (index, offset, interval) }
                stationCodes.insert(interval.fromStationCode)
                stationCodes.insert(interval.toStationCode)
                stationLines[interval.fromStationCode, default: []].insert(index)
                stationLines[interval.toStationCode, default: []].insert(index)
            }
        }
        intervalByCode = intervalIndex
        knownStationCodes = stationCodes
        stationLineIndices = stationLines
        var families: [String: [Int]] = [:]
        for (index, line) in lines.enumerated() {
            families[Self.familyKey(line), default: []].append(index)
        }
        familyLineIndices = families
        sourceMetrics = lines.map { line in line.intervals.compactMap { interval in
            guard interval.coordinates.count >= 2 else { return nil }
            let points = interval.coordinates
            return SourceMetric(
                coordinates: points, cumulative: Self.cumulativeMeasures(points),
                minLon: points.map(\.lon).min()!, maxLon: points.map(\.lon).max()!,
                minLat: points.map(\.lat).min()!, maxLat: points.map(\.lat).max()!)
        } }
        metrics = lines.map { line in
            line.parts.map { coordinates in
                var cumulative = [0.0]
                cumulative.reserveCapacity(coordinates.count)
                for index in 1..<max(coordinates.count, 1) {
                    cumulative.append(
                        cumulative[index - 1]
                            + Metric.distanceMeters(coordinates[index - 1], coordinates[index])
                    )
                }
                return PartMetric(coordinates: coordinates, cumulative: cumulative)
            }
        }
    }

    /// One display part, with the running distance along it.
    ///
    /// Parts are deliberately disjoint strokes, so a measure never runs across
    /// a junction and a ridden slice can never leak from one railway onto
    /// another.
    struct PartMetric: Sendable {
        let coordinates: [Coordinate]
        let cumulative: [Double]
    }

    struct SourceMetric: Sendable {
        let coordinates: [Coordinate]
        let cumulative: [Double]
        let minLon: Double
        let maxLon: Double
        let minLat: Double
        let maxLat: Double
    }

    static func familyKey(_ line: Line) -> String {
        (line.operator ?? "") + "\0" + (line.compactLine?.nameNorm ?? line.name ?? "")
    }

    /// Where a point lands on a part, and how far along.
    public struct Projection: Sendable {
        /// The point ON the stroke — an interpolation inside one edge, not a
        /// vertex of it.
        let coordinate: Coordinate
        let distance: Double
        /// The edge it landed in, so a slice can be cut at a vertex boundary.
        let index: Int
        let ratio: Double
        let partIndex: Int
        let measure: Double
    }

    // MARK: - the metric

    /// The equirectangular metric of `rail-network.js`, and NOT
    /// ``Geometry/distanceMeters(_:_:)``.
    ///
    /// The two have the same name in the two files they come from and they are
    /// different functions. This one reads about 0.1125% longer everywhere —
    /// 111 320 m per degree against the haversine's implied 111 194.93 — and
    /// every threshold in the original file (the 260 m endpoint snap, the
    /// 1.5 km gate, the 25 m replacement reach) was tuned against these
    /// numbers. Unifying them is a change in behaviour, not a removal of
    /// duplication, and the JavaScript says so at length.
    ///
    /// Nested inside `RouteNetwork` on purpose: several ports need this metric
    /// and each carries its own until somebody promotes one deliberately.
    ///
    /// **Measured, 2026-08-26.** This one and ``Grooming/distanceMeters(_:_:)``
    /// are the same function bit for bit: over 200,060 real coordinate triples
    /// drawn from all five shipped packages, `local` vs `Grooming.localMetric`
    /// differed **0 times**, and `distanceMeters` vs `Grooming.distanceMeters`
    /// differed **0 times** — compared on `Double.bitPattern`, not on an
    /// epsilon. So promoting one of them is now a decision somebody can take
    /// on evidence rather than on reading; it has not been taken here, because
    /// this audit's remit stopped at the string primitives (`JSString.swift`)
    /// and moving a metric is a change to the thing every threshold in two
    /// files was tuned against.
    ///
    /// What that measurement does NOT license is folding in
    /// ``DisplayParts/turnDegrees(_:_:_:)``, which uses V8's `Math.hypot`
    /// where `Grooming` uses Darwin's: 96,040 of the same 200,060 triples
    /// disagree in the last bits. The largest disagreement is 1.7 × 10⁻⁶
    /// degrees — practically nothing, and precisely the point. Each is
    /// verified bit for bit against its own JavaScript counterpart, and a
    /// difference too small to see is still a difference a fixture fails on.
    enum Metric {

        /// Flat local projection at a given latitude. `distanceMeters` must
        /// share it — an angle or a length measured on unprojected degrees is
        /// wrong by the aspect ratio.
        static func local(_ point: Coordinate, latitude: Double) -> (x: Double, y: Double) {
            let radians = (latitude * .pi) / 180
            // Written in the JavaScript's association order. `lon * 111320`
            // first, then × cos: floating-point multiplication is not
            // associative, and this function's output is compared bit for bit.
            return (point.lon * 111_320 * Foundation.cos(radians), point.lat * 111_320)
        }

        static func distanceMeters(_ left: Coordinate, _ right: Coordinate) -> Double {
            let latitude = (left.lat + right.lat) / 2
            let a = local(left, latitude: latitude)
            let b = local(right, latitude: latitude)
            // `hypot`, not `sqrt(x*x + y*y)`: the JavaScript calls `Math.hypot`,
            // which is scaled against intermediate overflow and can differ in
            // the last place from the naive form. Whether Darwin's `hypot` and
            // V8's agree to the last bit is a measurement, and
            // `port-fixtures/route-feature.json` is where it is measured — a
            // vertex is kept or dropped by comparing one of these against a
            // threshold, so a last-ulp disagreement is a different polyline.
            return Foundation.hypot(a.x - b.x, a.y - b.y)
        }

        static func pathLength(_ coordinates: [Coordinate]) -> Double {
            var total = 0.0
            for index in 1..<max(coordinates.count, 1) {
                total += distanceMeters(coordinates[index - 1], coordinates[index])
            }
            return total
        }
    }

    // MARK: - projection

    /// Nearest point on one display part, with its distance along the stroke.
    ///
    /// Two latitudes are in play and they are deliberately different: the local
    /// projection of the segment uses the QUERY POINT's latitude (so both ends
    /// of the segment are measured on one ruler), while the returned distance
    /// goes through `distanceMeters`, which uses the midpoint latitude of the
    /// pair it is given. Making them agree would change every projection in the
    /// app.
    func projectPointToPart(
        lineIndex: Int, partIndex: Int, point: Coordinate, cache: inout RouteProjectionCache
    ) -> Projection? {
        let line = lines[lineIndex]
        let key = "\(line.lineId)#\(partIndex)|\(Self.toFixed7(point.lon)),\(Self.toFixed7(point.lat))"
        if let cached = cache.storage[key] { return cached }
        guard partIndex < metrics[lineIndex].count else { return nil }
        let metric = metrics[lineIndex][partIndex]

        var best: Projection?
        if metric.coordinates.count >= 2 {
            for index in 0..<(metric.coordinates.count - 1) {
                let start = metric.coordinates[index]
                let end = metric.coordinates[index + 1]
                let latitude = point.lat
                let p = Metric.local(point, latitude: latitude)
                let a = Metric.local(start, latitude: latitude)
                let b = Metric.local(end, latitude: latitude)
                let dx = b.x - a.x
                let dy = b.y - a.y
                let lengthSquared = dx * dx + dy * dy
                let ratio =
                    lengthSquared == 0
                    ? 0
                    : Swift.max(
                        0, Swift.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
                // Interpolated in DEGREES, not in the local projection: this
                // coordinate is emitted into the drawn geometry, so it has to
                // land on the same chord the renderer draws.
                let projected = Coordinate(
                    lon: start.lon + (end.lon - start.lon) * ratio,
                    lat: start.lat + (end.lat - start.lat) * ratio
                )
                let distance = Metric.distanceMeters(point, projected)
                if best == nil || distance < best!.distance {
                    let segmentLength = metric.cumulative[index + 1] - metric.cumulative[index]
                    best = Projection(
                        coordinate: projected,
                        distance: distance,
                        index: index,
                        ratio: ratio,
                        partIndex: partIndex,
                        measure: metric.cumulative[index] + segmentLength * ratio
                    )
                }
            }
        }
        if let best { cache.storage[key] = best }
        return best
    }

    /// `Number.prototype.toFixed(7)`, for the cache key alone.
    ///
    /// `%.7f` rounds the exact binary value half-to-even; ECMAScript rounds a
    /// tie to the larger magnitude. A tie needs the value to be an odd multiple
    /// of 1/256, which no surveyed coordinate is, and even then the only
    /// consequence would be a cache miss — the memo is of a pure function.
    /// Negative zero IS handled, because JavaScript prints `(-0).toFixed(7)`
    /// without the sign and C does not.
    static func toFixed7(_ value: Double) -> String {
        if value == 0 { return "0.0000000" }
        return String(format: "%.7f", value)
    }

    // MARK: - slicing

    /// Append unless it repeats the previous vertex.
    ///
    /// `pushCoordinate`. The duplicate it drops is the ordinary case: a slice
    /// that starts exactly on a vertex has that vertex as both the projected
    /// endpoint and the first copied one.
    private static func push(_ coordinates: inout [Coordinate], _ coordinate: Coordinate) {
        if let last = coordinates.last, last.lon == coordinate.lon, last.lat == coordinate.lat {
            return
        }
        coordinates.append(coordinate)
    }

    private static func sliceForward(
        _ metric: PartMetric, _ start: Projection, _ end: Projection, wraps: Bool
    ) -> [Coordinate] {
        var output: [Coordinate] = []
        push(&output, start.coordinate)
        if !wraps {
            var index = start.index + 1
            while index <= end.index {
                push(&output, metric.coordinates[index])
                index += 1
            }
        } else {
            var index = start.index + 1
            while index < metric.coordinates.count {
                push(&output, metric.coordinates[index])
                index += 1
            }
            // A loop's last point repeats its first. Resuming at vertex 1 emits
            // the junction once, so the arc comes out with no seam in it.
            index = 1
            while index <= end.index {
                push(&output, metric.coordinates[index])
                index += 1
            }
        }
        push(&output, end.coordinate)
        return output
    }

    /// The slice, and which way it runs along the stroke.
    ///
    /// A loop only wraps when the whole line is ONE closed part: a split line's
    /// parts are open strokes even if the package marks the line as a loop.
    ///
    /// On a genuine loop both arcs are legal and no geometric test can separate
    /// them — through the seam, the vertex "behind" the start and the vertex
    /// "ahead" of it are the same place — so the two are measured against the
    /// LENGTH of the path the solver actually walked, and the nearer one wins.
    func canonicalLineSlice(
        lineIndex: Int, start: Projection, end: Projection, rawCoordinates: [Coordinate]
    ) -> [Coordinate] {
        let parts = metrics[lineIndex]
        guard start.partIndex < parts.count else { return [] }
        let metric = parts[start.partIndex]

        if !lines[lineIndex].isLoop || parts.count > 1 {
            if start.measure <= end.measure {
                return Self.sliceForward(metric, start, end, wraps: false)
            }
            var backward = Self.sliceForward(metric, end, start, wraps: false)
            backward.reverse()
            return backward
        }

        let forward = Self.sliceForward(metric, start, end, wraps: end.measure < start.measure)
        var backward = Self.sliceForward(metric, end, start, wraps: start.measure < end.measure)
        backward.reverse()
        let rawLength = Metric.pathLength(rawCoordinates)
        return abs(Metric.pathLength(forward) - rawLength)
            <= abs(Metric.pathLength(backward) - rawLength) ? forward : backward
    }

    // MARK: - hints

    /// An insertion-ordered set of strings — `new Set()` with JavaScript's
    /// iteration order, which decides the order candidates are collected in.
    struct HintSet {
        private(set) var order: [String] = []
        private var members: Set<String> = []

        mutating func insert(_ value: String) {
            if members.insert(value).inserted { order.append(value) }
        }
        func contains(_ value: String?) -> Bool {
            guard let value else { return false }  // `Set.has(undefined)` is false
            return members.contains(value)
        }
        var isEmpty: Bool { order.isEmpty }
    }

    /// `routeHintValues`. Array fields first, in order, then object fields —
    /// the sequence is the collection order and therefore a tie-break.
    static func routeHintValues(arrays: [[String?]], objects: [[String]]) -> HintSet {
        var values = HintSet()
        for rows in arrays {
            for value in rows {
                // `value != null && value !== ""`
                guard let value, !value.isEmpty else { continue }
                values.insert(value)
            }
        }
        for keys in objects {
            for key in keys where !key.isEmpty { values.insert(key) }
        }
        return values
    }

    // MARK: - fitting

    /// A line's best offer for one hop: where both ends land, and what it costs.
    struct Fit {
        let lineIndex: Int
        let start: Projection
        let end: Projection
        let score: Double
        /// `max(start.distance, end.distance)` — how far the WORSE end is from
        /// the rail. The gates are all written against this rather than the
        /// sum, because a hop that reaches one platform and misses the other by
        /// 100 m is on the wrong track however good its total looks.
        var reach: Double { Swift.max(start.distance, end.distance) }
    }

    /// Enough to settle a tie between two bores of one railway, far too little
    /// to pull a ride onto an unrelated line: a wrong-line candidate is out by
    /// hundreds of metres and the 1.5 km gate refuses it regardless.
    static let alignmentMatchBonus = 25.0

    private func bestFit(
        over lineIndices: [Int],
        rawStart: Coordinate,
        rawEnd: Coordinate,
        continueFrom: Coordinate?,
        fromStationCode: String? = nil,
        toStationCode: String? = nil,
        cache: inout RouteProjectionCache
    ) -> Fit? {
        var best: Fit?
        for lineIndex in lineIndices {
            // A nearby trunk station does not belong to the branch. A hop
            // spanning package rows has no single-row slice; returning nil
            // lets the caller retain the solver's complete surveyed path.
            let intervals = lines[lineIndex].intervals
            if !intervals.isEmpty {
                let codes = Set(intervals.flatMap { [$0.fromStationCode, $0.toStationCode] })
                if let fromStationCode, knownStationCodes.contains(fromStationCode), !codes.contains(fromStationCode) { continue }
                if let toStationCode, knownStationCodes.contains(toStationCode), !codes.contains(toStationCode) { continue }
            }
            // Both endpoints must land on the SAME part. Parts are separate
            // railways — a trunk and its branch — so allowing one endpoint on
            // each is exactly the "train turns onto the wrong line" bug: the
            // slice would run from a branch, through the junction, onto other
            // track. 豊肥線 across the 立野 switchback is the case that has no
            // answer at all, and returning none is the right one.
            for partIndex in 0..<metrics[lineIndex].count {
                guard
                    let start = projectPointToPart(
                        lineIndex: lineIndex, partIndex: partIndex, point: rawStart, cache: &cache),
                    let end = projectPointToPart(
                        lineIndex: lineIndex, partIndex: partIndex, point: rawEnd, cache: &cache)
                else { continue }

                let fit = start.distance + end.distance
                // The previous hop's drawn endpoint. A junction station sits on
                // two display parts, both a perfect match for a hop that starts
                // there, and proximity alone can hand consecutive hops of one
                // train different parts — the route then visibly breaks at the
                // junction. This breaks the tie in favour of staying on the
                // rail the train is already on.
                let seam = continueFrom.map { Metric.distanceMeters($0, start.coordinate) } ?? 0

                // A paired alignment is the SAME railway's other direction on
                // its own track — 上越線's up line keeps the older 清水
                // tunnel while the down line takes the 新清水 loop, and the two
                // have separate platforms. Both fit a ride between the same two
                // stations, so where the package carries a SOURCED direction
                // for the pair, the ride's own direction of travel decides:
                // forward through the line's station order is 下り, against it
                // 上り. A pair marked "unassigned" gets no nudge and geometry
                // alone decides, which is the honest outcome when nothing
                // states which bore is which.
                var bias = 0.0
                let alignment = lines[lineIndex].alignmentDirection
                if let compact = lines[lineIndex].compactLine, let traversal = compact.permittedTraversal,
                   (traversal == "forward" && start.measure > end.measure)
                    || (traversal == "reverse" && start.measure < end.measure) { continue }
                if alignment == "up" || alignment == "down" {
                    let order = lines[lineIndex].compactLine?.stationOrderDirection ?? "down"
                    let rode = start.measure <= end.measure ? order : (order == "down" ? "up" : "down")
                    if lines[lineIndex].compactLine?.stationOrderDirection != nil, alignment != rode { continue }
                    bias = alignment == rode ? -Self.alignmentMatchBonus : Self.alignmentMatchBonus
                }

                let candidate = Fit(
                    lineIndex: lineIndex, start: start, end: end, score: fit + seam + bias)
                // Strictly less than, so the FIRST line to reach a score keeps
                // it. That is why the index order above is preserved.
                if best == nil || candidate.score < best!.score { best = candidate }
            }
        }
        return best
    }

    /// A verified interval chain chooses the track by identity before any
    /// proximity comparison. Each interval is sliced from the same groomed
    /// display part used by the complete network.
    private func canonicalizeIntervals(
        _ feature: RouteFeature, cache: inout RouteProjectionCache
    ) -> CanonicalRoute? {
        var current = feature.hints.fromStationCode
        var coordinates: [Coordinate] = []
        var parts: [[Coordinate]] = []
        var used: [String] = []
        for code in feature.hints.sectionCodes {
            guard let record = intervalByCode[code] else { return nil }
            let lineIndex = record.lineIndex, interval = record.interval
            if current == nil, let rawStart = feature.geometry?.lines.first?.first {
                current = Geometry.distanceMeters(rawStart, interval.from) <= Geometry.distanceMeters(rawStart, interval.to)
                    ? interval.fromStationCode : interval.toStationCode
            }
            let forward: Bool
            if current == interval.fromStationCode { forward = true }
            else if current == interval.toStationCode { forward = false }
            else { return nil }
            guard allowedDirections(for: code).contains(forward ? 1 : -1) else { return nil }
            if !feature.hints.requiredLineIDs.isEmpty,
               !feature.hints.requiredLineIDs.contains(interval.lineID) { return nil }
            let sourceStart = forward ? interval.from : interval.to
            let sourceEnd = forward ? interval.to : interval.from
            let displayAnchors = lines[lineIndex].compactLine?.displayStationCoordinates ?? [:]
            let startCode = forward ? interval.fromStationCode : interval.toStationCode
            let endCode = forward ? interval.toStationCode : interval.fromStationCode
            let start = displayAnchors[startCode] ?? sourceStart
            let end = displayAnchors[endCode] ?? sourceEnd
            if coordinates.isEmpty, let rawStart = feature.geometry?.lines.first?.first,
               Geometry.distanceMeters(rawStart, sourceStart) > Geometry.distanceMeters(rawStart, sourceEnd) + 50 { return nil }
            guard let best = bestFit(over: [lineIndex], rawStart: start, rawEnd: end,
                                     continueFrom: coordinates.last, cache: &cache),
                  best.reach <= Self.endpointSnapMeters else { return nil }
            var slice = canonicalLineSlice(lineIndex: lineIndex, start: best.start,
                                           end: best.end, rawCoordinates: [start, end])
            guard slice.count >= 2 else { return nil }
            Self.snapEndpoint(&slice, 0, start, best.start.distance)
            Self.snapEndpoint(&slice, slice.count - 1, end, best.end.distance)
            if let last = coordinates.last, last == slice[0] {
                coordinates += slice.dropFirst()
            } else if coordinates.isEmpty { coordinates = slice }
            else {
                parts.append(coordinates)
                coordinates = slice
            }
            current = forward ? interval.toStationCode : interval.fromStationCode
            if !used.contains(interval.lineID) { used.append(interval.lineID) }
        }
        guard coordinates.count >= 2 else { return nil }
        if let toCode = feature.hints.toStationCode, current != toCode { return nil }
        parts.append(coordinates)
        let geometry: RouteGeometry = parts.count == 1 ? .lineString(parts[0]) : .multiLineString(parts)
        return CanonicalRoute(geometry: geometry, displayLineIds: used)
    }

    /// Source geometry plus the station-table vertices `decodeIntervals`
    /// writes over each interval end. Concatenating intervals leaves those
    /// ends as interior joins. `rowNames` are package `line.name` values in
    /// first-seen order, before graph-line normalization.
    public struct SourceGeometryCertification: Sendable {
        public var geometry: RouteGeometry
        public var anchorIndices: [Set<Int>]
        public var rowNames: [String]

        public init(geometry: RouteGeometry, anchorIndices: [Set<Int>], rowNames: [String]) {
            self.geometry = geometry
            self.anchorIndices = anchorIndices
            self.rowNames = rowNames
        }
    }

    /// The selected physical intervals' source path, kept separate from the
    /// groomed display path for mileage and exports. Platform gaps stay as
    /// separate parts; no unsurveyed connector is added between them.
    public func sourceGeometry(for hints: RouteHints) -> RouteGeometry? {
        sourceCertification(for: hints)?.geometry
    }

    public func sourceCertification(for hints: RouteHints) -> SourceGeometryCertification? {
        var current = hints.fromStationCode
        var parts: [[Coordinate]] = []
        var anchors: [Set<Int>] = []
        var rowNames: [String] = []
        var seenRows = Set<String>()
        for code in hints.sectionCodes {
            guard let record = intervalByCode[code] else { return nil }
            let interval = record.interval
            if !hints.requiredLineIDs.isEmpty && !hints.requiredLineIDs.contains(interval.lineID) { return nil }
            let forward: Bool
            if current == interval.fromStationCode { forward = true }
            else if current == interval.toStationCode { forward = false }
            else { return nil }
            guard allowedDirections(for: code).contains(forward ? 1 : -1) else { return nil }
            let path = forward ? interval.coordinates : Array(interval.coordinates.reversed())
            guard path.count >= 2 else { return nil }
            if let name = lines[record.lineIndex].name, !name.isEmpty, seenRows.insert(name).inserted {
                rowNames.append(name)
            }
            if let last = parts.last?.last, last == path.first {
                let join = parts[parts.count - 1].count - 1
                anchors[anchors.count - 1].insert(join)
                parts[parts.count - 1] += path.dropFirst()
            } else {
                parts.append(path)
                anchors.append([])
            }
            current = forward ? interval.toStationCode : interval.fromStationCode
        }
        guard !parts.isEmpty, hints.toStationCode == nil || current == hints.toStationCode else { return nil }
        let geometry: RouteGeometry = parts.count == 1 ? .lineString(parts[0]) : .multiLineString(parts)
        return SourceGeometryCertification(geometry: geometry, anchorIndices: anchors, rowNames: rowNames)
    }

    // MARK: - the function

    /// Distance from a platform anchor to its track that is still just the
    /// station's own approach; beyond it, the projection is telling us
    /// something is wrong with the data and it should not be hidden.
    public static let endpointSnapMeters = 260.0

    /// A hinted line this far from one of the hop's platforms is not the track
    /// the train stood on — no station in these packages puts its own line more
    /// than a platform's width away, and the anchoring audit holds every one of
    /// them at zero. Above it, look wider; below it, the hint wins.
    static let hintedLineMaxReachMeters = 60.0

    /// And only take the wider answer if it actually arrives, rather than
    /// trading one wrong railway for a nearer wrong railway.
    static let replacementMaxReachMeters = 25.0

    /// Endpoint display coordinates may deliberately bridge a station marker to
    /// its surveyed track. The characterized packages stay below 500 m; 1.5 km
    /// leaves room for future rural station corrections while still refusing an
    /// unrelated same-named railway elsewhere in the country.
    static let endpointGateMeters = 1500.0

    /// Convenience for a caller with no cache of its own to keep.
    public func canonicalizeRouteFeature(
        _ feature: RouteFeature, continueFrom: Coordinate? = nil
    ) -> CanonicalRoute? {
        var cache = RouteProjectionCache()
        return canonicalizeRouteFeature(feature, continueFrom: continueFrom, cache: &cache)
    }

    /// Re-draw one solved hop as an exact slice of the complete display line.
    ///
    /// Returns `nil` when no single stroke can carry the hop. That is not a
    /// failure to be papered over: the caller keeps the solver's own path
    /// there, and the alternative — a slice that starts on one stroke and
    /// finishes on another — is a train drawn onto track it never touched.
    ///
    /// - Parameter continueFrom: the previous hop's drawn endpoint, when this
    ///   hop is part of a chain.
    public func canonicalizeRouteFeature(
        _ feature: RouteFeature,
        continueFrom: Coordinate?,
        cache: inout RouteProjectionCache
    ) -> CanonicalRoute? {
        if !feature.hints.sectionCodes.isEmpty {
            return canonicalizeIntervals(feature, cache: &cache)
        }
        if let matched = matchRouteAcrossLineRows(feature) ?? directedEndpointIntervals(feature) {
            return canonicalizeMatchedRoute(feature, matched: matched, cache: &cache)
        }
        let rawLines = (feature.geometry?.lines ?? []).filter { $0.count >= 2 }
        guard !rawLines.isEmpty else { return nil }

        let candidates = canonicalRouteCandidates(feature)
        if !feature.hints.requiredLineIDs.isEmpty && candidates.isEmpty { return nil }

        var canonicalLines: [[Coordinate]] = []
        var usedLineIds: [String] = []

        for rawCoordinates in rawLines {
            guard let canonical = canonicalStroke(rawCoordinates, feature: feature,
                                                  candidates: candidates, continueFrom: continueFrom, cache: &cache) else { return nil }
            canonicalLines.append(canonical.coordinates)
            usedLineIds.append(canonical.lineID)
        }

        var seenIds = Set<String>()
        return CanonicalRoute(
            geometry: {
                if case .multiLineString = feature.geometry { return .multiLineString(canonicalLines) }
                return .lineString(canonicalLines[0])
            }(),
            displayLineIds: usedLineIds.filter { seenIds.insert($0).inserted }
        )
    }


    private func canonicalizeMatchedRoute(
        _ feature: RouteFeature, matched: IntervalMatch, cache: inout RouteProjectionCache
    ) -> CanonicalRoute? {
        var hints = feature.hints
        hints.sectionCodes = matched.sectionCodes
        hints.requiredLineIDs = matched.lineIDs
        guard var route = canonicalizeIntervals(RouteFeature(geometry: feature.geometry, hints: hints), cache: &cache) else { return nil }
        route.matchedSectionCodes = matched.sectionCodes
        route.directionCorrected = matched.corrected
        return route
    }

    private func canonicalRouteCandidates(_ feature: RouteFeature) -> [Int] {
        let lineNames = Self.routeHintValues(
            arrays: [feature.hints.requiredLineNames, feature.hints.preferredLineNames],
            objects: [feature.hints.usedLineNames]
        )
        let operatorNames = Self.routeHintValues(
            arrays: [feature.hints.requiredOperatorNames, feature.hints.preferredOperatorNames],
            objects: [feature.hints.usedOperatorNames]
        )

        var candidates: [Int] = []
        for name in lineNames.order { candidates.append(contentsOf: linesByName[name] ?? []) }
        // Only when no NAME resolved: an operator index answers with every
        // railway that company runs, which is a far weaker hint and a far
        // longer list.
        if candidates.isEmpty {
            for name in operatorNames.order {
                candidates.append(contentsOf: linesByOperator[name] ?? [])
            }
        }
        // `[...new Set(candidates)]` — dedupe, first occurrence keeps its place.
        var seen = Set<Int>()
        candidates = candidates.filter { seen.insert($0).inserted }
        if !operatorNames.isEmpty {
            let operatorMatched = candidates.filter { operatorNames.contains(lines[$0].operator) }
            if !operatorMatched.isEmpty { candidates = operatorMatched }
        }
        // Nothing usable was hinted, so every line is a candidate.
        if candidates.isEmpty { candidates = Array(lines.indices) }

        if !feature.hints.requiredLineIDs.isEmpty {
            let required = Set(feature.hints.requiredLineIDs)
            candidates = lines.indices.filter { required.contains(lines[$0].lineId) }

        }

        return candidates
    }

    private func canonicalStroke(
        _ rawCoordinates: [Coordinate], feature: RouteFeature, candidates: [Int],
        continueFrom: Coordinate?, cache: inout RouteProjectionCache
    ) -> (coordinates: [Coordinate], lineID: String)? {
        let rawStart = rawCoordinates[0]
        let rawEnd = rawCoordinates[rawCoordinates.count - 1]
        guard let best = canonicalStrokeFit(rawStart: rawStart, rawEnd: rawEnd, feature: feature,
            candidates: candidates, continueFrom: continueFrom, cache: &cache) else { return nil }
        // Written as the JavaScript writes it — `> gate` rather than
        // `<= gate` — so a NaN would pass here exactly as it does there.
        if best.reach > Self.endpointGateMeters { return nil }

        var canonical = canonicalLineSlice(
            lineIndex: best.lineIndex, start: best.start, end: best.end,
            rawCoordinates: rawCoordinates)
        // One unusable stroke discards the WHOLE feature, including the
        // strokes already accumulated. Reproduced deliberately: half a
        // MultiLineString drawn on network geometry and half on the
        // solver's own path would be two different claims in one shape.
        if canonical.count < 2 { return nil }

        // Finish ON the platform, not on the projection of it.
        //
        // A junction station belongs to two display parts, and the
        // projection of the same station onto each lands metres apart, so
        // consecutive hops routed over different parts left the drawn route
        // visibly split open at the junction. The solver's own endpoints
        // ARE the station nodes and are shared by both hops, so pinning the
        // slice ends to them closes the seam exactly. Only over the short
        // bridge from platform to track — a distant projection is a data
        // problem and must stay visible, not be papered over with a long
        // straight chord.
        Self.snapEndpoint(&canonical, 0, rawStart, best.start.distance)
        Self.snapEndpoint(&canonical, canonical.count - 1, rawEnd, best.end.distance)

        return (canonical, lines[best.lineIndex].lineId)
    }

    private func canonicalStrokeFit(
        rawStart: Coordinate, rawEnd: Coordinate, feature: RouteFeature, candidates: [Int],
        continueFrom: Coordinate?, cache: inout RouteProjectionCache
    ) -> Fit? {
        var best = bestFit(
            over: candidates, rawStart: rawStart, rawEnd: rawEnd,
            continueFrom: continueFrom,
            fromStationCode: feature.hints.fromStationCode,
            toStationCode: feature.hints.toStationCode, cache: &cache)

        // The hint names the RAILWAY the solver rode; it cannot make a line
        // reach a platform it does not serve. Where the package draws that
        // railway under another line's name — the 品鶴線 is 総武線-3 since
        // the 東京 rebuild, so a 湘南新宿ライン hop hinted 東海道線 landed
        // on the 相鉄直通線 106 m away — the drawn ride has to follow the
        // rail rather than the name, or the snap below turns the difference
        // into a right-angle chord into the station.
        //
        // Only when the hinted stroke is not at the platform AT ALL, and
        // only for a replacement that genuinely reaches both stops.
        // Anything in between is a disagreement about WHICH platform, which
        // the hint is still the better judge of, and which the
        // route-approach audit reports rather than papers over.
        if feature.hints.requiredLineIDs.isEmpty
            && (best?.reach ?? .infinity) > Self.hintedLineMaxReachMeters {
            let anywhere = bestFit(
                over: Array(lines.indices), rawStart: rawStart, rawEnd: rawEnd,
                continueFrom: continueFrom,
                fromStationCode: feature.hints.fromStationCode,
                toStationCode: feature.hints.toStationCode, cache: &cache)
            if (anywhere?.reach ?? .infinity) <= Self.replacementMaxReachMeters {
                best = anywhere
            }
        }

        return best
    }

    private static func snapEndpoint(
        _ coordinates: inout [Coordinate], _ index: Int, _ rawPoint: Coordinate,
        _ projectedDistance: Double
    ) {
        if projectedDistance > endpointSnapMeters { return }
        coordinates[index] = rawPoint
    }
}
