import Darwin
import MapKit
import RailCore
import RailPresentation
import SwiftUI
#if DEBUG
import OSLog

/// DEBUG: the latest map-coordinator counters, read by app-control `state`
/// (`map.probe`). Main-actor state written only by the coordinator.
@MainActor enum MapRenderProbe {
    struct RideStationDots {
        /// Ride-station dots handed to the shared circle overlay this pass.
        var drawn: Int
        /// Every ride-station annotation the marker election produced.
        var stations: Int
        /// What the mounted `RideStationOverlay` holds after the pass.
        var overlayStations: Int
    }
    static var rideStationDots: RideStationDots?
    /// The selected trip's marks in the built area, by tier class:
    /// `<class>.dots`, `<class>.names` (names offered, before collisions).
    static var selectedTripMarks: [String: Int]?
    /// Matching workers started, requests skipped as unchanged, and requests
    /// that waited for a burst's trailing debounce.
    static var matchingRuns = 0
    static var matchingSkipped = 0
    static var matchingDeferred = 0
    /// How long network-geometry preparations waited for their permit.
    /// Every overlay mounted on the map after the last rebuild, and how many of
    /// them are trip (ride) overlays; `RenderStats.overlays` is the network's.
    static var totalOverlays = 0
    static var rideOverlays = 0
    /// Frame-geometry entries released by memory-pressure drops.
    static var droppedFrames = 0
    /// A rebuild left the full marker pass owed and it has not run yet; app-control
    /// `idle` waits for it.
    static var markerPassOwed = false
    /// Where the geometry levels stand: installed (on screen), wanted (by the
    /// camera now), preparing (in flight), pending (landed, to install next).
    struct GeometryLevels {
        var installed: Int?
        var wanted: Int?
        var preparing: Int?
        var pending: Int?
        var cameraZoom: Double = 0
        var installedAt: ContinuousClock.Instant?
    }
    static var geometryLevels = GeometryLevels()
    static var geometryWaits = 0
    static var lastGeometryWaitMilliseconds = 0
    static var maxGeometryWaitMilliseconds = 0
    static let log = Logger(subsystem: RailSignpost.subsystem, category: "map")

    static func recordGeometryWait(milliseconds: Int) {
        geometryWaits += 1
        lastGeometryWaitMilliseconds = milliseconds
        maxGeometryWaitMilliseconds = max(maxGeometryWaitMilliseconds, milliseconds)
    }
}
#endif

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

extension RailMapView.Surface {
        final class Coordinator: NSObject, MKMapViewDelegate, PlaybackMapRendering,
            UIGestureRecognizerDelegate {
            weak var mapView: MKMapView?
            var controller: RailMapController? {
                didSet { playbackLayer.controller = controller }
            }
            weak var playback: PlaybackController? {
                didSet { playbackLayer.playback = playback }
            }
            var onRender: (RailMapView.RenderStats) -> Void = { _ in }
            var onSelectRide: ([String]) -> Void = { _ in }
            var onSelectStation: (StationCard) -> Void = { _ in }
            var onSelectLines: ([RailNetworkStore.DrawnLine]) -> Void = { _ in }
            /// The recognisers `makeUIView` installs, so `shouldReceive` can tell them apart.
            weak var tapRecognizer: UITapGestureRecognizer?
            weak var settledTapRecognizer: UITapGestureRecognizer?
            /// The line builds the last rebuild drew, retained for the network
            /// line tap. They only reference the polylines MapKit already holds.
            private var drawnLineBuilds: [LineBuild] = []
            /// The family-fallback and withheld-run polylines the same rebuild
            /// handed to MapKit, by canonical line id: drawn, so tappable.
            private var drawnExtraPolylines: [String: [MKPolyline]] = [:]
            /// An answer `answerTap` banked for `handleSettledTap`: the empty-map
            /// clear, or (over a panel card) a station or line card that a double
            /// tap cancels (`MapTapPolicy.defersAnswer`).
            private enum BankedTap {
                case clear
                case station(StationCard)
                case lines([RailNetworkStore.DrawnLine])
            }
            private var bankedTap: BankedTap?
            /// The non-station annotation the last `answerTap` left to MapKit.
            private var annotationUnderTap: (any MKAnnotation)?
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
            private var networkRideDate: String?
            private var naming = MapNaming()
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
            private var categoryVisibility = RiddenCategoryVisibility()
            private var selectionNeedsHighlightTransition = false
            /// Owns the camera snapshot that gates expensive geometry rebuilds.
            private var networkBuildState = MapNetworkBuildState()
            private var viewportResizeTask: Task<Void, Never>?
            /// Owns zoom-dependent line, stroke and ride-overlay geometry.
            private let networkGeometry = MapNetworkGeometryCache()
            /// The worker building the frame's
            /// ride polylines, its identity and the frame it builds for.
            private var rideStrokePreparation: Task<Void, Never>?
            private var rideStrokePreparationID = UUID()
            private var rideStrokePreparationFrame: RideStrokeBuilder.Frame?
            /// The rides the running ride-stroke build has requests for.
            private var rideStrokePreparationRideIDs: Set<String> = []
            private let rideStrokeMemo = RideStrokeBuilder.Memo()
            /// Ride polyline keys the worker found draw nothing, for one frame,
            /// so `rideStrokeRequests` does not ask for them again.
            private var rideStrokeEmptyKeys: Set<RideLineCacheKey> = []
            private var rideStrokeEmptyFrameKey = ""
            /// Nominal-zoom projection the installed geometry was built at.
            private var currentGeometryFrame: MapGeometryFrame?
            /// Bumped whenever `lines` or `stations` moves — see `update`'s
            /// own two sites. The cache key for ``prepareStrokeReferences()`` and
            /// for every ride's own entry in ``strokeRefCache``: both are
            /// built from `lines`/`stations` alone, and are correct for
            /// exactly as long as this number does not move, regardless of
            /// what else changes on a given rebuild.
            private var linesGeneration = 0
            /// Captured at update/rebuild boundaries, shared by frame keys,
            /// geometry workers and station visibility for that derivation.
            private var networkTodayByRegion: [String: String] = [:]
            private var annotationsNeedRefresh = false
            /// The geometry phase's outputs the marker phase reads. Kept from the last
            /// completed `rebuild` so the markers can be rebuilt on their own — a
            /// selection changes which dots and captions exist. A newly selected
            /// route first expands to include its offscreen segments.
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
            /// Set when a rebuild during a gesture skipped the full marker
            /// pass; paid by the first full pass, normally at settle.
            private var markerPassDebt = MarkerPassDebt() {
                didSet {
                    #if DEBUG
                    MapRenderProbe.markerPassOwed = markerPassDebt.isOwed
                    #endif
                }
            }
            /// The next-turn hand-off that pays the camera settle's marker debt.
            private var markerSettleTurn = MarkerSettleTurn()
            /// Per-ride digests of `rides`, kept in step with it in `update`.
            private var rideDeck = RideDeckState()
            /// The non-selected rides' installed batches and the inputs they
            /// were drawn under; see ``updateRides(_:on:)``.
            private var rideBatchCache: RideBatchCache?
            /// The marker pass's station and line lookups for `linesGeneration`.
            private var markerSetupCache: MarkerSetupCache?
            /// The installed selection includes every drawable segment, even
            /// outside the padded viewport. A new pick must expand its route once.
            private var fullyBuiltSelectedRideID: String?
            /// Rides the last full rebuild drew inside a shared `rides|` batch
            /// (every ride but that rebuild's selection), with how many
            /// polylines each contributed. The selection fast path only ever
            /// answers for `fullyBuiltSelectedRideID` (see the guard in
            /// `updateSelection`), whose own per-ride cores are not in any
            /// batch and stay mounted as unselected cores. Diagnostics read the
            /// counts, since a batch's overlay no longer names its rides.
            private var batchedRidePartCounts: [String: Int] = [:]
            private let selectedStationSnapshots = MapSelectedStationSnapshotController()
            private struct LineInputs: Equatable, Sendable {
                let contentID: UUID
                let anchors: [Int]
                let dependencies: [String: UUID]
            }
            private var lineInputs: [String: LineInputs] = [:]
            /// The inputs each line would be built from now, whatever is held.
            private var trueLineInputs: [String: LineInputs] = [:]
            private var lineInputGenerations: [String: Int] = [:]
            private var strokeStability = StrokeStabilityLedger()
            /// Lines whose stored stroke is held while the camera moves.
            private var heldJointLineIDs: Set<String> = []
            /// The junction index and per-line dependency ids of the APPLIED
            /// line set. Only ``installLineSwap(_:cancelsPreparation:)`` advances it,
            /// from a worker's result.
            private var junctionState = StrokeJunctionState()
            private var junctionIndex: StrokeJunctionIndex { junctionState.index }
            /// The junction line built for each resident line, by content id.
            private var junctionLineMemo: [String: JunctionLineMemo] = [:]
            private struct JunctionLineMemo: Sendable {
                let contentID: UUID
                let line: StrokeJunctionIndex.Line
            }
            /// The newest line and station set not yet applied. While it is set,
            /// `update` compares incoming data against it, not against `lines`.
            private var pendingLineSwap: (lines: [RailNetworkStore.DrawnLine],
                                          stations: [RailNetworkStore.DrawnStation])?
            private var lineSwapSchedule = LineSwapSchedule()
            private var lineSwapTask: Task<Void, Never>?
            /// A result that landed during a gesture, installed when it ends.
            private var heldLineSwap: LineSwapResult?

            /// What the worker needs to compute the next line set. Everything
            /// is an immutable snapshot of the applied state.
            private struct LineSwapInput: Sendable {
                let lines: [RailNetworkStore.DrawnLine]
                let stations: [RailNetworkStore.DrawnStation]
                let state: StrokeJunctionState
                let memo: [String: JunctionLineMemo]
                let joinedChains: JoinedChainCache
            }

            /// The next line set with everything derived from it. The main
            /// actor only assigns these.
            private struct LineSwapResult: Sendable {
                let baseSerial: Int
                let lines: [RailNetworkStore.DrawnLine]
                let stations: [RailNetworkStore.DrawnStation]
                let state: StrokeJunctionState
                let memo: [String: JunctionLineMemo]
                let chainKeys: Set<JoinedChainKey>
                let inputs: [String: LineInputs]
            }
            private var matchedLineInputs: [String: LineInputs] = [:]
            /// Background matching and its display-datum chain index, independent of zoom.
            private var matchingTask: Task<Void, Never>?
            // Cancellation is cooperative: keep a winding-down worker's permit
            // until it exits before admitting its replacement. Network geometry
            // and ride matching hold separate permits, so a long match during a
            // route load never makes a pan or zoom wait for its railways.
            private let geometryWorkLimiter = RouteSolveLimiter(limit: 1)
            private let matchingWorkLimiter = RouteSolveLimiter(limit: 1)
            private var matchingRevision = 0
            /// Coalesces ride/line changes into matching runs; see
            /// ``requestStrokeReferences()``.
            private var matchingDebounceTask: Task<Void, Never>?
            /// The input the running worker matches, and its line generation.
            private var matchingInFlight: (signature: Int, generation: Int)?
            /// The input the last completed worker matched.
            private var matchedSignature: Int?
            /// A change arrived while a same-generation worker was running.
            private var matchingRerunOwed = false
            /// The current burst of change requests: when the last match
            /// started (for the max wait) and when the last request arrived.
            private var matchingBurst: (lastStart: ContinuousClock.Instant, lastRequest: ContinuousClock.Instant)?
            /// Whether the route store is resolving trips (see ``ridesLoadingChanged(_:)``).
            private var ridesAreLoading = false
            /// The route load finished in the update pass now running: its final
            /// publish has nothing left to coalesce (``MatchingSchedule``).
            private var ridesLoadJustFinished = false
            /// Last `NetworkLOD.select` inputs and answer; see ``networkSelection(zoom:buildRect:)``.
            private var networkSelectionMemo: (generation: Int, zoom: Double, buildRect: MKMapRect,
                result: (lines: [RailNetworkStore.DrawnLine], culledOffScreen: Int))?
            /// The last completed chain index and the line generation it was
            /// built for. Kept across generations: the next run updates it
            /// with `StrokeRide.Index.updated(chains:)` and re-matches only
            /// the rides an added, removed or altered chain can affect.
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
            private let annotationReconciler = MapAnnotationReconciler()
            private let tripNoteLayer = MapTripNoteLayer()
            private var tripNoteSnapshot = TripNoteMapSnapshot()
            private var retiringStationOverlays: [ObjectIdentifier: UUID] = [:]
            private var networkAnnotations: [MKAnnotation] = []
            private var rideStationAnnotations: [MKAnnotation] = []
            /// Trip dots the shared station overlay draws. They are NOT map
            /// annotations: a mounted view per dot only provided hit-testing
            /// and a VoiceOver element, and cost an add/remove per level change.
            /// A tap reaches them through ``tappedOverlayRideDot(at:on:)``.
            private var overlayRideDots: [RideStationAnnotation] = []
            /// What the last full rebuild reported, so a rides-only update
            /// can report the same frame with its own ride counts and time.
            private var lastRenderStats: RailMapView.RenderStats?
#if DEBUG
            private var lastDiagnosticSnapshot: MapRenderDiagnostics.Snapshot?
#endif
            private var draftAnnotations: [MKAnnotation] = []
            private var draftSnapshot = DraftMapSnapshot(revision: 0, pins: [])
            private var draftLanguage: String?
            private var endpointAnnotations: [EndpointLabelAnnotation] = []
            private var display = RailMapView.DisplayValues()
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
            /// The scale the mounted network renderers were last rescaled to.
            /// Separate from `styledScale` because a stroke-bucket settle
            /// restyles the marks without touching overlays it will replace.
            private var styledOverlayScale: CGFloat = .nan
#if DEBUG
            private let diagnostics = MapRenderDiagnostics()
            private var pendingRideScanMilliseconds = 0
            private var pendingMaterializeMilliseconds = 0

            func attachDiagnosticsStatus(_ status: UILabel) { diagnostics.status = status }
#endif
            private let interaction = MapInteractionCoordinator()
            private let stationLabels = MapStationLabelCoordinator()

            /// Draft bubbles are not network or ride markers. Missing coordinates
            /// stay off the map; nothing here asks the route solver for a line.
            func reconcileDraftPins(_ snapshot: DraftMapSnapshot, on mapView: MKMapView) {
                let language = MainActor.assumeIsolated { localization?.language.rawValue }
                guard snapshot != draftSnapshot || language != draftLanguage else { return }
                draftSnapshot = snapshot
                draftLanguage = language
                let unfilled = MainActor.assumeIsolated {
                    localization?.text("ios.editor.timeUnfilled") ?? "Time not entered"
                }
                var visitsAtCoordinate: [String: Int] = [:]
                let desired: [MKAnnotation] = snapshot.pins.enumerated().compactMap { offset, pin in
                    guard let latitude = pin.latitude, let longitude = pin.longitude else { return nil }
                    let coordinateKey = "\(latitude)|\(longitude)"
                    let stackPosition = visitsAtCoordinate[coordinateKey, default: 0]
                    visitsAtCoordinate[coordinateKey] = stackPosition + 1
                    let stopTypeLabel = MainActor.assumeIsolated {
                        localization?.countryText(
                            "stoptype.\(pin.stopType)", fallback: pin.stopType) ?? pin.stopType
                    }
                    return DraftStopAnnotation(
                        occurrenceID: pin.occurrenceID,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        index: offset + 1,
                        name: pin.name,
                        stopType: pin.stopType,
                        timeText: pin.timeText,
                        stopTypeLabel: stopTypeLabel,
                        timeLabel: pin.timeText.isEmpty ? unfilled : pin.timeText,
                        stackPosition: stackPosition)
                }
                draftAnnotations = annotationReconciler.reconcile(
                    desired, replacing: draftAnnotations, on: mapView)
            }

            /// Trip-note marks follow the snapshot, the rides and the
            /// selection; the layer returns at once when none of them moved.
            func reconcileTripNotes(_ snapshot: TripNoteMapSnapshot, on mapView: MKMapView) {
                tripNoteSnapshot = snapshot
                renderTripNotes(on: mapView)
            }

            private func renderTripNotes(on mapView: MKMapView) {
                tripNoteLayer.render(
                    tripNoteSnapshot, rides: rides, selectedTrainID: selectedTrainID,
                    routesDrawn: layers.routes, playbackActive: playback?.isActive == true,
                    dateScope: dateScope, language: localization?.language.rawValue,
                    text: tripNoteText, reconciler: annotationReconciler, on: mapView)
            }

            private func tripNoteText() -> MapTripNoteLayer.Text {
                MapTripNoteLayer.Text(
                    marker: { [self] note in
                        let words = note.category.isEmpty ? note.text : note.category
                        return localization?.text("ios.tripNotes.marker.accessibility",
                                                  params: ["text": .string(words)],
                                                  fallback: "Note: {text}") ?? words
                    },
                    place: { [self] note, ride in tripNotePlaceSummary(note.anchor, on: ride) },
                    count: { [self] count in
                        localization?.text("ios.tripNotes.count", params: ["n": .number(Double(count))],
                                           fallback: "Notes: {n}") ?? "\(count)"
                    })
            }

            /// "At A", "A → B", "Pinned on map": named from the trip's own stops,
            /// exactly as the trip card names them.
            private func tripNotePlaceSummary(_ anchor: TripNoteAnchor,
                                              on ride: RiddenRouteStore.DrawnRide) -> String {
                guard let localization else { return "" }
                // The selection snapshot names the trip's stops while it is the
                // selected one; any other ride is named from its own stops.
                let snapshot = tripNoteSnapshot
                let fromTrip = snapshot.selectedTrainID == ride.id && !snapshot.selectedStops.isEmpty
                return TripNotePlaceNaming.place(
                    anchor, stops: fromTrip ? snapshot.selectedStops : ride.stops,
                    region: Region(rawValue: fromTrip ? snapshot.selectedRegion ?? ride.country : ride.country),
                    localization: localization)
            }

            // MARK: trip-note place picking

            private var tripNotePickRevisionSeen = 0
            /// Whether the current pick has been framed. A pick that starts
            /// before its trip's ride is drawn is framed when the ride lands.
            private var tripNotePickFramed = false
            private var tripNotePickRefreshKey: [Double] = []
            private var tripNotePickLastMovingRefresh = ContinuousClock.now

            /// Called from every `updateUIView`. Frames a newly started pick
            /// once, then keeps the pin's feedback current.
            func syncTripNotePick(revision: Int, on mapView: MKMapView) {
                guard let controller else { return }
                guard let trainID = controller.tripNotePickTrainID else {
                    tripNotePickRevisionSeen = revision
                    tripNotePickFramed = false
                    tripNotePickRefreshKey = []
                    return
                }
                if revision != tripNotePickRevisionSeen {
                    tripNotePickRevisionSeen = revision
                    tripNotePickFramed = false
                    tripNotePickRefreshKey = []
                }
                if !tripNotePickFramed, let ride = rides.first(where: { $0.id == trainID }) {
                    tripNotePickFramed = true
                    startTripNotePick(on: ride)
                }
                refreshTripNotePick(on: mapView)
            }

            /// The default framing: the picked trip's own line and stations,
            /// then the note being moved, or the reader's position when
            /// location is already allowed and lies on the line. Never prompts.
            private func startTripNotePick(on ride: RiddenRouteStore.DrawnRide) {
                guard let controller else { return }
                let beads = Array(MapRideMarkers.stopPositions(of: ride).values)
                if let region = MapProjection.region(covering: ride.strokes + [beads]) {
                    controller.frameTripNotePick(region)
                }
                // An unreadable or unplaceable initial anchor frames like none.
                if let initial = controller.tripNotePickInitial,
                   let point = TripNoteGeometry.displayCoordinate(of: initial, on: ride) {
                    controller.centerTripNotePick(on: point.clLocation, animated: false)
                    return
                }
                guard controller.locationIsAuthorized else { return }
                let token = controller.tripNotePickToken()
                Task { @MainActor [weak controller] in
                    guard let controller, case .success(let location) = await controller.currentLocationOnce(),
                          // Stale: the pick ended or restarted, or the reader moved the map.
                          controller.tripNotePickTokenIsCurrent(token),
                          let anchor = TripNoteGeometry.anchor(
                            forLocation: Coordinate(lon: location.coordinate.longitude,
                                                    lat: location.coordinate.latitude), on: ride),
                          let point = TripNoteGeometry.displayCoordinate(of: anchor, on: ride) else { return }
                    controller.centerTripNotePick(on: point.clLocation, animated: true)
                }
            }

            /// Project the point under the pin onto the picked ride. Gated on
            /// the camera, the pin and the ride, so a SwiftUI pass that moved
            /// none of them costs a comparison.
            private func refreshTripNotePick(on mapView: MKMapView) {
                guard let controller, let trainID = controller.tripNotePickTrainID,
                      let ride = rides.first(where: { $0.id == trainID }),
                      let pin = controller.tripNotePickPoint() else { return }
                let visible = mapView.visibleMapRect
                let center = mapView.convert(pin, toCoordinateFrom: mapView)
                let barBottom = controller.tripNotePickBarBottom
                let topInset = mapView.safeAreaInsets.top
                let key = [center.latitude, center.longitude, visible.size.width, Double(pin.x), Double(pin.y),
                           Double(barBottom), Double(topInset), Double(ride.geometryDigest)]
                guard key != tripNotePickRefreshKey else { return }
                tripNotePickRefreshKey = key
                let metersPerPoint = MKMetersPerMapPointAtLatitude(center.latitude)
                    * visible.size.width / max(Double(mapView.bounds.width), 1)
                let pick = TripNoteGeometry.pick(
                    at: Self.coordinate(center), on: ride,
                    maxMeters: 40 * metersPerPoint, stationSnapMeters: max(60, 18 * metersPerPoint))
                let feedback = TripNotePickFeedback(
                    anchor: pick?.anchor,
                    summary: pick.map { tripNotePlaceSummary($0.anchor, on: ride) },
                    pinPoint: pin, barBottom: barBottom, topInset: topInset)
                if controller.tripNotePickFeedback != feedback { controller.tripNotePickFeedback = feedback }
            }

            /// During a pan: at most ten projections a second.
            private func refreshTripNotePickWhileMoving(on mapView: MKMapView) {
                guard controller?.tripNotePickTrainID != nil,
                      ContinuousClock.now - tripNotePickLastMovingRefresh > .milliseconds(100) else { return }
                tripNotePickLastMovingRefresh = .now
                refreshTripNotePick(on: mapView)
            }

            func update(
                lines: [RailNetworkStore.DrawnLine],
                stations: [RailNetworkStore.DrawnStation],
                rides: [RiddenRouteStore.DrawnRide],
                networkExtent: MKCoordinateRegion?,
                selectedTrainID: String?,
                selectedDate: String,
                networkRideDate: String?,
                showsNetwork: Bool,
                layers: MapLayers,
                categoryIndexes: [String: Statistics.EdgeIndex],
                autoFocusRequest: MapCameraPolicy.FocusRequest?,
                display: RailMapView.DisplayValues,
                naming: MapNaming,
                on mapView: MKMapView
            ) {
                let updateInterval = RailSignpost.map.begin("map.update")
                defer { RailSignpost.map.end("map.update", updateInterval) }
                // Input preparation also rebuilds station and line indexes.
                // Keep the installed frame stable while fingers move, and
                // coalesce arriving data into the newest update for release.
                if isManipulating {
                    pendingViewUpdate = { [weak self, weak mapView] in
                        guard let self, let mapView, self.mapView === mapView else { return }
                        self.update(
                            lines: lines, stations: stations, rides: rides,
                            networkExtent: networkExtent,
                            selectedTrainID: selectedTrainID, selectedDate: selectedDate,
                            networkRideDate: networkRideDate,
                            showsNetwork: showsNetwork, layers: layers,
                            categoryIndexes: categoryIndexes,
                            autoFocusRequest: autoFocusRequest,
                            display: display, naming: naming, on: mapView)
                    }
                    rebuildDeferredByGesture = true
                    return
                }
                // A newer normal update supersedes any queued gesture update.
                pendingViewUpdate = nil
                // Consumed only by an update that runs (not a deferred one).
                defer { ridesLoadJustFinished = false }
                let regionalDayChanged = refreshNetworkToday()
                // A sheet drag and a menu presentation can call
                // `updateUIView` every frame while these arrays still share
                // their exact backing buffers with the coordinator. Take that
                // O(1) path before allocating thousands of ids/signatures.
                // Against the newest staged set when a swap is pending, so the
                // same set arriving again does not start another computation.
                let linesChanged = Self.changed(
                    lines, from: pendingLineSwap?.lines ?? self.lines, id: \.contentID)
                let stationsChanged = Self.changed(
                    stations, from: pendingLineSwap?.stations ?? self.stations, id: \.contentID)
                // Digested once per ride of the new array; the applied deck
                // keeps the old digests, so nothing is hashed twice.
                let deckUpdate = ArrayGeneration.same(rides, self.rides)
                    ? nil : rideDeck.advanced(to: rides)
                let ridesChanged = rides.count != self.rides.count
                    || deckUpdate.map { !$0.change.isEmpty } == true
                let previousSelectedTrainID = self.selectedTrainID
                let selectionChanged = selectedTrainID != previousSelectedTrainID
                if selectionChanged { selectionNeedsHighlightTransition = true }
                let focusRequest = controller?.pendingAutoFocusRequest(matching: autoFocusRequest)
                let visibilityChanged = showsNetwork != self.showsNetwork
                    || layers != self.layers
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
                // Only the ride-date era reads the date; elsewhere it must not
                // look like a network change (selection picks change it).
                let networkRideDate = display.networkEra.effectiveRideDate(networkRideDate)
                let rideDateChanged = networkRideDate != self.networkRideDate
                let eraChanged = display.networkEra != self.display.networkEra
                let routePaintOnly = displayChanged
                    && !eraChanged
                    && display.markers == self.display.markers
                    && display.focusBoost == self.display.focusBoost
                    && display.dimOpacity == self.display.dimOpacity
                    && display.showFullCrossDay == self.display.showFullCrossDay
                // The date scope is paint, not a filter: it decides which
                // rides draw at `dimOpacity` and which half of an overnight
                // one is dashed. Both are properties of things already built,
                // so a scope change is a rebuild like the others.
                let dateChanged = selectedDate != self.selectedDate
                let networkFilterChanged = rideDateChanged || eraChanged || regionalDayChanged
                let namingChanged = naming != self.naming
                if namingChanged { stationLabels.invalidateLabelWidths() }
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
                        || displayChanged || dateChanged
                        || networkFilterChanged
                        || namingChanged || focusRequest != nil || extentChanged else { return }

                if ridesChanged || indexesChanged {
                    categoryVisibility.invalidate()
                }
                self.layers = layers
                self.categoryIndexes = categoryIndexes

                self.display = display
                self.networkRideDate = networkRideDate
                self.selectedDate = selectedDate
                self.naming = naming
#if DEBUG
                if showsNetwork != self.showsNetwork { diagnostics.networkVisibilityChanged(showsNetwork) }
#endif
                self.showsNetwork = showsNetwork
                self.selectedTrainID = selectedTrainID
                if ridesChanged, let deckUpdate {
                    self.rides = rides
                    rideDeck = deckUpdate.next
                    retainRidePolylines(changed: deckUpdate.change)
                }
                renderTripNotes(on: mapView)
                prepareSelectedStationImportance(on: mapView)
                // The tap cull's geometry moved. Dropped rather than rebuilt:
                // `update` runs inside a SwiftUI pass, and a pass over every
                // ridden vertex is the thing this index exists to keep out of
                // one. See ``MapInteractionCoordinator/invalidateRideGeometry()``.
                //
                // Three ways for it to move, and only the first is the rides
                // themselves. A category switched off takes its segments out of
                // the index, and a region's edge index ARRIVING is what lets
                // those segments be classified at all — before it lands every
                // one of them is undetermined and therefore drawn, so the tap
                // geometry the reader ends up with is not the one built a
                // moment earlier.
                if ridesChanged || categoriesChanged || indexesChanged {
                    interaction.invalidateRideGeometry()
                }
                // Residency loads and evictions change `lines` all the time
                // while zooming, and installing a set costs a junction-index
                // update over every changed line. So the set is computed on a
                // worker and installed whole in one main-actor turn
                // (`applyLineSwap`); the previous set stays drawn meanwhile.
                // Only a changed temporal era, ride date or day (which makes
                // every old result wrong) installs it here, synchronously.
                let swapChanged = linesChanged || stationsChanged
                let appliesSwapNow = swapChanged && networkFilterChanged
                if appliesSwapNow {
                    lineSwapTask?.cancel()
                    lineSwapTask = nil
                    heldLineSwap = nil
                    pendingLineSwap = nil
                    lineSwapSchedule.appliedSynchronously()
                    if let result = Self.computeLineSwap(
                        swapInput(lines: lines, stations: stations),
                        baseSerial: lineSwapSchedule.appliedSerial, checksCancellation: false
                    ) {
                        installLineSwap(result, cancelsPreparation: true)
                    }
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

                if swapChanged && !appliesSwapNow {
                    stageLineSwap(lines: lines, stations: stations)
                }
                if appliesSwapNow || ridesChanged {
                    requestStrokeReferences()
                }

                let selectedRide = rides.first { $0.id == selectedTrainID }
                let selectionRegion = selectedRide.flatMap { self.selectionRegion(for: $0) }
                let controller = self.controller
                // Only an explicit selection request can move the camera.
                // The controller consumes it once across renderer replacements.
                // Loading can finish a pending pick; restored selection alone
                // and edits do not manufacture a camera request.
                let focusRegion: MKCoordinateRegion?
                let waitsForJourneyGeometry: Bool
                switch focusRequest?.target {
                case .journey(let id) where id == selectedTrainID:
                    focusRegion = selectionRegion
                    waitsForJourneyGeometry = true
                case .date(let date) where date == selectedDate && selectedTrainID == nil:
                    focusRegion = MapProjection.region(covering: rides
                        .filter { $0.daySpan.date == date }.flatMap(\.strokes))
                    waitsForJourneyGeometry = false
                default:
                    focusRegion = nil
                    waitsForJourneyGeometry = false
                }
                if focusRequest != nil, focusRegion == nil, !waitsForJourneyGeometry {
                    // Date changes do not queue a later camera move. A direct
                    // journey pick stays pending until its route is available;
                    // a gesture, another pick or deselection supersedes it.
                    _ = controller?.takeAutoFocusRequest(matching: focusRequest)
                }
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView, self.mapView === mapView,
                        controller?.mapView === mapView else { return }
                    controller?.selectionRegion = self.rides.first(where: { $0.id == self.selectedTrainID })
                        .flatMap { self.selectionRegion(for: $0) }
                    if let focusRequest, case .journey = focusRequest.target {
                        self.focusPendingJourney(on: mapView)
                        return
                    }
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
                if selectionChanged {
                    updateRidePaint(on: mapView, animated: playback?.isActive != true)
                }
                // A staged set changes nothing drawn yet: its own plan runs when
                // it is installed, so the rides-only fast path below still works.
                let changes = MapDrawChanges(
                    linesChanged: linesChanged && appliesSwapNow,
                    stationsChanged: stationsChanged && appliesSwapNow,
                    ridesChanged: ridesChanged,
                    selectionChanged: selectionChanged,
                    visibilityChanged: visibilityChanged,
                    indexesChanged: indexesChanged,
                    displayChanged: displayChanged,
                    routePaintOnly: routePaintOnly,
                    dateChanged: dateChanged,
                    networkFilterChanged: networkFilterChanged,
                    namingChanged: namingChanged,
                    showsNetwork: showsNetwork,
                    hasRides: !rides.isEmpty,
                    hasContinuousLines: self.lines.contains(where: \.continuous)
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
                        // A stroke build running for the ride just left is
                        // wasted only when it was for that ride alone: a build shared with
                        // other rides finishes (latest pick wins on its landing).
                        if let previous = previousSelectedTrainID, rideStrokePreparation != nil,
                           rideStrokePreparationRideIDs == [previous] {
                            rideStrokePreparation?.cancel()
                            rideStrokePreparation = nil
                            rideStrokePreparationID = UUID()
                        }
                        rebuildOwed(on: mapView)
                    }
                case .rebuild:
                    // Only rides moved: re-form the batches of the cells they
                    // touch and re-mark, instead of the whole map.
                    let ridesOnly = ridesChanged && !appliesSwapNow
                        && !selectionChanged && !visibilityChanged && !indexesChanged
                        && !displayChanged && !dateChanged && !networkFilterChanged && !namingChanged
                    if ridesOnly, let change = deckUpdate?.change, updateRides(change, on: mapView) {
                        break
                    }
                    rebuildOwed(on: mapView, tripsOnly: ridesOnly)
                }
#if DEBUG
                if selectionChanged || ridesChanged {
                    diagnostics.updateBasemapStatus(on: mapView)
                }
#endif
            }

            /// The old full-rebuild branch, unchanged, extracted so the
            /// `.rebuild` dispatch and both of `.selectionOnly`'s slow cases —
            /// a hand-off during a run, and a fast path that cannot answer
            /// from cached state — share it.
            ///
            /// `tripsOnly` is set when nothing but trips changed and the small
            /// update could not answer. A line preparation in flight is then
            /// for the same lines and frame, so it is left to finish
            /// (``MapRebuildOwedPolicy``): cancelling it on every arrival is
            /// what kept the first full draw from ever landing during a load.
            private func rebuildOwed(
                on mapView: MKMapView, tripsOnly: Bool = false, lineDataOnly: Bool = false
            ) {
                let policy = MapRebuildOwedPolicy(tripsOnly: tripsOnly, lineDataOnly: lineDataOnly)
                if policy.cancelsGeometryPreparation { cancelGeometryPreparation() }
                if policy.invalidatesLaneZoom {
                    networkBuildState.invalidateGeometry()
                } else if policy.invalidatesZoomBucket {
                    networkBuildState.invalidateZoomBucket()
                }
                if policy.invalidatesMarkerContext { markerBuildContext = nil }
                // Not during a run, for the reason `regionDidChangeAnimated`
                // gives — and this is the path that actually hurt. The
                // transport moves the selection from journey to journey as
                // it plays (`RailWorkspaceView`'s `onChange(of:playback.currentTrainID)`),
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
                    noteRebuildTrigger(policy.trigger)
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
            /// edit has to pass (the first is `AppShell.routeLoadKey`), and
            /// a gate that only counts holds the reloaded ride back at exactly
            /// the edits the reload existed to show.
            static func rideSignature(_ ride: RiddenRouteStore.DrawnRide) -> String {
                "\(ride.id):\(ride.geometryDigest):\(ride.colorHex):\(ride.visible ? 1 : 0)"
                    + ":\(ride.trainType ?? ""):\(RideDeckState.stopsDigest(ride.stops)):\(ride.daySpan.sig)"
            }

            /// Compare collection generations without allocating parallel id
            /// arrays. A count change is already a complete answer, which is
            /// the common case while regional packages stream in at launch.
            private static func changed<Element, Identity: Equatable>(
                _ next: [Element], from current: [Element],
                id: KeyPath<Element, Identity>
            ) -> Bool {
                guard next.count == current.count else { return true }
                guard !ArrayGeneration.same(next, current) else { return false }
                return !zip(next, current).allSatisfy {
                    $0[keyPath: id] == $1[keyPath: id]
                }
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
            /// initialiser, which `RailWorkspaceView` calls — so the table would be
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
                _ name: String, code: String? = nil, region: Region? = nil, stationID: String? = nil,
                lookupByName: Bool = true
            ) -> Named {
                guard !name.isEmpty, let localization else {
                    return Named(display: name, readings: [])
                }
                if let stationID, !stationID.isEmpty {
                    let display = RegistryStationDisplay.resolve(
                        storedName: name, stationID: stationID, region: region?.code)
                    if display.unresolved {
                        return Named(display: name, readings: [
                            .init(kind: .zh, text: localization.text(RegistryStationDisplay.unresolvedKey))
                        ])
                    }
                    return MainActor.assumeIsolated {
                        let namingRegion = region
                            ?? SolverRegistryInput.regionCode(stationID).flatMap(Region.init(rawValue:))
                        let readingCode = localization.preferredReadingCode(
                            display.readingCodes, region: namingRegion, fallback: code)
                        return Named(
                            display: localization.stationName(
                                display.primary, code: readingCode, region: namingRegion, allowNameFallback: false),
                            readings: localization.nameReadingsTyped(
                                display.primary, code: readingCode, region: namingRegion, allowNameFallback: false))
                    }
                }
                // A code is a package id, not a name. Name lookup is not an identity.
                if !lookupByName || code?.isEmpty != false {
                    let word = localization.text(RegistryStationDisplay.unresolvedKey)
                    return Named(display: name, readings: [
                        .init(kind: .zh, text: word)
                    ])
                }
                return MainActor.assumeIsolated {
                    Named(
                        display: localization.stationName(
                            name, code: code, region: region, allowNameFallback: false),
                        readings: localization.nameReadingsTyped(
                            name, code: code, region: region, allowNameFallback: false))
                }
            }

            /// A station name as a map marker prints it: the localized name
            /// only. A stop with no registry identity keeps its stored name;
            /// the identity state is the trip card's to show, never a marker's.
            func mapStationLabel(
                _ name: String, code: String?, region: Region?, stationID: String?
            ) -> String {
                guard let stationID, !stationID.isEmpty else { return name }
                return localized(name, code: code, region: region, stationID: stationID).display
            }

            /// Keep mounted layers while the camera moves. One deadline timer
            /// coalesces gesture, inertia, resize and data-arrival rebuilds;
            /// a camera frame only moves its deadline.
            private let cameraRebuildTimer = MapDeadlineTimer(delay: .milliseconds(120))
            private var pendingViewUpdate: (@MainActor () -> Void)?
            private var lastCameraChange: ContinuousClock.Instant?

            /// Cancel work and release bridges installed by this coordinator when
            /// SwiftUI replaces the map during a composition or window-size change.
            /// A replacement map may already own the shared controllers by the time
            /// dismantling runs, so shared hooks are cleared only while they still
            /// identify this coordinator or this exact map view.
            func tearDown(_ dismantledMapView: MKMapView) {
                selectedStationSnapshots.tearDown()
                drawnLineBuilds = []
                drawnExtraPolylines = [:]
                if let memoryWarningObserver {
                    NotificationCenter.default.removeObserver(memoryWarningObserver)
                }
                memoryWarningObserver = nil
                cameraRebuildTimer.cancel()
                markerSettleTurn.cancel()
                #if DEBUG
                // A new coordinator's initial debt does not fire didSet, so a
                // debt owed at teardown must not leave the probe stuck true.
                MapRenderProbe.markerPassOwed = false
                #endif
                travelStopTimer.cancel()
                stationLabels.tearDown()
                pendingViewUpdate = nil
                viewportResizeTask?.cancel()
                viewportResizeTask = nil
                matchingTask?.cancel()
                matchingTask = nil
                lineSwapTask?.cancel()
                lineSwapTask = nil
                heldLineSwap = nil
                pendingLineSwap = nil
                // Whatever the worker still delivers is stale: it lands as a
                // discard (never an apply into the torn-down coordinator) and
                // frees the schedule.
                lineSwapSchedule.appliedSynchronously()
                memoryReliefTask?.cancel()
                memoryReliefTask = nil
                matchingDebounceTask?.cancel()
                matchingDebounceTask = nil
                matchingInFlight = nil
                matchedSignature = nil
                matchingRerunOwed = false
                matchingBurst = nil
                matchingRevision += 1
                pendingStrokeRefs = nil
                networkSelectionMemo = nil
                cancelGeometryPreparation()
                markerBuildContext = nil
                annotationReconciler.removeRetiring(on: dismantledMapView)
                overlayInstaller.removeRetiring(on: dismantledMapView)
                retiringStationOverlays.removeAll()
                overlayStyles.removeAll()
                batchedRidePartCounts = [:]
                interaction.tearDown()
#if DEBUG
                diagnostics.tearDown()
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
                    controller?.selectedStationFailure = nil
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
                // A newer camera move supersedes a marker pass still waiting
                // for its turn; the debt stays owed and this settle pays it.
                markerSettleTurn.cancel()
                cameraRebuildTimer.schedule { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    guard !self.isManipulating else {
                        self.rebuildDeferredByGesture = true
                        return
                    }
                    let settledInterval = RailSignpost.map.begin("map.cameraSettled")
                    defer { RailSignpost.map.end("map.cameraSettled", settledInterval) }
                    // A line set that landed during the gesture installs now,
                    // before the update that may have been queued behind it.
                    self.applyHeldLineSwap()
                    let pendingUpdate = self.pendingViewUpdate
                    self.pendingViewUpdate = nil
                    pendingUpdate?()
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                        return
                    }
                    self.rebuildDeferredByGesture = false
                    // The fingers are up: lines held for stable joints take the
                    // strokes their neighbours now imply.
                    if !self.heldJointLineIDs.isEmpty {
                        self.refreshLineInputs()
                        self.networkBuildState.invalidateGeometry()
                    }
                    // Overlays about to be replaced keep their width; the
                    // rebuild's install rescales the new ones once.
                    let zoom = MapProjection.zoomLevel(of: mapView)
                    self.restyle(on: mapView, overlays: !self.strokeBucketPending(at: zoom))
                    self.noteRebuildTrigger(.cameraSettled)
                    // Overlays now, markers and labels on the next run-loop
                    // turn: a display-link frame can fire between the two.
                    self.rebuild(on: mapView, deferMarkers: true)
                    self.scheduleMarkerSettleTurn(on: mapView)
                }
            }

            /// Pays the marker debt a deferred settle rebuild left, on the next
            /// main run-loop turn. Superseded by a newer schedule or camera move,
            /// and a no-op once any full pass has run or the camera moves again;
            /// the debt then stays owed for the next settle. It reads the
            /// current build context, so it never applies an older build's markers.
            private func scheduleMarkerSettleTurn(on mapView: MKMapView) {
                guard markerPassDebt.isOwed else { return }
                let token = markerSettleTurn.schedule()
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, let mapView, self.mapView === mapView,
                          self.markerSettleTurn.claim(token) else { return }
                    let moving = self.isManipulating
                        || self.lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) == true
                    guard MarkerSettleTurn.runsFullPass(
                        debtOwed: self.markerPassDebt.isOwed, cameraMoving: moving) else { return }
                    self.runLabelPass(on: mapView, moving: false, fullPass: true)
                }
            }

            var preservesCameraDuringResize: Bool {
                !isManipulating && playback?.isActive != true
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
                        self.noteRebuildTrigger(.viewportResized)
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
                // Fires at display rate while the camera moves: Instruments only, never the
                // in-process recorder, whose ring and byName top rows it would flood.
                let regionTickState = RailSignpost.map.isEnabled && !RailSignpost.isSuppressed
                    ? RailSignpost.map.beginInterval("map.regionTick", id: RailSignpost.map.makeSignpostID()) : nil
                defer { if let regionTickState { RailSignpost.map.endInterval("map.regionTick", regionTickState) } }
#if DEBUG
                let regionTickStarted = ContinuousClock.now
                defer {
                    diagnostics.didRunRegionTick(
                        milliseconds: (ContinuousClock.now - regionTickStarted).milliseconds)
                }
                diagnostics.cameraChanged(manipulating: isManipulating)
#endif
                // Wheel, inertia and the first MapKit camera callback can
                // precede a touch sensor. Keep mounted styles stable for all
                // camera motion; the quiet-period task applies the final scale.
                // Screen-space work: these labels de-overlap each other and
                // clamp to the window's edges, so a label clamped at the right
                // edge stayed clamped after a pan carried it into the middle.
                layoutEndpointLabels(on: mapView)
                restoreRideMarkerStacking()
                refreshTripNotePickWhileMoving(on: mapView)
                lastCameraChange = .now
                let zoom = MapProjection.zoomLevel(of: mapView)
                zoomTravel.note(zoom: zoom, at: Self.seconds(.now))
                if travelPreparationOwesStopRebuild { scheduleTravelStopRebuild(on: mapView) }
#if DEBUG
                MapRenderProbe.geometryLevels.wanted = wantedGeometryLevel(at: zoom)
                MapRenderProbe.geometryLevels.cameraZoom = zoom
#endif
                cancelNeighbourPrebuildIfWantedSetMoved(zoom: zoom)
                swapGeometryDuringGestureIfReady(zoom: zoom, on: mapView)
                runMovingLoadPass(zoom: zoom, on: mapView)
                scheduleCameraRebuild(on: mapView)
                // Names update on their own quarter-zoom cadence, well ahead of
                // the full rebuild's 120 ms debounce — gated by the previous
                // moving pass's cost, so an expensive pass does not compound one
                // every callback.
                stationLabels.runMovingPass(at: zoom) {
                    runLabelPass(on: mapView, moving: true)
                }
                restartLabelSettleTask(on: mapView)
            }

            /// Debounces the settle-time label pass (and `restyle`) behind the
            /// camera's own quiet period, independent of the full rebuild's
            /// 120 ms debounce — a settle pass is much cheaper and can safely
            /// run sooner.
            private func restartLabelSettleTask(on mapView: MKMapView) {
                stationLabels.scheduleSettledPass { [weak self, weak mapView] in
                    guard let self, let mapView else { return }
                    guard !self.isManipulating,
                          self.playback?.isActive != true,
                          self.playbackLayer.lastSnapshot == nil
                    else { return }
                    // Let the full rebuild re-elect names when its LOD or extent
                    // will change, avoiding captions that immediately get replaced.
                    let zoom = MapProjection.zoomLevel(of: mapView)
                    if let context = self.markerBuildContext {
                        let visibilityZoom = self.networkVisibility(on: mapView).visibilityZoom(cameraZoom: zoom)
                        if visibilityZoom != context.visibilityZoom
                            || !context.buildRect.contains(mapView.visibleMapRect) {
                            return
                        }
                    }
                    // A stroke-bucket change replaces every network overlay, so
                    // leave their widths to the rebuild (no tile drawn twice).
                    // Marks and names do not wait for that geometry: settle
                    // them now, on the moving pass's anchors.
                    if self.strokeBucketPending(at: zoom) {
                        self.restyle(on: mapView, overlays: false)
                        self.runLabelPass(on: mapView, moving: true)
                        return
                    }
                    // A rebuild during the gesture left the full marker pass owed.
                    if self.markerPassDebt.isOwed {
                        self.restyle(on: mapView)
                        if self.runLabelPass(on: mapView, moving: false, fullPass: true) {
                            return
                        }
                        _ = self.runLabelPass(on: mapView, moving: false)
                        return
                    }
                    self.restyle(on: mapView)
                    self.runLabelPass(on: mapView, moving: false)
                }
            }


            func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
                // A framing animation a focus request started has settled.
                controller?.endFocusFit()
                if controller?.tripNotePickTrainID != nil { refreshTripNotePick(on: mapView) }
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
#if DEBUG
                let statusCamera = mapView.camera
                let heading = statusCamera.heading
                if !isManipulating { diagnostics.updateLiveStatus(on: mapView, camera: statusCamera, builtRect: networkBuildState.builtRect) }
