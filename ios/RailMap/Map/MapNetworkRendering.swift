import MapKit
import RailCore
import RailPresentation
import UIKit

/// Camera-dependent state for the currently installed network geometry.
///
/// This is the boundary between cheap camera callbacks and an expensive map
/// rebuild. It owns the committed snapshot and is the only app-side caller
/// that translates MapKit values into ``MapRebuildPolicy`` inputs.
@MainActor
struct MapNetworkBuildState {
    private(set) var zoomBucket: Int?
    private(set) var visibilityBucket: Int?
    private(set) var viewportSize: CGSize?
    private(set) var geometryLevel: Int?
    private(set) var builtRect: MKMapRect = .null

    func shouldRebuild(
        zoom: Double,
        visibilityBucket: Int,
        viewportSize: CGSize,
        hasLanedLines: Bool,
        visibleRect: MKMapRect
    ) -> Bool {
        MapRebuildPolicy(
            zoom: zoom,
            visibilityBucket: visibilityBucket,
            viewportWidth: Double(viewportSize.width),
            viewportHeight: Double(viewportSize.height),
            builtZoomBucket: zoomBucket,
            builtVisibilityBucket: self.visibilityBucket,
            builtViewportWidth: self.viewportSize.map { Double($0.width) },
            builtViewportHeight: self.viewportSize.map { Double($0.height) },
            hasLanedLines: hasLanedLines,
            builtGeometryLevel: geometryLevel,
            visibleRectIsContained: builtRect.contains(visibleRect)
        ).shouldRebuild
    }

    mutating func commit(
        zoom: Double,
        visibilityBucket: Int,
        viewportSize: CGSize,
        geometryLevel: Int,
        builtRect: MKMapRect
    ) {
        zoomBucket = Int(floor(zoom))
        self.visibilityBucket = visibilityBucket
        self.viewportSize = viewportSize
        self.geometryLevel = geometryLevel
        self.builtRect = builtRect
    }

    /// Invalidates every zoom-sensitive decision while retaining the padded
    /// rect and viewport metadata for diagnostics.
    mutating func invalidateGeometry() {
        zoomBucket = nil
        geometryLevel = nil
    }

    /// Used when only a newly prepared route-to-stroke mapping invalidates the
    /// installed result. The existing lane scale is still the previous bucket.
    mutating func invalidateZoomBucket() {
        zoomBucket = nil
    }
}

/// Zoom-dependent network geometry and ride-overlay caches.
///
/// The coordinator decides what should be drawn. Prepared strokes, line builds
/// and ride polylines are kept for up to three stroke-bucket frames and reused
/// when the camera returns to a recent bucket. Accessors read and write the
/// current frame. `retainLineBuilds` and `retainRidePolylines` apply to every
/// cached frame, so invalidated content cannot come back from an older entry.
/// A trip polyline is keyed by ``RideLineCacheKey``, which carries the rail
/// line's id and its stroke generation: a line rebuilt in one frame only
/// strands the polylines made from its old build, never another line's.
/// `frameStrokes` is the geometry
/// installed for the camera frame in progress and is not stored per entry.
///
/// `joinedChains` is the display-datum join, keyed by content id and chain id,
/// and is not per frame. `chainPixels` projects that join for one frame, lane
/// LOD and datum token.
@MainActor
final class MapNetworkGeometryCache {
    typealias BuiltStroke = (
        stroke: ContinuousStroke.Stroke,
        mapPointsPerScreenPoint: Double
    )

    private struct FrameEntry {
        var strokeBuilds: [String: ContinuousStrokeBuild] = [:]
        var lineBuilds: [String: LineBuild] = [:]
        var ridePolylines: [RideLineCacheKey: MKPolyline] = [:]
        /// Identity of the stroke build last stored per id; moves whenever
        /// ``storePrepared(_:key:)`` replaces a build.
        var strokeGenerations: [String: Int] = [:]
        var withheldPolylines: [String: WithheldPolylineEntry] = [:]
        var familyFallbacks: [String: FamilyFallbackEntry] = [:]
        /// Estimated resident bytes, see ``GeometryFrameBytes``. Kept in step
        /// by the cache: recomputed when content is replaced or filtered,
        /// added to when a polyline is stored.
        var bytes = 0

