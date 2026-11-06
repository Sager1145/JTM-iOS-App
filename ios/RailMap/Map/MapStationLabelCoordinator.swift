import Foundation
import RailCore

/// Owns station-name election caches and the lifetime/cadence of label passes.
/// Geometry identities come from the mounted scene; the label owner does not
/// maintain a second ride list or install annotations into another map.
@MainActor
final class MapStationLabelCoordinator {
    private var markerCache: (key: Int, settings: MapRideMarkers.Settings, drawn: [MapRideMarkers.Drawn])?
    /// Each ride's own records, so a deck change rebuilds only the rides that
    /// changed. Valid for one `settings` and one stroke generation: stroke
    /// references move with the network's lines and stations.
    private var rideRecordCache: (
        settings: MapRideMarkers.Settings, strokeGeneration: Int,
        rides: [String: (identity: Int, records: MapRideMarkers.RideRecords)]
    )?
    private var selectedNameCache: (key: String, settings: MapRideMarkers.Settings, keys: Set<String>)?
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
        -> [MapRideMarkers.Drawn]
    {
        if let markerCache, markerCache.key == geometryIdentity, markerCache.settings == settings {
            return markerCache.drawn
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
        let drawn = MapRideMarkers.drawn(assembling: perRide)
        markerCache = (geometryIdentity, settings, drawn)
        return drawn
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
        if let selectedNameCache, selectedNameCache.key == geometryIdentity,
            selectedNameCache.settings == settings
        {
            return selectedNameCache.keys
        }
        var keys: Set<String> = []
        for item in MapRideMarkers.drawn(rides: [ride], settings: settings, strokeRef: strokeRef)
        where !item.feature.name.isEmpty {
            keys.insert(Self.markerKey(item.record))
        }
        selectedNameCache = (geometryIdentity, settings, keys)
        return keys
    }

    /// Shared identity between the complete and selected elections. Role is
    /// omitted so the same named station matches when its dot role changes.
    static func markerKey(_ record: StationDisplay.MarkerRecord) -> String {
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

    func invalidateGeometry() {
        markerCache = nil
        rideRecordCache = nil
        selectedNameCache = nil
    }

    func tearDown() {
        settleTimer.cancel()
        invalidateGeometry()
    }
}