#else
                let heading = mapView.camera.heading
#endif
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
                noteRebuildTrigger(.appearanceChanged)
                rebuild(on: mapView)
            }


            private var geometryPreparation: Task<Void, Never>?
            /// Preparations started, cancelled and finished; full rebuilds and
            /// trip-line cache misses by what triggered them. Counts only,
            /// reported as signposts.
            private var drawCounters = MapDrawCounters()
            private var pendingRebuildTrigger: MapRebuildTrigger?

            /// Records why the next full rebuild runs (the `map.rebuild.trigger`
            /// signpost) so the rebuild can count itself under that trigger.
            private func noteRebuildTrigger(_ trigger: MapRebuildTrigger) {
                pendingRebuildTrigger = trigger
                RailSignpost.map.mark("map.rebuild.trigger", trigger.rawValue)
            }
            private var geometryPreparationID = UUID()
            private var geometryPreparationKey: String?
            /// The rect the preparation in flight was prepared for.
            private var geometryPreparationRect: MKMapRect?
            /// The geometry level the preparation in flight builds.
            private var geometryPreparationLevel: Int? {
                didSet {
#if DEBUG
                    MapRenderProbe.geometryLevels.preparing = geometryPreparationLevel
#endif
                }
            }

            private var networkTemporalContext: DisplayNetworkTemporalContext {
                DisplayNetworkTemporalContext(
                    era: display.networkEra, rideDate: networkRideDate,
                    todayByRegion: networkTodayByRegion, generation: linesGeneration)
            }

            /// Preparation, installation and cancellation share one identity
            /// for the captured temporal view. Per-line content retention owns
            /// input invalidation; the complete context guards worker publication.
            private var geometryEraKey: String { networkTemporalContext.cacheKey }

            private func invalidateNetworkTemporalGeometry(cancelsPreparation: Bool) {
                if cancelsPreparation { cancelGeometryPreparation() }
                cancelNeighbourPrebuild()
                networkBuildState.invalidateGeometry()
                annotationsNeedRefresh = true
                markerBuildContext = nil
            }

            @discardableResult
            private func refreshNetworkToday() -> Bool {
                let snapshot = MainActor.assumeIsolated {
                    Dictionary(uniqueKeysWithValues: RegionToday.byRegion().map { ($0.key.rawValue, $0.value) })
                }
                guard snapshot != networkTodayByRegion else { return false }
                networkTodayByRegion = snapshot
                invalidateNetworkTemporalGeometry(cancelsPreparation: true)
                return true
            }

            private func cancelGeometryPreparation() {
                guard geometryPreparation != nil else { return }
                if drawCounters.preparations.cancel() {
                    RailSignpost.map.mark("map.geometry.prep.cancelled", drawCounters.preparations.cancelled)
                }
                geometryPreparation?.cancel()
                geometryPreparation = nil
                geometryPreparationKey = nil
                geometryPreparationRect = nil
                geometryPreparationLevel = nil
                geometryPreparationID = UUID()
            }


            // MARK: - geometry levels

            /// The level the installed overlays were built at.
            private var installedGeometryLevel: Int? { currentGeometryFrame?.bucket }

            /// The level the camera wants, with hysteresis around the installed one.
            private func wantedGeometryLevel(at zoom: Double) -> Int {
                GeometryZoomLevels.wantedLevel(zoom: zoom, installed: installedGeometryLevel)
            }

            /// A landed level to install ahead of the wanted one, set by
            /// `landingDecision` and cleared when a rebuild commits
            /// (``GeometryZoomLevels/installsLanded(landed:installed:zoom:ready:)``).
            /// `rect` is the rect the level was prepared for (nil: the camera's
            /// own padded rect is ready); the install builds and commits that
            /// rect, and a later preparation adds the padding. `visibilityZoom`
            /// and `visibilityBucket` are the camera zoom the preparation was
            /// made for when that is not the camera's own (a level prepared
            /// ahead of a zoom-out), nil otherwise.
            private struct PendingInstall {
                var level: Int
                var rect: MKMapRect?
                var visibilityZoom: Double?
                var visibilityBucket: Int?
            }
            private var pendingInstall: PendingInstall? {
                didSet {
#if DEBUG
                    MapRenderProbe.geometryLevels.pending = pendingInstall?.level
#endif
                }
            }

            /// The installed level changed to a landed one, so the wanted level
            /// still has to start preparing.
            private var wantedLevelFollowUpOwed = false

            /// The level a rebuild builds and installs: a landed pending level
            /// while it is still complete, else the camera's wanted level.
            private func geometryLevelToBuild(at zoom: Double, on mapView: MKMapView) -> Int {
                if let pending = pendingInstall {
                    // A pending rect must still contain what is on screen.
                    let covers = pending.rect.map { $0.contains(mapView.visibleMapRect) } ?? true
                    if covers, isGeometryLevelReady(
                        pending.level, zoom: zoom, on: mapView, buildRect: pending.rect,
                        visibilityZoom: pending.visibilityZoom) {
                        return pending.level
                    }
                    pendingInstall = nil
                }
                return wantedGeometryLevel(at: zoom)
            }

            private func geometryFrame(level: Int, on mapView: MKMapView) -> MapGeometryFrame {
                MapGeometryFrame(level: level, eraKey: geometryEraKey, on: mapView)
            }

            /// The lines and strokes `frame`'s level still lacks for `buildRect`.
            /// Geometry is cached per frame entry, that is per (line id, level,
            /// stroke generation), so a level revisited reuses its builds.
            private func missingGeometryWork(
                frame: MapGeometryFrame, visibilityZoom: Double, buildRect: MKMapRect,
                recordsDiagnostics: Bool
            ) -> (
                lines: [RailNetworkStore.DrawnLine], strokes: [RailNetworkStore.DrawnLine],
                byID: [String: RailNetworkStore.DrawnLine]
            ) {
                let key = frame.key
                let selected = showsNetwork
                    ? networkSelection(zoom: visibilityZoom, buildRect: buildRect).lines
                        .filter { !$0.continuous || $0.intervalRects.contains { $0.intersects(buildRect) } }
                    : []
                var needed = Set(selected.filter(\.continuous).map(\.id))
                var selectedStrokeLineIDs: Set<String> = []
                let rideRect = NetworkLOD.tripArea(
                    buildRect: buildRect, mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint)
#if DEBUG
                let rideScanStarted = ContinuousClock.now
#endif
                if layers.routes {
                    for ride in rides where ride.visible {
                        let flags = ride.stops
                        for segment in ride.segments {
                            guard (ride.id == selectedTrainID || segment.boundingRect.intersects(rideRect)),
                                  draws(segment: segment, of: ride, riddenStops: flags),
                                  let ref = strokeRef(for: segment, of: ride) else { continue }
                            needed.insert(ref.chainID)
                            if ride.id == selectedTrainID { selectedStrokeLineIDs.insert(ref.chainID) }
                        }
                    }
                }
#if DEBUG
                if recordsDiagnostics {
                    pendingRideScanMilliseconds =
                        (ContinuousClock.now - rideScanStarted).milliseconds
                }
#endif
                let byID = linesByID()
                let missingLines = selected.filter { !networkGeometry.hasLineBuild(for: $0.id, in: key) }
                let missingStrokes = needed.compactMap { id -> RailNetworkStore.DrawnLine? in
                    guard !networkGeometry.hasStrokeBuild(for: id, in: key) else { return nil }
                    guard let line = byID[id],
                          selectedStrokeLineIDs.contains(id)
                            || line.intervalRects.contains(where: { $0.intersects(rideRect) }) else { return nil }
                    return line
                }
                return (missingLines, missingStrokes, byID)
            }

            /// Every line by id, built once per lines generation: the readiness
            /// check runs every 250 ms during a gesture.
            private func linesByID() -> [String: RailNetworkStore.DrawnLine] {
                if let linesByIDCache, linesByIDCache.generation == linesGeneration {
                    return linesByIDCache.byID
                }
                let byID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                linesByIDCache = (linesGeneration, byID)
                return byID
            }
            private var linesByIDCache: (generation: Int, byID: [String: RailNetworkStore.DrawnLine])?

            /// Whether `level` has everything `buildRect` (default: the camera's
            /// padded build rect) selects at the camera's zoom.
            private func isGeometryLevelReady(
                _ level: Int, zoom: Double, on mapView: MKMapView, buildRect: MKMapRect? = nil,
                visibilityZoom: Double? = nil
            ) -> Bool {
                let visibilityZoom = visibilityZoom
                    ?? networkVisibility(on: mapView).visibilityZoom(cameraZoom: zoom)
                let buildRect = buildRect ?? NetworkLOD.buildRect(for: mapView.visibleMapRect)
                let work = missingGeometryWork(
                    frame: geometryFrame(level: level, on: mapView),
                    visibilityZoom: visibilityZoom, buildRect: buildRect, recordsDiagnostics: false)
                return work.lines.isEmpty && work.strokes.isEmpty
            }

            /// Mid-pinch: once the camera has drifted far enough from the
            /// installed level and the wanted level is already prepared, install
            /// it now rather than at lift-off. The install also rescales every
            /// renderer's width to the live zoom, so widths are not frozen for
            /// the whole gesture.
            private func swapGeometryDuringGestureIfReady(zoom: Double, on mapView: MKMapView) {
                guard cameraTravelling, playbackLayer.lastSnapshot == nil, showsNetwork,
                      let installed = installedGeometryLevel else { return }
                let wanted = wantedGeometryLevel(at: zoom)
                // Cheap test first; readiness walks the selection.
                guard GeometryZoomLevels.shouldSwapDuringGesture(
                    zoom: zoom, installed: installed, wanted: wanted, wantedIsReady: true)
                else { return }
                let now = ContinuousClock.now
                if let last = lastGestureSwapAttempt, now - last < .milliseconds(250) { return }
                lastGestureSwapAttempt = now
                if !isGeometryLevelReady(wanted, zoom: zoom, on: mapView) {
                    // A long pinch outgrows every padded rect, so the wanted
                    // level never lands ready. A landed level waiting on its
                    // own prepared rect installs instead, as it would after
                    // lift-off, when it is nearer the camera than the
                    // installed one and still covers the screen.
                    guard let pending = pendingInstall, let rect = pending.rect,
                          rect.contains(mapView.visibleMapRect),
                          isGeometryLevelReady(
                            pending.level, zoom: zoom, on: mapView, buildRect: rect,
                            visibilityZoom: pending.visibilityZoom),
                          GeometryZoomLevels.installsLanded(
                            landed: pending.level, installed: installed, zoom: zoom, ready: true)
                    else { return }
                }
                noteRebuildTrigger(.levelSwapped)
                rebuild(on: mapView, duringGesture: true, deferMarkers: true)
            }

            private var lastGestureSwapAttempt: ContinuousClock.Instant?

            // MARK: loading while the camera moves

            private static let clockOrigin = ContinuousClock.now
            private static func seconds(_ instant: ContinuousClock.Instant) -> Double {
                let d = instant - clockOrigin
                return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
            }
            private static func buildAreaRect(_ rect: MKMapRect) -> MapBuildArea.Rect {
                .init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
            }
            private static func mapRect(_ rect: MapBuildArea.Rect) -> MKMapRect {
                MKMapRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            }

            private var loadAheadLastPass: Double?
            private var loadAheadSample: (rect: MapBuildArea.Rect, at: Double)?
            private var loadAheadVelocity = MapLoadAhead.Velocity.zero
            /// Set only while a moving-camera extension rebuild runs: the area
            /// that rebuild builds for, ahead of travel.
            private var movingBuildRect: MKMapRect?
            private var lastMovingExtension: Double?
            /// Lines loaded while the fingers were down; owes an extension pass.
            private var linesArrivedWhileMoving = false

            /// While the camera moves (pan, fling, zoom), about every 200 ms:
            /// ask the loader for the visible rect extended in the direction of
            /// travel plus a margin ring, and, when the built area no longer
            /// covers a screen ahead, add the newly loaded area at the
            /// installed level. Never waits for the gesture to end, and never
            /// unloads or replaces what is drawn (batches are add-only).
            private func runMovingLoadPass(zoom: Double, on mapView: MKMapView) {
                guard showsNetwork, playbackLayer.lastSnapshot == nil, mapView.bounds.width > 1,
                      mapView.bounds.height > 1 else { return }
                let now = Self.seconds(.now)
                guard MapLoadAhead.isDue(now: now, lastPass: loadAheadLastPass) else { return }
                loadAheadLastPass = now
                let visible = Self.buildAreaRect(mapView.visibleMapRect)
                if let sample = loadAheadSample, now - sample.at <= 1 {
                    loadAheadVelocity = MapLoadAhead.velocity(
                        from: sample.rect, to: visible, elapsed: now - sample.at)
                } else {
                    loadAheadVelocity = .zero
                }
                loadAheadSample = (visible, now)
                let visibilityZoom = networkVisibility(on: mapView).visibilityZoom(cameraZoom: zoom)
                onBuildRect(
                    Self.mapRect(MapLoadAhead.requestRect(visible: visible, velocity: loadAheadVelocity)),
                    visibilityZoom)
                if cameraTravelling {
                    startTravelPreparation(zoom: zoom, on: mapView)
                    extendTripsAtInstalledLevel(on: mapView)
                }
                extendBuiltAreaWhileMoving(zoom: zoom, visible: visible, on: mapView)
            }

            /// Add-only extension at the unchanged installed level.
            private func extendBuiltAreaWhileMoving(
                zoom: Double, visible: MapBuildArea.Rect, on mapView: MKMapView
            ) {
                guard isManipulating, let installed = installedGeometryLevel,
                      wantedGeometryLevel(at: zoom) == installed,
                      !networkBuildState.builtRect.isNull else { return }
                let built = networkBuildState.builtRect
                let velocity = loadAheadVelocity
                let linesArrived = linesArrivedWhileMoving
                guard linesArrived
                    || MapLoadAhead.needsExtension(
                        built: Self.buildAreaRect(built), visible: visible, velocity: velocity)
                else { return }
                // One extension rebuild at a time, no faster than the pass rate.
                let now = Self.seconds(.now)
                if let last = lastMovingExtension, now - last < MapLoadAhead.interval { return }
                lastMovingExtension = now
                linesArrivedWhileMoving = false
                networkBuildState.invalidateZoomBucket()
                movingBuildRect = Self.mapRect(
                    MapLoadAhead.movingBuildRect(visible: visible, velocity: velocity))
                defer { movingBuildRect = nil }
                noteRebuildTrigger(.movingExtended)
                rebuild(on: mapView, duringGesture: true)
            }

            // MARK: neighbour prebuild

            private struct NeighbourPrebuildTarget: Equatable {
                var levels: [Int]
                var buildRect: MKMapRect
                var eraKey: String
                var visibilityZoom: Double

                static func == (lhs: Self, rhs: Self) -> Bool {
                    lhs.levels == rhs.levels && MKMapRectEqualToRect(lhs.buildRect, rhs.buildRect)
                        && lhs.eraKey == rhs.eraKey && lhs.visibilityZoom == rhs.visibilityZoom
                }
            }
            private var neighbourPrebuild: Task<Void, Never>?
            /// The camera's zoom speed and which way it last moved.
            private var zoomTravel = ZoomTravel()
            /// How long a preparation takes from request to landing, measured
            /// (0.5 to 4 s). Sets how far ahead of a zoom-out one aims.
            private var prepareSeconds: Double = 1
            /// The coarsest level a preparation ahead of a zoom-out may aim at.
            private static let travelMinimumLevel = GeometryZoomLevels.nearestLevel(zoom: 2)
            /// A travel preparation was requested; owes one rebuild once the
            /// camera has stopped (rate 0) that asks for the wanted level.
            private var travelPreparationOwesStopRebuild = false
            private let travelStopTimer = MapDeadlineTimer(delay: .milliseconds(300))
            private var memoryWarningObserver: NSObjectProtocol?

            private var voiceOverObserver: NSObjectProtocol?

            /// Trip dots are drawn in the overlay (no annotation, so no
            /// accessibility element) except while VoiceOver runs; turning it
            /// on or off re-mounts the dots the other way.
            private func observeVoiceOver() {
                guard voiceOverObserver == nil else { return }
                voiceOverObserver = NotificationCenter.default.addObserver(
                    forName: UIAccessibility.voiceOverStatusDidChangeNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let mapView = self.mapView else { return }
                        self.annotationsNeedRefresh = true
                        self.networkBuildState.invalidateZoomBucket()
                        self.rebuild(on: mapView)
                    }
                }
            }

            /// Whether trip dots are drawn into the overlay instead of mounted
            /// as annotations: no selection, and no VoiceOver reader who needs
            /// each station as an element.
            private func tripDotsDrawInOverlay(hasSelection: Bool) -> Bool {
                !hasSelection && !UIAccessibility.isVoiceOverRunning
            }

            /// A memory warning drops every geometry frame but the current one
            /// and stops the idle prebuild that would refill the cache.
            func observeMemoryWarnings() {
                observeVoiceOver()
                guard memoryWarningObserver == nil else { return }
                memoryWarningObserver = NotificationCenter.default.addObserver(
                    forName: UIApplication.didReceiveMemoryWarningNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.cancelNeighbourPrebuild()
                        let droppedFrames = self.networkGeometry.dropNonCurrentFrames()
                        // Freed small-block pages are otherwise kept by the
                        // allocator and the footprint does not shrink. One
                        // relief, off the main thread, once the app's own
                        // releases (AppShell's) have run.
                        self.scheduleMemoryRelief(firstDelay: .milliseconds(500))
#if DEBUG
                        MapRenderProbe.droppedFrames += droppedFrames
#endif
                    }
                }
            }
            /// What the running (or finished) prebuild was asked for, so an
            /// idle camera asks once per installed level, area and era.
            private var neighbourPrebuildTarget: NeighbourPrebuildTarget?

            /// Identity of the running prebuild, so a cancelled one's cleanup
            /// never clears its successor's state.
            private var neighbourPrebuildID: UUID?
            /// The frame the running prebuild is building (set while it builds).
            private var neighbourPrebuildKey: String?
            /// The running prebuild's worker, to raise its priority on adoption.
            private var neighbourPrebuildWorker: Task<MapLineGeometry.PreparedGeometry, Error>?
            /// Set while a foreground request for the prebuild's own frame waits
            /// for it instead of starting a second preparation. Always cleared
            /// by the prebuild's landing or by any exit of it.
            private var adoptedPrebuildKey: String?

            private func cancelNeighbourPrebuild() {
                neighbourPrebuild?.cancel()
                neighbourPrebuild = nil
                neighbourPrebuildTarget = nil
                neighbourPrebuildID = nil
                neighbourPrebuildKey = nil
                neighbourPrebuildWorker = nil
                releaseAdoptedPrebuild()
            }

            /// Ends an adoption that did not land; the request that was waiting
            /// for it gets one rebuild on the next main turn (never inline:
            /// the caller may be inside `prepareNetworkGeometry`).
            private func releaseAdoptedPrebuild() {
                guard adoptedPrebuildKey != nil else { return }
                adoptedPrebuildKey = nil
                Task { @MainActor [weak self] in
                    guard let self, let mapView = self.mapView else { return }
                    self.noteRebuildTrigger(.geometryPrepared)
                    self.rebuild(on: mapView)
                }
            }

            /// Cancelled only when its level is no longer the wanted level or one
            /// of its neighbours; a touch-down alone does not stop it, and a
            /// prebuild of the level the camera just reached is kept (adopted).
            private func cancelNeighbourPrebuildIfWantedSetMoved(zoom: Double) {
                guard let target = neighbourPrebuildTarget else { return }
                if !GeometryZoomLevels.keepsNeighbourPrebuild(
                    levels: target.levels, zoom: zoom, installed: installedGeometryLevel) {
                    cancelNeighbourPrebuild()
                }
            }

            /// While idle, builds ONE neighbour of the installed level, the one in
            /// the direction of the last zoom, on a low-priority worker, so the
            /// next swap finds its geometry ready. Skipped while resident frame
            /// geometry is at its byte cap.
            private static func buildArea(_ rect: MKMapRect) -> MapBuildArea.Rect {
                .init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
            }

            private func scheduleNeighbourPrebuild(on mapView: MKMapView) {
                guard showsNetwork, !isManipulating, playback?.isActive != true,
                      playbackLayer.lastSnapshot == nil, geometryPreparation == nil,
                      mapView.bounds.width > 1,
                      let installed = installedGeometryLevel,
                      networkBuildState.geometryLevel == installed,
                      networkGeometry.hasRoomToPrebuild,
                      let context = markerBuildContext else { return }
                let prebuildLevel = GeometryZoomLevels.prebuildNeighbour(
                    of: installed, lastZoomDirection: zoomTravel.direction)
                // The rect the level will use once the camera reaches it
                // (larger when zooming out), united with what is built. The
                // installed visibility zoom is kept: a superset of lines.
                let visible = mapView.visibleMapRect
                let area = GeometryZoomLevels.prebuildVisibleRect(
                    visible: .init(x: visible.origin.x, y: visible.origin.y,
                                   width: visible.size.width, height: visible.size.height),
                    zoom: MapProjection.zoomLevel(of: mapView), level: prebuildLevel)
                let prebuildRect = NetworkLOD.buildRect(
                    for: MKMapRect(x: area.x, y: area.y, width: area.width, height: area.height))
                    .union(networkBuildState.builtRect)
                let target = NeighbourPrebuildTarget(
                    levels: [prebuildLevel],
                    buildRect: prebuildRect, eraKey: geometryEraKey,
                    visibilityZoom: context.visibilityZoom)
                guard target != neighbourPrebuildTarget else { return }
                // An adopted prebuild is the foreground's work now, and a running
                // one that still covers the camera's rect is not restarted (the
                // target follows the camera; see `prebuildStillCovers`).
                guard adoptedPrebuildKey == nil else { return }
                if let running = neighbourPrebuildTarget, running.levels == target.levels,
                   running.eraKey == target.eraKey, running.visibilityZoom == target.visibilityZoom,
                   GeometryZoomLevels.prebuildStillCovers(
                       running: Self.buildArea(running.buildRect), wanted: Self.buildArea(target.buildRect)) {
                    return
                }
                cancelNeighbourPrebuild()
                neighbourPrebuildTarget = target
                let prebuildID = UUID()
                neighbourPrebuildID = prebuildID
                let temporalContext = networkTemporalContext
                let limiter = geometryWorkLimiter
                neighbourPrebuild = Task { @MainActor [weak self, weak mapView] in
                    // Every exit: drop this prebuild's state (unless a successor
                    // owns it now) and release an adoption that never landed.
                    defer {
                        if let self, self.neighbourPrebuildID == prebuildID {
                            self.neighbourPrebuildKey = nil
                            self.neighbourPrebuildWorker = nil
                            self.releaseAdoptedPrebuild()
                        }
                    }
                    for level in target.levels {
                        guard !Task.isCancelled, let self, let mapView,
                              self.networkTemporalContext == temporalContext else { return }
                        let frame = self.geometryFrame(level: level, on: mapView)
                        let key = frame.key
                        self.networkGeometry.ensureFrame(key: key)
                        let work = self.missingGeometryWork(
                            frame: frame, visibilityZoom: target.visibilityZoom,
                            buildRect: target.buildRect, recordsDiagnostics: false)
                        guard !work.lines.isEmpty || !work.strokes.isEmpty else { continue }
                        self.neighbourPrebuildKey = key
                        let anchors = self.lineInputs.mapValues(\.anchors)
                        let cachedStrokes = self.networkGeometry.preparedStrokes(in: key)
                        let junctionIndex = self.junctionIndex
                        let chainPixels = self.networkGeometry.chainPixels
                        let datumToken = AppleMapDatum.gcj02Countries.sorted().joined(separator: ",")
                        let mapScale = frame.mapPointsPerScreenPoint
                        let scale = frame.scale
                        let laneScale = frame.laneScale
                        let era = temporalContext.era
                        let rideDate = temporalContext.rideDate
                        let todayByRegion = temporalContext.todayByRegion
                        let missingLines = work.lines
                        let missingStrokes = work.strokes
                        let byID = work.byID
                        let worker = Task.detached(priority: .utility) {
                            try await limiter.withPermit {
                                try await MapLineGeometry.prepare(
                                    lines: missingLines, strokes: missingStrokes, allLines: byID,
                                    anchors: anchors, cachedStrokes: cachedStrokes,
                                    junctionIndex: junctionIndex, chainPixels: chainPixels,
                                    frameKey: key, datumToken: datumToken,
                                    mapScale: mapScale, scale: scale, laneScale: laneScale,
                                    era: era, rideDate: rideDate, todayByRegion: todayByRegion,
                                    prebuild: true)
                            }
                        }
                        self.neighbourPrebuildWorker = worker
                        let geometry = await withTaskCancellationHandler {
                            try? await worker.value
                        } onCancel: {
                            worker.cancel()
                        }
                        guard !Task.isCancelled, let geometry else { return }
                        let prepared = await MapLineGeometry.materialize(geometry)
                        guard !Task.isCancelled, let prepared,
                              self.networkTemporalContext == temporalContext else { return }
                        _ = self.networkGeometry.storePrepared(prepared, key: key)
                        // A prebuild the camera has reached (adopted, or now the
                        // wanted level) installs through the ordinary rebuild.
                        let prebuildZoom = MapProjection.zoomLevel(of: mapView)
                        if self.adoptedPrebuildKey == key
                            || level == self.wantedGeometryLevel(at: prebuildZoom) {
                            self.adoptedPrebuildKey = nil
                            self.noteRebuildTrigger(.geometryPrepared)
                            self.rebuild(on: mapView)
                            self.scheduleMemoryRelief()
                        }
                    }
                }
            }

            /// Whether a landed (or already cached) level installs now, and how.
            /// Readiness is checked at the visibility zoom it was prepared for.
            /// The level installs on the camera's own padded rect when that is
            /// ready, else on the rect it was prepared for while that still
            /// holds the screen (zooming out, the padded rect outgrows every
            /// preparation); `GeometryZoomLevels.landingInstall` decides.
            private func landingDecision(
                level: Int, rect: MKMapRect, visibilityZoom: Double, visibilityBucket: Int?,
                preparedAhead: Bool, on mapView: MKMapView
            ) -> PendingInstall? {
                let zoom = MapProjection.zoomLevel(of: mapView)
                let override: Double? = preparedAhead ? visibilityZoom : nil
                let bucket: Int? = preparedAhead ? visibilityBucket : nil
                let wanted = wantedGeometryLevel(at: zoom)
                let readyOnPadded = isGeometryLevelReady(
                    level, zoom: zoom, on: mapView, visibilityZoom: override)
                let readyOnPrepared = !readyOnPadded && rect.contains(mapView.visibleMapRect)
                    && isGeometryLevelReady(
                        level, zoom: zoom, on: mapView, buildRect: rect, visibilityZoom: override)
                guard GeometryZoomLevels.landingInstall(
                    landed: level, installed: installedGeometryLevel, zoom: zoom,
                    wantedReady: isGeometryLevelReady(wanted, zoom: zoom, on: mapView),
                    landedUsable: readyOnPadded || readyOnPrepared) == .installLanded
                else { return nil }
                return PendingInstall(
                    level: level, rect: readyOnPadded ? nil : rect,
                    visibilityZoom: override, visibilityBucket: bucket)
            }

            /// While the camera zooms out fast, prepare the level it will be at
            /// when a preparation lands (``GeometryZoomLevels/travelLevel``), on
            /// the rect that level will show, without waiting for the wanted
            /// level the camera has already left. Returns true when a
            /// preparation for that target is running or queued: the ordinary
            /// request is skipped. A target whose geometry is already cached
            /// becomes the pending install and the ordinary rebuild installs it.
            @discardableResult
            private func startTravelPreparation(zoom: Double, on mapView: MKMapView) -> Bool {
                guard showsNetwork, playbackLayer.lastSnapshot == nil, mapView.bounds.width > 1,
                      let installed = installedGeometryLevel,
                      let level = GeometryZoomLevels.travelLevel(
                        zoom: zoom, rate: zoomTravel.rate(at: Self.seconds(.now)),
                        prepareSeconds: prepareSeconds, minimumLevel: Self.travelMinimumLevel),
                      level < installed
                else { return false }
                let area = GeometryZoomLevels.prebuildVisibleRect(
                    visible: Self.buildAreaRect(mapView.visibleMapRect), zoom: zoom, level: level)
                let rect = NetworkLOD.buildRect(for: Self.mapRect(area))
                let aheadZoom = GeometryZoomLevels.nominalZoom(level: level)
                let policy = networkVisibility(on: mapView)
                let visibilityZoom = policy.visibilityZoom(cameraZoom: aheadZoom)
                let visibilityBucket = policy.visibilityBucket(cameraZoom: aheadZoom)
                travelPreparationOwesStopRebuild = true
                scheduleTravelStopRebuild(on: mapView)
                let cached = prepareNetworkGeometry(
                    on: mapView, zoom: zoom, visibilityZoom: visibilityZoom, buildRect: rect,
                    visibilityBucket: visibilityBucket, level: level, installs: false)
                guard cached else { return true }
                if let decision = landingDecision(
                    level: level, rect: rect, visibilityZoom: visibilityZoom,
                    visibilityBucket: visibilityBucket, preparedAhead: true, on: mapView) {
                    pendingInstall = decision
                }
                return false
            }

            /// 0.3 s after the last camera change the zoom rate reads 0: one
            /// rebuild then asks for the wanted level on the padded rect.
            private func scheduleTravelStopRebuild(on mapView: MKMapView) {
                travelStopTimer.schedule { [weak self, weak mapView] in
                    guard let self, let mapView, self.mapView === mapView else { return }
                    self.travelPreparationOwesStopRebuild = false
                    guard !self.isManipulating else { return }
                    self.rebuild(on: mapView)
                }
            }

            /// Prepare immutable line geometry on a worker. Only the current camera/data
            /// generation may publish; MapKit's mounted overlays stay usable meanwhile.
            /// `level` replaces the level `geometryLevelToBuild` would choose, for
            /// a preparation ahead of the camera. With `installs: false` the
            /// request never begins a frame (nothing draws from it now): `true`
            /// then only says its geometry is already cached.
            private func prepareNetworkGeometry(
                on mapView: MKMapView, zoom: Double, visibilityZoom: Double, buildRect: MKMapRect,
                visibilityBucket: Int? = nil, level: Int? = nil, installs: Bool = true
            ) -> Bool {
                // Preparation can be cancelled. Only installed geometry may
                // advance the hysteresis bucket used by shouldRebuild.
                let temporalContext = networkTemporalContext
                let requestedInputs = lineInputs
                let frame = geometryFrame(
                    level: level ?? geometryLevelToBuild(at: zoom, on: mapView), on: mapView)
                let scale = frame.scale
                let mapScale = frame.mapPointsPerScreenPoint
                let key = frame.key
                let requestInterval = RailSignpost.map.begin("map.geometry.request")
                let work = missingGeometryWork(
                    frame: frame, visibilityZoom: visibilityZoom, buildRect: buildRect,
                    recordsDiagnostics: true)
                RailSignpost.map.end("map.geometry.request", requestInterval)
                let missingLines = work.lines
                let missingStrokes = work.strokes
                let byID = work.byID
                let inFlight = geometryPreparation != nil
                let canInstall = !inFlight || {
                    let visible = mapView.visibleMapRect
                    let coversView = geometryPreparationRect.map { $0.contains(visible) } ?? true
                    return GeometryPreparationGate.inFlightCanInstall(
                        rectCoversView: coversView,
                        stopped: !cameraTravelling,
                        isRequestedLevel: geometryPreparationLevel == frame.bucket)
                }()
                let gate = GeometryPreparationGate.decide(
                    inFlightKey: inFlight ? geometryPreparationKey : nil,
                    requestedKey: key, prebuildKey: neighbourPrebuildKey,
                    missingWork: !missingLines.isEmpty || !missingStrokes.isEmpty,
                    inFlightCanInstall: canInstall)
                if gate.adoptPrebuild {
                    // The idle prebuild is already building this frame: wait
                    // for it (its landing rebuilds) and let it run at the
                    // priority of the work the camera now needs.
                    adoptedPrebuildKey = key
                    if let worker = neighbourPrebuildWorker {
                        Task(priority: .userInitiated) { _ = try? await worker.value }
                    }
                    return false
                }
                // A foreground preparation outranks the idle neighbour prebuild.
                // Nothing waits on it any more, so it is not an adoption loss.
                adoptedPrebuildKey = nil
                cancelNeighbourPrebuild()
                if gate.drawNow {
                    if installs { networkGeometry.beginFrame(key: key, isOverview: frame.isOverview) }
                    return true
                }
                if gate.cancelInFlight { cancelGeometryPreparation() }
                guard gate.start else { return false }
                // Not `beginFrame`: that would make a level that is still
                // being prepared the cache's current frame and unprotect the
                // installed one. `rebuild` begins the frame when it installs.
                // Only a preparation that starts pins its frame: a request the
                // gate makes wait must not unpin the frame the in-flight
                // preparation stores into.
                networkGeometry.ensureFrame(key: key)
                let anchors = lineInputs.mapValues(\.anchors)
                let cachedStrokes = networkGeometry.preparedStrokes(in: key)
                let requestID = UUID()
                geometryPreparationID = requestID
                geometryPreparationKey = key
                geometryPreparationLevel = frame.bucket
                geometryPreparationRect = buildRect
                drawCounters.preparations.request(key: key)
                RailSignpost.map.mark("map.geometry.prep.started", drawCounters.preparations.started, frame.bucket)
                let era = temporalContext.era
                let rideDate = temporalContext.rideDate
                let todayByRegion = temporalContext.todayByRegion
                let limiter = geometryWorkLimiter
                let junctionIndex = self.junctionIndex
                let chainPixels = networkGeometry.chainPixels
                let laneScale = frame.laneScale
                let datumToken = AppleMapDatum.gcj02Countries.sorted().joined(separator: ",")
                let requested = ContinuousClock.now
                let worker = Task.detached(priority: .userInitiated) {
                    try await limiter.withPermit {
                        // How long this request queued behind the previous
                        // preparation for its permit.
                        let waited = (ContinuousClock.now - requested).milliseconds
                        RailSignpost.map.mark("map.geometry.wait", waited)
                        return (waited, try await MapLineGeometry.prepare(
                            lines: missingLines, strokes: missingStrokes, allLines: byID,
                            anchors: anchors, cachedStrokes: cachedStrokes,
                            junctionIndex: junctionIndex, chainPixels: chainPixels,
                            frameKey: key, datumToken: datumToken,
                            mapScale: mapScale, scale: scale, laneScale: laneScale,
                            era: era, rideDate: rideDate, todayByRegion: todayByRegion))
                    }
                }
                geometryPreparation = Task { @MainActor [weak self, weak mapView] in
                    let workerOutput = await withTaskCancellationHandler {
                        try? await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
#if DEBUG
                    if let waited = workerOutput?.0 { MapRenderProbe.recordGeometryWait(milliseconds: waited) }
#endif
                    let result = workerOutput?.1
                    guard let self else { return }
                    @MainActor func clearPreparationIfCurrent() {
                        guard self.geometryPreparationID == requestID else { return }
                        self.drawCounters.preparations.abort()
                        self.geometryPreparation = nil
                        self.geometryPreparationKey = nil
                        self.geometryPreparationRect = nil
                        self.geometryPreparationLevel = nil
                    }
                    guard !Task.isCancelled, let mapView,
                          self.geometryPreparationID == requestID else {
                        clearPreparationIfCurrent()
                        return
                    }
                    guard let geometry = result else {
                        clearPreparationIfCurrent()
                        return
                    }
                    let materializeInterval = RailSignpost.map.begin("map.materialize")
#if DEBUG
                    let materializeStarted = ContinuousClock.now
#endif
                    let prepared = await MapLineGeometry.materialize(geometry)
                    RailSignpost.map.end("map.materialize", materializeInterval)
                    // Lines loaded or evicted meanwhile do not spoil the rest;
                    // only the era (a captured date) makes every result wrong.
                    guard !Task.isCancelled,
                          self.geometryPreparationID == requestID,
                          self.geometryEraKey == temporalContext.cacheKey,
                          var prepared else {
                        clearPreparationIfCurrent()
                        return
                    }
                    let admitted = PreparedGeometryAdmission.admitted(
                        ids: Set(prepared.strokes.keys).union(prepared.lines.keys),
                        requested: requestedInputs, current: self.lineInputs)
                    prepared.strokes = prepared.strokes.filter { admitted.contains($0.key) }
                    prepared.lines = prepared.lines.filter { admitted.contains($0.key) }
#if DEBUG
                    self.pendingMaterializeMilliseconds =
                        (ContinuousClock.now - materializeStarted).milliseconds
#endif
                    // The frame may have been evicted or dropped (memory warning)
                    // while this preparation ran; its result still belongs there.
                    self.networkGeometry.ensureFrame(key: key)
                    guard self.networkGeometry.storePrepared(prepared, key: key) else {
                        clearPreparationIfCurrent()
                        return
                    }
                    // A replaced chain build changes the pixels rides slice.
                    self.resetRideStrokeCaches()
                    await Task.yield()
                    guard !Task.isCancelled,
                          self.geometryPreparationID == requestID else {
                        clearPreparationIfCurrent()
                        return
                    }
                    self.drawCounters.preparations.finish()
                    RailSignpost.map.mark("map.geometry.prep.finished", self.drawCounters.preparations.finished, frame.bucket)
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                        clearPreparationIfCurrent()
                        return
                    }
                    clearPreparationIfCurrent()
                    // Measured request-to-landing time: how far ahead the next
                    // zoom-out preparation has to aim.
                    let landedAfter = ContinuousClock.now - requested
                    self.prepareSeconds = min(max(
                        Double(landedAfter.components.seconds)
                            + Double(landedAfter.components.attoseconds) / 1e18, 0.5), 4)
                    // The camera has usually moved past this level by now. A
                    // landed level nearer the camera than the installed one is
                    // installed rather than discarded for the newest wanted
                    // one, which could then never land either.
                    self.pendingInstall = self.landingDecision(
                        level: frame.bucket, rect: buildRect, visibilityZoom: visibilityZoom,
                        visibilityBucket: visibilityBucket, preparedAhead: !installs, on: mapView)
                    self.noteRebuildTrigger(.geometryPrepared)
                    // A level landed while the camera travels installs now, on
                    // its prepared rect: no 120 ms quiet deferral.
                    let installNow = self.pendingInstall != nil && self.cameraTravelling
                    self.rebuild(on: mapView, duringGesture: installNow, deferMarkers: installNow)
                    self.scheduleMemoryRelief()
                }
                return false
            }

            private var memoryReliefTask: Task<Void, Never>?

            /// A preparation's large temporaries (a slow low-zoom one most of
            /// all) are freed but stay counted in the footprint until the
            /// allocator hands them back. Once the map has been idle for a
            /// moment after a landing, hand them back once: the same call the
            /// memory-warning handler makes. A later landing reschedules it.
            private func scheduleMemoryRelief(firstDelay: Duration = .seconds(2)) {
                memoryReliefTask?.cancel()
                memoryReliefTask = Task { @MainActor [weak self] in
                    for attempt in 0..<10 {
                        do { try await Task.sleep(for: attempt == 0 ? firstDelay : .seconds(2)) } catch { return }
                        guard let self else { return }
                        // Busy: try again after the next quiet moment.
                        if self.isManipulating || self.geometryPreparation != nil
                            || self.rideStrokePreparation != nil { continue }
                        // Tens of ms with a large heap; thread-safe.
                        Task.detached(priority: .utility) { _ = malloc_zone_pressure_relief(nil, 0) }
                        return
                    }
                }
            }

            /// `duringGesture` is the mid-pinch level swap: the wanted level is
            /// already prepared, so the rebuild only installs it and runs
            /// while the fingers are down.
            private func rebuild(
                on mapView: MKMapView, duringGesture: Bool = false, deferMarkers: Bool = false
            ) {
                if !duringGesture,
                   isManipulating || lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) == true {
                    rebuildDeferredByGesture = true
                    scheduleCameraRebuild(on: mapView)
                    return
                }
                defer {
                    if !duringGesture { scheduleNeighbourPrebuild(on: mapView) }
                    if wantedLevelFollowUpOwed {
                        wantedLevelFollowUpOwed = false
                        // Asked after this pass: the installed level is now
                        // the landed one, so the wanted level starts preparing.
                        DispatchQueue.main.async { [weak self, weak mapView] in
                            guard let self, let mapView, self.mapView === mapView else { return }
                            self.networkBuildState.invalidateZoomBucket()
                            self.noteRebuildTrigger(.wantedLevelFollowUp)
                            self.rebuild(on: mapView)
                        }
                    }
                }
                // Observe a regional midnight before the camera/zoom build
                // guard can reuse a previous day's derived visibility.
                refreshNetworkToday()
                // Keep the route mapping and its installed pixels in one
                // generation, including when a worker finishes during playback.
                if playback?.isActive != true, let pending = pendingStrokeRefs {
                    pendingStrokeRefs = nil
                    if pending.revision == matchingRevision {
                        let changedStrokeRideIDs = Set(rides.compactMap { ride in
                            strokeMatchUnchanged(strokeRefCache[ride.id], pending.refs[ride.id])
                                ? nil : ride.id
                        })
                        strokeRefCache = pending.refs
                        matchedLineInputs = pending.inputs
                        retainRidePolylines(excludingStrokeFor: changedStrokeRideIDs)
                        // A running ride build was requested against the old
                        // refs; its keys are superseded, so stop it and let the
                        // rebuild below ask again with the new ones.
                        if rideStrokePreparation != nil,
                           !changedStrokeRideIDs.isDisjoint(with: rideStrokePreparationRideIDs) {
                            rideStrokePreparation?.cancel()
                            rideStrokePreparation = nil
                            rideStrokePreparationID = UUID()
                        }
                        interaction.invalidateRideGeometry()
                        stationLabels.invalidateGeometry(forRides: changedStrokeRideIDs)
                        networkBuildState.invalidateZoomBucket()
                    }
                }
                // With both layers absent there is nothing to build. Hiding the
                // complete network does not hide the reader's routes.
                guard showsNetwork || !rides.isEmpty else {
                    annotationReconciler.removeRetiring(on: mapView)
                    overlayInstaller.removeRetiring(on: mapView)
                    let retiringOverlays = mapView.overlays(in: .aboveLabels)
                    mapView.removeOverlays(retiringOverlays)
                    if !networkAnnotations.isEmpty { mapView.removeAnnotations(networkAnnotations) }
                    networkAnnotations = []
                    if !rideStationAnnotations.isEmpty {
                        mapView.removeAnnotations(rideStationAnnotations)
                    }
                    rideStationAnnotations = []
                    overlayRideDots = []
                    if !endpointAnnotations.isEmpty { mapView.removeAnnotations(endpointAnnotations) }
                    endpointAnnotations = []
                    networkBuildState.invalidateGeometry()
                    networkGeometry.resetFrameStrokes()
                    markerBuildContext = nil
                    batchedRidePartCounts = [:]
                    interaction.invalidateRideGeometry()
#if DEBUG
                    diagnostics.publishEmpty(on: mapView, targetReadiness: targetRideReadiness(on: mapView))
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
                let cameraVisibilityZoom = visibilityPolicy.visibilityZoom(cameraZoom: zoom)
                let cameraVisibilityBucket = visibilityPolicy.visibilityBucket(cameraZoom: zoom)
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
                    visibilityBucket: cameraVisibilityBucket,
                    viewportSize: mapView.bounds.size,
                    hasLanedLines: hasLanedLines,
                    visibleRect: visibleRect
                ) else { return }
                // Validates a pending landed install (drops it once it no
                // longer covers the screen) before its rect is used.
                if pendingInstall != nil { _ = geometryLevelToBuild(at: zoom, on: mapView) }
                // A fast zoom-out prepares the level the camera will be at
                // when it lands; the ordinary request waits for the stop. Only
                // while the camera moves (a settled rebuild still reads the old
                // rate for 300 ms), and never ahead of a landed install: that
                // installs first and the next preparation starts after it.
                let cameraMoving = cameraTravelling
                var installedPendingThisPass = false
                if pendingInstall == nil, cameraMoving,
                   startTravelPreparation(zoom: zoom, on: mapView) {
                    extendTripsAtInstalledLevel(on: mapView)
                    return
                }
                let visibilityZoom = pendingInstall?.visibilityZoom ?? cameraVisibilityZoom
                let visibilityBucket = pendingInstall?.visibilityBucket ?? cameraVisibilityBucket
                let buildRect = pendingInstall?.rect ?? movingBuildRect ?? NetworkLOD.buildRect(for: visibleRect)
                onBuildRect(buildRect, visibilityZoom)
                guard prepareNetworkGeometry(
                    on: mapView, zoom: zoom, visibilityZoom: visibilityZoom, buildRect: buildRect,
                    visibilityBucket: visibilityBucket
                ) else {
                    extendTripsAtInstalledLevel(on: mapView)
                    return
                }
                // What is eligible: near enough to be seen, important enough for
                // this zoom. See NetworkLOD — that policy is deliberately stricter
                // than the web app's at low zoom, and deliberately outside the
                // ported tier, because there is no JavaScript to check it against.
                let selection = showsNetwork
                    ? networkSelection(zoom: visibilityZoom, buildRect: buildRect)
                    : nil
                // The strokes this rebuild installs, chosen before anything is
                // drawn so the worker slices rides from the very chains
                // `ridePolylines` will key them against.
                let strokeFrame = geometryFrame(level: geometryLevelToBuild(at: zoom, on: mapView), on: mapView)
                // One area for trips and lines (covers screen-space lane offsets
                // and rounded corners); strokes are selected with it too.
                let rideBuildRect = NetworkLOD.tripArea(
                    buildRect: buildRect,
                    mapPointsPerScreenPoint: strokeFrame.mapPointsPerScreenPoint)
                let frameStrokes = selectFrameStrokes(
                    selection: selection, buildRect: buildRect, rideBuildRect: rideBuildRect,
                    mapPointsPerScreenPoint: strokeFrame.mapPointsPerScreenPoint)
                guard prepareRideStrokes(
                    on: mapView, frame: strokeFrame, rideBuildRect: rideBuildRect,
                    strokes: frameStrokes.strokes
                ) else { return }
                installedTripRect = rideBuildRect
                networkBuildState.commit(
                    zoom: zoom,
                    visibilityBucket: visibilityBucket,
                    viewportSize: mapView.bounds.size,
                    geometryLevel: strokeFrame.bucket,
                    builtRect: buildRect
                )
                if let pending = pendingInstall {
                    let installedOnPreparedRect = pending.rect != nil
                    pendingInstall = nil
                    installedPendingThisPass = true
                    // When the camera still wants a different level than the
                    // one just installed, or the install used the prepared
                    // rect and the camera's padding is still owed.
                    wantedLevelFollowUpOwed = installedOnPreparedRect
                        || pending.visibilityZoom != nil
                        || GeometryZoomLevels.wantedLevel(zoom: zoom, installed: strokeFrame.bucket)
                        != strokeFrame.bucket
                }
