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
    /// rect and viewport metadata for diagnostics and basemap veil placement.
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

    init(styles: MapOverlayStyles) {
        self.styles = styles
    }

    func reconciliation(on mapView: MKMapView) -> MapOverlayReconciliation {
        MapOverlayReconciliation(overlays: mapView.overlays(in: .aboveLabels))
    }

    func networkOverlays(
        byColor: [String: [MKPolyline]],
        withheldByColor: [String: [MKPolyline]],
        colors: [String: UIColor],
        dark: Bool,
        reconciliation: MapOverlayReconciliation
    ) -> [MKMultiPolyline] {
        var overlays: [MKMultiPolyline] = []
        for (key, polylines) in byColor {
            let styleKey = "network|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: colors[key] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.networkOpacity
            )
            overlays.append(multi)
        }
        for (key, polylines) in withheldByColor {
            let styleKey = "network-withheld|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: colors[key] ?? .systemGray,
                widthToken: RailStyle.railWidth,
                alpha: RailStyle.withheldOpacity
            )
            overlays.append(multi)
        }
        for (key, polylines) in withheldByColor {
            let styleKey = "network-withheld-casing|\(key)"
            let multi = reconciliation.multiPolyline(polylines, key: styleKey)
            styles[styleKey] = .init(
                color: MapLabelStyle.halo(dark: dark),
                widthToken: RailStyle.railWidth,
                alpha: 1,
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
        on mapView: MKMapView
    ) {
        let oldOverlays = reconciliation.oldOverlays
        let desiredIDs = Set(desiredOverlays.map { ObjectIdentifier($0) })
        let oldIDs = Set(oldOverlays.map { ObjectIdentifier($0) })
        let removed = oldOverlays.filter { !desiredIDs.contains(ObjectIdentifier($0)) }
        for overlay in removed {
            guard let key = overlay.title ?? nil else { continue }
            styles.forgetRenderer(forKey: key)
            if !desiredOverlays.contains(where: { ($0.title ?? nil) == key }) {
                styles.forgetStyle(forKey: key)
            }
        }
        mapView.removeOverlays(removed)
        mapView.addOverlays(
            desiredOverlays.filter { !oldIDs.contains(ObjectIdentifier($0)) },
            level: .aboveLabels
        )

        // Selection changes stacking without changing geometry.
        var installed = mapView.overlays(in: .aboveLabels)
        for (position, overlay) in desiredOverlays.enumerated() {
            guard installed[position] !== overlay,
                  let other = installed.firstIndex(where: { $0 === overlay })
            else { continue }
            mapView.exchangeOverlay(installed[position], with: installed[other])
            installed.swapAt(position, other)
        }
        styles.rescale(to: scale)
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
