import MapKit
import RailCore
import RailPresentation
import SwiftUI

struct RailMapView: View {
    var lines: [RailNetworkStore.DrawnLine]
    var stations: [RailNetworkStore.DrawnStation]
    var rides: [RiddenRouteStore.DrawnRide]
    /// The union of the countries under the camera's last request, so a 定位 tap
    /// frames the countries being looked at rather than only what the byte
    /// budget currently keeps in `lines`. Nil until the store has seen a
    /// first camera request. See `RailNetworkStore.networkExtent`.
    var networkExtent: MKCoordinateRegion?
    var selectedTrainID: String?
    /// The date the reader has scoped the ride list to, or `Dates.allDates`.
    ///
    /// The map needs it for two things it cannot otherwise decide: which rides
    /// are off-date and should draw at `DisplaySettings.dimOpacity` rather than
    /// vanish, and — with `DrawnRide.daySpan` — which half of an overnight ride
    /// runs on the other calendar day, which `showFullCrossDay` either dashes
    /// or draws solid. Defaulted so a preview needs no date.
    var selectedDate: String = Dates.allDates
    /// The selected train's normalized ride date (`Dates.normalizeTrainDate`),
    /// or nil when nothing is selected or the train is undated. This is not
    /// ``selectedDate`` — that scopes the journey list. A nil date uses the
    /// Current era predicate.
    var networkRideDate: String? = nil
    /// Whether the network is drawn. Kept separate from `lines` on purpose:
    /// hiding the network used to be expressed by passing an empty list, which
    /// made showing it again indistinguishable from loading a country, so the
    /// map re-framed itself and threw away wherever the reader had panned to.
    var showsNetwork: Bool
    /// The N02 edge indexes the ridden-line category filter classifies
    /// against, one per region, and only for the regions that have rides.
    ///
    /// Handed in rather than reached for: building one parses the whole rail
    /// network, and the render path must never do that (`app-stats.js` says so
    /// in as many words). A region that is missing here is undetermined, and
    /// an undetermined ride stays visible — which is also the state while the
    /// indexes are still being built, and the state whenever every category is
    /// switched on and nothing needs classifying at all.
    var categoryIndexes: [String: Statistics.EdgeIndex] = [:]
    /// The wire to the control bar, which lives elsewhere in the layout — at
    /// the bottom of the screen on iPhone, at the foot of the sidebar on iPad.
    var controller: RailMapController
    var playback: PlaybackController
    /// Every ride under the tap, nearest first — empty when the tap landed on
    /// none. See ``Coordinator/handleMapTap(_:)``: a touch cannot hover, so
    /// the choice between crossing lines is handed up rather than guessed at.
    var onSelectRide: ([String]) -> Void
    /// A tap on a network station's bead. Handed up rather than answered here,
    /// because the answer is a sheet and a sheet presented from inside the map
    /// is a sheet that disappears with it.
    var onSelectStation: (StationCard) -> Void = { _ in }
    /// The rect the map has just rebuilt for.
    ///
    /// The map is the only thing that knows which countries are on screen, and
    /// `RailNetworkStore` decodes a country only when something asks for it —
    /// so this is the ask. Reported from the rebuild rather than from every
    /// camera callback because the rebuild is already throttled to a zoom tier
    /// and a padded rect, and a pan inside that rect cannot bring a new
    /// country into view. The second value is the viewport-adjusted network
    /// visibility zoom; loading uses the same scale as line and station gates.
    var onBuildRect: (MKMapRect, Double) -> Void = { _, _ in }
    /// Reports back what the renderer actually did, so the numbers on screen
    /// are measurements rather than estimates.
    var onRender: (RenderStats) -> Void

    /// The 顯示調節 numbers.
    ///
    /// Read from the environment rather than taken as a parameter: `AppShell`
    /// publishes one `DisplaySettings`, the panel that edits it and the map
    /// that draws with it sit in different branches of the tree, and threading
    /// it through every view between would make the ride list an intermediary
    /// in a conversation it takes no part in. Optional so a preview that never
    /// installed one draws at the defaults instead of trapping.
    ///
    /// `@Environment` has no `init(wrappedValue:)`, so this is NOT part of the
    /// memberwise initialiser and `RailWorkspaceView`'s call site is untouched.
    @Environment(DisplaySettings.self) private var displaySettings: DisplaySettings?

