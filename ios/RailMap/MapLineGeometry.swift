import MapKit
import RailCore
import SwiftUI

extension RailNetworkStore.DrawnLine: LODLine {}

/// One line's decimated geometry, kept with the line so the vertex budget can
/// shed the least important rather than simply the last built.
struct LineBuild: LODBuild {
    let line: RailNetworkStore.DrawnLine
    let polylines: [MKPolyline]
    /// Landlord family-window polylines (`ContinuousStrokeBuild.familyRuns`,
    /// simplified through the same Douglas–Peucker call `polylines` above
    /// is), keyed by the shared family's own colour hex pair. Drawn under
    /// THAT colour in `byColor`, alongside but separate from this line's own
    /// bucket above — the region `polylines` already excludes wherever this
    /// chain is the landlord. Empty for a line with no family windows.
    let familyPolylines: [String: FamilyRunBuild]
    init(
        line: RailNetworkStore.DrawnLine, polylines: [MKPolyline],
        familyPolylines: [String: FamilyRunBuild] = [:]
    ) {
        self.line = line
        self.polylines = polylines
        self.familyPolylines = familyPolylines
    }
    func intersecting(_ rect: MKMapRect) -> LineBuild {
        LineBuild(line: line,
            polylines: polylines.filter { $0.boundingMapRect.intersects(rect) },
            familyPolylines: familyPolylines.compactMapValues { family in
                let kept = family.polylines.filter { $0.boundingMapRect.intersects(rect) }
                return kept.isEmpty ? nil : FamilyRunBuild(
                    colorHex: family.colorHex, colorDarkHex: family.colorDarkHex, polylines: kept)
            })
    }

    var drawnVertexCount: Int {
        polylines.reduce(0) { $0 + $1.pointCount }
            + familyPolylines.values.reduce(0) { $0 + $1.polylines.reduce(0) { $0 + $1.pointCount } }
    }
}

/// Stable coordinate chunks share their terminal vertex, preserving every
/// segment. Split only AFTER simplification and offsets, so chunk boundaries
/// cannot kink lanes. These value-only chunks are safe to prepare off-main.
func mapCoordinateChunks(
    _ points: [CLLocationCoordinate2D]
) -> [[CLLocationCoordinate2D]] {
    guard points.count >= 2 else { return [] }
    return stride(from: 0, to: points.count - 1, by: 128).map { start in
        Array(points[start..<min(start + 129, points.count)])
    }
}

/// Construct MapKit reference objects only on the main actor, immediately
/// before they enter the mounted-geometry cache.
@MainActor
func mapPolylineChunks(
    _ chunks: [[CLLocationCoordinate2D]]
) -> [MKPolyline] {
    chunks.map { chunk in
        MKPolyline(coordinates: chunk, count: chunk.count)
    }
}

/// One family's simplified polylines for one `LineBuild`, and the colour
/// pair to draw them under (see `RailNetworkStore.DrawnLine.FamilyWindow`).
struct FamilyRunBuild {
    let colorHex: String
    let colorDarkHex: String
    var polylines: [MKPolyline]
}

/// Value geometry returned by the detached preparation task. Native MapKit
/// overlays are deliberately absent from this type.
struct PreparedFamilyRunBuild: Sendable {
    let colorHex: String
    let colorDarkHex: String
    var coordinateChunks: [[CLLocationCoordinate2D]]
}

/// One prepared line's value geometry. It becomes a ``LineBuild`` on the main
/// actor only after the request-generation guard accepts the worker result.
struct PreparedLineBuild: Sendable {
    let line: RailNetworkStore.DrawnLine
    let coordinateChunks: [[CLLocationCoordinate2D]]
    let familyCoordinateChunks: [String: PreparedFamilyRunBuild]
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
    /// distinct family group this chain landlords.
    let familyRuns: [(colorHex: String, colorDarkHex: String, runs: [[Coordinate]])]
}

/// Draw a continuous-stroke line (North America) as ONE polyline: the chain
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
/// Kept in WGS84 rather than projected: this is the geometry both
/// ``continuousChainPixels(of:mapPointsPerScreenPoint:)`` (screen pixels, for
/// drawing) and ``RailMapView/Coordinator/prepareStrokeReferences()`` (plain
/// coordinates, for `RailCore.StrokeRide` to match a ride's own segment
/// against) build from, and the WGS84 form is the one that does not change
/// with zoom — a rebuild at a different scale re-projects it but never
/// re-joins it.
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

/// The joined chain of a continuous line, in the pixel space of this frame —
/// ``joinedChainCoordinates(of:)`` projected through `mapPointsPerScreenPoint`.
func continuousChainPixels(
    of line: RailNetworkStore.DrawnLine, mapPointsPerScreenPoint: Double
) -> (points: [ContinuousStroke.Point], measures: [Double]) {
    let joined = joinedChainCoordinates(of: line)
    let points = joined.points.map { coordinate -> ContinuousStroke.Point in
        let point = MKMapPoint(coordinate.clLocation)
        return ContinuousStroke.Point(
            x: point.x / mapPointsPerScreenPoint, y: point.y / mapPointsPerScreenPoint)
    }
    return (points, joined.measures)
}

