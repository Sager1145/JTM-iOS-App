import Foundation
import os

/// The map's stroke engine around `ContinuousStroke`: the join of each chain's intervals,
/// projection to screen points, junction tangents, lane offsets, corner rounding, withheld and
/// family runs, simplification and the per-line preparation pass.
///
/// This is the code that used to be `MapLineGeometry.swift` in the app target, moved here so the
/// host-side bake runs the very same functions (behaviour-preserving: `StrokeBakeEqualityTests`
/// compares it with goldens captured from the unmoved code). Nothing here knows MapKit; the app
/// keeps thin adapters that turn the plain results into `MKPolyline`s.
public enum StrokeBake {

    /// One geometry frame: the scale a level is drawn at.
    public struct Frame: Sendable, Equatable {
        /// Map points per screen point at this frame.
        public var mapPointsPerPoint: Double
        /// The shared weight factor (`RailStrokeTokens.scale(atZoom:)`, possibly quantised).
        public var scale: Double
        /// Lane-gap multiplier from the lane LOD bucket.
        public var laneScale: Double
        /// Identity of the frame for the pixel cache.
        public var key: String
        /// Identity of the datum the coordinates were shifted to.
        public var datumToken: String

        public init(
            mapPointsPerPoint: Double, scale: Double, laneScale: Double,
            key: String = "", datumToken: String = ""
        ) {
            self.mapPointsPerPoint = mapPointsPerPoint
            self.scale = scale
            self.laneScale = laneScale
            self.key = key
            self.datumToken = datumToken
        }

        /// The frame the app draws at app zoom `zoom` (the 256-point convention of
        /// `MapProjection.zoomLevel`), unquantised, with the lane bucket resolved without history.
        public init(appZoom zoom: Double, datumToken: String = "") {
            let lane = LaneLOD.resolve(zoom: zoom, previousBucket: nil)
            self.init(
                mapPointsPerPoint: StrokeProjection.worldSize / (256 * exp2(zoom)),
                scale: RailStrokeTokens.scale(atZoom: zoom), laneScale: lane.scale,
                key: "z\(zoom)|\(lane.bucket)", datumToken: datumToken)
        }
    }

    /// What one continuous chain is drawn as, before MapKit.
    public struct Build: Sendable {
        /// Solid runs: the complement of the family windows, as unprojected coordinates.
        public let runs: [[Coordinate]]
        /// The metre range on the chain's stroke ruler each of `runs` was cut from (clamped to the
        /// stroke), one per run.
        public let runRanges: [(from: Double, to: Double)]
        /// Station anchors: the chain vertex index each anchor was requested at, to where the
        /// stroke put it.
        public let anchors: [Int: Coordinate]
        /// The complete stroke in screen points, from which rides are sliced.
        public let stroke: ContinuousStroke.Stroke
        public let sourceMeasures: [Double]
        /// Withheld spans cut out of `stroke`, each with the colour it draws under.
        public let withheldRuns: [(colorHex: String, colorDarkHex: String, from: Double, to: Double, coordinates: [Coordinate])]
        /// Landlord family windows cut out of `stroke` by metre measure.
        public let emittedFamilyWindows: [ContinuousStroke.WindowSpan]

        public init(
            runs: [[Coordinate]], runRanges: [(from: Double, to: Double)], anchors: [Int: Coordinate], stroke: ContinuousStroke.Stroke,
            sourceMeasures: [Double],
            withheldRuns: [(colorHex: String, colorDarkHex: String, from: Double, to: Double, coordinates: [Coordinate])],
            emittedFamilyWindows: [ContinuousStroke.WindowSpan]
        ) {
            self.runs = runs
            self.runRanges = runRanges
            self.anchors = anchors
            self.stroke = stroke
            self.sourceMeasures = sourceMeasures
            self.withheldRuns = withheldRuns
            self.emittedFamilyWindows = emittedFamilyWindows
        }
    }

    /// How a part of a line is to be drawn at the moment of preparation. The app derives it
    /// from the display era and the part's history stamp; the bake draws everything solid and
    /// leaves attribute assignment to the piece cutter.
    public enum PartStyle: Sendable {
        case hidden
        case solid
        case historical
    }

    /// One family's simplified runs for one line, and the colour pair to draw them under.
    public struct FamilyRun: Sendable {
        public let colorHex: String
        public let colorDarkHex: String
        public var coordinateChunks: [[Coordinate]]
        public var chunkWindows: [ContinuousStroke.WindowSpan]

        public init(
            colorHex: String, colorDarkHex: String, coordinateChunks: [[Coordinate]],
            chunkWindows: [ContinuousStroke.WindowSpan]
        ) {
            self.colorHex = colorHex
            self.colorDarkHex = colorDarkHex
            self.coordinateChunks = coordinateChunks
            self.chunkWindows = chunkWindows
        }
    }

    public struct FamilyFallbackRun: Sendable {
        public let window: ContinuousStroke.WindowSpan
        public let family: FamilyRun
    }

    /// One prepared line's value geometry.
    public struct LineGeometry: Sendable {
        public let coordinateChunks: [[Coordinate]]
        public let historicalCoordinateChunks: [[Coordinate]]
        public let familyCoordinateChunks: [String: FamilyRun]
        public let familyFallbacks: [FamilyFallbackRun]
        public let fallbackSplitReserve: Int
    }

    public struct Prepared: Sendable {
        public var strokes: [String: Build] = [:]
        public var lines: [String: LineGeometry] = [:]
    }
}

