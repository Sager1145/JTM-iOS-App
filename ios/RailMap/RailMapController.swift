import CoreLocation
import MapKit
import Observation
import RailCore
import RailPresentation
import SwiftUI

/// The commands the control bar can give the map, and the state it reads back.
///
/// The bar and the map are in different halves of the layout — on iPad the bar
/// lives at the foot of the sidebar while the map fills the detail pane — so
/// they cannot talk by being nested. This object is the wire between them.
///
/// It is also where the difference between the two "locate" buttons is kept
/// honest. The web app's 定位 button fits the *selection*: it frames the
/// railway being looked at. It has never had anything to do with where the
/// reader is standing, which is why this adds a second, separate button for
/// that. Collapsing the two would silently change what 定位 means.
@MainActor
@Observable
final class RailMapController {

    @ObservationIgnored private var cameraPolicy = MapCameraPolicy()
    private(set) var autoFocusRequest: MapCameraPolicy.FocusRequest?

    func requestAutoFocus(
        _ target: MapCameraPolicy.FocusTarget, enabled: Bool, playbackIsActive: Bool
    ) {
        autoFocusRequest = cameraPolicy.requestFocus(
            target, enabled: enabled, playbackIsActive: playbackIsActive)
        if autoFocusRequest != nil {
            pendingFollow = false
        }
    }

    func takeAutoFocusRequest(
        matching request: MapCameraPolicy.FocusRequest?
    ) -> MapCameraPolicy.FocusRequest? {
        guard request == autoFocusRequest else { return nil }
        return cameraPolicy.takeFocusRequest()
    }

    func pendingAutoFocusRequest(
        matching request: MapCameraPolicy.FocusRequest?
    ) -> MapCameraPolicy.FocusRequest? {
        guard request == autoFocusRequest else { return nil }
        return cameraPolicy.pendingFocusRequest
    }

    func cancelAutoFocus() { cameraPolicy.cancelFocus() }

    func isCurrentAutoFocus(_ request: MapCameraPolicy.FocusRequest) -> Bool {
        cameraPolicy.isCurrent(request)
    }

    // MARK: - state the bar renders from

    /// Map bearing in degrees. The compass needle points at true north, so it
    /// is drawn rotated by the negation of this.
    private(set) var headingDegrees: Double = 0

    /// Whether the map is currently following the device.
    private(set) var isFollowingUser = false

    /// Whether the rail network is drawn. The web app makes the network an
    /// opt-in layer rather than a permanent fixture, and the train button is
    /// that switch.
    ///
    /// Off to start with, which is what "opt-in" means and what the web app
    /// does (`app-map-init.js`, the `map.allRailways` toggle). It shipped
    /// defaulted on, and the reason that is wrong is the reason the web app
    /// gives for its own default: every railway in the country drawn under the
    /// reader's own rides buries the thing the app is for. A first launch is
    /// not blank without it — the basemap is still there, exactly as it is in
    /// the browser.
    var showsNetwork = false

    /// The rest of the layers menu: which of the reader's own route lines,
    /// station dots and ridden-line categories are drawn. See ``MapLayers``.
    var layers = MapLayers()
    var basemapOpacity = 1.0

    /// Whether the reader has asked for less motion.
    ///
    /// Pushed in from the view rather than read here: `@Environment` belongs to
    /// a `View`, and this object is deliberately not one. §9.4 asks a camera
    /// move to become shorter or to happen outright rather than travelling, and
    /// MapKit's only control over that is `animated:` — so this is what every
    /// call below passes.
    ///
    /// The writer is `RailWorkspaceView.map`'s `onChange(of: reduceMotion,
    /// initial: true)`, and it is named here because for a while there was no
    /// writer at all: this property held its `false` default for the app's
    /// whole life, so the six `RailMotion.cameraAnimated(reduceMotion:)` calls
    /// below were a constant `true` and every camera move flew with Reduce
    /// Motion on. A pushed-in value fails silently when nobody pushes it, and
    /// nothing about the reading side shows that.
    var reduceMotion = false

    private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined

