import MapKit
import os
import RailCore
import RailPresentation
import SwiftUI

/// One line's decimated geometry, kept with the line so the vertex budget can
/// shed the least important rather than simply the last built.
struct LineBuild {
    let line: RailNetworkStore.DrawnLine
    let polylines: [MKPolyline]
    /// Historical and relocated-old intervals. Not the cross-day dash.
    let historicalPolylines: [MKPolyline]
    /// Landlord family-window polylines (`ContinuousStrokeBuild.emittedFamilyWindows`,
    /// simplified through the same Douglas–Peucker call `polylines` above
    /// is), keyed by the shared family's group ID. Drawn under
    /// THAT colour in `byColor`, alongside but separate from this line's own
    /// bucket above — the region `polylines` already excludes wherever this
    /// chain is the landlord. Empty for a line with no family windows.
    let familyPolylines: [String: FamilyRunBuild]
    let familyFallbacks: [FamilyFallbackRunBuild]
    let fallbackSplitReserve: Int
    init(
        line: RailNetworkStore.DrawnLine, polylines: [MKPolyline],
        historicalPolylines: [MKPolyline] = [],
        familyPolylines: [String: FamilyRunBuild] = [:],
        familyFallbacks: [FamilyFallbackRunBuild] = [], fallbackSplitReserve: Int = 0
    ) {
        self.line = line
        self.polylines = polylines
        self.historicalPolylines = historicalPolylines
        self.familyPolylines = familyPolylines
        self.familyFallbacks = familyFallbacks
        self.fallbackSplitReserve = fallbackSplitReserve
    }
    func intersecting(_ rect: MKMapRect) -> LineBuild {
        LineBuild(line: line,
            polylines: polylines.filter { $0.boundingMapRect.intersects(rect) },
            historicalPolylines: historicalPolylines.filter { $0.boundingMapRect.intersects(rect) },
            familyPolylines: familyPolylines.compactMapValues { family in
                let kept = family.intersecting(rect)
                return kept.polylines.isEmpty ? nil : kept
            }, familyFallbacks: familyFallbacks.compactMap { fallback in
                let kept = fallback.family.intersecting(rect)
                guard !kept.polylines.isEmpty else { return nil }
                return FamilyFallbackRunBuild(window: fallback.window, family: kept)
            }, fallbackSplitReserve: fallbackSplitReserve)
    }

    var actualVertexCount: Int {
        polylines.reduce(0) { $0 + $1.pointCount }
            + historicalPolylines.reduce(0) { $0 + $1.pointCount }
            + familyPolylines.values.reduce(0) { $0 + $1.polylines.reduce(0) { $0 + $1.pointCount } }
    }
    var drawnVertexCount: Int {
        actualVertexCount + familyFallbacks.reduce(0) {
            $0 + $1.family.polylines.reduce(0) { $0 + $1.pointCount }
        } + (familyFallbacks.isEmpty ? 0 : fallbackSplitReserve)
    }
}

/// Stable coordinate chunks share their terminal vertex, preserving every
/// segment. Split only AFTER simplification and offsets, so chunk boundaries
/// cannot kink lanes. These value-only chunks are safe to prepare off-main.
func mapCoordinateChunks(
    _ points: [CLLocationCoordinate2D], preservingPattern: Bool = false
) -> [[CLLocationCoordinate2D]] {
    guard points.count >= 2 else { return [] }
    // MapKit restarts a dash pattern at the start of each MKPolyline.
    // Keep a patterned run whole so viewport culling never changes its phase.
    if preservingPattern { return [points] }
    return stride(from: 0, to: points.count - 1, by: 128).map { start in
        Array(points[start..<min(start + 129, points.count)])
    }
}

/// Construct MapKit reference objects only on the main actor, immediately
/// before they enter the mounted-geometry cache.
@MainActor
private func mapPolylineChunk(
    _ chunk: [CLLocationCoordinate2D]
) -> MKPolyline {
    MKPolyline(coordinates: chunk, count: chunk.count)
}

@MainActor
func mapPolylineChunks(
    _ chunks: [[CLLocationCoordinate2D]]
) -> [MKPolyline] {
    chunks.map(mapPolylineChunk)
}

/// One family's simplified polylines for one `LineBuild`, and the colour
/// pair to draw them under (see `RailNetworkStore.DrawnLine.FamilyWindow`).
struct FamilyRunBuild {
    let colorHex: String
    let colorDarkHex: String
    var polylines: [MKPolyline]
    let chunkWindows: [ContinuousStroke.WindowSpan]

    func intersecting(_ rect: MKMapRect) -> FamilyRunBuild {
        let indices = polylines.indices.filter { polylines[$0].boundingMapRect.intersects(rect) }
        return FamilyRunBuild(colorHex: colorHex, colorDarkHex: colorDarkHex,
                              polylines: indices.map { polylines[$0] },
                              chunkWindows: indices.map { chunkWindows[$0] })
    }
}

struct FamilyFallbackRunBuild {
    let window: ContinuousStroke.WindowSpan
    let family: FamilyRunBuild
}

/// Value geometry returned by the detached preparation task. Native MapKit
/// overlays are deliberately absent from this type.
struct PreparedFamilyRunBuild: Sendable {
    let colorHex: String
    let colorDarkHex: String
    var coordinateChunks: [[CLLocationCoordinate2D]]
    var chunkWindows: [ContinuousStroke.WindowSpan]
}

struct PreparedFamilyFallbackRunBuild: Sendable {
    let window: ContinuousStroke.WindowSpan
    let family: PreparedFamilyRunBuild
}