// MARK: - the join of a chain

extension StrokeBake {
    /// The joined chain of a continuous line's own intervals, stitched at shared station
    /// anchors, with the cumulative metres along it on the ruler the lane rows were measured
    /// with (`rail-network.js` `distanceMeters`: 111320 m per degree on both axes, longitude
    /// scaled by the cosine of the mean latitude).
    ///
    /// Coordinates are already in the display datum; callers project this chain or hand it to
    /// `StrokeRide`; they must not shift it again.
    public static func joinedChainCoordinates(
        of line: StrokeLineInput
    ) -> (points: [Coordinate], measures: [Double]) {
        var chain: [Coordinate] = []
        for (index, interval) in line.intervals.enumerated() {
            chain.append(contentsOf: index == 0 ? interval[...] : interval.dropFirst())
        }
        var measures = [Double](repeating: 0, count: chain.count)
        if chain.count > 1 {
            for index in 1..<chain.count {
                let a = chain[index - 1]
                let b = chain[index]
                let lat = ((a.lat + b.lat) / 2) * Double.pi / 180
                measures[index] = measures[index - 1]
                    + hypot((b.lon - a.lon) * 111_320 * cos(lat), (b.lat - a.lat) * 111_320)
            }
        }
        return (chain, measures)
    }

    /// Stable coordinate chunks share their terminal vertex, preserving every segment. A
    /// patterned (dashed) run stays whole, because MapKit restarts a dash pattern at the start
    /// of each polyline.
    public static func chunks<Element>(
        _ points: [Element], preservingPattern: Bool = false
    ) -> [[Element]] {
        guard points.count >= 2 else { return [] }
        if preservingPattern { return [points] }
        return stride(from: 0, to: points.count - 1, by: 128).map { start in
            Array(points[start..<min(start + 129, points.count)])
        }
    }

    static func pixel(_ coordinate: Coordinate, mapPointsPerPoint: Double) -> ContinuousStroke.Point {
        let point = StrokeProjection.point(coordinate)
        return ContinuousStroke.Point(x: point.x / mapPointsPerPoint, y: point.y / mapPointsPerPoint)
    }

    static func coordinate(
        of point: ContinuousStroke.Point, mapPointsPerPoint: Double
    ) -> Coordinate {
        StrokeProjection.coordinate(
            StrokePoint(x: point.x * mapPointsPerPoint, y: point.y * mapPointsPerPoint))
    }
}

/// One joined display chain. `points` and `measures` stay in the display datum; screen pixels
/// are a separate cache.
public struct JoinedChain: Sendable {
    public var points: [Coordinate]
    public var measures: [Double]

    public init(points: [Coordinate], measures: [Double]) {
        self.points = points
        self.measures = measures
    }
}

/// `StrokeLineInput.contentID` plus that line's chain identity (`StrokeLineInput.id`). A
/// replacement overview or full document with the same public id gets a new `contentID` and
/// does not reuse the old chain.
public struct JoinedChainKey: Hashable, Sendable {
    public var contentID: UUID
    public var chainID: String

    public init(_ line: StrokeLineInput) {
        contentID = line.contentID
        chainID = line.id
    }
}

/// The one join of each resident display chain. Junction indexing, stroke matching and pixel
/// projection all read ``chain(of:)``. The join runs only on a miss, and only while this lock
/// is held, so concurrent readers share that result. A chain left out of ``retain(_:)`` is not
/// stored again.
public final class JoinedChainCache: Sendable {
    private struct Storage {
        var constrained = false
        var resident: Set<JoinedChainKey> = []
        var chains: [JoinedChainKey: JoinedChain] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: Storage())

    public init() {}

    public func chain(of line: StrokeLineInput) -> JoinedChain {
        let key = JoinedChainKey(line)
        return state.withLock { storage in
            if let hit = storage.chains[key] { return hit }
            let built = StrokeBake.joinedChainCoordinates(of: line)
            let value = JoinedChain(points: built.points, measures: built.measures)
            if !storage.constrained || storage.resident.contains(key) {
                storage.chains[key] = value
            }
            return value
        }
    }

    public func retain(_ keys: Set<JoinedChainKey>) {
        state.withLock { storage in
            storage.constrained = true
            storage.resident = keys
            storage.chains = storage.chains.filter { keys.contains($0.key) }
        }
    }

    public func admits(_ key: JoinedChainKey) -> Bool {
        state.withLock { !$0.constrained || $0.resident.contains(key) }
    }
}

/// Screen projection of joined chains. Identity is the geometry frame (zoom bucket, display
/// scale, lane LOD) plus the datum token of the coordinates already stored on the chain. A
/// different identity drops the pixels; it does not join again and does not shift the datum.
public final class ChainPixelCache: Sendable {
    public struct Projection: Equatable, Sendable {
        public var frameKey: String
        public var datumToken: String
        public var mapPointsPerScreenPoint: Double
        public var lodScale: Double

        public init(
            frameKey: String, datumToken: String, mapPointsPerScreenPoint: Double, lodScale: Double
        ) {
            self.frameKey = frameKey
            self.datumToken = datumToken
            self.mapPointsPerScreenPoint = mapPointsPerScreenPoint
            self.lodScale = lodScale
        }
    }

    private struct Storage {
        var projection: Projection?
        var held: [JoinedChainKey: (points: [ContinuousStroke.Point], measures: [Double])] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: Storage())
    public let joinedChains: JoinedChainCache

