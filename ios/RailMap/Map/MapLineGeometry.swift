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
            // Thinned like the prepared chunks, so the drawn count stays within
            // the budget `drawnVertexCount` weighed.
            let slice = ContinuousStroke.slice(
                points: stroke.stroke.points, measures: stroke.stroke.measures,
                from: range.from, to: range.to)
            let coordinates = ScreenPolylineThinning.thinned(
                slice, x: slice.map(\.x), y: slice.map(\.y)
            ).map {
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

/// One complete continuous stroke at a drawing scale: its colour runs, platform positions and the
/// stroke a recorded ride can slice. The geometry is `RailCore.StrokeBake.Build`; this wrapper
/// only adds the MapKit view of the anchors, so the consumers in the map code read what they
/// always read.
///
/// `stroke` is what a ride's own `StrokeRef` is sliced out of
/// (`ContinuousStroke.slice(points:measures:from:to:)`) — clipping to the build rect is right for
/// what the network OVERLAY draws, but a ride can be selected, played back or tapped from off
/// screen, so the geometry it slices has to be the whole chain, not merely the runs on screen
/// this frame.
struct ContinuousStrokeBuild: Sendable {
    let core: StrokeBake.Build
    /// Where the stroke put each requested station anchor, by chain vertex index.
    let anchors: [Int: CLLocationCoordinate2D]

    init(_ core: StrokeBake.Build) {
        self.core = core
        self.anchors = core.anchors.mapValues(\.clLocation)
    }

    var runs: [[Coordinate]] { core.runs }
    var stroke: ContinuousStroke.Stroke { core.stroke }
    var sourceMeasures: [Double] { core.sourceMeasures }
    /// Withheld spans, sliced out of `stroke` by metre measure, each with the colour key it draws
    /// under: ordinarily the line's own, but a span inside a landlord family window carries that
    /// family's colour instead. Unclipped, like `stroke` itself.
    var withheldRuns: [(colorHex: String, colorDarkHex: String, coordinates: [Coordinate])] {
        core.withheldRuns.map { (colorHex: $0.colorHex, colorDarkHex: $0.colorDarkHex, coordinates: $0.coordinates) }
    }
    /// Landlord family windows, sliced out of `stroke` by metre measure.
    var emittedFamilyWindows: [ContinuousStroke.WindowSpan] { core.emittedFamilyWindows }
}

extension JoinedChainKey {
    init(_ line: RailNetworkStore.DrawnLine) { self.init(line.strokeInput) }
}

extension JoinedChainCache {
    func chain(of line: RailNetworkStore.DrawnLine) -> JoinedChain { chain(of: line.strokeInput) }
}

/// MapKit-typed face of `StrokeBake.parallelLaneCoordinates`, for the ride and trip callers that
/// hold `CLLocationCoordinate2D`s.
func parallelLaneCoordinates(
    _ coordinates: [CLLocationCoordinate2D], lane: Double,
    mapPointsPerScreenPoint: Double, scale: CGFloat, alreadyCurved: Bool = false
) -> [CLLocationCoordinate2D] {
    guard coordinates.count >= 2, mapPointsPerScreenPoint > 0, !alreadyCurved || lane != 0 else { return coordinates }
    return StrokeBake.parallelLaneCoordinates(
        coordinates.map { Coordinate(lon: $0.longitude, lat: $0.latitude) }, lane: lane,
        mapPointsPerPoint: mapPointsPerScreenPoint, scale: Double(scale), alreadyCurved: alreadyCurved
    ).map(\.clLocation)
}

/// The worker owns projection caches; results contain immutable geometry only.
/// No view, renderer, annotation, or coordinator is accessed here. The geometry itself is
/// `RailCore.StrokeBake` (`strokeBuild`, `prepareLines`); what stays here is the display-era decision (which parts draw,
/// and solid or historical) and the conversion to the types the mounted-geometry cache holds.
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

    /// Fewest summed stroke vertices worth a worker of their own.
    static let minimumStrokeWeightPerPart = 4_000

    static func prepare(
        lines: [RailNetworkStore.DrawnLine], strokes: [RailNetworkStore.DrawnLine],
        allLines: [String: RailNetworkStore.DrawnLine], anchors: [String: [Int]],
        cachedStrokes: [String: ContinuousStrokeBuild],
        junctionIndex: StrokeJunctionIndex, chainPixels: ChainPixelCache,
        frameKey: String, datumToken: String,
        mapScale: Double, scale: CGFloat, laneScale: Double,
        era: DisplayNetworkEra = .current,
        rideDate: String? = nil,
        todayByRegion: [String: String] = [:],
        prebuild: Bool = false
    ) async throws -> PreparedGeometry {
        // An idle prebuild is not the foreground's work: it reports under its
        // own name so `map.geometry.prepare` counts only what a rebuild waits on.
        let intervalName: StaticString = prebuild ? "map.geometry.prebuild" : "map.geometry.prepare"
        let interval = RailSignpost.map.begin(intervalName)
        defer { RailSignpost.map.end(intervalName, interval) }
        let frame = StrokeBake.Frame(
            mapPointsPerPoint: mapScale, scale: Double(scale), laneScale: laneScale,
            key: frameKey, datumToken: datumToken)
        var drawn = allLines
        for line in lines where drawn[line.id] == nil { drawn[line.id] = line }
        // Draw filter only. A hidden continuous chain still builds its stroke for rides, and
        // simply contributes no network ink.
        func partStyle(_ input: StrokeLineInput, _ index: Int) -> StrokeBake.PartStyle {
            guard let line = drawn[input.id] else { return .solid }
            let today = todayByRegion[line.region.rawValue] ?? ""
            let span: DisplayTemporalDecoration?
            if line.continuous {
                span = line.partSpans.first ?? nil
            } else {
                span = line.partSpans.isEmpty
                    ? nil : (line.partSpans.indices.contains(index) ? line.partSpans[index] : nil)
            }
            guard era.shows(span, today: today, rideDate: rideDate) else { return .hidden }
            return era.strokeStyle(for: span, today: today, rideDate: rideDate) == .historical
                ? .historical : .solid
        }
        let pass = StrokeBake.Pass(
            allLines: allLines.mapValues(\.strokeInput), anchors: anchors,
            junctionIndex: junctionIndex, chainPixels: chainPixels, frame: frame)
        // Strokes are independent: each reads only its own line, `allLines` and the
        // two lock-guarded caches, never the result. Build them in parts weighted by
        // vertex count (same width rule as `RideStrokeBuilder.build`) and merge.
        let strokeInputs = strokes.map(\.strokeInput)
        var builtStrokes: [String: StrokeBake.Build] = [:]
        do {
            let strokeInterval = RailSignpost.map.begin("map.geometry.prepare.strokes")
            defer { RailSignpost.map.end("map.geometry.prepare.strokes", strokeInterval) }
            let maxParts = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 1))
            let strokeParts = RideBuildPartition.partition(
                weights: strokes.map { $0.intervals.reduce(0) { $0 + $1.count } },
                maxParts: maxParts, minimumWeightPerPart: minimumStrokeWeightPerPart)
            let builtParts = try await RideBuildPartition.buildParts(strokeParts) { index in
                try StrokeBake.strokeBuild(for: strokeInputs[index], in: pass)
            }
            for (index, build) in builtParts { builtStrokes[strokeInputs[index].id] = build }
        }
        let linesInterval = RailSignpost.map.begin("map.geometry.prepare.lines")
        defer { RailSignpost.map.end("map.geometry.prepare.lines", linesInterval) }
        // Network lines are thinned to `ScreenPolylineThinning.stepPx` before they are chunked
        // (so before `NetworkLOD.fitToBudget` counts them); ride strokes never pass through here.
        let prepared = try StrokeBake.prepareLines(
            lines: lines.map(\.strokeInput), builtStrokes: builtStrokes,
            cachedStrokes: cachedStrokes.mapValues(\.core), in: pass,
            thinStepPx: ScreenPolylineThinning.stepPx, partStyle: partStyle)
        func locations(_ chunks: [[Coordinate]]) -> [[CLLocationCoordinate2D]] {
            chunks.map { $0.map(\.clLocation) }
        }
        func family(_ run: StrokeBake.FamilyRun) -> PreparedFamilyRunBuild {
            PreparedFamilyRunBuild(
                colorHex: run.colorHex, colorDarkHex: run.colorDarkHex,
                coordinateChunks: locations(run.coordinateChunks), chunkWindows: run.chunkWindows)
        }
        var result = PreparedGeometry()
        result.strokes = prepared.strokes.mapValues(ContinuousStrokeBuild.init)
        for line in lines {
            guard let geometry = prepared.lines[line.id] else { continue }
            result.lines[line.id] = PreparedLineBuild(
                line: line, coordinateChunks: locations(geometry.coordinateChunks),
                historicalCoordinateChunks: locations(geometry.historicalCoordinateChunks),
                familyCoordinateChunks: geometry.familyCoordinateChunks.mapValues(family),
                familyFallbacks: geometry.familyFallbacks.map {
                    PreparedFamilyFallbackRunBuild(window: $0.window, family: family($0.family))
                },
                fallbackSplitReserve: geometry.fallbackSplitReserve)
        }
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
