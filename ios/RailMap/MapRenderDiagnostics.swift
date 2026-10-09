import MapKit
import RailCore

#if DEBUG
/// Owns debug measurement lifetime and accessibility publication. All counters
/// describe this mounted map; render/selection inputs arrive as value snapshots.
@MainActor
final class MapRenderDiagnostics {
    struct Snapshot {
        let showsNetwork: Bool
        let visibleLines: Int
        let networkOverlays: Int
        let threshold: Double
        let totalLines: Int
        let culledOffScreen: Int
        let totalOverlays: Int
        let rideDots: Int
        let rideLabels: Int
        let rides: Int
        let budgetDrops: Int
        let vertices: Int
        let zoom: Double
        let visibilityZoom: Double
        let backbones: Int
        let networkStations: Int
        let focusRevision: Int
        let focusBottom: CGFloat
        let buildMilliseconds: Int
        let rideOverlaysMilliseconds: Int
        let rideCacheMisses: Int
        let markersMilliseconds: Int
        let networkOverlaysMilliseconds: Int
        let teardownMilliseconds: Int
        let rideScanMilliseconds: Int
        let materializeMilliseconds: Int
        let annotationViews: Int
        let builtRect: MKMapRect
        let targetReadiness: String
        let selectedTrainID: String?
        let selectedDate: String
    }

    weak var status: UILabel?
    private let gestureFrameProbe = MapGestureFrameProbe()
    private var stressSubmittedSelection: String?
    private var stressSubmittedDate = Dates.allDates
    private var networkEnabledAt: ContinuousClock.Instant?
    private var firstNetworkRenderMilliseconds: Double?
    private var rebuildCount = 0
    private var rebuildsDuringGesture = 0
    private var labelPasses = 0
    private var gestureLabelPasses = 0
    private var labelPassMilliseconds = 0
    private var labelPassMaxMilliseconds = 0
    private var gestureLabelPassMaxMilliseconds = 0
    private var regionTickMaxMilliseconds = 0
    private var stackingMaxMilliseconds = 0
    private var lineCacheHits = 0
    private var annotationReuses = 0
    private var panCallbacks = 0
    private var lastPanCallback: ContinuousClock.Instant?
    private var maxPanCallbackGapMilliseconds = 0
    private var markerPhases = ""

    func networkVisibilityChanged(_ visible: Bool) {
        networkEnabledAt = visible ? .now : nil
        firstNetworkRenderMilliseconds = nil
    }

    func didRebuild(manipulating: Bool) {
        rebuildCount += 1
        if manipulating { rebuildsDuringGesture += 1 }
    }

    func didRunLabelPass(manipulating: Bool, milliseconds: Int) {
        labelPasses += 1
        labelPassMilliseconds = milliseconds
        labelPassMaxMilliseconds = max(labelPassMaxMilliseconds, milliseconds)
        if manipulating {
            gestureLabelPasses += 1
            gestureLabelPassMaxMilliseconds = max(
                gestureLabelPassMaxMilliseconds, milliseconds)
        }
    }

    func didRunRegionTick(milliseconds: Int) {
        regionTickMaxMilliseconds = max(regionTickMaxMilliseconds, milliseconds)
    }

    func didRestoreRideMarkerStacking(milliseconds: Int) {
        stackingMaxMilliseconds = max(stackingMaxMilliseconds, milliseconds)
    }

    func reusedLineGeometry() { lineCacheHits += 1 }
    func reusedAnnotations(_ count: Int) { annotationReuses += count }
    func didBuildMarkerPhases(_ value: String) { markerPhases = value }

    func submittedSelection(_ id: String?, date: String) {
        stressSubmittedSelection = id
        stressSubmittedDate = date
    }

    func cameraChanged(manipulating: Bool) {
        guard manipulating else {
            lastPanCallback = nil
            return
        }
        let now = ContinuousClock.now
        panCallbacks += 1
        if let lastPanCallback {
            maxPanCallbackGapMilliseconds = max(
                maxPanCallbackGapMilliseconds,
                (now - lastPanCallback).milliseconds)
        }
        lastPanCallback = now
    }

    func gestureBegan() {
        lastPanCallback = nil
        gestureFrameProbe.start()
    }
    func gestureEnded() { gestureFrameProbe.stop() }