    public init(joinedChains: JoinedChainCache) {
        self.joinedChains = joinedChains
    }

    public func begin(_ projection: Projection) {
        state.withLock { storage in
            guard storage.projection != projection else { return }
            storage.held.removeAll(keepingCapacity: true)
            storage.projection = projection
        }
    }

    public func projectedChain(
        of line: StrokeLineInput, projection: Projection
    ) -> (points: [ContinuousStroke.Point], measures: [Double]) {
        let key = JoinedChainKey(line)
        if let hit = state.withLock({ storage -> (points: [ContinuousStroke.Point], measures: [Double])? in
            guard storage.projection == projection else { return nil }
            return storage.held[key]
        }) { return hit }
        let joined = joinedChains.chain(of: line)
        let projected = (
            points: joined.points.map {
                StrokeBake.pixel($0, mapPointsPerPoint: projection.mapPointsPerScreenPoint)
            }, measures: joined.measures)
        let admit = joinedChains.admits(key)
        return state.withLock { storage in
            guard storage.projection == projection else { return projected }
            if let hit = storage.held[key] { return hit }
            if admit { storage.held[key] = projected }
            return projected
        }
    }

    public func displayChain(of line: StrokeLineInput) -> JoinedChain {
        joinedChains.chain(of: line)
    }

    public func retain(_ keys: Set<JoinedChainKey>) {
        state.withLock { storage in
            storage.held = storage.held.filter { keys.contains($0.key) }
        }
    }
}

/// One prepare pass's view of ``ChainPixelCache``: the frame, LOD and datum it may reuse, and
/// the map-point scale those pixels were divided by.
public struct ChainPixelReader: Sendable {
    public let cache: ChainPixelCache
    public let projection: ChainPixelCache.Projection

    public init(cache: ChainPixelCache, projection: ChainPixelCache.Projection) {
        self.cache = cache
        self.projection = projection
    }

    public func chain(of line: StrokeLineInput) -> (points: [ContinuousStroke.Point], measures: [Double]) {
        cache.projectedChain(of: line, projection: projection)
    }

    public func displayChain(of line: StrokeLineInput) -> JoinedChain {
        cache.displayChain(of: line)
    }
}

/// Lines that could carry a tangent junction, keyed by the surveyed vertex they pass through
/// (plus region and operator). Built once per prepare pass in id order, so ``StrokeBake/continuousJoin``
/// examines only lines that actually touch the endpoint instead of every line in the network.
public struct JunctionCandidateIndex: Sendable {
    private let index: StrokeJunctionIndex
    private let byID: [String: StrokeLineInput]

    public init() {
        index = StrokeJunctionIndex([])
        byID = [:]
    }

    public init(_ lines: [String: StrokeLineInput], chains: JoinedChainCache) {
        byID = lines
        index = StrokeJunctionIndex(lines.values.map { line in
            .init(id: line.id, region: line.region, operatorName: line.operatorName,
                  coordinates: chains.chain(of: line).points, continuous: line.continuous,
                  follows: line.follows.map(\.canonicalID))
        })
    }

    public func lines(
        sharing coordinate: Coordinate, region: String, operatorName: String?
    ) -> [StrokeLineInput] {
        index.candidateIDs(sharing: coordinate, region: region, operatorName: operatorName)
            .compactMap { byID[$0] }
    }

    public func dependencyIDs(of id: String) -> Set<String> {
        index.dependencyIDs(of: id)
    }
}

// MARK: - joints