    /// Set when the reader asks to be located but the system has refused.
    /// Surfaced rather than swallowed: a button that appears to do nothing is
    /// worse than one that explains itself.
    ///
    /// A CASE rather than a sentence. This used to hold a `String(localized:)`
    /// result, and `RideSheet.swift` records why that is always wrong here:
    /// the app ships no `.lproj` bundles — its catalog is the web app's, read
    /// at runtime by `RailCore.Localization` — so `String(localized:)` returns
    /// English in all four languages while LOOKING translated. Naming the
    /// state instead lets the control bar resolve it through
    /// `AppLocalization`, which is the only thing in the app that knows what
    /// language the reader chose.
    private(set) var locationRefusal: LocationRefusal?

    /// Why the map cannot follow the device.
    ///
    /// Two cases, not one message: "you have never been asked" is a different
    /// sentence from "you said no", and the first one names the Settings path
    /// that fixes it.
    enum LocationRefusal: String, Equatable {
        /// Location Services is off for this app in Settings.
        case unavailable
        /// The reader answered the system prompt with Don't Allow.
        case declined

        var key: String {
            switch self {
            case .unavailable: "ios.location.unavailable"
            case .declined: "ios.location.declined"
            }
        }

        var fallback: String {
            switch self {
            case .unavailable:
                "Location access is off for this app. Settings › Privacy › Location Services."
            case .declined:
                "Location access was declined."
            }
        }
    }

    // MARK: - the map registers itself here

    /// Camera handed from an outgoing map to its replacement. SwiftUI may make
    /// the replacement before dismantling the old representable, or dismantle
    /// first; capturing in `willSet` covers both orders.
    @ObservationIgnored private var replacementCamera: MKMapCamera?
    @ObservationIgnored private var replacementTrackingMode: MKUserTrackingMode = .none

    /// Set by ``RailMapView.Coordinator`` once its `MKMapView` exists.
    ///
    /// Deliberately paired with an observable flag: the control stack contains
    /// an `MKCompassButton`, which cannot be constructed without a map view, so
    /// the interface has to *know* when one arrives rather than reading a
    /// non-observable reference and never being told.
    @ObservationIgnored weak var mapView: MKMapView? {
        willSet {
            guard let current = mapView, current !== newValue else { return }
            replacementCamera = current.camera.copy() as? MKMapCamera
            replacementTrackingMode = current.userTrackingMode
        }
        didSet {
            applyLeadingMargin()
            // makeUIView has no viewport yet. Setting its camera here lets
            // MapKit clamp it against zero bounds, losing center and scale.
            isMapReady = false
            if let mapView { restoreCameraAfterLayout(on: mapView) }
        }
    }

    private(set) var isMapReady = false

    func restoreCameraAfterLayout(on view: MKMapView) {
        guard mapView === view, view.bounds.width > 1, view.bounds.height > 1 else { return }
        if let camera = replacementCamera {
            let trackingMode = replacementTrackingMode
            discardReplacementCamera()
            applyLeadingMargin()
            view.setCamera(camera, animated: false)
            if trackingMode != .none { view.setUserTrackingMode(trackingMode, animated: false) }
        }
        if !isMapReady { isMapReady = true }
        if pendingFollow,
            locationAuthorization == .authorizedAlways || locationAuthorization == .authorizedWhenInUse {
            if beginFollowing() { pendingFollow = false }
        }
    }

    private func discardReplacementCamera() {
        replacementCamera = nil
        replacementTrackingMode = .none
    }

    private func claimCamera() {
        discardReplacementCamera()
        pendingFollow = false
        cameraPolicy.claimCamera()
    }

    func playbackWillMoveCamera() {
        if replacementCamera != nil { claimCamera() }
    }

    // MARK: - commands

    /// One zoom step. MapKit has no notion of a zoom level, so a step is a
    /// halving or doubling of the visible span — which is exactly what a web
    /// map's ± buttons do, and keeps the two apps' buttons comparable.
    func zoomIn() { scaleSpan(by: 0.5) }
    func zoomOut() { scaleSpan(by: 2) }

