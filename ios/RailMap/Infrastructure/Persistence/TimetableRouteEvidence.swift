import Foundation
import RailCore

/// The bundled Japanese timetable is an occurrence-evidence provider. It does
/// not replace recorded calls or validate geometry in the current rail network.
actor TimetableRouteEvidence {
    private static let shared = TimetableRouteEvidence()
    nonisolated private static let applied = AppliedEvidenceStore()
    nonisolated private static let resourceRevisions = Result { try loadRevisions() }

    private lazy var database: Result<TrainTimetableDatabase, TrainTimetableDatabase.OpenFailure> = {
        do { return .success(try TrainTimetableDatabase.bundled(country: "jp")) }
        catch let error as TrainTimetableDatabase.OpenFailure { return .failure(error) }
        catch { return .failure(.damaged(String(describing: error))) }
    }()
    private let dates = SharedRouteWork<String, TimetablePhysicalRouteMatch.CandidateIndex>(
        maxEntries: 6, maxCost: 5_000, cost: { max(1, $0.tripCount) })

    private struct CacheKey: Hashable {
        let identity: TimetablePhysicalRouteMatch.MatchRequestIdentity
        let railRevision: String
        let timetableRevision: String
    }

    private struct Cached {
        let outcome: TimetablePhysicalRouteMatch.Outcome
        var access: UInt64
    }

    private var matches: [CacheKey: Cached] = [:]
    private var access: UInt64 = 0

    /// Keeps an editor-applied occurrence only while the kept train and the
    /// current rail and timetable revisions still match. Missing revisions are
    /// not a license to reuse.
    nonisolated static func rememberAppliedOccurrence(
        trip: TrainTimetableDatabase.Trip, train: Train
    ) {
        guard case .success(let revisions) = resourceRevisions,
              let evidence = TimetablePhysicalRouteMatch.appliedEvidence(
                trip: trip, train: train, sections: train.routeSections ?? [],
                railRevision: revisions.rail, timetableRevision: revisions.timetable)
        else { return }
        applied.remember(evidence)
    }

    static func enrich(
        train: Train, country: String, sections: [RouteSection]
    ) async throws -> TimetablePhysicalRouteMatch.Match? {
        try await shared.match(train: train, country: country, sections: sections)
    }

    private func match(
        train: Train, country: String, sections: [RouteSection]
    ) async throws -> TimetablePhysicalRouteMatch.Match? {
        try Task.checkCancellation()
        guard country == "jp", TrainTimetableDatabase.accepts(train),
              !train.requiresRouteConfirmation, !sections.isEmpty,
              train.vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              train.stops.count >= 2,
              train.stops.allSatisfy({ $0.n02StationCode?.isEmpty == false }),
              let rideDate = train.date,
              case .valid(_, _, _, let canonicalDate) = EditorTime.parseDate(rideDate),
              canonicalDate == rideDate
        else { return nil }

        let identity = TimetablePhysicalRouteMatch.MatchRequestIdentity(
            train: train, sections: sections)
        let revisions = try Self.resourceRevisions.get()
        if let stored = Self.applied.lookup(identity) {
            if let match = TimetablePhysicalRouteMatch.reusableAppliedMatch(
                stored, train: train, sections: sections,
                railRevision: revisions.rail, timetableRevision: revisions.timetable) {
                return match
            }
            Self.applied.drop(identity)
        }
        let key = CacheKey(identity: identity, railRevision: revisions.rail,
                           timetableRevision: revisions.timetable)
        if let cached = cachedMatch(for: key) { return cached }
        if matches[key]?.outcome == .unavailable { return nil }
        let database: TrainTimetableDatabase
        switch self.database {
        case .success(let opened): database = opened
        case .failure(let error): throw error
        }

        var candidates: [TimetablePhysicalRouteMatch.CandidateIndex] = []
        for offset in 0...2 {
            try Task.checkCancellation()
            guard let serviceDate = Dates.addDays(rideDate, -offset),
                  case .valid(_, _, _, let canonical) = EditorTime.parseDate(serviceDate),
                  canonical == serviceDate else { return nil }
            let trips = try await dates.value(for: serviceDate) {
                try Task.checkCancellation()
                let trips = try database.trips(on: serviceDate)
                try Task.checkCancellation()
                return TimetablePhysicalRouteMatch.CandidateIndex(trips: trips)
            }
            candidates.append(trips)
        }
        try Task.checkCancellation()

        if let cached = cachedMatch(for: key) { return cached }
        if matches[key]?.outcome == .unavailable { return nil }
        let outcome = TimetablePhysicalRouteMatch.resolve(
            for: train, routeSections: sections, indexedBy: candidates)
        try Task.checkCancellation()
        switch outcome {
        case .matched(let match):
            retain(outcome, for: key)
            return match
        case .unavailable:
            retain(outcome, for: key)
            return nil
        case .ambiguous, .unsupported:
            return nil
        }
    }

    private func cachedMatch(for key: CacheKey) -> TimetablePhysicalRouteMatch.Match? {
        guard var cached = matches[key] else { return nil }
        access &+= 1
        cached.access = access
        matches[key] = cached
        if case .matched(let match) = cached.outcome { return match }
        return nil
    }

    private func retain(_ outcome: TimetablePhysicalRouteMatch.Outcome, for key: CacheKey) {
        if matches[key] == nil, matches.count >= 128,
           let oldest = matches.min(by: { $0.value.access < $1.value.access }) {
            matches.removeValue(forKey: oldest.key)
        }
        access &+= 1
        matches[key] = Cached(outcome: outcome, access: access)
    }

    private struct Revisions: Sendable {
        let rail: String
        let timetable: String
    }

    nonisolated private static func loadRevisions() throws -> Revisions {
        let decoded = try RailResourceRevisions.bundled()
        return Revisions(rail: try decoded.requiredRevision(for: "jp"),
                         timetable: decoded.timetableRevision)
    }
}

/// Synchronous so an editor apply is visible to the next route enrichment
/// without waiting on the evidence actor.
private final class AppliedEvidenceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [TimetablePhysicalRouteMatch.MatchRequestIdentity: TimetablePhysicalRouteMatch.AppliedOccurrenceEvidence] = [:]
    private var order: [TimetablePhysicalRouteMatch.MatchRequestIdentity] = []

    func remember(_ evidence: TimetablePhysicalRouteMatch.AppliedOccurrenceEvidence) {
        lock.lock()
        defer { lock.unlock() }
        let key = evidence.binding.identity
        if entries[key] == nil {
            while entries.count >= 32, let oldest = order.first {
                entries.removeValue(forKey: oldest)
                order.removeFirst()
            }
        }
        order.removeAll { $0 == key }
        order.append(key)
        entries[key] = evidence
    }

    func lookup(
        _ identity: TimetablePhysicalRouteMatch.MatchRequestIdentity
    ) -> TimetablePhysicalRouteMatch.AppliedOccurrenceEvidence? {
        lock.lock()
        defer { lock.unlock() }
        return entries[identity]
    }

    func drop(_ identity: TimetablePhysicalRouteMatch.MatchRequestIdentity) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: identity)
        order.removeAll { $0 == identity }
    }
}
