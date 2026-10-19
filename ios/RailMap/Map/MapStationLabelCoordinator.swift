import Foundation
import RailCore

/// Owns station-name election caches and the lifetime/cadence of label passes.
/// Geometry identities come from the mounted scene; the label owner does not
/// maintain a second ride list or install annotations into another map.
@MainActor
final class MapStationLabelCoordinator {
    private var markerCache: (key: Int, settings: MapRideMarkers.Settings, drawn: [MapRideMarkers.Drawn])?
    private var selectedNameCache: (key: String, settings: MapRideMarkers.Settings, keys: Set<String>)?
    private var settleTask: Task<Void, Never>?
    private var lastPassStep = Double.nan
    private var lastPassAt: ContinuousClock.Instant?
    private var lastMovingPassCost = Duration.zero

    private static let zoomStep = 0.25
    private static let passMinInterval = Duration.milliseconds(100)
    private static let movingBudget = Duration.milliseconds(8)

    func records(
        for rides: [RiddenRouteStore.DrawnRide], geometryIdentity: Int,
        settings: MapRideMarkers.Settings,
        strokeRef: (RiddenRouteStore.DrawnRide, RiddenRouteStore.DrawnSegment) -> StrokeRef?
    )
        -> [MapRideMarkers.Drawn]
    {
        if let markerCache, markerCache.key == geometryIdentity, markerCache.settings == settings {
            return markerCache.drawn
        }
        let drawn = MapRideMarkers.drawn(rides: rides, settings: settings, strokeRef: strokeRef)
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
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(32)) } catch { return }
            guard let self else { return }
            self.settleTask = nil
            perform()
        }
    }

    func invalidateGeometry() {
        markerCache = nil
        selectedNameCache = nil
    }

    func tearDown() {
        settleTask?.cancel()
        settleTask = nil
        invalidateGeometry()
    }
}
