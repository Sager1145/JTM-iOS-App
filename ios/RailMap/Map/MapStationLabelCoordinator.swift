import Foundation
import MapKit
import RailCore
import RailPresentation

/// Owns station-name election caches and the lifetime/cadence of label passes.
/// Geometry identities come from the mounted scene; the label owner does not
/// maintain a second ride list or install annotations into another map.
@MainActor
final class MapStationLabelCoordinator {
    /// The deck's station records and a grid over their positions, so a pass
    /// reads only the records near the visible rect.
    struct Records {
        let drawn: [MapRideMarkers.Drawn]
        let grid: SpatialGrid

        /// Map-point cell edge: about one city view.
        static let gridCellSize = 262_144.0

        init(drawn: [MapRideMarkers.Drawn]) {
            self.drawn = drawn
            var xs: [Double] = []
            var ys: [Double] = []
            xs.reserveCapacity(drawn.count)
            ys.reserveCapacity(drawn.count)
            for item in drawn {
                let point = MKMapPoint(item.record.position.clLocation)
                xs.append(point.x)
                ys.append(point.y)
            }
            grid = SpatialGrid(cellSize: Self.gridCellSize, xs: xs, ys: ys)
        }
    }

    private var markerCache: (key: Int, settings: MapRideMarkers.Settings, records: Records)?
    /// Each ride's own records, so a deck change rebuilds only the rides that
    /// changed. Valid for one `settings` and one stroke generation: stroke
    /// references move with the network's lines and stations.
    private var rideRecordCache: (
        settings: MapRideMarkers.Settings, strokeGeneration: Int,
        rides: [String: (identity: Int, records: MapRideMarkers.RideRecords)]
    )?
    private var selectedCache: (
        rideID: String, key: String, settings: MapRideMarkers.Settings, keys: Set<String>,
        tiers: SelectedTripStationTiers.Ranking)?
    /// One timer per quiet period; each camera frame only moves its deadline.
    private let settleTimer = MapDeadlineTimer(delay: .milliseconds(32))
    private var lastPassStep = Double.nan
    private var lastPassAt: ContinuousClock.Instant?
    private var lastMovingPassCost = Duration.zero

    private static let zoomStep = 0.25
    private static let passMinInterval = Duration.milliseconds(100)
    private static let movingBudget = Duration.milliseconds(8)

    /// `geometryIdentity` names the whole deck and `rideIdentity` each ride;
    /// `strokeGeneration` is the network generation the stroke references
    /// were resolved against.
    func records(
        for rides: [RiddenRouteStore.DrawnRide], geometryIdentity: Int,
        rideIdentity: (RiddenRouteStore.DrawnRide) -> Int?, strokeGeneration: Int,
        settings: MapRideMarkers.Settings,
        strokeRef: (RiddenRouteStore.DrawnRide, RiddenRouteStore.DrawnSegment) -> StrokeRef?
    )
        -> Records
    {
        if let markerCache, markerCache.key == geometryIdentity, markerCache.settings == settings {
            return markerCache.records
        }
        // Ids name the cache entries, so a deck that repeats one is not cached.
        let unique = Set(rides.map(\.id)).count == rides.count
        var previous: [String: (identity: Int, records: MapRideMarkers.RideRecords)] = [:]
        if unique, let cache = rideRecordCache, cache.settings == settings,
           cache.strokeGeneration == strokeGeneration {
            previous = cache.rides
        }
        var next: [String: (identity: Int, records: MapRideMarkers.RideRecords)] = [:]
        let perRide = rides.map { ride -> MapRideMarkers.RideRecords in
            let identity = unique ? rideIdentity(ride) : nil
            if let identity, let cached = previous[ride.id], cached.identity == identity {
                next[ride.id] = cached
                return cached.records
            }
            let records = MapRideMarkers.rideRecords(of: ride, settings: settings, strokeRef: strokeRef)
            if let identity { next[ride.id] = (identity, records) }
            return records
        }
        rideRecordCache = (settings, strokeGeneration, next)
        let records = Records(drawn: MapRideMarkers.drawn(assembling: perRide))
        markerCache = (geometryIdentity, settings, records)
        return records
    }

    /// The selected ride's election has its own cache: using the all-ride cache
    /// would evict the network-wide election on every selection/rebuild pair.
    func namedRecordKeys(
        of ride: RiddenRouteStore.DrawnRide, geometryIdentity: String,
        settings: MapRideMarkers.Settings,
        strokeRef: (RiddenRouteStore.DrawnRide, RiddenRouteStore.DrawnSegment) -> StrokeRef?
    )
        -> Set<String>
    {
        selected(ride, geometryIdentity: geometryIdentity, settings: settings, strokeRef: strokeRef).keys
    }

    /// The selected trip's station ranking (`SelectedTripStationTiers`),
    /// built once per trip geometry: a zoom or a pan only reads it.
    func selectedTripTiers(
        of ride: RiddenRouteStore.DrawnRide, geometryIdentity: String,
        settings: MapRideMarkers.Settings,
        strokeRef: (RiddenRouteStore.DrawnRide, RiddenRouteStore.DrawnSegment) -> StrokeRef?
    ) -> SelectedTripStationTiers.Ranking {
        selected(ride, geometryIdentity: geometryIdentity, settings: settings, strokeRef: strokeRef).tiers
    }