        mutating func recomputeBytes() {
            var polylineVertices = 0
            for build in lineBuilds.values { polylineVertices += build.drawnVertexCount }
            for polyline in ridePolylines.values { polylineVertices += polyline.pointCount }
            for entry in withheldPolylines.values { polylineVertices += entry.polyline.pointCount }
            for entry in familyFallbacks.values {
                for build in entry.builds {
                    for polyline in build.polylines { polylineVertices += polyline.pointCount }
                }
            }
            var strokeVertices = 0
            for build in strokeBuilds.values { strokeVertices += build.stroke.points.count }
            bytes = GeometryFrameBytes.estimate(
                polylineVertices: polylineVertices, strokeVertices: strokeVertices)
        }
    }
    private struct WithheldPolylineEntry {
        let lineID: String
        let count: Int
        let first: Coordinate
        let last: Coordinate
        let polyline: MKPolyline
    }
    private struct FamilyFallbackEntry {
        let lineID: String
        let builds: [FamilyRunBuild]
    }

    /// Bytes the unpinned zoom/era frames may hold: 12 MB compact, 24 MB otherwise.
    private static let frameByteCap = ResourceProfile.current.geometryFrameByteCap
    /// Frames kept besides the current one and the neighbour, whatever their
    /// estimated bytes: the estimate undercounts MapKit's own polyline storage.
    private static let maxUnpinnedFrames = ResourceProfile.current.geometryMaxUnpinnedFrames

    let joinedChains: JoinedChainCache
    let chainPixels: ChainPixelCache

    private var frameKey = ""
    private var entries: [String: FrameEntry] = [:]
    private var residency = GeometryFrameResidency(
        byteCap: MapNetworkGeometryCache.frameByteCap,
        maxUnpinnedFrames: MapNetworkGeometryCache.maxUnpinnedFrames)
    private var frameStrokes: [String: BuiltStroke] = [:]
    private var nextStrokeGeneration = 0

    init() {
        let joinedChains = JoinedChainCache()
        self.joinedChains = joinedChains
        self.chainPixels = ChainPixelCache(joinedChains: joinedChains)
    }

    /// Drop joined chains and their pixels whose content is no longer resident.
    /// Line-build retention stays on ``retainLineBuilds(withIDs:)``, which still
    /// requires matching anchors and junction dependencies.
    func retainDisplayChains(_ keys: Set<JoinedChainKey>) {
        joinedChains.retain(keys)
        chainPixels.retain(keys)
    }

    private var currentEntry: FrameEntry {
        entries[frameKey] ?? FrameEntry()
    }

    func beginFrame(key: String) {
        if entries[key] == nil {
            entries[key] = FrameEntry()
        }
        frameKey = key
        for evicted in residency.begin(key) { entries.removeValue(forKey: evicted) }
    }

    /// Whether resident frame geometry leaves room to prebuild a neighbour.
    var hasRoomToPrebuild: Bool { residency.hasRoomToPrebuild }

    /// Memory pressure: every frame but the current one is released.
    @discardableResult
    func dropNonCurrentFrames() -> Int {
        let dropped = residency.dropNonCurrent()
        for key in dropped { entries.removeValue(forKey: key) }
        return dropped.count
    }

    /// Reports `key`'s size to the residency rule, which may evict others.
    private func noteBytes(of key: String) {
        guard let bytes = entries[key]?.bytes else { return }
        for evicted in residency.setBytes(bytes, for: key) { entries.removeValue(forKey: evicted) }
    }

    private func recomputeBytes(of key: String) {
        entries[key]?.recomputeBytes()
        noteBytes(of: key)
    }

    func resetFrameStrokes() {
        frameStrokes.removeAll(keepingCapacity: true)
    }

    /// Keeps the polylines of the segments in `segments`, whichever line they
    /// were sliced from, except the line-sliced variants of `rideIDs` (a new
    /// trip-to-line match moved their span). A polyline made from a line's
    /// old build is not named here: it falls out through its key's
    /// generation, see ``dropStaleRidePolylines(in:)``.
    func retainRidePolylines(
        ofSegments segments: Set<RideLineCacheKey.SegmentIdentity>,
        droppingStrokeVariantsOf rideIDs: Set<String> = []
    ) {
        for key in Array(entries.keys) {
            if let kept = entries[key]?.ridePolylines.filter({ entry in
                segments.contains(entry.key.segmentIdentity)
                    && !(entry.key.stroke != nil && rideIDs.contains(entry.key.rideID))
            }) {
                entries[key]?.ridePolylines = kept
                recomputeBytes(of: key)
            }
        }
    }