#if DEBUG
                MapRenderProbe.geometryLevels.installed = strokeFrame.bucket
                MapRenderProbe.geometryLevels.installedAt = .now
                MapRenderProbe.geometryLevels.wanted = GeometryZoomLevels.wantedLevel(
                    zoom: zoom, installed: strokeFrame.bucket)
                MapRenderProbe.geometryLevels.cameraZoom = zoom
#endif
                if installedPendingThisPass, cameraMoving {
                    _ = startTravelPreparation(zoom: zoom, on: mapView)
                }
                // A cold display-network request has no geometry to build
                // yet. Its result changes `lines`, invalidates the build state in
                // `update`, and returns through this method with the region's
                // continuous geometry.
                guard !lines.isEmpty || !rides.isEmpty else { return }

                let rebuildTrigger = pendingRebuildTrigger ?? .update
                pendingRebuildTrigger = nil
                drawCounters.noteFullRebuild(rebuildTrigger)
                RailSignpost.map.mark(
                    "map.rebuild.full", rebuildTrigger.rawValue, drawCounters.totalFullRebuilds)
                var rideLineMisses = 0
                if MarkerPassDebt.resetsMovingBudget(duringGesture: duringGesture) {
                    stationLabels.resetMovingBudget()
                }
#if DEBUG
                diagnostics.didRebuild(manipulating: isManipulating)
#endif
                let started = ContinuousClock.now
#if DEBUG
                let materializeMilliseconds = pendingMaterializeMilliseconds
                pendingMaterializeMilliseconds = 0
#endif
                let rebuildInterval = RailSignpost.map.begin("map.rebuild")
                defer { RailSignpost.map.end("map.rebuild", rebuildInterval) }

                // Geometry is already prepared off actor. This phase selects
                // cached chunks for the viewport and applies the vertex budget.
                let geometryInterval = RailSignpost.map.begin("map.rebuild.geometry")

                let buildScale = MapProjection.quantised(
                    RailStyle.scale(atZoom: zoom), on: mapView)
                // How far apart a continuous stroke's parallel lanes sit at
                // this zoom — a hub packed with lanes at a city view would be
                // just as packed zoomed out to a national one if the gap
                // never shrank. `LaneLOD` carries the bucket forward itself
                // so a pinch idling on a boundary does not reopen and re-close
                // the gap every rebuild; the hub/lane rows this scales are
                // untouched.
                let geometryFrame = strokeFrame
                let mapPointsPerScreenPoint = geometryFrame.mapPointsPerScreenPoint
                // The tap index is built from this level's laned polylines; their
                // lane offsets scale with the level, so a new level re-snapshots.
                if currentGeometryFrame?.bucket != geometryFrame.bucket {
                    interaction.invalidateRideGeometry()
                }
                currentGeometryFrame = geometryFrame
                networkGeometry.beginFrame(key: geometryFrame.key, isOverview: geometryFrame.isOverview)

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
                let strokeAnchors = frameStrokes.anchors
                // Replaced whole, not merged: only chains prepared for this
                // frame may back route drawing and hit testing.
                networkGeometry.resetFrameStrokes()
                for (id, stroke) in frameStrokes.strokes {
                    networkGeometry.storeStroke(stroke, for: id)
                }
#if DEBUG
                let rideScanMilliseconds = pendingRideScanMilliseconds
                    + frameStrokes.rideScanMilliseconds
                pendingRideScanMilliseconds = 0