    private func selected(
        _ ride: RiddenRouteStore.DrawnRide, geometryIdentity: String,
        settings: MapRideMarkers.Settings,
        strokeRef: (RiddenRouteStore.DrawnRide, RiddenRouteStore.DrawnSegment) -> StrokeRef?
    ) -> (keys: Set<String>, tiers: SelectedTripStationTiers.Ranking) {
        // The geometry identity does not cover what a station's class reads
        // beyond its stop type: whether a pass was generated, and the
        // sections' line names.
        let key = geometryIdentity + "|" + String(MapRideMarkers.tierClassDigest(of: ride))
        if let selectedCache, selectedCache.rideID == ride.id, selectedCache.key == key,
            selectedCache.settings == settings
        {
            return (selectedCache.keys, selectedCache.tiers)
        }
        let interval = RailSignpost.map.begin("map.selectedTripTiers")
        defer { RailSignpost.map.end("map.selectedTripTiers", interval) }
        let drawn = MapRideMarkers.drawn(rides: [ride], settings: settings, strokeRef: strokeRef)
        var keys: Set<String> = []
        for item in drawn where !item.feature.name.isEmpty {
            keys.insert(Self.markerKey(item.record))
        }
        // A railway preview is not a trip: it keeps the zoom floors.
        let tiers = RailwayLinePreview.isPreviewRide(ride.id) ? .empty
            : SelectedTripStationTiers.rank(MapRideMarkers.tierStations(of: ride, drawn: drawn))
        selectedCache = (ride.id, key, settings, keys, tiers)
        return (keys, tiers)
    }

    /// Shared identity between the complete and selected elections. Role is
    /// omitted so the same named station matches when its dot role changes.
    nonisolated static func markerKey(_ record: StationDisplay.MarkerRecord) -> String {
        "\(record.position.lat)|\(record.position.lon)|\(record.name)"
    }

    /// Quarter-zoom cadence and a measured work budget keep inertial camera
    /// callbacks from repeating costly label election in the same frame.
    func runMovingPass(at zoom: Double, perform: () -> Bool) {
        let step = (zoom / Self.zoomStep).rounded(.down) * Self.zoomStep
        guard step != lastPassStep,
            lastPassAt.map({ ContinuousClock.now - $0 >= Self.passMinInterval }) ?? true,
            lastMovingPassCost <= Self.movingBudget,
            perform()
        else { return }
        lastPassStep = step
        lastPassAt = .now
    }

    /// Measure only election/install work, after the coordinator checks whether
    /// its current geometry and playback state permit a moving label pass.
    func measureMovingPass(_ perform: () -> Void) {
        let started = ContinuousClock.now
        perform()
        lastMovingPassCost = ContinuousClock.now - started
    }

    func resetMovingBudget() { lastMovingPassCost = .zero }

    /// Restarted by camera callbacks and gesture release, independently of the
    /// full geometry rebuild's 120 ms debounce. The callback checks live scene
    /// state when it runs; a stale captured geometry snapshot is never applied.
    func scheduleSettledPass(_ perform: @escaping @MainActor () -> Void) {
        settleTimer.schedule(perform)
    }

    private struct LabelWidthKey: Hashable {
        var text: String
        var pointSize: Double
    }
    private var labelWidths: [LabelWidthKey: CGFloat] = [:]

    /// The rounded-up width of `text` in `font` (the election's own
    /// measurement), remembered by (text, point size). Measuring with
    /// `NSString.size` was a large share of the station election on the main
    /// actor; the same names at the same size repeat on every pass.
    func labelWidth(of text: String, pointSize: CGFloat, font: UIFont) -> CGFloat {
        let key = LabelWidthKey(text: text, pointSize: Double(pointSize))
        if let known = labelWidths[key] { return known }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        if labelWidths.count > 8192 { labelWidths.removeAll(keepingCapacity: true) }
        labelWidths[key] = width
        return width
    }

    /// Display names changed (a different naming), so every measured width
    /// is for a text that may no longer be shown.
    func invalidateLabelWidths() { labelWidths.removeAll() }

    /// Drops everything: a different network, or teardown.
    func invalidateGeometry() {
        markerCache = nil
        rideRecordCache = nil
        selectedCache = nil
    }

    /// A stroke install moved only `rideIDs`' stroke references: only those
    /// rides' records are stale. The assembled deck is rebuilt from the other
    /// rides' cached records.
    func invalidateGeometry(forRides rideIDs: Set<String>) {
        guard !rideIDs.isEmpty else { return }
        markerCache = nil
        if let cache = rideRecordCache {
            rideRecordCache = (
                cache.settings, cache.strokeGeneration,
                cache.rides.filter { !rideIDs.contains($0.key) })
        }
        if let selected = selectedCache, rideIDs.contains(selected.rideID) {
            selectedCache = nil
        }
    }

    func tearDown() {
        settleTimer.cancel()
        invalidateLabelWidths()
        invalidateGeometry()
    }
}