    func tearDown() {
        gestureFrameProbe.stop()
        status = nil
    }

    /// Camera motion can retain covered geometry without entering rebuild.
    /// Refresh only live diagnostics; the last submitted geometry metrics stay intact.
    func updateLiveStatus(on mapView: MKMapView, camera: MKMapCamera, builtRect: MKMapRect) {
        guard let status = status else { return }
        let liveKeys: Set<String> = [
            "camera", "distance", "heading", "centerLat", "centerLon",
            "viewportWidth", "viewportHeight", "panCallbacks", "panMaxGapMs",
            "gestureFrames", "gestureMaxFrameGapMs", "covered", "labelPassMs",
            "labelPassMaxMs", "gestureLabelPassMaxMs", "regionTickMaxMs",
            "stackingMaxMs", "annotationViews",
        ]
        let fields = (status.text ?? "").split(separator: ";").filter { field in
            let key = field.prefix { $0 != ":" }
            return !liveKeys.contains(String(key))
        }
        status.text =
            fields.joined(separator: ";")
            + String(
                format: ";camera:%.2f;distance:%.1f;heading:%.1f",
                MapProjection.zoomLevel(of: mapView), camera.centerCoordinateDistance, camera.heading)
            + String(
                format: ";centerLat:%.6f;centerLon:%.6f",
                camera.centerCoordinate.latitude, camera.centerCoordinate.longitude)
            + String(
                format: ";viewportWidth:%.1f;viewportHeight:%.1f",
                mapView.bounds.width, mapView.bounds.height)
            + ";panCallbacks:\(panCallbacks);panMaxGapMs:\(maxPanCallbackGapMilliseconds)"
            + ";gestureFrames:\(gestureFrameProbe.frames);gestureMaxFrameGapMs:\(Int(gestureFrameProbe.maximumGapMilliseconds))"
            + ";covered:\(builtRect.contains(mapView.visibleMapRect) ? 1 : 0)"
            + ";labelPassMs:\(labelPassMilliseconds);labelPassMaxMs:\(labelPassMaxMilliseconds)"
            + ";gestureLabelPassMaxMs:\(gestureLabelPassMaxMilliseconds)"
            + ";regionTickMaxMs:\(regionTickMaxMilliseconds);stackingMaxMs:\(stackingMaxMilliseconds)"
            + ";annotationViews:\(mapView.annotations.count)"
    }

    func updateBasemapStatus(on mapView: MKMapView) {
        guard let status = status else { return }
        let fields = (status.text ?? "").split(separator: ";").filter {
            !$0.hasPrefix("basemapMuted:")
        }
        status.text =
            fields.joined(separator: ";")
            + ";basemapMuted:\((mapView.preferredConfiguration as? MKStandardMapConfiguration)?.emphasisStyle == .muted ? 1 : 0)"
    }