#endif
                // Withheld dashed runs (see `ContinuousStrokeBuild.withheldRuns`),
                // by the drawn line's id.
                let withheldRunsByLineID = frameStrokes.withheldRuns
                let builds: [LineBuild] = (selection?.lines ?? []).compactMap { line in
                    guard let cached = networkGeometry.lineBuild(for: line.id) else { return nil }
#if DEBUG
                    diagnostics.reusedLineGeometry()
#endif
                    if line.continuous, frameStrokes.strokes[line.id] == nil { return nil }
                    return cached.intersecting(buildRect)
                }.filter {
                    !$0.polylines.isEmpty || !$0.historicalPolylines.isEmpty
                        || !$0.familyPolylines.isEmpty || !$0.familyFallbacks.isEmpty
                }

                // The tap index is not tied to the frame: it reads drawn polylines
                // or raw coordinates, within the hit tolerance of any level.
                if interaction.tapSnapshotProvider == nil {
                    interaction.tapSnapshotProvider = { [weak self] in
                        // Not while a gesture or the camera is settling; the
                        // prebuild retries.
                        guard let self, !self.isManipulating,
                            self.lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) != true
                        else { return nil }
                        let interval = RailSignpost.map.begin("map.tapIndex.snapshot")
                        defer { RailSignpost.map.end("map.tapIndex.snapshot", interval) }
                        return RideTapIndex.Snapshot(rides: self.rides,
                            drawnStrokes: { self.drawnStrokes(of: $0) })
                    }
                }

                // The budget is applied to what decimation actually produced, not
                // to the stored vertex count. Budgeting on the raw count cut a
                // national view of Japan from 262 lines to 7, by weighing 394,285
                // stored vertices against a budget meant for the ~12,000 drawn.
                let fitted = NetworkLOD.fitToBudget(builds, zoom: visibilityZoom)
                let visible = fitted.kept.map(\.line)
                drawnLineBuilds = fitted.kept
                var extraPolylines: [String: [MKPolyline]] = [:]
                var selectedFamilyCoverage: [String: [ContinuousStroke.WindowSpan]] = [:]
                for build in fitted.kept where !build.familyPolylines.isEmpty {
                    selectedFamilyCoverage[build.line.id] = build.familyPolylines.values.flatMap(\.chunkWindows)
                }
                RailSignpost.map.end("map.rebuild.geometry", geometryInterval)

                // One palette or the other, chosen once per rebuild rather than
                // per line: mixing them would be a map half in each mode.
                let dark = mapView.traitCollection.userInterfaceStyle == .dark

                var byColor: [String: [MKPolyline]] = [:]
                var historicalByColor: [String: [MKPolyline]] = [:]
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
                    // Batch by eligibility as well as colour. Adding a detail
                    // tier must not fade the lower-tier rails sharing its colour.
                    let lodSuffix = "|lod:\(build.line.lodMinZoom)"
                    let key = (dark ? build.line.colorDarkHex : build.line.colorHex) + lodSuffix
                    colors[key] = UIColor(dark ? build.line.colorDark : build.line.color)
                    if !build.polylines.isEmpty {
                        byColor[key, default: []].append(contentsOf: build.polylines)
                    }
                    if !build.historicalPolylines.isEmpty {
                        historicalByColor[key, default: []].append(contentsOf: build.historicalPolylines)
                    }
                    vertices += build.actualVertexCount
                    // Landlord family-window polylines: one MKMultiPolyline
                    // per distinct colour already exists (`byColor` below),
                    // so a family colour simply joins that same grouping
                    // under its own hex key rather than a new overlay class.
                    for (_, family) in build.familyPolylines {
                        let familyColor = dark ? family.colorDarkHex : family.colorHex
                        let familyKey = familyColor + lodSuffix
                        colors[familyKey] = colors[familyKey]
                            ?? UIColor(Color(hex: familyColor) ?? .accentColor)
                        byColor[familyKey, default: []].append(contentsOf: family.polylines)
                    }
                    if !build.familyFallbacks.isEmpty,
                       let stroke = networkGeometry.strokeBuild(for: build.line.id),
                       let completeBuild = networkGeometry.lineBuild(for: build.line.id) {
                        let coverage = build.line.follows.flatMap { follow in
                            ContinuousStroke.mappedFamilyCoverage(
                                ownerWindows: selectedFamilyCoverage[follow.canonicalID] ?? [],
                                from: follow.from, to: follow.to,
                                canonicalFrom: follow.canonicalFrom, canonicalTo: follow.canonicalTo)
                        }
                        let windows = ContinuousStroke.familyFallbackWindows(
                            tenantWindows: completeBuild.familyFallbacks.map(\.window),
                            drawnLandlordCoverage: coverage)
                        let fallbackKey = build.line.id + "|family:" + windows.map {
                            "\($0.groupID):\($0.from):\($0.to)"
                        }.joined(separator: "|")
                        let fallbacks: [FamilyRunBuild]
                        if let cached = networkGeometry.familyFallbacks(for: fallbackKey) {
                            fallbacks = cached
                        } else {
                            fallbacks = familyFallbackBuilds(
                                for: completeBuild, stroke: stroke,
                                mapPointsPerScreenPoint: mapPointsPerScreenPoint, windows: windows)
                            networkGeometry.storeFamilyFallbacks(
                                fallbacks, for: fallbackKey, lineID: build.line.id)
                        }
                        for family in fallbacks {
                            let kept = family.polylines.filter { $0.boundingMapRect.intersects(buildRect) }
                            guard !kept.isEmpty else { continue }
                            let familyColor = dark ? family.colorDarkHex : family.colorHex
                            let familyKey = familyColor + lodSuffix
                            colors[familyKey] = colors[familyKey]
                                ?? UIColor(Color(hex: familyColor) ?? .accentColor)
                            byColor[familyKey, default: []].append(contentsOf: kept)
                            extraPolylines[build.line.lineID, default: []].append(contentsOf: kept)
                            vertices += kept.reduce(0) { $0 + $1.pointCount }
                        }
                    }
                    for (runIndex, run) in (withheldRunsByLineID[build.line.id] ?? []).enumerated() {
                        guard run.coordinates.count >= 2 else { continue }
                        let runColor = dark ? run.colorDarkHex : run.colorHex
                        let runKey = runColor + lodSuffix
                        colors[runKey] = colors[runKey]
                            ?? UIColor(Color(hex: runColor) ?? .accentColor)
                        guard let polyline = networkGeometry.withheldPolyline(
                            lineID: build.line.id, runIndex: runIndex, coordinates: run.coordinates)
                        else { continue }
                        withheldByColor[runKey, default: []].append(polyline)
                        extraPolylines[build.line.lineID, default: []].append(polyline)
                    }
                }
                drawnExtraPolylines = extraPolylines

                // The scale this build's marks are sized for. One factor, read
                // once, handed to every weight below — see RailStyle. Rounded
                // by the same rule `restyle` rounds by, so a mark built here
                // and a mark rescaled there are never a fraction of a pixel
                // apart.
                let scale = buildScale
                styledScale = scale
                styledOverlayScale = scale
                styledMarkZoom = (zoom * 16).rounded() / 16

                // The transport owns its overlays separately from the base
                // layers reconciled below; re-mount its snapshot afterwards.
                playbackLayer.clear(on: mapView)
                let teardown = RailSignpost.map.begin("map.rebuild.teardown")
#if DEBUG
                let teardownStarted = ContinuousClock.now
#endif
                let overlayReconciliation = overlayInstaller.reconciliation(on: mapView)
                var desiredOverlays: [MKOverlay] = []
                annotationsNeedRefresh = false
#if DEBUG
                let teardownMilliseconds =
                    (ContinuousClock.now - teardownStarted).milliseconds
#endif
                RailSignpost.map.end("map.rebuild.teardown", teardown)
                let networkOverlays = RailSignpost.map.begin("map.rebuild.networkOverlays")
#if DEBUG
                let networkOverlaysStarted = ContinuousClock.now
#endif
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let overlays = overlayInstaller.networkOverlays(
                    byColor: byColor, historicalByColor: historicalByColor,
                    withheldByColor: withheldByColor,
                    colors: colors, dark: dark,
                    alphaScale: hasSelection ? RailStyle.selectDim : 1,
                    epoch: geometryFrame.key,
                    tileSize: MapOverlayTiling.tileSize(mapPointsPerScreenPoint: mapPointsPerScreenPoint),
                    buildRect: buildRect,
                    reconciliation: overlayReconciliation)
                desiredOverlays.append(contentsOf: overlays)
#if DEBUG
                let networkOverlaysMilliseconds =
                    (ContinuousClock.now - networkOverlaysStarted).milliseconds
#endif
                RailSignpost.map.end("map.rebuild.networkOverlays", networkOverlays)

                // The two scopes a ride's stroke answers to, both ported in
                // `MapDateScope`: the SELECTION spotlight, and the DATE scope
                // the reader set on the ride list. `dimOpacity` finally has a
                // subject — an off-date ride draws faint rather than
                // disappearing, which is what makes the slider a control over
                // something.
                let scope = dateScope

                let rideOverlayInterval = RailSignpost.map.begin("map.rebuild.rideOverlays")
#if DEBUG
                let rideOverlaysStarted = ContinuousClock.now
                var rideCacheMisses = 0
#endif
                var rideCasings: [MKMultiPolyline] = []
                var rideOverlays: [MKMultiPolyline] = []
                var selectedRideOverlays: [MKMultiPolyline] = []
                var batchEntries: [RideOverlayBatching.RideEntry] = []
                // 列車路線 off draws no route lines and leaves every station
                // dot alone — `RailMap.setVisible` moves the route, cross-day,
                // hover and selection layers and no marker layer at all.
                let orderedRides = layers.routes
                    ? rides.sorted { left, right in
                        left.id != selectedTrainID && right.id == selectedTrainID
                    }
                    : []
                for ride in orderedRides {
                    let (solid, crossDay, unproven, cacheMisses) = ridePolylines(
                        of: ride, rideBuildRect: rideBuildRect,
                        mapPointsPerScreenPoint: mapPointsPerScreenPoint, scope: scope)
                    rideLineMisses += cacheMisses
#if DEBUG
                    rideCacheMisses += cacheMisses
#endif
                    guard !solid.isEmpty || !crossDay.isEmpty || !unproven.isEmpty else { continue }
                    let selected = ride.id == selectedTrainID
                    // Everything but the selected ride is drawn from shared
                    // batches (`RideOverlayBatching`), planned after the loop.
                    guard selected else {
                        batchEntries.append(RideOverlayBatching.entry(
                            for: ride, scope: scope, solid: solid, crossDay: crossDay, unproven: unproven))
                        continue
                    }
                    appendSelectedRideOverlays(
                        of: ride, solid: solid, crossDay: crossDay, unproven: unproven,
                        dark: dark, hasSelection: hasSelection, reconciliation: overlayReconciliation,
                        cores: &selectedRideOverlays, casings: &rideCasings)
                }
                // Non-selected rides: one overlay per colour x kind x date-scope
                // class. The style is exactly what `MapDateScope.alpha` gives a
                // non-selected ride of that class.
                let batchPlan = RideOverlayBatching.plan(
                    entries: batchEntries, selectedRideID: selectedTrainID)
                batchedRidePartCounts = Dictionary(batchEntries.map {
                    ($0.rideID, $0.solid.count + $0.crossDay.count + $0.unproven.count)
                }, uniquingKeysWith: +)
                rideOverlays = rideBatchOverlays(
                    batchPlan.batches, hasSelection: hasSelection, reconciliation: overlayReconciliation)
                rideBatchCache = layers.routes ? RideBatchCache(
                    stamp: rideBatchStamp(
                        frameKey: geometryFrame.key, hasSelection: hasSelection, dark: dark),
                    entries: Dictionary(batchEntries.map { ($0.rideID, $0) },
                        uniquingKeysWith: { first, _ in first }),
                    batches: batchPlan.batches) : nil
                // Casings first so the coloured cores land on top of them.
                // Both above the base map's labels, for the reason the
                // network's strokes are.
                desiredOverlays.append(contentsOf: retiringCasings(
                    from: overlayReconciliation.oldOverlays, on: mapView))
                desiredOverlays.append(contentsOf: rideOverlays)
                desiredOverlays.append(contentsOf: rideCasings)
                desiredOverlays.append(contentsOf: selectedRideOverlays)
                // Keep dot renderers alive until marker reconciliation updates
                // their individual arrivals and departures below.
                desiredOverlays.append(contentsOf: overlayReconciliation.oldOverlays.filter {
                    $0 is RideStationOverlay
                })
                let animateHighlight = selectionNeedsHighlightTransition && playback?.isActive != true
                selectionNeedsHighlightTransition = false
                fullyBuiltSelectedRideID = selectedTrainID
#if DEBUG
                let rideOverlaysMilliseconds =
                    (ContinuousClock.now - rideOverlaysStarted).milliseconds
#endif
                drawCounters.noteRideCacheMisses(rideLineMisses, trigger: rebuildTrigger)
                RailSignpost.map.mark("map.rideCache.miss", rideLineMisses, rebuildTrigger.rawValue)
                RailSignpost.map.end("map.rebuild.rideOverlays", rideOverlayInterval)
                noteTripsDrawn(on: mapView)
                let context = MarkerBuildContext(
                    zoom: zoom, visibilityZoom: visibilityZoom, scale: scale,
                    buildRect: buildRect, strokeAnchors: strokeAnchors, visible: visible)
                markerBuildContext = context
                // Install once, after marker election has placed each journey's
                // station circles amongst its strokes. Installing the temporary
                // strokes-then-circles stack first forces MapKit to reorder the
                // same hundreds of retained overlays twice on every pan.
#if DEBUG
                let markersStarted = ContinuousClock.now
#endif
                let highlightTransition: TimeInterval? =
                    playback?.isActive == true ? 0 : (animateHighlight ? highlightDuration : nil)
                switch MarkerPassDebt.pass(deferMarkers: deferMarkers) {
                case .full:
                    buildMarkers(context, on: mapView, pendingOverlays: desiredOverlays,
                                 networkTransitionDuration: detailDuration,
                                 highlightTransitionDuration: highlightTransition)
                case .deferred:
                    // Mid-pinch level swap only: install the overlays this rebuild
                    // produced and leave markers (election, annotation reconcile,
                    // restyle) to the settled pass. A moving load-ahead extension
                    // runs the full marker pass so new-area stations and dots show.
                    installRideStationOverlays(
                        on: mapView, scale: scale, pendingOverlays: desiredOverlays,
                        networkTransitionDuration: detailDuration,
                        highlightTransitionDuration: highlightTransition)
                    markerPassDebt.noteDeferred()
                }
#if DEBUG
                let markersMilliseconds = (ContinuousClock.now - markersStarted).milliseconds
#endif
                playbackLayer.repaint(on: mapView)

                let elapsed = ContinuousClock.now - started
                // Deferred: a rebuild can be triggered from inside updateUIView,
                // and writing SwiftUI state during a view update is undefined
                // behaviour — in practice the panel simply never showed the
                // numbers. Hand them back on the next turn of the loop instead.
                let stats = RailMapView.RenderStats(
                    zoom: zoom,
                    visibilityZoom: visibilityZoom,
                    visibleLines: visible.count,
                    overlays: overlays.count + rideOverlays.count + selectedRideOverlays.count
                        + rideCasings.count,
                    vertices: vertices,
                    buildMilliseconds: elapsed.milliseconds,
                    culledOffScreen: selection?.culledOffScreen ?? 0,
                    threshold: fitted.threshold
                )
                lastRenderStats = stats
#if DEBUG
                let snapshot = MapRenderDiagnostics.Snapshot(
                    showsNetwork: showsNetwork, visibleLines: visible.count, networkOverlays: overlays.count,
                    threshold: fitted.threshold, totalLines: lines.count,
                    culledOffScreen: selection?.culledOffScreen ?? 0, totalOverlays: stats.overlays,
                    rideDots: rideStationAnnotations.filter { $0 is RideStationAnnotation }.count + overlayRideDots.count,
                    rideLabels: rideStationAnnotations.filter { $0 is RideLabelAnnotation }.count,
                    rides: rides.count, budgetDrops: builds.count - fitted.kept.count, vertices: vertices,
                    zoom: zoom, visibilityZoom: visibilityZoom,
                    backbones: Set(visible.filter { $0.lodMinZoom < 0 }.map(\.lineID)).count,
                    networkStations: networkAnnotations.count,
                    focusRevision: controller?.explicitFitRevision ?? 0,
                    focusBottom: controller?.lastExplicitFitBottom ?? 0,
                    buildMilliseconds: elapsed.milliseconds,
                    rideOverlaysMilliseconds: rideOverlaysMilliseconds,
                    rideCacheMisses: rideCacheMisses,
                    markersMilliseconds: markersMilliseconds,
                    networkOverlaysMilliseconds: networkOverlaysMilliseconds,
                    teardownMilliseconds: teardownMilliseconds,
                    rideScanMilliseconds: rideScanMilliseconds,
                    materializeMilliseconds: materializeMilliseconds,
                    annotationViews: mapView.annotations.count,
                    builtRect: networkBuildState.builtRect,
                    targetReadiness: targetRideReadiness(on: mapView),
                    selectedTrainID: selectedTrainID, selectedDate: selectedDate)
                lastDiagnosticSnapshot = snapshot
                MapRenderProbe.totalOverlays = mapView.overlays.count
                MapRenderProbe.rideOverlays = rideOverlays.count + selectedRideOverlays.count + rideCasings.count
                diagnostics.publish(snapshot, on: mapView)
#endif
                DispatchQueue.main.async { [onRender] in onRender(stats) }
            }

            /// The trip-line cache key of one segment this frame: the rail line it
            /// is sliced from, that line's stroke generation and the span, or
            /// no line for a segment drawn from its own coordinates.
            private func rideLineCacheKey(
                of segment: RiddenRouteStore.DrawnSegment, in ride: RiddenRouteStore.DrawnRide,
                stroke ref: StrokeRef?
            ) -> RideLineCacheKey {
                RideLineCacheKey(
                    rideID: ride.id, geometryDigest: ride.geometryDigest,
                    segmentIndex: segment.segmentIndex, partIndex: segment.partIndex,
                    stroke: ref.map {
                        .init(
                            lineID: $0.chainID,
                            generation: networkGeometry.residentStrokeGeneration(for: $0.chainID),
                            from: $0.from, to: $0.to)
                    })
            }

            /// The selected ride's cores and their casings, appended to `cores`
            /// and `casings`: one core per surviving suffix (`ride` /
            /// `ride-xday` / `ride-unproven`) with its halo. Shared by a full
            /// rebuild and by a new pick answered in place, so the two cannot
            /// draw the selected ride differently.
            private func appendSelectedRideOverlays(
                of ride: RiddenRouteStore.DrawnRide,
                solid: [MKPolyline], crossDay: [MKPolyline], unproven: [MKPolyline],
                dark: Bool, hasSelection: Bool, reconciliation: MapOverlayReconciliation,
                cores: inout [MKMultiPolyline], casings: inout [MKMultiPolyline]
            ) {
                // A ride's stroke width: see ``RideOverlayStyle/widthToken(display:selected:)``.
                let width = RideOverlayStyle.widthToken(display: display, selected: true)
                let alpha = MapDateScope.alpha(
                    own: CGFloat(display.riddenOpacity), span: ride.daySpan,
                    scope: dateScope, isSelected: true, hasSelection: hasSelection)
                let color = UIColor(railHex: ride.colorHex) ?? .railDefaultTrip

                // Same source, same colour, same width — only the stroke
                // pattern says "not this day" (`TRAIN_XDAY_LAYER`), or
                // "unproven" (the historical dotted rhythm).
                for (suffix, polylines, dashed, historical) in [
                    ("ride", solid, false, false), ("ride-xday", crossDay, true, false),
                    ("ride-unproven", unproven, false, true),
                ] where !polylines.isEmpty {
                    let styleKey = "\(suffix)|\(ride.id)"
                    let multi = reconciliation.multiPolyline(polylines, key: styleKey)
                    overlayStyles[styleKey] = .init(
                        color: color, widthToken: width, alpha: alpha, dashed: dashed,
                        historical: historical)
                    cores.append(multi)

                    // §10.5: a selection has to change more than a colour.
                    // The casing is a dark halo UNDER the selected line,
                    // 0.7 pt per side at full scale — Apple's restrained
                    // selected-transit outline rather than a glow — and it
                    // rides the same ramp, or "selected" would read
                    // differently at every zoom. It follows the dash too:
                    // a solid casing under a dashed core would fill the
                    // gaps back in and undo the distinction.
                    let casingKey = "\(suffix)-casing|\(ride.id)"
                    let casing = reconciliation.multiPolyline(polylines, key: casingKey)
                    overlayStyles[casingKey] = .init(
                        // `MAP_SURFACE_COLORS[theme].casing`, the same two
                        // values the web app's selection halo uses.
                        color: UIColor(railHex: dark ? "#F5EEE9" : "#1A1A1A") ?? .label,
                        widthToken: width + RailStyle.selectionCasingEdge * 2,
                        alpha: 0.9,
                        dashed: dashed,
                        historical: historical
                    )
                    if selectionNeedsHighlightTransition, playback?.isActive != true {
                        overlayStyles.animateOpacity(
                            forKey: casingKey, duration: highlightDuration,
                            fromAlpha: reconciliation.oldOverlays.contains(where: { $0 === casing })
                                ? nil : 0)
                    }
                    casings.append(casing)
                }
            }

            /// Whether every segment of `ride` that draws has its polyline in
            /// the installed frame's cache, or is known to build to nothing
            /// (it is drawn from nothing either way). A standalone ride draws
            /// its whole route (not only the part inside the built rect), so a
            /// ride that reaches outside has not been built for it and takes a
            /// rebuild.
            private func routeAvailableInFrame(_ ride: RiddenRouteStore.DrawnRide) -> Bool {
                let riddenStops = ride.stops
                for segment in ride.segments {
                    guard draws(segment: segment, of: ride, riddenStops: riddenStops) else { continue }
                    let ref = strokeRef(for: segment, of: ride)
                    let usesStroke = ref.map { networkGeometry.containsStroke(for: $0.chainID) } ?? false
                    let key = rideLineCacheKey(of: segment, in: ride, stroke: usesStroke ? ref : nil)
                    if networkGeometry.ridePolyline(for: key) != nil { continue }
                    // The worker built this segment to nothing in this frame:
                    // `ridePolylines` skips it, and a rebuild would too.
                    if rideStrokeEmptyFrameKey == currentGeometryFrame?.key,
                       rideStrokeEmptyKeys.contains(key) { continue }
                    return false
                }
                return true
            }

            /// One ride's drawable polylines this frame, split into solid,
            /// cross-day and unproven runs. Shared by the full rebuild and the
            /// rides-only update so both draw a ride identically.
            private func ridePolylines(
                of ride: RiddenRouteStore.DrawnRide, rideBuildRect: MKMapRect,
                mapPointsPerScreenPoint: Double, scope: MapDateScope.Scope
            ) -> (solid: [MKPolyline], crossDay: [MKPolyline], unproven: [MKPolyline], cacheMisses: Int) {
                // Split by the calendar day each SEGMENT runs on, which is
                // why the strokes are taken from `segments` rather than
                // from `strokes`: `Dates.segmentDate` needs the segment's
                // own index and the flattened list has thrown it away.
                var solid: [MKPolyline] = []
                var crossDay: [MKPolyline] = []
                var unproven: [MKPolyline] = []
                var cacheMisses = 0
                let unprovenSections = ride.unprovenSegmentIndices
                let riddenStops = ride.stops
                for segment in ride.segments {
                    // 已乘路線顯示: a segment whose category the reader has
                    // switched off is not drawn. Per SEGMENT rather than
                    // per journey, because that is the granularity the web
                    // app classifies at — a 新幹線 run with a metro leg on
                    // the end loses the leg, not the run.
                    // Keep the entire selection installed across camera
                    // moves; MapKit clips its pixels to the visible map.
                    guard (ride.id == selectedTrainID || segment.boundingRect.intersects(rideBuildRect)),
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
                    let ref = strokeRef(for: segment, of: ride)
                    let usesStroke = ref.map { networkGeometry.containsStroke(for: $0.chainID) } ?? false
                    let key = rideLineCacheKey(of: segment, in: ride, stroke: usesStroke ? ref : nil)
                    let polyline: MKPolyline
                    if let cached = networkGeometry.ridePolyline(for: key) {
                        polyline = cached
                    } else {
                        cacheMisses += 1
                        // `prepareRideStrokes` built every drawn segment on a
                        // worker before this rebuild ran, so a miss here is a
                        // segment that draws nothing. No geometry on main.
                        continue
                    }
                    if unprovenSections.contains(segment.segmentIndex) {
                        unproven.append(polyline)
                    } else if let stopInterval = ride.stopInterval(forSectionIndex: segment.segmentIndex),
                       MapDateScope.isCrossDayContinuation(
                        ride.daySpan, segmentIndex: stopInterval, scope: scope) {
                        crossDay.append(polyline)
                    } else {
                        solid.append(polyline)
                    }
                }
                return (solid, crossDay, unproven, cacheMisses)
            }

            /// What one rebuild installs as this frame's strokes, chosen from the
            /// built chains without touching the cache's frame strokes.
            private struct FrameStrokeSelection {
                var strokes: [String: MapNetworkGeometryCache.BuiltStroke] = [:]
                var anchors: [String: [Int: CLLocationCoordinate2D]] = [:]
                var withheldRuns:
                    [String: [(colorHex: String, colorDarkHex: String, coordinates: [Coordinate])]] = [:]
                /// The chains a visible ride's segments name.
                var neededLineIDs: Set<String> = []
#if DEBUG
                var rideScanMilliseconds = 0
#endif
            }

            /// The continuous chains a rebuild installs this frame: every
            /// selected continuous line that has a build, plus the chains a
            /// visible ride's own segments resolve against
            /// (``strokeRef(for:of:)``), built for the ride even when the line
            /// itself is culled by LOD, off by zoom, or the whole network layer
            /// is hidden (`showsNetwork` starts `false`), so a ride still draws
            /// on the network's own offset pixels while the network it shares
            /// them with stays invisible. A segment 已乘路線顯示 has switched off
            /// is skipped here too. The pad of `rideBuildRect` covers
            /// screen-space lane offsets and rounded corners. Only reads the
            /// cache; the rebuild installs the result, and the ride stroke
            /// worker slices rides from the same chains.
            private func selectFrameStrokes(
                selection: (lines: [RailNetworkStore.DrawnLine], culledOffScreen: Int)?,
                buildRect: MKMapRect, rideBuildRect: MKMapRect, mapPointsPerScreenPoint: Double
            ) -> FrameStrokeSelection {
                var result = FrameStrokeSelection()
                var selectedIDs: Set<String> = []
#if DEBUG
                let scanStarted = ContinuousClock.now
#endif
                if layers.routes {
                    for ride in rides where ride.visible {
                        let riddenStops = ride.stops
                        for segment in ride.segments {
                            guard (ride.id == selectedTrainID || segment.boundingRect.intersects(rideBuildRect)),
                                draws(segment: segment, of: ride, riddenStops: riddenStops),
                                let ref = strokeRef(for: segment, of: ride)
                            else { continue }
                            result.neededLineIDs.insert(ref.chainID)
                            if ride.id == selectedTrainID { selectedIDs.insert(ref.chainID) }
                        }
                    }
                }
#if DEBUG
                result.rideScanMilliseconds = (ContinuousClock.now - scanStarted).milliseconds
#endif
                for line in selection?.lines ?? [] where line.continuous {
                    guard networkGeometry.lineBuild(for: line.id) != nil,
                        let stroke = networkGeometry.strokeBuild(for: line.id) else { continue }
                    result.anchors[line.id] = stroke.anchors
                    result.strokes[line.id] = (
                        stroke: stroke.stroke, mapPointsPerScreenPoint: mapPointsPerScreenPoint)
                    result.withheldRuns[line.id] = stroke.withheldRuns
                }
                // A needed chain the selection never reached is built purely
                // for the ride that names it; never added to the overlay.
                let linesByStrokeID = Dictionary(
                    lines.filter(\.continuous).map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                for id in result.neededLineIDs where result.strokes[id] == nil {
                    guard let line = linesByStrokeID[id],
                        selectedIDs.contains(id)
                            || line.intervalRects.contains(where: { $0.intersects(rideBuildRect) }),
                        let stroke = networkGeometry.strokeBuild(for: line.id) else { continue }
                    result.anchors[line.id] = stroke.anchors
                    result.strokes[line.id] = (
                        stroke: stroke.stroke, mapPointsPerScreenPoint: mapPointsPerScreenPoint)
                }
                return result
            }

            /// A chain's stroke was replaced or the lines changed: what the
            /// stroke worker remembered no longer holds.
            private func resetRideStrokeCaches() {
                rideStrokeMemo.removeAll()
                rideStrokeEmptyKeys.removeAll()
                rideStrokeEmptyFrameKey = ""
                arrivalStrokePreparationID = UUID()
            }

            /// The worker requests for every drawn segment of `rides` that has
            /// no polyline cached for the current frame: the same visibility
            /// rules and keys as `ridePolylines`, values only.
            ///
            /// `defersUnmatchedFallbacks` leaves out the raw-coordinate fallback
            /// of a ride whose match is not current while matching is still
            /// due (``RideStrokeBuildPolicy``): that is the costliest build and
            /// its key is replaced by the chain-sliced one when matching lands.
            private func rideStrokeRequests(
                for rides: [RiddenRouteStore.DrawnRide], rideBuildRect: MKMapRect,
                defersUnmatchedFallbacks: Bool = false,
                noteRequestedRide: ((String) -> Void)? = nil,
                strokeFor: (String) -> MapNetworkGeometryCache.BuiltStroke?
            ) -> [RideStrokeBuilder.Request] {
                let matchingPending = defersUnmatchedFallbacks && strokeMatchingPending
                var requests: [RideStrokeBuilder.Request] = []
                var seen: Set<RideLineCacheKey> = []
                for ride in rides {
                    let riddenStops = ride.stops
                    let matchIsCurrent = strokeRefCache[ride.id]?.geometryKey
                        == "\(ride.id):\(ride.geometryDigest)"
                    for segment in ride.segments {
                        guard (ride.id == selectedTrainID || segment.boundingRect.intersects(rideBuildRect)),
                            draws(segment: segment, of: ride, riddenStops: riddenStops)
                        else { continue }
                        var source: RideStrokeBuilder.StrokeSource?
                        var sourceRef: StrokeRef?
                        if let ref = strokeRef(for: segment, of: ride),
                            let built = strokeFor(ref.chainID) {
                            source = .init(
                                chainID: ref.chainID, points: built.stroke.points,
                                measures: built.stroke.measures,
                                mapPointsPerScreenPoint: built.mapPointsPerScreenPoint,
                                from: ref.from, to: ref.to)
                            sourceRef = ref
                        }
                        if RideStrokeBuildPolicy.defersFallback(
                            hasStroke: source != nil, matchIsCurrent: matchIsCurrent,
                            matchingPending: matchingPending) { continue }
                        let key = rideLineCacheKey(of: segment, in: ride, stroke: sourceRef)
                        guard networkGeometry.ridePolyline(for: key) == nil,
                            !rideStrokeEmptyKeys.contains(key), seen.insert(key).inserted
                        else { continue }
                        noteRequestedRide?(ride.id)
                        requests.append(.init(
                            key: key, coordinates: segment.coordinates,
                            latitude: MKMapPoint(x: segment.boundingRect.midX,
                                y: segment.boundingRect.midY).coordinate.latitude,
                            stroke: source))
                    }
                }
                return requests
            }

            /// Whether a ride's match is the same ride geometry with the same
            /// refs. A new geometry key with equal refs still changed what the
            /// ride's deferred fallback segments must draw.
            private func strokeMatchUnchanged(
                _ old: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])?,
                _ new: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])?
            ) -> Bool {
                old?.geometryKey == new?.geometryKey && old?.refs == new?.refs
            }

            /// A trip-to-line match is debouncing, running or owed.
            private var strokeMatchingPending: Bool {
                matchingDebounceTask != nil || matchingInFlight != nil || matchingRerunOwed
            }

            /// Builds the missing ride polylines of the
            /// frame on a worker, stores them, and re-enters `rebuild`. Answers
            /// `true` when nothing is missing, so the rebuild goes on and only
            /// installs. Mirrors `prepareNetworkGeometry`'s return protocol.
            private func prepareRideStrokes(
                on mapView: MKMapView, frame: MapGeometryFrame, rideBuildRect: MKMapRect,
                strokes: [String: MapNetworkGeometryCache.BuiltStroke]
            ) -> Bool {
                guard layers.routes else { return true }
                let strokeFrame = RideStrokeBuilder.Frame(
                    key: frame.key, mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint,
                    scale: frame.scale)
                if rideStrokePreparation != nil, rideStrokePreparationFrame != strokeFrame {
                    rideStrokePreparation?.cancel()
                    rideStrokePreparation = nil
                    rideStrokePreparationID = UUID()
                }
                if rideStrokeEmptyFrameKey != strokeFrame.key {
                    rideStrokeEmptyKeys.removeAll()
                    rideStrokeEmptyFrameKey = strokeFrame.key
                }
                var requestedRideIDs: Set<String> = []
                let requests = rideStrokeRequests(
                    for: rides, rideBuildRect: rideBuildRect, defersUnmatchedFallbacks: true,
                    noteRequestedRide: { requestedRideIDs.insert($0) },
                    strokeFor: { strokes[$0] })
                guard !requests.isEmpty else { return true }
                guard rideStrokePreparation == nil else { return false }
                rideStrokePreparationRideIDs = requestedRideIDs
                let requestID = UUID()
                rideStrokePreparationID = requestID
                rideStrokePreparationFrame = strokeFrame
                let memo = rideStrokeMemo
                let worker = Task.detached(priority: .userInitiated) {
                    await RideStrokeBuilder.build(requests, frame: strokeFrame, memo: memo)
                }
                rideStrokePreparation = Task { @MainActor [weak self, weak mapView] in
                    let output = await withTaskCancellationHandler {
                        await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard let self, let mapView else { return }
                    guard self.rideStrokePreparationID == requestID, !Task.isCancelled else { return }
                    // The only main-actor work: file the finished polylines under
                    // the frame they were built for, without moving the cache's
                    // current frame (the camera may be elsewhere by now).
                    let install = RailSignpost.map.begin("map.rideStrokes.install")
                    for built in output.built {
                        self.networkGeometry.storeRidePolyline(
                            built.polyline, for: built.key, frameKey: strokeFrame.key)
                    }
                    if self.rideStrokeEmptyFrameKey == strokeFrame.key {
                        self.rideStrokeEmptyKeys.formUnion(output.empty)
                    }
                    RailSignpost.map.end("map.rideStrokes.install", install)
                    RailSignpost.map.mark("map.rideStrokes.shared", output.shared)
                    self.rideStrokePreparation = nil
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                        return
                    }
                    self.noteRebuildTrigger(.rideStrokesPrepared)
                    self.rebuild(on: mapView)
                }
                return false
            }

            /// The non-selected rides' batch overlays, reusing every installed
            /// overlay whose polylines are unchanged, with their styles.
            private func rideBatchOverlays(
                _ batches: [RideOverlayBatching.BatchSpec], hasSelection: Bool,
                reconciliation: MapOverlayReconciliation
            ) -> [MKMultiPolyline] {
                let scope = dateScope
                return batches.map { batch in
                    let multi = reconciliation.multiPolyline(batch.polylines, key: batch.key)
                    overlayStyles[batch.key] = .init(
                        color: UIColor(railHex: batch.colorHex) ?? .railDefaultTrip,
                        widthToken: RideOverlayStyle.widthToken(display: display, selected: false),
                        alpha: RideOverlayStyle.batchAlpha(
                            display: display, scope: scope, hasSelection: hasSelection,
                            inScope: batch.scopeClass == .inScope),
                        dashed: batch.kind.dashed, historical: batch.kind.historical)
                    return multi
                }
            }

            private func rideBatchStamp(
                frameKey: String, hasSelection: Bool, dark: Bool
            ) -> RideBatchCache.Stamp {
                RideBatchCache.Stamp(
                    frameKey: frameKey, buildRect: installedTripRect, linesGeneration: linesGeneration,
                    selectedTrainID: selectedTrainID,
                    hasSelection: hasSelection, selectedDate: selectedDate, display: display,
                    layers: layers, categoryCountries: Set(categoryIndexes.keys), dark: dark)
            }

            /// A rides-only change — a partial route publication or one ride
            /// edited — answered from the last build: only the batches of the
            /// cells the changed rides leave or enter are re-formed, the network
            /// overlays and the selected ride's overlays stay mounted, and the
            /// marker pass re-marks from per-ride cached records.
            ///
            /// Answers `false` — doing nothing — whenever the last build's
            /// inputs are not all still current (camera frame, built rect,
            /// selection, scope, layers, display, network generation, a stroke
            /// match waiting), or a changed ride needs a chain this frame has
            /// not built, so the caller falls back to a full rebuild.
            private func updateRides(_ change: RideDeckState.Change, on mapView: MKMapView) -> Bool {
                guard !change.ambiguous, let context = markerBuildContext, let cache = rideBatchCache,
                    let frame = currentGeometryFrame, !annotationsNeedRefresh,
                    !rebuildDeferredByPlayback, !rebuildDeferredByGesture, pendingStrokeRefs == nil,
                    !selectionNeedsHighlightTransition,
                    playback?.isActive != true, playbackLayer.lastSnapshot == nil,
                    mapView.bounds.width > 1, layers.routes, !rides.isEmpty, !isManipulating,
                    lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) != true
                else { return false }
                if let selectedTrainID {
                    guard selectedTrainID == fullyBuiltSelectedRideID,
                        !change.changed.contains(selectedTrainID) else { return false }
                }
                // The camera still shows the frame and rect the cache was drawn for.
                let zoom = MapProjection.zoomLevel(of: mapView)
                let visibilityBucket = networkVisibility(on: mapView).visibilityBucket(cameraZoom: zoom)
                guard !networkBuildState.shouldRebuild(
                    zoom: zoom, visibilityBucket: visibilityBucket,
                    viewportSize: mapView.bounds.size,
                    hasLanedLines: lines.contains(where: { $0.lane != 0 || $0.continuous }),
                    visibleRect: mapView.visibleMapRect) else { return false }
                let frameKey = geometryFrame(level: wantedGeometryLevel(at: zoom), on: mapView).key
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let dark = mapView.traitCollection.userInterfaceStyle == .dark
                guard frameKey == frame.key, cache.stamp == rideBatchStamp(
                    frameKey: frameKey, hasSelection: hasSelection, dark: dark) else { return false }

                let rideBuildRect = installedTripRect
                let changedRides = rides.filter { change.changed.contains($0.id) }
                // A full rebuild builds a needed chain the frame lacks; this
                // path cannot, so such a ride takes the full rebuild.
                let linesByStrokeID = markerSetup().linesByStrokeID
                for ride in changedRides {
                    let riddenStops = ride.stops
                    for segment in ride.segments {
                        guard segment.boundingRect.intersects(rideBuildRect),
                            draws(segment: segment, of: ride, riddenStops: riddenStops),
                            let ref = strokeRef(for: segment, of: ride),
                            !networkGeometry.containsStroke(for: ref.chainID),
                            let line = linesByStrokeID[ref.chainID],
                            line.intervalRects.contains(where: { $0.intersects(rideBuildRect) })
                        else { continue }
                        return false
                    }
                }
                return applyRideChange(change, frame: frame, context: context, on: mapView)
            }

            /// The core of a rides-only change: re-forms the batches of the
            /// changed rides over ``installedTripRect`` and reinstalls the
            /// overlay stack with the batch block replaced. The caller has
            /// established that the cache still describes the installed frame.
            /// `deferMarkers` installs the overlays and leaves the marker pass
            /// to the settled rebuild (a trip extension during zoom travel).
            private func applyRideChange(
                _ change: RideDeckState.Change, frame: MapGeometryFrame, context: MarkerBuildContext,
                deferMarkers: Bool = false, on mapView: MKMapView
            ) -> Bool {
                guard var cache = rideBatchCache else { return false }
                let interval = RailSignpost.map.begin("map.rides")
                defer { RailSignpost.map.end("map.rides", interval) }
                let started = ContinuousClock.now
                let scope = dateScope
                let mapPointsPerScreenPoint = frame.mapPointsPerScreenPoint
                let rideBuildRect = installedTripRect
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let dark = mapView.traitCollection.userInterfaceStyle == .dark
                let changedRides = rides.filter { change.changed.contains($0.id) }

                // A changed ride that still needs a line has it built on a
                // worker for those rides alone, then re-enters here. Never
                // a full network rebuild (`RideArrivalPlan`).
                let missing = rideStrokeRequests(
                    for: changedRides, rideBuildRect: rideBuildRect,
                    strokeFor: { networkGeometry.stroke(for: $0) })
                if !missing.isEmpty {
                    prepareArrivalStrokes(
                        missing, change: change, frame: frame, on: mapView)
                    return true
                }

                var affectedCells: Set<Int> = []
                for id in change.changed {
                    if let old = cache.entries.removeValue(forKey: id) { affectedCells.insert(old.cell) }
                    batchedRidePartCounts.removeValue(forKey: id)
                }
                for ride in changedRides {
                    let (solid, crossDay, unproven, _) = ridePolylines(
                        of: ride, rideBuildRect: rideBuildRect,
                        mapPointsPerScreenPoint: mapPointsPerScreenPoint, scope: scope)
                    guard !solid.isEmpty || !crossDay.isEmpty || !unproven.isEmpty else { continue }
                    let entry = RideOverlayBatching.entry(
                        for: ride, scope: scope, solid: solid, crossDay: crossDay, unproven: unproven)
                    cache.entries[ride.id] = entry
                    affectedCells.insert(entry.cell)
                    batchedRidePartCounts[ride.id] = solid.count + crossDay.count + unproven.count
                }
                cache.batches = RideOverlayBatching.replan(
                    previous: cache.batches, entries: rides.compactMap { cache.entries[$0.id] },
                    affectedCells: affectedCells, selectedRideID: selectedTrainID)
                rideBatchCache = cache

                // The installed stack with its batch block replaced, in the
                // order a full rebuild installs: network, retiring casings,
                // batches, then the selection, the dots and the playback.
                let reconciliation = overlayInstaller.reconciliation(on: mapView)
                let batchOverlays: [MKOverlay] = rideBatchOverlays(
                    cache.batches, hasSelection: hasSelection, reconciliation: reconciliation)
                var desired: [MKOverlay] = []
                var placed = false
                for overlay in reconciliation.oldOverlays {
                    let key = (overlay.title ?? nil) ?? ""
                    if MapOverlayStyles.isRideBatchKey(key) {
                        if !placed { desired.append(contentsOf: batchOverlays); placed = true }
                        continue
                    }
                    let selectedCasing = MapOverlayStyles.isRideCasingKey(key)
                        && key.firstIndex(of: "|").map { String(key[key.index(after: $0)...]) } == selectedTrainID
                    if !placed, selectedCasing || MapOverlayStyles.isRideCoreKey(key)
                        || overlay is RideStationOverlay || key.hasPrefix("playback") {
                        desired.append(contentsOf: batchOverlays)
                        placed = true
                    }
                    desired.append(overlay)
                }
                if !placed { desired.append(contentsOf: batchOverlays) }
                if deferMarkers {
                    installRideStationOverlays(
                        on: mapView, scale: context.scale, pendingOverlays: desired,
                        networkTransitionDuration: detailDuration)
                    markerPassDebt.noteDeferred()
                } else {
                    buildMarkers(context, on: mapView, pendingOverlays: desired,
                                 networkTransitionDuration: detailDuration)
                }
                publishRidesOnlyUpdate(
                    overlays: desired.count,
                    rideOverlays: desired.reduce(0) { count, overlay in
                        let key = (overlay.title ?? nil) ?? ""
                        return count + (MapOverlayStyles.isRideBatchKey(key)
                            || MapOverlayStyles.isRideCasingKey(key)
                            || MapOverlayStyles.isRideCoreKey(key) ? 1 : 0)
                    },
                    elapsed: ContinuousClock.now - started, on: mapView)
                return true
            }

            /// The area trips were last built for: the full rebuild's trip area,
            /// grown by ``extendTripsAtInstalledLevel(on:)`` while the camera
            /// outgrows it. Every ride-path read of "where are trips drawn"
            /// uses this, never a rect derived from the marker context.
            private var installedTripRect = MKMapRect.null
            private var lastTripExtension: Double?

            /// Trips do not wait for the network level. When the view outgrows
            /// ``installedTripRect``, trips are extended at the INSTALLED level
            /// over the camera's padded rect: chain strokes are whole-chain, so a
            /// chain built in the installed frame slices correctly anywhere, and
            /// a chain with no build draws no network line either, so its trips
            /// draw from surveyed coordinates beside nothing. Never changes the
            /// level, the network overlays or the cache's frame, and never takes
            /// a geometry preparation or its permit.
            private func extendTripsAtInstalledLevel(on mapView: MKMapView) {
                guard layers.routes, let frame = currentGeometryFrame,
                      let context = markerBuildContext, let cache = rideBatchCache,
                      playback?.isActive != true, playbackLayer.lastSnapshot == nil,
                      pendingStrokeRefs == nil, arrivalStrokePreparation == nil,
                      !rides.isEmpty, !installedTripRect.isNull, mapView.bounds.width > 1,
                      selectedTrainID == nil || selectedTrainID == fullyBuiltSelectedRideID,
                      // A rebuild that began the next level's frame and stopped
                      // before installing leaves the cache reading that frame.
                      networkGeometry.currentFrameKey == frame.key,
                      !rebuildDeferredByGesture, !annotationsNeedRefresh,
                      // A level more than one away would build trips over a
                      // national area that the settled rebuild throws away.
                      abs(wantedGeometryLevel(at: MapProjection.zoomLevel(of: mapView)) - frame.bucket) <= 1
                else { return }
                let now = Self.seconds(.now)
                guard TripAreaExtension.isDue(now: now, last: lastTripExtension) else { return }
                let visible = mapView.visibleMapRect
                let cameraPadded = NetworkLOD.tripArea(
                    buildRect: NetworkLOD.buildRect(for: visible),
                    mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint)
                guard let areaRect = TripAreaExtension.area(
                    installed: Self.buildAreaRect(installedTripRect),
                    cameraPadded: Self.buildAreaRect(cameraPadded)) else { return }
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let dark = mapView.traitCollection.userInterfaceStyle == .dark
                var expected = rideBatchStamp(frameKey: frame.key, hasSelection: hasSelection, dark: dark)
                expected.buildRect = cache.stamp.buildRect
                guard cache.stamp == expected else { return }
                lastTripExtension = now
                let area = Self.mapRect(areaRect)
                let previousRect = installedTripRect
                var changedIDs: Set<String> = []
                var chainIDs: Set<String> = []
                for ride in rides where ride.visible && ride.id != selectedTrainID {
                    let riddenStops = ride.stops
                    for segment in ride.segments {
                        guard segment.boundingRect.intersects(area),
                              !segment.boundingRect.intersects(previousRect),
                              draws(segment: segment, of: ride, riddenStops: riddenStops)
                        else { continue }
                        changedIDs.insert(ride.id)
                        if let ref = strokeRef(for: segment, of: ride) { chainIDs.insert(ref.chainID) }
                    }
                }
                // The same rule as the tail of `selectFrameStrokes`: a chain the
                // installed frame has built is sliced from it. A chain with no
                // build stays surveyed, beside no drawn line.
                for id in chainIDs where !networkGeometry.containsStroke(for: id) {
                    guard let build = networkGeometry.strokeBuild(for: id) else { continue }
                    networkGeometry.storeStroke(
                        (stroke: build.stroke, mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint),
                        for: id)
                }
                installedTripRect = area
                var stamped = cache
                stamped.stamp = rideBatchStamp(frameKey: frame.key, hasSelection: hasSelection, dark: dark)
                rideBatchCache = stamped
                if !changedIDs.isEmpty {
                    let change = RideDeckState.Change(
                        changed: changedIDs, orderChanged: false, ambiguous: false)
                    _ = applyRideChange(
                        change, frame: frame, context: context, deferMarkers: true, on: mapView)
                }
                noteTripsDrawn(on: mapView)
            }

            /// `map.trips.drawn(drawn, wanted)`: visible rides with a drawable
            /// segment in the camera's rect, and how many of them have one inside
            /// the area trips are built for. The only way to measure "at the
            /// stop", because state polls are blocked during motion.
            private func noteTripsDrawn(on mapView: MKMapView) {
                guard RailSignpost.map.isEnabled, layers.routes else { return }
                let visible = mapView.visibleMapRect
                var wanted = 0
                var drawn = 0
                for ride in rides where ride.visible {
                    let riddenStops = ride.stops
                    var isWanted = false
                    var isDrawn = false
                    for segment in ride.segments where segment.boundingRect.intersects(visible)
                        && draws(segment: segment, of: ride, riddenStops: riddenStops) {
                        isWanted = true
                        if segment.boundingRect.intersects(installedTripRect) { isDrawn = true; break }
                    }
                    if isWanted { wanted += 1 }
                    if isDrawn { drawn += 1 }
                }
                RailSignpost.map.mark("map.trips.drawn", drawn, wanted)
            }

            /// Builds the missing lines of newly arrived rides on a worker
            /// and re-enters ``updateRides(_:on:)`` for them when they land.
            /// Arrivals during the build join the same pending set, so one
            /// worker run follows another instead of each taking a rebuild.
            private func prepareArrivalStrokes(
                _ requests: [RideStrokeBuilder.Request], change: RideDeckState.Change,
                frame: MapGeometryFrame, on mapView: MKMapView
            ) {
                arrivalPendingRideIDs.formUnion(change.changed)
                guard arrivalStrokePreparation == nil else { return }
                let strokeFrame = RideStrokeBuilder.Frame(
                    key: frame.key, mapPointsPerScreenPoint: frame.mapPointsPerScreenPoint,
                    scale: frame.scale)
                if rideStrokeEmptyFrameKey != strokeFrame.key {
                    rideStrokeEmptyKeys.removeAll()
                    rideStrokeEmptyFrameKey = strokeFrame.key
                }
                let requestID = UUID()
                arrivalStrokePreparationID = requestID
                let memo = rideStrokeMemo
                let worker = Task.detached(priority: .userInitiated) {
                    await RideStrokeBuilder.build(requests, frame: strokeFrame, memo: memo)
                }
                arrivalStrokePreparation = Task { @MainActor [weak self, weak mapView] in
                    let output = await withTaskCancellationHandler {
                        await worker.value
                    } onCancel: { worker.cancel() }
                    guard let self, let mapView, !Task.isCancelled else { return }
                    self.arrivalStrokePreparation = nil
                    guard self.arrivalStrokePreparationID == requestID else {
                        // Built against caches that were reset meanwhile.
                        self.arrivalPendingRideIDs = []
                        return
                    }
                    for built in output.built {
                        self.networkGeometry.storeRidePolyline(
                            built.polyline, for: built.key, frameKey: strokeFrame.key)
                    }
                    if self.rideStrokeEmptyFrameKey == strokeFrame.key {
                        self.rideStrokeEmptyKeys.formUnion(output.empty)
                    }
                    let pending = self.arrivalPendingRideIDs
                    self.arrivalPendingRideIDs = []
                    guard !pending.isEmpty else { return }
                    let rebuildChange = RideDeckState.Change(
                        changed: pending, orderChanged: false, ambiguous: false)
                    if self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                    } else if self.cameraTravelling, self.reapplyTripsDuringTravel(rebuildChange, on: mapView) {
                        // An extension's missing polylines landed: re-enter it.
                    } else if !self.updateRides(rebuildChange, on: mapView) {
                        self.noteRebuildTrigger(.rideStrokesPrepared)
                        self.rebuild(on: mapView)
                    }
                }
            }

            /// Polylines an extension was missing have landed while the camera
            /// still travels: apply them to the extended area now.
            private func reapplyTripsDuringTravel(
                _ change: RideDeckState.Change, on mapView: MKMapView
            ) -> Bool {
                guard layers.routes, let frame = currentGeometryFrame,
                      let context = markerBuildContext, let cache = rideBatchCache,
                      pendingStrokeRefs == nil,
                      arrivalStrokePreparation == nil, playback?.isActive != true,
                      networkGeometry.currentFrameKey == frame.key,
                      !rebuildDeferredByGesture, !annotationsNeedRefresh,
                      !selectionNeedsHighlightTransition
                else { return false }
                if let selectedTrainID {
                    guard selectedTrainID == fullyBuiltSelectedRideID,
                          !change.changed.contains(selectedTrainID) else { return false }
                }
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                var expected = rideBatchStamp(
                    frameKey: frame.key, hasSelection: hasSelection,
                    dark: mapView.traitCollection.userInterfaceStyle == .dark)
                expected.buildRect = cache.stamp.buildRect
                guard cache.stamp == expected else { return false }
                let applied = applyRideChange(
                    change, frame: frame, context: context, deferMarkers: true, on: mapView)
                if applied { noteTripsDrawn(on: mapView) }
                return applied
            }

            private var arrivalStrokePreparation: Task<Void, Never>?
            private var arrivalStrokePreparationID = UUID()
            private var arrivalPendingRideIDs: Set<String> = []

            /// Keeps the render status and the panel's stats current after a
            /// rides-only update: the last full rebuild's frame, with this
            /// update's ride counts, overlay count and time.
            private func publishRidesOnlyUpdate(
                overlays: Int, rideOverlays: Int, elapsed: Duration, on mapView: MKMapView
            ) {
                guard var stats = lastRenderStats else { return }
#if DEBUG
                // This path replaces the full rebuild during a load, so the
                // probe the control channel reports must follow it too.
                MapRenderProbe.totalOverlays = overlays
                MapRenderProbe.rideOverlays = rideOverlays
#endif
                stats.overlays = overlays
                stats.buildMilliseconds = elapsed.milliseconds
                lastRenderStats = stats
#if DEBUG
                if var snapshot = lastDiagnosticSnapshot {
                    snapshot.totalOverlays = overlays
                    snapshot.rides = rides.count
                    snapshot.rideDots = rideStationAnnotations.filter { $0 is RideStationAnnotation }.count + overlayRideDots.count
                    snapshot.rideLabels = rideStationAnnotations.filter { $0 is RideLabelAnnotation }.count
                    snapshot.buildMilliseconds = elapsed.milliseconds
                    snapshot.annotationViews = mapView.annotations.count
                    snapshot.targetReadiness = targetRideReadiness(on: mapView)
                    snapshot.selectedTrainID = selectedTrainID
                    snapshot.selectedDate = selectedDate
                    lastDiagnosticSnapshot = snapshot
                    diagnostics.publish(snapshot, on: mapView)
                }
#endif
                DispatchQueue.main.async { [onRender] in onRender(stats) }
            }

