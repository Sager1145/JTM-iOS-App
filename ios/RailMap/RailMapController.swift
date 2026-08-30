import CoreLocation
import MapKit
import Observation
import RailCore
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

    /// Set by ``RailMapView.Coordinator`` once its `MKMapView` exists.
    ///
    /// Deliberately paired with an observable flag: the control stack contains
    /// an `MKCompassButton`, which cannot be constructed without a map view, so
    /// the interface has to *know* when one arrives rather than reading a
    /// non-observable reference and never being told.
    @ObservationIgnored weak var mapView: MKMapView? {
        didSet { isMapReady = mapView != nil }
    }

    private(set) var isMapReady = false

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
        hasFramedForReader = true
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

    /// The room a framed subject is given: the resident sheet's own height at
    /// the bottom (§9.5.6), and a margin everywhere else.
    private var framingInsets: UIEdgeInsets {
        UIEdgeInsets(top: 40, left: 40, bottom: max(40, bottomObstruction + 20), right: 40)
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

    // MARK: - the one move the app makes for itself

    /// Open the map on a country, once, before anything else has claimed the
    /// camera. Answers whether it did.
    ///
    /// **What this replaced.** The map used to frame ITSELF: each time a
    /// regional package finished decoding, the camera was set to the extent of
    /// every line loaded so far. Five packages land at five different moments
    /// over the first seconds of a launch, so the camera jumped five times and
    /// finished on all five networks at once — a view of four countries the
    /// reader is not going to, arriving after they had already started
    /// pinching, and taking their zoom with it. A camera that moves seconds
    /// after launch is not an opening view, it is an interruption of one.
    ///
    /// So the opening view is now chosen from the RIDES — the country of the
    /// reader's first journey (`RailWorkspaceView.launchExtent`), or East Asia
    /// when there is none — and it happens at most once. Every guard below is
    /// a way of saying the same thing: the app gets the camera only while
    /// nobody else wants it.
    ///
    ///   - ``hasOpened`` — an opening move is a move you make once. A second
    ///     one is exactly the behaviour this replaced.
    ///   - ``hasFramedForReader`` — a journey chosen, a 定位, a statistics
    ///     scope switched. A deliberate move outranks a housekeeping one, and
    ///     the rides can finish loading after any of them.
    ///   - ``readerMovedCamera`` — a finger already on the map. Nothing the
    ///     app decided at launch is worth taking that away for.
    ///
    /// **A country, and nothing closer.** A second, "precise" frame used to
    /// follow this one, zooming onto the routes of the soonest upcoming day as
    /// soon as their geometry had been read off disk. It is gone for the
    /// reason the five-package framing is: it moved the camera at the moment a
    /// FILE finished, which is not a moment the reader did anything at. What
    /// this leaves is a single set-and-stay — which is why it is never
    /// animated. There is nowhere to travel from; this is where the map
    /// starts.
    @discardableResult
    func frameAtLaunch(_ region: MKCoordinateRegion) -> Bool {
        guard !hasOpened, !hasFramedForReader, !readerMovedCamera else { return false }
        guard let mapView else { return false }
        let rect = Self.mapRect(of: region)
        guard !rect.isNull else { return false }
        hasOpened = true
        mapView.setVisibleMapRect(rect, edgePadding: framingInsets, animated: false)
        return true
    }

    /// Whether the map has already opened on its country.
    @ObservationIgnored private(set) var hasOpened = false

    /// Whether the reader's own hands have been on the map.
    ///
    /// Reported by the map's pinch and pan sensors rather than inferred from a
    /// region change, because MapKit's own callbacks cannot tell a gesture
    /// from a `setVisibleMapRect` this object just made — see
    /// ``RailMapView/Coordinator/handleManipulation(_:)``.
    @ObservationIgnored private(set) var readerMovedCamera = false

    /// Told by the map when a finger starts moving it.
    func readerBeganManipulating() { readerMovedCamera = true }

    /// How much of the map's bottom edge the resident sheet is covering right
    /// now. Written by the workspace as the sheet moves.
    @ObservationIgnored var bottomObstruction: CGFloat = 0

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

    /// Whether a move the READER asked for has happened.
    ///
    /// A journey chosen, a 定位, a statistics scope switched. It exists
    /// because the app has one camera move of its own — ``frameAtLaunch(_:)``
    /// — and it waits on rides being read from disk, which can finish after
    /// any of those. A deliberate move outranks a housekeeping one, so the
    /// opening move is simply not owed any more once one has happened.
    @ObservationIgnored private(set) var hasFramedForReader = false

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
            beginFollowing()
        }
    }

    func stopFollowingUser() {
        guard let mapView else { return }
        mapView.setUserTrackingMode(
            .none, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
        isFollowingUser = false
    }

    private func beginFollowing() {
        guard let mapView else { return }
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(
            .follow, animated: RailMotion.cameraAnimated(reduceMotion: reduceMotion))
        isFollowingUser = true
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
        pendingFollow = false
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            beginFollowing()
        case .denied, .restricted:
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