    func publish(_ snapshot: Snapshot, on mapView: MKMapView) {
        // Synchronous console output stays in DEBUG; release builds publish
        // RenderStats to the in-app panel through the coordinator's callback.
        // "off" distinguishes a hidden network from a LOD selection with no lines.
        let drawnLines = snapshot.showsNetwork ? "\(snapshot.visibleLines)" : "off"
        NSLog(
            "railmap: z=%.2f lod=%.2f thr=%.1f lines=%@/%d (culled %d) overlays=%d vertices=%d "
                + "stations=%d ridedots=%d ridelabels=%d %dms",
            snapshot.zoom, snapshot.visibilityZoom, snapshot.threshold, drawnLines, snapshot.totalLines,
            snapshot.culledOffScreen, snapshot.totalOverlays, snapshot.vertices, snapshot.networkStations,
            snapshot.rideDots, snapshot.rideLabels, snapshot.buildMilliseconds)
        let networkState =
            !snapshot.showsNetwork
            ? "off"
            : (snapshot.visibleLines == 0 || snapshot.networkOverlays == 0 ? "empty" : "rendered")
        // Measure inside the app: XCTest's map accessibility snapshot
        // can take longer than the render itself. Include region
        // loading, but freeze at the first submitted network frame.
        if networkState == "rendered", firstNetworkRenderMilliseconds == nil,
            let networkEnabledAt
        {
            firstNetworkRenderMilliseconds = Double(
                (ContinuousClock.now - networkEnabledAt).milliseconds)
        }
        status?.text =
            "network:\(networkState);lines:\(snapshot.visibleLines);overlays:\(snapshot.networkOverlays)"
            + ";rides:\(snapshot.rides)"
            + ";budgetDrops:\(snapshot.budgetDrops);vertices:\(snapshot.vertices)"
            + String(format: ";camera:%.2f;lod:%.2f", snapshot.zoom, snapshot.visibilityZoom)
            + ";backbones:\(snapshot.backbones)"
            + ";networkStations:\(snapshot.networkStations)"
            + String(format: ";distance:%.1f", mapView.camera.centerCoordinateDistance)
            + ";focusRevision:\(snapshot.focusRevision)"
            + String(format: ";focusBottom:%.1f", snapshot.focusBottom)
            + String(format: ";heading:%.1f", mapView.camera.heading)
            + String(
                format: ";centerLat:%.6f;centerLon:%.6f", mapView.centerCoordinate.latitude,
                mapView.centerCoordinate.longitude)
            + String(
                format: ";viewportWidth:%.1f;viewportHeight:%.1f", mapView.bounds.width,
                mapView.bounds.height)
            + String(format: ";firstNetworkMs:%.1f", firstNetworkRenderMilliseconds ?? -1)
            + ";rebuilds:\(rebuildCount);gestureBuilds:\(rebuildsDuringGesture)"
            + ";labelPasses:\(labelPasses);gestureLabelPasses:\(gestureLabelPasses)"
            + ";cacheHits:\(lineCacheHits);annotationReuses:\(annotationReuses)"
            + ";panCallbacks:\(panCallbacks);panMaxGapMs:\(maxPanCallbackGapMilliseconds)"
            + ";gestureFrames:\(gestureFrameProbe.frames);gestureMaxFrameGapMs:\(Int(gestureFrameProbe.maximumGapMilliseconds))"
            + ";buildMs:\(snapshot.buildMilliseconds);covered:\(snapshot.builtRect.contains(mapView.visibleMapRect) ? 1 : 0)"
        status?.text = (status?.text ?? "") + snapshot.targetReadiness
        stressSubmittedSelection = snapshot.selectedTrainID
        stressSubmittedDate = snapshot.selectedDate
        updateBasemapStatus(on: mapView)
        status?.text = (status?.text ?? "")
            + ";rideOverlaysMs:\(snapshot.rideOverlaysMilliseconds);rideCacheMisses:\(snapshot.rideCacheMisses)"
            + ";markersMs:\(snapshot.markersMilliseconds);networkOverlaysMs:\(snapshot.networkOverlaysMilliseconds)"
            + ";teardownMs:\(snapshot.teardownMilliseconds);rideScanMs:\(snapshot.rideScanMilliseconds)"
            + ";materializeMs:\(snapshot.materializeMilliseconds)"
            + ";labelPassMs:\(labelPassMilliseconds);labelPassMaxMs:\(labelPassMaxMilliseconds)"
            + ";gestureLabelPassMaxMs:\(gestureLabelPassMaxMilliseconds)"
            + ";regionTickMaxMs:\(regionTickMaxMilliseconds);stackingMaxMs:\(stackingMaxMilliseconds)"
            + ";annotationViews:\(snapshot.annotationViews)"
            + ";markerPhases:\(markerPhases)"
    }

    func publishEmpty(on mapView: MKMapView, targetReadiness: String) {
        status?.text =
            "network:off;lines:0;overlays:0;backbones:0;networkStations:0"
            + ";rides:0"
            + String(
                format: ";centerLat:%.6f;centerLon:%.6f;distance:%.1f", mapView.centerCoordinate.latitude,
                mapView.centerCoordinate.longitude, mapView.camera.centerCoordinateDistance)
            + String(
                format: ";viewportWidth:%.1f;viewportHeight:%.1f", mapView.bounds.width,
                mapView.bounds.height)
            + targetReadiness
        updateBasemapStatus(on: mapView)
        status?.text = (status?.text ?? "")
            + ";rideOverlaysMs:0;rideCacheMisses:0;markersMs:0;networkOverlaysMs:0"
            + ";teardownMs:0;rideScanMs:0;materializeMs:0"
            + ";labelPassMs:\(labelPassMilliseconds);labelPassMaxMs:\(labelPassMaxMilliseconds)"
            + ";gestureLabelPassMaxMs:\(gestureLabelPassMaxMilliseconds)"
            + ";regionTickMaxMs:\(regionTickMaxMilliseconds);stackingMaxMs:\(stackingMaxMilliseconds)"
            + ";annotationViews:\(mapView.annotations.count)"
    }