#if DEBUG
            func stressSelectionReadiness() -> String {
                guard let mapView else { return "" }
                return diagnostics.stressSelectionReadiness(on: mapView, rides: rides, draws: draws)
            }

            private func targetRideReadiness(on mapView: MKMapView) -> String {
                diagnostics.targetRideReadiness(on: mapView, rides: rides,
                    categoryCountries: Set(categoryIndexes.keys),
                    batchedParts: { [batchedRidePartCounts] in batchedRidePartCounts[$0] ?? 0 },
                    draws: draws)
            }
#endif

            /// Load only station identities, so hub priority remains available
            /// with the network hidden or its viewport geometry evicted.
            private func prepareSelectedStationImportance(on mapView: MKMapView) {
                let country = rides.first(where: { $0.id == selectedTrainID })?.country
                selectedStationSnapshots.prepare(
                    country: country,
                    isCurrentMount: { [weak self, weak mapView] in
                        guard let self, let mapView else { return false }
                        return self.mapView === mapView
                    },
                    onFailureChange: { [weak self] message in
                        self?.controller?.selectedStationFailure = message
                    },
                    didLoad: { [weak self, weak mapView] in
                        guard let self, let mapView, self.mapView === mapView else { return }
                        if let selected = self.rides.first(where: { $0.id == self.selectedTrainID }) {
                            self.controller?.selectionRegion = self.selectionRegion(for: selected)
                        }
                        self.focusPendingJourney(on: mapView)
                        if self.isManipulating || self.playback?.isActive == true
                            || self.playbackLayer.lastSnapshot != nil
                            || self.rebuildDeferredByGesture || self.rebuildDeferredByPlayback
                            || self.annotationsNeedRefresh || self.pendingStrokeRefs != nil
                            || self.lastCameraChange.map({ ContinuousClock.now - $0 < .milliseconds(120) }) == true {
                            self.annotationsNeedRefresh = true
                            self.rebuildOwed(on: mapView)
                        } else if let context = self.markerBuildContext {
                            self.buildMarkers(context, on: mapView)
                        } else {
                            self.rebuildOwed(on: mapView)
                        }
                })
            }

            private func knownEndpointPosition(
                for stop: Stop, of ride: RiddenRouteStore.DrawnRide
            ) -> Coordinate? {
                MapEndpointLabels.stationPosition(
                    for: stop, country: ride.country, on: ride.daySpan.date,
                    in: selectedStationSnapshots.snapshot(for: ride.country)?.endpointPositions ?? [:])
            }

            /// Frame known stops alongside available railway. These points do
            /// not become strokes, route continuity, or measured distance.
            private func selectionRegion(for ride: RiddenRouteStore.DrawnRide) -> MKCoordinateRegion? {
                guard selectedStationSnapshots.snapshot(for: ride.country) != nil else { return nil }
                let endpoints = [MapEndpointLabels.Kind.origin, .destination].compactMap { kind in
                    MapEndpointLabels.endpointStop(of: ride, kind: kind) {
                        knownEndpointPosition(for: $0, of: ride)
                    }?.position
                }
                return MapProjection.region(covering: ride.strokes + [endpoints])
            }

            /// A station table arriving completes an existing explicit pick;
            /// it never creates a new camera intent after a gesture or dismissal.
            private func focusPendingJourney(on mapView: MKMapView) {
                guard let controller, controller.mapView === mapView,
                      let request = controller.pendingAutoFocusRequest(matching: controller.autoFocusRequest),
                      case .journey(let id) = request.target, selectedTrainID == id,
                      let ride = rides.first(where: { $0.id == id }),
                      selectedStationSnapshots.snapshot(for: ride.country) != nil,
                      controller.isMapReady,
                      mapView.bounds.width > 1, mapView.bounds.height > 1,
                      playback?.isActive != true else { return }
                // The completed lookup can legitimately have no position. An
                // unavailable route with unknown stations has nothing to frame.
                guard let region = selectionRegion(for: ride) else {
                    _ = controller.takeAutoFocusRequest(matching: request)
                    return
                }
                guard controller.takeAutoFocusRequest(matching: request) == request else { return }
                controller.selectionRegion = region
                controller.fit(region, startedByFocus: true)
            }

            /// Re-elects names through screen-space collisions while moving passes
            /// preserve built zoom and dot positions to avoid replacing endpoint captions.
            /// Settled passes refresh zoom and scale to recover what moving passes skipped.
            @discardableResult
            private func runLabelPass(
                on mapView: MKMapView, moving: Bool, fullPass: Bool = false
            ) -> Bool {
                guard let context = markerBuildContext,
                      playbackLayer.lastSnapshot == nil,
                      playback?.isActive != true,
                      pendingStrokeRefs == nil,
                      mapView.bounds.width > 1,
                      selectedTrainID == nil || selectedTrainID == fullyBuiltSelectedRideID
                else { return false }
#if DEBUG
                let labelPassStarted = ContinuousClock.now
#endif
                var copy = context
                if !moving {
                    copy.zoom = MapProjection.zoomLevel(of: mapView)
                }
                if !moving, styledScale.isFinite {
                    copy.scale = styledScale
                }
                if fullPass {
                    buildMarkers(copy, on: mapView)
                } else if moving {
                    stationLabels.measureMovingPass {
                        buildMarkers(copy, on: mapView, pass: .labels(moving: true))
                    }
                } else {
                    buildMarkers(copy, on: mapView, pass: .labels(moving: false))
                }
#if DEBUG
                diagnostics.didRunLabelPass(
                    manipulating: isManipulating,
                    milliseconds: (ContinuousClock.now - labelPassStarted).milliseconds)
#endif
                return true
            }

            /// A full rebuild re-elects every marker and restyles the mount.
            /// A label pass only touches station names and the lane-fallback
            /// coordinate that holds a dot while it is moving, so it can run on
            /// its own, much faster, between full rebuilds. `moving` marks a
            /// pass that ran mid-gesture, where an installed dot's position
            /// must not jump.
            private enum MarkerPass {
                case full
                case labels(moving: Bool)
            }

            /// The marker pass's lookups, rebuilt only when `lines` or
            /// `stations` moved since the last pass.
            private func markerSetup() -> MarkerSetupCache {
                if let markerSetupCache, markerSetupCache.generation == linesGeneration {
                    return markerSetupCache
                }
                let setup = MarkerSetupCache(generation: linesGeneration, lines: lines, stations: stations)
                markerSetupCache = setup
                return setup
            }

            private func buildMarkers(
                _ context: MarkerBuildContext, on mapView: MKMapView,
                pendingOverlays: [MKOverlay]? = nil,
                networkTransitionDuration: TimeInterval? = nil,
                highlightTransitionDuration: TimeInterval? = nil,
                pass: MarkerPass = .full
            ) {
#if DEBUG
                let markerPhasesStarted = ContinuousClock.now
#endif
                let zoom = context.zoom
                let visibilityZoom = context.visibilityZoom
                let scale = context.scale
                let buildRect = context.buildRect
                let strokeAnchors = context.strokeAnchors
                let visible = context.visible
                let isLabelPass: Bool
                let movingLabelPass: Bool
                switch pass {
                case .full:
                    isLabelPass = false
                    movingLabelPass = false
                case .labels(let moving):
                    isLabelPass = true
                    movingLabelPass = moving
                }
#if DEBUG
                var markerPhaseStarted = markerPhasesStarted
                var markerPhaseMilliseconds: [(name: String, milliseconds: Int)] = []
                var annotationAddedCount = 0
                var annotationRemovedCount = 0
                var annotationRetainedCount = 0
                var annotationCoordinateChangedCount = 0
                var restyledAnnotationViewCount = 0
                func finishMarkerPhase(_ name: String) {
                    guard !isLabelPass else { return }
                    let now = ContinuousClock.now
                    let phaseMilliseconds = (now - markerPhaseStarted).milliseconds
                    RailSignpost.map.mark("map.markers.phase", markerPhaseMilliseconds.count, phaseMilliseconds)
                    markerPhaseMilliseconds.append((name, phaseMilliseconds))
                    markerPhaseStarted = now
                }
#endif
                // Reuse an installed dot's position rather than recomputing the
                // lane fallback mid-gesture — see `parallelStationCoordinate`
                // below. Built once per pass; empty outside a moving label pass,
                // where nothing reads it.
                let installedStationCoordinates: [String: CLLocationCoordinate2D] =
                    movingLabelPass
                    ? Dictionary(
                        networkAnnotations.compactMap {
                            annotation -> (String, CLLocationCoordinate2D)? in
                            guard let station = (annotation as? StationAnnotation)?.station
                            else { return nil }
                            return (
                                "\(station.region.rawValue)|\(station.lineID)|\(station.id)",
                                annotation.coordinate
                            )
                        },
                        uniquingKeysWith: { first, _ in first })
                    : [:]
                let markerInterval = RailSignpost.map.begin(
                    isLabelPass ? "map.labels" : "map.rebuild.markers")
                // Recomputed rather than cached: derived only from coordinator
                // state (`rides`, `selectedTrainID`, `dateScope`, `stations`,
                // `lines`), not from geometry the last rebuild produced.
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                let scope = dateScope
                let setup = markerSetup()
                let stationsByPlace = setup.stationsByPlace
                let linesByStrokeID = setup.linesByStrokeID
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
                    let key = StationNameKeyCache.key(name)
                    guard !key.isEmpty else { return false }
                    return !(namedPlaces[key]?.contains(where: {
                        Geometry.distanceMeters($0, position) <= Self.labelMergeMeters
                    }) ?? false)
                }
                func claimName(_ name: String, at position: Coordinate) -> Bool {
                    let key = StationNameKeyCache.key(name)
                    guard canClaimName(name, at: position) else { return false }
                    namedPlaces[key, default: []].append(position)
                    return true
                }
#if DEBUG
                finishMarkerPhase("setup")
#endif

                // The cards are built here, ahead of every dot, because they
                // hold the first claim on a name. They are still ADDED last,
                // where they always were.
                let endpointSpecList = endpointSpecs(strokeAnchors: strokeAnchors)
                for spec in endpointSpecList {
                    _ = claimName(spec.rawName, at: spec.coordinate)
                }
#if DEBUG
                finishMarkerPhase("endpointSpecsClaims")
#endif

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
                MapEndpointLabels.layout(
                    &placedEndpointSpecs, at: endpointPoints,
                    containerWidth: mapView.bounds.width)
                for index in placedEndpointSpecs.indices {
                    let point = endpointPoints[index]
                    let offset = MapEndpointLabels.centreOffset(
                        for: placedEndpointSpecs[index])
                    let size = CGSize(
                        width: placedEndpointSpecs[index].width,
                        height: placedEndpointSpecs[index].height)
                    labelCollisions.reserve(CGRect(
                        x: point.x + offset.x - size.width / 2,
                        y: point.y + offset.y - size.height / 2,
                        width: size.width, height: size.height))
                }
#if DEBUG
                finishMarkerPhase("endpointLayout")
#endif

                // The selected ride keeps its names even if the deck-wide
                // election handed a shared station to another ride. A station two
                // rides both call at hands its name to whichever record
                // arrived first (`markerLabelWinners` resolves ties by
                // arrival), so filtering afterwards would leave the selected
                // ride unnamed at exactly its busiest stations. The election is
                // re-run over that ride's own records instead.
                var selectedRideNames: Set<String> = []
                // The selected trip's stations show by `SelectedTripStationTiers`:
                // one ranking per trip, read at this pass's scale. The layer
                // switches gate each record's role above the lookup
                // (`layers.draws(role:)`), so the ranking is asked with all
                // tiers on. A railway preview is not a trip and keeps the
                // zoom floors.
                var selectedTiers: SelectedTripStationTiers.Ranking?
                if let ride = rides.first(where: { $0.id == selectedTrainID }) {
                    let signature = Self.rideSignature(ride)
                    selectedRideNames = stationLabels.namedRecordKeys(
                        of: ride, geometryIdentity: signature, settings: display.markers,
                        strokeRef: { [self] ride, segment in strokeRef(for: segment, of: ride) })
                    if !RailwayLinePreview.isPreviewRide(ride.id) {
                        selectedTiers = stationLabels.selectedTripTiers(
                            of: ride, geometryIdentity: signature, settings: display.markers,
                            strokeRef: { [self] ride, segment in strokeRef(for: segment, of: ride) })
                    }
                }
#if DEBUG
                finishMarkerPhase("selectedNames")
                let ridesDigestStarted = ContinuousClock.now
#endif

                // Every visible ride's calls, flattened into the deck marker
                // records `RailCore.StationDisplay` already knows how to elect
                // names for. Not just the selected ride's: the election exists
                // because a station reached by twenty trains ships twenty records
                // that all know the same name, and only one of them may print it.
                let ridesGeometryIdentity = rideDeck.deckDigest
#if DEBUG
                if !isLabelPass {
                    let now = ContinuousClock.now
                    markerPhaseMilliseconds.append(
                        ("ridesDigest", (now - ridesDigestStarted).milliseconds))
                    markerPhaseStarted = now
                }
#endif
                let deckRecords = stationLabels.records(
                    for: rides, geometryIdentity: ridesGeometryIdentity,
                    rideIdentity: { [rideDeck] in rideDeck.digest(of: $0.id) },
                    strokeGeneration: linesGeneration, settings: display.markers,
                    strokeRef: { [self] ride, segment in strokeRef(for: segment, of: ride) })
                let drawn = deckRecords.drawn
                let selectedCallCount = selectedTrainID == nil || selectedTiers != nil ? 0 : Set(drawn.filter {
                    $0.feature.tid == selectedTrainID
                        && ["terminal", "xday", "stop"].contains($0.feature.role)
                }.map(\.record.position)).count
                let preservesSelectedCalls = rides.first { $0.id == selectedTrainID }.map {
                    StationLabelVisibility.preservesSelectedCalls(
                        trainType: $0.trainType, country: $0.country, callCount: selectedCallCount)
                } ?? false
#if DEBUG
                finishMarkerPhase("records")
#endif
                let connectionsByPlace = setup.connectionsByPlace
#if DEBUG
                finishMarkerPhase("connections")
