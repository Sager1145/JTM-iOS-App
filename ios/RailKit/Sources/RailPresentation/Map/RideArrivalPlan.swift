import Foundation

/// What an arrival of rides (a partial route publication, a finished load, a
/// finished stroke match) requires of the map. The coordinator computes the
/// scalar facts; this decides, so the rule is testable without a map view.
///
/// The cheapest correct answer wins: nothing when nothing changed, an
/// incremental ride add when the last build can answer, a worker line build
/// for just the new rides when only their lines are missing, and a full
/// rebuild only when something the incremental path cannot supply is absent.
public struct RideArrivalPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Nothing drawn changes.
        case nothing
        /// The map has no size yet; the first layout builds everything.
        case deferUntilMapReady
        /// Add or re-form only the changed rides' batches.
        case incrementalAdd
        /// Build the changed rides' missing lines on the worker, then add
        /// them incrementally. Never a full network rebuild.
        case prepareLinesThenIncrementalAdd
        case fullRebuild
    }

    public struct Facts: Equatable, Sendable {
        public var mapReady: Bool
        /// A previous build exists and every input it was drawn for (frame,
        /// rect, scope, layers, network generation, camera) is still current.
        public var incrementalBaseCurrent: Bool
        public var changedRideCount: Int
        /// The id sequence or duplicates make per-ride diffs unreliable.
        public var changeAmbiguous: Bool
        /// A changed ride needs a network chain the frame has not built.
        public var changedRidesNeedNetworkChain: Bool
        /// A changed ride needs a ride line the frame has not cached.
        public var changedRidesMissingLines: Bool
        public var selectionChanged: Bool
        /// A stroke match finished and its results wait to be installed.
        public var matchesPending: Bool
        /// The finished match changed what the network layer reads.
        public var matchedNetworkInputsChanged: Bool

        public init(
            mapReady: Bool, incrementalBaseCurrent: Bool, changedRideCount: Int,
            changeAmbiguous: Bool = false, changedRidesNeedNetworkChain: Bool = false,
            changedRidesMissingLines: Bool = false, selectionChanged: Bool = false,
            matchesPending: Bool = false, matchedNetworkInputsChanged: Bool = false
        ) {
            self.mapReady = mapReady
            self.incrementalBaseCurrent = incrementalBaseCurrent
            self.changedRideCount = changedRideCount
            self.changeAmbiguous = changeAmbiguous
            self.changedRidesNeedNetworkChain = changedRidesNeedNetworkChain
            self.changedRidesMissingLines = changedRidesMissingLines
            self.selectionChanged = selectionChanged
            self.matchesPending = matchesPending
            self.matchedNetworkInputsChanged = matchedNetworkInputsChanged
        }
    }

    public static func decide(_ facts: Facts) -> Action {
        guard facts.mapReady else {
            return facts.changedRideCount > 0 || facts.matchesPending ? .deferUntilMapReady : .nothing
        }
        // A load that completes with nothing new owes nothing.
        guard facts.changedRideCount > 0 || facts.matchesPending || facts.changeAmbiguous
            || facts.selectionChanged else { return .nothing }
        if facts.selectionChanged || facts.changeAmbiguous || facts.matchedNetworkInputsChanged
            || !facts.incrementalBaseCurrent || facts.changedRidesNeedNetworkChain {
            return .fullRebuild
        }
        return facts.changedRidesMissingLines ? .prepareLinesThenIncrementalAdd : .incrementalAdd
    }
}