    /// The reader's language, for the three places on this map that carry a
    /// station's NAME rather than its mark: the network's station callout, the
    /// ride's own station captions, and the origin / destination cards.
    ///
    /// Read from the environment for the same reason `displaySettings` is —
    /// `AppShell` publishes one and the map is not on the path between it and
    /// the settings panel — and optional for the same reason: a preview that
    /// installed none draws the packages' own names rather than trapping.
    @Environment(AppLocalization.self) private var localization: AppLocalization?

    /// A snapshot of the 顯示調節 values, taken during a SwiftUI update and
    /// then carried by value.
    ///
    /// The renderer runs off `MKMapView` delegate callbacks that are not
    /// SwiftUI updates, so it must not hold the observable object and re-read
    /// it whenever a region changes — that is how one redraw ends up mixing
    /// two generations of settings. It also gives the coordinator something it
    /// can compare, which is what tells a settings change from a pan.
    struct DisplayValues: Equatable {
        var routeWidthScale = DisplaySettings.Defaults.routeWidthScale
        var riddenOpacity = DisplaySettings.Defaults.riddenOpacity
        var dimOpacity = DisplaySettings.Defaults.dimOpacity
        var focusBoost = DisplaySettings.Defaults.focusBoost
        var showFullCrossDay = DisplaySettings.Defaults.showFullCrossDay
        var networkEra = DisplayNetworkEra.current
        var markers = MapRideMarkers.Settings(
            terminalRadius: DisplaySettings.Defaults.terminalRadius,
            passRadius: DisplaySettings.Defaults.passRadius,
            stopCentreRadius: DisplaySettings.Defaults.stopRadius
                * DisplaySettings.stopCentreSliderScale,
            markerStrokeScale: DisplaySettings.Defaults.markerStrokeScale,
            focusBoost: DisplaySettings.Defaults.focusBoost)

        init() {}

        /// `DisplaySettings` is main-actor state; a SwiftUI update is on the
        /// main actor, and this is the moment the values leave it.
        @MainActor
        init(_ settings: DisplaySettings) {
            routeWidthScale = settings.routeWidthScale
            riddenOpacity = settings.riddenOpacity
            dimOpacity = settings.dimOpacity
            focusBoost = settings.focusBoost
            showFullCrossDay = settings.showFullCrossDay
            networkEra = settings.networkEra
            markers = MapRideMarkers.Settings(
                terminalRadius: settings.terminalRadius,
                passRadius: settings.passRadius,
                stopCentreRadius: settings.stopCentreRadius,
                markerStrokeScale: settings.markerStrokeScale,
                focusBoost: settings.focusBoost)
        }
    }

    struct RenderStats: Equatable {
        var zoom: Double
        var visibilityZoom: Double
        var visibleLines: Int
        var overlays: Int
        var vertices: Int
        var buildMilliseconds: Int
        /// Lines whose bounding box never met the build rect. A large number
        /// here is the off-screen cull earning its keep; a zero at a city zoom
        /// would mean it is not working.
        var culledOffScreen: Int = 0
        /// The threshold actually in force. Below `visibilityZoom` when the vertex
        /// budget had to raise the bar — worth seeing rather than guessing at.
        var threshold: Double = 0
    }

    /// The environment read happens HERE, in a `body`.
    ///
    /// A `UIViewRepresentable` has no body, and `updateUIView` is not a scope
    /// SwiftUI is documented to install observation tracking around — so a
    /// 顯示調節 value first read inside it might never schedule an update when
    /// the reader next moved the slider. Read in a body it is tracked like any
    /// other observable property, and the surface below then takes the numbers
    /// as a plain value, exactly the way it already takes the lines and the
    /// rides.
    var body: some View {
        Surface(
            lines: lines,
            stations: stations,
            rides: rides,
            networkExtent: networkExtent,
            selectedTrainID: selectedTrainID,
            selectedDate: selectedDate,
            networkRideDate: networkRideDate,
            showsNetwork: showsNetwork,
            // Read HERE, in a body, for the same reason the 顯示調節 numbers
            // are: `updateUIView` is not a scope SwiftUI installs observation
            // tracking around, so a switch first read down there might never
            // schedule the update that redraws it.
            layers: controller.layers,
            draftMap: controller.draftMap,
            categoryIndexes: categoryIndexes,
            autoFocusRequest: controller.autoFocusRequest,
            isMapReady: controller.isMapReady,
            controller: controller,
            playback: playback,
            display: displaySettings.map(DisplayValues.init) ?? DisplayValues(),
            naming: localization.map(MapNaming.init) ?? MapNaming(),
            localization: localization,
            onSelectRide: onSelectRide,
            onSelectStation: onSelectStation,
            onBuildRect: onBuildRect,
            onRender: onRender
        )
    }