#endif
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
                        let riddenStops = ride.stops
                        let ridden = ride.segments.filter { segment in
                            guard let stopInterval = ride.stopInterval(forSectionIndex: segment.segmentIndex) else { return false }
                            return Statistics.isRideSegment(riddenStops, segmentIndex: stopInterval)
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
                // Unselected rides retain role-specific zoom floors. The
                // Sparse selected services offer every call. Dense stopping
                // lists reveal hubs first; pass-throughs wait for close zooms.
                var markerAnnotations: [MKAnnotation] = []
                var overlayDots: [RideStationAnnotation] = []
                /// Overlay-drawn dots stay out of MapKit entirely.
                func placeDot(_ dot: RideStationAnnotation) {
                    if dot.drawsInOverlay { overlayDots.append(dot) } else { markerAnnotations.append(dot) }
                }
                var pendingRideLabels: [(
                    claimName: String, position: Coordinate,
                    annotation: RideLabelAnnotation, importance: Int,
                    supportingDot: RideStationAnnotation?
                )] = []
                let markerMapPointsPerScreenPoint = MapProjection.mapPointsPerScreenPoint(of: mapView)
                var displayedCoordinateCache = DisplayedStationCoordinateCache()
                var connectionCounts: [StationPlaceKey: Int] = [:]
                var networkTerminalStatuses: [StationPlaceKey: Bool] = [:]
                var routeColors: [String: UIColor] = [:]
#if DEBUG
                var selectedTripMarks: [String: Int] = [:]
                var culledRecordCount = 0
                finishMarkerPhase("hiddenRides")
#endif
                // Only the records near the built area: the grid answers in deck
                // order, and the exact per-record cull below still decides.
                let recordCandidates = deckRecords.grid.indices(in: Self.cullQueryRect(
                    buildRect: buildRect, mapPointsPerScreenPoint: markerMapPointsPerScreenPoint))
                for recordIndex in recordCandidates {
                    let item = drawn[recordIndex]
                    let record = item.record
                    let feature = item.feature
                    // Role and category switches govern ordinary dots.
                    // Named endpoints are guaranteed separately below.
                    guard layers.draws(role: feature.role),
                        !fullyHiddenRides.contains(feature.tid) else {
                        continue
                    }
                    let selected = feature.tid == selectedTrainID
                    guard !hasSelection || selected else { continue }
                    let recordPoint = MKMapPoint(record.position.clLocation)
                    let cullMargin = max(
                        2_000 * MKMapPointsPerMeterAtLatitude(record.position.lat),
                        96 * markerMapPointsPerScreenPoint)
                    guard buildRect.insetBy(dx: -cullMargin, dy: -cullMargin)
                        .contains(recordPoint) else {
#if DEBUG
                        culledRecordCount += 1
#endif
                        continue
                    }
                    let placeKey = item.region.flatMap { region in
                        item.stationCode.map {
                            StationPlaceKey(region: region.rawValue, stationCode: $0)
                        }
                    }
                    let connectionCount: Int
                    let isNetworkTerminal: Bool
                    if let placeKey {
                        if let cached = connectionCounts[placeKey] {
                            connectionCount = cached
                        } else {
                            let value = max(
                                connectionsByPlace[
                                    "\(placeKey.region)|\(placeKey.stationCode)"] ?? 0,
                                selectedStationSnapshots.snapshot(for: placeKey.region)?.lineCounts[placeKey.stationCode] ?? 0)
                            connectionCounts[placeKey] = value
                            connectionCount = value
                        }
                        if let cached = networkTerminalStatuses[placeKey] {
                            isNetworkTerminal = cached
                        } else {
                            let value = stationsByPlace[
                                "\(placeKey.region)|\(placeKey.stationCode)"]?
                                .contains(where: \.isTerminal) ?? false
                            networkTerminalStatuses[placeKey] = value
                            isNetworkTerminal = value
                        }
                    } else {
                        connectionCount = 0
                        isNetworkTerminal = false
                    }
                    let selectedMinimum = StationLabelVisibility.selectedRideMinimumMapLibreZoom(
                        role: feature.role, preservesCalls: preservesSelectedCalls,
                        densityMinimum: item.mapLibreMinZoom, lineCount: connectionCount,
                        isNetworkTerminal: isNetworkTerminal)
                    let tierMark = selected ? selectedTiers?.mark(
                        for: MapStationLabelCoordinator.markerKey(record),
                        metresPerPoint: markerMapPointsPerScreenPoint
                            / MKMapPointsPerMeterAtLatitude(record.position.lat)) : nil
                    let drawsDot = tierMark?.drawsDot ?? MapRideMarkers.drawsDot(
                        item, atZoom: zoom, isSelected: selected, selectedCallMinimum: selectedMinimum)
                    // Gate both the dot and its name: label collision placement
                    // can otherwise restore a supporting dot below its floor.
                    if selected && !drawsDot { continue }
                    // A selected journey uses screen space rather than the
                    // network zoom ladder to decide which names can fit.
                    // Other rides keep the journey-only map's existing rule.
                    guard selected || !showsNetwork || drawsDot
                            || feature.role == "stop-center" else {
                        continue
                    }
                    if feature.role == "stop-center" { continue }
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
                    let displayCoordinate = displayedStationCoordinate(
                        at: record.position, anchor: item.strokeAnchor,
                        ride: ridesByID[feature.tid], strokeAnchors: strokeAnchors,
                        cache: &displayedCoordinateCache)
                    guard buildRect.contains(MKMapPoint(displayCoordinate)) else { continue }
                    let routeColor: UIColor
                    if let cached = routeColors[item.routeColorHex] {
                        routeColor = cached
                    } else {
                        let color = UIColor(railHex: item.routeColorHex) ?? .railDefaultTrip
                        routeColors[item.routeColorHex] = color
                        routeColor = color
                    }
                    let stationID = ridesByID[feature.tid]?.stops.first { stop in
                        stop.name == record.name
                            && (item.stationCode == nil || stop.n02StationCode == item.stationCode)
                    }?.stationID
                    // A pass is a smaller hollow ring in the route colour. An
                    // on-route station (no source says stop or pass) is smaller
                    // still, with a neutral grey ring: not a claim either way.
                    let onRoute = tierMark?.stationClass == .onRoute
                    let markScale: CGFloat = onRoute ? 0.6 : feature.role == "pass" ? 0.75 : 1
                    let annotation = RideStationAnnotation(
                        rideID: feature.tid, drawsInOverlay: tripDotsDrawInOverlay(hasSelection: hasSelection),
                        coordinate: displayCoordinate,
                        name: feature.name,
                        rawName: record.name,
                        stationCode: item.stationCode,
                        region: item.region,
                        role: feature.role,
                        stationID: stationID,
                        radius: CGFloat(feature.radius) * markScale,
                        lineWidth: CGFloat(feature.lineWidth) * markScale,
                        ordinaryRadius: CGFloat(display.markers.passRadius),
                        ordinaryLineWidth: CGFloat(MapRideMarkers.ringWidth(
                            1, settings: display.markers)),
                        focusScale: CGFloat(feature.focusScale) * markScale,
                        // Calls are solid; only pass-throughs have a hollow centre.
                        fill: feature.role == "pass" ? .white : routeColor,
                        stroke: onRoute ? .systemGray : feature.role == "pass" ? routeColor : .white,
                        // The record's OWN alpha, put through the same two
                        // scopes the ride's stroke goes through — a dot on an
                        // off-date ride dims with the line it sits on.
                        alpha: CGFloat(feature.alpha) * MapDateScope.alpha(
                            own: 1, span: item.daySpan, scope: scope,
                            isSelected: selected, hasSelection: hasSelection),
                        focusBoost: CGFloat(display.focusBoost),
                        selected: selected)
                    if drawsDot { placeDot(annotation) }
#if DEBUG
                    if let tierMark, drawsDot {
                        selectedTripMarks["\(tierMark.stationClass).dots", default: 0] += 1
                        if tierMark.offersName {
                            selectedTripMarks["\(tierMark.stationClass).names", default: 0] += 1
                        }
                    }
#endif
                    // …and its name, if it won one. Unselected rides retain
                    // their tier floor; a selected ride offers every name to
                    // collision placement. Elect the new visible names first;
                    // the reconciler keeps outgoing captions only for their fade.
                    //
                    // Only the highlighted journey's stations are shown.
                    let labelName = selected
                        && selectedRideNames.contains(MapStationLabelCoordinator.markerKey(record))
                        ? record.name : feature.name
                    guard !labelName.isEmpty, let tier = annotation.labelTier,
                          selected || !showsNetwork
                            || zoom >= RailStyle.zoom(fromMapLibre: Double(tier.minZoom)),
                          tierMark?.offersName ?? true
                    else { continue }
                    // The election runs on the package's own names — see
                    // The cached marker election names only its winner, so
                    // which record carries a name never depends on the
                    // reader's language.
                    let stationName = mapStationLabel(
                        labelName, code: item.stationCode, region: item.region,
                        stationID: annotation.stationID)
                    let roleTag = selected && !RailwayLinePreview.isPreviewRide(feature.tid)
                        ? (onRoute ? "" : feature.role == "pass" ? naming.passTag
                        : feature.role == "stop" ? naming.stopTag : "") : ""
                    let displayedName = roleTag.isEmpty
                        ? stationName : "\(stationName) · \(roleTag)"
                    let label = RideLabelAnnotation(
                        coordinate: annotation.coordinate,
                        text: displayedName,
                        rawName: record.name, stationCode: item.stationCode,
                        region: item.region,
                        tier: tier,
                        dotRadiusToken: annotation.drawnRadiusToken(atZoom: zoom),
                        selected: annotation.selected,
                        stationID: annotation.stationID)
                    let importance = tierMark.map {
                        SelectedTripStationTiers.labelPriority(
                            $0.stationClass, lineCount: connectionCount,
                            isNetworkTerminal: isNetworkTerminal)
                    } ?? StationLabelVisibility.rideLabelPriority(
                        role: feature.role, lineCount: connectionCount,
                        isNetworkTerminal: isNetworkTerminal)
                    pendingRideLabels.append((
                        claimName: labelName, position: record.position,
                        annotation: label,
                        // Journey boundaries, then connected hubs, calls and
                        // pass-throughs. Selection retains first priority.
                        importance: (annotation.selected ? 10_000 : 0) + importance,
                        supportingDot: drawsDot ? nil : annotation))
                }
#if DEBUG
                MapRenderProbe.selectedTripMarks = selectedTiers == nil ? nil : selectedTripMarks
                finishMarkerPhase("rideDotLoop")
#endif
                for spec in endpointSpecList {
                    guard let ride = ridesByID[spec.trainID] else { continue }
                    let selected = ride.id == selectedTrainID
                    let position = spec.coordinate.clLocation
                    // Replace a coincident dot with the same resolved endpoint
                    // identity rather than drawing two marker sizes over it.
                    func coincides(_ dot: RideStationAnnotation) -> Bool {
                        guard dot.selected == selected,
                              StationNameKeyCache.key(dot.rawName)
                                == StationNameKeyCache.key(spec.rawName) else { return false }
                        return MKMapPoint(dot.coordinate).distance(to: MKMapPoint(position)) < 0.1
                    }
                    markerAnnotations.removeAll { ($0 as? RideStationAnnotation).map(coincides) ?? false }
                    overlayDots.removeAll(where: coincides)
                    let endpoint = MapEndpointLabels.endpointStop(of: ride, kind: spec.kind,
                        stationPosition: { knownEndpointPosition(for: $0, of: ride) })
                    let color = UIColor(railHex: ride.colorHex) ?? .railDefaultTrip
                    placeDot(RideStationAnnotation(
                        rideID: ride.id, drawsInOverlay: tripDotsDrawInOverlay(hasSelection: hasSelection),
                        coordinate: position, name: spec.name, rawName: spec.rawName,
                        stationCode: endpoint?.stop.n02StationCode,
                        region: Region(rawValue: ride.country), role: "terminal",
                        stationID: endpoint?.stop.stationID,
                        radius: CGFloat(display.markers.terminalRadius),
                        lineWidth: CGFloat(MapRideMarkers.ringWidth(1, settings: display.markers)),
                        ordinaryRadius: CGFloat(display.markers.passRadius),
                        ordinaryLineWidth: CGFloat(MapRideMarkers.ringWidth(1, settings: display.markers)),
                        focusScale: 1, fill: color, stroke: .white,
                        alpha: selected ? 1 : MapDateScope.alpha(
                            own: 1, span: ride.daySpan, scope: scope,
                            isSelected: false, hasSelection: hasSelection),
                        focusBoost: CGFloat(display.focusBoost), selected: selected))
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
                    let gap = item.dotRadiusToken * scale
                        + textSize * MapLabelStyle.radialOffsetEm
                    let trailing = CGRect(
                        x: point.x + gap, y: point.y - height / 2,
                        width: width, height: height)
                    let leading = CGRect(
                        x: point.x - gap - width, y: point.y - height / 2,
                        width: width, height: height)
                    if labelCollisions.insertIfClear(trailing) {
                        item.side = .trailing
                    } else if labelCollisions.insertIfClear(leading) {
                        item.side = .leading
                    } else {
                        continue
                    }
                    guard claimName(candidate.claimName, at: candidate.position)
                    else { continue }
                    // Only revive a below-threshold dot when its label fits;
                    // a national view must not instantiate every station view.
                    if let dot = candidate.supportingDot {
                        placeDot(dot)
                    }
                    markerAnnotations.append(item)
                }
#if DEBUG
                finishMarkerPhase("rideLabels")
#endif

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
                if showsNetwork, layers.networkStations, !hasSelection {
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
                    // measured on (the shared display-datum chain, so it does
                    // not depend on this frame's pixel scale).
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
                    func promotesName(_ station: RailNetworkStore.DrawnStation) -> Bool {
                        // Offer every elected name as soon as its railway is
                        // drawn. Screen-space placement decides what fits;
                        // only accepted names restore a supporting bead below
                        // the station-dot LOD floor.
                        layers.networkStationNames && station.showsLabel
                    }
                    func beadPolicyStation(_ station: RailNetworkStore.DrawnStation) -> StationBeadPolicy.Station {
                        let anchor = station.slot.flatMap {
                            anchorMeasure(region: station.region, lineID: station.lineID, slot: $0)
                        }
                        return .init(
                            region: station.region.rawValue, stationCode: station.stationCode,
                            lineID: station.lineID, isDrawn: isDrawn(station),
                            anchorMeasure: anchor?.measure,
                            windows: anchor?.line.familyWindows.map {
                                .init(groupID: $0.groupID, isLandlord: $0.isLandlord, from: $0.from, to: $0.to)
                            } ?? [])
                    }
                    var beadStationsByPlace: [String: [StationBeadPolicy.Station]] = [:]
                    func isSuppressedTenantBead(_ station: RailNetworkStore.DrawnStation) -> Bool {
                        // The station's own policy record first: with no tenant
                        // group `StationBeadPolicy.isSuppressed` is false whatever
                        // the siblings are, so they are not even mapped.
                        let own = beadPolicyStation(station)
                        guard own.tenantGroup != nil else { return false }
                        let place = "\(station.region.rawValue)|\(station.stationCode)"
                        if beadStationsByPlace[place] == nil {
                            beadStationsByPlace[place] = (stationsByPlace[place] ?? []).map(beadPolicyStation)
                        }
                        return StationBeadPolicy.isSuppressed(own, siblings: beadStationsByPlace[place] ?? [])
                    }
                    let era = display.networkEra
                    let rideDate = networkRideDate
                    let todayByRegion = networkTodayByRegion
                    let stationCandidates = setup.stationGrid.indices(in: .init(
                        x: buildRect.origin.x, y: buildRect.origin.y,
                        width: buildRect.size.width, height: buildRect.size.height))
                    let visibleStations = stationCandidates.compactMap { index -> (
                        key: String, station: RailNetworkStore.DrawnStation,
                        displayName: String, readings: [String]?, alpha: CGFloat
                    )? in
                        let station = self.stations[index]
                        let today = todayByRegion[station.region.rawValue] ?? ""
                        guard era.shows(
                            station.temporalDecoration, today: today, rideDate: rideDate,
                            isStation: true)
                        else { return nil }
                        guard station.lodMinZoom <= visibilityZoom || promotesName(station)
                        else { return nil }
                        let point = MKMapPoint(station.coordinate.clLocation)
                        guard buildRect.contains(point) else { return nil }
                        guard drawnLineIDs.contains(station.lineID) else { return nil }
                        guard !isSuppressedTenantBead(station) else { return nil }
                        // Readings key on the platform id. A miss keeps the stored
                        // name; it does not borrow another station's name.
                        let named = self.localized(station.name, code: station.id)
                        let referenceDay = era == .rideDate && Dates.isValidDateString(rideDate)
                            ? (rideDate ?? today) : today
                        let open = RouteGraph.RailValidity.isValid(
                            validFrom: station.validFrom, validTo: station.validTo, on: referenceDay)
                        // Closed overlay stations stay a normal dot. Never the
                        // cross-day diamond (`role == "xday"`).
                        let alpha: CGFloat = station.isOverlay && !open ? 0.4 : 1
                        return (
                            key: "\(station.region.rawValue)|\(station.lineID)|\(station.id)",
                            station: station, displayName: named.display,
                            readings: self.localization == nil
                                ? nil : named.readings.map(\.text),
                            alpha: alpha)
                    }

#if DEBUG
                    finishMarkerPhase("networkStations.filter")
#endif
                    // The network is the broadest naming layer, so it fills the
                    // spaces left by endpoint cards and journey captions. Among
                    // its own candidates, Apple-style navigational hierarchy
                    // wins: interchanges, then line ends, then ordinary stops.
                    var acceptedStationNames: Set<String> = []
                    if layers.networkStationNames {
                        let ordered = visibleStations.filter {
                            $0.station.showsLabel
                        }.sorted {
                            let left = $0.station.popup.lines.count > 1
                                ? $0.station.popup.lines.count + 1 : ($0.station.isTerminal ? 1 : 0)
                            let right = $1.station.popup.lines.count > 1
                                ? $1.station.popup.lines.count + 1 : ($1.station.isTerminal ? 1 : 0)
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
                            let width = min(180, stationLabels.labelWidth(
                                of: candidate.displayName, pointSize: textSize, font: font))
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

#if DEBUG
                    finishMarkerPhase("networkStations.election")
#endif
                    let stationAnnotations = visibleStations.compactMap { candidate -> StationAnnotation? in
                        let station = candidate.station
                        guard station.lodMinZoom <= visibilityZoom
                            || acceptedStationNames.contains(candidate.key) else { return nil }
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
                            markerAlpha: candidate.alpha,
                            displayCoordinate: station.slot.flatMap { slot in
                                strokeAnchors[
                                    "\(station.region.rawValue)|\(station.lineID)#\(slot.chain)"
                                ]?[slot.anchor]
                            } ?? nearestStrokeAnchorCoordinate(
                                for: station, in: strokeAnchors
                            ) ?? installedStationCoordinates[candidate.key]
                            ?? parallelStationCoordinate(
                                station.coordinate.clLocation,
                                lane: station.lane,
                                bearing: station.laneBearing,
                                scale: scale,
                                on: mapView))
                    }
                    desiredNetworkAnnotations = stationAnnotations
                }
#if DEBUG
                finishMarkerPhase("networkStations.annotations")
#endif
                let networkAnnotationPlan = annotationReconciler.plan(
                    desiredNetworkAnnotations, replacing: networkAnnotations)
                networkAnnotations = annotationReconciler.apply(
                    networkAnnotationPlan, on: mapView, duration: detailDuration)
                let rideStationAnnotationPlan = annotationReconciler.plan(
                    markerAnnotations, replacing: rideStationAnnotations)
                rideStationAnnotations = annotationReconciler.apply(
                    rideStationAnnotationPlan, on: mapView, duration: detailDuration)
                overlayRideDots = overlayDots
                if !isLabelPass { markerPassDebt.noteFullPassRan() }
#if DEBUG
                annotationAddedCount = networkAnnotationPlan.addedCount
                    + rideStationAnnotationPlan.addedCount
                annotationRemovedCount = networkAnnotationPlan.removedCount
                    + rideStationAnnotationPlan.removedCount
                annotationRetainedCount = networkAnnotationPlan.retainedCount
                    + rideStationAnnotationPlan.retainedCount
                annotationCoordinateChangedCount = networkAnnotationPlan.coordinateChangedCount
                    + rideStationAnnotationPlan.coordinateChangedCount
                diagnostics.reusedAnnotations(
                    networkAnnotationPlan.retainedOldCount
                        + rideStationAnnotationPlan.retainedOldCount)
                finishMarkerPhase("annotationApply")
#endif
                // A moving label pass never installs ride-station overlays: it
                // only relabels, and must not fight the gesture for the dots
                // a full rebuild already placed.
                if !movingLabelPass {
                    installRideStationOverlays(on: mapView, scale: scale,
                        pendingOverlays: pendingOverlays,
                        networkTransitionDuration: networkTransitionDuration,
                        highlightTransitionDuration: highlightTransitionDuration)
                }
#if DEBUG
                finishMarkerPhase("rideStationOverlayInstall")
#endif
                // A label pass changes no scale and must not clear the mark
                // zoom a full rebuild is still using to throttle `restyle`.
                if !isLabelPass {
                    // Retained views need the final zoom's sizing after a pinch.
                    styledScale = .nan
                    styledOverlayScale = .nan
                    styledMarkZoom = .nan
#if DEBUG
                    restyledAnnotationViewCount = restyle(on: mapView)
#else
                    restyle(on: mapView)
#endif
                }
                RailSignpost.map.end(
                    isLabelPass ? "map.labels" : "map.rebuild.markers", markerInterval)
#if DEBUG
                finishMarkerPhase("annotationRestyle")
#endif

                // The selected ride's origin / destination cards, and — when a
                // day is in scope — that DAY's first origin and last
                // destination with a 起點/終點 badge, which is `updateEndpointLabels`
                // step (1). `computeScopedEndpoints` is not ported: the scoped
                // pair is derived here from the rides the map already holds.
                endpointAnnotations = annotationReconciler.reconcile(
                    endpointSpecList.map(EndpointLabelAnnotation.init),
                    replacing: endpointAnnotations, on: mapView, duration: detailDuration)
                    .compactMap { $0 as? EndpointLabelAnnotation }
                if !endpointAnnotations.isEmpty { layoutEndpointLabels(on: mapView) }
#if DEBUG
                finishMarkerPhase("endpointsAdd")
                if !isLabelPass {
                    let measuredMilliseconds = markerPhaseMilliseconds.reduce(0) {
                        $0 + $1.milliseconds
                    }
                    let totalMilliseconds = (ContinuousClock.now - markerPhasesStarted).milliseconds
                    markerPhaseMilliseconds.append((
                        "other", max(0, totalMilliseconds - measuredMilliseconds)))
                    let value = (
                        markerPhaseMilliseconds.map { "\($0.name)=\($0.milliseconds)" }
                            + ["drawnCount=\(drawn.count)", "stationsCount=\(stations.count)",
                               "culled=\(culledRecordCount)",
                               "annAdded=\(annotationAddedCount)",
                               "annRemoved=\(annotationRemovedCount)",
                               "annRetained=\(annotationRetainedCount)",
                               "annCoordChanged=\(annotationCoordinateChangedCount)",
                               "restyledViews=\(restyledAnnotationViewCount)"]
                    ).joined(separator: ",")
                    diagnostics.didBuildMarkerPhases(value)
                }
#endif
            }

            /// A rect that contains every record the marker cull below can keep:
            /// the build rect grown by the largest cull margin it can use.
            private static func cullQueryRect(
                buildRect: MKMapRect, mapPointsPerScreenPoint: Double
            ) -> SpatialGrid.Rect {
                let extremeLatitude = max(
                    abs(MKMapPoint(x: buildRect.minX, y: buildRect.minY).coordinate.latitude),
                    abs(MKMapPoint(x: buildRect.minX, y: buildRect.maxY).coordinate.latitude))
                let margin = max(
                    2_000 * MKMapPointsPerMeterAtLatitude(extremeLatitude),
                    96 * mapPointsPerScreenPoint) * 1.5
                return SpatialGrid.Rect(
                    x: buildRect.origin.x, y: buildRect.origin.y,
                    width: buildRect.size.width, height: buildRect.size.height
                ).inset(by: margin)
            }

            private static let allRideStationsID = "all"

            /// Mount every unselected journey's circles above all its strokes.
            /// Running after the final marker election also covers supporting
            /// dots restored by labels and endpoint replacements, and repairs
            /// the stack after the selection fast path clears a highlight.
            private func installRideStationOverlays(
                on mapView: MKMapView, scale: CGFloat,
                pendingOverlays: [MKOverlay]? = nil,
                networkTransitionDuration: TimeInterval? = nil,
                highlightTransitionDuration: TimeInterval? = nil
            ) {
                let reconciliation = overlayInstaller.reconciliation(on: mapView)
                let installed = reconciliation.oldOverlays
                let previous = Dictionary(installed.compactMap { $0 as? RideStationOverlay }
                    .map { ($0.rideID, $0) }, uniquingKeysWith: { first, _ in first })
                let stations = Dictionary(grouping: overlayRideDots, by: \.rideID)
                let base = (pendingOverlays ?? installed).filter { !($0 is RideStationOverlay) }
                // Selection already raised its casing and cores. Only remove
                // ordinary circle batches here; rebuilding deck order would
                // put a selected early ride underneath later journeys.
                if rides.contains(where: { $0.id == selectedTrainID }) {
#if DEBUG
                    recordRideStationDots(drawn: 0, overlayStations: 0)
#endif
                    retiringStationOverlays.removeAll()
                    overlayInstaller.install(base, replacing: reconciliation, scale: scale, on: mapView,
                        detailTransitionDuration: networkTransitionDuration,
                        alphaTransitionDuration: highlightTransitionDuration)
                    return
                }
                let duration = detailDuration
                var strokes: [String: [MKOverlay]] = [:]
                var desired: [MKOverlay] = []
                var playbackOverlays: [MKOverlay] = []
                for overlay in base {
                    let key = (overlay.title ?? nil) ?? ""
                    if MapOverlayStyles.isRideCoreKey(key),
                       let separator = key.firstIndex(of: "|") {
                        strokes[String(key[key.index(after: separator)...]), default: []].append(overlay)
                    } else if key.hasPrefix("playback") {
                        playbackOverlays.append(overlay)
                    } else {
                        desired.append(overlay)
                    }
                }
                // Use the deck order even after deselection: the previous
                // selected route may have been moved to the top of the stack.
                for ride in rides {
                    desired.append(contentsOf: strokes.removeValue(forKey: ride.id) ?? [])
                }
                // One canvas for every journey's circles, in deck order, above
                // every journey's strokes. See ``RideStationOverlay``.
                let dots = rides.flatMap { stations[$0.id] ?? [] }
                let old = previous[Self.allRideStationsID]
#if DEBUG
                var overlayStationCount = 0
                defer { recordRideStationDots(drawn: dots.count, overlayStations: overlayStationCount) }
#endif
                if !dots.isEmpty || (duration > 0 && old != nil) {
                    let overlay: RideStationOverlay
                    if let old {
                        overlay = old
                        overlay.stations = dots
                    } else {
                        overlay = RideStationOverlay(rideID: Self.allRideStationsID, stations: dots)
                    }
                    overlay.transitionDuration = duration
#if DEBUG
                    overlayStationCount = overlay.stations.count
#endif
                    if let renderer = mapView.renderer(for: overlay) as? RideStationOverlayRenderer {
                        renderer.updateStations(duration: duration)
                    }
                    let id = ObjectIdentifier(overlay)
                    if dots.isEmpty {
                        // Keep the empty batch mounted until its outgoing dots
                        // finish painting. A new update invalidates this removal.
                        if retiringStationOverlays[id] == nil {
                            let token = UUID()
                            retiringStationOverlays[id] = token
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak mapView] in
                                guard let self, self.retiringStationOverlays[id] == token else { return }
                                self.retiringStationOverlays.removeValue(forKey: id)
                                guard overlay.stations.isEmpty else { return }
                                mapView?.removeOverlay(overlay)
                            }
                        }
                    } else {
                        retiringStationOverlays.removeValue(forKey: id)
                    }
                    desired.append(overlay)
                }
                desired.append(contentsOf: playbackOverlays)
                overlayInstaller.install(desired, replacing: reconciliation, scale: scale, on: mapView,
                    detailTransitionDuration: networkTransitionDuration,
                    alphaTransitionDuration: highlightTransitionDuration)
            }

#if DEBUG
            /// A selection keeps its dots on the selected ride's own layers, so
            /// that pass reports no shared-overlay dots.
            private func recordRideStationDots(drawn: Int, overlayStations: Int) {
                let stationsCount = rideStationAnnotations.count + overlayRideDots.count
                MapRenderProbe.rideStationDots = .init(
                    drawn: drawn, stations: stationsCount, overlayStations: overlayStations)
                MapRenderProbe.log.debug(
                    "rideStationDots drawn=\(drawn) stations=\(stationsCount) overlayStations=\(overlayStations)")
            }