extension StrokeBake {
    /// The joint one chain of a continuous line shares with the chain before or after it, when
    /// the two meet at the same surveyed vertex.
    ///
    /// A line the display pass cut into chains is still ONE railway. Each chain is offset by its
    /// own lane rows and approaches the shared vertex from its own direction, so without this the
    /// two strokes step apart there — measured on the shipped US package at 18.9 px. Handing both
    /// chains the neighbour's terminal lane and the same pair of tangents at the joint makes them
    /// land on the same point; see `ContinuousStroke.Join`.
    public static func continuousJoin(
        of line: StrokeLineInput, at end: Bool,
        neighbour: (String) -> StrokeLineInput?, chains: ChainPixelReader,
        junctionCandidates: JunctionCandidateIndex = JunctionCandidateIndex()
    ) -> ContinuousStroke.Join? {
        let branch = chains.chain(of: line)
        let terminal = ContinuousStroke.terminalLanes(rows: line.laneRows, total: line.totalMetres)
        let endpointCoordinate = chains.displayChain(of: line).points
        let probe = end ? endpointCoordinate.last : endpointCoordinate.first
        let candidates = probe.map {
            junctionCandidates.lines(sharing: $0, region: line.region, operatorName: line.operatorName)
        } ?? []
        // A physical Y split owns one surveyed junction. Its three endpoint parts meet at the
        // survey centre, without a sharp adjacent-part mitre.
        func baseID(_ id: String) -> String {
            guard let hash = id.lastIndex(of: "#") else { return id }
            return String(id[..<hash])
        }
        let ownBase = baseID(line.id)
        let endpointParts = candidates.filter { candidate in
            guard baseID(candidate.id) == ownBase, let probe else { return false }
            let points = chains.displayChain(of: candidate).points
            return points.first == probe || points.last == probe
        }
        if endpointParts.count >= 3 {
            for main in endpointParts where main.id != line.id {
                if let join = ContinuousStroke.tangentJoin(
                    branch.points, mainChain: chains.chain(of: main).points, atEnd: end,
                    lane: end ? terminal.end : terminal.start, mainLane: 0, allowMainEndpoint: true) {
                    return join
                }
            }
            // A steep real fork still meets at the same point; retain its own edge direction
            // rather than borrowing an unrelated sharp tangent.
            guard branch.points.count >= 2 else { return nil }
            let a = end ? branch.points[branch.points.count - 2] : branch.points[0]
            let b = end ? branch.points.last! : branch.points[1]
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return nil }
            let tangent = ContinuousStroke.Point(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
            return ContinuousStroke.Join(lane: end ? terminal.end : terminal.start,
                                         incoming: tangent, outgoing: tangent, targetLane: 0)
        }
        // Other reviewed adjacent boundaries keep their established ownership.
        if let adjacent = continuousPartJoin(of: line, at: end, neighbour: neighbour, chains: chains) {
            return adjacent
        }
        for main in candidates where main.id != line.id {
            guard main.bounds.intersects(line.bounds) else { continue }
            let through = chains.chain(of: main)
            let endpoint = end ? branch.points.last : branch.points.first
            guard let endpoint, let vertex = through.points.firstIndex(of: endpoint),
                  vertex > 0, vertex + 1 < through.points.count else { continue }
            let pixelLength = zip(through.points, through.points.dropFirst()).reduce(0.0) {
                $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
            }
            let metresPerPixel = pixelLength > 0 ? main.totalMetres / pixelLength : 0
            let width = max(
                ContinuousStroke.laneRampHalfWidthMetres, RailStrokeTokens.strokeMinRamp * metresPerPixel)
            let mainLane = ContinuousStroke.laneAt(
                profile: ContinuousStroke.laneProfile(
                    rows: main.laneRows, total: main.totalMetres,
                    joinStart: continuousPartJoin(of: main, at: false, neighbour: neighbour, chains: chains)?.lane,
                    joinEnd: continuousPartJoin(of: main, at: true, neighbour: neighbour, chains: chains)?.lane),
                measure: through.measures[vertex], width: width)
            if let join = ContinuousStroke.tangentJoin(branch.points, mainChain: through.points,
                                                      atEnd: end, lane: end ? terminal.end : terminal.start,
                                                      mainLane: mainLane) {
                return join
            }
        }
        return nil
    }

    private static func continuousPartJoin(
        of line: StrokeLineInput, at end: Bool,
        neighbour: (String) -> StrokeLineInput?, chains: ChainPixelReader
    ) -> ContinuousStroke.Join? {
        // The chain index is the tail of a continuous stroke's id, `lineKey#n`.
        guard line.continuous, let hash = line.id.lastIndex(of: "#"),
              let index = Int(line.id[line.id.index(after: hash)...])
        else { return nil }
        let wanted = index + (end ? 1 : -1)
        guard wanted >= 0,
              let other = neighbour("\(line.id[line.id.startIndex..<hash])#\(wanted)"),
              other.continuous
        else { return nil }
        // The chain after a boundary owns the reviewed decision for both sides. A coincident
        // station anchor is not enough evidence that two branches share one tangent continuation.
        if end ? !other.joinPrevious : !line.joinPrevious { return nil }
        let own = chains.chain(of: line)
        let theirs = chains.chain(of: other)
        guard own.points.count >= 2, theirs.points.count >= 2 else { return nil }
        // The pair of raw edges at the joint, in the digitised order: the chain that arrives,
        // then the chain that leaves. Both chains derive it from these same two edges, so both
        // mitre the shared vertex identically.
        let arriving = end ? own : theirs
        let leaving = end ? theirs : own
        guard arriving.points[arriving.points.count - 1] == leaving.points[0] else { return nil }
        func unit(_ from: ContinuousStroke.Point, _ to: ContinuousStroke.Point)
            -> ContinuousStroke.Point?
        {
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = hypot(dx, dy)
            return length > 0 ? ContinuousStroke.Point(x: dx / length, y: dy / length) : nil
        }
        guard let incoming = unit(
                arriving.points[arriving.points.count - 2],
                arriving.points[arriving.points.count - 1]),
              let outgoing = unit(leaving.points[0], leaving.points[1])
        else { return nil }
        let span = (theirs.measures.last ?? 0) - (theirs.measures.first ?? 0)
        let lanes = ContinuousStroke.terminalLanes(rows: other.laneRows, total: span)
        return ContinuousStroke.Join(
            lane: end ? lanes.start : lanes.end, incoming: incoming, outgoing: outgoing)
    }
}

// MARK: - one chain's stroke