/// One prepared line's value geometry. It becomes a ``LineBuild`` on the main
/// actor only after the request-generation guard accepts the worker result.
struct PreparedLineBuild: Sendable {
    let line: RailNetworkStore.DrawnLine
    let coordinateChunks: [[CLLocationCoordinate2D]]
    let historicalCoordinateChunks: [[CLLocationCoordinate2D]]
    let familyCoordinateChunks: [String: PreparedFamilyRunBuild]
    let familyFallbacks: [PreparedFamilyFallbackRunBuild]
    let fallbackSplitReserve: Int
}

/// One complete continuous stroke at a drawing scale: its colour runs,
/// platform positions and the stroke a recorded ride can slice. Viewport
/// selection uses cached polyline chunks without repeating this geometry.
///
/// `stroke` is what a ride's own `StrokeRef` is sliced out of
/// (`ContinuousStroke.slice(points:measures:from:to:)`) — clipping to the
/// build rect is right for what the network OVERLAY draws, but a ride can be
/// selected, played back or tapped from off screen, so the geometry it slices
/// has to be the whole chain, not merely the runs on screen this frame.
struct ContinuousStrokeBuild: Sendable {
    let runs: [[Coordinate]]
    let anchors: [Int: CLLocationCoordinate2D]
    let stroke: ContinuousStroke.Stroke
    let sourceMeasures: [Double]
    /// Withheld spans (`RailNetworkStore.DrawnLine.withheld`), sliced out of
    /// `stroke` by metre measure — the same `ContinuousStroke.slice` call a
    /// ride's own `StrokeRef` is cut with, so the dashed overlay can never sit
    /// a fraction of a pixel off the field it traces. Unclipped, like `stroke`
    /// itself: a withheld span is short (kilometres, not a viewport), so it is
    /// always built whole rather than run through the build-rect cull.
    ///
    /// Each run carries the colour key it should draw under: ordinarily the
    /// line's own, but a span that falls inside a landlord family window
    /// (`RailNetworkStore.DrawnLine.familyWindows`) carries that family's
    /// colour instead — the solid field under the dash there is the shared
    /// family stroke, not this line's own, and a same-colour dash on a
    /// same-colour field disappears (see the withheld-casing note where this
    /// is consumed).
    let withheldRuns: [(colorHex: String, colorDarkHex: String, coordinates: [Coordinate])]
    /// Landlord family windows, sliced out of `stroke` by metre measure the
    /// same way `withheldRuns` is: the stretches THIS chain draws in the
    /// shared family colour instead of its own. `runs` above already
    /// excludes both these and any tenant window, so the base colour and the
    /// family colour never draw the same pixels twice. One entry per
    /// surviving landlord window; preparation creates its measured chunks.
    let emittedFamilyWindows: [ContinuousStroke.WindowSpan]
}