#endif

            /// The marker records, built once per ride set rather than per pan.
            ///
            /// `buildDeckMarkerRecords` is documented SELECTION-INDEPENDENT and
            /// nothing in it reads the zoom, so the record set only changes with
            /// the rides and the 顯示調節 sizes — while `rebuild` also runs
            /// whenever the map is panned out of the rect it was built for. The
            /// name election walks every ride's every call, so re-running it on a
            /// pan would be the most expensive thing a pan does.
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
            ) -> [RideTapIndex.Source] {
                let filtered = layers.categories.anyHidden
                let riddenStops = filtered ? ride.stops : []
                return ride.segments.map { segment in
                    guard !filtered || draws(segment: segment, of: ride, riddenStops: riddenStops)
                    else { return .coordinates([]) }
                    return tapSource(of: segment, in: ride)
                }
            }

            /// The polyline the worker already built for this segment, copied as
            /// map points, else the segment's raw coordinates. No geometry
            /// maths: a tap's tolerance covers the lane offset and rounding.
            private func tapSource(
                of segment: RiddenRouteStore.DrawnSegment, in ride: RiddenRouteStore.DrawnRide
            ) -> RideTapIndex.Source {
                let ref = strokeRef(for: segment, of: ride)
                let usesStroke = ref.map { networkGeometry.containsStroke(for: $0.chainID) } ?? false
                let key = rideLineCacheKey(of: segment, in: ride, stroke: usesStroke ? ref : nil)
                guard let polyline = networkGeometry.ridePolyline(for: key), polyline.pointCount >= 2
                else { return .coordinates(segment.coordinates) }
                return .mapPoints(Array(UnsafeBufferPointer(
                    start: polyline.points(), count: polyline.pointCount)))
            }

            /// Keep unchanged route pixels through progressive arrivals. A new
            /// stroke match invalidates only that ride's stroke-derived variant;
            /// the canonical variant still names the same source geometry. A
            /// line-sliced variant is also tied to its line's stroke generation
            /// by its key, so a rebuilt line strands only its own trips.
            private func retainRidePolylines(excludingStrokeFor changedRideIDs: Set<String> = []) {
                var segments: Set<RideLineCacheKey.SegmentIdentity> = []
                for ride in rides {
                    for segment in ride.segments {
                        segments.insert(.init(
                            rideID: ride.id, geometryDigest: ride.geometryDigest,
                            segmentIndex: segment.segmentIndex, partIndex: segment.partIndex))
                    }
                }
                networkGeometry.retainRidePolylines(
                    ofSegments: segments, droppingStrokeVariantsOf: changedRideIDs)
            }

            /// The same retention as ``retainRidePolylines(excludingStrokeFor:)``
            /// after a rides-only change, touching only the rides it names: an
            /// unchanged ride's keys are already exactly its current ones.
            private func retainRidePolylines(changed change: RideDeckState.Change) {
                guard !change.ambiguous else {
                    retainRidePolylines()
                    return
                }
                guard !change.changed.isEmpty else { return }
                var segments: Set<RideLineCacheKey.SegmentIdentity> = []
                for ride in rides where change.changed.contains(ride.id) {
                    for segment in ride.segments {
                        segments.insert(.init(
                            rideID: ride.id, geometryDigest: ride.geometryDigest,
                            segmentIndex: segment.segmentIndex, partIndex: segment.partIndex))
                    }
                }
                networkGeometry.retainRidePolylines(ofRides: change.changed, segments: segments)
            }

            /// Computes the next line set on a worker thread (or synchronously,
            /// `checksCancellation: false`, for an era change): the junction
            /// index and dependency ids, the junction lines, the station
            /// anchors and every line's inputs. Reads only its input; copy-on-write
            /// of the index happens here, never on the main actor. Returns nil
            /// when cancelled between phases.
            nonisolated private static func computeLineSwap(
                _ input: LineSwapInput, baseSerial: Int, checksCancellation: Bool
            ) -> LineSwapResult? {
                let interval = RailSignpost.map.begin("map.lineSwap.compute")
                defer { RailSignpost.map.end("map.lineSwap.compute", interval) }
                func cancelled() -> Bool { checksCancellation && Task.isCancelled }
                let lines = input.lines
                let byID = Dictionary(lines.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first })
                let chainKeys = Set(lines.map(JoinedChainKey.init))
                let junctionLineMemo = input.memo
                if cancelled() { return nil }
                // A line whose content id is unchanged keeps its junction
                // line (same coordinates buffer), so neither the chain lookup
                // nor the index's equality check does per-vertex work for it.
                var nextMemo: [String: JunctionLineMemo] = [:]
                nextMemo.reserveCapacity(lines.count)
                let junctionLines = lines.map { line -> StrokeJunctionIndex.Line in
                    if let known = junctionLineMemo[line.id], known.contentID == line.contentID {
                        nextMemo[line.id] = known
                        return known.line
                    }
                    let built = StrokeJunctionIndex.Line(
                        id: line.id, region: line.region.rawValue, operatorName: line.operatorName,
                        coordinates: input.joinedChains.chain(of: line).points,
                        continuous: line.continuous, follows: line.follows.map(\.canonicalID))
                    nextMemo[line.id] = JunctionLineMemo(contentID: line.contentID, line: built)
                    return built
                }
                if cancelled() { return nil }
                let advanced = input.state.advanced(to: junctionLines)
                if cancelled() { return nil }
                var anchors: [String: [Int]] = [:]
                for station in input.stations {
                    guard let slot = station.slot else { continue }
                    anchors["\(station.region.rawValue)|\(station.lineID)#\(slot.chain)", default: []]
                        .append(slot.anchor)
                }
                var inputs: [String: LineInputs] = [:]
                inputs.reserveCapacity(lines.count)
                for line in lines {
                    var dependencies: [String: UUID] = [:]
                    for id in advanced.state.dependencyIDs[line.id] ?? [] {
                        dependencies[id] = byID[id]?.contentID
                    }
                    inputs[line.id] = LineInputs(contentID: line.contentID,
                        anchors: anchors[line.id] ?? [], dependencies: dependencies)
                }
                return LineSwapResult(
                    baseSerial: baseSerial, lines: lines, stations: input.stations,
                    state: advanced.state, memo: nextMemo, chainKeys: chainKeys, inputs: inputs)
            }

            private func swapInput(
                lines: [RailNetworkStore.DrawnLine], stations: [RailNetworkStore.DrawnStation]
            ) -> LineSwapInput {
                LineSwapInput(
                    lines: lines, stations: stations, state: junctionState,
                    memo: junctionLineMemo, joinedChains: networkGeometry.joinedChains)
            }

            /// Records the newest line set and starts the worker when none runs.
            private func stageLineSwap(
                lines: [RailNetworkStore.DrawnLine], stations: [RailNetworkStore.DrawnStation]
            ) {
                pendingLineSwap = (lines, stations)
                if case .start(let base) = lineSwapSchedule.stage() { startLineSwap(baseSerial: base) }
            }

            private func startLineSwap(baseSerial: Int) {
                guard let pending = pendingLineSwap else { return }
                // Admit the arriving lines' chains before the worker joins them,
                // or the constrained cache would drop each join it just made.
                networkGeometry.admitDisplayChains(Set(pending.lines.map(JoinedChainKey.init)))
                let input = swapInput(lines: pending.lines, stations: pending.stations)
                let worker = Task.detached(priority: .userInitiated) {
                    Self.computeLineSwap(input, baseSerial: baseSerial, checksCancellation: true)
                }
                lineSwapTask = Task { @MainActor [weak self] in
                    let result = await withTaskCancellationHandler {
                        await worker.value
                    } onCancel: { worker.cancel() }
                    self?.landLineSwap(result)
                }
            }

            /// The worker finished (nil: it was cancelled, by a synchronous
            /// install or a tear-down, so its result is stale either way).
            private func landLineSwap(_ result: LineSwapResult?) {
                guard let result else {
                    if case .start(let base) = lineSwapSchedule.abandoned() { startLineSwap(baseSerial: base) }
                    return
                }
                switch lineSwapSchedule.landed(baseSerial: result.baseSerial, duringGesture: isManipulating) {
                case .apply: applyLineSwap(result)
                case .hold:
                    heldLineSwap = result
                    // Applied by the settle rebuild; a gesture that never moves
                    // the camera would otherwise leave it held for good.
                    rebuildDeferredByGesture = true
                case .discard(let restart):
                    if case .start(let base) = restart { startLineSwap(baseSerial: base) }
                }
            }

            /// Installs a held result once the gesture has ended.
            private func applyHeldLineSwap() {
                guard lineSwapSchedule.releaseHeld(), let held = heldLineSwap else { return }
                heldLineSwap = nil
                applyLineSwap(held)
            }

            /// Installs a landed line set: one main-actor turn, no `await`.
            private func applyLineSwap(_ result: LineSwapResult) {
                let swapInterval = RailSignpost.map.begin("map.lineSwap.apply")
                defer { RailSignpost.map.end("map.lineSwap.apply", swapInterval) }
                let linesChanged = Self.changed(result.lines, from: lines, id: \.contentID)
                let stationsChanged = Self.changed(result.stations, from: stations, id: \.contentID)
                installLineSwap(result, cancelsPreparation: false)
                if case .start(let base) = lineSwapSchedule.applied() {
                    startLineSwap(baseSerial: base)
                } else {
                    pendingLineSwap = nil
                }
                requestStrokeReferences()
                guard let mapView else { return }
                let changes = MapDrawChanges(
                    linesChanged: linesChanged, stationsChanged: stationsChanged,
                    ridesChanged: false, selectionChanged: false, visibilityChanged: false,
                    indexesChanged: false, displayChanged: false, routePaintOnly: false,
                    dateChanged: false, networkFilterChanged: false, namingChanged: false,
                    showsNetwork: showsNetwork, hasRides: !rides.isEmpty,
                    hasContinuousLines: lines.contains(where: \.continuous))
                if case .rebuild = changes.plan {
                    rebuildOwed(on: mapView, lineDataOnly: true)
                }
            }

            /// Assigns a computed line set and revalidates what depends on it.
            /// Residency loads and evictions change `lines` all the time while
            /// zooming; only a changed temporal era makes an in-flight
            /// preparation wrong (`cancelsPreparation`). Otherwise its landing
            /// keeps the lines whose inputs still match.
            private func installLineSwap(_ result: LineSwapResult, cancelsPreparation: Bool) {
                lines = result.lines
                stations = result.stations
                interaction.replaceStations(result.stations)
                junctionState = result.state
                junctionLineMemo = result.memo
                // A chain's own `anchors` come off `stations`' slots, and the
                // display-datum chains `prepareStrokeReferences()` reads (and
                // every `strokeRef(for:of:)` answer keyed on them) are built
                // from `lines` alone: both are stale the moment either moves.
                linesGeneration += 1
                networkGeometry.retainDisplayChains(result.chainKeys)
                invalidateNetworkTemporalGeometry(cancelsPreparation: cancelsPreparation)
                refreshLineInputs(newTruth: result.inputs)
            }

            /// Revalidate only the inputs a line build actually reads. A
            /// country arriving must not discard every other country's pixels.
            /// `newTruth` is the inputs each line would be built from now (from
            /// the worker); without it the stored truth is refreshed, which is
            /// what the settle after a gesture needs to release held joints.
            private func refreshLineInputs(newTruth: [String: LineInputs]? = nil) {
                let refreshInterval = RailSignpost.map.begin("map.refreshLineInputs")
                defer { RailSignpost.map.end("map.refreshLineInputs", refreshInterval) }
                // A neighbour prebuild captured the old inputs; its builds would
                // land as present-but-stale in the neighbour entry.
                cancelNeighbourPrebuild()
                var next = newTruth ?? trueLineInputs
                // Stable joints: a line's stroke depends on which junction
                // neighbours are loaded, so a later wave must not move a line
                // that is already drawn. While the fingers are down, a drawn
                // line keeps its stored stroke (and the inputs it was built
                // from); it refreshes once the camera settles.
                var trueGenerations = lineInputGenerations
                for (id, inputs) in next where trueLineInputs[id] != inputs {
                    trueGenerations[id] = (trueGenerations[id] ?? 0) + 1
                }
                trueGenerations = trueGenerations.filter { next[$0.key] != nil }
                trueLineInputs = next
                lineInputGenerations = trueGenerations
                strokeStability.resolve(current: trueGenerations, moving: isManipulating)
                let frameKey = currentGeometryFrame?.key
                let heldIDs = strokeStability.held(current: trueGenerations).filter { id in
                    frameKey.map { networkGeometry.hasLineBuild(for: id, in: $0) } == true
                        && lineInputs[id] != nil
                }
                for id in heldIDs { next[id] = lineInputs[id] }
                heldJointLineIDs = heldIDs
                let retainedIDs = Set(next.keys.filter { next[$0] == lineInputs[$0] })
                networkGeometry.retainLineBuilds(withIDs: retainedIDs)
                resetRideStrokeCaches()
                lineInputs = next
                interaction.invalidateRideGeometry()
            }

            /// This frame's continuous-stroke chains, in the display datum — the
            /// geometry `RailCore.StrokeRide.resolve(segment:chains:)` matches a
            /// ride's own segment against. See ``strokeRef(for:of:)``.
            ///
            /// One entry per continuous `DrawnLine`. The joined coordinates and
            /// measures come from ``JoinedChainCache`` (one join per content id
            /// and chain id), which is the display network's own split — the
            /// same one the pixel build in `rebuild` projects — not the compact
            /// package's `RouteNetwork.Line.parts`, which a prior version of this
            /// wrongly matched against. Memoised on ``linesGeneration``, not
            /// rebuilt every frame: unlike the pixel geometry in
            /// the frame-stroke cache, none of this depends on zoom.
            /// Joining, indexing and matching operate on immutable snapshots.
            /// A newer line generation cancels the old worker; only its own
            /// revision may publish, including when a removed journey reused an ID.
            /// Called only through ``requestStrokeReferences()``.
            private func prepareStrokeReferences(signature: Int) {
                matchingTask?.cancel()
                // Results published but not yet installed are still valid
                // per-ride cache entries: each is keyed on its own geometry
                // and line generation, which the worker re-checks.
                let cached = pendingStrokeRefs.map { pending in
                    strokeRefCache.merging(pending.refs) { _, new in new }
                } ?? strokeRefCache
                pendingStrokeRefs = nil
                matchingRevision += 1
                let revision = matchingRevision
                let generation = linesGeneration
                let lines = self.lines
                let stations = self.stations
                let rides = self.rides
                let inputs = lineInputs
                let now = ContinuousClock.now
                matchingInFlight = (signature, generation)
                matchingRerunOwed = false
                matchingBurst = (now, matchingBurst?.lastRequest ?? now)
#if DEBUG
                MapRenderProbe.matchingRuns += 1
#endif
                // The last published index, of any generation: the same
                // generation is reused as is, an older one is updated in place.
                let priorIndex: @Sendable () async -> (generation: Int, index: StrokeRide.Index)? = { [weak self] in
                    await MainActor.run {
                        guard let self, self.mapView != nil, self.linesGeneration == generation else { return nil }
                        return self.preparedStrokeIndex
                    }
                }
                let publishIndex: @Sendable (StrokeRide.Index) async -> Void = { [weak self] index in
                    await MainActor.run {
                        guard let self, self.mapView != nil, self.linesGeneration == generation else { return }
                        self.preparedStrokeIndex = (generation, index)
                    }
                }
                let limiter = matchingWorkLimiter
                let joinedChains = networkGeometry.joinedChains
                let worker = Task.detached(priority: .userInitiated) {
                    try await limiter.withPermit {
                        // The matching itself, off the main thread.
                        let workInterval = RailSignpost.map.begin("map.matching.work")
                        defer { RailSignpost.map.end("map.matching.work", workInterval) }
                        let index: StrokeRide.Index
                        // What moved since the prior index; nil when there is
                        // no prior index to compare against.
                        let change: StrokeRide.Index.Change?
                        let prior = await priorIndex()
                        if let prior, prior.generation == generation {
                            index = prior.index
                            change = nil
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
                                let chain = joinedChains.chain(of: line)
                                chains.append(ChainRef(id: line.id, points: chain.points,
                                    measures: chain.measures, anchors: anchors[line.id] ?? [],
                                    contentKey: line.contentID.uuidString))
                            }
                            // A chunk arrival adds or drops a few chains; the
                            // prepared entries of every other chain are kept.
                            // Answers equal a full `Index(chains:)` rebuild.
                            if let prior {
                                let updated = prior.index.updated(chains: chains)
                                index = updated.index
                                change = updated.change
                            } else {
                                index = StrokeRide.Index(chains: chains)
                                change = nil
                            }
                            // Salvage a completed index through ride-only cancellation.
                            // Network/anchor changes and dismantled maps reject it.
                            await publishIndex(index)
                        }
                        try Task.checkCancellation()
                        var results: [String: (geometryKey: String, linesGeneration: Int, refs: [String: StrokeRef])] = [:]
                        for ride in rides {
                            try Task.checkCancellation()
                            let key = "\(ride.id):\(ride.geometryDigest)"
                            if let entry = cached[ride.id], entry.geometryKey == key {
                                if entry.linesGeneration == generation {
                                    results[ride.id] = entry
                                    continue
                                }
                                // Matched against the prior index, and no
                                // added, removed or altered chain can hold
                                // any of its segments: the answers stand.
                                if let change, let prior, entry.linesGeneration == prior.generation,
                                   !ride.segments.contains(where: { change.affects(segment: $0.coordinates) }) {
                                    results[ride.id] = (key, generation, entry.refs)
                                    continue
                                }
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
                }
                matchingTask = Task { [weak self] in
                    // `map.matching` is the time spent WAITING for the worker
                    // (`map.matching.work`), not main-thread work; the main
                    // thread only pays the snapshot above and `map.matching.apply`.
                    let matchingInterval = RailSignpost.map.begin("map.matching")
                    let result = await withTaskCancellationHandler {
                        try? await worker.value
                    } onCancel: { worker.cancel() }
                    let completed = !Task.isCancelled && result != nil
                    RailSignpost.map.end("map.matching", matchingInterval)
                    RailSignpost.map.mark("map.matching.completed", completed ? 1 : 0)
                    guard !Task.isCancelled, let self, self.matchingRevision == revision else { return }
                    let applyInterval = RailSignpost.map.begin("map.matching.apply")
                    defer { RailSignpost.map.end("map.matching.apply", applyInterval) }
                    self.matchingInFlight = nil
                    guard let (_, results) = result else {
                        self.runOwedStrokeMatching()
                        // Ride segments whose fallback waited for this match
                        // are drawn by a rebuild once nothing is pending.
                        if !self.strokeMatchingPending, let map = self.mapView {
                            self.networkBuildState.invalidateZoomBucket()
                            self.noteRebuildTrigger(.strokeMatching)
                            self.rebuild(on: map)
                        }
                        return
                    }
                    self.matchedSignature = signature
                    self.pendingStrokeRefs = (revision, results, inputs)
                    if self.playback?.isActive == true, self.playbackLayer.lastSnapshot != nil {
                        self.rebuildDeferredByPlayback = true
                    } else if self.isManipulating {
                        self.rebuildDeferredByGesture = true
                    } else if let map = self.mapView {
                        if !self.applyMatchesIncrementally(on: map) {
                            self.noteRebuildTrigger(.strokeMatching)
                            self.rebuild(on: map)
                        }
                    }
                    self.runOwedStrokeMatching()
                }
            }

            /// Installs a finished match for only the rides whose matches moved
            /// and re-forms their batches, instead of a full rebuild. Answers
            /// `false`, with nothing installed and the zoom bucket cleared, when
            /// the full rebuild must run (`RideArrivalPlan`): the match changed
            /// what the network layer reads, or the last build cannot answer.
            private func applyMatchesIncrementally(on mapView: MKMapView) -> Bool {
                guard let pending = pendingStrokeRefs, pending.revision == matchingRevision,
                    pending.inputs == matchedLineInputs, playback?.isActive != true,
                    markerBuildContext != nil, rideBatchCache != nil
                else {
                    networkBuildState.invalidateZoomBucket()
                    return false
                }
                let changed = Set(rides.compactMap { ride in
                    strokeMatchUnchanged(strokeRefCache[ride.id], pending.refs[ride.id])
                        ? nil : ride.id
                })
                let action = RideArrivalPlan.decide(.init(
                    mapReady: mapView.bounds.width > 1, incrementalBaseCurrent: true,
                    changedRideCount: changed.count, matchesPending: true))
                if action == .nothing {
                    pendingStrokeRefs = nil
                    strokeRefCache = pending.refs
                    return true
                }
                let previousRefs = strokeRefCache
                let previousInputs = matchedLineInputs
                pendingStrokeRefs = nil
                strokeRefCache = pending.refs
                matchedLineInputs = pending.inputs
                retainRidePolylines(excludingStrokeFor: changed)
                interaction.invalidateRideGeometry()
                stationLabels.invalidateGeometry(forRides: changed)
                if updateRides(.init(changed: changed, orderChanged: false, ambiguous: false),
                               on: mapView) {
                    return true
                }
                // Roll back so the full rebuild installs the same results itself.
                strokeRefCache = previousRefs
                matchedLineInputs = previousInputs
                pendingStrokeRefs = pending
                networkBuildState.invalidateZoomBucket()
                return false
            }

            /// What one matching run depends on: the line/station generation
            /// and the ordered `(id, geometryDigest)` of every ride. Equal
            /// signatures produce identical results, so a repeat is skipped.
            private func strokeMatchingSignature() -> Int {
                var hasher = Hasher()
                hasher.combine(linesGeneration)
                hasher.combine(rides.count)
                for ride in rides {
                    hasher.combine(ride.id)
                    hasher.combine(ride.geometryDigest)
                }
                return hasher.finalize()
            }

            /// The single entry point for ride matching, coalescing every
            /// `ridesChanged`/`linesChanged`/`stationsChanged` request.
            ///
            /// - An input equal to the running or last matched one is skipped.
            /// - The first request after a quiet period starts at once.
            /// - Requests inside ``MatchingSchedule/burstWindow`` of the previous
            ///   one (a route load's 750 ms partial publishes, regions
            ///   streaming in) wait for ``MatchingSchedule/debounce`` of quiet,
            ///   bounded by ``MatchingSchedule/maxWait`` since the last run
            ///   started. A load's final publish starts at once.
            /// - At most one worker runs: a same-generation worker is left to
            ///   finish and one rerun is owed; a worker on stale lines is
            ///   cancelled by its replacement and its permit drains first.
            private func requestStrokeReferences() {
                let signature = strokeMatchingSignature()
                if signature == (matchingInFlight?.signature ?? matchedSignature) {
                    matchingDebounceTask?.cancel()
                    matchingDebounceTask = nil
                    matchingRerunOwed = false
#if DEBUG
                    MapRenderProbe.matchingSkipped += 1
#endif
                    return
                }
                let now = ContinuousClock.now
                matchingDebounceTask?.cancel()
                matchingDebounceTask = nil
                func seconds(_ duration: Duration) -> Double {
                    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                }
                let start = MatchingSchedule.decide(
                    sinceLastRequest: matchingBurst.map { seconds(now - $0.lastRequest) },
                    sinceBurstStart: matchingBurst.map { seconds(now - $0.lastStart) },
                    loadJustFinished: ridesLoadJustFinished)
                guard case .after(let delaySeconds) = start, let burst = matchingBurst else {
                    matchingBurst = (matchingBurst?.lastStart ?? now, now)
                    startStrokeMatching(signature: signature)
                    return
                }
                matchingBurst = (burst.lastStart, now)
                let delay = Duration.seconds(delaySeconds)
#if DEBUG
                MapRenderProbe.matchingDeferred += 1
#endif
                matchingDebounceTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    guard let self, !Task.isCancelled else { return }
                    self.matchingDebounceTask = nil
                    self.startStrokeMatching(signature: self.strokeMatchingSignature())
                }
            }

            private func startStrokeMatching(signature: Int) {
                guard signature != (matchingInFlight?.signature ?? matchedSignature) else { return }
                if let inFlight = matchingInFlight, inFlight.generation == linesGeneration {
                    // Same lines: its index and most rides are still right.
                    // Let it publish, then match whatever is current.
                    matchingRerunOwed = true
                    return
                }
                prepareStrokeReferences(signature: signature)
            }

            private func runOwedStrokeMatching() {
                guard matchingRerunOwed, matchingInFlight == nil else { return }
                matchingRerunOwed = false
                startStrokeMatching(signature: strokeMatchingSignature())
            }

            /// `NetworkLOD.select` for the current lines, memoised on its exact
            /// inputs. `prepareNetworkGeometry` and the `rebuild` that installs
            /// its result ask the same question in one pass and again when the
            /// worker returns; only a new line generation, visibility zoom or
            /// build rect pays the filter.
            private func networkSelection(
                zoom: Double, buildRect: MKMapRect
            ) -> (lines: [RailNetworkStore.DrawnLine], culledOffScreen: Int) {
                if let memo = networkSelectionMemo, memo.generation == linesGeneration,
                   memo.zoom == zoom, MKMapRectEqualToRect(memo.buildRect, buildRect) {
                    return memo.result
                }
                let result = NetworkLOD.select(from: lines, zoom: zoom, buildRect: buildRect)
                networkSelectionMemo = (linesGeneration, zoom, buildRect, result)
                return result
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
                else {
                    guard let mapView, segment.coordinates.count >= 2 else { return nil }
                    // Return the fallback as built ink too: the overlay's
                    // caller must not decimate these new curves afterwards.
                    // Prefer the installed bucket so this curve matches the
                    // geometry the network was built at.
                    let mapPointsPerScreenPoint = currentGeometryFrame?.mapPointsPerScreenPoint
                        ?? MapProjection.mapPointsPerScreenPoint(of: mapView)
                    let fallbackScale = currentGeometryFrame?.scale
                        ?? RailStyle.scale(atZoom: MapProjection.zoomLevel(of: mapView))
                    return parallelLaneCoordinates(
                        segment.coordinates.map(\.clLocation), lane: 0,
                        mapPointsPerScreenPoint: mapPointsPerScreenPoint,
                        scale: fallbackScale)
                }
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
                riddenStops: [Stop]
            ) -> Bool {
                // `RiddenCategoryVisibility.draws` returns true at once when no
                // category is hidden; skip building its key and arguments then.
                guard layers.categories.anyHidden else { return true }
                let isRidden = ride.stopInterval(forSectionIndex: segment.segmentIndex).map {
                    Statistics.isRideSegment(riddenStops, segmentIndex: $0)
                } ?? false
                return categoryVisibility.draws(
                    key: "\(ride.id)#\(segment.segmentIndex).\(segment.partIndex)",
                    isRidden: isRidden, sourceCoordinates: segment.sourceCoordinates,
                    sectionSourceLines: ride.segments.filter { $0.segmentIndex == segment.segmentIndex }
                        .map(\.sourceCoordinates),
                    from: segment.from, to: segment.to, country: ride.country,
                    index: categoryIndexes[ride.country], filter: layers.categories)
            }

            /// How near two same-named labels have to be to be one place.
            ///
            /// Shared with RailCore's station-name election and the ride
            /// station-importance policy so they agree about one place.
            static let labelMergeMeters = StationDisplay.labelMergeMeters

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
            private func endpointSpecs(
                strokeAnchors: [String: [Int: CLLocationCoordinate2D]]
            ) -> [MapEndpointLabels.Spec] {
                var specs: [MapEndpointLabels.Spec] = []
                var seen: Set<String> = []
                func add(_ spec: MapEndpointLabels.Spec?) {
                    guard let spec, seen.insert(spec.key).inserted else { return }
                    specs.append(spec)
                }
                if let ride = rides.first(where: { $0.id == selectedTrainID }) {
                    // A highlighted railway has no journey endpoints.
                    guard ride.visible, !RailwayLinePreview.isPreviewRide(ride.id) else { return [] }
                    add(endpointSpec(for: ride, kind: .origin, strokeAnchors: strokeAnchors))
                    add(endpointSpec(for: ride, kind: .destination, strokeAnchors: strokeAnchors))
                    return specs
                }
                if dateScope.isActive, let pair = scopedEndpointRides() {
                    add(endpointSpec(for: pair.first, kind: .origin, strokeAnchors: strokeAnchors))
                    add(endpointSpec(for: pair.last, kind: .destination, strokeAnchors: strokeAnchors))
                }
                return specs
            }

            private struct StationPlaceKey: Hashable {
                var region: String
                var stationCode: String
            }

            private struct RideSegmentPartKey: Hashable {
                var segmentIndex: Int
                var partIndex: Int
            }

            private struct RideSegmentEndpointKey: Hashable {
                var rideID: String
                var segmentIndex: Int
                var partIndex: Int
            }

            private struct DisplayedStationCoordinateCache {
                var segmentsByRide: [String: [RideSegmentPartKey: RiddenRouteStore.DrawnSegment]] = [:]
                var endpoints: [RideSegmentEndpointKey: (
                    first: CLLocationCoordinate2D?, last: CLLocationCoordinate2D?
                )] = [:]
            }

            private func displayedStationCoordinate(
                at position: Coordinate, anchor: MapRideMarkers.StrokeAnchorRef?,
                ride: RiddenRouteStore.DrawnRide?,
                strokeAnchors: [String: [Int: CLLocationCoordinate2D]]
            ) -> CLLocationCoordinate2D {
                var cache = DisplayedStationCoordinateCache()
                return displayedStationCoordinate(
                    at: position, anchor: anchor, ride: ride,
                    strokeAnchors: strokeAnchors, cache: &cache)
            }

            private func displayedStationCoordinate(
                at position: Coordinate, anchor: MapRideMarkers.StrokeAnchorRef?,
                ride: RiddenRouteStore.DrawnRide?,
                strokeAnchors: [String: [Int: CLLocationCoordinate2D]],
                cache: inout DisplayedStationCoordinateCache
            ) -> CLLocationCoordinate2D {
                guard let anchor else { return position.clLocation }
                if let vertex = anchor.vertexIndex,
                   let point = strokeAnchors[anchor.chainID]?[vertex] { return point }
                guard let ride else { return position.clLocation }
                let endpointKey = RideSegmentEndpointKey(
                    rideID: ride.id, segmentIndex: anchor.segmentIndex,
                    partIndex: anchor.partIndex)
                if let endpoints = cache.endpoints[endpointKey] {
                    return (anchor.isSegmentStart ? endpoints.first : endpoints.last)
                        ?? position.clLocation
                }
                if cache.segmentsByRide[ride.id] == nil {
                    cache.segmentsByRide[ride.id] = Dictionary(
                        ride.segments.map {
                            (RideSegmentPartKey(
                                segmentIndex: $0.segmentIndex, partIndex: $0.partIndex), $0)
                        },
                        uniquingKeysWith: { first, _ in first })
                }
                let segmentKey = RideSegmentPartKey(
                    segmentIndex: anchor.segmentIndex, partIndex: anchor.partIndex)
                guard let segment = cache.segmentsByRide[ride.id]?[segmentKey] else {
                    return position.clLocation
                }
                let coordinates = drawnCoordinates(of: segment, ride: ride)
                let endpoints = (first: coordinates.first, last: coordinates.last)
                cache.endpoints[endpointKey] = endpoints
                return (anchor.isSegmentStart ? endpoints.first : endpoints.last)
                    ?? position.clLocation
            }

            /// `buildEndpointLabelSpec`, with the four pieces resolved.
            private func endpointSpec(
                for ride: RiddenRouteStore.DrawnRide,
                kind: MapEndpointLabels.Kind,
                strokeAnchors: [String: [Int: CLLocationCoordinate2D]]
            ) -> MapEndpointLabels.Spec? {
                guard let endpoint = MapEndpointLabels.endpointStop(of: ride, kind: kind,
                    stationPosition: { knownEndpointPosition(for: $0, of: ride) })
                else { return nil }
                let anchors = MapRideMarkers.stopStrokeAnchors(of: ride) {
                    strokeRef(for: $0, of: ride)
                }
                var position = displayedStationCoordinate(
                    at: endpoint.position, anchor: anchors[endpoint.index], ride: ride,
                    strokeAnchors: strokeAnchors)
                // A fully resolved route may have no explicit stop records.
                // Its fallback endpoint still follows the displayed segment.
                if anchors[endpoint.index] == nil,
                   MapRideMarkers.stopPositions(of: ride)[endpoint.index] == nil,
                   ride.route.isResolved {
                    let ordered = ride.segments.sorted { $0.segmentIndex < $1.segmentIndex }
                    if let segment = (kind == .origin ? ordered.first : ordered.last) {
                        let coordinates = drawnCoordinates(of: segment, ride: ride)
                        position = (kind == .origin ? coordinates.first : coordinates.last) ?? position
                    }
                }
                let named = localized(
                    endpoint.stop.name, code: endpoint.stop.n02StationCode,
                    region: Region(rawValue: ride.country), stationID: endpoint.stop.stationID,
                    lookupByName: false)
                // No usable registry identity: none recorded, or one the
                // registry cannot name.
                let unresolved = endpoint.stop.stationID?.isEmpty != false
                    || RegistryStationDisplay.resolve(
                        storedName: endpoint.stop.name, stationID: endpoint.stop.stationID,
                        region: Region(rawValue: ride.country)?.code).unresolved
                // An origin shows when the ride LEFT and a destination when it
                // arrived — never both, because a card that showed both would
                // be describing the timetable rather than the journey's end.
                let clock = kind == .origin ? endpoint.stop.departure : endpoint.stop.arrival
                let tag = kind == .origin ? naming.departureTag : naming.arrivalTag
                let time = (clock?.isEmpty == false) ? "\(tag) \(clock!)" : ""
                let badge = kind == .origin ? naming.startTag : naming.endTag
                return MapEndpointLabels.spec(
                    trainID: ride.id, kind: kind,
                    at: Coordinate(lon: position.longitude, lat: position.latitude),
                    name: unresolved ? endpoint.stop.name : named.display,
                    rawName: endpoint.stop.name,
                    badge: badge, time: time,
                    // A stop with no registry id keeps its stored name and
                    // shows no readings: the identity state belongs to the
                    // trip card, not under a station the map placed.
                    readings: unresolved ? [] : named.readings.map(\.text))
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
                MapEndpointLabels.layout(
                    &specs, at: points, containerWidth: mapView.bounds.width)
                for index in specs.indices {
                    // Placement is all `layout` touches;
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

            // MARK: - taps

            /// What a tap measured under the finger, beyond what the policy
            /// needs: the objects an answer opens.
            private struct TapMeasurement {
                var hits: MapTapHits
                /// The trip dot under the finger, mounted or drawn in the overlay.
                var dot: RideStationAnnotation?
                /// The annotation under the finger that is not a trip dot.
                var annotation: (any MKAnnotation)?
                /// The station annotation within reach, for ``MapTapAnswer/station``.
                var stationAnnotation: (any MKAnnotation)?
                /// Network lines within reach, nearest first.
                var lines: [RailNetworkStore.DrawnLine] = []
            }

            @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
                guard recognizer.state == .ended, let mapView else { return }
                answerTap(at: recognizer.location(in: mapView), on: mapView)
            }

            /// Measures what is under the finger, asks ``MapTapPolicy`` and
            /// performs its answer. Every priority decision is the policy's; this
            /// only measures and acts. An empty-map clear is banked for
            /// ``handleSettledTap(_:)``, which delivers it after the double-tap
            /// window.
            @discardableResult
            func answerTap(
                at point: CGPoint, on mapView: MKMapView, tapCount: Int = 1
            ) -> (answer: MapTapAnswer, hits: MapTapHits) {
                bankedTap = nil
                annotationUnderTap = nil
                // Playback owns the map; picking a note's place only pans.
                guard !(playback?.isActive == true && playbackLayer.lastSnapshot != nil),
                      controller?.tripNotePickTrainID == nil
                else { return (.ignore, MapTapHits(tapCount: tapCount)) }
                let interval = RailSignpost.map.begin("map.tap")
                defer { RailSignpost.map.end("map.tap", interval) }
                let measured = measureTap(at: point, on: mapView, tapCount: tapCount)
                let answer = MapTapPolicy.answer(measured.hits)
                switch answer {
                case .annotation:
                    // A network bead answers at once like every other hit; notes,
                    // badges and draft pins answer through `mapView(_:didSelect:)`,
                    // which this touch has not claimed.
                    if let annotation = measured.annotation as? StationAnnotation,
                       let card = stationCard(for: annotation) {
                        answerOrBank(.station, .station(card))
                    } else {
                        annotationUnderTap = measured.annotation
                    }
                case .ignore:
                    break
                case .stationCard:
                    if let dot = measured.dot, let card = stationCard(for: dot) {
                        answerOrBank(answer, .station(card))
                    }
                case .station:
                    if let annotation = measured.stationAnnotation, let card = stationCard(for: annotation) {
                        answerOrBank(answer, .station(card))
                    }
                case .pickTrip(let id):
                    interaction.claimTouch()
                    onSelectRide([id])
                case .tripChooser(let ids):
                    interaction.claimTouch()
                    onSelectRide(ids)
                case .lineCard, .lineChooser:
                    answerOrBank(answer, .lines(measured.lines))
                case .clearWhenSettled:
                    bankedTap = .clear
                }
                return (answer, measured.hits)
            }

            /// Answers a station or line hit at once, or banks it for
            /// `handleSettledTap` when `MapTapPolicy.defersAnswer` says a double
            /// tap over the open panel card must only zoom. The touch is claimed
            /// either way: this tap has been answered, so MapKit must not too.
            private func answerOrBank(_ answer: MapTapAnswer, _ tap: BankedTap) {
                interaction.claimTouch()
                if MapTapPolicy.defersAnswer(answer, cardHost: controller?.mapCardHost) {
                    bankedTap = tap
                } else {
                    deliver(tap)
                }
            }

            private func deliver(_ tap: BankedTap) {
                switch tap {
                case .clear: onSelectRide([])
                case .station(let card): onSelectStation(card)
                case .lines(let lines): onSelectLines(lines)
                }
            }

            /// Delivers the answer `answerTap` banked, once `doubleTap` has failed.
            @objc func handleSettledTap(_ recognizer: UITapGestureRecognizer) {
                guard recognizer.state == .ended, let tap = bankedTap else { return }
                bankedTap = nil
                deliver(tap)
            }

            private func measureTap(at point: CGPoint, on mapView: MKMapView, tapCount: Int) -> TapMeasurement {
                var measured = TapMeasurement(hits: MapTapHits(tapCount: tapCount))
                var view = mapView.hitTest(point, with: nil)
                var annotationView: MKAnnotationView?
                while let current = view {
                    if let found = current as? MKAnnotationView { annotationView = found; break }
                    view = current.superview
                }
                if let annotationView {
                    if let dot = annotationView.annotation as? RideStationAnnotation {
                        measured.dot = dot
                    } else {
                        measured.hits.annotationViewUnderFinger = true
                        measured.annotation = annotationView.annotation
                    }
                } else if layers.routes {
                    measured.dot = tappedOverlayRideDot(at: point, on: mapView)
                }
                // 列車経路 off takes the rides' hit area with their ink: no trip
                // dot and no trip line can have been meant.
                var dotOwnsTap = false
                if layers.routes, let dot = measured.dot {
                    if dot.rideID == selectedTrainID {
                        measured.hits.selectedTripStationDot = true
                    } else {
                        // A dot under the finger is its own trip's, whatever
                        // other trips pass that station: no line reach added.
                        measured.hits.tripIDsInReach = [dot.rideID]
                        dotOwnsTap = true
                    }
                }
                if !measured.hits.annotationViewUnderFinger, !measured.hits.selectedTripStationDot, !dotOwnsTap {
                    if layers.routes {
                        measured.hits.tripIDsInReach += interaction.rideHits(
                            at: point, on: mapView, rides: rides, drawnStrokes: drawnStrokes)
                    }
                    if measured.hits.tripIDsInReach.isEmpty {
                        measured.stationAnnotation = stationAnnotation(at: point, on: mapView)
                        measured.hits.stationAnnotationInReach = measured.stationAnnotation != nil
                        if measured.stationAnnotation == nil {
                            measured.lines = networkLines(at: point, on: mapView)
                            measured.hits.networkLineIDsInReach = measured.lines.map(\.lineID)
                        }
                    }
                }
                return measured
            }

            /// The nearest station annotation within ``MapTapPolicy/stationReach``:
            /// a mounted network bead or a dot of the selected trip, or one of its
            /// dots drawn in the overlay. MapKit selects from further out than a
            /// view's own target, so this answers the same touch at once.
            private func stationAnnotation(at point: CGPoint, on mapView: MKMapView) -> (any MKAnnotation)? {
                var best: (annotation: any MKAnnotation, distance: CGFloat)?
                func consider(_ annotation: any MKAnnotation, at centre: CGPoint) {
                    let distance = hypot(centre.x - point.x, centre.y - point.y)
                    guard distance <= CGFloat(MapTapPolicy.stationReach),
                          distance < (best?.distance ?? .infinity)
                    else { return }
                    best = (annotation, distance)
                }
                for view in displayedAnnotationViews.allObjects where view.window != nil {
                    // A bead nobody can see (faded, hidden by collision
                    // handling, or not touchable) answers nothing.
                    guard !view.isHidden, view.alpha >= 0.01, view.isUserInteractionEnabled,
                          let annotation = view.annotation else { continue }
                    let eligible = annotation is StationAnnotation
                        || (annotation as? RideStationAnnotation)?.rideID == selectedTrainID
                    guard eligible else { continue }
                    // The bead's own point, not `view.center`: `centerOffset` puts the
                    // centre in the middle of a named bead's label.
                    consider(annotation, at: mapView.convert(annotation.coordinate, toPointTo: mapView))
                }
                for dot in overlayRideDots where dot.rideID == selectedTrainID {
                    consider(dot, at: mapView.convert(dot.coordinate, toPointTo: mapView))
                }
                return best?.annotation
            }

            /// Network lines within ``MapTapPolicy/networkLineReach`` over the
            /// line builds the last rebuild drew. Nothing is answered for a
            /// pitched camera, where one view-point reach has no single scale.
            private func networkLines(at point: CGPoint, on mapView: MKMapView) -> [RailNetworkStore.DrawnLine] {
                guard showsNetwork, !drawnLineBuilds.isEmpty else { return [] }
                // A pitched camera has no single scale; use the one at the tap.
                let scale: Double
                if let uniform = RideTapIndex.mapPointsPerViewPoint(on: mapView) {
                    scale = uniform
                } else {
                    let a = MKMapPoint(mapView.convert(point, toCoordinateFrom: mapView))
                    let b = MKMapPoint(mapView.convert(
                        CGPoint(x: point.x + 10, y: point.y), toCoordinateFrom: mapView))
                    let local = hypot(b.x - a.x, b.y - a.y) / 10
                    guard local.isFinite, local > 0 else { return [] }
                    scale = local
                }
                let interval = RailSignpost.map.begin("map.tap.lines")
                defer { RailSignpost.map.end("map.tap.lines", interval) }
                let tap = MKMapPoint(mapView.convert(point, toCoordinateFrom: mapView))
                let ids = NetworkLineHitTest.lineIDs(
                    at: tap, reach: MapTapPolicy.networkLineReach * scale, in: drawnLineBuilds,
                    extra: drawnExtraPolylines)
                var byLineID: [String: RailNetworkStore.DrawnLine] = [:]
                for build in drawnLineBuilds where byLineID[build.line.lineID] == nil {
                    byLineID[build.line.lineID] = build.line
                }
                return ids.compactMap { byLineID[$0] }
            }

            /// A double tap zooms. One that lands on exactly one trip also
            /// selects it (`MapTapPolicy.doubleTapAnswer`); the selection comes
            /// first so that stopping the auto-fit afterwards holds.
            @objc func handleMapDoubleTap(_ recognizer: UITapGestureRecognizer) {
                guard recognizer.state == .ended, let mapView else { return }
                answerDoubleTap(at: recognizer.location(in: mapView), on: mapView)
            }

            /// The double tap's answer, shared with the `tapMap` command. It
            /// first cancels the station or line answer the first tap banked, so
            /// a double tap over a panel card only zooms.
            func answerDoubleTap(at point: CGPoint, on mapView: MKMapView) {
                bankedTap = nil
                if layers.routes, controller?.tripNotePickTrainID == nil,
                   !(playback?.isActive == true && playbackLayer.lastSnapshot != nil) {
                    let measured = measureTap(at: point, on: mapView, tapCount: 2)
                    if case .selectTripAndZoom(let id) = MapTapPolicy.doubleTapAnswer(measured.hits),
                       id != selectedTrainID {
                        interaction.claimTouch()
                        onSelectRide([id])
                    }
                }
                controller?.readerBeganManipulating()
            }

#if DEBUG
            /// The `tapMap` command: the same answer a tap gives, with a banked
            /// clear delivered at once. It does not exercise the recognisers.
            func answerTapForUITest(
                at point: CGPoint, on mapView: MKMapView, doubleTap: Bool = false
            ) -> MapTapTestReport {
                interaction.beginTouch()
                let outcome = answerTap(at: point, on: mapView)
                // No real touch reaches MapKit here: select what it would have. MapKit
                // selects only after its own double-tap recogniser fails, so a double
                // tap selects nothing.
                if !doubleTap, outcome.answer == .annotation, let annotation = annotationUnderTap {
                    self.mapView(mapView, didSelect: annotation)
                }
                var report = MapTapTestReport(answer: outcome.answer, hits: outcome.hits)
                if doubleTap {
                    // The second tap inside the window: cancels what the first banked.
                    report.cancelledByDoubleTap = bankedTap != nil
                    answerDoubleTap(at: point, on: mapView)
                } else if let tap = bankedTap {
                    bankedTap = nil
                    deliver(tap)
                }
                return report
            }
#endif

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

            /// The camera is moving the zoom right now: a gesture is down, or
            /// the last zoom change is fresher than ``ZoomTravel/travellingWindow``
            /// (momentum, wheel, animated moves). Travel preparation and the
            /// during-motion install are gated on this, not on recognisers.
            private var cameraTravelling: Bool {
                isManipulating || zoomTravel.isTravelling(at: Self.seconds(.now))
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
                    // A tap-then-drag zoom is not a tap: drop a banked clear.
                    bankedTap = nil
#if DEBUG
                    diagnostics.gestureBegan()
#endif
                    // The reader has the camera. Said once, and never taken
                    // back: what reads it is the app's own opening move
                    // (`RailMapController.frameAtLaunch`), which is owed only
                    // while nobody has touched the map — and the rides it
                    // waits for can land mid-pinch.
                    controller?.readerBeganManipulating()
                    // A preparation for the level the camera still wants keeps
                    // running; only one for a level it has left stops.
                    if GeometryPreparationGate.cancelsOnTouchDown(
                        inFlightLevel: geometryPreparationLevel,
                        zoom: mapView.map { MapProjection.zoomLevel(of: $0) } ?? 0,
                        installedLevel: installedGeometryLevel) {
                        // The cancelled job exits without rebuilding; a touch
                        // that never moves the camera must still owe one.
                        if geometryPreparation != nil { rebuildDeferredByGesture = true }
                        cancelGeometryPreparation()
                    }
                case .ended, .cancelled, .failed:
#if DEBUG
                    if !isManipulating {
                        diagnostics.gestureEnded()
                        if let mapView { diagnostics.updateLiveStatus(on: mapView, camera: mapView.camera, builtRect: networkBuildState.builtRect) }
                    }
#endif
                    if !isManipulating, let mapView {
                        restartLabelSettleTask(on: mapView)
                    }
                    guard !isManipulating, rebuildDeferredByGesture, let mapView else { return }
                    rebuildDeferredByGesture = false
                    scheduleCameraRebuild(on: mapView)
                default:
                    break
                }
            }

            func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
                for view in views {
                    displayedAnnotationViews.add(view)
                    if let dot = view as? RideStationAnnotationView {
                        dot.applyStacking()
                        if (dot.annotation as? RideStationAnnotation)?.selected == true {
                            raisedAnnotationViews.add(dot)
                        } else {
                            raisedAnnotationViews.remove(dot)
                        }
                    } else if let label = view as? RideLabelAnnotationView {
                        label.applyStacking()
                        raisedAnnotationViews.add(label)
                    } else if let endpoint = view as? EndpointLabelView {
                        endpoint.applyStacking()
                        raisedAnnotationViews.add(endpoint)
                    }
                }
                annotationReconciler.didAdd(views)
                // MapKit finishes its initial ordering after this callback.
                DispatchQueue.main.async { [weak self] in
                    self?.restoreRideMarkerStacking()
                }
            }

            private func restoreRideMarkerStacking() {
#if DEBUG
                let stackingStarted = ContinuousClock.now
                defer {
                    diagnostics.didRestoreRideMarkerStacking(
                        milliseconds: (ContinuousClock.now - stackingStarted).milliseconds)
                }
#endif
                for view in raisedAnnotationViews.allObjects where view.window != nil {
                    switch view {
                    case let dot as RideStationAnnotationView: dot.applyStacking()
                    case let label as RideLabelAnnotationView: label.applyStacking()
                    case let endpoint as EndpointLabelView: endpoint.applyStacking()
                    default: break
                    }
                }
            }

            /// Which touches the tap recognisers receive: the first tap of a sequence
            /// only (`MapTapPolicy.receives`), wherever it lands. A touch on an
            /// annotation view is measured like any other and the policy answers
            /// `.annotation`, which `mapView(_:didSelect:)` carries out; one that
            /// the tap answered itself is claimed there so it is not answered twice.
            /// `EndpointLabelView` turns interaction off, so a touch on one is a
            /// touch on the map.
            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
            ) -> Bool {
                // The second tap of a double tap is never a tap. The
                // manipulation sensors want every touch that moves the map, and
                // a pinch very often starts with a finger on a station bead.
                if gestureRecognizer === tapRecognizer || gestureRecognizer === settledTapRecognizer {
                    guard MapTapPolicy.receives(tapCount: touch.tapCount) else { return false }
                }
                if gestureRecognizer === tapRecognizer {
                    // A new touch has been given no answer yet, whichever of
                    // the two answers it ends up getting (`mapView(_:didSelect:)`).
                    interaction.beginTouch()
                    bankedTap = nil
                }
                return true
            }

            /// What every stroke on this map is drawn with. See
            /// ``MapOverlayStyles`` for the full-scale-token contract the four
            /// writers — network, rides, playback — share through it.
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
            private let raisedAnnotationViews = NSHashTable<MKAnnotationView>.weakObjects()
            private let stationOverlayRenderers = NSHashTable<RideStationOverlayRenderer>.weakObjects()

            /// What a new pick answered in place built.
            private struct RebatchedSelection {
                var cores: [MKMultiPolyline]
                var casings: [MKMultiPolyline]
                var batchOverlays: [MKOverlay]
                var previousStandaloneID: String?
            }

            private func newPickRouteIsCached() -> Bool {
                guard layers.routes, playback?.isActive != true, playbackLayer.lastSnapshot == nil,
                      let id = selectedTrainID, let ride = rides.first(where: { $0.id == id })
                else { return false }
                return routeAvailableInFrame(ride)
            }

            /// The batch cache is the one the installed frame drew, with every
            /// input the same but the selection (which a pick changes).
            private func batchCacheIsCurrent(context: MarkerBuildContext, on mapView: MKMapView) -> Bool {
                // A stroke build still pending means the network geometry has begun
                // a frame that is not the installed one yet.
                guard rideStrokePreparation == nil,
                      let cache = rideBatchCache, let frame = currentGeometryFrame,
                      cache.stamp.frameKey == frame.key else { return false }
                let hasSelection = rides.contains { $0.id == selectedTrainID }
                var expected = rideBatchStamp(
                    frameKey: frame.key, hasSelection: hasSelection,
                    dark: mapView.traitCollection.userInterfaceStyle == .dark)
                expected.selectedTrainID = cache.stamp.selectedTrainID
                expected.hasSelection = cache.stamp.hasSelection
                return cache.stamp == expected
            }

            /// Moves the new selection out of its batch and the previous
            /// standalone ride back into one, then builds the new ride's cores
            /// and casings. After it the standalone ride's cores hold every
            /// drawable segment and it is in no batch; every other drawn ride is
            /// in exactly one. nil, with nothing changed, when the cache is gone.
            private func rebatchForNewSelection(
                context: MarkerBuildContext, dark: Bool, reconciliation: MapOverlayReconciliation,
                on mapView: MKMapView
            ) -> RebatchedSelection? {
                guard var cache = rideBatchCache, let frame = currentGeometryFrame,
                      let selectedID = selectedTrainID,
                      let ride = rides.first(where: { $0.id == selectedID }) else { return nil }
                let scope = dateScope
                let mapPointsPerScreenPoint = frame.mapPointsPerScreenPoint
                let rideBuildRect = installedTripRect
                let hasSelection = true
                var affectedCells: Set<Int> = []
                if let old = cache.entries.removeValue(forKey: selectedID) { affectedCells.insert(old.cell) }
                batchedRidePartCounts.removeValue(forKey: selectedID)
                let previousID = fullyBuiltSelectedRideID
                if let previousID, previousID != selectedID,
                   let previous = rides.first(where: { $0.id == previousID }), layers.routes {
                    let (solid, crossDay, unproven, _) = ridePolylines(
                        of: previous, rideBuildRect: rideBuildRect,
                        mapPointsPerScreenPoint: mapPointsPerScreenPoint, scope: scope)
                    if !solid.isEmpty || !crossDay.isEmpty || !unproven.isEmpty {
                        let entry = RideOverlayBatching.entry(
                            for: previous, scope: scope, solid: solid, crossDay: crossDay, unproven: unproven)
                        cache.entries[previousID] = entry
                        affectedCells.insert(entry.cell)
                        batchedRidePartCounts[previousID] = solid.count + crossDay.count + unproven.count
                    }
                }
                cache.batches = RideOverlayBatching.replan(
                    previous: cache.batches, entries: rides.compactMap { cache.entries[$0.id] },
                    affectedCells: affectedCells, selectedRideID: selectedID)
                cache.stamp = rideBatchStamp(
                    frameKey: frame.key, hasSelection: hasSelection, dark: dark)
                rideBatchCache = cache

                let (solid, crossDay, unproven, _) = ridePolylines(
                    of: ride, rideBuildRect: rideBuildRect,
                    mapPointsPerScreenPoint: mapPointsPerScreenPoint, scope: scope)
                var cores: [MKMultiPolyline] = []
                var casings: [MKMultiPolyline] = []
                appendSelectedRideOverlays(
                    of: ride, solid: solid, crossDay: crossDay, unproven: unproven, dark: dark,
                    hasSelection: hasSelection, reconciliation: reconciliation,
                    cores: &cores, casings: &casings)
                fullyBuiltSelectedRideID = selectedID
                return RebatchedSelection(
                    cores: cores, casings: casings,
                    batchOverlays: rideBatchOverlays(
                        cache.batches, hasSelection: hasSelection, reconciliation: reconciliation),
                    previousStandaloneID: previousID == selectedID ? nil : previousID)
            }

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
            /// ``MarkerBuildContext`` when its complete route is installed.
            /// A new selection first rebuilds to include offscreen segments.
            /// Folding every selection
            /// into the full rebuild cost 150–460 ms on device over Japan
            /// (see the long comment in ``rebuildOwed(on:)``); this answers
            /// from state the last rebuild already cached.
            ///
            /// A NEW pick is answered here too when its whole route is already
            /// cached in the installed frame (``SelectionApplyPlan``): its
            /// cores and casings are built from the cache, the previous
            /// standalone ride returns to its batch, and the batches of the
            /// two cells are re-formed. A route that reaches outside the
            /// built rect still takes the full rebuild.
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
                let isNewPick = selectedTrainID != nil && selectedTrainID != fullyBuiltSelectedRideID
                let plan = SelectionApplyPlan.decide(
                    selected: selectedTrainID, standalone: fullyBuiltSelectedRideID,
                    routeAvailableInFrame: isNewPick && newPickRouteIsCached(),
                    batchCacheCurrent: isNewPick && batchCacheIsCurrent(context: context, on: mapView),
                    contextValid: true)
                guard case .selectionOnly(let rebatch) = plan else { return false }
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

                updateRidePaint(on: mapView, animated: true)

                let overlaysInterval = RailSignpost.map.begin("map.selection.overlays")
                let dark = mapView.traitCollection.userInterfaceStyle == .dark
                let reconciliation = overlayInstaller.reconciliation(on: mapView)
                let installed = reconciliation.oldOverlays
                var others: [MKOverlay] = []
                var casings: [MKMultiPolyline] = []
                var unselectedCores: [MKMultiPolyline] = []
                var selectedCores: [MKMultiPolyline] = []
                var playback: [MKOverlay] = []
                // A new pick: the ride's own overlays come from the cache, its
                // batch block is re-formed, and the previous standalone ride's
                // cores are dropped (it is in a batch again).
                var rebatched: RebatchedSelection?
                if rebatch {
                    guard let result = rebatchForNewSelection(
                        context: context, dark: dark, reconciliation: reconciliation, on: mapView)
                    else {
                        RailSignpost.map.end("map.selection.overlays", overlaysInterval)
                        return false
                    }
                    rebatched = result
                    selectedCores.append(contentsOf: result.cores)
                    casings.append(contentsOf: result.casings)
                }
                for overlay in installed {
                    guard let key = overlay.title ?? nil else { others.append(overlay); continue }
                    if rebatched != nil {
                        // The block is replaced wholesale; the ride that was
                        // standalone is in it now.
                        if MapOverlayStyles.isRideBatchKey(key) { continue }
                        if MapOverlayStyles.isRideCoreKey(key),
                           let separator = key.firstIndex(of: "|"),
                           String(key[key.index(after: separator)...]) == rebatched?.previousStandaloneID {
                            continue
                        }
                    }
                    if MapOverlayStyles.isRideCasingKey(key) {
                        // Retain the new selection's casing. Old casings stay
                        // mounted separately until their exit fade completes.
                        if let separator = key.firstIndex(of: "|"),
                            String(key[key.index(after: separator)...]) == selectedTrainID,
                            let multi = overlay as? MKMultiPolyline {
                            if var style = overlayStyles[key] {
                                style.alpha = 0.9
                                overlayStyles[key] = style
                                overlayStyles.animateOpacity(forKey: key, duration: highlightDuration)
                            }
                            if !casings.contains(where: { $0.title == key }) { casings.append(multi) }
                        }
                    } else if MapOverlayStyles.isRideCoreKey(key),
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
                // (`ride` / `ride-xday` / `ride-unproven`) — same style rule `rebuild` uses for
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
                            dashed: style.dashed,
                            historical: style.historical
                        )
                        overlayStyles.animateOpacity(
                            forKey: casingKey, duration: highlightDuration, fromAlpha: 0)
                        casings.append(casing)
                    }
                }

                // Other routes first, then the selected casing and core —
                // the same order as a full rebuild.
                let retired = retiringCasings(from: installed, on: mapView)
                let desired: [MKOverlay] = others + retired + (rebatched?.batchOverlays ?? [])
                    + unselectedCores + casings + selectedCores + playback
                // The build's own scale, as `rebuild` hands `install`: the
                // marks below are styled from the same context, and the two
                // halves must agree on the frame they are drawn.
                overlayInstaller.install(
                    desired, replacing: reconciliation, scale: context.scale, on: mapView)
                selectionNeedsHighlightTransition = false
                RailSignpost.map.end("map.selection.overlays", overlaysInterval)

                // `buildMarkers` re-adds `endpointAnnotations` unconditionally
                // without first removing the old ones — `rebuild` owes it
                // that teardown ahead of the marker phase (its own teardown
                // section, before calling `buildMarkers`), so this does too.
                let markersInterval = RailSignpost.map.begin("map.selection.markers")
                buildMarkers(context, on: mapView)
                RailSignpost.map.end("map.selection.markers", markersInterval)