    /// ``retainRidePolylines(ofSegments:droppingStrokeVariantsOf:)``
    /// restricted to the polylines of `rideIDs`; every other ride's polylines
    /// are left as they are.
    func retainRidePolylines(
        ofRides rideIDs: Set<String>, segments: Set<RideLineCacheKey.SegmentIdentity>
    ) {
        guard !rideIDs.isEmpty else { return }
        for key in Array(entries.keys) {
            if let kept = entries[key]?.ridePolylines.filter({ entry in
                !rideIDs.contains(entry.key.rideID) || segments.contains(entry.key.segmentIdentity)
            }) {
                entries[key]?.ridePolylines = kept
                recomputeBytes(of: key)
            }
        }
    }

    /// Frees the polylines whose line build was replaced or left. Correctness
    /// does not depend on this: such a key can never be asked for again,
    /// because the line's generation is part of it.
    private func dropStaleRidePolylines(in key: String) {
        guard let entry = entries[key], !entry.ridePolylines.isEmpty else { return }
        let generations = entry.strokeGenerations
        entries[key]?.ridePolylines = entry.ridePolylines.filter {
            $0.key.isCurrent(lineGenerations: generations)
        }
        recomputeBytes(of: key)
    }

    func retainLineBuilds(withIDs ids: Set<String>) {
        for key in Array(entries.keys) {
            if let kept = entries[key]?.strokeBuilds.filter({ ids.contains($0.key) }) {
                entries[key]?.strokeBuilds = kept
            }
            if let kept = entries[key]?.lineBuilds.filter({ ids.contains($0.key) }) {
                entries[key]?.lineBuilds = kept
            }
            if let kept = entries[key]?.familyFallbacks.filter({ ids.contains($0.value.lineID) }) {
                entries[key]?.familyFallbacks = kept
            }
            if let kept = entries[key]?.withheldPolylines.filter({ ids.contains($0.value.lineID) }) {
                entries[key]?.withheldPolylines = kept
            }
            if let kept = entries[key]?.strokeGenerations.filter({ ids.contains($0.key) }) {
                entries[key]?.strokeGenerations = kept
            }
            dropStaleRidePolylines(in: key)
            recomputeBytes(of: key)
        }
    }

    /// Creates the entry for `key` without making it the current frame and
    /// pins it as the one neighbour, so a neighbour level can be prepared
    /// while the installed level stays current. The current frame and this
    /// neighbour are never evicted by the byte cap.
    func ensureFrame(key: String) {
        if entries[key] == nil { entries[key] = FrameEntry() }
        guard key != frameKey else { return }
        for evicted in residency.pinNeighbour(key) { entries.removeValue(forKey: evicted) }
    }

    func hasStrokeBuild(for id: String, in key: String) -> Bool {
        entries[key]?.strokeBuilds[id] != nil
    }
    func hasLineBuild(for id: String, in key: String) -> Bool {
        entries[key]?.lineBuilds[id] != nil
    }
    func preparedStrokes(in key: String) -> [String: ContinuousStrokeBuild] {
        entries[key]?.strokeBuilds ?? [:]
    }

    /// Stores a prepared result in the entry for `key`, which must exist (the
    /// frame was begun or ensured and not evicted since). The current frame is
    /// not required: a neighbour level's result lands in its own entry.
    func storePrepared(_ result: MapLineGeometry.Prepared, key: String) -> Bool {
        guard entries[key] != nil else { return false }
        // Mutate in place: copying an entry out and back would copy its
        // dictionaries on every store.
        entries[key]?.strokeBuilds.merge(result.strokes) { _, new in new }
        for id in result.strokes.keys {
            nextStrokeGeneration += 1
            entries[key]?.strokeGenerations[id] = nextStrokeGeneration
            // A replaced stroke build invalidates the dashed runs cut from it.
            if let withheld = entries[key]?.withheldPolylines.filter({ $0.value.lineID != id }) {
                entries[key]?.withheldPolylines = withheld
            }
        }
        entries[key]?.lineBuilds.merge(result.lines) { _, new in new }
        if !result.strokes.isEmpty { dropStaleRidePolylines(in: key) } else { recomputeBytes(of: key) }
        return true
    }

    func strokeBuild(for id: String) -> ContinuousStrokeBuild? { currentEntry.strokeBuilds[id] }

