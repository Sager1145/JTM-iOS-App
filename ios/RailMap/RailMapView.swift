import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// MapKit owns mounted overlays and annotations. Projection, lane offsets,
/// corner rounding and polyline construction live in MapLineGeometry's worker.
@MainActor private func parallelStationCoordinate(
    _ coordinate: CLLocationCoordinate2D, lane: Double, bearing: Double?,
    scale: CGFloat, on mapView: MKMapView
) -> CLLocationCoordinate2D {
    guard lane != 0, let bearing else { return coordinate }
    var point = mapView.convert(coordinate, toPointTo: mapView)
    let radians = bearing * .pi / 180
    let offset = lane * Double(RailStyle.parallelLaneCentreDistance * scale)
    point.x += CGFloat(cos(radians) * offset)
    point.y += CGFloat(sin(radians) * offset)
    return mapView.convert(point, toCoordinateFrom: mapView)
}

/// The web's own last resort for a continuous-stroke platform with no exact
/// `slot` (`rail-network.js`'s nearest-vertex fallback in
/// `displayPartsForLine`): scan every chain this station's line built THIS
/// frame and take the closest vertex, so a station the build never anchored
/// still lands ON the offset stroke instead of at its raw, un-offset
/// coordinate. `build-display-network.py` is expected to give every
/// continuous-region station a `slot` (it fails the build otherwise), so
/// this should never fire for shipped data — it exists purely so a future
/// gap in that guarantee degrades to "off by a few metres" rather than "off
/// the line".
@MainActor private func nearestStrokeAnchorCoordinate(
    for station: RailNetworkStore.DrawnStation,
    in strokeAnchors: [String: [Int: CLLocationCoordinate2D]]
) -> CLLocationCoordinate2D? {
    let prefix = "\(station.region.rawValue)|\(station.lineID)#"
    let target = CLLocation(
        latitude: station.coordinate.lat, longitude: station.coordinate.lon)
    var best: (distance: CLLocationDistance, coordinate: CLLocationCoordinate2D)?
    for (chainID, anchors) in strokeAnchors where chainID.hasPrefix(prefix) {
        for coordinate in anchors.values {
            let distance = target.distance(
                from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if best == nil || distance < best!.distance {
                best = (distance, coordinate)
            }
        }
    }
    return best?.coordinate
}

/// A tiny screen-space collision index for labels the app owns.
///
/// MapKit's annotation collision pass also competes with the basemap's labels.
/// Giving our station names a priority low enough to collide made every name in
/// a dense city disappear behind Apple's road labels; making them `.required`
/// kept the names, but also disabled collision handling between our own names.
/// This grid separates those two questions: it thins only JTM labels before
/// they reach MapKit, then the accepted labels can remain stable above the map.
private struct MapLabelCollisionGrid {
    private struct Cell: Hashable {
        let column: Int
        let row: Int
    }

    private static let cellSize: CGFloat = 96
    private static let horizontalPadding: CGFloat = 4
    private static let verticalPadding: CGFloat = 3
    private var boxesByCell: [Cell: [CGRect]] = [:]

    mutating func insertIfClear(_ box: CGRect) -> Bool {
        guard box.width > 0, box.height > 0 else { return false }
        let padded = box.insetBy(
            dx: -Self.horizontalPadding, dy: -Self.verticalPadding)
        let columns = cellRange(from: padded.minX, through: padded.maxX)
        let rows = cellRange(from: padded.minY, through: padded.maxY)

        for column in columns {
            for row in rows {
                let cell = Cell(column: column, row: row)
                if boxesByCell[cell, default: []].contains(where: {
                    $0.intersects(padded)
                }) {
                    return false
                }
            }
        }
        for column in columns {
            for row in rows {
                boxesByCell[Cell(column: column, row: row), default: []].append(padded)
            }
        }
        return true
    }

    private func cellRange(from lower: CGFloat, through upper: CGFloat) -> ClosedRange<Int> {
        Int(floor(lower / Self.cellSize))...Int(floor(upper / Self.cellSize))
    }
}

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
    /// Whether the network is drawn. Kept separate from `lines` on purpose:
    /// hiding the network used to be expressed by passing an empty list, which
    /// made showing it again indistinguishable from loading a country, so the
    /// map re-framed itself and threw away wherever the reader had panned to.
    var showsNetwork: Bool
    var basemapOpacity: Double
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
    /// memberwise initialiser and `ContentView`'s call site is untouched.
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
            showsNetwork: showsNetwork,
            // Read HERE, in a body, for the same reason the 顯示調節 numbers
            // are: `updateUIView` is not a scope SwiftUI installs observation
            // tracking around, so a switch first read down there might never
            // schedule the update that redraws it.
            layers: controller.layers,
            categoryIndexes: categoryIndexes,
            autoFocusRequest: controller.autoFocusRequest,
            isMapReady: controller.isMapReady,
            basemapOpacity: basemapOpacity,
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
        var showsNetwork: Bool
        var layers: MapLayers
        var categoryIndexes: [String: Statistics.EdgeIndex]
        var autoFocusRequest: MapCameraPolicy.FocusRequest?
        var isMapReady: Bool
        var basemapOpacity: Double
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
            #if DEBUG
            weak var renderStatus: UILabel?
            weak var gestureTarget: UIView?
            #endif

            override func layoutSubviews() {
                super.layoutSubviews()
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
                let targetCenterY = bounds.height * (bounds.width < 500 && bounds.height > bounds.width ? 0.3 : 0.5)
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
            let renderStatus = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            renderStatus.text = " "
            renderStatus.textColor = .clear
            renderStatus.isUserInteractionEnabled = false
            renderStatus.isAccessibilityElement = true
            renderStatus.accessibilityIdentifier = "railMapRenderStatus"
            mapView.addSubview(renderStatus)
            mapView.renderStatus = renderStatus
            context.coordinator.renderStatus = renderStatus
            if ProcessInfo.processInfo.environment["RAILMAP_UI_TEST_GESTURE_TARGET"] == "1" {
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
            let configuration = MKStandardMapConfiguration()
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
            }

            // Dark mode is not just a darker basemap: the packages ship a separate
            // colour per line for it, so the overlays have to be rebuilt with the
            // other palette. MapKit recolours itself; these do not.
            mapView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                (view: MKMapView, _: UITraitCollection) in
                context.coordinator.appearanceChanged(on: view)
            }
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
            playback.mapRenderer = context.coordinator
            playback.mapRendererViewSize = mapView.bounds.size
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
                showsNetwork: showsNetwork,
                layers: layers,
                categoryIndexes: categoryIndexes,
                autoFocusRequest: isMapReady ? autoFocusRequest : nil,
                basemapOpacity: basemapOpacity,
                display: display,
                naming: naming,
                on: mapView
            )
        }

        static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
            coordinator.tearDown(mapView)
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator: NSObject, MKMapViewDelegate, PlaybackMapRendering,
            UIGestureRecognizerDelegate {
            weak var mapView: MKMapView?
            var controller: RailMapController? {
                didSet { playbackLayer.controller = controller }
            }
            weak var playback: PlaybackController? {
                didSet { playbackLayer.playback = playback }
            }
            var onRender: (RenderStats) -> Void = { _ in }
            var onSelectRide: ([String]) -> Void = { _ in }
            var onSelectStation: (StationCard) -> Void = { _ in }
            var onBuildRect: (MKMapRect, Double) -> Void = { _, _ in }
            /// The localisation engine's owner. A `@MainActor` class, and
            /// therefore `Sendable`, so a nonisolated coordinator may hold it;
            /// see ``localized(_:code:)`` for how it is read.
            var localization: AppLocalization?

            private var lines: [RailNetworkStore.DrawnLine] = []
            private var stations: [RailNetworkStore.DrawnStation] = []
            private var rides: [RiddenRouteStore.DrawnRide] = []
            private var networkExtent: MKCoordinateRegion?
            private var selectedTrainID: String?
            private var selectedDate = Dates.allDates
            private var naming = MapNaming()
            private var minZoomByLineId: [String: Int] = [:]
            /// Starts where `RailMapController.showsNetwork` starts, so the
            /// first update is not told the layer just changed.
            private var showsNetwork = false
#if DEBUG
            private var networkEnabledAt: ContinuousClock.Instant?
            private var firstNetworkRenderMilliseconds: Double?
            private var rebuildCount = 0
            private var rebuildsDuringGesture = 0
            private var lineCacheHits = 0
            private var annotationReuses = 0
            private var panCallbacks = 0
            private var lastPanCallback: ContinuousClock.Instant?
            private var maxPanCallbackGapMilliseconds = 0
#endif
            private var layers = MapLayers()
            private var categoryIndexes: [String: Statistics.EdgeIndex] = [:]
            /// Drawn segment → the ridden-line category it belongs to, `""`
            /// for "the index could not say".
            ///
            /// Classifying walks every vertex of every segment, and a rebuild
            /// happens on each zoom tier and each pan out of the built rect —
            /// so without this the filter would put an O(vertices) pass inside
            /// the pan gesture. The web app caches the same answer on the
            /// geometry object itself; here the geometry has no identity to
            /// hang it on, so it is keyed and dropped when the rides or the
            /// indexes move. The CATEGORY is cached rather than the visibility
            /// that follows from it, which is what makes flipping a checkbox
            /// free.
            private var segmentCategories: [String: String] = [:]
            private var basemapOpacity = 1.0
            private var basemapVeil: BasemapVeilOverlay?
            /// Owns the camera snapshot that gates expensive geometry rebuilds.
            private var networkBuildState = MapNetworkBuildState()
            private var viewportResizeTask: Task<Void, Never>?
            /// Owns zoom-dependent line, stroke and ride-overlay geometry.
            private let networkGeometry = MapNetworkGeometryCache()
            /// Bumped whenever `lines` or `stations` moves — see `update`'s
            /// own two sites. The cache key for ``prepareStrokeReferences()`` and
            /// for every ride's own entry in ``strokeRefCache``: both are
            /// built from `lines`/`stations` alone, and are correct for
            /// exactly as long as this number does not move, regardless of
            /// what else changes on a given rebuild.
            private var linesGeneration = 0
            private var annotationsNeedRefresh = false
            /// The geometry phase's outputs the marker phase reads. Kept from the last
            /// completed `rebuild` so the markers can be rebuilt on their own — a
            /// selection changes which dots and captions exist, not where the lines are.
            private struct MarkerBuildContext {
                var zoom: Double
                var visibilityZoom: Double
                var scale: CGFloat
                var buildRect: MKMapRect
                var strokeAnchors: [String: [Int: CLLocationCoordinate2D]]
                var visible: [RailNetworkStore.DrawnLine]
            }
            /// Nil until a rebuild completes, and nil again whenever the next full
            /// rebuild is owed, so a stale context can never place markers against
            /// geometry that is about to change.
            private var markerBuildContext: MarkerBuildContext?
            private struct LineInputs: Equatable, Sendable {
                let contentID: UUID
                let anchors: [Int]
                let dependencies: [String: UUID]
            }
            private var lineInputs: [String: LineInputs] = [:]
            private var matchedLineInputs: [String: LineInputs] = [:]
            /// Background matching and its WGS84 index, independent of zoom.
            private var matchingTask: Task<Void, Never>?
            private var matchingRevision = 0
            private var preparedStrokeIndex: (generation: Int, index: StrokeRide.Index)?
            /// One ride's own segments, matched against ``prepareStrokeReferences()``
            /// — see ``strokeRef(for:of:)``. Keyed by `ride.id`; a ride whose
            /// own `(ride.id, ride.geometryDigest)` and `linesGeneration` both
            /// still match its entry is not walked again.
            private typealias StrokeMatches =
                [String: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])]
            private var strokeRefCache: StrokeMatches = [:]
            private var pendingStrokeRefs:
                (revision: Int, refs: StrokeMatches, inputs: [String: LineInputs])?
            /// The chase — see ``MapPlaybackLayer``, which owns every field the
            /// trail needs and shares only this coordinator's style registry.
            private lazy var playbackLayer = MapPlaybackLayer(overlayStyles: overlayStyles)
            private lazy var overlayInstaller = MapOverlayInstaller(styles: overlayStyles)
            private var networkAnnotations: [MKAnnotation] = []
            private var rideStationAnnotations: [MKAnnotation] = []
            private var endpointAnnotations: [EndpointLabelAnnotation] = []
            private var display = DisplayValues()
            /// The value of ``RailStyle/scale(atZoom:)`` the marks on screen were
            /// last drawn at. Every weight on this map is a token times that one
            /// factor, so re-applying it is the whole of a rescale — and comparing
            /// against it is what keeps a pan that did not change the scale from
            /// touching a single renderer.
            private var styledScale: CGFloat = .nan
            /// Labels have their own shallow zoom ramp after railway weights
            /// have already reached full size. Tracking that ramp separately is
            /// essential: using `styledScale` as the only throttle froze every
            /// station name at the zoom on which it was first configured.
            private var styledMarkZoom = Double.nan
#if DEBUG
            weak var renderStatus: UILabel?
            private let gestureFrameProbe = MapGestureFrameProbe()