/// Draw a reviewed continuous-stroke line as ONE polyline: the chain
/// of intervals is joined at its shared station anchors, projected to the
/// pixel space this frame is drawn in, handed to `RailCore.ContinuousStroke`
/// — the port of rail-stroke.js — which bakes the screen-space lane offset in
/// through its smoothed lane profile and rounds the corners, and only then
/// clipped to the build rect. Clipping after offsetting is what keeps the
/// stroke whole across the viewport: an edge is kept when its own box meets
/// the rect, so nothing on screen is ever the end of a piece.
/// The joined chain of a continuous line's own intervals, stitched at shared
/// station anchors, with the cumulative metres along it on the ruler the
/// lane rows were measured with (rail-network.js `distanceMeters`: 111320 m
/// per degree on both axes, longitude scaled by the cosine of the mean
/// latitude).
///
/// Coordinates are already in the display datum. `prepareDisplayLine` and the
/// canonical package decode both apply `AppleMapDatum.display` before
/// constructing `DrawnLine`, so `intervals` are not raw WGS84. Callers project
/// this chain or hand it to `StrokeRide`; they must not shift it again. The
/// display-datum chain does not change with zoom — a rebuild at a different
/// scale re-projects it but never re-joins it. ``JoinedChainCache`` is the only
/// caller: junction indexing, stroke matching and pixel projection read that
/// one result.
func joinedChainCoordinates(
    of line: RailNetworkStore.DrawnLine
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

/// One joined display chain. `points` and `measures` stay in the display datum;
/// screen pixels are a separate cache.
struct JoinedChain: Sendable {
    var points: [Coordinate]
    var measures: [Double]
}

/// `DrawnLine.contentID` plus that line's chain identity (`DrawnLine.id`,
/// `lineKey#chain` or `lineKey@lane`). A replacement overview or full document
/// with the same public id gets a new `contentID` and does not reuse the old chain.
struct JoinedChainKey: Hashable, Sendable {
    var contentID: UUID
    var chainID: String

    init(_ line: RailNetworkStore.DrawnLine) {
        contentID = line.contentID
        chainID = line.id
    }
}

/// The one join of each resident display chain. Junction indexing, stroke
/// matching and pixel projection all read ``chain(of:)``. The join runs only
/// on a miss, and only while this lock is held, so concurrent readers share
/// that result. A chain left out of ``retain(_:)`` is not stored again.
final class JoinedChainCache: Sendable {
    private struct Storage {
        var constrained = false
        var resident: Set<JoinedChainKey> = []
        var chains: [JoinedChainKey: JoinedChain] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: Storage())

    func chain(of line: RailNetworkStore.DrawnLine) -> JoinedChain {
        let key = JoinedChainKey(line)
        return state.withLock { storage in
            if let hit = storage.chains[key] { return hit }
            let built = joinedChainCoordinates(of: line)
            let value = JoinedChain(points: built.points, measures: built.measures)
            if !storage.constrained || storage.resident.contains(key) {
                storage.chains[key] = value
            }
            return value
        }
    }

    func retain(_ keys: Set<JoinedChainKey>) {
        state.withLock { storage in
            storage.constrained = true
            storage.resident = keys
            storage.chains = storage.chains.filter { keys.contains($0.key) }
        }
    }

    func admits(_ key: JoinedChainKey) -> Bool {
        state.withLock { !$0.constrained || $0.resident.contains(key) }
    }
}

/// Project an already-joined display chain. This does not walk `intervals`.
func continuousChainPixels(
    _ joined: JoinedChain, mapPointsPerScreenPoint: Double
) -> (points: [ContinuousStroke.Point], measures: [Double]) {
    let points = joined.points.map { coordinate -> ContinuousStroke.Point in
        let point = MKMapPoint(coordinate.clLocation)
        return ContinuousStroke.Point(
            x: point.x / mapPointsPerScreenPoint, y: point.y / mapPointsPerScreenPoint)
    }
    return (points, joined.measures)
}

/// Screen projection of joined chains. Identity is the geometry frame (zoom
/// bucket, display scale, lane LOD) plus the datum token of the coordinates
/// already stored on the chain. A different identity drops the pixels; it does
/// not join again and does not call `AppleMapDatum.display`.
final class ChainPixelCache: Sendable {
    struct Projection: Equatable, Sendable {
        var frameKey: String
        var datumToken: String
        var mapPointsPerScreenPoint: Double
        var lodScale: Double
    }

    private struct Storage {
        var projection: Projection?
        var held: [JoinedChainKey: (points: [ContinuousStroke.Point], measures: [Double])] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: Storage())
    let joinedChains: JoinedChainCache

    init(joinedChains: JoinedChainCache) {
        self.joinedChains = joinedChains
    }

    func begin(_ projection: Projection) {
        state.withLock { storage in
            guard storage.projection != projection else { return }
            storage.held.removeAll(keepingCapacity: true)
            storage.projection = projection
        }
    }

    func projectedChain(
        of line: RailNetworkStore.DrawnLine, projection: Projection
    ) -> (points: [ContinuousStroke.Point], measures: [Double]) {
        let key = JoinedChainKey(line)
        if let hit = state.withLock({ storage -> (points: [ContinuousStroke.Point], measures: [Double])? in
            guard storage.projection == projection else { return nil }
            return storage.held[key]
        }) { return hit }
        let joined = joinedChains.chain(of: line)
        let projected = continuousChainPixels(joined, mapPointsPerScreenPoint: projection.mapPointsPerScreenPoint)
        let admit = joinedChains.admits(key)
        return state.withLock { storage in
            guard storage.projection == projection else { return projected }
            if let hit = storage.held[key] { return hit }
            if admit { storage.held[key] = projected }
            return projected
        }
    }

    func displayChain(of line: RailNetworkStore.DrawnLine) -> JoinedChain {
        joinedChains.chain(of: line)
    }

    func retain(_ keys: Set<JoinedChainKey>) {
        state.withLock { storage in
            storage.held = storage.held.filter { keys.contains($0.key) }
        }
    }
}

/// One prepare pass's view of ``ChainPixelCache``: the frame, LOD and datum it
/// may reuse, and the map-point scale those pixels were divided by.
struct ChainPixelReader: Sendable {
    let cache: ChainPixelCache
    let projection: ChainPixelCache.Projection

    func chain(of line: RailNetworkStore.DrawnLine) -> (points: [ContinuousStroke.Point], measures: [Double]) {
        cache.projectedChain(of: line, projection: projection)
    }

    func displayChain(of line: RailNetworkStore.DrawnLine) -> JoinedChain {
        cache.displayChain(of: line)
    }
}

/// Lines that could carry a tangent junction, keyed by the surveyed vertex they
/// pass through (plus region and operator). Built once per prepare pass in id
/// order, so `continuousJoin` examines only lines that actually touch the
/// endpoint instead of every line in the network.
struct JunctionCandidateIndex {
    private let index: StrokeJunctionIndex
    private let byID: [String: RailNetworkStore.DrawnLine]
    init() {
        index = StrokeJunctionIndex([])
        byID = [:]
    }
    init(_ lines: [String: RailNetworkStore.DrawnLine], chains: JoinedChainCache) {
        byID = lines
        index = StrokeJunctionIndex(lines.values.map { line in
            .init(id: line.id, region: line.region.rawValue, operatorName: line.operatorName,
                  coordinates: chains.chain(of: line).points, continuous: line.continuous,
                  follows: line.follows.map(\.canonicalID))
        })
    }
    func lines(sharing coordinate: Coordinate, region: Region, operatorName: String?) -> [RailNetworkStore.DrawnLine] {
        index.candidateIDs(sharing: coordinate, region: region.rawValue, operatorName: operatorName)
            .compactMap { byID[$0] }
    }
    func dependencyIDs(of id: String) -> Set<String> {
        index.dependencyIDs(of: id)
    }
}

/// Family ink not supplied by a selected landlord, sliced from this tenant's
/// complete prepared stroke. Coverage uses this tenant's own metre ruler.
@MainActor
func familyFallbackBuilds(
    for build: LineBuild, stroke: ContinuousStrokeBuild,
    mapPointsPerScreenPoint: Double, windows: [ContinuousStroke.WindowSpan]
) -> [FamilyRunBuild] {
    var result: [FamilyRunBuild] = []
    for window in windows {
        if let prepared = build.familyFallbacks.first(where: { $0.window == window }) {
            result.append(prepared.family)
            continue
        }
        guard let prepared = build.familyFallbacks.first(where: {
            $0.window.groupID == window.groupID && $0.window.from <= window.from && window.to <= $0.window.to
        }) else { continue }
        let ranges = ContinuousStroke.intersectingChunkRanges(
            ranges: [.init(from: window.from, to: window.to)],
            chunks: prepared.family.chunkWindows.map { .init(from: $0.from, to: $0.to) })
        var polylines: [MKPolyline] = []
        var chunkWindows: [ContinuousStroke.WindowSpan] = []
        for range in ranges {
            let chunkWindow = ContinuousStroke.WindowSpan(from: range.from, to: range.to, groupID: window.groupID)
            if let index = prepared.family.chunkWindows.firstIndex(of: chunkWindow) {
                polylines.append(prepared.family.polylines[index])
                chunkWindows.append(chunkWindow)
                continue
            }
            let coordinates = ContinuousStroke.slice(
                points: stroke.stroke.points, measures: stroke.stroke.measures,
                from: range.from, to: range.to).map {
                    MKMapPoint(x: $0.x * mapPointsPerScreenPoint,
                               y: $0.y * mapPointsPerScreenPoint).coordinate
                }
            guard coordinates.count >= 2 else { continue }
            polylines.append(mapPolylineChunk(coordinates))
            chunkWindows.append(chunkWindow)
        }
        guard !polylines.isEmpty else { continue }
        result.append(FamilyRunBuild(
            colorHex: prepared.family.colorHex, colorDarkHex: prepared.family.colorDarkHex,
            polylines: polylines, chunkWindows: chunkWindows))
    }
    return result
}

/// The joint one chain of a continuous line shares with the chain before or
/// after it, when the two meet at the same surveyed vertex.
///
/// A line the display pass cut into chains is still ONE railway. Each chain is
/// offset by its own lane rows and approaches the shared vertex from its own
/// direction, so without this the two strokes step apart there — measured on
/// the shipped US package at 18.9 px on `mta-…-city-terminal-zone` (lane
/// −3.5) and 2.7 px on `amtrak-ethan-allen-express`. Handing both chains the
/// neighbour's terminal lane and the same pair of tangents at the joint makes
/// them land on the same point; see `ContinuousStroke.Join`.
func continuousJoin(
    of line: RailNetworkStore.DrawnLine, at end: Bool,
    neighbour: (String) -> RailNetworkStore.DrawnLine?, chains: ChainPixelReader,
    junctionCandidates: JunctionCandidateIndex = JunctionCandidateIndex()
) -> ContinuousStroke.Join? {
    let branch = chains.chain(of: line)
    let terminal = ContinuousStroke.terminalLanes(rows: line.laneRows, total: line.totalMetres)
    let endpointCoordinate = chains.displayChain(of: line).points
    let probe = end ? endpointCoordinate.last : endpointCoordinate.first
    let candidates = probe.map { junctionCandidates.lines(sharing: $0, region: line.region, operatorName: line.operatorName) } ?? []
    // A physical Y split owns one surveyed junction. Its three endpoint
    // parts meet at the survey centre, without a sharp adjacent-part mitre.
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
        // A steep real fork still meets at the same point; retain its own
        // edge direction rather than borrowing an unrelated sharp tangent.
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
        guard main.mapRect.intersects(line.mapRect) else { continue }
        let through = chains.chain(of: main)
        let endpoint = end ? branch.points.last : branch.points.first
        guard let endpoint, let vertex = through.points.firstIndex(of: endpoint),
              vertex > 0, vertex + 1 < through.points.count else { continue }
        let pixelLength = zip(through.points, through.points.dropFirst()).reduce(0.0) {
            $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        let metresPerPixel = pixelLength > 0 ? main.totalMetres / pixelLength : 0
        let width = max(ContinuousStroke.laneRampHalfWidthMetres, RailStyle.strokeMinRamp * metresPerPixel)
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

private func continuousPartJoin(
    of line: RailNetworkStore.DrawnLine, at end: Bool,
    neighbour: (String) -> RailNetworkStore.DrawnLine?, chains: ChainPixelReader
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
    // The chain after a boundary owns the reviewed decision for both sides.
    // A coincident station anchor is not enough evidence that two branches
    // share one tangent continuation.
    if end ? !other.joinPrevious : !line.joinPrevious { return nil }
    let own = chains.chain(of: line)
    let theirs = chains.chain(of: other)
    guard own.points.count >= 2, theirs.points.count >= 2 else { return nil }
    // The pair of raw edges at the joint, in the digitised order: the chain
    // that arrives, then the chain that leaves. Both chains derive it from
    // these same two edges, so both mitre the shared vertex identically.
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

func continuousStrokeBuild(
    for line: RailNetworkStore.DrawnLine, anchors: [Int],
    canonical: (String) -> RailNetworkStore.DrawnLine?,
    chains: ChainPixelReader,
    mapPointsPerScreenPoint: Double, scale: CGFloat,
    laneScale: Double = 1, junctionCandidates: JunctionCandidateIndex = JunctionCandidateIndex()
) -> ContinuousStrokeBuild {
    // `Stroke` has no public initializer of its own (`ContinuousStroke.swift`
    // is not this file's to extend), so an empty one is built the same way
    // `buildStroke` builds one for fewer than two points itself.
    let emptyStroke = ContinuousStroke.buildStroke(
        [], options: .init(rows: [], totalMetres: 0, laneGapPx: 0, minRampPx: 0, cornerRadiusPx: 0, anchors: []))
    guard mapPointsPerScreenPoint > 0 else {
        return ContinuousStrokeBuild(
            runs: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [],
            emittedFamilyWindows: [])
    }
    let chain = chains.chain(of: line)
    let pixels = chain.points
    guard pixels.count >= 2 else {
        return ContinuousStrokeBuild(
            runs: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [],
            emittedFamilyWindows: [])
    }
    // The canonical alignments this chain is drawn from, projected into the
    // same pixel space; a follow whose canonical chain is not loaded is
    // simply not applied.
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
    let stroke = ContinuousStroke.buildStroke(
        pixels,
        options: .init(
            measures: chain.measures,
            rows: line.laneRows, totalMetres: line.totalMetres,
            laneGapPx: Double(RailStyle.parallelLaneCentreDistance * scale) * laneScale,
            minRampPx: RailStyle.strokeMinRamp,
            cornerRadiusPx: Double(RailStyle.strokeCornerRadius * scale),
            // The radius the map PROMISES to present. Passing it is what turns
            // that promise into an operation: where a corner's own edges are
            // too short to carry it, the run of vertices is rounded as one
            // corner rather than leaving a kink at each of them.
            minCornerRadiusPx: Double(RailStyle.minimumCornerRadius(atScale: scale)),
            anchors: anchors, follows: follows,
            shapeBoundaryMeasures: line.familyWindows.flatMap { [$0.from, $0.to] },
            joinStart: continuousJoin(
                of: line, at: false, neighbour: canonical, chains: chains, junctionCandidates: junctionCandidates),
            joinEnd: continuousJoin(
                of: line, at: true, neighbour: canonical, chains: chains, junctionCandidates: junctionCandidates),
            enforceMinimumCornerRadius: true))
    func mapPoint(_ point: ContinuousStroke.Point) -> MKMapPoint {
        MKMapPoint(x: point.x * mapPointsPerScreenPoint, y: point.y * mapPointsPerScreenPoint)
    }
    var anchorPoints: [Int: CLLocationCoordinate2D] = [:]
    for (slot, index) in anchors.enumerated() where slot < stroke.anchors.count {
        anchorPoints[index] = mapPoint(stroke.anchors[slot]).coordinate
    }
    let points = stroke.points.map(mapPoint)
    func coordinate(_ point: MKMapPoint) -> Coordinate {
        let held = point.coordinate
        return Coordinate(lon: held.longitude, lat: held.latitude)
    }
    // Sliced straight off the just-built stroke by metre measure, exactly the
    // way `drawnCoordinates(of:ride:)` cuts a ride's own segment — no extra
    // Douglas–Peucker pass here, because this IS the simplified polyline a
    // ride slice already reuses; the lane offset and corner rounding are
    // already baked into `stroke.points`, so unprojecting is the whole job.
    func sliceRun(_ from: Double, _ to: Double) -> [Coordinate]? {
        let sliced = ContinuousStroke.slice(
            points: stroke.points, measures: stroke.measures, from: from, to: to)
        guard sliced.count >= 2 else { return nil }
        return sliced.map { coordinate(mapPoint($0)) }
    }
    // This chain's own family-collapse windows, split by role — reused below
    // by the run partition AND the withheld clip, so a line with no family
    // windows at all runs both through the same code with empty lists
    // (`ContinuousStroke.familyPartition`/`clipRangesToComplement` are then
    // the identity split/no-op they were always meant to be).
    let tenantWindows = line.familyWindows.filter { !$0.isLandlord }
    let landlordWindows = line.familyWindows.filter(\.isLandlord)
    let tenantSpans = tenantWindows.map {
        ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupID)
    }
    let landlordSpans = landlordWindows.map {
        ContinuousStroke.WindowSpan(from: $0.from, to: $0.to, groupID: $0.groupID)
    }
    var runs: [[Coordinate]] = []
    var emittedFamilyWindows: [ContinuousStroke.WindowSpan] = []
    if line.familyWindows.isEmpty {
        // Cache the complete, zoom-dependent stroke. Viewport selection happens
        // on stable polyline chunks after lane offsets and rounding are finished.
        runs = points.count >= 2 ? [points.map(coordinate)] : []
    } else {
        // A family window (`RailNetworkStore.DrawnLine.familyWindows`) is a
        // stretch this chain shares with a sibling railway of the same
        // operator collapse — kilometres, not a viewport, the same scale
        // `withheld` already draws unclipped at above. So a line with ANY
        // family window is built whole here too, split by metre measure
        // instead of by the build-rect edge test above: `runs` becomes the
        // complement of every window — tenant AND landlord alike withhold
        // this chain's OWN colour there — and each landlord window becomes
        // its own measured entry, in the shared family's colour.
        // Windows are reviewed non-overlapping and sorted (the data
        // contract `familyWindowsByRegion` is built to). The boundary walk
        // itself is `ContinuousStroke.familyPartition` — the production
        // function `port-fixtures/family-windows.json` and
        // `FamilyWindowParityTests` both pin, so this file no longer hand-
        // mirrors it.
        let lower = stroke.measures.first ?? 0
        let upper = stroke.measures.last ?? 0
        let partition = ContinuousStroke.familyPartition(
            totalMetres: line.totalMetres, tenantWindows: tenantSpans, landlordWindows: landlordSpans,
            measureStart: lower, measureEnd: upper)
        for piece in partition.base {
            if let run = sliceRun(piece.from, piece.to) { runs.append(run) }
        }
        for piece in partition.family {
            // `familyPartition` returns one piece per surviving landlord
            // window (never merged with a neighbour), so the source window
            // this piece came from is the one of the same group that
            // contains it. Keep only pieces with both a source and real ink;
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
    // A withheld span (`RailNetworkStore.DrawnLine.withheld`) is clipped to
    // the complement of this chain's OWN tenant windows first
    // (`ContinuousStroke.clipRangesToComplement`): a span inside a tenant
    // window sits on track this line draws NOWHERE (the base feature just
    // excluded that exact stretch, and the landlord's own stroke — not this
    // one — draws it), so dashing it here would dash a field with no solid
    // stroke under it. A span straddling a tenant edge keeps only the
    // piece(s) still this line's own track.
    //
    // Each surviving piece is then split again at every landlord-window edge
    // it crosses, so no single drawn dash spans both a landlord stretch and
    // plain track — the OLD code tinted a whole span by its MIDPOINT alone,
    // which is wrong the moment a span straddles a landlord edge (the near
    // half sits on the shared family stroke, in that group's colour; the far
    // half sits on this line's own colour, plain track). A piece inside a
    // landlord window is tinted with that family's colour — it still sits on
    // real track, just drawn by this line's own family feature rather than
    // its base one, and the two already share a colour. A piece on plain
    // track keeps this line's own colour.
    var withheldRuns: [(colorHex: String, colorDarkHex: String, coordinates: [Coordinate])] = []
    for span in line.withheld {
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
                    coordinates))
            }
        }
    }
    return ContinuousStrokeBuild(
        runs: runs, anchors: anchorPoints, stroke: stroke, sourceMeasures: chain.measures,
        withheldRuns: withheldRuns, emittedFamilyWindows: emittedFamilyWindows)
}

/// Offset one display fragment in projected map space. The canonical package
/// geometry stays untouched; only the MKPolyline submitted for this frame is
/// shifted, by the same point token the Web renderer applies with line-offset.
func parallelLaneCoordinates(
    _ coordinates: [CLLocationCoordinate2D], lane: Double,
    mapPointsPerScreenPoint: Double, scale: CGFloat, alreadyCurved: Bool = false
) -> [CLLocationCoordinate2D] {
    guard coordinates.count >= 2, mapPointsPerScreenPoint > 0, !alreadyCurved || lane != 0 else { return coordinates }
    let pixels = coordinates.map { coordinate in
        let point = MKMapPoint(coordinate)
        return ContinuousStroke.Point(x: point.x / mapPointsPerScreenPoint,
                                      y: point.y / mapPointsPerScreenPoint)
    }
    let survey = coordinates.map { Coordinate(lon: $0.longitude, lat: $0.latitude) }
    var measures = [Double](repeating: 0, count: survey.count)
    for index in 1..<survey.count {
        measures[index] = measures[index - 1] + Geometry.distanceMeters(survey[index - 1], survey[index])
    }
    let total = measures.last ?? 0
    let stroke = ContinuousStroke.buildStroke(pixels, options: .init(
        measures: measures, rows: [.init(from: 0, to: total, lane: lane)], totalMetres: total,
        laneGapPx: Double(RailStyle.parallelLaneCentreDistance * scale),
        minRampPx: RailStyle.strokeMinRamp,
        cornerRadiusPx: Double(RailStyle.strokeCornerRadius * scale),
        minCornerRadiusPx: Double(RailStyle.minimumCornerRadius(atScale: scale)),
        anchors: [0, pixels.count - 1], enforceMinimumCornerRadius: true, curveCentreline: !alreadyCurved))
    return stroke.points.map {
        MKMapPoint(x: $0.x * mapPointsPerScreenPoint, y: $0.y * mapPointsPerScreenPoint).coordinate
    }
}

/// The worker owns projection caches; results contain immutable geometry only.
/// No view, renderer, annotation, or coordinator is accessed here.
enum MapLineGeometry {
    /// Main-actor product consumed by ``MapNetworkGeometryCache``.
    struct Prepared {
        var strokes: [String: ContinuousStrokeBuild] = [:]
        var lines: [String: LineBuild] = [:]
    }

    /// Sendable value geometry produced by the detached worker.
    struct PreparedGeometry: Sendable {
        var strokes: [String: ContinuousStrokeBuild] = [:]
        var lines: [String: PreparedLineBuild] = [:]
    }

    static func prepare(
        lines: [RailNetworkStore.DrawnLine], strokes: [RailNetworkStore.DrawnLine],
        allLines: [String: RailNetworkStore.DrawnLine], anchors: [String: [Int]],
        cachedStrokes: [String: ContinuousStrokeBuild],
        joinedChains: JoinedChainCache, chainPixels: ChainPixelCache,
        frameKey: String, datumToken: String,
        mapScale: Double, scale: CGFloat, laneScale: Double,
        era: DisplayNetworkEra = .current,
        rideDate: String? = nil,
        todayByRegion: [String: String] = [:]
    ) throws -> PreparedGeometry {
        let interval = RailSignpost.map.begin("map.geometry.prepare")
        defer { RailSignpost.map.end("map.geometry.prepare", interval) }
        let projection = ChainPixelCache.Projection(
            frameKey: frameKey, datumToken: datumToken,
            mapPointsPerScreenPoint: mapScale, lodScale: laneScale)
        chainPixels.begin(projection)
        let chains = ChainPixelReader(cache: chainPixels, projection: projection)
        var result = PreparedGeometry()
        let junctionCandidates = JunctionCandidateIndex(allLines, chains: joinedChains)
        for line in strokes {
            try Task.checkCancellation()
            result.strokes[line.id] = continuousStrokeBuild(
                for: line, anchors: anchors[line.id] ?? [], canonical: { allLines[$0] },
                chains: chains, mapPointsPerScreenPoint: mapScale, scale: scale,
                laneScale: laneScale, junctionCandidates: junctionCandidates)
        }
        for line in lines {
            try Task.checkCancellation()
            let stroke = result.strokes[line.id] ?? cachedStrokes[line.id]
            let today = todayByRegion[line.region.rawValue] ?? ""
            let epsilon = MKMetersPerMapPointAtLatitude(
                MKMapPoint(x: line.mapRect.midX, y: line.mapRect.midY).coordinate.latitude)
                * mapScale * RailStyle.simplifyTolerance
            func coordinateChunks(
                _ runs: [[Coordinate]], preservingPattern: Bool = false
            ) throws -> [[CLLocationCoordinate2D]] {
                var result: [[CLLocationCoordinate2D]] = []
                for interval in runs where interval.count >= 2 {
                    try Task.checkCancellation()
                    // Continuous geometry already spent its simplification budget
                    // before rounding. Never decimate those arcs a second time.
                    let coordinates = line.continuous || line.lane != 0 ? interval.map(\.clLocation)
                        : Geometry.douglasPeuckerIndices(interval, epsilonMeters: epsilon)
                            .map { interval[$0].clLocation }
                    let points = parallelLaneCoordinates(
                        coordinates, lane: line.lane,
                        mapPointsPerScreenPoint: mapScale, scale: scale, alreadyCurved: line.continuous)
                    result.append(contentsOf: mapCoordinateChunks(points, preservingPattern: preservingPattern))
                }
                return result
            }
            // Draw filter only. `intervals` and `continuousStrokeBuild` stay
            // whole — a hidden continuous chain still builds above for rides,
            // and simply contributes no network stroke here.
            let solidRuns: [[Coordinate]]
            let historicalRuns: [[Coordinate]]
            let drawFamilies: Bool
            if line.continuous {
                let span = line.partSpans.first ?? nil
                let shown = era.shows(span, today: today, rideDate: rideDate)
                drawFamilies = shown
                if !shown {
                    solidRuns = []
                    historicalRuns = []
                } else if DisplayNetworkEra.strokeStyle(for: span?.kind ?? .current) == .historical {
                    solidRuns = []
                    historicalRuns = stroke?.runs ?? line.intervals
                } else {
                    solidRuns = stroke?.runs ?? line.intervals
                    historicalRuns = []
                }
            } else {
                drawFamilies = true
                var solid: [[Coordinate]] = []
                var historical: [[Coordinate]] = []
                for (index, interval) in line.intervals.enumerated() {
                    let span: DisplayTemporalDecoration? = line.partSpans.isEmpty
                        ? nil
                        : (line.partSpans.indices.contains(index) ? line.partSpans[index] : nil)
                    guard era.shows(span, today: today, rideDate: rideDate) else { continue }
                    if DisplayNetworkEra.strokeStyle(for: span?.kind ?? .current) == .historical {
                        historical.append(interval)
                    } else {
                        solid.append(interval)
                    }
                }
                solidRuns = solid
                historicalRuns = historical
            }
            var families: [String: PreparedFamilyRunBuild] = [:]
            var fallbacks: [PreparedFamilyFallbackRunBuild] = []
            var fallbackSplitReserve = 0
            if drawFamilies {
                if let stroke {
                    func measuredFamily(
                        from: Double, to: Double, groupID: String, colorHex: String, colorDarkHex: String
                    ) -> PreparedFamilyRunBuild {
                        let chunks = ContinuousStroke.measuredSliceChunks(
                            points: stroke.stroke.points, measures: stroke.stroke.measures, from: from, to: to)
                        return PreparedFamilyRunBuild(
                            colorHex: colorHex, colorDarkHex: colorDarkHex,
                            coordinateChunks: chunks.map { chunk in
                                chunk.points.map {
                                    MKMapPoint(x: $0.x * mapScale, y: $0.y * mapScale).coordinate
                                }
                            }, chunkWindows: chunks.map {
                                .init(from: $0.from, to: $0.to, groupID: groupID)
                            })
                    }
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
                        fallbacks.append(PreparedFamilyFallbackRunBuild(
                            window: .init(from: tenant.from, to: tenant.to, groupID: tenant.groupID),
                            family: prepared))
                        // A later pan can select the landlord without changing
                        // resident data. Prepare only this reviewed family owner
                        // now so the cached tenant already reserves its cuts.
                        for follow in line.follows where follow.to > tenant.from && follow.from < tenant.to {
                            guard result.strokes[follow.canonicalID] == nil,
                                  cachedStrokes[follow.canonicalID] == nil,
                                  let owner = allLines[follow.canonicalID], owner.continuous,
                                  owner.familyWindows.contains(where: {
                                      $0.isLandlord && $0.groupID == tenant.groupID
                                          && $0.to > min(follow.canonicalFrom, follow.canonicalTo)
                                          && $0.from < max(follow.canonicalFrom, follow.canonicalTo)
                                  }) else { continue }
                            try Task.checkCancellation()
                            result.strokes[owner.id] = continuousStrokeBuild(
                                for: owner, anchors: anchors[owner.id] ?? [], canonical: { allLines[$0] },
                                chains: chains, mapPointsPerScreenPoint: mapScale, scale: scale,
                                laneScale: laneScale, junctionCandidates: junctionCandidates)
                        }
                        // Partial selected coverage can cut a cached window into
                        // multiple pieces. Reserve boundary/chunk vertices too.
                        let possibleCoverage = line.follows.reduce(0) { count, follow in
                            guard follow.to > tenant.from, follow.from < tenant.to,
                                  let owner = result.strokes[follow.canonicalID]
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
                }
            }
            result.lines[line.id] = PreparedLineBuild(
                line: line, coordinateChunks: try coordinateChunks(solidRuns),
                historicalCoordinateChunks: try coordinateChunks(historicalRuns, preservingPattern: true),
                familyCoordinateChunks: families, familyFallbacks: fallbacks,
                fallbackSplitReserve: fallbackSplitReserve)
        }
        try Task.checkCancellation()
        return result
    }

    /// Publish a worker result as native MapKit geometry. The caller performs
    /// its cancellation/generation check before entering this synchronous step.
    @MainActor
    static func materialize(_ geometry: PreparedGeometry) -> Prepared {
        var result = Prepared(strokes: geometry.strokes)
        result.lines.reserveCapacity(geometry.lines.count)
        for (id, prepared) in geometry.lines {
            let families = prepared.familyCoordinateChunks.mapValues { family in
                FamilyRunBuild(
                    colorHex: family.colorHex,
                    colorDarkHex: family.colorDarkHex,
                    polylines: mapPolylineChunks(family.coordinateChunks), chunkWindows: family.chunkWindows)
            }
            result.lines[id] = LineBuild(
                line: prepared.line,
                polylines: mapPolylineChunks(prepared.coordinateChunks),
                historicalPolylines: mapPolylineChunks(prepared.historicalCoordinateChunks),
                familyPolylines: families,
                familyFallbacks: prepared.familyFallbacks.map { fallback in
                    FamilyFallbackRunBuild(window: fallback.window, family: FamilyRunBuild(
                        colorHex: fallback.family.colorHex, colorDarkHex: fallback.family.colorDarkHex,
                        polylines: mapPolylineChunks(fallback.family.coordinateChunks),
                        chunkWindows: fallback.family.chunkWindows))
                }, fallbackSplitReserve: prepared.fallbackSplitReserve)
        }
        return result
    }

    /// Publish native MapKit geometry without monopolising one main-actor turn.
    /// Each chunk is still created and appended in the synchronous path's order.
    @MainActor
    static func materialize(
        _ geometry: PreparedGeometry, budget: Duration = .milliseconds(5)
    ) async -> Prepared? {
        let clock = ContinuousClock()
        var lastYield = clock.now
        func yieldIfNeeded() async -> Bool {
            guard clock.now - lastYield >= budget else { return true }
            await Task.yield()
            guard !Task.isCancelled else { return false }
            lastYield = clock.now
            return true
        }

        var result = Prepared(strokes: geometry.strokes)
        result.lines.reserveCapacity(geometry.lines.count)
        for (id, prepared) in geometry.lines {
            var families: [String: FamilyRunBuild] = [:]
            families.reserveCapacity(prepared.familyCoordinateChunks.count)
            for (key, family) in prepared.familyCoordinateChunks {
                var familyPolylines: [MKPolyline] = []
                familyPolylines.reserveCapacity(family.coordinateChunks.count)
                for chunk in family.coordinateChunks {
                    familyPolylines.append(mapPolylineChunk(chunk))
                    guard await yieldIfNeeded() else { return nil }
                }
                families[key] = FamilyRunBuild(
                    colorHex: family.colorHex,
                    colorDarkHex: family.colorDarkHex,
                    polylines: familyPolylines, chunkWindows: family.chunkWindows)
                guard await yieldIfNeeded() else { return nil }
            }

            var polylines: [MKPolyline] = []
            polylines.reserveCapacity(prepared.coordinateChunks.count)
            for chunk in prepared.coordinateChunks {
                polylines.append(mapPolylineChunk(chunk))
                guard await yieldIfNeeded() else { return nil }
            }

            var historicalPolylines: [MKPolyline] = []
            historicalPolylines.reserveCapacity(prepared.historicalCoordinateChunks.count)
            for chunk in prepared.historicalCoordinateChunks {
                historicalPolylines.append(mapPolylineChunk(chunk))
                guard await yieldIfNeeded() else { return nil }
            }

            var fallbacks: [FamilyFallbackRunBuild] = []
            for fallback in prepared.familyFallbacks {
                var fallbackPolylines: [MKPolyline] = []
                for chunk in fallback.family.coordinateChunks {
                    fallbackPolylines.append(mapPolylineChunk(chunk))
                    guard await yieldIfNeeded() else { return nil }
                }
                fallbacks.append(FamilyFallbackRunBuild(window: fallback.window, family: FamilyRunBuild(
                    colorHex: fallback.family.colorHex, colorDarkHex: fallback.family.colorDarkHex,
                    polylines: fallbackPolylines, chunkWindows: fallback.family.chunkWindows)))
            }

            result.lines[id] = LineBuild(
                line: prepared.line,
                polylines: polylines,
                historicalPolylines: historicalPolylines,
                familyPolylines: families, familyFallbacks: fallbacks,
                fallbackSplitReserve: prepared.fallbackSplitReserve)
            guard await yieldIfNeeded() else { return nil }
        }
        return result
    }
}