    func lineBuild(for id: String) -> LineBuild? {
        currentEntry.lineBuilds[id]
    }

    func store(_ build: LineBuild, for id: String) {
        entries[frameKey, default: FrameEntry()].lineBuilds[id] = build
        addBytes(polylineVertices: build.drawnVertexCount, to: frameKey)
    }

    func familyFallbacks(for key: String) -> [FamilyRunBuild]? {
        currentEntry.familyFallbacks[key]?.builds
    }

    func storeFamilyFallbacks(_ builds: [FamilyRunBuild], for key: String, lineID: String) {
        entries[frameKey, default: FrameEntry()].familyFallbacks[key] = FamilyFallbackEntry(
            lineID: lineID, builds: builds)
        addBytes(polylineVertices: builds.reduce(0) { $0 + $1.polylines.reduce(0) { $0 + $1.pointCount } },
                 to: frameKey)
    }

    private func addBytes(polylineVertices: Int, to key: String) {
        guard entries[key] != nil else { return }
        guard polylineVertices != 0 else { return }
        let current = entries[key]?.bytes ?? 0
        entries[key]?.bytes = max(0, current + polylineVertices * GeometryFrameBytes.bytesPerPolylineVertex)
        noteBytes(of: key)
    }

    func storeStroke(_ value: BuiltStroke, for id: String) {
        frameStrokes[id] = value
    }

    /// Identity of the stroke resident for `id` this frame, or nil when none is.
    /// Equal values mean equal drawn pixels for the same frame key.
    func strokeGeneration(for id: String) -> Int? {
        guard frameStrokes[id] != nil else { return nil }
        return currentEntry.strokeGenerations[id] ?? 0
    }

    /// Identity of the stroke build stored for `id` in the current frame, the
    /// one a trip segment is sliced from. Unlike ``strokeGeneration(for:)`` it
    /// does not need the frame's strokes installed yet, so a rebuild can key a
    /// polyline before it installs them.
    func residentStrokeGeneration(for id: String) -> Int {
        currentEntry.strokeGenerations[id] ?? 0
    }

    /// The dashed polyline of one withheld run, identical across rebuilds of the
    /// same frame so overlay reconciliation can reuse its batch. The content
    /// guard (count, first and last vertex) catches a run that changed without
    /// its stroke build being replaced.
    func withheldPolyline(
        lineID: String, runIndex: Int, coordinates: [Coordinate]
    ) -> MKPolyline? {
        guard let first = coordinates.first, let last = coordinates.last else { return nil }
        let key = "\(lineID)|\(runIndex)"
        if let cached = currentEntry.withheldPolylines[key],
            cached.count == coordinates.count, cached.first == first, cached.last == last {
            return cached.polyline
        }
        let points = coordinates.map(\.clLocation)
        let polyline = MKPolyline(coordinates: points, count: points.count)
        entries[frameKey, default: FrameEntry()].withheldPolylines[key] = WithheldPolylineEntry(
            lineID: lineID, count: coordinates.count, first: first, last: last, polyline: polyline)
        addBytes(polylineVertices: polyline.pointCount, to: frameKey)
        return polyline
    }

    func containsStroke(for id: String) -> Bool {
        frameStrokes[id] != nil
    }

    func stroke(for id: String) -> BuiltStroke? {
        frameStrokes[id]
    }

    func ridePolyline(for key: RideLineCacheKey) -> MKPolyline? {
        currentEntry.ridePolylines[key]
    }

    func storeRidePolyline(_ polyline: MKPolyline, for key: RideLineCacheKey) {
        let replaced = entries[frameKey]?.ridePolylines[key]?.pointCount ?? 0
        entries[frameKey, default: FrameEntry()].ridePolylines[key] = polyline
        addBytes(polylineVertices: polyline.pointCount - replaced, to: frameKey)
    }

    /// Files a polyline built for `frameKey` without moving the current frame.
    /// A frame the cache has already evicted drops it.
    func storeRidePolyline(_ polyline: MKPolyline, for key: RideLineCacheKey, frameKey: String) {
        let replaced = entries[frameKey]?.ridePolylines[key]?.pointCount ?? 0
        entries[frameKey]?.ridePolylines[key] = polyline
        addBytes(polylineVertices: polyline.pointCount - replaced, to: frameKey)
    }
}

