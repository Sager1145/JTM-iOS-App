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
    private(set) var laneZoom: Double?
    private(set) var laneLODBucket: Int?
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
            builtLaneZoom: laneZoom,
            builtLaneLODBucket: laneLODBucket,
            visibleRectIsContained: builtRect.contains(visibleRect)
        ).shouldRebuild
    }

    mutating func commit(
        zoom: Double,
        visibilityBucket: Int,
        viewportSize: CGSize,
        builtRect: MKMapRect
    ) {
        zoomBucket = Int(floor(zoom))
        self.visibilityBucket = visibilityBucket
        self.viewportSize = viewportSize
        laneZoom = zoom
        self.builtRect = builtRect
    }

    /// Invalidates every zoom-sensitive decision while retaining the padded
    /// rect and viewport metadata for diagnostics.
    mutating func invalidateGeometry() {
        zoomBucket = nil
        laneZoom = nil
    }

    /// Used when only a newly prepared route-to-stroke mapping invalidates the
    /// installed result. The existing lane scale is still the previous bucket.
    mutating func invalidateZoomBucket() {
        zoomBucket = nil
    }

    func previewLaneLOD(at zoom: Double) -> (bucket: Int, scale: Double) {
        LaneLOD.resolve(zoom: zoom, previousBucket: laneLODBucket)
    }

    mutating func resolveLaneLOD(at zoom: Double) -> (bucket: Int, scale: Double) {
        let resolved = previewLaneLOD(at: zoom)
        laneLODBucket = resolved.bucket
        return resolved
    }
}

/// Zoom-dependent network geometry and ride-overlay caches.
///
/// The coordinator decides what should be drawn. This object owns how long a
/// prepared geometry value remains valid and clears the complete cache family
/// whenever its shared projection key changes.
@MainActor
final class MapNetworkGeometryCache {
    typealias BuiltStroke = (
        stroke: ContinuousStroke.Stroke,
        mapPointsPerScreenPoint: Double
    )

    private var frameKey = ""
    private var strokeBuilds: [String: ContinuousStrokeBuild] = [:]
    private var lineBuilds: [String: LineBuild] = [:]
    private var ridePolylines: [String: MKPolyline] = [:]
    private var frameStrokes: [String: BuiltStroke] = [:]

    func beginFrame(key: String) {
        if frameKey != key {
            frameKey = key
            strokeBuilds.removeAll(keepingCapacity: true)
            lineBuilds.removeAll(keepingCapacity: true)
            ridePolylines.removeAll(keepingCapacity: true)
        }
    }

    func resetFrameStrokes() {
        frameStrokes.removeAll(keepingCapacity: true)
    }

    func clearRidePolylines() {
        ridePolylines.removeAll(keepingCapacity: true)
    }

    static func ridePolylineKey(
        rideID: String, geometryDigest: Int, segmentIndex: Int, partIndex: Int,
        usesStroke: Bool
    ) -> String {
        "\(rideID)|\(geometryDigest)|\(segmentIndex).\(partIndex)|\(usesStroke)"
    }

    func retainRidePolylines(withKeys keys: Set<String>) {
        ridePolylines = ridePolylines.filter { keys.contains($0.key) }
    }

    func retainLineBuilds(withIDs ids: Set<String>) {
        strokeBuilds = strokeBuilds.filter { ids.contains($0.key) }
        lineBuilds = lineBuilds.filter { ids.contains($0.key) }
        clearRidePolylines()
    }

    var preparedStrokes: [String: ContinuousStrokeBuild] { strokeBuilds }

    func hasStrokeBuild(for id: String) -> Bool { strokeBuilds[id] != nil }
    func hasLineBuild(for id: String) -> Bool { lineBuilds[id] != nil }

    func storePrepared(_ result: MapLineGeometry.Prepared, key: String) -> Bool {
        guard key == frameKey else { return false }
        strokeBuilds.merge(result.strokes) { _, new in new }
        lineBuilds.merge(result.lines) { _, new in new }
        return true
    }

    func strokeBuild(for id: String) -> ContinuousStrokeBuild? { strokeBuilds[id] }

    func lineBuild(for id: String) -> LineBuild? {
        lineBuilds[id]
    }

    func store(_ build: LineBuild, for id: String) {
        lineBuilds[id] = build
    }

    func storeStroke(_ value: BuiltStroke, for id: String) {
        frameStrokes[id] = value
    }

    func containsStroke(for id: String) -> Bool {
        frameStrokes[id] != nil
    }

    func stroke(for id: String) -> BuiltStroke? {
        frameStrokes[id]
    }

    func ridePolyline(for key: String) -> MKPolyline? {
        ridePolylines[key]
    }

    func storeRidePolyline(_ polyline: MKPolyline, for key: String) {
        ridePolylines[key] = polyline
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

    init(styles: MapOverlayStyles) {
        self.styles = styles
    }

    func reconciliation(on mapView: MKMapView) -> MapOverlayReconciliation {
        let retiringIDs = Set(retiring.values.map { ObjectIdentifier($0.overlay) })
        return MapOverlayReconciliation(overlays: mapView.overlays(in: .aboveLabels).filter {
            !retiringIDs.contains(ObjectIdentifier($0))
        })
    }

    func removeRetiring(on mapView: MKMapView) {
        let overlays = retiring.values.map(\.overlay)
        styles.forget(overlays)
        mapView.removeOverlays(overlays)
        retiring.removeAll()
    }

    func networkOverlays(
        byColor: [String: [MKPolyline]],
        historicalByColor: [String: [MKPolyline]],
        withheldByColor: [String: [MKPolyline]],
        colors: [String: UIColor],
        dark: Bool,
        alphaScale: CGFloat = 1,
        reconciliation: MapOverlayReconciliation
    ) -> [MKMultiPolyline] {
        var overlays: [MKMultiPolyline] = []
        // Preserve the same stack across rebuilds and process launches, including
        // shared track geometry whose visible color depends on overlay order.
        for key in byColor.keys.sorted() {
            let polylines = byColor[key]!
            let styleKey = "network|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: colors[key] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.networkOpacity * alphaScale
            )
            overlays.append(multi)
        }
        for key in historicalByColor.keys.sorted() {
            let polylines = historicalByColor[key]!
            let styleKey = "network-hist|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: colors[key] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.networkOpacity * alphaScale,
                historical: true
            )
            overlays.append(multi)
        }
        for key in withheldByColor.keys.sorted() {
            let polylines = withheldByColor[key]!
            let styleKey = "network-withheld|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: colors[key] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.withheldOpacity * alphaScale
            )
            overlays.append(multi)
        }
        for key in withheldByColor.keys.sorted() {
            let polylines = withheldByColor[key]!
            let styleKey = "network-withheld-casing|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
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
        for overlay in removed {
            guard let key = overlay.title ?? nil else {
                immediateRemovals.append(overlay)
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
                      !oldKeys.contains(key) else { continue }
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
