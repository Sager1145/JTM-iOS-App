import RailCore

/// Physical proof and historical availability for one immutable planner snapshot.
/// The caller decides whether this snapshot still matches its current inputs.
public enum TripRouteValidation {
    public struct Candidate: Sendable {
        public let id: String
        public let train: Train?

        public init(id: String, train: Train?) {
            self.id = id
            self.train = train
        }
    }

    public struct Result: Sendable, Equatable {
        public let retainedIDs: Set<String>
        public let physicallyResolvedIDs: Set<String>
    }

    public struct Availability: Sendable, Equatable {
        public let datedResolved: Bool
        public let undatedResolved: Bool

        public init(datedResolved: Bool, undatedResolved: Bool) {
            self.datedResolved = datedResolved
            self.undatedResolved = undatedResolved
        }
    }

    /// Unproven candidates remain available for saving as pending. A candidate
    /// is removed only when an undated route exists but its dated route does not.
    public static func validate(
        candidates: [Candidate],
        resolve: @Sendable ([Train]) async throws -> [Availability]
    ) async throws -> Result {
        try Task.checkCancellation()
        var retainedIDs = Set(candidates.map(\.id))
        var physicallyResolvedIDs: Set<String> = []
        var probes: [(id: String, train: Train)] = []
        for candidate in candidates {
            try Task.checkCancellation()
            guard var dated = candidate.train else { continue }
            // Pending drafts must be probed without the saved-ride solver's
            // pending guard. This local copy never changes the caller's draft.
            dated.routeConfirmation = .confirmed
            probes.append((candidate.id, dated))
        }
        if !probes.isEmpty {
            do {
                try Task.checkCancellation()
                // One ordered batch lets the platform resolver reuse its graph
                // for both dated and undated probes without writing routes.
                let availability = try await resolve(probes.map(\.train))
                try Task.checkCancellation()
                // A partial or oversized reply cannot establish positional
                // identity, so retain the entire snapshot without proof.
                if availability.count == probes.count {
                    for (probe, status) in zip(probes, availability) {
                        if status.datedResolved {
                            physicallyResolvedIDs.insert(probe.id)
                        } else if status.undatedResolved {
                            retainedIDs.remove(probe.id)
                        }
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An ordinary failure establishes neither proof nor closure.
                try Task.checkCancellation()
            }
        }
        try Task.checkCancellation()
        return Result(retainedIDs: retainedIDs, physicallyResolvedIDs: physicallyResolvedIDs)
    }
}