#endif
            /// When a tap was last answered with a ride of this map's own —
            /// read by ``mapView(_:didSelect:)`` half a second later, and
            /// cleared as the next touch arrives, so it only ever describes
            /// the touch in hand.
            private var rideAnsweredTap: ContinuousClock.Instant?

            func update(
                lines: [RailNetworkStore.DrawnLine],
                stations: [RailNetworkStore.DrawnStation],
                rides: [RiddenRouteStore.DrawnRide],
                networkExtent: MKCoordinateRegion?,
                selectedTrainID: String?,
                selectedDate: String,
                showsNetwork: Bool,
                layers: MapLayers,
                categoryIndexes: [String: Statistics.EdgeIndex],
                autoFocusRequest: MapCameraPolicy.FocusRequest?,
                basemapOpacity: Double,
                display: DisplayValues,
                naming: MapNaming,
                on mapView: MKMapView
            ) {
                // A sheet drag and a menu presentation can call
                // `updateUIView` every frame while these arrays still share
                // their exact backing buffers with the coordinator. Take that
                // O(1) path before allocating thousands of ids/signatures.
                let linesChanged = Self.changed(lines, from: self.lines, id: \.contentID)
                let stationsChanged = Self.changed(stations, from: self.stations, id: \.contentID)
                let ridesChanged = rides.count != self.rides.count
                    || (!Self.sharesStorage(rides, self.rides)
                        && !zip(rides, self.rides).allSatisfy {
                            Self.rideSignature($0) == Self.rideSignature($1)
                        })
                let selectionChanged = selectedTrainID != self.selectedTrainID
                let focusRequest = controller?.pendingAutoFocusRequest(matching: autoFocusRequest)
                let visibilityChanged = showsNetwork != self.showsNetwork
                    || layers != self.layers
                let basemapChanged = basemapOpacity != self.basemapOpacity
                // Compared by which regions have one, not by value: an edge
                // index holds a dictionary with an entry per network edge, and
                // comparing two of those on every update would cost more than
                // the drawing does. An index is built once per region and
                // never mutated, so its presence is the whole of the news.
                let indexesChanged = Set(categoryIndexes.keys) != Set(self.categoryIndexes.keys)
                // Read here, while `self.layers` is still the previous pass's:
                // the tap index carries only the segments 已乘路線顯示 leaves
                // drawn (see ``drawnStrokes(of:)``), so a category switched off
                // — or back on — moves the hit geometry without moving a
                // single ride.
                let categoriesChanged = layers.categories != self.layers.categories
                // Pure route paint updates existing renderers. Marker geometry
                // and cross-day segmentation still need a layout pass.
                let displayChanged = display != self.display
                let routePaintOnly = displayChanged
                    && display.markers == self.display.markers
                    && display.focusBoost == self.display.focusBoost
                    && display.dimOpacity == self.display.dimOpacity
                    && display.showFullCrossDay == self.display.showFullCrossDay
                // The date scope is paint, not a filter: it decides which
                // rides draw at `dimOpacity` and which half of an overnight
                // one is dashed. Both are properties of things already built,
                // so a scope change is a rebuild like the others.
                let dateChanged = selectedDate != self.selectedDate
                let namingChanged = naming != self.naming
                // `networkExtent` follows the camera's countries, not residency
                // (see `RailNetworkStore.networkExtent`), so a batch that merely
                // adds to it without changing `lines` still has to widen the
                // 定位 frame, and a batch that only evicts must not shrink it.
                // Computed here, ahead of the guard, so an extent-only update
                // (no line/station/ride/etc. change) still reaches the
                // `fitRegion` dispatch below instead of being dropped before
                // it is ever read. It is deliberately not part of
                // `MapDrawChanges`: an extent-only pass must hand the
                // controller its new frame without tripping a geometry
                // rebuild, and `changes.plan` never sees this flag.
                let extentChanged: Bool = {
                    switch (networkExtent, self.networkExtent) {
                    case (nil, nil): return false
                    case let (a?, b?):
                        return a.center.latitude != b.center.latitude
                            || a.center.longitude != b.center.longitude
                            || a.span.latitudeDelta != b.span.latitudeDelta
                            || a.span.longitudeDelta != b.span.longitudeDelta
                    default: return true
                    }
                }()
                guard linesChanged || stationsChanged || ridesChanged
                        || selectionChanged || visibilityChanged || indexesChanged
                        || basemapChanged || displayChanged || dateChanged
                        || namingChanged || focusRequest != nil || extentChanged else { return }

                if ridesChanged || indexesChanged {
                    segmentCategories.removeAll(keepingCapacity: true)
                }
                self.layers = layers
                self.categoryIndexes = categoryIndexes

                self.display = display
                self.selectedDate = selectedDate
                self.naming = naming
#if DEBUG
                if showsNetwork != self.showsNetwork {
                    networkEnabledAt = showsNetwork ? .now : nil
                    firstNetworkRenderMilliseconds = nil
                }
#endif
                self.showsNetwork = showsNetwork
                self.basemapOpacity = basemapOpacity
                self.selectedTrainID = selectedTrainID
                if ridesChanged {
                    self.rides = rides
                    networkGeometry.clearRidePolylines()
                }
                // The tap cull's geometry moved. Dropped rather than rebuilt:
                // `update` runs inside a SwiftUI pass, and a pass over every
                // ridden vertex is the thing this index exists to keep out of
                // one. See ``tapIndex()``.
                //
                // Three ways for it to move, and only the first is the rides
                // themselves. A category switched off takes its segments out of
                // the index, and a region's edge index ARRIVING is what lets
                // those segments be classified at all — before it lands every
                // one of them is undetermined and therefore drawn, so the tap
                // geometry the reader ends up with is not the one built a
                // moment earlier.
                if ridesChanged || categoriesChanged || indexesChanged {
                    cachedTapIndex = nil
                }
                if stationsChanged {
                    self.stations = stations
                    indexStations()
                    // A chain's own `anchors` come off `stations`' slots —
                    // see `prepareStrokeReferences()` — so a station move is a
                    // reason to rebuild them too, not only a line move.
                    linesGeneration += 1
                }

                if linesChanged {
                    self.lines = lines
                    // The WGS84 chain geometry `prepareStrokeReferences()` caches
                    // and every `strokeRef(for:of:)` answer keyed on it are
                    // built from `self.lines` alone; both are stale the
                    // moment it moves.
                    linesGeneration += 1
                    self.minZoomByLineId = Dictionary(
                        lines.map { ($0.lineID, $0.minZoom) },
                        uniquingKeysWith: { first, _ in first })
                }

                if linesChanged || extentChanged {
                    self.networkExtent = networkExtent
                    // A new country's extent, handed to the controller so the 定位
                    // button frames what is actually loaded rather than a
                    // remembered extent — and kept even while the network is
                    // hidden, so the button still works. `networkExtent` — the
                    // union of the countries under the camera's last request,
                    // never shrunk by eviction — takes priority over the
                    // resident `lines`' own bounds, so a budget-driven drop
                    // can never pull the frame in behind it.
                    //
                    // Handed over is ALL that happens here. This used to move
                    // the camera as well, on the reasoning that a country
                    // finishing its load is a reasonable moment to look at it
                    // — and five countries finish at five different moments,
                    // so the map jumped five times over the first seconds of a
                    // launch and ended framing all of them. Where the map opens
                    // is a question about the reader's rides, not about which
                    // package decoded last; it is answered once, at launch, by
                    // `RailMapController.frameAtLaunch`.
                    let region = networkExtent ?? MapProjection.region(covering: lines)
                    let controller = self.controller
                    DispatchQueue.main.async { controller?.fitRegion = region }
                }

                if linesChanged || stationsChanged {
                    refreshLineInputs()
                }
                if linesChanged || stationsChanged || ridesChanged {
                    prepareStrokeReferences()
                }

                let selectedRide = rides.first { $0.id == selectedTrainID }
                let selectionRegion = selectedRide.flatMap { MapProjection.region(covering: $0.strokes) }
                let controller = self.controller
                // Only an explicit selection request can move the camera.
                // The controller consumes it once across renderer replacements;
                // route loading, restored selections and edits only repaint.
                let focusRegion: MKCoordinateRegion?
                switch focusRequest?.target {
                case .journey(let id) where id == selectedTrainID:
                    focusRegion = selectionRegion
                case .date(let date) where date == selectedDate && selectedTrainID == nil:
                    focusRegion = MapProjection.region(covering: rides
                        .filter { $0.daySpan.date == date }.flatMap(\.strokes))
                default:
                    focusRegion = nil
                }
                if focusRequest != nil, focusRegion == nil {
                    // No delayed focus when route geometry finishes loading.
                    _ = controller?.takeAutoFocusRequest(matching: focusRequest)
                }
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView, self.mapView === mapView,
                        controller?.mapView === mapView else { return }
                    controller?.selectionRegion = selectionRegion
                    guard let focusRequest, let focusRegion,
                        controller?.isCurrentAutoFocus(focusRequest) == true,
                        controller?.isMapReady == true,
                        mapView.bounds.width > 1, mapView.bounds.height > 1,
                        self.playback?.isActive != true else { return }
                    // A replacement renderer may have observed the same
                    // request. Only the renderer that actually frames consumes it.
                    guard controller?.takeAutoFocusRequest(matching: focusRequest) == focusRequest
                    else { return }
                    controller?.fitIfNeeded(focusRegion)
                }

                // Loading network packages must not repeatedly rebuild the
                // reader's routes while that network layer is hidden. Five
                // regions arrive independently at launch; before this gate,
                // each arrival rebuilt every ride overlay on the main thread
                // even though none of the arriving geometry was visible.
                // `MapDrawChanges.plan` (RailPresentation) is the tested
                // dispatch rule. `showsNetwork`/`hasRides`/`hasContinuousLines`
                // feed its own `visibleNetworkChanged`/`strokeableNetworkChanged`
                // — see that type for why those two exist: the network layer
                // being visible does not stop a ride from slicing its own
                // stroke out of `lines`, so a continuous-stroke region's lines
                // arriving still has to move a ride's offset geometry even
                // while the network stays hidden.
                let changes = MapDrawChanges(
                    linesChanged: linesChanged,
                    stationsChanged: stationsChanged,
                    ridesChanged: ridesChanged,
                    selectionChanged: selectionChanged,
                    visibilityChanged: visibilityChanged,
                    indexesChanged: indexesChanged,
                    displayChanged: displayChanged,
                    routePaintOnly: routePaintOnly,
                    dateChanged: dateChanged,
                    namingChanged: namingChanged,
                    showsNetwork: showsNetwork,
                    hasRides: !rides.isEmpty,
                    hasContinuousLines: lines.contains(where: \.continuous)
                )
                switch changes.plan {
                case .none:
                    break
                case .paintOnly:
                    updateRidePaint(on: mapView)
                case .selectionOnly:
                    // Nothing rebuilds, paints or re-marks inside a run — see
                    // the long comment in `rebuildOwed(on:)` for why. So a
                    // hand-off during a run owes the same deferred rebuild it
                    // always did, invalidation included: the rebuild that pays
                    // the debt when the run ends must not be skipped by its
                    // own zoom-bucket guard.
                    if playback?.isActive == true, playbackLayer.lastSnapshot != nil {
                        rebuildOwed(on: mapView)
                    } else if !updateSelection(on: mapView) {
                        rebuildOwed(on: mapView)
                    }
                case .rebuild:
                    rebuildOwed(on: mapView)
                }
                if basemapChanged { updateBasemapVeil(on: mapView) }
            }

            /// The old full-rebuild branch, unchanged, extracted so the
            /// `.rebuild` dispatch and both of `.selectionOnly`'s slow cases —
            /// a hand-off during a run, and a fast path that cannot answer
            /// from cached state — share it.
            private func rebuildOwed(on mapView: MKMapView) {
                cancelGeometryPreparation()
                networkBuildState.invalidateGeometry()
                markerBuildContext = nil
                // Not during a run, for the reason `regionDidChangeAnimated`
                // gives — and this is the path that actually hurt. The
                // transport moves the selection from journey to journey as
                // it plays (`ContentView`'s `onChange(of:playback.currentTrainID)`),
                // so `selectionChanged` was true at every hand-off and every
                // hand-off ran the whole rebuild: 150–460 ms of main-thread
                // work over Japan, in the middle of a 60 Hz chase, which
                // tore the mounted playback trail and its beads off the map
                // and remounted them a fifth of a second later. The dot
                // vanishing and reappearing at each new train is that.
                //
                // The build state's zoom bucket is cleared above whether or not the
                // rebuild is deferred, so the one `renderPlayback(nil)`
                // pays afterwards is not skipped by its own zoom-bucket
                // guard when a run ends at the zoom it started from.
                // `isActive` as well as a mounted snapshot: an ENDED run
                // keeps its last frame on the map until the reader presses
                // stop, and deferring through that would leave an edit made
                // from the list undrawn with nothing on screen to explain
                // it. A rebuild that does happen settles any debt owed from
                // earlier in the run, so the flag cannot outlive the reason
                // for it.
                if playback?.isActive == true, playbackLayer.lastSnapshot != nil {
                    rebuildDeferredByPlayback = true
                } else {
                    rebuildDeferredByPlayback = false
                    rebuild(on: mapView)
                }
            }

            /// Everything about one ride that changes what is DRAWN for it.
            ///
            /// The stops and the day-span signature are here because they are
            /// inputs: the stops decide which dots exist and what role each
            /// carries, and the day span decides where the cross-day diamond
            /// lands and which segments dash. Before those were read, a ride
            /// edited into a different stop list with the same geometry would
            /// have kept its old markers.
            ///
            /// The stops are digested rather than counted. A count answers
            /// "were any added or removed", which is not the question — turning
            /// `ride_segment` off for one call, or making a stop a
            /// pass-through, changes which dots are drawn and how without
            /// changing how many stops there are. This is the second gate an
            /// edit has to pass (the first is `ContentView.routeLoadKey`), and
            /// a gate that only counts holds the reloaded ride back at exactly
            /// the edits the reload existed to show.
            static func rideSignature(_ ride: RiddenRouteStore.DrawnRide) -> String {
                "\(ride.id):\(ride.geometryDigest):\(ride.colorHex):\(ride.visible ? 1 : 0)"
                    + ":\(ride.trainType ?? ""):\(stopsDigest(ride.stops)):\(ride.daySpan.sig)"
            }

            /// Whether two arrays are the same immutable generation.
            /// `Array` is copy-on-write, so a store mutation moves to another
            /// buffer while an unchanged value handed through SwiftUI keeps
            /// this address. Empty arrays are the same generation for render
            /// purposes regardless of their sentinel pointer.
            private static func sharesStorage<Element>(
                _ left: [Element], _ right: [Element]
            ) -> Bool {
                guard left.count == right.count else { return false }
                guard !left.isEmpty else { return true }
                return left.withUnsafeBufferPointer { leftBuffer in
                    right.withUnsafeBufferPointer { rightBuffer in
                        UnsafeRawPointer(leftBuffer.baseAddress!)
                            == UnsafeRawPointer(rightBuffer.baseAddress!)
                    }
                }
            }

            /// Compare collection generations without allocating parallel id
            /// arrays. A count change is already a complete answer, which is
            /// the common case while regional packages stream in at launch.
            private static func changed<Element, Identity: Equatable>(
                _ next: [Element], from current: [Element],
                id: KeyPath<Element, Identity>
            ) -> Bool {
                guard next.count == current.count else { return true }
                guard !sharesStorage(next, current) else { return false }
                return !zip(next, current).allSatisfy {
                    $0[keyPath: id] == $1[keyPath: id]
                }
            }

            /// The stops, as the one number the signature needs.
            ///
            /// `Hasher` rather than a joined string: this runs for every ride
            /// on every `updateUIView`, and a national store is 201 journeys of
            /// twenty-odd calls each. Seeded per process, which is all that is
            /// asked of it — the comparison is always between two values read
            /// in the same run.
            private static func stopsDigest(_ stops: [Stop]) -> Int {
                var hasher = Hasher()
                hasher.combine(stops.count)
                for stop in stops {
                    hasher.combine(stop.name)
                    hasher.combine(stop.stopType)
                    hasher.combine(stop.rideSegment)
                    hasher.combine(stop.arrival)
                    hasher.combine(stop.departure)
                    hasher.combine(stop.n02StationCode)
                }
                return hasher.finalize()
            }

            /// The reader's date scope, as the paint rules read it.
            private var dateScope: MapDateScope.Scope {
                MapDateScope.Scope(
                    date: selectedDate, dimOpacity: display.dimOpacity,
                    showFullCrossDay: display.showFullCrossDay)
            }

            /// A station name and its reading sublines, in the reader's
            /// language.
            struct Named: Sendable {
                var display: String
                var readings: [Localization.Reading]
            }

            /// `stationNameReadings(name, code)` — the ONE spelling of the
            /// display rule, resolved through the app's localisation engine.
            ///
            /// `MainActor.assumeIsolated` rather than a pre-resolved table.
            /// Japan ships 10,217 stations and a `UIViewRepresentable` has
            /// nowhere to memoise a table of them without changing the view's
            /// initialiser, which `ContentView` calls — so the table would be
            /// rebuilt on every SwiftUI update, which is far more work than
            /// the handful of lookups a rebuild actually makes.
            ///
            /// The assumption is sound and it is checkable: every path into
            /// this coordinator is a main-thread callback. `makeUIView` and
            /// `updateUIView` are `@MainActor` by `UIViewRepresentable`'s own
            /// declaration, MapKit delivers every `MKMapViewDelegate` message
            /// on the main thread, `PlaybackController` is `@MainActor` and so
            /// is everything it calls `renderPlayback` from, and the tap and
            /// trait-change callbacks are UIKit's own.
            ///
            /// The `code` is not optional decoration: `stationReadingRow`
            /// tries it BEFORE the name, and same-named stations are common
            /// enough that dropping it annotates the wrong one.
            /// A station's name and readings, as the reader's language
            /// spells them.
            ///
            /// `region` is not redundant with `code`. A NETWORK station's id
            /// is the package's (`tw-alsr-alishan:tw-official-…`) and names
            /// its own region; a JOURNEY's stop carries the operator's code
            /// (`TYMC-A13`), which names none, and would otherwise be answered
            /// by Japan's table — which annotates instead of replacing, so the
            /// name would come back untouched. Callers that hold a ride pass
            /// its region. See `StationNaming.swift`.
            func localized(
                _ name: String, code: String? = nil, region: Region? = nil
            ) -> Named {
                guard !name.isEmpty, let localization else {
                    return Named(display: name, readings: [])
                }
                return MainActor.assumeIsolated {
                    Named(
                        display: localization.stationName(
                            name, code: code, region: region),
                        readings: localization.nameReadingsTyped(
                            name, code: code, region: region))
                }
            }

            /// Keep mounted layers while the camera moves. A cancellable settle
            /// task coalesces gesture, inertia, resize and data-arrival rebuilds.
            private var cameraRebuildTask: Task<Void, Never>?
            private var lastCameraChange: ContinuousClock.Instant?

            /// Cancel work and release bridges installed by this coordinator when
            /// SwiftUI replaces the map during a composition or window-size change.
            /// A replacement map may already own the shared controllers by the time
            /// dismantling runs, so shared hooks are cleared only while they still
            /// identify this coordinator or this exact map view.
            func tearDown(_ dismantledMapView: MKMapView) {
                cameraRebuildTask?.cancel()
                cameraRebuildTask = nil
                viewportResizeTask?.cancel()
                viewportResizeTask = nil
                matchingTask?.cancel()
                matchingTask = nil
                matchingRevision += 1
                pendingStrokeRefs = nil
                cancelGeometryPreparation()
                markerBuildContext = nil
#if DEBUG
                gestureFrameProbe.stop()
                renderStatus = nil
#endif

                if let viewportMapView = dismantledMapView as? ViewportMapView {
                    viewportMapView.onSizeChange = nil
                }
                manipulationSensors.removeAll()
                if dismantledMapView.delegate === self {
                    dismantledMapView.delegate = nil
                }
                if mapView === dismantledMapView {
                    mapView = nil
                }
                if controller?.mapView === dismantledMapView {
                    controller?.mapView = nil
                }
                if let playback, playback.mapRenderer === self {
                    playback.mapRenderer = nil
                    playback.mapRendererViewSize = nil
                    playback.drawnCoordinates = nil
                }
                controller = nil
                playback = nil
                localization = nil
            }

            private func scheduleCameraRebuild(on mapView: MKMapView) {
                cameraRebuildTask?.cancel()
                cameraRebuildTask = Task { @MainActor [weak self, weak mapView] in
                    do { try await Task.sleep(for: .milliseconds(120)) }
                    catch { return }
                    guard let self, let mapView else { return }
                    self.cameraRebuildTask = nil
                    guard !self.isManipulating else {
                        self.rebuildDeferredByGesture = true
                        return
                    }
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                        return
                    }
                    self.rebuildDeferredByGesture = false
                    self.restyle(on: mapView)
                    self.rebuild(on: mapView)
                }
            }

            func viewportSizeChanged(on mapView: MKMapView) {
                cancelGeometryPreparation()
                playback?.mapRendererViewSize = mapView.bounds.size
                // Wait for live resizing to settle; do not rebuild overlays
                // recursively from UIKit's layout pass.
                viewportResizeTask?.cancel()
                viewportResizeTask = Task { @MainActor [weak self, weak mapView] in
                    do { try await Task.sleep(for: .milliseconds(120)) }
                    catch { return }
                    guard let self, let mapView else { return }
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                    } else if self.isManipulating {
                        self.rebuildDeferredByGesture = true
                    } else {
                        self.rebuild(on: mapView)
                    }
                    self.layoutEndpointLabels(on: mapView)
                }
            }

            private func networkVisibility(on mapView: MKMapView) -> NetworkVisibilityPolicy {
                NetworkVisibilityPolicy(
                    width: Double(mapView.bounds.width), height: Double(mapView.bounds.height))
            }

            func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
#if DEBUG
                if isManipulating {
                    let now = ContinuousClock.now
                    panCallbacks += 1
                    if let lastPanCallback {
                        maxPanCallbackGapMilliseconds = max(maxPanCallbackGapMilliseconds,
                            (now - lastPanCallback).milliseconds)
                    }
                    lastPanCallback = now
                } else {
                    lastPanCallback = nil
                }