    /// The `MKMapView` itself, and everything that draws into it.
    struct Surface: UIViewRepresentable {
        var lines: [RailNetworkStore.DrawnLine]
        var stations: [RailNetworkStore.DrawnStation]
        var rides: [RiddenRouteStore.DrawnRide]
        var networkExtent: MKCoordinateRegion?
        var selectedTrainID: String?
        var selectedDate: String
        var networkRideDate: String?
        var showsNetwork: Bool
        var layers: MapLayers
        var draftMap: DraftMapSnapshot
        var categoryIndexes: [String: Statistics.EdgeIndex]
        var autoFocusRequest: MapCameraPolicy.FocusRequest?
        var isMapReady: Bool
        var controller: RailMapController
        var playback: PlaybackController
        var display: DisplayValues
        /// What the reader's language settles, as a value the renderer can
        /// compare — see ``MapNaming``. The lookups themselves go through
        /// `localization`.
        var naming: MapNaming
        var localization: AppLocalization?
        var onSelectRide: ([String]) -> Void
        var onSelectStation: (StationCard) -> Void
        var onBuildRect: (MKMapRect, Double) -> Void = { _, _ in }
        var onRender: (RenderStats) -> Void

        /// MapKit need not send a camera callback when only the window size
        /// changes. Report layout separately so Stage Manager and Mac resizing
        /// cannot leave network eligibility or culling at the previous size.
        final class ViewportMapView: MKMapView {
            var onSizeChange: ((MKMapView) -> Void)?
            private var reportedSize: CGSize = .zero
            var preservesCameraOnResize: (() -> Bool)?
            var cameraIntentRevision: (() -> UInt64?)?
            private var resizeCamera: (camera: MKMapCamera, revision: UInt64)?

            override var frame: CGRect {
                willSet { captureCameraBeforeResize(to: newValue.size) }
            }

            override var bounds: CGRect {
                willSet { captureCameraBeforeResize(to: newValue.size) }
            }

            private func captureCameraBeforeResize(to size: CGSize) {
                guard size != bounds.size, bounds.width > 1, bounds.height > 1,
                    size.width > 1, size.height > 1, resizeCamera == nil,
                    userTrackingMode == .none, preservesCameraOnResize?() == true
                else { return }
                guard let revision = cameraIntentRevision?(),
                    let saved = camera.copy() as? MKMapCamera else { return }
                resizeCamera = (saved, revision)
            }
            #if DEBUG
            weak var renderStatus: UILabel?
            weak var gestureTarget: UIView?
            #endif

            override func layoutSubviews() {
                super.layoutSubviews()
                // MapKit can shift the center as its viewport and safe-area
                // margins change. A passive resize keeps the existing camera.
                if let saved = resizeCamera {
                    resizeCamera = nil
                    if preservesCameraOnResize?() == true, userTrackingMode == .none,
                        cameraIntentRevision?() == saved.revision {
                        setCamera(saved.camera, animated: false)
                    }
                }
                #if DEBUG
                // The map extends beneath system chrome. A probe at (0, 0)
                // can disappear from accessibility snapshots after rotation
                // or resizing even though the railway rendered successfully.
                let windowInsets = window?.safeAreaInsets ?? .zero
                renderStatus?.frame.origin = CGPoint(
                    x: max(safeAreaInsets.left, windowInsets.left) + 8,
                    y: max(safeAreaInsets.top, windowInsets.top) + 8)
                // A square has the same usable pinch span after XCTest
                // rotates screen coordinates. A full-width landscape strip
                // becomes a narrow portrait strip and truncates the gesture.
                let left = max(safeAreaInsets.left, windowInsets.left,
                               bounds.width > bounds.height ? layoutMargins.left : 0)
                let right = max(safeAreaInsets.right, windowInsets.right,
                                bounds.width > bounds.height ? layoutMargins.right : 0)
                let targetSide = max(0, min(300, bounds.width - left - right - 48, bounds.height * 0.28))
                // Rotation can sweep beyond the element's inset pinch rect.
                // On a small portrait phone, keep that sweep above the right
                // toolbar and resident sheet as well as inside the map.
                let centeredProbe = UITestLaunchConfiguration.current[.centeredGestureTarget] == "1"
                let targetCenterY = bounds.height * (
                    !centeredProbe && bounds.width < 500 && bounds.height > bounds.width ? 0.3 : 0.5)
                gestureTarget?.frame = CGRect(
                    x: left + (bounds.width - left - right - targetSide) / 2,
                    y: targetCenterY - targetSide / 2,
                    width: targetSide, height: targetSide)
                #endif
                guard bounds.size != reportedSize else { return }
                reportedSize = bounds.size
                onSizeChange?(self)
            }
        }