extension StrokeBake {
    /// Draw a reviewed continuous-stroke line as ONE stroke: the chain of intervals is joined at
    /// its shared station anchors, projected to the pixel space this frame is drawn in, handed to
    /// `ContinuousStroke` (the port of rail-stroke.js) which bakes the screen-space lane offset in
    /// through its smoothed lane profile and rounds the corners.
    public static func strokeBuild(
        for line: StrokeLineInput, anchors: [Int],
        canonical: (String) -> StrokeLineInput?,
        chains: ChainPixelReader,
        mapPointsPerPoint: Double, scale: Double,
        laneScale: Double = 1, junctionCandidates: JunctionCandidateIndex = JunctionCandidateIndex()
    ) throws -> Build {
        // Cooperative cancellation between the build's expensive steps, so a stale frame
        // releases the geometry permit without finishing the line. `Stroke` has no public
        // initializer of its own, so an empty one is built the way `buildStroke` builds one for
        // fewer than two points itself.
        let emptyStroke = ContinuousStroke.buildStroke(
            [], options: .init(rows: [], totalMetres: 0, laneGapPx: 0, minRampPx: 0, cornerRadiusPx: 0, anchors: []))
        guard mapPointsPerPoint > 0 else {
            return Build(
                runs: [], runRanges: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [],
                emittedFamilyWindows: [])
        }
        try Task.checkCancellation()
        let chain = chains.chain(of: line)
        let pixels = chain.points
        guard pixels.count >= 2 else {
            return Build(
                runs: [], runRanges: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [],
                emittedFamilyWindows: [])
        }
        // The canonical alignments this chain is drawn from, projected into the same pixel
        // space; a follow whose canonical chain is not loaded is simply not applied.
        let follows = line.follows.compactMap { follow -> ContinuousStroke.Follow? in
            guard let canon = canonical(follow.canonicalID) else { return nil }
            let canonChain = chains.chain(of: canon)
            guard canonChain.points.count >= 2 else { return nil }
            return ContinuousStroke.Follow(
                from: follow.from, to: follow.to,
                canonFrom: follow.canonicalFrom, canonTo: follow.canonicalTo,
                points: canonChain.points, measures: canonChain.measures,
                shapeBoundaryMeasures: canon.familyWindows.flatMap { [$0.from, $0.to] })
        }
        try Task.checkCancellation()
        var literalSpans: [ContinuousStroke.LiteralSpan] = []
        if !line.literalDisplaySpansV1.isEmpty, line.region == "jp", line.continuous,
           line.lane == 0, line.laneRows.allSatisfy({ $0.lane == 0 }),
           line.follows.isEmpty, line.familyWindows.isEmpty, line.withheld.isEmpty,
           chains.projection.mapPointsPerScreenPoint == mapPointsPerPoint {
            let display = chains.displayChain(of: line)
            if display.points.count == pixels.count {
                // Bind against the very same joined coordinates and cached pixel array used
                // below. No new ruler, rounded key or index remapping.
                var projected: [Coordinate: ContinuousStroke.Point] = [:]
                for (coordinate, pixel) in zip(display.points, pixels) {
                    projected[coordinate] = pixel
                }
                literalSpans = DisplayLiteralSpans.projected(
                    line.literalDisplaySpansV1, coordinates: display.points,
                    // The resolver projects only exact current-chain coordinates; every such
                    // coordinate was inserted above from this pixel array.
                    project: { projected[$0]! })
            }
        }
        try Task.checkCancellation()
        let stroke = ContinuousStroke.buildStroke(
            pixels,
            options: .init(
                measures: chain.measures,
                rows: line.laneRows, totalMetres: line.totalMetres,
                laneGapPx: RailStrokeTokens.parallelLaneCentreDistance * scale * laneScale,
                minRampPx: RailStrokeTokens.strokeMinRamp,
                cornerRadiusPx: RailStrokeTokens.strokeCornerRadius * scale,
                // The radius the map PROMISES to present. Passing it is what turns that promise
                // into an operation: where a corner's own edges are too short to carry it, the
                // run of vertices is rounded as one corner rather than leaving a kink at each.
                minCornerRadiusPx: RailStrokeTokens.minimumCornerRadius(atScale: scale),
                anchors: anchors, follows: follows,
                shapeBoundaryMeasures: line.familyWindows.flatMap { [$0.from, $0.to] },
                joinStart: continuousJoin(
                    of: line, at: false, neighbour: canonical, chains: chains, junctionCandidates: junctionCandidates),
                joinEnd: continuousJoin(
                    of: line, at: true, neighbour: canonical, chains: chains, junctionCandidates: junctionCandidates),
                enforceMinimumCornerRadius: true,
                literalSpans: literalSpans,
                hardCornerMaxDeviationPx: RailStrokeTokens.hardCornerMaxDeviation(atScale: scale),
                railWidthPx: RailStrokeTokens.railWidth * scale))
        try Task.checkCancellation()
        var anchorPoints: [Int: Coordinate] = [:]
        for (slot, index) in anchors.enumerated() where slot < stroke.anchors.count {
            anchorPoints[index] = coordinate(of: stroke.anchors[slot], mapPointsPerPoint: mapPointsPerPoint)
        }
        let points = stroke.points.map { coordinate(of: $0, mapPointsPerPoint: mapPointsPerPoint) }
        // Sliced straight off the just-built stroke by metre measure, exactly the way a ride's
        // own segment is cut — no extra Douglas–Peucker pass here, because this IS the simplified
        // polyline a ride slice already reuses; the lane offset and corner rounding are already
        // baked into `stroke.points`, so unprojecting is the whole job.
        let strokeLow = stroke.measures.first ?? 0
        let strokeHigh = stroke.measures.last ?? 0
        func clamped(_ metres: Double) -> Double { max(strokeLow, min(strokeHigh, metres)) }
        func sliceRun(_ from: Double, _ to: Double) -> [Coordinate]? {
            let sliced = ContinuousStroke.slice(
                points: stroke.points, measures: stroke.measures, from: from, to: to)
            guard sliced.count >= 2 else { return nil }
            return sliced.map { coordinate(of: $0, mapPointsPerPoint: mapPointsPerPoint) }
        }
        // This chain's own family-collapse windows, split by role — reused below by the run
        // partition AND the withheld clip, so a line with no family windows at all runs both
        // through the same code with empty lists.
        let tenantWindows = line.familyWindows.filter { !$0.isLandlord }
        let landlordWindows = line.familyWindows.filter(\.isLandlord)
        let tenantSpans = tenantWindows.map {
            ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupID)
        }
        let landlordSpans = landlordWindows.map {
            ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupID)
        }
        var runs: [[Coordinate]] = []
        var runRanges: [(from: Double, to: Double)] = []
        var emittedFamilyWindows: [ContinuousStroke.WindowSpan] = []
        if line.familyWindows.isEmpty {
            // Cache the complete, zoom-dependent stroke. Viewport selection happens on stable
            // polyline chunks after lane offsets and rounding are finished.
            runs = points.count >= 2 ? [points] : []
            if points.count >= 2 { runRanges = [(strokeLow, strokeHigh)] }
        } else {
            // A family window is a stretch this chain shares with a sibling railway of the same
            // operator collapse — kilometres, not a viewport. So a line with ANY family window
            // is built whole, split by metre measure: `runs` becomes the complement of every
            // window — tenant AND landlord alike withhold this chain's OWN colour there — and
            // each landlord window becomes its own measured entry, in the shared family's colour.
            // Windows are reviewed non-overlapping and sorted. The boundary walk itself is
            // `ContinuousStroke.familyPartition`, which the family-windows port fixture pins.
            let lower = stroke.measures.first ?? 0
            let upper = stroke.measures.last ?? 0
            let partition = ContinuousStroke.familyPartition(
                totalMetres: line.totalMetres, tenantWindows: tenantSpans, landlordWindows: landlordSpans,
                measureStart: lower, measureEnd: upper)
            for piece in partition.base {
                try Task.checkCancellation()
                if let run = sliceRun(piece.from, piece.to) {
                    runs.append(run)
                    runRanges.append((clamped(piece.from), clamped(piece.to)))
                }
            }
            for piece in partition.family {
                try Task.checkCancellation()
                // `familyPartition` returns one piece per surviving landlord window (never merged
                // with a neighbour), so the source window this piece came from is the one of the
                // same group that contains it. Keep only pieces with both a source and real ink;
                // preparation resolves the colour and builds measured chunks.
                guard
                    landlordWindows.contains(where: {
                        $0.groupID == piece.groupID && $0.from <= piece.from && piece.to <= $0.to
                    }),
                    ContinuousStroke.slice(points: stroke.points, measures: stroke.measures,
                                           from: piece.from, to: piece.to).count >= 2
                else { continue }
                emittedFamilyWindows.append(piece)
            }
        }
        // A withheld span is clipped to the complement of this chain's OWN tenant windows first:
        // a span inside a tenant window sits on track this line draws NOWHERE, so dashing it here
        // would dash a field with no solid stroke under it. Each surviving piece is then split
        // again at every landlord-window edge it crosses, so no single drawn dash spans both a
        // landlord stretch and plain track. A piece inside a landlord window is tinted with that
        // family's colour; a piece on plain track keeps this line's own colour.
        var withheldRuns: [(colorHex: String, colorDarkHex: String, from: Double, to: Double, coordinates: [Coordinate])] = []
        for span in line.withheld {
            try Task.checkCancellation()
            let clipped = ContinuousStroke.clipRangesToComplement(
                [ContinuousStroke.Interval(from: span.from, to: span.to)], tenantWindows: tenantSpans)
            for piece in clipped {
                var cuts: Set<Double> = [piece.from, piece.to]
                for window in landlordWindows {
                    if window.from > piece.from, window.from < piece.to { cuts.insert(window.from) }
                    if window.to > piece.from, window.to < piece.to { cuts.insert(window.to) }
                }
                let ordered = cuts.sorted()
                for index in 0..<max(0, ordered.count - 1) {
                    let from = ordered[index]
                    let to = ordered[index + 1]
                    guard to - from > ContinuousStroke.familyPartitionEpsilonMetres,
                        let coordinates = sliceRun(from, to)
                    else { continue }
                    let midpoint = (from + to) / 2
                    let family = landlordWindows.first { $0.from <= midpoint && midpoint <= $0.to }
                    withheldRuns.append((
                        family?.colorHex ?? line.colorHex,
                        family?.colorDarkHex ?? line.colorDarkHex,
                        clamped(from), clamped(to), coordinates))
                }
            }
        }
        return Build(
            runs: runs, runRanges: runRanges, anchors: anchorPoints, stroke: stroke, sourceMeasures: chain.measures,
            withheldRuns: withheldRuns, emittedFamilyWindows: emittedFamilyWindows)
    }

    /// Offset one display fragment in projected map space. The canonical package geometry stays
    /// untouched; only the polyline submitted for this frame is shifted, by the same point token
    /// the Web renderer applies with line-offset.
    public static func parallelLaneCoordinates(
        _ coordinates: [Coordinate], lane: Double,
        mapPointsPerPoint: Double, scale: Double, alreadyCurved: Bool = false
    ) -> [Coordinate] {
        guard coordinates.count >= 2, mapPointsPerPoint > 0, !alreadyCurved || lane != 0 else { return coordinates }
        let pixels = coordinates.map { pixel($0, mapPointsPerPoint: mapPointsPerPoint) }
        var measures = [Double](repeating: 0, count: coordinates.count)
        for index in 1..<coordinates.count {
            measures[index] = measures[index - 1]
                + Geometry.distanceMeters(coordinates[index - 1], coordinates[index])
        }
        let total = measures.last ?? 0
        let stroke = ContinuousStroke.buildStroke(pixels, options: .init(
            measures: measures, rows: [.init(from: 0, to: total, lane: lane)], totalMetres: total,
            laneGapPx: RailStrokeTokens.parallelLaneCentreDistance * scale,
            minRampPx: RailStrokeTokens.strokeMinRamp,
            cornerRadiusPx: RailStrokeTokens.strokeCornerRadius * scale,
            minCornerRadiusPx: RailStrokeTokens.minimumCornerRadius(atScale: scale),
            anchors: [0, pixels.count - 1], enforceMinimumCornerRadius: true, curveCentreline: !alreadyCurved,
            hardCornerMaxDeviationPx: RailStrokeTokens.hardCornerMaxDeviation(atScale: scale),
            railWidthPx: RailStrokeTokens.railWidth * scale))
        return stroke.points.map { coordinate(of: $0, mapPointsPerPoint: mapPointsPerPoint) }
    }

    /// The runs of one line brought to what is drawn: simplified (a non-continuous, unlaned run),
    /// and lane-offset. Continuous geometry already spent its simplification budget before
    /// rounding and is never decimated a second time. Runs under two vertices are dropped.
    public static func finishedRuns(
        _ runs: [[Coordinate]], line: StrokeLineInput, frame: Frame
    ) throws -> [[Coordinate]] {
        let epsilon = StrokeProjection.metresPerMapPoint(
            atLatitude: StrokeProjection.coordinate(
                StrokePoint(x: line.bounds.midX, y: line.bounds.midY)).lat)
            * frame.mapPointsPerPoint * RailStrokeTokens.simplifyTolerance
        var result: [[Coordinate]] = []
        for interval in runs where interval.count >= 2 {
            try Task.checkCancellation()
            let coordinates = try line.continuous || line.lane != 0 ? interval
                : Geometry.cancellableDouglasPeuckerIndices(interval, epsilonMeters: epsilon)
                    .map { interval[$0] }
            result.append(parallelLaneCoordinates(
                coordinates, lane: line.lane, mapPointsPerPoint: frame.mapPointsPerPoint,
                scale: frame.scale, alreadyCurved: line.continuous))
        }
        return result
    }
}