#if DEBUG
                diagnostics.submittedSelection(selectedTrainID, date: selectedDate)
#endif
                return true
            }

            private var detailDuration: TimeInterval {
                playback?.isActive == true ? 0
                    : RailMotion.mapDetailDuration(reduceMotion: controller?.reduceMotion == true)
            }

            private var highlightDuration: TimeInterval {
                playback?.isActive == true ? 0
                    : RailMotion.mapHighlightDuration(reduceMotion: controller?.reduceMotion == true)
            }

            private var highlightExitDuration: TimeInterval {
                playback?.isActive == true ? 0
                    : RailMotion.mapHighlightExitDuration(reduceMotion: controller?.reduceMotion == true)
            }

            /// A casing exits where it entered. Retargeting the same key cancels
            /// its removal callback, so selecting it again keeps its current alpha.
            private func retiringCasings(from overlays: [MKOverlay], on mapView: MKMapView) -> [MKOverlay] {
                var retired: [MKOverlay] = []
                for overlay in overlays {
                    guard let key = overlay.title ?? nil,
                        MapOverlayStyles.isRideCasingKey(key),
                        let separator = key.firstIndex(of: "|"),
                        String(key[key.index(after: separator)...]) != selectedTrainID,
                        var style = overlayStyles[key], highlightExitDuration > 0 else { continue }
                    retired.append(overlay)
                    guard style.alpha != 0 else { continue }
                    style.alpha = 0
                    overlayStyles[key] = style
                    overlayStyles.animateOpacity(forKey: key, duration: highlightExitDuration) { [weak self, weak mapView] in
                        guard let self, let mapView, self.mapView === mapView,
                            self.overlayStyles[key]?.alpha == 0,
                            mapView.overlays.contains(where: { $0 === overlay }) else { return }
                        mapView.removeOverlay(overlay)
                        self.overlayStyles.forget([overlay])
                    }
                }
                return retired
            }

            private func updateRidePaint(on mapView: MKMapView, animated: Bool = false) {
                let byID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let hasSelection = selectedTrainID.flatMap { byID[$0] } != nil
                for overlay in mapView.overlays {
                    if let key = overlay.title ?? nil, key.hasPrefix("network"),
                       var style = overlayStyles[key] {
                        let baseAlpha: CGFloat = key.hasPrefix("network-withheld-casing|") ? 1
                            : (key.hasPrefix("network-withheld|") ? RailStyle.withheldOpacity
                                : RailStyle.networkOpacity)
                        style.alpha = baseAlpha * (hasSelection ? RailStyle.selectDim : 1)
                        overlayStyles[key] = style
                        continue
                    }
                    if let key = overlay.title ?? nil, MapOverlayStyles.isRideBatchKey(key),
                       var style = overlayStyles[key] {
                        // rides|<kind>|<in|off>|<#colour>|c<cell>
                        let parts = key.split(separator: "|")
                        let inScope = parts.count > 2 && parts[2] == "in"
                        style.widthToken = (RailStyle.riddenWidth * CGFloat(display.routeWidthScale))
                            * RailStyle.riddenWidthScale
                        style.alpha = hasSelection ? RailStyle.selectDim
                            : (inScope ? CGFloat(display.riddenOpacity) : dateScope.dimOpacity)
                        overlayStyles[key] = style
                        continue
                    }
                    guard let key = overlay.title ?? nil,
                        MapOverlayStyles.isRideCoreKey(key),
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
                    RailStyle.scale(atZoom: MapProjection.zoomLevel(of: mapView)), on: mapView),
                    alphaTransitionDuration: animated ? highlightDuration
                        : (playback?.isActive == true ? 0 : nil))
            }

            /// Whether the settled zoom sits in a stroke bucket the installed
            /// geometry was not built for — the next rebuild replaces every
            /// laned network overlay, so restyling them first is wasted tiles.
            private func strokeBucketPending(at zoom: Double) -> Bool {
                wantedGeometryLevel(at: zoom) != currentGeometryFrame?.bucket
                    && lines.contains(where: { $0.lane != 0 || $0.continuous })
            }

            /// `overlays: false` restyles marks and names only, leaving the
            /// network renderers for the rebuild that will replace them.
            @discardableResult
            private func restyle(on mapView: MKMapView, overlays: Bool = true) -> Int {
                let restyleInterval = RailSignpost.map.begin("map.restyle")
                defer { RailSignpost.map.end("map.restyle", restyleInterval) }
                // Keep MapKit's mounted paths and annotation layouts stable
                // under the fingers. Mutating every renderer's width/font
                // during a pinch triggers tessellation and collision work.
                // The camera quiet-period task applies the final style once.
                guard !isManipulating, mapView.bounds.width > 1 else { return 0 }
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
                let overlayScaleChanged = overlays
                    && (!styledOverlayScale.isFinite || scale != styledOverlayScale)
                guard scaleChanged || markZoomChanged || overlayScaleChanged else { return 0 }
                styledScale = scale
                styledMarkZoom = markZoom
                if overlayScaleChanged {
                    overlayStyles.rescale(to: scale)
                    styledOverlayScale = scale
                }
                for renderer in stationOverlayRenderers.allObjects {
                    renderer.applyScale(scale, zoom: markZoom)
                }
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
                var restyledViews = 0
                for view in displayedAnnotationViews.allObjects
                where view.window != nil && viewport.intersects(view.frame) {
                    switch view {
                    case let station as StationAnnotationView:
                        station.applyScale(scale, zoom: markZoom)
                        restyledViews += 1
                    case let dot as RideStationAnnotationView:
                        dot.applyScale(scale, zoom: markZoom)
                        restyledViews += 1
                    case let label as RideLabelAnnotationView:
                        label.applyScale(scale, zoom: markZoom)
                        restyledViews += 1
                    case let playback as PlaybackAnnotationView:
                        guard scaleChanged else { continue }
                        guard let annotation = playback.annotation as? PlaybackAnnotation else {
                            continue
                        }
                        playback.configure(annotation, scale: scale)
                        restyledViews += 1
                    default:
                        continue
                    }
                }
                return restyledViews
            }

            // MARK: - playback

            // The chase itself lives in `MapPlaybackLayer`. What stays here is
            // the one thing that is not about the trail: whether a rebuild the
            // trail was holding off may now run. See `rebuildDeferredByPlayback`.

            /// The route store started or finished resolving trips; see
            /// ``MapInteractionCoordinator/setRidesLoading(_:)``.
            func ridesLoadingChanged(_ loading: Bool) {
                interaction.setRidesLoading(loading)
                guard loading != ridesAreLoading else { return }
                ridesAreLoading = loading
                guard !loading else { return }
                // The load finished. The final publish arrives in the update
                // pass that follows this call, with the new rides, and starts
                // matching at once (`MatchingSchedule`); matching here would
                // run on the old ride set.
                ridesLoadJustFinished = true
            }

            func playbackStateChanged(on mapView: MKMapView) {
                playbackLayer.playbackStateChanged(on: mapView)
            }

            func renderPlayback(_ snapshot: PlaybackMapSnapshot?) {
                guard let mapView else { return }
                let releasedCamera = playbackLayer.render(snapshot, on: mapView)
                if snapshot != nil { restyle(on: mapView) }
                guard releasedCamera, rebuildDeferredByPlayback else { return }
                rebuildDeferredByPlayback = false
                noteRebuildTrigger(.playbackReleased)
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
            /// So a touch the tap has already answered (`answerTap` claims it for a
            /// trip, a chooser, a station card or a line) is not answered again
            /// here. A touch the tap left to the annotation (`.annotation`), or
            /// found nothing for, makes no claim — so those still open their card.
            func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
                if let draft = annotation as? DraftStopAnnotation {
                    mapView.deselectAnnotation(annotation, animated: false)
                    controller?.onDraftPin?(draft.occurrenceID)
                    return
                }
                // Picking a note's place: no mark, badge or station answers.
                if controller?.tripNotePickTrainID != nil {
                    mapView.deselectAnnotation(annotation, animated: false)
                    return
                }
                if let note = annotation as? TripNoteAnnotation {
                    mapView.deselectAnnotation(annotation, animated: false)
                    guard !interaction.suppressesStationSelection else { return }
                    controller?.onTripNote?(note.trainID, note.noteID)
                    return
                }
                if let badge = annotation as? TripNoteBadgeAnnotation {
                    mapView.deselectAnnotation(annotation, animated: false)
                    guard !interaction.suppressesStationSelection else { return }
                    onSelectRide([badge.rideID])
                    return
                }
                guard let card = stationCard(for: annotation) else { return }
                mapView.deselectAnnotation(annotation, animated: false)
                if interaction.suppressesStationSelection {
                    return
                }
                onSelectStation(card)
            }

            private func stationCard(for annotation: any MKAnnotation) -> StationCard? {
                interaction.stationCard(for: annotation, named: { [self] name, code in
                    let named = localized(name, code: code)
                    return (named.display, localization == nil ? nil : named.readings.map(\.text))
                }, unresolvedLabel: localization?.text(RegistryStationDisplay.unresolvedKey) ?? "unresolved")
            }

            /// The overlay-drawn trip dot a touch lands in, by the same reach a
            /// mounted dot view claimed (the larger of the minimum touch target
            /// and its drawn diameter). Runs on a tap only; nothing per frame.
            private func tappedOverlayRideDot(at point: CGPoint, on mapView: MKMapView) -> RideStationAnnotation? {
                guard !overlayRideDots.isEmpty else { return nil }
                let zoom = MapProjection.zoomLevel(of: mapView)
                let scale = RailStyle.scale(atZoom: zoom)
                let targets = overlayRideDots.map { dot -> DotHitTest.Dot in
                    let centre = mapView.convert(dot.coordinate, toPointTo: mapView)
                    let diameter = max(1, dot.drawnRadiusToken(atZoom: zoom) * 2 * scale)
                    return DotHitTest.Dot(
                        x: Double(centre.x), y: Double(centre.y),
                        reach: Double(max(RailStyle.minimumTouchTarget, diameter) / 2))
                }
                return DotHitTest.hit(x: Double(point.x), y: Double(point.y), among: targets)
                    .map { overlayRideDots[$0] }
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
                if let stations = overlay as? RideStationOverlay {
                    let renderer = RideStationOverlayRenderer(overlay: stations)
                    renderer.updateStations(duration: stations.transitionDuration)
                    renderer.applyScale(MapProjection.quantised(scale, on: mapView),
                        zoom: (MapProjection.zoomLevel(of: mapView) * 16).rounded() / 16)
                    stationOverlayRenderers.add(renderer)
                    return renderer
                }
                if let polyline = overlay as? MKPolyline {
                    return styled(MKPolylineRenderer(polyline: polyline),
                        title: polyline.title, scale: scale)
                }
                guard let multi = overlay as? MKMultiPolyline else {
                    return MKOverlayRenderer(overlay: overlay)
                }
                return styled(DrawReportingMultiPolylineRenderer(multiPolyline: multi),
                    title: multi.title, scale: scale)
            }

            /// Applies the stored overlay style for `title` to a path renderer.
            private func styled(_ renderer: MKOverlayPathRenderer, title: String?,
                                scale: CGFloat) -> MKOverlayRenderer {
                let key = title ?? ""
                let style = overlayStyles[key]
                renderer.strokeColor = (style?.color ?? .systemBlue)
                    .withAlphaComponent(style?.alpha ?? 1)
                renderer.lineWidth = MapOverlayStyles.drawnWidth(style, atScale: scale)
                // A round cap adds half a line width to each dash and eats
                // its gap, the same reason the web app's dashed layers
                // (`rn-segments-withheld-casing`, `train-routes-xday`, the
                // suspended layers) all set `line-cap: butt`.
                let patterned = style?.dashed == true || style?.historical == true
                renderer.lineCap = patterned ? .butt : .round
                renderer.lineJoin = .round
                renderer.lineDashPattern = MapOverlayStyles.dashPattern(style, atScale: scale)
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
                    annotationReconciler.prepare(view)
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
                    annotationReconciler.prepare(view)
                    return view
                }
                if let label = annotation as? RideLabelAnnotation {
                    let identifier = "ride-station-label"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? RideLabelAnnotationView
                        ?? RideLabelAnnotationView(annotation: label, reuseIdentifier: identifier)
                    view.annotation = label
                    view.configure(label, scale: scale, zoom: zoom)
                    annotationReconciler.prepare(view)
                    return view
                }
                if let draft = annotation as? DraftStopAnnotation {
                    let identifier = "draft-stop"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? DraftStopAnnotationView
                        ?? DraftStopAnnotationView(annotation: draft, reuseIdentifier: identifier)
                    view.annotation = draft
                    view.configure(draft)
                    annotationReconciler.prepare(view)
                    return view
                }
                if let note = annotation as? TripNoteAnnotation {
                    let identifier = "trip-note"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? TripNoteMarkerView
                        ?? TripNoteMarkerView(annotation: note, reuseIdentifier: identifier)
                    view.annotation = note
                    view.configure(note)
                    annotationReconciler.prepare(view)
                    return view
                }
                if let badge = annotation as? TripNoteBadgeAnnotation {
                    let identifier = "trip-note-badge"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? TripNoteBadgeView
                        ?? TripNoteBadgeView(annotation: badge, reuseIdentifier: identifier)
                    view.annotation = badge
                    view.configure(badge)
                    annotationReconciler.prepare(view)
                    return view
                }
                if let endpoint = annotation as? EndpointLabelAnnotation {
                    let identifier = "ride-endpoint-label"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        as? EndpointLabelView
                        ?? EndpointLabelView(annotation: endpoint, reuseIdentifier: identifier)
                    view.annotation = endpoint
                    view.configure(endpoint)
                    annotationReconciler.prepare(view)
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
