import MapKit
import RailCore
import RailPresentation
import SwiftUI

/// The railway over Apple Maps, drawn through `MKMapView` rather than
/// SwiftUI's `Map`.
///
/// The first version used SwiftUI's `Map` with one `MapPolyline` per station
/// interval, and the simulator said what was wrong with that:
///
///     Exceeded Metal Buffer threshold of 50000 with a count of 50796
///     resources, pruning resources now
///     _UIInterruptScrollDecelerationGestureRecognizer has been in possible
///     phase for 21.899 seconds
///
/// Japan is 9,568 intervals. Every one became its own overlay, its own
/// renderer and its own set of Metal buffers, VectorKit hit its ceiling and
/// started pruning mid-render, and the gesture recogniser stalled for
/// twenty-two seconds. SwiftUI's `MapPolyline` cannot fix this: it initialises
/// from coordinates, `MKMapPoint`s, an `MKPolyline` or an `MKRoute`, and there
/// is no batch form — one polyline is always one overlay.
///
/// `MKMultiPolyline` is the batch form, so this drops to UIKit. Every line of
/// one colour becomes a single overlay drawn by a single
/// `MKMultiPolylineRenderer`, which takes Japan from 9,568 overlays to roughly
/// one per distinct railway colour.
///
/// Geometry is untouched. The vertices submitted are exactly the ones
/// `RailCore.decodeIntervals` produces, which is exactly what the JavaScript
/// draws — this changes only how they are handed to MapKit.
extension RailNetworkStore.DrawnLine: LODLine {}

/// One line's decimated geometry, kept with the line so the vertex budget can
/// shed the least important rather than simply the last built.
private struct LineBuild: LODBuild {
    let line: RailNetworkStore.DrawnLine
    let polylines: [MKPolyline]
    var drawnVertexCount: Int { polylines.reduce(0) { $0 + $1.pointCount } }
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
    /// `focusZoomEnabled` — 自動縮放. Whether choosing a journey, or a day,
    /// moves the map to frame what was chosen.
    var autoFocus: Bool = false
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
    /// country into view.
    var onBuildRect: (MKMapRect) -> Void = { _ in }
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
        var visibleLines: Int
        var overlays: Int
        var vertices: Int
        var buildMilliseconds: Int
        /// Lines whose bounding box never met the build rect. A large number
        /// here is the off-screen cull earning its keep; a zero at a city zoom
        /// would mean it is not working.
        var culledOffScreen: Int = 0
        /// The threshold actually in force. Below `zoom` when the vertex
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
            selectedTrainID: selectedTrainID,
            selectedDate: selectedDate,
            showsNetwork: showsNetwork,
            // Read HERE, in a body, for the same reason the 顯示調節 numbers
            // are: `updateUIView` is not a scope SwiftUI installs observation
            // tracking around, so a switch first read down there might never
            // schedule the update that redraws it.
            layers: controller.layers,
            categoryIndexes: categoryIndexes,
            autoFocus: autoFocus,
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
        var selectedTrainID: String?
        var selectedDate: String
        var showsNetwork: Bool
        var layers: MapLayers
        var categoryIndexes: [String: Statistics.EdgeIndex]
        var autoFocus: Bool
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
        var onBuildRect: (MKMapRect) -> Void = { _ in }
        var onRender: (RenderStats) -> Void