/// Projected chains, memoised across pans at the same drawing scale. Shared
/// canonical chains and station measures reuse the same projection.
final class ChainPixelCache {
    private var held: [String: (points: [ContinuousStroke.Point], measures: [Double])] = [:]
    private let mapPointsPerScreenPoint: Double
    init(mapPointsPerScreenPoint: Double) { self.mapPointsPerScreenPoint = mapPointsPerScreenPoint }
    func retain(_ ids: Set<String>) {
        held = held.filter { ids.contains($0.key) }
    }
    func chain(of line: RailNetworkStore.DrawnLine) -> (points: [ContinuousStroke.Point], measures: [Double]) {
        if let cached = held[line.id] { return cached }
        let built = continuousChainPixels(of: line, mapPointsPerScreenPoint: mapPointsPerScreenPoint)
        held[line.id] = built
        return built
    }
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
    neighbour: (String) -> RailNetworkStore.DrawnLine?, chains: ChainPixelCache
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
    chains: ChainPixelCache,
    mapPointsPerScreenPoint: Double, scale: CGFloat,
    laneScale: Double = 1
) -> ContinuousStrokeBuild {
    // `Stroke` has no public initializer of its own (`ContinuousStroke.swift`
    // is not this file's to extend), so an empty one is built the same way
    // `buildStroke` builds one for fewer than two points itself.
    let emptyStroke = ContinuousStroke.buildStroke(
        [], options: .init(rows: [], totalMetres: 0, laneGapPx: 0, minRampPx: 0, cornerRadiusPx: 0, anchors: []))
    guard mapPointsPerScreenPoint > 0 else {
        return ContinuousStrokeBuild(
            runs: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [], familyRuns: [])
    }
    let chain = chains.chain(of: line)
    let pixels = chain.points
    guard pixels.count >= 2 else {
        return ContinuousStrokeBuild(
            runs: [], anchors: [:], stroke: emptyStroke, sourceMeasures: [], withheldRuns: [], familyRuns: [])
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
            points: canonChain.points, measures: canonChain.measures)
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
            joinStart: continuousJoin(
                of: line, at: false, neighbour: canonical, chains: chains),
            joinEnd: continuousJoin(
                of: line, at: true, neighbour: canonical, chains: chains),
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
    var familyRuns: [(colorHex: String, colorDarkHex: String, runs: [[Coordinate]])] = []
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
        // its own entry in `familyRuns`, in the shared family's colour.
        // Windows are reviewed non-overlapping and sorted (the data
        // contract `familyWindowsByRegion` is built to). The boundary walk
        // itself is `ContinuousStroke.familyPartition` — the production
        // function `port-fixtures/family-windows.json` and
        // `FamilyWindowParityTests` both pin, so this file no longer hand-
        // mirrors it.
        var familyByGroup: [String: (colorHex: String, colorDarkHex: String, runs: [[Coordinate]])] = [:]
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
            // contains it — recovered here for its colour, which
            // `familyPartition` itself does not carry.
            guard
                let source = landlordWindows.first(where: {
                    $0.groupID == piece.groupID && $0.from <= piece.from && piece.to <= $0.to
                }),
                let run = sliceRun(piece.from, piece.to)
            else { continue }
            familyByGroup[
                piece.groupID, default: (source.colorHex, source.colorDarkHex, [])
            ].runs.append(run)
        }
        familyRuns = Array(familyByGroup.values)
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
        withheldRuns: withheldRuns, familyRuns: familyRuns)
}

/// Offset one display fragment in projected map space. The canonical package
/// geometry stays untouched; only the MKPolyline submitted for this frame is
/// shifted, by the same point token the Web renderer applies with line-offset.
func parallelLaneCoordinates(
    _ coordinates: [CLLocationCoordinate2D], lane: Double,
    mapPointsPerScreenPoint: Double, scale: CGFloat
) -> [CLLocationCoordinate2D] {
    guard lane != 0, coordinates.count >= 2 else { return coordinates }
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
        anchors: [0, pixels.count - 1], enforceMinimumCornerRadius: true))
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
        mapScale: Double, scale: CGFloat, laneScale: Double
    ) throws -> PreparedGeometry {
        let interval = RailSignpost.map.begin("map.geometry.prepare")
        defer { RailSignpost.map.end("map.geometry.prepare", interval) }
        let chains = ChainPixelCache(mapPointsPerScreenPoint: mapScale)
        var result = PreparedGeometry()
        for line in strokes {
            try Task.checkCancellation()
            result.strokes[line.id] = continuousStrokeBuild(
                for: line, anchors: anchors[line.id] ?? [], canonical: { allLines[$0] },
                chains: chains, mapPointsPerScreenPoint: mapScale, scale: scale,
                laneScale: laneScale)
        }
        for line in lines {
            try Task.checkCancellation()
            let stroke = result.strokes[line.id] ?? cachedStrokes[line.id]
            let runs = stroke?.runs ?? line.intervals
            let latitude = MKMapPoint(x: line.mapRect.midX, y: line.mapRect.midY).coordinate.latitude
            let epsilon = line.continuous ? 0 : MKMetersPerMapPointAtLatitude(latitude)
                * mapScale * RailStyle.simplifyTolerance
            func coordinateChunks(
                _ runs: [[Coordinate]]
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
                        coordinates, lane: line.lane, mapPointsPerScreenPoint: mapScale, scale: scale)
                    result.append(contentsOf: mapCoordinateChunks(points))
                }
                return result
            }
            var families: [String: PreparedFamilyRunBuild] = [:]
            for family in stroke?.familyRuns ?? [] {
                families[family.colorHex] = PreparedFamilyRunBuild(
                    colorHex: family.colorHex, colorDarkHex: family.colorDarkHex,
                    coordinateChunks: try coordinateChunks(family.runs))
            }
            result.lines[line.id] = PreparedLineBuild(
                line: line, coordinateChunks: try coordinateChunks(runs),
                familyCoordinateChunks: families)
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
                    polylines: mapPolylineChunks(family.coordinateChunks))
            }
            result.lines[id] = LineBuild(
                line: prepared.line,
                polylines: mapPolylineChunks(prepared.coordinateChunks),
                familyPolylines: families)
        }
        return result
    }
}