// MARK: - one line's family geometry

extension StrokeBake {
    /// The landlord windows this line draws and the tenant windows it can fall back to, cut out of
    /// its already-built stroke, plus the vertex reserve a later partial landlord selection can
    /// split a tenant window into. A reviewed landlord's own stroke is built (and recorded in
    /// `strokes`) now, so the cached tenant already reserves its cuts.
    static func familyGeometry(
        for line: StrokeLineInput, stroke: Build, strokes: inout [String: Build],
        cachedStrokes: [String: Build], allLines: [String: StrokeLineInput],
        anchors: [String: [Int]], chains: ChainPixelReader, frame: Frame,
        junctionCandidates: JunctionCandidateIndex
    ) throws -> (families: [String: FamilyRun], fallbacks: [FamilyFallbackRun], reserve: Int) {
        let mapScale = frame.mapPointsPerPoint
        func measuredFamily(
            from: Double, to: Double, groupID: String, colorHex: String, colorDarkHex: String
        ) -> FamilyRun {
            let chunks = ContinuousStroke.measuredSliceChunks(
                points: stroke.stroke.points, measures: stroke.stroke.measures, from: from, to: to)
            return FamilyRun(
                colorHex: colorHex, colorDarkHex: colorDarkHex,
                coordinateChunks: chunks.map { chunk in
                    chunk.points.map { coordinate(of: $0, mapPointsPerPoint: mapScale) }
                }, chunkWindows: chunks.map {
                    .init(from: $0.from, to: $0.to, groupID: groupID)
                })
        }
        var families: [String: FamilyRun] = [:]
        var fallbacks: [FamilyFallbackRun] = []
        var fallbackSplitReserve = 0
        for window in stroke.emittedFamilyWindows {
            guard let source = line.familyWindows.first(where: {
                $0.isLandlord && $0.groupID == window.groupID
                    && $0.from <= window.from && window.to <= $0.to
            }) else { continue }
            let prepared = measuredFamily(
                from: window.from, to: window.to, groupID: window.groupID,
                colorHex: source.colorHex, colorDarkHex: source.colorDarkHex)
            if var existing = families[window.groupID] {
                existing.coordinateChunks.append(contentsOf: prepared.coordinateChunks)
                existing.chunkWindows.append(contentsOf: prepared.chunkWindows)
                families[window.groupID] = existing
            } else {
                families[window.groupID] = prepared
            }
        }
        for tenant in line.familyWindows where !tenant.isLandlord {
            let prepared = measuredFamily(
                from: tenant.from, to: tenant.to, groupID: tenant.groupID,
                colorHex: tenant.colorHex, colorDarkHex: tenant.colorDarkHex)
            guard !prepared.coordinateChunks.isEmpty else { continue }
            fallbacks.append(FamilyFallbackRun(
                window: .init(from: tenant.from, to: tenant.to, groupID: tenant.groupID),
                family: prepared))
            // A later pan can select the landlord without changing resident data. Prepare only
            // this reviewed family owner now so the cached tenant already reserves its cuts.
            for follow in line.follows where follow.to > tenant.from && follow.from < tenant.to {
                guard strokes[follow.canonicalID] == nil,
                      cachedStrokes[follow.canonicalID] == nil,
                      let owner = allLines[follow.canonicalID], owner.continuous,
                      owner.familyWindows.contains(where: {
                          $0.isLandlord && $0.groupID == tenant.groupID
                              && $0.to > min(follow.canonicalFrom, follow.canonicalTo)
                              && $0.from < max(follow.canonicalFrom, follow.canonicalTo)
                      }) else { continue }
                try Task.checkCancellation()
                strokes[owner.id] = try strokeBuild(
                    for: owner, anchors: anchors[owner.id] ?? [], canonical: { allLines[$0] },
                    chains: chains, mapPointsPerPoint: mapScale, scale: frame.scale,
                    laneScale: frame.laneScale, junctionCandidates: junctionCandidates)
            }
            // Partial selected coverage can cut a cached window into multiple pieces. Reserve
            // boundary/chunk vertices too.
            let possibleCoverage = line.follows.reduce(0) { count, follow in
                guard follow.to > tenant.from, follow.from < tenant.to,
                      let owner = strokes[follow.canonicalID]
                        ?? cachedStrokes[follow.canonicalID] else { return count }
                return count + owner.emittedFamilyWindows
                    .filter { $0.groupID == tenant.groupID }
                    .reduce(0) { chunks, window in
                        chunks + ContinuousStroke.measuredSliceChunks(
                            points: owner.stroke.points, measures: owner.stroke.measures,
                            from: window.from, to: window.to).count
                    }
            }
            fallbackSplitReserve += 2 + 6 * possibleCoverage
        }
        return (families, fallbacks, fallbackSplitReserve)
    }
}