        func makeUIView(context: Context) -> MKMapView {
            let mapView = MKMapView()
            mapView.delegate = context.coordinator
            mapView.showsCompass = true
            mapView.showsScale = true

            // `.muted` is MapKit's own term for "something is being drawn over
            // me", and excluding points of interest stops Apple's transit lines
            // competing with ours for the same ink.
            let configuration = MKStandardMapConfiguration(
                elevationStyle: .flat, emphasisStyle: .muted)
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

            // Two SENSORS, not gestures: they never move the map and never
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
            context.coordinator.update(
                lines: lines,
                stations: stations,
                rides: rides,
                selectedTrainID: selectedTrainID,
                selectedDate: selectedDate,
                showsNetwork: showsNetwork,
                layers: layers,
                categoryIndexes: categoryIndexes,
                autoFocus: autoFocus,
                basemapOpacity: basemapOpacity,
                display: display,
                naming: naming,
                on: mapView
            )
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
            var onBuildRect: (MKMapRect) -> Void = { _ in }
            /// The localisation engine's owner. A `@MainActor` class, and
            /// therefore `Sendable`, so a nonisolated coordinator may hold it;
            /// see ``localized(_:code:)`` for how it is read.
            var localization: AppLocalization?

            private var lines: [RailNetworkStore.DrawnLine] = []
            private var stations: [RailNetworkStore.DrawnStation] = []
            private var rides: [RiddenRouteStore.DrawnRide] = []
            private var selectedTrainID: String?
            private var selectedDate = Dates.allDates
            private var naming = MapNaming()
            private var minZoomByLineId: [String: Int] = [:]
            /// Starts where `RailMapController.showsNetwork` starts, so the
            /// first update is not told the layer just changed.
            private var showsNetwork = false
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
            private var basemapVeil: MKPolygon?
            /// The zoom bucket the current overlays were built for. Rebuilding on
            /// every region change would put a full decimation pass inside the
            /// pan gesture; rebuilding when the integer zoom changes puts it at
            /// the handful of moments where what is drawn actually changes.
            private var builtForZoom: Int?
            /// The rect the current overlays were built for — the visible one plus
            /// its padding. Panning inside it does no work; leaving it rebuilds.
            private var builtRect: MKMapRect = .null
            /// The chase — see ``MapPlaybackLayer``, which owns every field the
            /// trail needs and shares only this coordinator's style registry.
            private lazy var playbackLayer = MapPlaybackLayer(overlayStyles: overlayStyles)
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
            /// When a tap was last answered with a ride of this map's own —
            /// read by ``mapView(_:didSelect:)`` half a second later, and
            /// cleared as the next touch arrives, so it only ever describes
            /// the touch in hand.
            private var rideAnsweredTap: ContinuousClock.Instant?

            func update(
                lines: [RailNetworkStore.DrawnLine],
                stations: [RailNetworkStore.DrawnStation],
                rides: [RiddenRouteStore.DrawnRide],
                selectedTrainID: String?,
                selectedDate: String,
                showsNetwork: Bool,
                layers: MapLayers,
                categoryIndexes: [String: Statistics.EdgeIndex],
                autoFocus: Bool,
                basemapOpacity: Double,
                display: DisplayValues,
                naming: MapNaming,
                on mapView: MKMapView
            ) {
                // A sheet drag and a menu presentation can call
                // `updateUIView` every frame while these arrays still share
                // their exact backing buffers with the coordinator. Take that
                // O(1) path before allocating thousands of ids/signatures.
                let linesChanged = Self.changed(lines, from: self.lines, id: \.id)
                let stationsChanged = Self.changed(stations, from: self.stations, id: \.id)
                let ridesChanged = rides.count != self.rides.count
                    || (!Self.sharesStorage(rides, self.rides)
                        && !zip(rides, self.rides).allSatisfy {
                            Self.rideSignature($0) == Self.rideSignature($1)
                        })
                let selectionChanged = selectedTrainID != self.selectedTrainID
                let visibilityChanged = showsNetwork != self.showsNetwork
                    || layers != self.layers
                let basemapChanged = basemapOpacity != self.basemapOpacity
                // Compared by which regions have one, not by value: an edge
                // index holds a dictionary with an entry per network edge, and
                // comparing two of those on every update would cost more than
                // the drawing does. An index is built once per region and
                // never mutated, so its presence is the whole of the news.
                let indexesChanged = Set(categoryIndexes.keys) != Set(self.categoryIndexes.keys)
                // Every 顯示調節 number is a width, a radius or an opacity of
                // something already drawn, so a change to one is a rebuild like
                // any other rather than a separate code path.
                let displayChanged = display != self.display
                // The date scope is paint, not a filter: it decides which
                // rides draw at `dimOpacity` and which half of an overnight
                // one is dashed. Both are properties of things already built,
                // so a scope change is a rebuild like the others.
                let dateChanged = selectedDate != self.selectedDate
                let namingChanged = naming != self.naming
                guard linesChanged || stationsChanged || ridesChanged
                        || selectionChanged || visibilityChanged || indexesChanged
                        || basemapChanged || displayChanged || dateChanged
                        || namingChanged else { return }

                if ridesChanged || indexesChanged {
                    segmentCategories.removeAll(keepingCapacity: true)
                }
                self.layers = layers
                self.categoryIndexes = categoryIndexes

                self.display = display
                self.selectedDate = selectedDate
                self.naming = naming
                self.showsNetwork = showsNetwork
                self.basemapOpacity = basemapOpacity
                self.selectedTrainID = selectedTrainID
                if ridesChanged {
                    self.rides = rides
                    // The tap cull's geometry moved. Dropped rather than
                    // rebuilt: `update` runs inside a SwiftUI pass, and a pass
                    // over every ridden vertex is the thing this index exists
                    // to keep out of one. See ``tapIndex()``.
                    cachedTapIndex = nil
                }
                if stationsChanged {
                    self.stations = stations
                    indexStations()
                }

                if linesChanged {
                    self.lines = lines
                    self.minZoomByLineId = Dictionary(
                        uniqueKeysWithValues: lines.map { ($0.id, $0.minZoom) })

                    // A new country's extent, handed to the controller so the 定位
                    // button frames what is actually loaded rather than a
                    // remembered extent — and kept even while the network is
                    // hidden, so the button still works.
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
                    let region = MapProjection.region(covering: lines)
                    let controller = self.controller
                    DispatchQueue.main.async { controller?.fitRegion = region }
                }

                let selectedRide = rides.first { $0.id == selectedTrainID }
                let selectionRegion = selectedRide.flatMap { MapProjection.region(covering: $0.strokes) }
                let controller = self.controller
                // 自動縮放, and it is decided HERE rather than at the dozen
                // places that can change a selection, because this is the
                // first moment the answer exists: the region to frame is the
                // chosen ride's own geometry, and the shell does not hold it.
                //
                // A journey wins over a day. `selectDateBucket` in the web app
                // clears the selection before it fits, so the two can never
                // both be the news there; here a tap on a journey in another
                // day moves both at once, and framing the day would throw away
                // the more specific of the two answers.
                var focusRegion: MKCoordinateRegion? = nil
                // Never while the transport owns the camera, and this is the
                // same rule the rebuild below keeps for the same reason. A run
                // moves the selection from journey to journey as it plays
                // (`ContentView`'s `onChange(of:playback.currentTrainID)`), so
                // with 自動フォーカス on, every hand-off asked `fit` to fly the
                // camera to the whole extent of the journey now starting —
                // against a chase that writes the visible rect on every
                // display-link frame. Two owners, sixty times a second: the
                // camera lurched out to the journey's bounding box and was
                // yanked back onto the train on the next tick, for the length
                // of the fit's animation.
                let playbackOwnsCamera = playback?.isActive == true
                if autoFocus, !playbackOwnsCamera, selectionChanged, let selectionRegion {
                    // Selection only moves the map when its geometry already
                    // exists. Do not keep a pending camera request while the
                    // route is loading: completing a solve must not yank the
                    // reader away from wherever they have panned in the
                    // meantime. The explicit locate action remains available
                    // once the geometry is ready.
                    focusRegion = selectionRegion
                } else if autoFocus, !playbackOwnsCamera, dateChanged,
                    selectedDate != Dates.allDates, selectedTrainID == nil {
                    // "Whole-day auto-focus skips hidden trains; the
                    // single-train fit does not" — and every ride that reaches
                    // this surface is already a visible one.
                    focusRegion = MapProjection.region(
                        covering: rides
                            .filter { $0.daySpan.date == selectedDate }
                            .flatMap(\.strokes))
                }
                DispatchQueue.main.async {
                    controller?.selectionRegion = selectionRegion
                    guard let focusRegion else { return }
                    controller?.fit(focusRegion)
                }

                // Loading network packages must not repeatedly rebuild the
                // reader's routes while that network layer is hidden. Five
                // regions arrive independently at launch; before this gate,
                // each arrival rebuilt every ride overlay on the main thread
                // even though none of the arriving geometry was visible.
                let visibleNetworkChanged = showsNetwork && (linesChanged || stationsChanged)
                let drawingChanged = visibleNetworkChanged || ridesChanged
                    || selectionChanged || visibilityChanged || indexesChanged
                    || displayChanged || dateChanged || namingChanged
                if drawingChanged {
                    builtForZoom = nil
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
                    // `builtForZoom` is cleared above whether or not the
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
                if basemapChanged { updateBasemapVeil(on: mapView) }
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

            /// The region as it MOVES, rather than once it has come to rest.
            ///
            /// `regionDidChangeAnimated` is delivered when a change SETTLES —
            /// at the end of a programmatic animated move, and coarsely during
            /// a gesture — so a "frame the selection" spent its whole 300–550
            /// ms flight drawing the railway at the weight of the zoom it left
            /// from, and stepped to the right weight on arrival. §9.1 asks the
            /// intermediate frames to explain the change; a weight that only
            /// updates at the end explains nothing and announces itself with a
            /// jump.
            ///
            /// Only the two cheap halves belong here. `rebuild` must NOT be
            /// called from this callback: its guard is
            /// `bucket != builtForZoom || !builtRect.contains(visibleRect)`,
            /// and the second half fails on nearly every frame of a pan — so
            /// wiring the settled callback's whole body to this one would
            /// rebuild the entire network sixty times a second. It stays where
            /// its zoom-bucket guard is the right one.
            ///
            /// `restyle` carries its own throttle (a 0.005 epsilon on the
            /// scale, see below), and `layoutEndpointLabels` returns
            /// immediately when there are no endpoint labels — which is the
            /// state the map is in unless a journey is selected.
            func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
                restyle(on: mapView)
                // Screen-space work: these labels de-overlap each other and
                // clamp to the window's edges, so a label clamped at the right
                // edge stayed clamped after a pan carried it into the middle.
                layoutEndpointLabels(on: mapView)
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
                // their ramp (`restyle` below still runs every frame), so what
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
                    rebuild(on: mapView)
                }
                // The weight ramp is continuous in zoom while a rebuild happens
                // only when the zoom BUCKET changes, so re-applying it is its own
                // step. It costs a width per renderer and a frame per visible dot,
                // and only when the scale has actually moved.
                restyle(on: mapView)
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
                builtForZoom = nil
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
                if let basemapVeil {
                    if let renderer = mapView.renderer(for: basemapVeil) as? MKPolygonRenderer {
                        renderer.fillColor = UIColor.systemBackground.withAlphaComponent(
                            1 - min(max(basemapOpacity, 0), 1))
                        renderer.setNeedsDisplay()
                    }
                    return
                }
                guard !builtRect.isNull else { return }
                let corners = [
                    MKMapPoint(x: builtRect.minX, y: builtRect.minY),
                    MKMapPoint(x: builtRect.maxX, y: builtRect.minY),
                    MKMapPoint(x: builtRect.maxX, y: builtRect.maxY),
                    MKMapPoint(x: builtRect.minX, y: builtRect.maxY),
                ].map(\.coordinate)
                let veil = MKPolygon(coordinates: corners, count: corners.count)
                veil.title = "basemap-veil"
                basemapVeil = veil
                // Under the railways, which are a level up. See the mount in
                // `rebuild`.
                mapView.addOverlay(veil, level: .aboveRoads)
            }

            private func rebuild(on mapView: MKMapView) {
                // With both layers absent there is nothing to build. Hiding the
                // complete network does not hide the reader's routes.
                guard showsNetwork || !rides.isEmpty else {
                    mapView.removeOverlays(mapView.overlays)
                    basemapVeil = nil
                    if !networkAnnotations.isEmpty { mapView.removeAnnotations(networkAnnotations) }
                    networkAnnotations = []
                    if !rideStationAnnotations.isEmpty {
                        mapView.removeAnnotations(rideStationAnnotations)
                    }
                    rideStationAnnotations = []
                    builtForZoom = nil
                    return
                }

                // Before the first layout pass the view has no width, and the
                // zoom derived from it is nonsense — it was reading z = -8 and
                // culling every line. Wait for a real size.
                guard mapView.bounds.width > 1, !lines.isEmpty || !rides.isEmpty else { return }

                let zoom = MapProjection.zoomLevel(of: mapView)
                // Every LOD and label floor is an integer zoom. `rounded()`
                // rebuilt half a level before the floor, then did nothing when
                // the camera actually crossed it; a z14 caption could therefore
                // wait until z14.5 to appear. Flooring changes the bucket at the
                // same boundary as the visibility rule itself.
                let bucket = Int(floor(zoom))
                let visibleRect = mapView.visibleMapRect
                // Rebuild when the zoom tier changes, or when the map has been
                // panned past what was built for. Panning within the padded rect
                // is free, which is what keeps the gesture smooth.
                guard bucket != builtForZoom || !builtRect.contains(visibleRect) else { return }
                builtForZoom = bucket
                let buildRect = NetworkLOD.buildRect(for: visibleRect)
                builtRect = buildRect
                // Before the build, not after: a country that has not been
                // decoded contributes nothing to what follows, and saying so
                // now is what gets it decoded in time for the next rebuild.
                onBuildRect(buildRect)

                let started = ContinuousClock.now
                let rebuildInterval = RailSignpost.map.begin("map.rebuild")
                defer { RailSignpost.map.end("map.rebuild", rebuildInterval) }

                // The geometry half — level of detail, decimation, the vertex
                // budget. It is the only part of a rebuild that touches no
                // MapKit object, and therefore the only part that could ever
                // move off this actor; measured over the whole Japanese
                // network in release it is 6.7 ms at a national zoom and
                // 24.2 ms at a city one (`ios/tools/bench`), against a rebuild
                // this file's own history records at 150–460 ms. What the rest
                // of it is, is what the phases below are here to say.
                let geometryInterval = RailSignpost.map.begin("map.rebuild.geometry")

                // What is eligible: near enough to be seen, important enough for
                // this zoom. See NetworkLOD — that policy is deliberately stricter
                // than the web app's at low zoom, and deliberately outside the
                // ported tier, because there is no JavaScript to check it against.
                let selection = showsNetwork
                    ? NetworkLOD.select(from: lines, zoom: zoom, buildRect: buildRect)
                    : nil

                // Decimation is ours to IMPLEMENT — MapLibre gets it free from
                // geojson-vt and MapKit has no equivalent — but it is not ours
                // to SET. How far the drawn line may leave the surveyed one is
                // a contract both apps keep, and `RailStyle.simplifyTolerance`
                // is the web app's own number. The half a point that stood here
                // was eight times it, and because the parity fixtures compare
                // the two apps ABOVE this line, nothing reported the difference
                // but the map.
                let epsilon = MapProjection.metresPerPixel(
                    zoom: zoom, latitude: mapView.region.center.latitude)
                    * RailStyle.simplifyTolerance

                let builds: [LineBuild] = (selection?.lines ?? []).map { line in
                    var polylines: [MKPolyline] = []
                    for interval in line.intervals where interval.count >= 2 {
                        let kept = Geometry.douglasPeuckerIndices(interval, epsilonMeters: epsilon)
                        let points = kept.map { interval[$0].clLocation }
                        guard points.count >= 2 else { continue }
                        polylines.append(MKPolyline(coordinates: points, count: points.count))
                    }
                    return LineBuild(line: line, polylines: polylines)
                }

                // The budget is applied to what decimation actually produced, not
                // to the stored vertex count. Budgeting on the raw count cut a
                // national view of Japan from 262 lines to 7, by weighing 394,285
                // stored vertices against a budget meant for the ~12,000 drawn.
                let fitted = NetworkLOD.fitToBudget(builds, zoom: zoom)
                let visible = fitted.kept.map(\.line)
                RailSignpost.map.end("map.rebuild.geometry", geometryInterval)

                // One palette or the other, chosen once per rebuild rather than
                // per line: mixing them would be a map half in each mode.
                let dark = mapView.traitCollection.userInterfaceStyle == .dark

                var byColor: [String: [MKPolyline]] = [:]
                var colors: [String: UIColor] = [:]
                var vertices = 0
                for build in fitted.kept {
                    let key = dark ? build.line.colorDarkHex : build.line.colorHex
                    colors[key] = UIColor(dark ? build.line.colorDark : build.line.color)
                    byColor[key, default: []].append(contentsOf: build.polylines)
                    vertices += build.drawnVertexCount
                }

                // The scale this build's marks are sized for. One factor, read
                // once, handed to every weight below — see RailStyle. Rounded
                // by the same rule `restyle` rounds by, so a mark built here
                // and a mark rescaled there are never a fraction of a pixel
                // apart.
                let scale = MapProjection.quantised(RailStyle.scale(atZoom: zoom), on: mapView)
                styledScale = scale
                styledMarkZoom = (zoom * 16).rounded() / 16

                // A normal network rebuild removes every overlay underneath
                // MapKit. Forget the incremental playback mount before doing
                // so; the current snapshot is re-mounted once at the end.
                playbackLayer.clear(on: mapView)
                let teardown = RailSignpost.map.begin("map.rebuild.teardown")
                mapView.removeOverlays(mapView.overlays)
                basemapVeil = nil
                // The rescale's view set belongs to the annotations about to be
                // replaced. MapKit hands back the ones it puts on the map next
                // (`didAdd`), so clearing here is what keeps the set the CURRENT
                // marks rather than every mark this map has ever shown.
                displayedAnnotationViews.removeAllObjects()
                if !networkAnnotations.isEmpty { mapView.removeAnnotations(networkAnnotations) }
                networkAnnotations = []
                if !rideStationAnnotations.isEmpty { mapView.removeAnnotations(rideStationAnnotations) }
                rideStationAnnotations = []
                if !endpointAnnotations.isEmpty { mapView.removeAnnotations(endpointAnnotations) }
                endpointAnnotations = []
                overlayStyles.removeAll()
                RailSignpost.map.end("map.rebuild.teardown", teardown)
                if basemapOpacity < 0.999 {
                    let corners = [
                        MKMapPoint(x: buildRect.minX, y: buildRect.minY),
                        MKMapPoint(x: buildRect.maxX, y: buildRect.minY),
                        MKMapPoint(x: buildRect.maxX, y: buildRect.maxY),
                        MKMapPoint(x: buildRect.minX, y: buildRect.maxY),
                    ].map(\.coordinate)
                    let veil = MKPolygon(coordinates: corners, count: corners.count)
                    veil.title = "basemap-veil"
                    basemapVeil = veil
                    // `.aboveRoads` is what keeps the veil UNDER every rail
                    // layer, which all mount at `.aboveLabels`: a level is
                    // ordered before insertion order is, so the slider can add
                    // this after a rebuild has already drawn the railways and
                    // still not dim them. It is also why the base map's labels
                    // stay full-strength while its roads fade — they are drawn
                    // above this level, and 底圖不透明度 is a control over the
                    // map behind the railways, not over their labelling.
                    mapView.addOverlay(veil, level: .aboveRoads)
                }
                let networkOverlays = RailSignpost.map.begin("map.rebuild.networkOverlays")
                var overlays: [MKMultiPolyline] = []
                for (key, polylines) in byColor {
                    let multi = MKMultiPolyline(polylines)
                    let styleKey = "network|\(key)"
                    multi.title = styleKey
                    overlayStyles[styleKey] = .init(
                        color: colors[key] ?? .systemGray,
                        // The rail stroke is a quarter of the station dot, and it
                        // is a TOKEN — the full-scale weight, not the drawn one.
                        // The previous fixed 1.5 pt drew a nationwide Japan as one
                        // fused mass of railway, which is the thing the ramp
                        // exists to prevent.
                        widthToken: RailStyle.railWidth,
                        alpha: RailStyle.networkOpacity
                    )
                    overlays.append(multi)
                }
                // `.aboveLabels`, not `.aboveRoads`. The base map's own
                // labelling — road names, station icons, the expressway
                // shields — is drawn BETWEEN the two levels, so at
                // `.aboveRoads` a motorway badge printed straight over the
                // railway it happens to sit on: the base map annotating
                // itself on top of the thing this app is a map of. The web
                // app stacks every rail layer above the whole OpenFreeMap
                // style, labels included; this is that order. Nothing of ours
                // is buried by the move — annotations (station dots, captions,
                // endpoint cards) draw above both levels either way, and the
                // dimming veil stays a level below on purpose.
                mapView.addOverlays(overlays, level: .aboveLabels)
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
                for (index, ride) in orderedRides.enumerated() {
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
                        guard draws(segment: segment, of: ride, riddenStops: riddenStops)
                        else { continue }
                        let stroke = segment.coordinates
                        guard stroke.count >= 2 else { continue }
                        // Straight off the ride's own coordinates. Rule R14 is
                        // withdrawn (commit 38cf0a8): a drawn vertex is the
                        // surveyed vertex, so nothing between here and the
                        // renderer may move one sideways. Decimation is allowed
                        // because it only ever DROPS vertices, and only ones
                        // that cannot move the line by more than the shared
                        // `RailStyle.simplifyTolerance` the network is held to.
                        let kept = Geometry.douglasPeuckerIndices(stroke, epsilonMeters: epsilon)
                        let points = kept.map { stroke[$0].clLocation }
                        guard points.count >= 2 else { continue }
                        let polyline = MKPolyline(coordinates: points, count: points.count)
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
                        let styleKey = "\(suffix)|\(index)|\(ride.id)"
                        let multi = MKMultiPolyline(polylines)
                        multi.title = styleKey
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
                        let casingKey = "\(suffix)-casing|\(index)|\(ride.id)"
                        let casing = MKMultiPolyline(polylines)
                        casing.title = casingKey
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
                mapView.addOverlays(rideCasings, level: .aboveLabels)
                mapView.addOverlays(rideOverlays, level: .aboveLabels)
                RailSignpost.map.end("map.rebuild.rideOverlays", rideOverlayInterval)
                let markerInterval = RailSignpost.map.begin("map.rebuild.markers")

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
                    guard buildRect.contains(MKMapPoint(record.position.clLocation)) else { continue }
                    let selected = feature.tid == selectedTrainID
                    let routeColor = UIColor(railHex: item.routeColorHex) ?? .systemBlue
                    let prominent = feature.role == "terminal" || feature.role == "xday"
                    let annotation = RideStationAnnotation(
                        coordinate: record.position.clLocation,
                        name: feature.name,
                        rawName: record.name,
                        stationCode: item.stationCode,
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
                rideStationAnnotations = markerAnnotations

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
                    let drawnLineIDs = Set(visible.map(\.id))
                    let visibleStations = stations.compactMap { station -> (
                        key: String, station: RailNetworkStore.DrawnStation,
                        displayName: String, readings: [String]?
                    )? in
                        guard station.lodMinZoom <= zoom else { return nil }
                        let point = MKMapPoint(station.coordinate.clLocation)
                        guard buildRect.contains(point) else { return nil }
                        guard drawnLineIDs.contains(station.lineID) else { return nil }
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
                            readings: candidate.readings)
                    }
                    networkAnnotations = stationAnnotations
                    mapView.addAnnotations(stationAnnotations)
                }
                mapView.addAnnotations(markerAnnotations)
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
                    "railmap: z=%.2f thr=%.1f lines=%@/%d (culled %d) overlays=%d vertices=%d "
                        + "stations=%d ridedots=%d ridelabels=%d %dms",
                    zoom, fitted.threshold, drawnLines, lines.count,
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
                    visibleLines: visible.count,
                    overlays: overlays.count + rideOverlays.count + rideCasings.count,
                    vertices: vertices,
                    buildMilliseconds: elapsed.milliseconds,
                    culledOffScreen: selection?.culledOffScreen ?? 0,
                    threshold: fitted.threshold
                )
                DispatchQueue.main.async { [onRender] in onRender(stats) }
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
                let index = RideTapIndex(rides: rides)
                cachedTapIndex = index
                return index
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

                let key = "\(ride.id)#\(segment.segmentIndex)"
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
                let drawn = MapRideMarkers.drawn(rides: rides, settings: settings)
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
                for item in MapRideMarkers.drawn(rides: [ride], settings: settings)
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
                      playbackLayer.lastSnapshot == nil else { return }
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
            @objc func handleMapDoubleTap(_ recognizer: UITapGestureRecognizer) {}

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

            /// The pinch and pan sensors added in `makeUIView`. They exist to
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
                    // The reader has the camera. Said once, and never taken
                    // back: what reads it is the app's own opening move
                    // (`RailMapController.frameAtLaunch`), which is owed only
                    // while nobody has touched the map — and the rides it
                    // waits for can land mid-pinch.
                    controller?.readerBeganManipulating()
                case .ended, .cancelled, .failed:
                    guard !isManipulating, rebuildDeferredByGesture, let mapView else { return }
                    rebuildDeferredByGesture = false
                    // The map may still be gliding to a stop, and its own
                    // settled callback will arrive when it is. Building here as
                    // well is what makes the release feel immediate; the second
                    // one costs nothing, because `rebuild`'s guard answers
                    // "same zoom tier, still inside the built rect".
                    rebuild(on: mapView)
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
            /// `restyle` runs on every frame of a pinch, and it used to reach
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
            private func restyle(on mapView: MKMapView) {
                guard mapView.bounds.width > 1 else { return }
                // Once, not twice: this now runs on every frame of a pan or a
                // camera flight (see `mapViewDidChangeVisibleRegion`), and the
                // annotation pass below used to derive the same number a
                // second time.
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
                guard playbackLayer.render(snapshot, on: mapView),
                      rebuildDeferredByPlayback else { return }
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
                        name: dot.rawName, code: dot.stationCode,
                        at: Self.coordinate(dot.coordinate))
                }
                if let caption = annotation as? RideLabelAnnotation {
                    return rideStationCard(
                        name: caption.rawName, code: caption.stationCode,
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
                name: String, code: String?, at position: Coordinate
            ) -> StationCard {
                if let station = networkStation(code: code, name: name, near: position) {
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
                    region: Region.fromStationCode(code) ?? .jp,
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
                code: String?, name: String, near position: Coordinate
            ) -> RailNetworkStore.DrawnStation? {
                func nearest(_ indexes: [Int], within metres: Double) -> RailNetworkStore.DrawnStation? {
                    indexes
                        .map { (station: stations[$0], distance:
                            Geometry.distanceMeters(stations[$0].coordinate, position)) }
                        .filter { $0.distance <= metres }
                        .min { $0.distance < $1.distance }?
                        .station
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
                if let polygon = overlay as? MKPolygon, polygon.title == "basemap-veil" {
                    let renderer = MKPolygonRenderer(polygon: polygon)
                    renderer.fillColor = UIColor.systemBackground.withAlphaComponent(
                        1 - min(max(basemapOpacity, 0), 1))
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
                    renderer.lineCap = .round
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
                renderer.lineCap = .round
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