        func makeUIView(context: Context) -> MKMapView {
            let mapView = ViewportMapView()
            mapView.preservesCameraOnResize = { [weak coordinator = context.coordinator] in
                guard let coordinator else { return false }
                return coordinator.preservesCameraDuringResize
            }
            mapView.cameraIntentRevision = { [weak coordinator = context.coordinator] in
                coordinator?.controller?.cameraIntentRevision
            }
            mapView.onSizeChange = { [weak coordinator = context.coordinator] view in
                coordinator?.controller?.restoreCameraAfterLayout(on: view)
                coordinator?.viewportSizeChanged(on: view)
            }
#if DEBUG
            // UI tests used to prove only that the “全部線路” switch stayed
            // responsive, while a screenshot that nobody asserted on was the
            // sole evidence that the railway layer actually drew. A one-point,
            // visually empty label gives XCTest a machine-readable render state;
            // it is compiled out of release builds and cannot intercept input.
            let renderStatus = RouteStressStatusLabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            if RouteStressHarness.enabled {
                renderStatus.readStatus = { [weak coordinator = context.coordinator, weak renderStatus] in
                    (renderStatus?.text ?? "") + (coordinator?.stressSelectionReadiness() ?? "")
                }
            }
            renderStatus.text = " "
            renderStatus.textColor = .clear
            renderStatus.isUserInteractionEnabled = false
            renderStatus.isAccessibilityElement = true
            renderStatus.accessibilityIdentifier = "railMapRenderStatus"
            mapView.addSubview(renderStatus)
            mapView.renderStatus = renderStatus
            context.coordinator.attachDiagnosticsStatus(renderStatus)
            if UITestLaunchConfiguration.current[.gestureTarget] == "1" {
                let target = UIView()
                target.isUserInteractionEnabled = false
                target.isAccessibilityElement = true
                target.accessibilityIdentifier = "railMapGestureTarget"
                target.accessibilityLabel = "Map gesture area"
                mapView.addSubview(target)
                mapView.gestureTarget = target
            }
#endif
            mapView.delegate = context.coordinator
            mapView.showsCompass = true
            mapView.showsScale = true
#if targetEnvironment(macCatalyst)
            // Catalyst's MKMapView adds a ± pair by default. Pinch, scroll and
            // the ⌘+/⌘− shortcuts already zoom, and the pair crowded the rail.
            mapView.showsZoomControls = false
#endif

            // The basemap keeps MapKit's default emphasis, so Apple's own
            // zoom-by-zoom detail (roads, labels, terrain) is whatever Apple
            // Maps would show; only the railway is tiered by zoom, in
            // `NetworkLOD`. Points of interest are still excluded so Apple's
            // station pins do not compete with our own station marks.
            // Selection changes only railway styling; keep cartography stable
            // so highlighting a route never triggers a muted-basemap transition.
            let configuration = MKStandardMapConfiguration(emphasisStyle: .default)
            configuration.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = configuration

            context.coordinator.mapView = mapView
            context.coordinator.onSelectRide = onSelectRide
            context.coordinator.onSelectStation = onSelectStation
            context.coordinator.onBuildRect = onBuildRect
            context.coordinator.controller = controller
            context.coordinator.playback = playback
            playback.mapRenderer = context.coordinator
            playback.mapRendererViewSize = mapView.bounds.size
            // The smallest hook `PlaybackController` needs to draw a ride on
            // the same offset pixels the map itself draws it on — see
            // `PlaybackController.drawnCoordinates`.
            playback.drawnCoordinates = { [weak coordinator = context.coordinator] ride, segment in
                coordinator?.drawnCoordinates(of: segment, ride: ride).map {
                    Coordinate(lon: $0.longitude, lat: $0.latitude)
                } ?? segment.coordinates
            }
            controller.mapView = mapView
            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
            tap.delegate = context.coordinator
            mapView.addGestureRecognizer(tap)

            // A double tap is a ZOOM, and a zoom is not an answer about the
            // selection.
            //
            // Without this the single-tap recogniser fires on the FIRST tap of
            // every double tap, so zooming in on empty water cleared the ride
            // the reader had just chosen — and a double tap on the chosen line
            // itself re-picked it, which with 自動縮放 on sent the camera to
            // frame the selection in the middle of the reader's own zoom.
            //
            // This recogniser exists only to be waited on. MapKit's own
            // double-tap-to-zoom is a private recogniser this cannot name, so
            // rather than reaching into `mapView.gestureRecognizers` for
            // something Apple never promised is there, the map gets one of ours
            // to fail against. It consumes nothing (`cancelsTouchesInView` and
            // the two touch delays are all off, and the coordinator answers
            // `true` to `shouldRecognizeSimultaneouslyWith`), so MapKit's zoom
            // still sees the same pair of taps it always did.
            //
            // The cost is that a single tap is answered when the double-tap
            // window closes rather than on the lift. That is the tempo this
            // map already runs at: MapKit's own annotation selection waits for
            // the same recogniser and lands at 0.51–0.57 s (see
            // `mapView(_:didSelect:)`), which is still after this, so the
            // claim/answer order between the two is unchanged.
            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleMapDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = context.coordinator
            doubleTap.cancelsTouchesInView = false
            doubleTap.delaysTouchesBegan = false
            doubleTap.delaysTouchesEnded = false
            mapView.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)