// MARK: - the preparation pass

extension StrokeBake {
    /// The worker pass: build every requested stroke, then bring every requested line to the
    /// geometry it draws. `partStyle(line, part)` says whether a part is drawn, and how: the app
    /// answers from the display era and the part's history stamp; for a continuous line it is
    /// called once, with part 0, for the whole chain.
    ///
    /// The worker owns projection caches; results contain immutable geometry only.
    public static func prepare(
        lines: [StrokeLineInput], strokes: [StrokeLineInput],
        allLines: [String: StrokeLineInput], anchors: [String: [Int]],
        cachedStrokes: [String: Build],
        joinedChains: JoinedChainCache, chainPixels: ChainPixelCache,
        frame: Frame,
        partStyle: (StrokeLineInput, Int) -> PartStyle
    ) throws -> Prepared {
        let projection = ChainPixelCache.Projection(
            frameKey: frame.key, datumToken: frame.datumToken,
            mapPointsPerScreenPoint: frame.mapPointsPerPoint, lodScale: frame.laneScale)
        chainPixels.begin(projection)
        let chains = ChainPixelReader(cache: chainPixels, projection: projection)
        var result = Prepared()
        let junctionCandidates = JunctionCandidateIndex(allLines, chains: joinedChains)
        for line in strokes {
            try Task.checkCancellation()
            result.strokes[line.id] = try strokeBuild(
                for: line, anchors: anchors[line.id] ?? [], canonical: { allLines[$0] },
                chains: chains, mapPointsPerPoint: frame.mapPointsPerPoint, scale: frame.scale,
                laneScale: frame.laneScale, junctionCandidates: junctionCandidates)
        }
        for line in lines {
            try Task.checkCancellation()
            let stroke = result.strokes[line.id] ?? cachedStrokes[line.id]
            func chunked(_ runs: [[Coordinate]], preservingPattern: Bool = false) throws -> [[Coordinate]] {
                try finishedRuns(runs, line: line, frame: frame).flatMap {
                    chunks($0, preservingPattern: preservingPattern)
                }
            }
            // Draw filter only. `intervals` and `strokeBuild` stay whole — a hidden continuous
            // chain still builds above for rides, and simply contributes no network stroke here.
            let solidRuns: [[Coordinate]]
            let historicalRuns: [[Coordinate]]
            let drawFamilies: Bool
            if line.continuous {
                let style = partStyle(line, 0)
                drawFamilies = style != .hidden
                switch style {
                case .hidden:
                    solidRuns = []
                    historicalRuns = []
                case .historical:
                    solidRuns = []
                    historicalRuns = stroke?.runs ?? line.intervals
                case .solid:
                    solidRuns = stroke?.runs ?? line.intervals
                    historicalRuns = []
                }
            } else {
                drawFamilies = true
                var solid: [[Coordinate]] = []
                var historical: [[Coordinate]] = []
                for (index, interval) in line.intervals.enumerated() {
                    switch partStyle(line, index) {
                    case .hidden: continue
                    case .historical: historical.append(interval)
                    case .solid: solid.append(interval)
                    }
                }
                solidRuns = solid
                historicalRuns = historical
            }
            var families: [String: FamilyRun] = [:]
            var fallbacks: [FamilyFallbackRun] = []
            var fallbackSplitReserve = 0
            if drawFamilies, let stroke {
                let built = try familyGeometry(
                    for: line, stroke: stroke, strokes: &result.strokes,
                    cachedStrokes: cachedStrokes, allLines: allLines, anchors: anchors,
                    chains: chains, frame: frame, junctionCandidates: junctionCandidates)
                families = built.families
                fallbacks = built.fallbacks
                fallbackSplitReserve = built.reserve
            }
            result.lines[line.id] = LineGeometry(
                coordinateChunks: try chunked(solidRuns),
                historicalCoordinateChunks: try chunked(historicalRuns, preservingPattern: true),
                familyCoordinateChunks: families, familyFallbacks: fallbacks,
                fallbackSplitReserve: fallbackSplitReserve)
        }
        try Task.checkCancellation()
        return result
    }
}