    /// One zoom step, on the CAMERA rather than on a coordinate region.
    ///
    /// This used to read `mapView.region`, scale its span and hand it back
    /// through `setRegion`, and that loses the two things a region cannot
    /// carry:
    ///
    ///   - **Heading.** `MKCoordinateRegion` has no rotation, so setting one
    ///     always produces a north-up camera. On a map the reader had turned,
    ///     every tap on + or − snapped it back to north — and the compass
    ///     button, whose whole job is to say the map is not north-up, faded out
    ///     a moment later.
    ///   - **A stable step.** On a rotated map `region.span` is the BOUNDING
    ///     BOX of the tilted viewport, which is wider than what is actually on
    ///     screen. Scaling that and converting back is not the inverse of
    ///     itself, so repeated taps drifted the centre and the step size.
    ///
    /// `centerCoordinateDistance` is the same quantity in the form the camera
    /// keeps it — metres from the centre coordinate — so halving it is one
    /// level in, heading and pitch are untouched, and the operation round-trips
    /// exactly. `resetNorth` below already worked this way; this is the other
    /// half of that.
    private func scaleSpan(by factor: Double) {
        guard let mapView else { return }
        claimCamera()
        let camera = mapView.camera.copy() as! MKMapCamera
        // Clamped for the same reason the span was: past MapKit's own limits it
        // stops accepting the value and jumps somewhere unrelated. About 150 m
        // across at the near end, and the whole globe at the far one.
        camera.centerCoordinateDistance = min(
            max(camera.centerCoordinateDistance * factor, 200), 60_000_000)
        mapView.setCamera(
            camera, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
    }

    /// Turn the map back to north, keeping the centre and zoom.
    func resetNorth() {
        guard let mapView else { return }
        claimCamera()
        let camera = mapView.camera.copy() as! MKMapCamera
        camera.heading = 0
        mapView.setCamera(camera, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
    }

    /// Frame the drawn railway — the native reading of the web app's 定位.
    func fitToNetwork() {
        guard let region = fitRegion else { return }
        fit(Self.mapRect(of: region))
    }

    /// Frame the selected ridden route, falling back to the complete network
    /// when no route geometry is available for the current selection.
    func fitToSelection() {
        guard let region = selectionRegion ?? fitRegion else { return }
        fit(region)
    }

    /// Frame a region, clear of the resident sheet.
    ///
    /// The map hands regions rather than rects — `region(covering:)` is what
    /// it computes from a ride's own strokes — so the conversion belongs here,
    /// with the padding rule it feeds, rather than at every caller.
    func fit(_ region: MKCoordinateRegion, animated: Bool? = nil) {
        fit(Self.mapRect(of: region), animated: animated)
    }

    /// Frame an extent, clear of the resident sheet.
    ///
    /// The bottom inset is the sheet's own height (§9.5.6). Without it, every
    /// "frame this" centres its subject behind the panel covering the lower
    /// half of the screen — a frame nobody can read, and the reason both fit
    /// actions go through here rather than calling `setRegion`, which has no
    /// padding to give.
    func fit(_ rect: MKMapRect, animated: Bool? = nil) {
        guard let mapView, !rect.isNull else { return }
        claimCamera()
        stopFollowingUser()
        mapView.setVisibleMapRect(
            rect,
            edgePadding: framingInsets,
            // `animated` overrides only downwards in practice: the transport
            // passes false when the reader asked for less motion, and the
            // reduce-motion rule below would have said the same. It is a
            // parameter so a caller that has already decided does not have to
            // decide twice.
            animated: animated ?? RailMotion.cameraAnimated(reduceMotion: reduceMotion))
    }

    /// Automatic focus leaves an already visible subject and the user's zoom
    /// alone. Explicit locate commands continue to frame its complete extent.
    func fitIfNeeded(_ region: MKCoordinateRegion) {
        guard let mapView else { return }
        let rect = Self.mapRect(of: region)
        let available = mapView.bounds.inset(by: framingInsets)
        let corners = [
            MKMapPoint(x: rect.minX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.minY),
            MKMapPoint(x: rect.minX, y: rect.maxY),
            MKMapPoint(x: rect.maxX, y: rect.maxY),
        ]
        if available.width > 0, available.height > 0,
            corners.allSatisfy({ available.contains(mapView.convert($0.coordinate, toPointTo: mapView)) }) {
            return
        }
        fit(rect)
    }

    /// The room a framed subject is given: the resident sheet's own height at
    /// the bottom (§9.5.6), the docked card's own width at the left in the
    /// wide composition, and a margin everywhere else.
    ///
    /// Non-private because the launch-framing harness in `ContentView` needs
    /// the same padding the reader's own "frame this" calls use — a debug
    /// camera set with a bare `UIEdgeInsets(40,40,40,40)` would land a shot
    /// half hidden under the card on any window wide enough to show one.
    var framingInsets: UIEdgeInsets {
        UIEdgeInsets(
            top: 40,
            left: max(40, leadingObstruction + 20),
            bottom: max(40, bottomObstruction + 20),
            right: 40)
    }

    /// The same rectangle, for the playback chase to centre its train in.
    ///
    /// Exposed because the transport frames the map from two places and they
    /// have to agree about where the middle is. The bracketing moves — the
    /// opening overview, the ease onto the first journey, the closing panorama
    /// — come through ``fit(_:animated:)`` and are therefore clear of the
    /// panel; the per-frame chase wrote `setRegion` directly and centred on the
    /// raw view, so the instant the clock started the map jumped by half the
    /// sheet's height and the train then rode the panel's top edge for the
    /// whole run.
    var playbackFramingInsets: UIEdgeInsets { framingInsets }

    // MARK: - opening camera

    /// Open once, before a gesture, explicit camera command or focus request
    /// has claimed the map. Rail package completion never requests this move.
    @discardableResult
    func frameAtLaunch(_ region: MKCoordinateRegion) -> Bool {
        guard let mapView else { return false }
        let rect = Self.mapRect(of: region)
        guard !rect.isNull, cameraPolicy.openAtLaunch() else { return false }
        mapView.setVisibleMapRect(rect, edgePadding: framingInsets, animated: false)
        return true
    }

#if DEBUG
    /// Deterministic camera ownership for screenshot/UI-test harnesses.
    /// Marking the opening move consumed prevents the normal launch framing
    /// task from overwriting the requested audit location a moment later.
    func frameForUITest(_ region: MKCoordinateRegion) {
        guard let mapView else { return }
        claimCamera()
        mapView.setRegion(region, animated: false)
    }

    /// Package-bounds audit framing, after the normal opening move. Unlike the
    /// explicit region override, it does not change launch ownership flags.
    func frameForUITest(_ rect: MKMapRect) {
        mapView?.setVisibleMapRect(rect, edgePadding: framingInsets, animated: false)
    }
#endif

    /// Told by the map when a finger starts moving it.
    func readerBeganManipulating() { claimCamera() }

    /// How much of the map's bottom edge the resident sheet is covering right
    /// now. Written by the workspace as the sheet moves.
    @ObservationIgnored var bottomObstruction: CGFloat = 0

    /// How much of the map's leading edge the docked menu card is covering
    /// right now, in the wide composition. Written by the workspace once,
    /// from the panel width the same layout pass already computed — the
    /// card does not move the way the resident sheet's height does, so this
    /// has no per-frame drag to track.
    ///
    /// The `didSet` pushes the same number into the map's own
    /// `directionalLayoutMargins`, because `framingInsets` only moves a
    /// camera THIS object frames — it does nothing for MapKit's own Legal
    /// label or any built-in control MapKit draws for itself, both of which
    /// would otherwise sit under the card exactly where a reader would go
    /// looking for them.
    @ObservationIgnored var leadingObstruction: CGFloat = 0 {
        didSet { applyLeadingMargin() }
    }

    /// Pushes `leadingObstruction` into whatever `MKMapView` is current.
    ///
    /// Split out of `leadingObstruction`'s `didSet` (and no longer guarded on
    /// `oldValue`) so `mapView`'s own `didSet` can call it too — a fresh map
    /// view from a composition swap needs the number applied even though
    /// `leadingObstruction` itself did not change. The write is cheap enough
    /// that re-applying an unchanged value costs nothing worth guarding.
    private func applyLeadingMargin() {
        guard let mapView else { return }
        var margins = mapView.directionalLayoutMargins
        guard margins.leading != leadingObstruction else { return }
        margins.leading = leadingObstruction
        mapView.directionalLayoutMargins = margins
    }

    /// A region as the rect the padded framing call needs.
    private static func mapRect(of region: MKCoordinateRegion) -> MKMapRect {
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let bottomRight = MKMapPoint(
            CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y))
    }

    /// The box that holds every one of these strokes, with the margin a framed
    /// subject is given around itself.
    ///
    /// Here rather than inside the map's coordinator because two halves of the
    /// app now measure the same thing: the coordinator frames the selected
    /// ride and the day's rides, and the workspace frames the journeys the
    /// opening view is for. One box, one margin, so a "fit this" cannot come
    /// to mean two slightly different framings.
    ///
    /// `nil` for strokes that hold no points at all — a ride whose route has
    /// not solved has nothing to frame, and a null rect would silently move
    /// the camera nowhere.
    nonisolated static func region(covering strokes: [[Coordinate]]) -> MKCoordinateRegion? {
        var minLat = Double.infinity, maxLat = -Double.infinity
        var minLon = Double.infinity, maxLon = -Double.infinity
        for stroke in strokes {
            for point in stroke {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLon = min(minLon, point.lon)
                maxLon = max(maxLon, point.lon)
            }
        }
        guard minLat <= maxLat, minLon <= maxLon else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.35, 0.01)
            )
        )
    }

    /// Supplied by the map each time it rebuilds, so the button frames what is
    /// actually drawn rather than a remembered extent.
    @ObservationIgnored var fitRegion: MKCoordinateRegion?
    @ObservationIgnored var selectionRegion: MKCoordinateRegion?

    // MARK: - the device's own position

    func toggleFollowUser() {
        if isFollowingUser {
            stopFollowingUser()
        } else {
            startFollowingUser()
        }
    }

    func startFollowingUser() {
        claimCamera()
        locationRefusal = nil
        switch locationAuthorization {
        case .notDetermined:
            // The prompt is the answer to the tap; following begins in the
            // authorization callback rather than here, because asking and
            // acting in the same breath shows the reader an empty map.
            pendingFollow = true
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            locationRefusal = .unavailable
        default:
            pendingFollow = !beginFollowing()
        }
    }

    func stopFollowingUser() {
        pendingFollow = false
        guard let mapView else { return }
        mapView.setUserTrackingMode(
            .none, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
        isFollowingUser = false
    }

    private func beginFollowing() -> Bool {
        guard isMapReady, let mapView else { return false }
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(
            .follow, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
        isFollowingUser = true
        return true
    }

    // MARK: - feedback from the map

    /// Both guarded, and it is not a micro-optimisation.
    ///
    /// `@Observable`'s generated setter does not compare — it calls
    /// `withMutation` whatever it is handed — and the map reports a region
    /// change on every frame of a playback chase, because the chase writes the
    /// visible rect on every display-link tick. Writing the same heading and
    /// the same tracking mode sixty times a second therefore invalidated every
    /// view that read either of them sixty times a second, `MapControlBar`
    /// among them, for two values that change when the reader rotates the map
    /// or presses 定位 and at no other time.
    func mapDidChange(heading: Double, trackingMode: MKUserTrackingMode) {
        if headingDegrees != heading { headingDegrees = heading }
        let following = trackingMode != .none
        if isFollowingUser != following { isFollowingUser = following }
    }

    // MARK: - CoreLocation

    @ObservationIgnored private var pendingFollow = false
    // @ObservationIgnored because @Observable rewrites stored properties into
    // computed ones and `lazy` cannot survive that. Neither of these is state
    // the interface reads, so there is nothing to observe here anyway.
    @ObservationIgnored private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = locationDelegate
        return manager
    }()
    @ObservationIgnored private lazy var locationDelegate = LocationDelegate(controller: self)

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        locationAuthorization = status
        guard pendingFollow else { return }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            pendingFollow = !beginFollowing()
        case .denied, .restricted:
            pendingFollow = false
            locationRefusal = .declined
        default:
            break
        }
    }

    /// A separate object because `CLLocationManagerDelegate` conformance would
    /// otherwise drag `@Observable`'s stored properties into an
    /// `NSObject` subclass, and the two do not mix well.
    private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
        weak var controller: RailMapController?

        init(controller: RailMapController) {
            self.controller = controller
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor [weak controller] in
                controller?.authorizationChanged(status)
            }
        }
    }
}