    /// Live inspection of mounted overlays and their MapKit renderers,
    /// invoked only by an opt-in stress test's accessibility snapshot.
    func stressSelectionReadiness(
        on mapView: MKMapView, rides: [RiddenRouteStore.DrawnRide],
        draws: (RiddenRouteStore.DrawnSegment, RiddenRouteStore.DrawnRide, [Statistics.Stop]) -> Bool
    ) -> String {
        let id = stressSubmittedSelection ?? "none"
        let target = rides.first { $0.id == stressSubmittedSelection }
        let expected =
            target.map { ride in
                let flags = MapRideMarkers.rideFlags(ride.stops)
                return ride.segments.filter {
                    $0.coordinates.count > 1 && draws($0, ride, flags)
                }.count
            } ?? 0
        let mounted = mapView.overlays.compactMap { $0 as? MKMultiPolyline }
        let cores = mounted.filter { $0.title == "ride|\(id)" || $0.title == "ride-xday|\(id)" }
        let casings = mounted.filter {
            $0.title == "ride-casing|\(id)" || $0.title == "ride-xday-casing|\(id)"
        }
        let parts = cores.reduce(0) { $0 + $1.polylines.count }
        let casingParts = casings.reduce(0) { $0 + $1.polylines.count }
        let coreRenderers = cores.compactMap { mapView.renderer(for: $0) }
        let casingRenderers = casings.compactMap { mapView.renderer(for: $0) }
        let nonemptyRides = rides.filter { $0.segments.contains { $0.coordinates.count > 1 } }.count
        let installedRideOverlays = mounted.filter {
            $0.title?.hasPrefix("ride|") == true || $0.title?.hasPrefix("ride-xday|") == true
        }.count
        let settled =
            !cores.isEmpty && coreRenderers.count == cores.count
            && casingRenderers.count == casings.count && casingParts == parts
            && !casings.isEmpty && casingRenderers.allSatisfy { $0.alpha >= 0.89 }
            && coreRenderers.allSatisfy { $0.alpha > 0 }
        return ";submittedSelection:\(id);submittedDate:\(stressSubmittedDate)"
            + ";nonemptyRides:\(nonemptyRides);installedRideOverlays:\(installedRideOverlays)"
            + ";selectionExpectedParts:\(expected);selectionParts:\(parts);selectionCasingParts:\(casingParts)"
            + ";selectionRenderers:\(coreRenderers.count);selectionSettled:\(settled ? 1 : 0)"
    }

    func targetRideReadiness(
        on mapView: MKMapView, rides: [RiddenRouteStore.DrawnRide],
        categoryCountries: Set<String>,
        draws: (RiddenRouteStore.DrawnSegment, RiddenRouteStore.DrawnRide, [Statistics.Stop]) -> Bool
    ) -> String {
        // A ride count includes entries whose geometry is still being
        // decoded. Picking/focus tests wait for their target and the
        // category index used to filter its segments.
        guard let targetID = ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_READY_RIDE"]
        else { return "" }
        let target = rides.first { $0.id == targetID }
        let ready = target?.segments.contains { $0.coordinates.count > 1 } == true
        let classified = target.map { categoryCountries.contains($0.country) } == true
        let expectedParts =
            target.map { ride in
                let flags = MapRideMarkers.rideFlags(ride.stops)
                return ride.segments.filter {
                    $0.coordinates.count > 1 && draws($0, ride, flags)
                }.count
            } ?? 0
        let installedParts = mapView.overlays.compactMap { $0 as? MKMultiPolyline }
            .filter {
                ($0.title ?? "") == "ride|\(targetID)"
                    || ($0.title ?? "") == "ride-xday|\(targetID)"
            }
            .reduce(0) { $0 + $1.polylines.count }
        return ";targetRideReady:\(ready ? 1 : 0);targetCategoryReady:\(classified ? 1 : 0)"
            + ";targetRouteParts:\(expectedParts);installedTargetRouteParts:\(installedParts)"
    }
}
#endif