/// The installed overlay identities captured at the start of one rebuild.
/// Reusing an unchanged `MKMultiPolyline` keeps MapKit's renderer alive.
@MainActor
struct MapOverlayReconciliation {
    let oldOverlays: [MKOverlay]
    private let oldByKey: [String: MKMultiPolyline]

    init(overlays: [MKOverlay]) {
        oldOverlays = overlays
        oldByKey = Dictionary(overlays.compactMap { overlay -> (String, MKMultiPolyline)? in
            guard let multi = overlay as? MKMultiPolyline, let key = multi.title else { return nil }
            return (key, multi)
        }, uniquingKeysWith: { first, _ in first })
    }

    func multiPolyline(_ polylines: [MKPolyline], key: String) -> MKMultiPolyline {
        if let old = oldByKey[key], old.polylines.count == polylines.count,
           zip(old.polylines, polylines).allSatisfy({ $0 === $1 }) {
            return old
        }
        let multi = MKMultiPolyline(polylines)
        multi.title = key
        return multi
    }
}

/// Builds network overlay batches and reconciles the full overlay stack.
/// Geometry selection remains outside; this type owns MapKit installation,
/// identity reuse, style cleanup, ordering and final renderer rescaling.
@MainActor
final class MapOverlayInstaller {
    private let styles: MapOverlayStyles
    private struct RetiringBatch {
        let originalKey: String
        let overlay: MKMultiPolyline
    }
    private var retiring: [String: RetiringBatch] = [:]
    private var handoffs: [String: RetiringBatch] = [:]
    private var swap: OverlaySwapSequencer?
    private var swapLastTick: CFTimeInterval = 0
    private var swapTickScheduled = false

    init(styles: MapOverlayStyles) {
        self.styles = styles
    }

    func reconciliation(on mapView: MKMapView) -> MapOverlayReconciliation {
        let retiringIDs = Set(retiring.values.map { ObjectIdentifier($0.overlay) })
        let handoffIDs = Set(handoffs.values.map { ObjectIdentifier($0.overlay) })
        return MapOverlayReconciliation(overlays: mapView.overlays(in: .aboveLabels).filter {
            !retiringIDs.contains(ObjectIdentifier($0)) && !handoffIDs.contains(ObjectIdentifier($0))
        })
    }

    func removeRetiring(on mapView: MKMapView) {
        let overlays = retiring.values.map(\.overlay) + handoffs.values.map(\.overlay)
        styles.forget(overlays)
        mapView.removeOverlays(overlays)
        retiring.removeAll()
        handoffs.removeAll()
        swap = nil
    }