            // Three SENSORS, not gestures: they never move the map and never
            // consume a touch, they only let the coordinator know that a finger
            // is on it. See `Coordinator.handleManipulation(_:)` for what that
            // answer is worth — MapKit reports where the map ENDED UP, and
            // never whether the reader is still moving it.
            //
            // `cancelsTouchesInView = false` is what makes them harmless: every
            // touch still reaches MapKit's own pinch and pan untouched, and
            // `shouldRecognizeSimultaneouslyWith` (which this coordinator
            // answers `true` to) is documented to GUARANTEE simultaneous
            // recognition from either side of a pair.
            for sensor in [
                UIPinchGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleManipulation(_:))),
                UIPanGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleManipulation(_:))),
                UIRotationGestureRecognizer(
                    target: context.coordinator,
                    action: #selector(Coordinator.handleManipulation(_:))),
            ] as [UIGestureRecognizer] {
                sensor.delegate = context.coordinator
                sensor.cancelsTouchesInView = false
                sensor.delaysTouchesBegan = false
                sensor.delaysTouchesEnded = false
                mapView.addGestureRecognizer(sensor)
                context.coordinator.manipulationSensors.append(sensor)
                // The map can pan and select on the same contact when the
                // delegates allow simultaneous recognition. A real camera
                // gesture must fail selection, including its final hold.
                // These are our own sensors; MapKit still receives all input.
                tap.require(toFail: sensor)
            }

            // Dark mode is not just a darker basemap: the packages ship a separate
            // colour per line for it, so the overlays have to be rebuilt with the
            // other palette. MapKit recolours itself; these do not.
            mapView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                (view: MKMapView, _: UITraitCollection) in
                context.coordinator.appearanceChanged(on: view)
            }
#if DEBUG
            if MapIndependentRailPrototype.enabled { context.coordinator.attachIndependentRailPrototype(on: mapView) }
#endif
            return mapView
        }

        func updateUIView(_ mapView: MKMapView, context: Context) {
            context.coordinator.onRender = onRender
            context.coordinator.controller = controller
            context.coordinator.playback = playback
            context.coordinator.onSelectRide = onSelectRide
            context.coordinator.onSelectStation = onSelectStation
            context.coordinator.onBuildRect = onBuildRect
            context.coordinator.localization = localization
            context.coordinator.reconcileDraftPins(draftMap, on: mapView)
            playback.mapRenderer = context.coordinator
            playback.mapRendererViewSize = mapView.bounds.size
            context.coordinator.playbackStateChanged(on: mapView)
            playback.drawnCoordinates = { [weak coordinator = context.coordinator] ride, segment in
                coordinator?.drawnCoordinates(of: segment, ride: ride).map {
                    Coordinate(lon: $0.longitude, lat: $0.latitude)
                } ?? segment.coordinates
            }
            context.coordinator.update(
                lines: lines,
                stations: stations,
                rides: rides,
                networkExtent: networkExtent,
                selectedTrainID: selectedTrainID,
                selectedDate: selectedDate,
                networkRideDate: networkRideDate,
                showsNetwork: showsNetwork,
                layers: layers,
                categoryIndexes: categoryIndexes,
                autoFocusRequest: isMapReady ? autoFocusRequest : nil,
                display: display,
                naming: naming,
                on: mapView
            )
        }

        static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
            coordinator.tearDown(mapView)
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

    }
}