#endif
                // Wheel, inertia and the first MapKit camera callback can
                // precede a touch sensor. Keep mounted styles stable for all
                // camera motion; the quiet-period task applies the final scale.
                // Screen-space work: these labels de-overlap each other and
                // clamp to the window's edges, so a label clamped at the right
                // edge stayed clamped after a pan carried it into the middle.
                layoutEndpointLabels(on: mapView)
                lastCameraChange = .now
                cancelGeometryPreparation()
                scheduleCameraRebuild(on: mapView)
            }


            func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
                // Not while the reader is still moving the map.
                //
                // This callback is documented as the SETTLED region, and during
                // a pinch MapKit sends it several times anyway — once per pause
                // in the fingers, near enough. Each one that crosses a zoom
                // tier ran the whole rebuild, and a rebuild is 150–460 ms of
                // main-thread work (measured over Japan with the network on):
                // decimating every eligible line, rebuilding every overlay and
                // re-adding every annotation. Three of those inside one pinch
                // is three freezes while the fingers are still moving, and it
                // is the larger half of why the map lagged them.
                //
                // Deferring costs the LOD tier a moment: lines the new zoom
                // admits appear when the fingers lift rather than during the
                // gesture. The strokes already drawn keep being drawn and keep
                // their installed styles until motion settles, so what
                // the reader loses is detail arriving late — against a map that
                // stopped following them, which is what the report was.
                if playbackLayer.lastSnapshot != nil {
                    // The chase moves the camera every display-link frame.
                    // The retained strokes still restyle continuously; a
                    // national LOD rebuild waits until playback releases the
                    // camera instead of interrupting it every padded rect.
                    rebuildDeferredByPlayback = true
                } else if isManipulating {
                    rebuildDeferredByGesture = true
                } else {
                    scheduleCameraRebuild(on: mapView)
                }
                // MapKit can report this while a wheel or inertial camera move
                // is still running. Styling shares the quiet-period task too.
                layoutEndpointLabels(on: mapView)
                // The compass needle tracks the map continuously, so heading is
                // reported on every region change rather than only on rebuilds —
                // a rotation that does not cross a zoom bucket rebuilds nothing.
                let heading = mapView.camera.heading
                let mode = mapView.userTrackingMode
                DispatchQueue.main.async { [controller] in
                    controller?.mapDidChange(heading: heading, trackingMode: mode)
                }
            }

            func mapView(
                _ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool
            ) {
                let heading = mapView.camera.heading
                DispatchQueue.main.async { [controller] in
                    controller?.mapDidChange(heading: heading, trackingMode: mode)
                }
            }

            // MARK: - building

            /// Light/dark flipped. The zoom bucket has not changed, so the normal
            /// guard would skip the rebuild — clear it first, or the map keeps the
            /// previous palette until the reader happens to zoom.
            func appearanceChanged(on mapView: MKMapView) {
                annotationsNeedRefresh = true
                networkBuildState.invalidateZoomBucket()
                rebuild(on: mapView)
            }

            /// Basemap dimming is one polygon, not a reason to rebuild every
            /// railway and station mounted above it.
            private func updateBasemapVeil(on mapView: MKMapView) {
                if basemapOpacity >= 0.999 {
                    if let basemapVeil { mapView.removeOverlay(basemapVeil) }
                    basemapVeil = nil
                    return
                }
                let alpha = 1 - min(max(basemapOpacity, 0), 1)
                if let basemapVeil, mapView.overlays.contains(where: { $0 === basemapVeil }) {
                    if let renderer = mapView.renderer(for: basemapVeil) as? BasemapVeilRenderer {
                        renderer.veilColor = Self.veilColor(alpha: alpha, on: mapView)
                        renderer.setNeedsDisplay()
                    }
                    return
                }
                // The whole world, not the loaded network's bounds: the veil
                // used to follow `builtRect`, so with the network switched off
                // (the default) it covered nothing, and panning past the
                // network showed an undimmed edge.
                let veil = BasemapVeilOverlay()
                basemapVeil = veil
                // Under the railways, which mount at `.aboveLabels`.
                mapView.addOverlay(veil, level: .aboveRoads)
            }

            /// Black in both appearances: lowering the basemap's opacity DIMS it
            /// in light mode too, rather than washing it out toward white, so
            /// the rail colours keep their contrast either way.
            private static func veilColor(alpha: Double, on mapView: MKMapView) -> CGColor {
                UIColor.black.withAlphaComponent(alpha).cgColor
            }

            private var geometryPreparation: Task<Void, Never>?
            private var geometryPreparationID = UUID()
            private var geometryPreparationKey: String?

            private func cancelGeometryPreparation() {
                guard geometryPreparation != nil else { return }
                geometryPreparation?.cancel()
                geometryPreparation = nil
                geometryPreparationKey = nil
                geometryPreparationID = UUID()
            }

            /// Prepare immutable line geometry on a worker. Only the current camera/data
            /// generation may publish; MapKit's mounted overlays stay usable meanwhile.
            private func prepareNetworkGeometry(
                on mapView: MKMapView, zoom: Double, visibilityZoom: Double, buildRect: MKMapRect
            ) -> Bool {
                let scale = MapProjection.quantised(RailStyle.scale(atZoom: zoom), on: mapView)
                let rawScale = MapProjection.mapPointsPerScreenPoint(of: mapView)
                let mapScale = exp2((log2(rawScale) * 1_000_000).rounded() / 1_000_000)
                // Preparation can be cancelled. Only installed geometry may
                // advance the hysteresis bucket used by shouldRebuild.
                let laneLOD = networkBuildState.previewLaneLOD(at: zoom)
                let key = "\(mapScale)|\(scale)|\(laneLOD.scale)"
                if geometryPreparation != nil, geometryPreparationKey != key {
                    cancelGeometryPreparation()
                }
                networkGeometry.beginFrame(key: key)
                let selected = showsNetwork
                    ? NetworkLOD.select(from: lines, zoom: visibilityZoom, buildRect: buildRect).lines
                        .filter { !$0.continuous || $0.intervalRects.contains { $0.intersects(buildRect) } }
                    : []
                var needed = Set(selected.filter(\.continuous).map(\.id))
                let rideRect = buildRect.insetBy(dx: -256 * mapScale, dy: -256 * mapScale)
                if layers.routes {
                    for ride in rides where ride.visible {
                        let flags = MapRideMarkers.rideFlags(ride.stops)
                        for segment in ride.segments {
                            guard segment.boundingRect.intersects(rideRect),
                                  draws(segment: segment, of: ride, riddenStops: flags),
                                  let ref = strokeRef(for: segment, of: ride) else { continue }
                            needed.insert(ref.chainID)
                        }
                    }
                }
                let byID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let missingLines = selected.filter { !networkGeometry.hasLineBuild(for: $0.id) }
                let missingStrokes = needed.compactMap { id -> RailNetworkStore.DrawnLine? in
                    guard !networkGeometry.hasStrokeBuild(for: id) else { return nil }
                    guard let line = byID[id],
                          line.intervalRects.contains(where: { $0.intersects(buildRect) }) else { return nil }
                    return line
                }
                guard !missingLines.isEmpty || !missingStrokes.isEmpty else { return true }
                guard geometryPreparation == nil else { return false }
                let anchors = lineInputs.mapValues(\.anchors)
                let cachedStrokes = networkGeometry.preparedStrokes
                let requestID = UUID()
                geometryPreparationID = requestID
                geometryPreparationKey = key
                let worker = Task.detached(priority: .userInitiated) {
                    try MapLineGeometry.prepare(
                        lines: missingLines, strokes: missingStrokes, allLines: byID,
                        anchors: anchors, cachedStrokes: cachedStrokes,
                        mapScale: mapScale, scale: scale, laneScale: laneLOD.scale)
                }
                geometryPreparation = Task { @MainActor [weak self, weak mapView] in
                    let result = await withTaskCancellationHandler {
                        try? await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled, let self, let mapView,
                          self.geometryPreparationID == requestID else { return }
                    self.geometryPreparation = nil
                    self.geometryPreparationKey = nil
                    guard let geometry = result else { return }
                    let prepared = MapLineGeometry.materialize(geometry)
                    guard self.networkGeometry.storePrepared(prepared, key: key) else { return }
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                        return
                    }
                    self.rebuild(on: mapView)
                }
                return false
            }

            private func rebuild(on mapView: MKMapView) {
                if isManipulating || lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) == true {
                    rebuildDeferredByGesture = true
                    scheduleCameraRebuild(on: mapView)
                    return
                }
                // Keep the route mapping and its installed pixels in one
                // generation, including when a worker finishes during playback.
                if playback?.isActive != true, let pending = pendingStrokeRefs {
                    pendingStrokeRefs = nil
                    if pending.revision == matchingRevision {
                        strokeRefCache = pending.refs
                        matchedLineInputs = pending.inputs
                        networkGeometry.clearRidePolylines()
                        cachedTapIndex = nil
                        markerCache = nil
                        selectedNameCache = nil
                        networkBuildState.invalidateZoomBucket()
                    }
                }
                // With both layers absent there is nothing to build. Hiding the
                // complete network does not hide the reader's routes.
                guard showsNetwork || !rides.isEmpty else {
                    mapView.removeOverlays(mapView.overlays(in: .aboveLabels))
                    updateBasemapVeil(on: mapView)
                    if !networkAnnotations.isEmpty { mapView.removeAnnotations(networkAnnotations) }
                    networkAnnotations = []
                    if !rideStationAnnotations.isEmpty {
                        mapView.removeAnnotations(rideStationAnnotations)
                    }
                    rideStationAnnotations = []
                    if !endpointAnnotations.isEmpty { mapView.removeAnnotations(endpointAnnotations) }
                    endpointAnnotations = []
                    networkBuildState.invalidateGeometry()
                    networkGeometry.resetFrameStrokes()
                    markerBuildContext = nil
                    cachedTapIndex = nil
#if DEBUG
                    renderStatus?.text = "network:off;lines:0;overlays:0;backbones:0;networkStations:0"
#endif
                    return
                }

                // Before the first layout pass the view has no width, and the
                // zoom derived from it is nonsense — it was reading z = -8 and
                // culling every line. Wait for a real size. An empty geometry
                // array is NOT a reason to return: the build rect computed
                // below is the request that loads the first display network.
                // Returning before `onBuildRect` made the complete network
                // permanently blank for a reader with no recorded journeys.
                guard mapView.bounds.width > 1 else { return }

                let zoom = MapProjection.zoomLevel(of: mapView)
                let visibilityPolicy = networkVisibility(on: mapView)
                let visibilityZoom = visibilityPolicy.visibilityZoom(cameraZoom: zoom)
                let visibilityBucket = visibilityPolicy.visibilityBucket(cameraZoom: zoom)
                // Every LOD and label floor is an integer in its own scale.
                // Camera and railway eligibility share the same scale on
                // every viewport; both buckets cross the same integer floors.
                // `rounded()`
                // rebuilt half a level before the floor, then did nothing when
                // the camera actually crossed it; a z14 caption could therefore
                // wait until z14.5 to appear. Flooring changes the bucket at the
                // same boundary as the visibility rule itself.
                let visibleRect = mapView.visibleMapRect
                // Rebuild when the zoom tier changes, or when the map has been
                // panned past what was built for. Panning within the padded rect
                // is free, which is what keeps the gesture smooth.
                // A continuous stroke's own screen-space geometry — lane
                // rows, jog taper, corner rounding — is exactly as
                // zoom-sensitive as a laned line's parallel offset, even at
                // `lane == 0`: it is what a ride's own bead and sliced
                // stroke are read off of, so it has to refresh on the same
                // pinch-settle trigger a laned line already does.
                let hasLanedLines = lines.contains(where: { $0.lane != 0 || $0.continuous })
                guard networkBuildState.shouldRebuild(
                    zoom: zoom,
                    visibilityBucket: visibilityBucket,
                    viewportSize: mapView.bounds.size,
                    hasLanedLines: hasLanedLines,
                    visibleRect: visibleRect
                ) else { return }
                let buildRect = NetworkLOD.buildRect(for: visibleRect)
                onBuildRect(buildRect, visibilityZoom)
                guard prepareNetworkGeometry(
                    on: mapView, zoom: zoom, visibilityZoom: visibilityZoom, buildRect: buildRect
                ) else { return }
                networkBuildState.commit(
                    zoom: zoom,
                    visibilityBucket: visibilityBucket,
                    viewportSize: mapView.bounds.size,
                    builtRect: buildRect
                )
                // A cold display-network request has no geometry to build
                // yet. Its result changes `lines`, invalidates the build state in
                // `update`, and returns through this method with the region's
                // continuous geometry.
                guard !lines.isEmpty || !rides.isEmpty else { return }

#if DEBUG
                rebuildCount += 1
                if isManipulating { rebuildsDuringGesture += 1 }