    /// Identity box so a polyline can be a ledger item (and stay alive in it).
    private struct PolylineItem: Hashable {
        let polyline: MKPolyline
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.polyline === rhs.polyline }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(polyline)) }
    }
    private var networkBatches = AddOnlyBatchLedger<PolylineItem>()
    private var historicalBatches = AddOnlyBatchLedger<PolylineItem>()
    private var withheldBatches = AddOnlyBatchLedger<PolylineItem>()
    private var batchEpoch: String?

    /// Network overlays are batched by colour group AND spatial tile, and a
    /// batch's polylines are fixed when it is created: area that loads later
    /// adds batches and never replaces one already on the map. `epoch` names
    /// the geometry the polylines belong to (the level's frame); a new epoch
    /// starts the batches afresh.
    func networkOverlays(
        byColor: [String: [MKPolyline]],
        historicalByColor: [String: [MKPolyline]],
        withheldByColor: [String: [MKPolyline]],
        colors: [String: UIColor],
        dark: Bool,
        alphaScale: CGFloat = 1,
        epoch: String,
        tileSize: Double,
        buildRect: MKMapRect,
        reconciliation: MapOverlayReconciliation
    ) -> [MKMultiPolyline] {
        let area = MapBuildArea.Rect(
            x: buildRect.origin.x, y: buildRect.origin.y,
            width: buildRect.size.width, height: buildRect.size.height)
        if batchEpoch != epoch {
            networkBatches.reset()
            historicalBatches.reset()
            withheldBatches.reset()
            batchEpoch = epoch
        }
        func entries(_ byGroup: [String: [MKPolyline]]) -> [AddOnlyBatchLedger<PolylineItem>.Entry] {
            byGroup.keys.sorted().flatMap { group in
                byGroup[group]!.map { polyline in
                    let rect = polyline.boundingMapRect
                    let bounds = MapBuildArea.Rect(
                        x: rect.origin.x, y: rect.origin.y,
                        width: rect.size.width, height: rect.size.height)
                    return AddOnlyBatchLedger<PolylineItem>.Entry(
                        item: PolylineItem(polyline: polyline), group: group,
                        tile: MapOverlayTiling.tile(of: bounds, tileSize: tileSize),
                        bounds: bounds)
                }
            }
        }
        networkBatches.update(entries(byColor), buildRect: area)
        historicalBatches.update(entries(historicalByColor), buildRect: area)
        withheldBatches.update(entries(withheldByColor), buildRect: area)

        var overlays: [MKMultiPolyline] = []
        // Preserve the same stack across rebuilds and process launches, including
        // shared track geometry whose visible color depends on overlay order.
        for batch in networkBatches.batches {
            let styleKey = "network|\(batch.key)"
            let multi = reconciliation.multiPolyline(batch.items.map(\.polyline), key: styleKey)
            styles[styleKey] = .init(
                color: colors[batch.group] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.networkOpacity * alphaScale
            )
            overlays.append(multi)
        }
        for batch in historicalBatches.batches {
            let styleKey = "network-hist|\(batch.key)"
            let multi = reconciliation.multiPolyline(batch.items.map(\.polyline), key: styleKey)
            styles[styleKey] = .init(
                color: colors[batch.group] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.networkOpacity * alphaScale,
                historical: true
            )
            overlays.append(multi)
        }
        for batch in withheldBatches.batches {
            let styleKey = "network-withheld|\(batch.key)"
            let multi = reconciliation.multiPolyline(batch.items.map(\.polyline), key: styleKey)
            styles[styleKey] = .init(
                color: colors[batch.group] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.withheldOpacity * alphaScale
            )
            overlays.append(multi)
        }
        for batch in withheldBatches.batches {
            let styleKey = "network-withheld-casing|\(batch.key)"
            let multi = reconciliation.multiPolyline(batch.items.map(\.polyline), key: styleKey)
            styles[styleKey] = .init(
                color: MapLabelStyle.halo(dark: dark),
                widthToken: RailStyle.railWidth,
                alpha: alphaScale,
                dashed: true
            )
            overlays.append(multi)
        }
        return overlays
    }

    func install(
        _ desiredOverlays: [MKOverlay],
        replacing reconciliation: MapOverlayReconciliation,
        scale: CGFloat,
        on mapView: MKMapView,
        detailTransitionDuration: TimeInterval? = nil,
        alphaTransitionDuration: TimeInterval? = nil
    ) {
        let oldOverlays = reconciliation.oldOverlays
        let desiredIDs = Set(desiredOverlays.map { ObjectIdentifier($0) })
        let oldIDs = Set(oldOverlays.map { ObjectIdentifier($0) })
        let removed = oldOverlays.filter { !desiredIDs.contains(ObjectIdentifier($0)) }
        let desiredKeys = Set(desiredOverlays.compactMap { $0.title ?? nil })
        let oldKeys = Set(oldOverlays.compactMap { $0.title ?? nil })
        var returningAlpha: [String: CGFloat] = [:]
        // A reversal uses the opacity already on screen and cancels the old
        // removal. Retiring batches never enter the next active reconciliation.
        for (key, batch) in retiring where desiredKeys.contains(batch.originalKey) {
            returningAlpha[batch.originalKey] = styles.presentedAlpha(forKey: key)
            mapView.removeOverlay(batch.overlay)
            styles.forget([batch.overlay])
            retiring.removeValue(forKey: key)
        }
        var immediateRemovals: [MKOverlay] = []
        // New network batches replacing old ones (a level, era, colour or batch
        // rebuild): every old network overlay stays mounted as one group until
        // the new ones drew, never crossfading against them, never vanishing
        // before them. Whether the old key survives does not matter.
        let newNetworkKeys = desiredKeys.subtracting(oldKeys).filter { $0.hasPrefix("network") }
        let replacesNetwork = !newNetworkKeys.isEmpty
            && removed.contains { ($0.title ?? nil)?.hasPrefix("network") == true }
        for overlay in removed {
            guard let key = overlay.title ?? nil else {
                immediateRemovals.append(overlay)
                continue
            }
            if replacesNetwork, key.hasPrefix("network"), !desiredKeys.contains(key),
               let multi = overlay as? MKMultiPolyline {
                let exitKey = "handoff|\(UUID().uuidString)"
                styles.rekey(from: key, to: exitKey)
                multi.title = exitKey
                handoffs[exitKey] = RetiringBatch(originalKey: key, overlay: multi)
                continue
            }
            if let duration = detailTransitionDuration, duration > 0,
               key.hasPrefix("network"), !desiredKeys.contains(key),
               let multi = overlay as? MKMultiPolyline {
                let exitKey = "retiring|\(UUID().uuidString)"
                styles.rekey(from: key, to: exitKey)
                multi.title = exitKey
                retiring[exitKey] = RetiringBatch(originalKey: key, overlay: multi)
                if var style = styles[exitKey] {
                    style.alpha = 0
                    styles[exitKey] = style
                }
                styles.animateOpacity(forKey: exitKey, duration: duration) { [weak self, weak mapView] in
                    guard let self, let batch = self.retiring.removeValue(forKey: exitKey) else { return }
                    mapView?.removeOverlay(batch.overlay)
                    self.styles.forget([batch.overlay])
                }
                continue
            }
            if alphaTransitionDuration != 0,
               (MapOverlayStyles.isRideCoreKey(key) || MapOverlayStyles.isRideCasingKey(key)
                || MapOverlayStyles.isRideBatchKey(key)
                || key.hasPrefix("network")),
               desiredKeys.contains(key), let multi = overlay as? MKMultiPolyline {
                let exitKey = "handoff|\(UUID().uuidString)"
                styles.rekey(from: key, to: exitKey)
                styles[key] = styles[exitKey]
                multi.title = exitKey
                handoffs[exitKey] = RetiringBatch(originalKey: key, overlay: multi)
                continue
            }
            immediateRemovals.append(overlay)
            styles.forgetRenderer(forKey: key)
            if !desiredKeys.contains(key) {
                styles.forgetStyle(forKey: key)
            }
        }
        mapView.removeOverlays(immediateRemovals)
        // Register before adding: MapKit may request the renderer immediately.
        if let duration = detailTransitionDuration {
            for overlay in desiredOverlays {
                guard let key = overlay.title ?? nil, key.hasPrefix("network"),
                      !oldKeys.contains(key), !replacesNetwork else { continue }
                styles.animateOpacity(forKey: key, duration: duration,
                    fromAlpha: returningAlpha[key] ?? 0)
            }
        }
        mapView.addOverlays(
            desiredOverlays.filter { !oldIDs.contains(ObjectIdentifier($0)) },
            level: .aboveLabels
        )

        // Exiting network details stay beneath the ride and selection layers.
        var stack = desiredOverlays
        let networkEnd = stack.lastIndex { ($0.title ?? nil)?.hasPrefix("network") == true }
            .map { $0 + 1 } ?? 0
        stack.insert(contentsOf: retiring.keys.sorted().compactMap { retiring[$0]?.overlay }, at: networkEnd)
        for key in handoffs.keys.sorted() {
            guard let batch = handoffs[key] else { continue }
            let position = stack.firstIndex { ($0.title ?? nil) == batch.originalKey } ?? networkEnd
            stack.insert(batch.overlay, at: position)
        }
        // Selection changes stacking without changing geometry.
        var installed = mapView.overlays(in: .aboveLabels)
        let mountedIDs = Set(installed.map(ObjectIdentifier.init))
        var orderedIDs: Set<ObjectIdentifier> = []
        let residentStack = stack.filter { overlay in
            let id = ObjectIdentifier(overlay)
            return mountedIDs.contains(id) && orderedIDs.insert(id).inserted
        }
        var positions = Dictionary(installed.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        }, uniquingKeysWith: { first, _ in first })
        // MapKit can ignore an add or already hold a requested identity. Order
        // only the unique mounted overlays, with contiguous resident positions.
        for (position, overlay) in zip(installed.indices, residentStack) {
            guard installed[position] !== overlay,
                  let other = positions[ObjectIdentifier(overlay)]
            else { continue }
            positions[ObjectIdentifier(installed[position])] = other
            positions[ObjectIdentifier(overlay)] = position
            mapView.exchangeOverlay(installed[position], with: installed[other])
            installed.swapAt(position, other)
        }
        styles.rescale(to: scale, alphaTransitionDuration: alphaTransitionDuration)
        beginSwap(on: mapView, newKeys: newNetworkKeys)
    }

    /// The old overlays of every replacement stay mounted as one group until
    /// ``OverlaySwapSequencer`` says the new ones drew, then all come off in
    /// the same run-loop turn: never neither set, never a partial mix.
    /// A later install joins the group and restarts its frame count; the
    /// group's old overlays are never removed one by one.
    private func beginSwap(on mapView: MKMapView, newKeys: Set<String>) {
        guard !handoffs.isEmpty else {
            swap = nil
            return
        }
        // Wait on the new network batches plus any kept key still handed off
        // (ride layers); a handed-off key that is gone is not waited for.
        let kept = handoffs.values.map(\.originalKey).filter { styles[$0] != nil }
        swap = OverlaySwapSequencer(newKeys: newKeys.union(kept))
        swapLastTick = CACurrentMediaTime()
        scheduleSwapTick(on: mapView)
    }

    private func scheduleSwapTick(on mapView: MKMapView) {
        guard !swapTickScheduled else { return }
        swapTickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self, weak mapView] in
            guard let self else { return }
            self.swapTickScheduled = false
            guard let mapView, var swap = self.swap else { return }
            for key in swap.undrawn where self.styles.hasDrawn(forKey: key) {
                swap.reportDrawn(key: key)
            }
            let now = CACurrentMediaTime()
            swap.elapse(now - self.swapLastTick)
            self.swapLastTick = now
            self.swap = swap
            switch swap.decision {
            case .holdOld:
                self.scheduleSwapTick(on: mapView)
            case .retireOld:
                let overlays = self.handoffs.values.map(\.overlay)
                self.styles.forget(overlays)
                mapView.removeOverlays(overlays)
                self.handoffs.removeAll()
                self.swap = nil
            }
        }
    }
}

