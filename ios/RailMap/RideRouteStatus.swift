import Foundation
import Observation
import RailCore
import RailPresentation

// `RideRouteStatus` itself now lives in `RailPresentation`, next to the
// `JourneyRouteState` it bridges to and the `RouteLoadPhase` it reads.
// Deciding which of §5.5's five states a journey is in is a rule, and a
// rule stated in the app target is a rule nothing runs: this file has no
// test target under it. `RouteStatusResolver` is where those rules are
// asserted; what stays here is the observable storage they read.

/// What the editor and the journey detail need to know about the workspace
/// they were never handed.
///
/// ## Why this is a shared object rather than a parameter
///
/// `RiddenRouteStore` and `ItineraryStore` are created once, in `AppShell`,
/// and threaded down by hand. The journey detail is pushed by
/// `ContentView.navigationDestination` and the ride panel builds `RideCard`;
/// neither passes a route store, and both files belong to other ports running
/// in parallel — so a new initialiser argument on `RideDetailContent` cannot be
/// filled in without editing files this work does not own.
///
/// So the two stores publish into one main-actor `@Observable` object, and the
/// surfaces read it. Every consumer still accepts an explicit value first
/// (`RideDetailContent.routeStatus`), which is the seam to close once the
/// owning files can be touched: pass the status in, and this becomes the
/// fallback nobody reaches.
///
/// It holds no truth of its own. Every field is a projection of a store's
/// state, written by that store, and reset when the store resets.
@MainActor
@Observable
final class RideStatusCenter {
    static let shared = RideStatusCenter()

    /// `RiddenRouteStore.LoadState`, flattened — the same four cases
    /// `RailPresentation.RouteLoadPhase` names, which is now simply that type.
    typealias Phase = RouteLoadPhase

    /// One journey's solved route, as the store left it.
    typealias Entry = RouteStatusEntry

    private(set) var phase: Phase = .idle
    private(set) var entries: [String: Entry] = [:]
    /// Journeys with a solve in flight right now — a single-journey rebuild
    /// (§8.4), which the store-wide `phase` cannot express.
    private(set) var resolvingIDs: Set<String> = []
    /// Every id in the itinerary store. §8.3: an id edit must not silently
    /// overwrite another record, and the editor can only warn about a
    /// collision it can see.
    private(set) var trainIDs: Set<String> = []
    /// The live route store, for the one thing a status reader has to be able
    /// to ask for: solve this journey again. Weak, and ignored by observation
    /// — it is a wire, not state.
    @ObservationIgnored weak var routeStore: RiddenRouteStore?

    // MARK: - Reading

    /// §5.5's state for one journey. The rules are
    /// ``RouteStatusResolver/status(id:resolvingIDs:entries:phase:)``'s, and
    /// they are asserted there rather than here.
    func status(forTrainID id: String) -> RideRouteStatus {
        RouteStatusResolver.status(
            id: id, resolvingIDs: resolvingIDs, entries: entries, phase: phase)
    }

    // MARK: - Writing (stores only)

    func publish(phase: Phase) {
        self.phase = phase
        if phase == .loading { resolvingIDs.removeAll() }
    }

    func publish(entries: [String: Entry], phase: Phase) {
        self.entries = entries
        self.phase = phase
        resolvingIDs.removeAll()
    }

    func publish(trainIDs: Set<String>) {
        self.trainIDs = trainIDs
    }

    func beginResolving(_ id: String) { resolvingIDs.insert(id) }

    func finishResolving(_ id: String, entry: Entry?) {
        resolvingIDs.remove(id)
        if let entry {
            entries[id] = entry
        } else {
            entries.removeValue(forKey: id)
        }
    }

    func clear() {
        phase = .idle
        entries.removeAll()
        resolvingIDs.removeAll()
    }

    /// §8.4: solve one journey again and let the map update.
    ///
    /// Returns whether a solve actually started. It does not when the app is
    /// running without a route store under it (previews, tests), and the
    /// caller says "sections rebuilt" rather than "route rebuilt" in that
    /// case instead of claiming work that nobody is doing.
    @discardableResult
    func resolveAgain(_ train: Train) -> Bool {
        guard let routeStore else { return false }
        // Which package a rebuild solves against comes from the journey
        // itself — `Train.region` — rather than from a region the app is
        // switched to, because there is no longer such a thing.
        routeStore.resolve(train)
        return true
    }
}