#endif
                let started = ContinuousClock.now
                let rebuildInterval = RailSignpost.map.begin("map.rebuild")
                defer { RailSignpost.map.end("map.rebuild", rebuildInterval) }

                // Geometry is already prepared off actor. This phase selects
                // cached chunks for the viewport and applies the vertex budget.
                let geometryInterval = RailSignpost.map.begin("map.rebuild.geometry")

                // What is eligible: near enough to be seen, important enough for
                // this zoom. See NetworkLOD — that policy is deliberately stricter
                // than the web app's at low zoom, and deliberately outside the
                // ported tier, because there is no JavaScript to check it against.
                let selection = showsNetwork
                    ? NetworkLOD.select(from: lines, zoom: visibilityZoom, buildRect: buildRect)
                    : nil

                let buildScale = MapProjection.quantised(
                    RailStyle.scale(atZoom: zoom), on: mapView)
                let rawMapScale = MapProjection.mapPointsPerScreenPoint(of: mapView)
                let mapPointsPerScreenPoint = exp2((log2(rawMapScale) * 1_000_000).rounded() / 1_000_000)
                // How far apart a continuous stroke's parallel lanes sit at
                // this zoom — a hub packed with lanes at a city view would be
                // just as packed zoomed out to a national one if the gap
                // never shrank. `LaneLOD` carries the bucket forward itself
                // so a pinch idling on a boundary does not reopen and re-close
                // the gap every rebuild; the hub/lane rows this scales are
                // untouched.
                let laneLOD = networkBuildState.resolveLaneLOD(at: zoom)

                // The per-interval cull, and it is what lets the map hold a
                // railway whole. `NetworkLOD.select` has already dropped the
                // lines whose whole extent is off screen; a transcontinental
                // corridor passes that test from one coast while the camera
                // sits on the other, and without this every interval of it
                // would be decimated, laned and handed to MapKit to draw the
                // handful that are visible. The rects are precomputed beside
                // the geometry (`DrawnLine.intervalRects`), so the test is one
                // rectangle intersection per stroke rather than a walk over
                // its vertices. Cheapest first: reject before decimating.
                // The platforms of every continuous stroke, by the stroke's
                // id, so the stroke can carry them along and the dots below
                // can be placed on the offset stroke rather than beside it.
                var strokeAnchors: [String: [Int: CLLocationCoordinate2D]] = [:]
                // Replaced whole, not merged: only chains prepared for this
                // frame may back route drawing and hit testing.
                networkGeometry.resetFrameStrokes()
                // Every resident line by stroke id, for the canonical chains
                // a follow names — resident, not merely selected, because a
                // canonical stroke may be culled while its tenant is drawn.
                let linesByStrokeID = Dictionary(
                    lines.filter(\.continuous).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                // The continuous chains a visible ride's own segments resolve
                // against (``strokeRef(for:of:)``) — built for the ride below
                // even when the line itself is culled by LOD, off by zoom, or
                // the whole network layer is hidden (`showsNetwork` starts
                // `false`), so a ride still draws on the network's own offset
                // pixels while the network it shares them with stays
                // invisible. A segment 已乘路線顯示 has switched off is
                // skipped here too — its own bead and stroke draw nothing, so
                // forcing its chain built would cost a build for geometry
                // nothing on screen reads.
                // The pad covers screen-space lane offsets and rounded corners.
                let rideBuildRect = buildRect.insetBy(dx: -256 * mapPointsPerScreenPoint,
                    dy: -256 * mapPointsPerScreenPoint)
                let frameKey = "\(mapPointsPerScreenPoint)|\(buildScale)|\(laneLOD.scale)"
                networkGeometry.beginFrame(key: frameKey)
                var neededStrokeLineIDs: Set<String> = []
                if layers.routes {
                    for ride in rides where ride.visible {
                        let riddenStops = MapRideMarkers.rideFlags(ride.stops)
                        for segment in ride.segments {
                            guard segment.boundingRect.intersects(rideBuildRect),
                                draws(segment: segment, of: ride, riddenStops: riddenStops),
                                let ref = strokeRef(for: segment, of: ride)
                            else { continue }
                            neededStrokeLineIDs.insert(ref.chainID)
                        }
                    }
                }
                // Withheld dashed runs (see `ContinuousStrokeBuild.withheldRuns`),
                // by the drawn line's id — collected here rather than read back
                // off the frame-stroke cache below, because that cache only holds
                // ONE build per chain id and a ride's own need for it
                // (`neededStrokeLineIDs`) must not be confused with the
                // network actually drawing that chain this frame.
                var withheldRunsByLineID:
                    [String: [(colorHex: String, colorDarkHex: String, coordinates: [Coordinate])]] = [:]
                let builds: [LineBuild] = (selection?.lines ?? []).compactMap { line in
                    guard let cached = networkGeometry.lineBuild(for: line.id) else { return nil }
#if DEBUG
                    lineCacheHits += 1
#endif
                    if line.continuous {
                        guard let stroke = networkGeometry.strokeBuild(for: line.id) else { return nil }
                        strokeAnchors[line.id] = stroke.anchors
                        networkGeometry.storeStroke(
                            (stroke: stroke.stroke, mapPointsPerScreenPoint: mapPointsPerScreenPoint),
                            for: line.id)
                        withheldRunsByLineID[line.id] = stroke.withheldRuns
                    }
                    return cached.intersecting(buildRect)
                }.filter { !$0.polylines.isEmpty || !$0.familyPolylines.isEmpty }

                // A needed chain the LOD/budget pass above never reached —
                // culled, below its own zoom floor, or the whole network
                // layer switched off — is still built here, purely for the
                // ride that names it. Never added to `builds`/the overlay: it
                // is not a line the network draws this frame, only pixels a
                // ride slices.
                for id in neededStrokeLineIDs where !networkGeometry.containsStroke(for: id) {
                    guard let line = linesByStrokeID[id],
                        line.intervalRects.contains(where: { $0.intersects(buildRect) })
                    else { continue }
                    guard let stroke = networkGeometry.strokeBuild(for: line.id) else { continue }
                    strokeAnchors[line.id] = stroke.anchors
                    networkGeometry.storeStroke(
                        (stroke: stroke.stroke,
                         mapPointsPerScreenPoint: mapPointsPerScreenPoint),
                        for: line.id)
                }
                // The frame-stroke cache just moved — a stale tap index would score a
                // ride against last frame's pixel geometry. See
                // ``drawnCoordinates(of:)`` and ``tapIndex()``.
                cachedTapIndex = nil

                // The budget is applied to what decimation actually produced, not
                // to the stored vertex count. Budgeting on the raw count cut a
                // national view of Japan from 262 lines to 7, by weighing 394,285
                // stored vertices against a budget meant for the ~12,000 drawn.
                let fitted = NetworkLOD.fitToBudget(builds, zoom: visibilityZoom)
                let visible = fitted.kept.map(\.line)
                RailSignpost.map.end("map.rebuild.geometry", geometryInterval)

                // One palette or the other, chosen once per rebuild rather than
                // per line: mixing them would be a map half in each mode.
                let dark = mapView.traitCollection.userInterfaceStyle == .dark

                var byColor: [String: [MKPolyline]] = [:]
                var colors: [String: UIColor] = [:]
                var vertices = 0
                // Withheld dashed runs, grouped by EACH RUN's own colour key
                // (`ContinuousStrokeBuild.withheldRuns` — ordinarily this
                // line's, but a family colour where the span falls inside a
                // landlord family window) and only for a line that survived
                // the LOD/budget cull above — a chain the network decided
                // not to draw this frame must not have its bridged span
                // drawn either.
                var withheldByColor: [String: [MKPolyline]] = [:]
                for build in fitted.kept {
                    let key = dark ? build.line.colorDarkHex : build.line.colorHex
                    colors[key] = UIColor(dark ? build.line.colorDark : build.line.color)
                    byColor[key, default: []].append(contentsOf: build.polylines)
                    vertices += build.drawnVertexCount
                    // Landlord family-window polylines: one MKMultiPolyline
                    // per distinct colour already exists (`byColor` below),
                    // so a family colour simply joins that same grouping
                    // under its own hex key rather than a new overlay class.
                    for (_, family) in build.familyPolylines {
                        let familyKey = dark ? family.colorDarkHex : family.colorHex
                        colors[familyKey] = colors[familyKey]
                            ?? UIColor(Color(hex: familyKey) ?? .accentColor)
                        byColor[familyKey, default: []].append(contentsOf: family.polylines)
                    }
                    for run in withheldRunsByLineID[build.line.id] ?? [] {
                        guard run.coordinates.count >= 2 else { continue }
                        let runKey = dark ? run.colorDarkHex : run.colorHex
                        colors[runKey] = colors[runKey]
                            ?? UIColor(Color(hex: runKey) ?? .accentColor)
                        let coordinates = run.coordinates.map(\.clLocation)
                        withheldByColor[runKey, default: []].append(
                            MKPolyline(coordinates: coordinates, count: coordinates.count))
                    }
                }

                // The scale this build's marks are sized for. One factor, read
                // once, handed to every weight below — see RailStyle. Rounded
                // by the same rule `restyle` rounds by, so a mark built here
                // and a mark rescaled there are never a fraction of a pixel
                // apart.
                let scale = buildScale
                styledScale = scale
                styledMarkZoom = (zoom * 16).rounded() / 16

                // The transport owns its overlays separately from the base
                // layers reconciled below; re-mount its snapshot afterwards.
                playbackLayer.clear(on: mapView)
                let teardown = RailSignpost.map.begin("map.rebuild.teardown")
                let overlayReconciliation = overlayInstaller.reconciliation(on: mapView)
                var desiredOverlays: [MKOverlay] = []
                if let basemapVeil { mapView.removeOverlay(basemapVeil) }
                basemapVeil = nil
                if annotationsNeedRefresh {
                    mapView.removeAnnotations(networkAnnotations + rideStationAnnotations)
                    networkAnnotations = []
                    rideStationAnnotations = []
                    annotationsNeedRefresh = false
                }
                if !endpointAnnotations.isEmpty { mapView.removeAnnotations(endpointAnnotations) }
                endpointAnnotations = []
                RailSignpost.map.end("map.rebuild.teardown", teardown)
                // `.aboveRoads` is what keeps the veil UNDER every rail
                // layer, which all mount at `.aboveLabels`: a level is
                // ordered before insertion order is, so the slider can add
                // this after a rebuild has already drawn the railways and
                // still not dim them. It is also why the base map's labels
                // stay full-strength while its roads fade — they are drawn
                // above this level, and 底圖不透明度 is a control over the
                // map behind the railways, not over their labelling.
                updateBasemapVeil(on: mapView)
                let networkOverlays = RailSignpost.map.begin("map.rebuild.networkOverlays")
                let overlays = overlayInstaller.networkOverlays(
                    byColor: byColor, withheldByColor: withheldByColor,
                    colors: colors, dark: dark,
                    reconciliation: overlayReconciliation)
                desiredOverlays.append(contentsOf: overlays)
                RailSignpost.map.end("map.rebuild.networkOverlays", networkOverlays)

                // A ride's stroke: the seed weight, the reader's 線路粗細
                // multiplier, the focus boost when it is the selected one, and
                // then RIDDEN_WIDTH_SCALE — in that order, because the boost is a
                // width the reader chose and not a proportion of one.
                func rideWidthToken(selected: Bool) -> CGFloat {
                    let seed = RailStyle.riddenWidth * CGFloat(display.routeWidthScale)
                    let focused = selected ? CGFloat(display.focusBoost) : 0
                    return (seed + focused) * RailStyle.riddenWidthScale
                }
                // The two scopes a ride's stroke answers to, both ported in
                // `MapDateScope`: the SELECTION spotlight, and the DATE scope
                // the reader set on the ride list. `dimOpacity` finally has a
                // subject — an off-date ride draws faint rather than
                // disappearing, which is what makes the slider a control over
                // something.
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let scope = dateScope
                func rideAlpha(_ ride: RiddenRouteStore.DrawnRide, selected: Bool) -> CGFloat {
                    MapDateScope.alpha(
                        own: CGFloat(display.riddenOpacity), span: ride.daySpan,
                        scope: scope, isSelected: selected, hasSelection: hasSelection)
                }

                let rideOverlayInterval = RailSignpost.map.begin("map.rebuild.rideOverlays")
                var rideCasings: [MKMultiPolyline] = []
                var rideOverlays: [MKMultiPolyline] = []
                // 列車路線 off draws no route lines and leaves every station
                // dot alone — `RailMap.setVisible` moves the route, cross-day,
                // hover and selection layers and no marker layer at all.
                let orderedRides = layers.routes
                    ? rides.sorted { left, right in
                        left.id != selectedTrainID && right.id == selectedTrainID
                    }
                    : []
                for ride in orderedRides {
                    // Split by the calendar day each SEGMENT runs on, which is
                    // why the strokes are taken from `segments` rather than
                    // from `strokes`: `Dates.segmentDate` needs the segment's
                    // own index and the flattened list has thrown it away.
                    var solid: [MKPolyline] = []
                    var crossDay: [MKPolyline] = []
                    let riddenStops = MapRideMarkers.rideFlags(ride.stops)
                    for segment in ride.segments {
                        // 已乘路線顯示: a segment whose category the reader has
                        // switched off is not drawn. Per SEGMENT rather than
                        // per journey, because that is the granularity the web
                        // app classifies at — a 新幹線 run with a metro leg on
                        // the end loses the leg, not the run.
                        guard segment.boundingRect.intersects(rideBuildRect),
                            draws(segment: segment, of: ride, riddenStops: riddenStops)
                        else { continue }
                        // The network's own offset pixels, sliced to this
                        // segment's own measures, when its `StrokeRef` names a
                        // chain built this frame — see ``drawnCoordinates(of:)``.
                        // Whether this segment is drawn from the network's
                        // own rounded stroke pixels or from its raw surveyed
                        // coordinates decides its epsilon, exactly as
                        // `line.continuous` does for the network above: only
                        // the former has already been decimated (inside
                        // `buildStroke`, BEFORE its corners were rounded), and
                        // running the pass below over it again would strip
                        // every shallow fillet back to the chord it replaced.
                        // A segment that fell back to `segment.coordinates` —
                        // a survey region, or a chain no line built this frame
                        // — is surveyed geometry and owes its own metre tolerance.
                        let usesStroke = strokeRef(for: segment, of: ride).map {
                            networkGeometry.containsStroke(for: $0.chainID)
                        } ?? false
                        let key = "\(ride.id)|\(ride.geometryDigest)|\(segment.segmentIndex)."
                            + "\(segment.partIndex)|\(usesStroke)"
                        let polyline: MKPolyline
                        if let cached = networkGeometry.ridePolyline(for: key) {
                            polyline = cached
                        } else {
                            let built = builtStrokeCoordinates(of: segment, ride: ride)
                            let stroke = asCoordinates(built ?? segment.coordinates.map(\.clLocation))
                            guard stroke.count >= 2 else { continue }
                            let latitude = MKMapPoint(x: segment.boundingRect.midX,
                                y: segment.boundingRect.midY).coordinate.latitude
                            let epsilon = built == nil ? MKMetersPerMapPointAtLatitude(latitude)
                                * mapPointsPerScreenPoint * RailStyle.simplifyTolerance : 0
                            let kept = Geometry.douglasPeuckerIndices(stroke, epsilonMeters: epsilon)
                            let points = kept.map { stroke[$0].clLocation }
                            guard points.count >= 2 else { continue }
                            polyline = MKPolyline(coordinates: points, count: points.count)
                            networkGeometry.storeRidePolyline(polyline, for: key)
                        }
                        if MapDateScope.isCrossDayContinuation(
                            ride.daySpan, segmentIndex: segment.segmentIndex, scope: scope) {
                            crossDay.append(polyline)
                        } else {
                            solid.append(polyline)
                        }
                    }
                    guard !solid.isEmpty || !crossDay.isEmpty else { continue }
                    let selected = ride.id == selectedTrainID
                    let color = UIColor(railHex: ride.colorHex) ?? .systemBlue
                    let width = rideWidthToken(selected: selected)
                    let alpha = rideAlpha(ride, selected: selected)

                    // Same source, same colour, same width — only the stroke
                    // pattern says "not this day" (`TRAIN_XDAY_LAYER`).
                    for (suffix, polylines, dashed) in [
                        ("ride", solid, false), ("ride-xday", crossDay, true),
                    ] where !polylines.isEmpty {
                        let styleKey = "\(suffix)|\(ride.id)"
                        let multi = overlayReconciliation.multiPolyline(polylines, key: styleKey)
                        overlayStyles[styleKey] = .init(
                            color: color, widthToken: width, alpha: alpha, dashed: dashed)
                        rideOverlays.append(multi)

                        // §10.5: a selection has to change more than a colour.
                        // The casing is a dark halo UNDER the selected line,
                        // 0.7 pt per side at full scale — Apple's restrained
                        // selected-transit outline rather than a glow — and it
                        // rides the same ramp, or "selected" would read
                        // differently at every zoom. It follows the dash too:
                        // a solid casing under a dashed core would fill the
                        // gaps back in and undo the distinction.
                        guard selected else { continue }
                        let casingKey = "\(suffix)-casing|\(ride.id)"
                        let casing = overlayReconciliation.multiPolyline(polylines, key: casingKey)
                        overlayStyles[casingKey] = .init(
                            // `MAP_SURFACE_COLORS[theme].casing`, the same two
                            // values the web app's selection halo uses.
                            color: UIColor(railHex: dark ? "#F5EEE9" : "#1A1A1A") ?? .label,
                            widthToken: width + RailStyle.selectionCasingEdge * 2,
                            alpha: 0.9,
                            dashed: dashed
                        )
                        rideCasings.append(casing)
                    }
                }
                // Casings first so the coloured cores land on top of them.
                // Both above the base map's labels, for the reason the
                // network's strokes are.
                desiredOverlays.append(contentsOf: rideCasings)
                desiredOverlays.append(contentsOf: rideOverlays)
                overlayInstaller.install(
                    desiredOverlays, replacing: overlayReconciliation,
                    scale: scale, on: mapView)
                RailSignpost.map.end("map.rebuild.rideOverlays", rideOverlayInterval)
                let context = MarkerBuildContext(
                    zoom: zoom, visibilityZoom: visibilityZoom, scale: scale,
                    buildRect: buildRect, strokeAnchors: strokeAnchors, visible: visible)
                markerBuildContext = context
                buildMarkers(context, on: mapView)
                playbackLayer.repaint(on: mapView)

                let elapsed = ContinuousClock.now - started
#if DEBUG
                // Debug builds only, and that is not tidiness.
                //
                // This sits on the map REBUILD path — every pan that crosses a
                // LOD threshold, every zoom step, every ride edit — and `NSLog`
                // is synchronous: it formats, takes a lock, writes to the
                // unified log AND to stderr, on the main thread, before the
                // frame it belongs to can be presented. Seven of these fire in
                // the first second of launch alone.
                //
                // Nothing is lost by gating it. The same numbers are handed
                // back as `RenderStats` immediately below, which is what the
                // diagnostics panel in Settings reads — so the data has a
                // supported in-app home on every build, and this line is only
                // the console mirror of it.
                // "off", not "0", when the complete network is switched off.
                //
                // The count and the reason for it are different facts, and this
                // line reported only the count: a map with the network layer
                // off — which is how the app STARTS, `showsNetwork` defaults to
                // false — printed `lines=0/804` on every pan, which reads as
                // eight hundred lines being dropped by the LOD rule. The
                // difference between "nothing qualified" and "nobody asked" is
                // the whole diagnostic value of the field.
                let drawnLines = showsNetwork ? "\(visible.count)" : "off"
                NSLog(
                    "railmap: z=%.2f lod=%.2f thr=%.1f lines=%@/%d (culled %d) overlays=%d vertices=%d "
                        + "stations=%d ridedots=%d ridelabels=%d %dms",
                    zoom, visibilityZoom, fitted.threshold, drawnLines, lines.count,
                    selection?.culledOffScreen ?? 0,
                    overlays.count + rideOverlays.count + rideCasings.count,
                    vertices,
                    networkAnnotations.count,
                    rideStationAnnotations.filter { $0 is RideStationAnnotation }.count,
                    rideStationAnnotations.filter { $0 is RideLabelAnnotation }.count,
                    elapsed.milliseconds)
#endif
                // Deferred: a rebuild can be triggered from inside updateUIView,
                // and writing SwiftUI state during a view update is undefined
                // behaviour — in practice the panel simply never showed the
                // numbers. Hand them back on the next turn of the loop instead.
                let stats = RenderStats(
                    zoom: zoom,
                    visibilityZoom: visibilityZoom,
                    visibleLines: visible.count,
                    overlays: overlays.count + rideOverlays.count + rideCasings.count,
                    vertices: vertices,
                    buildMilliseconds: elapsed.milliseconds,
                    culledOffScreen: selection?.culledOffScreen ?? 0,
                    threshold: fitted.threshold
                )
#if DEBUG
                let networkState = !showsNetwork
                    ? "off"
                    : (visible.isEmpty || overlays.isEmpty ? "empty" : "rendered")
                // Measure inside the app: XCTest's map accessibility snapshot
                // can take longer than the render itself. Include region
                // loading, but freeze at the first submitted network frame.
                if networkState == "rendered", firstNetworkRenderMilliseconds == nil,
                   let networkEnabledAt {
                    firstNetworkRenderMilliseconds = Double((ContinuousClock.now - networkEnabledAt).milliseconds)
                }
                renderStatus?.text =
                    "network:\(networkState);lines:\(visible.count);overlays:\(overlays.count)"
                    + ";rides:\(rides.count)"
                    + ";budgetDrops:\(builds.count - fitted.kept.count);vertices:\(vertices)"
                    + String(format: ";camera:%.2f;lod:%.2f", zoom, visibilityZoom)
                    + ";backbones:\(Set(visible.filter { $0.lodMinZoom < 0 }.map(\.lineID)).count)"
                    + ";networkStations:\(networkAnnotations.count)"
                    + String(format: ";distance:%.1f", mapView.camera.centerCoordinateDistance)
                    + String(format: ";heading:%.1f", mapView.camera.heading)
                    + String(format: ";centerLat:%.4f;centerLon:%.4f", mapView.centerCoordinate.latitude, mapView.centerCoordinate.longitude)
                    + String(format: ";viewportWidth:%.1f;viewportHeight:%.1f", mapView.bounds.width, mapView.bounds.height)
                    + String(format: ";firstNetworkMs:%.1f", firstNetworkRenderMilliseconds ?? -1)
                    + ";rebuilds:\(rebuildCount);gestureBuilds:\(rebuildsDuringGesture)"
                    + ";cacheHits:\(lineCacheHits);annotationReuses:\(annotationReuses)"
                    + ";panCallbacks:\(panCallbacks);panMaxGapMs:\(maxPanCallbackGapMilliseconds)"
                    + ";gestureFrames:\(gestureFrameProbe.frames);gestureMaxFrameGapMs:\(Int(gestureFrameProbe.maximumGapMilliseconds))"
                    + ";buildMs:\(elapsed.milliseconds);covered:\(networkBuildState.builtRect.contains(mapView.visibleMapRect) ? 1 : 0)"
#endif
                DispatchQueue.main.async { [onRender] in onRender(stats) }
            }

            private func buildMarkers(_ context: MarkerBuildContext, on mapView: MKMapView) {
                let zoom = context.zoom
                let visibilityZoom = context.visibilityZoom
                let scale = context.scale
                let buildRect = context.buildRect
                let strokeAnchors = context.strokeAnchors
                let visible = context.visible
                let markerInterval = RailSignpost.map.begin("map.rebuild.markers")
                // Recomputed rather than cached: derived only from coordinator
                // state (`rides`, `selectedTrainID`, `dateScope`, `stations`,
                // `lines`), not from geometry the last rebuild produced.
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let scope = dateScope
                let stationsByPlace = Dictionary(grouping: stations) {
                    "\($0.region.rawValue)|\($0.stationCode)"
                }
                let linesByStrokeID = Dictionary(
                    lines.filter(\.continuous).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                // Retain unchanged station/ride annotations and their mounted
                // views. Reconcile only after label placement is resolved below.
                var desiredNetworkAnnotations: [MKAnnotation] = []

                // One place, one name.
                //
                // Three things on this map name stations — an endpoint card, a
                // ride's own caption beside its dot, and the network's own
                // label — and each used to decide alone, so a station that was
                // all three printed its name three times: 我孫子 on the card,
                // 我孫子 beside the dot, 我孫子 again from the network under
                // them. They are ranked rather than merged, most specific
                // first: the card, which also carries the time; then the
                // journey's caption; then the network's. Whichever reaches a
                // place first claims it and the rest stay quiet.
                //
                // A "place" is a name within `labelMergeMeters` of a name, not
                // a coordinate — 東京's JR and Metro platforms are hundreds of
                // metres apart and both name the same place, which is the rule
                // the two label ELECTIONS already merge on
                // (`StationDisplay.markerLabelWinners`). Comparing coordinates
                // would leave exactly those pairs doubled.
                var namedPlaces: [String: [Coordinate]] = [:]
                func canClaimName(_ name: String, at position: Coordinate) -> Bool {
                    let key = Stations.normalizeStationName(name)
                    guard !key.isEmpty else { return false }
                    return !(namedPlaces[key]?.contains(where: {
                        Geometry.distanceMeters($0, position) <= Self.labelMergeMeters
                    }) ?? false)
                }
                func claimName(_ name: String, at position: Coordinate) -> Bool {
                    let key = Stations.normalizeStationName(name)
                    guard canClaimName(name, at: position) else { return false }
                    namedPlaces[key, default: []].append(position)
                    return true
                }

                // The cards are built here, ahead of every dot, because they
                // hold the first claim on a name. They are still ADDED last,
                // where they always were.
                let endpointSpecList = endpointSpecs()
                for spec in endpointSpecList {
                    _ = claimName(spec.rawName, at: spec.coordinate)
                }

                // MapKit cannot simultaneously keep JTM labels above Apple's
                // basemap labels and thin them against one another. Reserve the
                // endpoint cards first, then admit the remaining station names
                // through our own screen-space collision grid in importance
                // order. Projection makes this naturally density-aware: as the
                // reader zooms in, stations separate and more names fit.
                var labelCollisions = MapLabelCollisionGrid()
                var placedEndpointSpecs = endpointSpecList
                let endpointPoints = placedEndpointSpecs.map {
                    mapView.convert($0.coordinate.clLocation, toPointTo: mapView)
                }
                MapEndpointLabels.layout(&placedEndpointSpecs, at: endpointPoints)
                for index in placedEndpointSpecs.indices {
                    let point = endpointPoints[index]
                    MapEndpointLabels.clampHorizontally(
                        &placedEndpointSpecs[index], at: point,
                        containerWidth: mapView.bounds.width)
                    let offset = MapEndpointLabels.centreOffset(
                        for: placedEndpointSpecs[index])
                    let size = CGSize(
                        width: placedEndpointSpecs[index].width,
                        height: placedEndpointSpecs[index].height)
                    _ = labelCollisions.insertIfClear(CGRect(
                        x: point.x + offset.x - size.width / 2,
                        y: point.y + offset.y - size.height / 2,
                        width: size.width, height: size.height))
                }

                // 選了一條線路之後，站名只屬於它 — and that cannot be had by
                // filtering the deck-wide election by `tid`. A station two
                // rides both call at hands its name to whichever record
                // arrived first (`markerLabelWinners` resolves ties by
                // arrival), so filtering afterwards would leave the selected
                // ride unnamed at exactly its busiest stations. The election is
                // re-run over that ride's own records instead.
                var selectedRideNames: Set<String> = []
                if let ride = rides.first(where: { $0.id == selectedTrainID }) {
                    selectedRideNames = namedRecordKeys(of: ride, settings: display.markers)
                }

                // Every visible ride's calls, flattened into the deck marker
                // records `RailCore.StationDisplay` already knows how to elect
                // names for. Not just the selected ride's: the election exists
                // because a station reached by twenty trains ships twenty records
                // that all know the same name, and only one of them may print it.
                let drawn = markerRecords(for: rides, settings: display.markers)
                // A journey every one of whose ridden segments is switched off
                // by category loses its station dots with its line. Its beads
                // would otherwise be left floating over a route that is not
                // drawn, which reads as a fault rather than as a filter.
                //
                // The web app decides this per STATION, from the line
                // attributes its own station dataset repeats on every station
                // (`markerCategoryForStation`). The ride markers here are
                // built from the journey's stops, which carry no such
                // attributes, so the decision is made at the journey's
                // granularity instead: a dot is kept whenever any part of the
                // line it sits on is still drawn.
                var fullyHiddenRides: Set<String> = []
                if layers.categories.anyHidden {
                    for ride in rides {
                        let riddenStops = MapRideMarkers.rideFlags(ride.stops)
                        let ridden = ride.segments.filter {
                            Statistics.isRideSegment(
                                riddenStops, segmentIndex: $0.segmentIndex)
                        }
                        guard !ridden.isEmpty,
                            ridden.allSatisfy({
                                !draws(segment: $0, of: ride, riddenStops: riddenStops)
                            })
                        else { continue }
                        fullyHiddenRides.insert(ride.id)
                    }
                }
                // Every marker record names its ride only by `feature.tid`
                // (== `ride.id`); the sliced-stroke bead fallback below needs
                // the ride itself, to find the segment `item.strokeAnchor`
                // names and slice it. Built once rather than searched per
                // marker.
                let ridesByID = Dictionary(
                    rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                // Each role has its own floor: terminals and cross-day breaks
                // at every zoom, intermediate stops from `STOP_MIN_ZOOM`, the
                // numerous pass-throughs only from `PASSTHROUGH_MIN_ZOOM`. So
                // pulling back sheds pass-throughs first and stops second,
                // while a ride's two ends — the whole of what it says at a
                // national view — never leave.
                var markerAnnotations: [MKAnnotation] = []
                var pendingRideLabels: [(
                    claimName: String, position: Coordinate,
                    annotation: RideLabelAnnotation, importance: Int
                )] = []
                var lastEmitted: RideStationAnnotation?
                for item in drawn {
                    let record = item.record
                    let feature = item.feature
                    // 中途停靠站 / 端點站 / 通過站, and the categories above.
                    // `lastEmitted` is cleared on the way out so a dropped
                    // dot's coloured core cannot land inside the previous dot.
                    guard layers.draws(role: feature.role),
                        !fullyHiddenRides.contains(feature.tid) else {
                        lastEmitted = nil
                        continue
                    }
                    guard MapRideMarkers.drawsDot(item, atZoom: zoom)
                            || feature.role == "stop-center" else {
                        lastEmitted = nil
                        continue
                    }
                    if feature.role == "stop-center" {
                        // MapKit draws one view per annotation, so the call core
                        // goes INSIDE the dot it sits in rather than on a second
                        // annotation at the same point — two annotations one point
                        // apart would fight the collision pass over a mark that is
                        // not even pickable. The record is still emitted, so the
                        // record set and its indices stay the web app's.
                        lastEmitted?.core = RideStationAnnotation.Core(
                            radius: CGFloat(feature.radius),
                            focusScale: CGFloat(feature.focusScale),
                            // A small route-coloured centre distinguishes an
                            // actual call from a pass-through without bringing
                            // the old heavy black bullseye back.
                            color: UIColor(railHex: item.routeColorHex) ?? .systemBlue)
                        continue
                    }
                    lastEmitted = nil
                    // Three tiers, same fallback order the network's own
                    // station dots take (`strokeAnchors[...] ??
                    // parallelStationCoordinate(...)`, below): the platform
                    // anchor this boundary snapped to, in THIS frame's offset
                    // pixels; failing that (the boundary is a plain
                    // interpolation on open track, or the anchor's own chain
                    // was not built this frame), the sliced stroke's own
                    // endpoint — never the un-offset canonical point, which
                    // would put a "snapped" bead visibly off the line it
                    // shares an anchor with; and only when the segment never
                    // resolved a chain at all, the plain drawn coordinate.
                    let displayCoordinate: CLLocationCoordinate2D
                    if let anchor = item.strokeAnchor {
                        if let vertexIndex = anchor.vertexIndex,
                            let point = strokeAnchors[anchor.chainID]?[vertexIndex] {
                            displayCoordinate = point
                        } else if let ride = ridesByID[feature.tid],
                            let segment = ride.segments.first(where: {
                                $0.segmentIndex == anchor.segmentIndex
                                    && $0.partIndex == anchor.partIndex
                            }) {
                            let sliced = drawnCoordinates(of: segment, ride: ride)
                            displayCoordinate =
                                (anchor.isSegmentStart ? sliced.first : sliced.last)
                                ?? record.position.clLocation
                        } else {
                            displayCoordinate = record.position.clLocation
                        }
                    } else {
                        displayCoordinate = record.position.clLocation
                    }
                    guard buildRect.contains(MKMapPoint(displayCoordinate)) else { continue }
                    let selected = feature.tid == selectedTrainID
                    let routeColor = UIColor(railHex: item.routeColorHex) ?? .systemBlue
                    let prominent = feature.role == "terminal" || feature.role == "xday"
                    let annotation = RideStationAnnotation(
                        coordinate: displayCoordinate,
                        name: feature.name,
                        rawName: record.name,
                        stationCode: item.stationCode,
                        region: item.region,
                        role: feature.role,
                        radius: CGFloat(feature.radius),
                        lineWidth: CGFloat(feature.lineWidth),
                        ordinaryRadius: CGFloat(display.markers.passRadius),
                        ordinaryLineWidth: CGFloat(MapRideMarkers.ringWidth(
                            1, settings: display.markers)),
                        focusScale: CGFloat(feature.focusScale),
                        // Apple Maps' route hierarchy: ordinary calls are
                        // light beads edged by the route, while the two ends
                        // invert that pair and become solid route-colour
                        // anchors. The cross-day diamond shares the prominent
                        // palette but retains its non-circular semantics.
                        fill: prominent ? routeColor : .white,
                        stroke: prominent ? .white : routeColor,
                        // The record's OWN alpha, put through the same two
                        // scopes the ride's stroke goes through — a dot on an
                        // off-date ride dims with the line it sits on.
                        alpha: CGFloat(feature.alpha) * MapDateScope.alpha(
                            own: 1, span: item.daySpan, scope: scope,
                            isSelected: selected, hasSelection: hasSelection),
                        focusBoost: CGFloat(display.focusBoost),
                        selected: selected)
                    markerAnnotations.append(annotation)
                    lastEmitted = annotation
                    // …and its name, if it won one and the view is wide enough for
                    // its tier. Each floor is a hard gate rather than a fade,
                    // because a zero-opacity label would still hold its space in
                    // the collision pass and silently suppress a name that IS
                    // shown — the finding recorded on `RideLabelTier`.
                    //
                    // Which election answers depends on whether the reader has
                    // chosen a journey: with none chosen the deck-wide one
                    // does, and with one chosen only that ride's own names are
                    // drawn at all — every other journey's captions and the
                    // whole network's labels go quiet, so what is left on the
                    // map is the chosen line and the stations along it.
                    let labelName = hasSelection
                        ? (selected && selectedRideNames.contains(Self.markerKey(record))
                            ? record.name : "")
                        : feature.name
                    guard !labelName.isEmpty, let tier = annotation.labelTier,
                          zoom >= RailStyle.zoom(fromMapLibre: Double(tier.minZoom))
                    else { continue }
                    // The election runs on the package's own names — see
                    // `markerRecords` — and only the winner is translated, so
                    // which record carries a name never depends on the
                    // reader's language.
                    let label = RideLabelAnnotation(
                        coordinate: annotation.coordinate,
                        text: localized(
                            labelName, code: item.stationCode, region: item.region).display,
                        rawName: record.name, stationCode: item.stationCode,
                        region: item.region,
                        tier: tier,
                        dotRadiusToken: annotation.drawnRadiusToken(atZoom: zoom),
                        selected: annotation.selected)
                    pendingRideLabels.append((
                        claimName: labelName, position: record.position,
                        annotation: label,
                        // A lower floor means a rarer, more important role:
                        // terminals before stops before pass-through stations.
                        importance: (annotation.selected ? 1_000 : 0) - tier.minZoom))
                }
                pendingRideLabels.sort {
                    if $0.importance != $1.importance {
                        return $0.importance > $1.importance
                    }
                    return $0.annotation.text.localizedStandardCompare(
                        $1.annotation.text) == .orderedAscending
                }
                for candidate in pendingRideLabels {
                    guard canClaimName(candidate.claimName, at: candidate.position) else {
                        continue
                    }
                    let item = candidate.annotation
                    let textSize = CGFloat(item.tier.textSize(
                        atZoom: RailStyle.mapLibreZoom(from: zoom)))
                    let measured = (item.text as NSString).size(withAttributes: [
                        .font: MapLabelStyle.font(ofSize: textSize),
                    ])
                    let width = min(190, ceil(measured.width))
                        + MapLabelStyle.haloWidth * 2
                    let height = max(ceil(measured.height), 16)
                    let point = mapView.convert(item.coordinate, toPointTo: mapView)
                    let box = CGRect(
                        x: point.x + item.dotRadiusToken * scale
                            + textSize * MapLabelStyle.radialOffsetEm,
                        y: point.y - height / 2,
                        width: width, height: height)
                    guard labelCollisions.insertIfClear(box),
                          claimName(candidate.claimName, at: candidate.position)
                    else { continue }
                    markerAnnotations.append(item)
                }

                // The network's own station names come LAST, after every name
                // the reader's journeys have already claimed — which is why
                // this block moved down here from above the ride markers. It
                // is the most general of the three sources and therefore the
                // one that yields: a station on a journey is named by the
                // journey, and the network names everything else.
                //
                // `layers.networkStations` is read UNDER `showsNetwork` rather
                // than beside it: with the network off there is no line for a
                // station to sit on, so the dots go with it either way.
                if showsNetwork, layers.networkStations {
                    // A dot goes on the map only where the line it belongs to
                    // is on the map. `DrawnStation.lodMinZoom` is the station's
                    // own threshold raised to its line's, in THIS app's zoom
                    // (`NetworkLOD`) — the package's own number is a MapLibre
                    // one and reading it against this zoom fired a level early,
                    // which at a city view was not a subtlety: jp drew 3,963
                    // dots where the web app draws 348.
                    //
                    // The drawn set is consulted as well as the threshold, and
                    // it is not the same question: the threshold says the line
                    // is eligible at this zoom, the set says it was actually
                    // built. The two part company when the vertex budget binds
                    // and `fitToBudget` sheds branches — which is precisely
                    // when a stranded dot would be least explicable.
                    let drawnLineIDs = Set(visible.map(\.lineID))
                    // The measure a continuous-stroke station's own anchor
                    // sits at, on its chain's own ruler — the same one
                    // `DrawnLine.familyWindows`/`laneRows`/`totalMetres` are
                    // measured on (`ChainPixelCache` re-derives it from plain
                    // WGS84 coordinates, so it does not depend on this
                    // frame's pixel scale).
                    func anchorMeasure(
                        region: Region, lineID: String, slot: RailNetworkStore.StrokeSlot
                    ) -> (line: RailNetworkStore.DrawnLine, measure: Double)? {
                        guard let line = linesByStrokeID["\(region.rawValue)|\(lineID)#\(slot.chain)"]
                        else { return nil }
                        guard let measures = networkGeometry.strokeBuild(for: line.id)?.sourceMeasures
                        else { return nil }
                        guard slot.anchor >= 0, slot.anchor < measures.count else { return nil }
                        return (line, measures[slot.anchor])
                    }
                    // A tenant window (`RailNetworkStore.DrawnLine.
                    // FamilyWindow`, role 1) withholds THIS line's own
                    // stroke there — the shared family stroke a landlord
                    // sibling draws stands for it instead. Its bead mirrors
                    // that, by one rule (documented here in full so the web
                    // agent can mirror the exact predicate — see
                    // `$SP/family/bead-rule.md`):
                    //   (a) the station's own anchor measure lies inside one
                    //       of its line's tenant windows;
                    //   (b) a same-family sibling line — same `stationCode`,
                    //       same region, different `lineID` — holds a
                    //       LANDLORD window of the SAME group covering that
                    //       sibling's own anchor at this station; AND
                    //   (c) that sibling's bead is ITSELF drawn right now —
                    //       the same `lodMinZoom`/`buildRect`/drawn-line gate
                    //       `visibleStations` applies below, not merely "its
                    //       line is on screen somewhere" — so the platform is
                    //       never silently dropped when the landlord's own
                    //       bead is off screen, off by LOD, or shed by the
                    //       vertex budget even while its line otherwise
                    //       draws elsewhere.
                    // When (a)+(b)+(c) all hold, EVERY tenant member of the
                    // group is suppressed at that station — the landlord's
                    // own bead stands for the platform.
                    //
                    // When (a) holds but no drawn landlord bead of the group
                    // exists at that station (an express landlord with no
                    // stop there, a local-only tenant pair, or the landlord
                    // simply off screen), the platform must still show
                    // exactly one bead: the tenant with the lowest `lineID`
                    // (plain `String` order) among every tenant member of the
                    // SAME group stopping at the SAME physical station keeps
                    // its bead; every other tenant member there is
                    // suppressed — so two-or-more tenants at one physical
                    // stop never draw duplicate dots, and the stop is never
                    // left bare either.
                    func isDrawn(_ candidate: RailNetworkStore.DrawnStation) -> Bool {
                        candidate.lodMinZoom <= visibilityZoom
                            && drawnLineIDs.contains(candidate.lineID)
                            && buildRect.contains(MKMapPoint(candidate.coordinate.clLocation))
                    }
                    func tenantGroupID(_ candidate: RailNetworkStore.DrawnStation) -> String? {
                        guard let slot = candidate.slot,
                              let (line, measure) = anchorMeasure(
                                region: candidate.region, lineID: candidate.lineID, slot: slot)
                        else { return nil }
                        return line.familyWindows.first(where: {
                            !$0.isLandlord && $0.from <= measure && measure <= $0.to
                        })?.groupID
                    }
                    func isSuppressedTenantBead(_ station: RailNetworkStore.DrawnStation) -> Bool {
                        guard let group = tenantGroupID(station) else { return false }
                        let siblings = stationsByPlace["\(station.region.rawValue)|\(station.stationCode)"] ?? []
                        let landlordDrawn = siblings.contains { sibling in
                            guard sibling.stationCode == station.stationCode,
                                  sibling.region == station.region,
                                  sibling.lineID != station.lineID,
                                  isDrawn(sibling),
                                  let siblingSlot = sibling.slot,
                                  let (siblingLine, siblingMeasure) = anchorMeasure(
                                      region: sibling.region, lineID: sibling.lineID,
                                      slot: siblingSlot)
                            else { return false }
                            return siblingLine.familyWindows.contains {
                                $0.isLandlord && $0.groupID == group
                                    && $0.from <= siblingMeasure && siblingMeasure <= $0.to
                            }
                        }
                        if landlordDrawn { return true }
                        let lowestTenantLineID = siblings
                            .filter { sibling in
                                sibling.stationCode == station.stationCode
                                    && sibling.region == station.region
                                    && tenantGroupID(sibling) == group
                                    && isDrawn(sibling)
                            }
                            .map(\.lineID)
                            .min()
                        return station.lineID != lowestTenantLineID
                    }
                    let visibleStations = stations.compactMap { station -> (
                        key: String, station: RailNetworkStore.DrawnStation,
                        displayName: String, readings: [String]?
                    )? in
                        guard station.lodMinZoom <= visibilityZoom else { return nil }
                        let point = MKMapPoint(station.coordinate.clLocation)
                        guard buildRect.contains(point) else { return nil }
                        guard drawnLineIDs.contains(station.lineID) else { return nil }
                        guard !isSuppressedTenantBead(station) else { return nil }
                        // `buildStationPopupModel` keys its readings on the
                        // platform's OWN id (`lineId:stationId`), which the
                        // four localised-name tables carry alongside the
                        // official code; Japan's table has neither, and falls
                        // through to the by-name lookup exactly as it does in
                        // the web app.
                        let named = self.localized(station.name, code: station.id)
                        return (
                            key: "\(station.region.rawValue)|\(station.lineID)|\(station.id)",
                            station: station, displayName: named.display,
                            readings: self.localization == nil
                                ? nil : named.readings.map(\.text))
                    }

                    // The network is the broadest naming layer, so it fills the
                    // spaces left by endpoint cards and journey captions. Among
                    // its own candidates, Apple-style navigational hierarchy
                    // wins: interchanges, then line ends, then ordinary stops.
                    var acceptedStationNames: Set<String> = []
                    if layers.networkStationNames, !hasSelection,
                       zoom >= MapLabelStyle.stationLabelMinZoom {
                        let ordered = visibleStations.filter(\.station.showsLabel).sorted {
                            let left = $0.station.popup.lines.count > 1
                                ? 2 : ($0.station.isTerminal ? 1 : 0)
                            let right = $1.station.popup.lines.count > 1
                                ? 2 : ($1.station.isTerminal ? 1 : 0)
                            if left != right { return left > right }
                            return $0.key < $1.key
                        }
                        let textSize = MapLabelStyle.stationLabelSize(atZoom: zoom)
                        let font = MapLabelStyle.font(ofSize: textSize)
                        let diameter = max(1, RailStyle.stationDiameter * scale)
                        for candidate in ordered {
                            let station = candidate.station
                            guard canClaimName(station.name, at: station.coordinate) else {
                                continue
                            }
                            let measured = (candidate.displayName as NSString).size(
                                withAttributes: [.font: font])
                            let width = min(180, ceil(measured.width))
                                + MapLabelStyle.haloWidth * 2
                            let point = mapView.convert(
                                station.coordinate.clLocation, toPointTo: mapView)
                            let box = CGRect(
                                x: point.x + diameter / 2
                                    + textSize * MapLabelStyle.radialOffsetEm
                                    - MapLabelStyle.haloWidth,
                                y: point.y - 11,
                                width: width, height: 22)
                            guard labelCollisions.insertIfClear(box),
                                  claimName(station.name, at: station.coordinate)
                            else { continue }
                            acceptedStationNames.insert(candidate.key)
                        }
                    }

                    let stationAnnotations = visibleStations.map { candidate in
                        let station = candidate.station
                        return StationAnnotation(
                            station: station, displayName: candidate.displayName,
                            // The name switch is folded in HERE rather than in
                            // the view, so the annotation's display priority is
                            // computed from what will actually be printed. A
                            // dot that keeps a named station's priority while
                            // drawing no name wins collisions it should have
                            // lost, and the labels that do draw get thinned
                            // out around it.
                            //
                            // Two more conditions join it. A chosen journey
                            // takes the map's naming for itself, so the whole
                            // network goes unnamed while one is selected; and
                            // otherwise a name already claimed by a journey's
                            // own caption is not written a second time.
                            showsName: acceptedStationNames.contains(candidate.key),
                            // `nil` is the standalone case — no localisation
                            // engine at all — which is what keeps the single
                            // `nameRoma` subline. See `StationCardView`.
                            readings: candidate.readings,
                            displayCoordinate: station.slot.flatMap { slot in
                                strokeAnchors[
                                    "\(station.region.rawValue)|\(station.lineID)#\(slot.chain)"
                                ]?[slot.anchor]
                            } ?? nearestStrokeAnchorCoordinate(
                                for: station, in: strokeAnchors
                            ) ?? parallelStationCoordinate(
                                station.coordinate.clLocation,
                                lane: station.lane,
                                bearing: station.laneBearing,
                                scale: scale,
                                on: mapView))
                    }
                    desiredNetworkAnnotations = stationAnnotations
                }
#if DEBUG
                let oldAnnotationIDs = Set((networkAnnotations + rideStationAnnotations).map(ObjectIdentifier.init))
#endif
                networkAnnotations = MapAnnotationReconciler.reconcile(
                    desiredNetworkAnnotations, replacing: networkAnnotations, on: mapView)
                rideStationAnnotations = MapAnnotationReconciler.reconcile(
                    markerAnnotations, replacing: rideStationAnnotations, on: mapView)
#if DEBUG
                annotationReuses += (networkAnnotations + rideStationAnnotations).filter {
                    oldAnnotationIDs.contains(ObjectIdentifier($0))
                }.count
#endif
                // Retained views need the final zoom's sizing after a pinch.
                styledScale = .nan
                styledMarkZoom = .nan
                restyle(on: mapView)
                RailSignpost.map.end("map.rebuild.markers", markerInterval)

                // The selected ride's origin / destination cards, and — when a
                // day is in scope — that DAY's first origin and last
                // destination with a 起點/終點 badge, which is `updateEndpointLabels`
                // step (1). `computeScopedEndpoints` is not ported: the scoped
                // pair is derived here from the rides the map already holds.
                endpointAnnotations = endpointSpecList.map(EndpointLabelAnnotation.init)
                if !endpointAnnotations.isEmpty {
                    mapView.addAnnotations(endpointAnnotations)
                    layoutEndpointLabels(on: mapView)
                }
            }

            /// The marker records, built once per ride set rather than per pan.
            ///
            /// `buildDeckMarkerRecords` is documented SELECTION-INDEPENDENT and
            /// nothing in it reads the zoom, so the record set only changes with
            /// the rides and the 顯示調節 sizes — while `rebuild` also runs
            /// whenever the map is panned out of the rect it was built for. The
            /// name election walks every ride's every call, so re-running it on a
            /// pan would be the most expensive thing a pan does.
            private var markerCache:
                (key: Int, settings: MapRideMarkers.Settings, drawn: [MapRideMarkers.Drawn])?

            /// The tap cull's index — see ``RideTapIndex``.
            ///
            /// Built on the first tap after the rides move rather than in
            /// `update`, for two reasons. A launch, a sheet drag or a settings
            /// change that never ends in a tap should pay nothing for it. And
            /// `update` runs inside a SwiftUI pass, where a walk over every
            /// ridden vertex is precisely the work this index exists to keep
            /// out of the main thread's frame — paying it once, on a touch
            /// that is already going to change the selection, is the moment it
            /// costs least.
            private var cachedTapIndex: RideTapIndex?

            private func tapIndex() -> RideTapIndex {
                if let cachedTapIndex { return cachedTapIndex }
                let interval = RailSignpost.map.begin("map.tapIndex.build")
                defer { RailSignpost.map.end("map.tapIndex.build", interval) }
                let index = RideTapIndex(rides: rides, drawnStrokes: drawnStrokes)
                cachedTapIndex = index
                return index
            }

            /// The runs of one ride that are actually on the map.
            ///
            /// 已乘路線顯示 hides ridden line by CATEGORY, and it does so per
            /// segment — a 新幹線 run with a metro leg on the end loses the
            /// leg, not the run. The web app filters the same thing out of the
            /// source `renderTrainLayers` pushes, and the pick layer reads that
            /// source, so a stretch the reader has switched off is not clicked
            /// there either. The index used to be built from `ride.strokes`,
            /// which knows nothing about any of this: 地下鐵 off left every
            /// subway leg invisible and still selectable, which is the same
            /// complaint as a tap on a hidden ride and the same answer.
            ///
            /// A dropped run is handed back as an empty array rather than
            /// removed: `RideTapIndex` reads a stroke's position as the
            /// segment it came from, and a stroke of fewer than two points
            /// draws nothing and is skipped by both the chunker and
            /// ``RideTapResolver/hits(at:among:tolerance:)``.
            ///
            /// The whole geometry, unexamined, whenever no category is off —
            /// which is the state the app ships in, and `draws(segment:…)`
            /// would answer `true` for every segment anyway. That fast path is
            /// also what keeps `MapRideMarkers.rideFlags` off this path
            /// entirely until a filter is on.
            private func drawnStrokes(
                of ride: RiddenRouteStore.DrawnRide
            ) -> [[Coordinate]] {
                guard layers.categories.anyHidden else {
                    return ride.segments.map { asCoordinates(drawnCoordinates(of: $0, ride: ride)) }
                }
                let riddenStops = MapRideMarkers.rideFlags(ride.stops)
                return ride.segments.map { segment in
                    draws(segment: segment, of: ride, riddenStops: riddenStops)
                        ? asCoordinates(drawnCoordinates(of: segment, ride: ride)) : []
                }
            }

            /// Revalidate only the inputs a line build actually reads. A
            /// country arriving must not discard every other country's pixels.
            private func refreshLineInputs() {
                let byID = Dictionary(lines.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                var anchors: [String: [Int]] = [:]
                for station in stations {
                    guard let slot = station.slot else { continue }
                    anchors["\(station.region.rawValue)|\(station.lineID)#\(slot.chain)", default: []]
                        .append(slot.anchor)
                }
                var next: [String: LineInputs] = [:]
                for line in lines {
                    var dependencyIDs = line.follows.map(\.canonicalID)
                    if line.continuous, let hash = line.id.lastIndex(of: "#"),
                        let index = Int(line.id[line.id.index(after: hash)...]) {
                        let prefix = line.id[..<hash]
                        if index > 0 { dependencyIDs.append("\(prefix)#\(index - 1)") }
                        dependencyIDs.append("\(prefix)#\(index + 1)")
                    }
                    var dependencies: [String: UUID] = [:]
                    for id in dependencyIDs { dependencies[id] = byID[id]?.contentID }
                    next[line.id] = LineInputs(contentID: line.contentID,
                        anchors: anchors[line.id] ?? [], dependencies: dependencies)
                }
                let retainedIDs = Set(next.keys.filter { next[$0] == lineInputs[$0] })
                networkGeometry.retainLineBuilds(withIDs: retainedIDs)
                lineInputs = next
                cachedTapIndex = nil
            }

            /// This frame's continuous-stroke chains, in WGS84 — the geometry
            /// `RailCore.StrokeRide.resolve(segment:chains:)` matches a
            /// ride's own segment against. See ``strokeRef(for:of:)``.
            ///
            /// One entry per continuous `DrawnLine`: each already holds its
            /// own joined, unclipped chain (``joinedChainCoordinates(of:)``),
            /// which is the display network's own split — the same one the
            /// pixel build in `rebuild` projects — not the compact package's
            /// `RouteNetwork.Line.parts`, which a prior version of this
            /// wrongly matched against. Memoised on ``linesGeneration``, not
            /// rebuilt every frame: unlike the pixel geometry in
            /// the frame-stroke cache, none of this depends on zoom.
            /// Joining, indexing and matching operate on immutable snapshots.
            /// A newer input cancels the old worker; only its own revision may
            /// publish, including when a removed journey reused an ID.
            private func prepareStrokeReferences() {
                matchingTask?.cancel()
                pendingStrokeRefs = nil
                matchingRevision += 1
                let revision = matchingRevision
                let generation = linesGeneration
                let lines = self.lines
                let stations = self.stations
                let rides = self.rides
                let cached = strokeRefCache
                let inputs = lineInputs
                let prepared = preparedStrokeIndex?.generation == generation
                    ? preparedStrokeIndex?.index : nil
                let worker = Task.detached(priority: .userInitiated) {
                    let index: StrokeRide.Index
                    if let prepared {
                        index = prepared
                    } else {
                        var anchors: [String: [Int]] = [:]
                        for station in stations {
                            guard let slot = station.slot else { continue }
                            anchors["\(station.region.rawValue)|\(station.lineID)#\(slot.chain)", default: []]
                                .append(slot.anchor)
                        }
                        var chains: [ChainRef] = []
                        for line in lines where line.continuous {
                            try Task.checkCancellation()
                            let chain = joinedChainCoordinates(of: line)
                            chains.append(ChainRef(id: line.id, points: chain.points,
                                measures: chain.measures, anchors: anchors[line.id] ?? []))
                        }
                        index = StrokeRide.Index(chains: chains)
                    }
                    var results: [String: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])] = [:]
                    for ride in rides {
                        try Task.checkCancellation()
                        let key = "\(ride.id):\(ride.geometryDigest)"
                        if let entry = cached[ride.id], entry.geometryKey == key,
                            entry.linesGeneration == generation {
                            results[ride.id] = entry
                            continue
                        }
                        var refs: [String: StrokeRef] = [:]
                        for segment in ride.segments {
                            try Task.checkCancellation()
                            refs["\(segment.segmentIndex).\(segment.partIndex)"] =
                                index.resolve(segment: segment.coordinates)
                        }
                        results[ride.id] = (key, generation, refs)
                    }
                    return (index, results)
                }
                matchingTask = Task { [weak self] in
                    let result = await withTaskCancellationHandler {
                        try? await worker.value
                    } onCancel: { worker.cancel() }
                    guard !Task.isCancelled, let self, self.matchingRevision == revision,
                        let (index, results) = result else { return }
                    self.preparedStrokeIndex = (generation, index)
                    self.pendingStrokeRefs = (revision, results, inputs)
                    self.networkBuildState.invalidateZoomBucket()
                    if self.playback?.isActive == true, self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                    } else if self.isManipulating {
                        self.rebuildDeferredByGesture = true
                    } else if let map = self.mapView {
                        self.rebuild(on: map)
                    }
                }
            }

            /// Reads prepared results or a verified reference into an unchanged
            /// chain. Otherwise use the canonical route fallback; no UI entry
            /// point performs a cold match, including taps and playback markers.
            func strokeRef(
                for segment: RiddenRouteStore.DrawnSegment, of ride: RiddenRouteStore.DrawnRide
            ) -> StrokeRef? {
                guard let cached = strokeRefCache[ride.id],
                    cached.geometryKey == "\(ride.id):\(ride.geometryDigest)",
                    let ref = cached.refs["\(segment.segmentIndex).\(segment.partIndex)"] else { return nil }
                // While a new region is being matched, a reference into an
                // unchanged chain still uses the exact same measure space.
                // Missing/replaced chains and changed anchors must fall back.
                guard cached.linesGeneration == linesGeneration
                    || (lineInputs[ref.chainID] != nil
                        && lineInputs[ref.chainID] == matchedLineInputs[ref.chainID])
                else { return nil }
                return ref
            }

            /// The coordinates one ride segment is ACTUALLY drawn with: a
            /// continuous-stroke chain's own offset pixels
            /// (`ContinuousStroke.slice`) when the segment resolves against
            /// one of this frame's chains (``strokeRef(for:of:)``) AND that
            /// chain was built this frame, else the canonical slice
            /// `RiddenRouteStore` produced.
            ///
            /// Slicing the built stroke rather than redrawing
            /// `segment.coordinates` is what keeps a ridden segment on the
            /// same lane-offset, corner-rounded pixels the network itself
            /// draws — the two cannot part company on a corridor where the
            /// ride and the line share track. Used everywhere a ride's
            /// geometry reaches the map: the overlay loop, the tap index (via
            /// ``drawnStrokes(of:)``) and the playback snapshot.
            ///
            /// The frame-stroke cache holds the WHOLE chain, unclipped — see its own
            /// note — so a ride miles outside the current build rect still
            /// slices correctly; only a chain not built AT ALL this frame (no
            /// visible ride named it, and the line itself was culled) falls
            /// back to the plain slice.
            func drawnCoordinates(
                of segment: RiddenRouteStore.DrawnSegment, ride: RiddenRouteStore.DrawnRide
            ) -> [CLLocationCoordinate2D] {
                builtStrokeCoordinates(of: segment, ride: ride)
                    ?? segment.coordinates.map(\.clLocation)
            }

            /// The stroke half of ``drawnCoordinates(of:ride:)``, or nil where
            /// that method falls back to `segment.coordinates`.
            ///
            /// Split out so a caller can tell the two apart. The overlay loop
            /// has to: geometry sliced out of a built stroke is already
            /// decimated and must not be decimated again, and raw surveyed
            /// coordinates have not been and must be. Answering that by
            /// re-asking the same questions in a second place would be a copy
            /// free to drift; this is the one implementation, and
            /// `drawnCoordinates` is now its fallback.
            func builtStrokeCoordinates(
                of segment: RiddenRouteStore.DrawnSegment, ride: RiddenRouteStore.DrawnRide
            ) -> [CLLocationCoordinate2D]? {
                guard let ref = strokeRef(for: segment, of: ride),
                    let built = networkGeometry.stroke(for: ref.chainID)
                else { return nil }
                let sliced = ContinuousStroke.slice(
                    points: built.stroke.points, measures: built.stroke.measures,
                    from: ref.from, to: ref.to)
                guard sliced.count >= 2 else { return nil }
                return sliced.map {
                    MKMapPoint(
                        x: $0.x * built.mapPointsPerScreenPoint,
                        y: $0.y * built.mapPointsPerScreenPoint
                    ).coordinate
                }
            }

            /// `drawnCoordinates(of:ride:)` converted back to `RailCore.Coordinate`
            /// for the callers — the tap index and the Douglas–Peucker pass —
            /// that still work in that space.
            private func asCoordinates(_ points: [CLLocationCoordinate2D]) -> [Coordinate] {
                points.map { Coordinate(lon: $0.longitude, lat: $0.latitude) }
            }

            /// Whether one drawn segment's ridden-line category is switched on.
            ///
            /// Three ways to be visible without being classified, all of them
            /// the web app's: every category is on and nothing is classified
            /// at all; this region's edge index has not been built yet; or the
            /// index was consulted and none of the segment matched the
            /// network, which is undetermined rather than uncategorised.
            ///
            /// Only a RIDDEN section is filtered — `app-deck-records.js` reads
            /// `ride_segment === true` before it asks — so a stretch the
            /// reader travelled without riding keeps drawing whatever the
            /// checkboxes say.
            private func draws(
                segment: RiddenRouteStore.DrawnSegment,
                of ride: RiddenRouteStore.DrawnRide,
                riddenStops: [Statistics.Stop]
            ) -> Bool {
                guard layers.categories.anyHidden,
                    Statistics.isRideSegment(
                        riddenStops, segmentIndex: segment.segmentIndex)
                else { return true }

                let key = "\(ride.id)#\(segment.segmentIndex).\(segment.partIndex)"
                if let cached = segmentCategories[key] {
                    return cached.isEmpty || layers.categories[cached]
                }
                guard let index = categoryIndexes[ride.country] else { return true }
                let category = Statistics.riddenFeatureCategory(
                    Statistics.RouteFeature(
                        // Statistics and the edge index both remain WGS84;
                        // MapKit's GCJ-02 copy is presentation data only.
                        lines: [segment.sourceCoordinates], hasGeometry: true,
                        rideSegment: true, from: segment.from, to: segment.to),
                    index: index, country: ride.country)
                segmentCategories[key] = category ?? ""
                guard let category else { return true }
                return layers.categories[category]
            }

            private func markerRecords(
                for rides: [RiddenRouteStore.DrawnRide], settings: MapRideMarkers.Settings
            ) -> [MapRideMarkers.Drawn] {
                let key = Self.ridesDigest(rides)
                if let markerCache, markerCache.key == key, markerCache.settings == settings {
                    return markerCache.drawn
                }
                let drawn = MapRideMarkers.drawn(
                    rides: rides, settings: settings,
                    strokeRef: { [self] ride, segment in strokeRef(for: segment, of: ride) })
                markerCache = (key, settings, drawn)
                return drawn
            }

            /// The same facts ``rideSignature(_:)`` states, as one number.
            ///
            /// The cache key used to be those signatures joined: 201 freshly
            /// built strings and one join of them, on every rebuild — which is
            /// every zoom tier crossed and every pan out of the built rect,
            /// i.e. inside the gesture. The key exists to answer "is this the
            /// same ride set", and a digest answers it without allocating.
            /// Kept field for field in step with `rideSignature` so the two
            /// cannot come to disagree about what a change is.
            static func ridesDigest(_ rides: [RiddenRouteStore.DrawnRide]) -> Int {
                var hasher = Hasher()
                hasher.combine(rides.count)
                for ride in rides {
                    hasher.combine(ride.id)
                    hasher.combine(ride.geometryDigest)
                    hasher.combine(ride.colorHex)
                    hasher.combine(ride.visible)
                    hasher.combine(ride.trainType)
                    hasher.combine(stopsDigest(ride.stops))
                    hasher.combine(ride.daySpan.sig)
                }
                return hasher.finalize()
            }

            /// One marker record's identity, as the two elections' results can
            /// be compared across: its place and the name it carries.
            ///
            /// The role is deliberately not in it. A record that carries a name
            /// is never a `stop-center` — those are unnamed by construction —
            /// so place and name already single one out, and leaving the role
            /// out means a station whose role differs between the two elections
            /// still matches itself.
            static func markerKey(_ record: StationDisplay.MarkerRecord) -> String {
                "\(record.position.lat)|\(record.position.lon)|\(record.name)"
            }

            /// Which of ONE ride's records win a name among that ride's records
            /// alone — the election a selection restricts the map's naming to.
            ///
            /// Cached separately from `markerCache` rather than by calling
            /// `markerRecords` with a one-ride list: the two calls alternate
            /// every rebuild, and a single slot would mean each of them evicting
            /// the other's answer and the deck-wide election — the most
            /// expensive thing a pan does — running again on every pan.
            private var selectedNameCache:
                (key: String, settings: MapRideMarkers.Settings, keys: Set<String>)?

            private func namedRecordKeys(
                of ride: RiddenRouteStore.DrawnRide, settings: MapRideMarkers.Settings
            ) -> Set<String> {
                let key = Self.rideSignature(ride)
                if let selectedNameCache, selectedNameCache.key == key,
                    selectedNameCache.settings == settings {
                    return selectedNameCache.keys
                }
                var keys: Set<String> = []
                for item in MapRideMarkers.drawn(
                    rides: [ride], settings: settings,
                    strokeRef: { [self] ride, segment in strokeRef(for: segment, of: ride) })
                where !item.feature.name.isEmpty {
                    keys.insert(Self.markerKey(item.record))
                }
                selectedNameCache = (key, settings, keys)
                return keys
            }

            /// How near two same-named labels have to be to be one place.
            ///
            /// `StationDisplay.labelMergeMeters`, which is internal to
            /// `RailCore`; the number is the web app's own and both label
            /// elections merge on it, so the cross-source claim above uses the
            /// same one rather than inventing a second distance.
            static let labelMergeMeters: Double = 600

            // MARK: - the origin / destination cards

            /// `computeScopedEndpoints` — the rides that own the selected
            /// day's first origin and last destination.
            ///
            /// The web app orders by position in `trainStore.trains`, which is
            /// the reader's own trip order; `rides` arrives here in that order,
            /// so first and last are literally that. The day's own trains are
            /// preferred and the whole trip stands in when the day has none,
            /// which is the JavaScript's fallback.
            private func scopedEndpointRides()
                -> (first: RiddenRouteStore.DrawnRide, last: RiddenRouteStore.DrawnRide)? {
                let visible = rides.filter(\.visible)
                let day = visible.filter { $0.daySpan.date == selectedDate }
                let pool = day.isEmpty ? visible : day
                guard let first = pool.first, let last = pool.last else { return nil }
                return (first, last)
            }

            /// `updateEndpointLabels` — its two sources, in its own order.
            private func endpointSpecs() -> [MapEndpointLabels.Spec] {
                var specs: [MapEndpointLabels.Spec] = []
                var seen: Set<String> = []
                func add(_ spec: MapEndpointLabels.Spec?) {
                    guard let spec, seen.insert(spec.key).inserted else { return }
                    specs.append(spec)
                }
                let scope = dateScope
                // (1) The selected day's very first origin and very last
                // destination are ALWAYS labelled, so picking a date
                // immediately shows where that day begins and ends.
                if scope.isActive, let pair = scopedEndpointRides() {
                    add(endpointSpec(for: pair.first, kind: .origin, dayEndpoint: true))
                    add(endpointSpec(for: pair.last, kind: .destination, dayEndpoint: true))
                }
                // (2) …and the selected ride keeps its own two ends.
                guard let ride = rides.first(where: { $0.id == selectedTrainID }), ride.visible
                else { return specs }
                // A cross-day ride is on-date for BOTH of the days it runs on,
                // so its cards must not vanish while its line is still drawn.
                guard MapDateScope.inScope(ride.daySpan, scope) else { return specs }
                add(endpointSpec(for: ride, kind: .origin))
                add(endpointSpec(for: ride, kind: .destination))
                return specs
            }

            /// `buildEndpointLabelSpec`, with the four pieces resolved.
            private func endpointSpec(
                for ride: RiddenRouteStore.DrawnRide,
                kind: MapEndpointLabels.Kind,
                dayEndpoint: Bool = false
            ) -> MapEndpointLabels.Spec? {
                guard let endpoint = MapEndpointLabels.endpointStop(of: ride, kind: kind)
                else { return nil }
                let named = localized(
                    endpoint.stop.name, code: endpoint.stop.n02StationCode,
                    region: Region(rawValue: ride.country))
                // An origin shows when the ride LEFT and a destination when it
                // arrived — never both, because a card that showed both would
                // be describing the timetable rather than the journey's end.
                let clock = kind == .origin ? endpoint.stop.departure : endpoint.stop.arrival
                let tag = kind == .origin ? naming.departureTag : naming.arrivalTag
                let time = (clock?.isEmpty == false) ? "\(tag) \(clock!)" : ""
                let badge = dayEndpoint
                    ? (kind == .origin ? naming.startTag : naming.endTag) : ""
                return MapEndpointLabels.spec(
                    trainID: ride.id, kind: kind, at: endpoint.position,
                    name: named.display, rawName: endpoint.stop.name,
                    badge: badge, time: time,
                    readings: named.readings.map(\.text))
            }

            /// Re-runs the endpoint cards' overlap-avoidance layout.
            ///
            /// Pure pixel-space work, so it has to be redone whenever the
            /// projection moves — which is what the web app's re-run on
            /// `zoomend` / `moveend` is. It is at most two boxes, and MapKit keeps
            /// each card anchored to its own coordinate on its own, so nothing
            /// here runs during a pan.
            private func layoutEndpointLabels(on mapView: MKMapView) {
                guard !endpointAnnotations.isEmpty else { return }
                var specs = endpointAnnotations.map(\.spec)
                let points = specs.map {
                    mapView.convert($0.coordinate.clLocation, toPointTo: mapView)
                }
                MapEndpointLabels.layout(&specs, at: points)
                for index in specs.indices {
                    MapEndpointLabels.clampHorizontally(
                        &specs[index], at: points[index],
                        containerWidth: mapView.bounds.width)
                    // Placement is all `layout` and `clampHorizontally` touch;
                    // the text, the readings and the measured box are the ones
                    // the spec was built with. `configure` re-measures three
                    // labels and every reading with `sizeThatFits`, and this
                    // pass now runs on every frame of a pan (see
                    // `mapViewDidChangeVisibleRegion`) — so a card that did
                    // not move must not pay for it.
                    //
                    // Safe to skip because nothing else about the spec can have
                    // changed here: a rebuild REPLACES these annotations, and
                    // `mapView(_:viewFor:)` configures the fresh view with the
                    // fresh text before this pass ever sees it.
                    let placed = endpointAnnotations[index].spec
                    guard placed.direction != specs[index].direction
                        || placed.offset != specs[index].offset
                    else { continue }
                    endpointAnnotations[index].spec = specs[index]
                    (mapView.view(for: endpointAnnotations[index]) as? EndpointLabelView)?
                        .configure(endpointAnnotations[index])
                }
            }

            @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
                guard recognizer.state == .ended, let mapView,
                      !(playback?.isActive == true && playbackLayer.lastSnapshot != nil)
                else { return }
                // 列車経路 off takes the rides' HIT AREA with their ink.
                //
                // `RailMap.setVisible` moves `TRAIN_PICK_LAYER` and
                // `TRAIN_PICK_FAN_LAYER` — the layers a click is resolved
                // against — along with the drawn ones, and MapLibre answers no
                // rendered feature from a hidden layer, so in the browser a
                // click over a hidden route is a click on bare ground. Here the
                // tap index was built from the rides themselves, which do not
                // know whether they were drawn: with the switch off the reader
                // tapped an empty basemap and got a journey card, or the
                // ambiguity chooser offering three journeys none of which was
                // on screen.
                //
                // Answered as a tap on empty map rather than swallowed, which
                // is what it now is: nothing of the reader's is drawn, so §4.4's
                // rule that empty ground clears the selection is the same rule
                // here. `tappedStationOfSelectedRide` is not consulted for the
                // same reason — `MapLayers.draws(role:)` is gated on this
                // switch, so there is no bead of any ride on the map to have
                // been meant.
                guard layers.routes else {
                    onSelectRide([])
                    return
                }
                let point = recognizer.location(in: mapView)
                let interval = RailSignpost.map.begin("map.tap")
                defer { RailSignpost.map.end("map.tap", interval) }
                // Projection here, arithmetic in `RideTapResolver`.
                //
                // Every ride under the finger is handed up, not just the
                // nearest: `railmap-interactions.js` can afford to pick one
                // because a mouse hovers first and the reader sees which line
                // is about to be chosen, while a finger commits on contact —
                // so the web app hands a coarse-pointer tap over crossing
                // lines to `handleDeckRouteChoices` and asks. One ride
                // selects, several are offered, none steps back (§4.4).
                //
                // What is projected is decided by ``RideTapIndex``: the
                // vertices near the finger rather than every vertex the reader
                // has ever ridden. It answers `nil` for a pitched camera,
                // where its one-scale argument does not hold, and then the
                // whole geometry is projected exactly as it always was.
                let index = tapIndex()
                let candidates = index.candidates(at: point, on: mapView)
                    ?? index.allCandidates(on: mapView)
                RailSignpost.map.mark(
                    "map.tap.projected",
                    candidates.reduce(0) { $0 + $1.strokes.reduce(0) { $0 + $1.count } },
                    index.vertexCount)
                let hits = RideTapResolver.hits(
                    at: RideTapResolver.Point(x: point.x, y: point.y),
                    among: candidates)
                // A tap that found no ride, but landed on a station OF THE
                // CHOSEN one, is not a tap on empty map — so it must not be
                // answered as one.
                //
                // `gestureRecognizer(_:shouldReceive:)` already keeps a touch
                // inside a bead's own 44-point target away from this
                // recogniser, and that is the narrower question. MapKit selects
                // an annotation from further out than the view itself claims —
                // `mapView(_:didSelect:)` says so — so a finger that lands
                // beside a dot, past its target but still within MapKit's,
                // reached here, found no ride under it (a bead at the very end
                // of a line has stroke on one side only) and cleared the
                // selection, and then half a second later the same touch opened
                // that station's card. One touch, two contradictory answers,
                // and the reader watching a card appear over a map that has
                // just gone quiet.
                if hits.isEmpty, tappedStationOfSelectedRide(at: point, on: mapView) { return }
                // The touch is CLAIMED when it lands on a ride, and the claim
                // is what `mapView(_:didSelect:)` reads half a second later.
                // See the comment there: this map answers a tap twice
                // otherwise.
                if !hits.isEmpty { rideAnsweredTap = .now }
                onSelectRide(hits)
            }

            /// A double tap only ever zooms. See `makeUIView` for why this
            /// recogniser exists at all — the single tap waits on it, and the
            /// waiting is the whole feature.
            @objc func handleMapDoubleTap(_ recognizer: UITapGestureRecognizer) {
                if recognizer.state == .ended { controller?.readerBeganManipulating() }
            }

            /// Whether `point` is on one of the SELECTED ride's own station
            /// beads.
            ///
            /// Asked of the annotations rather than of the ride's stops so that
            /// the answer is the one the reader can see: a bead that was culled
            /// from the build rect, or that belongs to a journey which is not
            /// the chosen one, is not on screen to be tapped. `selected` is
            /// already on the annotation — the beads are built with it, for the
            /// focus boost — so nothing new has to be carried to ask this.
            ///
            /// The reach is three quarters of ``RailStyle/minimumTouchTarget``,
            /// and the fraction is the point. Half of it is the dot's own claim
            /// (`RideStationAnnotationView.point(inside:with:)`), and a touch
            /// inside THAT never arrives here — `shouldReceive` hands it
            /// straight to MapKit. What is left to cover is the band outside
            /// the dot's target that MapKit nevertheless answers with the same
            /// bead, whose width Apple does not document; a quarter-target
            /// margin is enough for a finger that lands beside a dot and no
            /// wider on purpose, because a guard that swallowed taps a whole
            /// target away from the line would make a selection hard to leave.
            private func tappedStationOfSelectedRide(
                at point: CGPoint, on mapView: MKMapView
            ) -> Bool {
                guard selectedTrainID != nil else { return false }
                let reach = RailStyle.minimumTouchTarget * 0.75
                for annotation in rideStationAnnotations {
                    guard let dot = annotation as? RideStationAnnotation, dot.selected
                    else { continue }
                    let centre = mapView.convert(dot.coordinate, toPointTo: mapView)
                    let dx = centre.x - point.x, dy = centre.y - point.y
                    if dx * dx + dy * dy <= reach * reach { return true }
                }
                return false
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool { true }

            /// The pinch, pan and rotation sensors added in `makeUIView`. They exist to
            /// answer one question — is a finger moving the map right now — and
            /// they answer it by their own `state`, so nothing has to be
            /// mirrored into a flag that can be left behind by a cancelled
            /// touch.
            var manipulationSensors: [UIGestureRecognizer] = []

            /// True while at least one sensor is mid-gesture.
            ///
            /// Read inside a sensor's own callback as well, where the
            /// recogniser that just ended already reports `.ended` — so a pinch
            /// releasing while the other hand still pans correctly stays
            /// manipulating.
            private var isManipulating: Bool {
                manipulationSensors.contains {
                    $0.state == .began || $0.state == .changed
                }
            }

            /// Set when a region change arrived mid-gesture and its rebuild was
            /// held back, so the release knows there is one owing.
            private var rebuildDeferredByGesture = false
            /// Set while the playback chase owns the camera. Cleared by
            /// `renderPlayback(nil)`, which pays the one rebuild then owed.
            private var rebuildDeferredByPlayback = false

            @objc func handleManipulation(_ recognizer: UIGestureRecognizer) {
                switch recognizer.state {
                case .began:
#if DEBUG
                    lastPanCallback = nil
                    gestureFrameProbe.start()
#endif
                    // The reader has the camera. Said once, and never taken
                    // back: what reads it is the app's own opening move
                    // (`RailMapController.frameAtLaunch`), which is owed only
                    // while nobody has touched the map — and the rides it
                    // waits for can land mid-pinch.
                    controller?.readerBeganManipulating()
                    cancelGeometryPreparation()
                case .ended, .cancelled, .failed:
#if DEBUG
                    if !isManipulating { gestureFrameProbe.stop() }
#endif
                    guard !isManipulating, rebuildDeferredByGesture, let mapView else { return }
                    rebuildDeferredByGesture = false
                    scheduleCameraRebuild(on: mapView)
                default:
                    break
                }
            }

            /// Every view MapKit has just put on the map, collected for
            /// ``displayedAnnotationViews``.
            func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
                for view in views { displayedAnnotationViews.add(view) }
            }

            /// A tap that landed on a MARK belongs to that mark.
            ///
            /// The recogniser is attached to the map view, so it also fires for
            /// touches inside annotation views — and every dot a ride puts on a
            /// station sits on that ride's own stroke. Without this, opening a
            /// station's card from one would select the journey underneath at
            /// the same time: two answers to one tap, and where two journeys
            /// call at the station, `handleDeckRouteChoices`' chooser and the
            /// card both trying to be presented at once — a `confirmationDialog`
            /// and a `sheet` asked for in the same frame.
            ///
            /// A deviation from `handleDeckMarkerClick`, which selects the
            /// marker's train as well as opening its popup, and a deliberate
            /// one. That popup is the web app's stop DATA grid — train id, stop
            /// type, `ride_segment`, route source — which is about the journey
            /// it belongs to and reasonably comes with it selected. What opens
            /// here is the station's own card, which is about the place: the
            /// same answer whichever journey called there, and not a reason to
            /// move the reader's selection, their camera (自動縮放) and the
            /// map's whole naming out from under the sheet as it appears.
            ///
            /// The origin/destination cards are unaffected and stay transparent
            /// to route picking, because `EndpointLabelView` turns interaction
            /// off — a touch on one is delivered as a touch on the map, and this
            /// asks the touch where it landed rather than asking the map what is
            /// drawn there.
            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
            ) -> Bool {
                // Only the tap asks where it landed. The manipulation sensors
                // want every touch that moves the map, and a pinch very often
                // starts with a finger on a station bead.
                guard gestureRecognizer is UITapGestureRecognizer else { return true }
                // A new touch has been given no answer yet, whichever of the
                // two answers it ends up getting (`mapView(_:didSelect:)`).
                rideAnsweredTap = nil
                var view = touch.view
                while let current = view {
                    if current is MKAnnotationView { return false }
                    view = current.superview
                }
                return true
            }

            /// What every stroke on this map is drawn with. See
            /// ``MapOverlayStyles`` for the full-scale-token contract the four
            /// writers — network, rides, veil, playback — share through it.
            let overlayStyles = MapOverlayStyles()

            /// The annotation views MapKit currently has on the map, kept so a
            /// rescale does not have to ASK for each of them.
            ///
            /// `restyle` formerly ran on every frame of a pinch and reached
            /// each mark with `mapView.view(for: annotation)`. That call is
            /// roughly 0.15–0.25 ms, which reads as free until you count the
            /// callers: a national view is ~535 station beads and ~390 ride
            /// dots, so the lookups alone cost **219 ms per frame** — measured,
            /// with the loop that writes every renderer's width and dash
            /// pattern costing 0 ms beside them. A pinch over Japan ran at two
            /// to four frames a second and the map visibly lagged the fingers.
            ///
            /// MapKit hands every view it puts on the map to `didAdd`, so the
            /// set is free to collect. It is WEAK: MapKit owns the views, may
            /// recycle one for another annotation and may drop it outright, and
            /// none of that is reported — so membership is not proof a view is
            /// still on screen, which is why the rescale also checks `window`.
            /// A recycled view answering to its new annotation is still exactly
            /// the view that wants the new scale.
            private let displayedAnnotationViews = NSHashTable<MKAnnotationView>.weakObjects()

            /// Re-applies the one shared factor to everything already on screen.
            ///
            /// Cheap by construction: the strokes are a handful of renderers, the
            /// dots are only those MapKit is currently showing a view for, and the
            /// mark pass is skipped unless the railway factor or the labels'
            /// own zoom step moved. Above the anchor zoom railway weights are
            /// pinned at 1, while station type still follows its shallow ramp.
            /// Answers a selection change alone: repaints every ride (width,
            /// alpha, surviving casing width), adds or drops the one casing
            /// overlay under the newly/previously selected ride, repairs
            /// overlay stacking so the selected core and its casing sit on
            /// top, and re-runs the marker phase from the cached
            /// ``MarkerBuildContext`` — never geometry. Folding a selection
            /// into the full rebuild cost 150–460 ms on device over Japan
            /// (see the long comment in ``rebuildOwed(on:)``); this answers
            /// from state the last rebuild already cached.
            ///
            /// Answers `false` — doing nothing — when that state is missing
            /// or stale, so the caller falls back to a full rebuild.
            private func updateSelection(on mapView: MKMapView) -> Bool {
                // A cached context is only as good as the build it came from:
                // while a full rebuild is owed — to a run, or to a gesture —
                // the geometry on screen may be older than the viewport, and
                // the debt is paid by `rebuild`, not by trusting the cache.
                guard let context = markerBuildContext, !annotationsNeedRefresh,
                    !rebuildDeferredByPlayback, !rebuildDeferredByGesture,
                    pendingStrokeRefs == nil, mapView.bounds.width > 1 else { return false }
                // Mirror rebuild's own gesture guard: a finger on the map
                // defers the same way, and reports itself handled so the
                // caller does not also fall back to a full rebuild.
                if isManipulating
                    || lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) == true {
                    rebuildDeferredByGesture = true
                    scheduleCameraRebuild(on: mapView)
                    return true
                }
                let interval = RailSignpost.map.begin("map.selection")
                defer { RailSignpost.map.end("map.selection", interval) }

                updateRidePaint(on: mapView)

                let overlaysInterval = RailSignpost.map.begin("map.selection.overlays")
                let dark = mapView.traitCollection.userInterfaceStyle == .dark
                let installed = mapView.overlays(in: .aboveLabels)
                let reconciliation = MapOverlayReconciliation(overlays: installed)
                var others: [MKOverlay] = []
                var casings: [MKMultiPolyline] = []
                var unselectedCores: [MKMultiPolyline] = []
                var selectedCores: [MKMultiPolyline] = []
                var playback: [MKOverlay] = []
                for overlay in installed {
                    guard let key = overlay.title ?? nil else { others.append(overlay); continue }
                    if key.hasPrefix("ride-casing|") || key.hasPrefix("ride-xday-casing|") {
                        // Kept only for the ride selected NOW — the old
                        // selection's casing is simply left out of `desired`
                        // below, and `install` tears it down.
                        if let separator = key.firstIndex(of: "|"),
                            String(key[key.index(after: separator)...]) == selectedTrainID,
                            let multi = overlay as? MKMultiPolyline {
                            casings.append(multi)
                        }
                    } else if key.hasPrefix("ride|") || key.hasPrefix("ride-xday|"),
                        let multi = overlay as? MKMultiPolyline {
                        if let separator = key.firstIndex(of: "|"),
                            String(key[key.index(after: separator)...]) == selectedTrainID {
                            selectedCores.append(multi)
                        } else {
                            unselectedCores.append(multi)
                        }
                    } else if key.hasPrefix("playback") {
                        playback.append(overlay)
                    } else {
                        others.append(overlay)
                    }
                }

                // The selected ride's casing, one per surviving core suffix
                // (`ride` / `ride-xday`) — same style rule `rebuild` uses for
                // a newly selected ride's halo (§10.5): colour by theme,
                // width from the CORE's own current token plus the casing
                // edge on both sides, 0.9 alpha, the core's own dash.
                if let selectedID = selectedTrainID {
                    for core in selectedCores {
                        guard let coreKey = core.title, let separator = coreKey.firstIndex(of: "|")
                        else { continue }
                        let suffix = String(coreKey[coreKey.startIndex..<separator])
                        let casingKey = "\(suffix)-casing|\(selectedID)"
                        guard !casings.contains(where: { $0.title == casingKey }),
                            let style = overlayStyles[coreKey] else { continue }
                        let casing = reconciliation.multiPolyline(core.polylines, key: casingKey)
                        overlayStyles[casingKey] = .init(
                            color: UIColor(railHex: dark ? "#F5EEE9" : "#1A1A1A") ?? .label,
                            widthToken: style.widthToken + RailStyle.selectionCasingEdge * 2,
                            alpha: 0.9,
                            dashed: style.dashed
                        )
                        casings.append(casing)
                    }
                }

                // Casings first, then cores with the selected ride's last —
                // same order `rebuild` installs in, which is what keeps the
                // selected line and its halo on top.
                let desired: [MKOverlay] = others + casings + unselectedCores + selectedCores + playback
                // The build's own scale, as `rebuild` hands `install`: the
                // marks below are styled from the same context, and the two
                // halves must agree on the frame they are drawn.
                overlayInstaller.install(
                    desired, replacing: reconciliation, scale: context.scale, on: mapView)
                RailSignpost.map.end("map.selection.overlays", overlaysInterval)

                // `buildMarkers` re-adds `endpointAnnotations` unconditionally
                // without first removing the old ones — `rebuild` owes it
                // that teardown ahead of the marker phase (its own teardown
                // section, before calling `buildMarkers`), so this does too.
                if !endpointAnnotations.isEmpty { mapView.removeAnnotations(endpointAnnotations) }
                endpointAnnotations = []

                let markersInterval = RailSignpost.map.begin("map.selection.markers")
                buildMarkers(context, on: mapView)
                RailSignpost.map.end("map.selection.markers", markersInterval)
                return true
            }

            private func updateRidePaint(on mapView: MKMapView) {
                let byID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let hasSelection = selectedTrainID.flatMap { byID[$0] } != nil
                for overlay in mapView.overlays {
                    guard let key = overlay.title ?? nil,
                        key.hasPrefix("ride|") || key.hasPrefix("ride-xday|"),
                        let separator = key.firstIndex(of: "|"),
                        let ride = byID[String(key[key.index(after: separator)...])],
                        var style = overlayStyles[key] else { continue }
                    let selected = ride.id == selectedTrainID
                    style.widthToken = (RailStyle.riddenWidth * CGFloat(display.routeWidthScale)
                        + (selected ? CGFloat(display.focusBoost) : 0)) * RailStyle.riddenWidthScale
                    style.alpha = MapDateScope.alpha(own: CGFloat(display.riddenOpacity),
                        span: ride.daySpan, scope: dateScope, isSelected: selected, hasSelection: hasSelection)
                    overlayStyles[key] = style
                    let casingKey = key.replacingOccurrences(of: "|", with: "-casing|", range: key.startIndex..<key.index(after: separator))
                    if var casing = overlayStyles[casingKey] {
                        casing.widthToken = style.widthToken + RailStyle.selectionCasingEdge * 2
                        overlayStyles[casingKey] = casing
                    }
                }
                overlayStyles.rescale(to: MapProjection.quantised(
                    RailStyle.scale(atZoom: MapProjection.zoomLevel(of: mapView)), on: mapView))
            }

            private func restyle(on mapView: MKMapView) {
                // Keep MapKit's mounted paths and annotation layouts stable
                // under the fingers. Mutating every renderer's width/font
                // during a pinch triggers tessellation and collision work.
                // The camera quiet-period task applies the final style once.
                guard !isManipulating, mapView.bounds.width > 1 else { return }
                // Derive this once for both overlay and annotation styles.
                // Settled camera changes and explicit playback frames share
                // this path; ordinary camera callbacks only schedule it.
                let zoom = MapProjection.zoomLevel(of: mapView)
                // QUANTISED, and everything below is drawn from these rather
                // than from the raw pair.
                //
                // The factor is continuous in zoom, so on every frame of a
                // pinch it is a slightly different number — and a slightly
                // different number relaid out 557 station beads that were
                // already drawn at the width the new one rounds to. The map
                // paid ~87 ms a frame to change nothing a reader could see.
                //
                // A step is one device pixel on the widest mark the factor
                // drives, and a sixteenth of a zoom level on the label ramp
                // (which climbs 10 pt → 12 pt over four levels, so a step is
                // 1/32 pt of type). Both are below what the screen can show,
                // which is the whole argument: the ramp still runs on every
                // frame — §9.1's intermediate frames still explain the change —
                // it just stops re-running for differences that round away.
                let scale = MapProjection.quantised(RailStyle.scale(atZoom: zoom), on: mapView)
                let markZoom = (zoom * 16).rounded() / 16
                // Two throttles, because marks and type stop changing at
                // different zooms. Conflating them froze the label ramp as soon
                // as the railway scale reached 1.
                //
                // Which of them was worth skipping is not what it looks like.
                // Writing a width and a dash pattern into every renderer and
                // asking each to redraw — the loop this note used to call "the
                // expensive half" — measured **0 ms** for 323 renderers, because
                // `setNeedsDisplay` only marks. The marks were the cost, and
                // only because of how they were reached; see
                // ``displayedAnnotationViews``.
                let scaleChanged = !styledScale.isFinite || scale != styledScale
                let markZoomChanged = !styledMarkZoom.isFinite || markZoom != styledMarkZoom
                guard scaleChanged || markZoomChanged else { return }
                styledScale = scale
                styledMarkZoom = markZoom
                if scaleChanged { overlayStyles.rescale(to: scale) }
                // The marks, reached through the views MapKit already handed
                // over rather than by asking it for one per annotation. See
                // ``displayedAnnotationViews`` — the asking was the whole of
                // the cost, and a pinch paid it 900 times a frame.
                //
                // `window` is the on-screen test: the table is weak, but a view
                // MapKit has taken off the map and is holding for reuse is
                // still alive and still in it.
                // On screen, and not merely alive: MapKit keeps an annotation
                // view after it scrolls out — pooled for reuse, still in the
                // window — so `window` alone let a national pan grow the pass
                // from 557 marks to 941, most of them nowhere near the
                // viewport. The rect test is the one that answers "is this
                // drawn", and it is a `CGRect` intersection.
                let viewport = mapView.bounds
                for view in displayedAnnotationViews.allObjects
                where view.window != nil && viewport.intersects(view.frame) {
                    switch view {
                    case let station as StationAnnotationView:
                        station.applyScale(scale, zoom: markZoom)
                    case let dot as RideStationAnnotationView:
                        dot.applyScale(scale, zoom: markZoom)
                    case let label as RideLabelAnnotationView:
                        label.applyScale(scale, zoom: markZoom)
                    case let playback as PlaybackAnnotationView:
                        guard scaleChanged else { continue }
                        guard let annotation = playback.annotation as? PlaybackAnnotation else {
                            continue
                        }
                        playback.configure(annotation, scale: scale)
                    default:
                        continue
                    }
                }
            }

            // MARK: - playback

            // The chase itself lives in `MapPlaybackLayer`. What stays here is
            // the one thing that is not about the trail: whether a rebuild the
            // trail was holding off may now run. See `rebuildDeferredByPlayback`.

            func renderPlayback(_ snapshot: PlaybackMapSnapshot?) {
                guard let mapView else { return }
                let releasedCamera = playbackLayer.render(snapshot, on: mapView)
                if snapshot != nil { restyle(on: mapView) }
                guard releasedCamera, rebuildDeferredByPlayback else { return }
                rebuildDeferredByPlayback = false
                rebuild(on: mapView)
            }

            func framePlayback(coordinates: [Coordinate], maxZoom: Double, animated: Bool) {
                guard let mapView else { return }
                playbackLayer.frame(
                    coordinates: coordinates, maxZoom: maxZoom, animated: animated,
                    on: mapView)
            }

            // MARK: - selection

            /// A tap on any station on this map opens its card.
            ///
            /// ANY: the network's beads, the dots a recorded ride puts on its
            /// own stops, and the captions beside those dots. A station is one
            /// place whether the reader is looking at the whole network or at
            /// one journey through it, and it used to answer differently in the
            /// two — the network bead opened the card, while a ride's dot
            /// opened MapKit's default callout when it happened to have won a
            /// name and did nothing at all when it had not.
            ///
            /// The annotation is deselected straight away, and deliberately.
            /// MapKit's selection is the callout's own state — it exists to
            /// keep a bubble on screen — and there is no bubble now. Left
            /// selected, the bead would stay in its selected appearance behind
            /// the sheet and a second tap on the same station would do nothing
            /// at all, because selecting what is already selected is not a
            /// change.
            ///
            /// ## One touch, one answer
            ///
            /// MapKit's selection does not arrive with the touch. It waits for
            /// the double-tap-to-zoom recogniser to fail first, so it lands
            /// about half a second AFTER the finger lifts — measured at
            /// 0.51–0.57 s on the simulator — and it hit-tests an annotation
            /// more generously than `gestureRecognizer(_:shouldReceive:)` can
            /// see: a touch that never entered any `MKAnnotationView` (so the
            /// map's own tap recogniser took it, resolved the rides under it
            /// and opened the ambiguous-tap chooser) still selects the bead or
            /// the caption it landed beside.
            ///
            /// That is one touch asking the workspace for two surfaces. The
            /// second one is not merely redundant — it is DROPPED: both are
            /// presented by the resident sheet's controller, which is already
            /// presenting the chooser by the time this runs, so UIKit refuses
            /// with "Attempt to present … which is already presenting" and the
            /// station card the reader would have seen never appears. It reads
            /// as a card that opens sometimes and not others.
            ///
            /// So a touch this map has already answered with a ride is not
            /// answered again here. A touch that landed ON an annotation never
            /// reaches the tap recogniser at all (`shouldReceive` returns
            /// false), and one that found no ride under it makes no claim — so
            /// both of those still open their card.
            func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
                guard let card = stationCard(for: annotation) else { return }
                mapView.deselectAnnotation(annotation, animated: false)
                if let answered = rideAnsweredTap, ContinuousClock.now - answered < .seconds(1) {
                    return
                }
                onSelectStation(card)
            }

            /// The card one tapped annotation opens, or `nil` when the thing
            /// tapped was not a station at all.
            private func stationCard(for annotation: any MKAnnotation) -> StationCard? {
                if let station = annotation as? StationAnnotation {
                    return StationCard(
                        station: station.station,
                        displayName: station.displayName,
                        readings: station.readings)
                }
                if let dot = annotation as? RideStationAnnotation {
                    return rideStationCard(
                        name: dot.rawName, code: dot.stationCode, region: dot.region,
                        at: Self.coordinate(dot.coordinate))
                }
                if let caption = annotation as? RideLabelAnnotation {
                    return rideStationCard(
                        name: caption.rawName, code: caption.stationCode, region: caption.region,
                        at: Self.coordinate(caption.coordinate))
                }
                return nil
            }

            /// The card behind one of a ride's own dots.
            ///
            /// A ride's stop knows its name, its station-group code and where
            /// the route drew it; what it does NOT know is which railways run
            /// through the place, which is the whole body of the card. That
            /// lives on the network's side, so the stop is resolved back to a
            /// platform there and the platform's popup model is used — which is
            /// also what makes the card identical to the one the network's own
            /// bead at that station opens, down to the name and the readings.
            ///
            /// When nothing resolves, the card is still opened, with the stop's
            /// own name and no line rows. The reader tapped a station and a
            /// station is what they get; the alternative is a mark that answers
            /// a tap with silence, which is the fault this replaced.
            private func rideStationCard(
                name: String, code: String?, region: Region?, at position: Coordinate
            ) -> StationCard {
                if let station = networkStation(
                    code: code, name: name, region: region, near: position) {
                    // Named and read exactly as `StationAnnotation` names and
                    // reads the same platform — the readings table is keyed on
                    // the platform's own id first and its name second.
                    let named = localized(station.name, code: station.id)
                    return StationCard(
                        station: station, displayName: named.display,
                        readings: localization == nil ? nil : named.readings.map(\.text))
                }
                let named = localized(name, code: code)
                return StationCard(
                    id: "stop:\(Stations.normalizeStationName(name))"
                        + "@\(position.lat),\(position.lon)",
                    coordinate: position,
                    displayName: named.display,
                    rawName: name,
                    // A stop that resolved to no platform still names a
                    // region well enough to search in: the store's own
                    // station code says which package it came from, and a
                    // hand-typed ride with no code at all is Japanese for the
                    // same reason `naming` reads it as Japanese.
                    region: region ?? Region.fromStationCode(code) ?? .jp,
                    readings: localization == nil ? nil : named.readings.map(\.text),
                    nameRoma: "",
                    lines: [])
            }

            /// The network platform a ride's stop stands on.
            ///
            /// By CODE first, and it is the answer that can be trusted: a
            /// station group is an identity the ride's stop and the network's
            /// station both carry (`n02_station_code`), so a match is the same
            /// station rather than a station that reads the same. The nearest
            /// of the group's platforms is taken, which is also what settles a
            /// code that two countries' packages both happen to use — a ride in
            /// Japan cannot resolve to a Korean platform 1,000 km away.
            ///
            /// By NAME second, for the stores that carry no code — a journey
            /// typed in by hand, or one imported from a source that had none.
            /// A name is a guess and is capped accordingly: 同名 stations are
            /// common enough (中山, 大手町) that an uncapped one would hand the
            /// reader another prefecture's railways.
            private func networkStation(
                code: String?, name: String, region: Region?, near position: Coordinate
            ) -> RailNetworkStore.DrawnStation? {
                // Same-region candidates are preferred whenever the ride
                // knows its region — a station code or name shared with
                // another country's package must not steal the match. Only
                // when nothing in the ride's own region resolves does the
                // search fall back across every region, which keeps a ride
                // with no known region (`region == nil`) behaving exactly
                // as it always has.
                func nearest(_ indexes: [Int], within metres: Double) -> RailNetworkStore.DrawnStation? {
                    let candidates = indexes
                        .map { (station: stations[$0], distance:
                            Geometry.distanceMeters(stations[$0].coordinate, position)) }
                        .filter { $0.distance <= metres }
                    if let region {
                        let sameRegion = candidates.filter { $0.station.region == region }
                        if let hit = sameRegion.min(by: { $0.distance < $1.distance }) {
                            return hit.station
                        }
                    }
                    return candidates.min { $0.distance < $1.distance }?.station
                }
                if let code, !code.isEmpty, let group = stationsByCode[code],
                    let hit = nearest(group, within: .infinity) {
                    return hit
                }
                let key = Stations.normalizeStationName(name)
                guard !key.isEmpty, let sameName = stationsByName[key] else { return nil }
                return nearest(sameName, within: Self.nameMatchMeters)
            }

            /// How far a NAME may reach for a platform. Generous next to the
            /// ~600 m the label election merges on, because a stop's drawn
            /// position is the route's own geometry rather than the station
            /// table's point, and a complex like 梅田/大阪 spreads its platforms
            /// over half a kilometre before either number applies.
            static let nameMatchMeters: Double = 2_000

            /// The network's platforms, indexed by the two keys a ride's stop
            /// can offer. Rebuilt when the station list itself changes, which
            /// is once per region as the packages land.
            ///
            /// Indices rather than rows: every `DrawnStation` carries its whole
            /// popup model, and Japan alone ships some 12,000 of them.
            private var stationsByCode: [String: [Int]] = [:]
            private var stationsByName: [String: [Int]] = [:]

            private func indexStations() {
                stationsByCode.removeAll(keepingCapacity: true)
                stationsByName.removeAll(keepingCapacity: true)
                for (index, station) in stations.enumerated() {
                    if !station.stationCode.isEmpty {
                        stationsByCode[station.stationCode, default: []].append(index)
                    }
                    let key = Stations.normalizeStationName(station.name)
                    if !key.isEmpty { stationsByName[key, default: []].append(index) }
                }
            }

            /// MapKit's pair as `RailCore`'s. The annotations hold the
            /// former because that is what `MKAnnotation` requires; everything
            /// ported — `Geometry.distanceMeters`, the station table — speaks
            /// the latter.
            static func coordinate(_ location: CLLocationCoordinate2D) -> Coordinate {
                Coordinate(lon: location.longitude, lat: location.latitude)
            }

            // MARK: - rendering

            func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
                if let veil = overlay as? BasemapVeilOverlay {
                    let renderer = BasemapVeilRenderer(overlay: veil)
                    renderer.veilColor = Self.veilColor(
                        alpha: 1 - min(max(basemapOpacity, 0), 1), on: mapView)
                    return renderer
                }
                // The weight ramp, applied at the one place a token becomes points.
                //
                // This used to read "MapKit line widths are already in points and
                // are not scaled by zoom, so the token transfers directly rather
                // than needing a ramp", and that was wrong twice over: the token IS
                // the width at FULL scale — the weight at about 500 m of ground per
                // point and no wider — and the fact that MapKit does not thin a
                // stroke by itself is exactly why the ramp has to be applied here.
                // Drawing every stroke at full weight at every zoom is the thing
                // `railwayScale` exists to prevent: a nationwide Japan that reads
                // as one fused mass of railway rather than as a network.
                let scale = mapView.bounds.width > 1
                    ? RailStyle.scale(atZoom: MapProjection.zoomLevel(of: mapView)) : 1
                if let polyline = overlay as? MKPolyline {
                    let renderer = MKPolylineRenderer(polyline: polyline)
                    let key = polyline.title ?? ""
                    let style = overlayStyles[key]
                    renderer.strokeColor = (style?.color ?? .systemBlue)
                        .withAlphaComponent(style?.alpha ?? 1)
                    renderer.lineWidth = MapOverlayStyles.drawnWidth(style, atScale: scale)
                    // A round cap adds half a line width to each dash and eats
                    // its gap, the same reason the web app's dashed layers
                    // (`rn-segments-withheld-casing`, `train-routes-xday`, the
                    // suspended layers) all set `line-cap: butt`.
                    renderer.lineCap = style?.dashed == true ? .butt : .round
                    renderer.lineJoin = .round
                    if style?.dashed == true {
                        renderer.lineDashPattern = RailStyle.dashPattern(atScale: scale)
                    }
                    overlayStyles.remember(renderer, forKey: key)
                    return renderer
                }
                guard let multi = overlay as? MKMultiPolyline else {
                    return MKOverlayRenderer(overlay: overlay)
                }
                let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
                let key = multi.title ?? ""
                let style = overlayStyles[key]
                renderer.strokeColor = (style?.color ?? .systemBlue).withAlphaComponent(style?.alpha ?? 1)
                renderer.lineWidth = MapOverlayStyles.drawnWidth(style, atScale: scale)
                renderer.lineCap = style?.dashed == true ? .butt : .round
                renderer.lineJoin = .round
                if style?.dashed == true {
                    renderer.lineDashPattern = RailStyle.dashPattern(atScale: scale)
                }
                overlayStyles.remember(renderer, forKey: key)
                return renderer
            }

            func mapView(
                _ mapView: MKMapView, viewFor annotation: any MKAnnotation
            ) -> MKAnnotationView? {
                let zoom = MapProjection.zoomLevel(of: mapView)
                let scale = mapView.bounds.width > 1
                    ? MapProjection.quantised(RailStyle.scale(atZoom: zoom), on: mapView) : 1
                if let station = annotation as? StationAnnotation {
                    let identifier = "network-station"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? StationAnnotationView
                        ?? StationAnnotationView(annotation: station, reuseIdentifier: identifier)
                    view.annotation = station
                    view.configure(station, scale: scale, zoom: zoom)
                    return view
                }
                if let station = annotation as? RideStationAnnotation {
                    let identifier = "ride-station"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? RideStationAnnotationView
                        ?? RideStationAnnotationView(
                            annotation: station, reuseIdentifier: identifier)
                    view.annotation = station
                    view.configure(station, scale: scale, zoom: zoom)
                    return view
                }
                if let label = annotation as? RideLabelAnnotation {
                    let identifier = "ride-station-label"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? RideLabelAnnotationView
                        ?? RideLabelAnnotationView(annotation: label, reuseIdentifier: identifier)
                    view.annotation = label
                    view.configure(label, scale: scale, zoom: zoom)
                    return view
                }
                if let endpoint = annotation as? EndpointLabelAnnotation {
                    let identifier = "ride-endpoint-label"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? EndpointLabelView
                        ?? EndpointLabelView(annotation: endpoint, reuseIdentifier: identifier)
                    view.annotation = endpoint
                    view.configure(endpoint)
                    return view
                }
                guard let annotation = annotation as? PlaybackAnnotation else { return nil }
                let identifier = annotation.kind == .head ? "playback-head" : "playback-station"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                    as? PlaybackAnnotationView
                    ?? PlaybackAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.configure(annotation, scale: scale)
                return view
            }

            /// The `[r, g, b]` channels a `MarkerRecord` carries.
            ///
            /// Taken from the RECORD rather than parsed back out of the
            /// `"rgb(26,26,26)"` string its feature prints: that string exists
            /// because deck.gl wanted CSS, and its `undefined` blue channel for a
            /// short array is a JavaScript quirk the port reproduces faithfully —
            /// not a colour format anything on this side should have to read.
            static func uiColor(channels: [Double]?) -> UIColor? {
                guard let channels, channels.count >= 3 else { return nil }
                return UIColor(
                    red: CGFloat(channels[0] / 255), green: CGFloat(channels[1] / 255),
                    blue: CGFloat(channels[2] / 255), alpha: 1)
            }
        }
    }
}

/// 底圖不透明度's veil: one world-sized black overlay, so the basemap dims in
/// both light and dark mode. It sits at `.aboveRoads`, under every rail layer
/// and under MapKit's own labels.
final class BasemapVeilOverlay: NSObject, MKOverlay {
    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
    func canReplaceMapContent() -> Bool { false }
}

final class BasemapVeilRenderer: MKOverlayRenderer {
    var veilColor = UIColor.clear.cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setFillColor(veilColor)
        context.fill(rect(for: mapRect))
    }
}