#if DEBUG
/// Display-link delivery measures main-run-loop stalls independently of how
/// frequently MapKit emits camera changes during a synthetic or real pinch.
@MainActor
final class MapGestureFrameProbe {
    @MainActor private final class Target: NSObject {
        weak var probe: MapGestureFrameProbe?
        init(_ probe: MapGestureFrameProbe) { self.probe = probe }
        @objc func tick(_ link: CADisplayLink) {
            guard let probe else { link.invalidate(); return }
            probe.tick()
        }
    }

    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private(set) var frames = 0
    private(set) var maximumGapMilliseconds = 0.0

    func start() {
        guard link == nil else { return }
        // Registration is not a delivered frame. Compare actual callbacks
        // only; counting display-link startup latency invents a frame gap.
        lastTick = nil
        let link = CADisplayLink(target: Target(self), selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        guard link != nil else { return }
        link?.invalidate()
        link = nil
        lastTick = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let lastTick {
            maximumGapMilliseconds = max(maximumGapMilliseconds, (now - lastTick) * 1_000)
        }
        lastTick = now
        frames += 1
    }

}
#endif

/// Geometry projection for one geometry level (``GeometryZoomLevels``).
/// Screen-space geometry (lane offsets, jog tapers, fillets, decimation) is
/// built at the level's nominal zoom, so zooms near a level and returns to a
/// recent level reuse prepared geometry and overlay identities. Renderer
/// widths keep following the live zoom.
@MainActor
struct MapGeometryFrame {
    /// The geometry level.
    let bucket: Int
    let nominalZoom: Double
    let mapPointsPerScreenPoint: Double
    let scale: CGFloat
    let laneScale: Double
    let key: String

    init(level: Int, eraKey: String, on mapView: MKMapView) {
        let nominalZoom = GeometryZoomLevels.nominalZoom(level: level)
        let laneLOD = GeometryZoomLevels.laneLOD(level: level)
        self.bucket = level
        self.nominalZoom = nominalZoom
        self.laneScale = laneLOD.scale
        // Inverse of `MapProjection.zoomLevel`: world width / (256 × 2^zoom).
        self.mapPointsPerScreenPoint = MKMapSize.world.width / (256 * exp2(nominalZoom))
        self.scale = MapProjection.quantised(
            RailStyle.scale(atZoom: nominalZoom), on: mapView)
        // The quantised scale carries the display scale, so a window moved
        // to a different screen does not reuse geometry rounded for the other.
        self.key = "\(level)|\(self.scale)|\(laneLOD.bucket)|\(laneLOD.scale)|\(eraKey)"
    }
}
