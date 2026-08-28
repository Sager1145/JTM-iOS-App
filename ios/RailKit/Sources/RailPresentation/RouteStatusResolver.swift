import Foundation

// What became of one journey's route, and how a surface should say so.
//
// §5.5 gives a journey five route states and §8.4 requires the interface to
// name the stretches that did not draw rather than to report that something,
// somewhere, failed. Deciding which of the five a journey is in is a small
// state machine over four inputs — is a solve in flight for this id, is there
// a recorded outcome for it, what is the store-wide load phase, and what did
// the solve actually produce — and every one of its rules is a claim that can
// be wrong in a way no screenshot shows.
//
// The machine used to live in `RideStatusCenter.status(forTrainID:)`, a method
// on a `@MainActor @Observable` app object, in the app target — which has no
// test target under it. So the rules below sat unasserted:
//
//   * a store-wide failure is NOT evidence that this journey has nothing to
//     draw, so it reports `unavailable` carrying the message, never `noRoute`
//     (§8.8);
//   * `expected == 0` is the store's spelling for "this journey asked for
//     nothing", which is `noRoute` and not an unavailable route;
//   * a journey nobody has reported on yet, while the store is loading, is
//     still being worked on rather than known to be empty.
//
// Three rules, three ways to silently degrade the interface into "something
// failed". They are arithmetic over enums, they need no view and no store
// underneath them, and `RouteLoadPhase` was already sitting in this module
// waiting for exactly this — its own documentation says that when the store
// grows a per-train state, "this enum is what changes".
//
// So the types the decision reads and the decision itself live here, and the
// app's status centre keeps only what genuinely needs the main actor: the
// observable storage, and the wire back to the route store.

/// One stretch that has no drawn railway, named by its own endpoints.
public struct SectionGap: Sendable, Equatable {
    public let segmentIndex: Int
    public let from: String?
    public let to: String?

    public init(segmentIndex: Int, from: String?, to: String?) {
        self.segmentIndex = segmentIndex
        self.from = from
        self.to = to
    }
}

/// What became of one journey's route, per journey rather than per store.
///
/// The store used to answer this with a single bit — a ride was in `rides`
/// or it was not — and that bit could not tell "drew everything" from
/// "drew four of six and dropped the rest". `solveMissing` appended a ride
/// `if !segments.isEmpty` and discarded every section that solved to
/// nothing, so a partly-solved journey was indistinguishable from a whole
/// one and the interface had nothing to warn anybody with.
///
/// Nothing here ever invents geometry: `partial` and `unavailable` mean a
/// stretch of railway was **not drawn**, never that a straight line stood
/// in for it.
public enum RouteOutcome: Sendable, Equatable {
    /// Every section the journey asked for came back with geometry.
    case resolved
    /// Some did not. `unsolved` names them the way the reader wrote them,
    /// so the interface can say which stretch is missing rather than that
    /// something, somewhere, failed.
    case partial(solved: Int, expected: Int, unsolved: [SectionGap])
    /// Not one section solved. The record is untouched and still exports.
    case unavailable(expected: Int)

    public var isResolved: Bool { self == .resolved }
}

/// One journey's solved route, as the store left it.
///
/// `Sendable` because the store builds these on the decode's own executor
/// and hands the finished table to the main actor in one assignment.
public struct RouteStatusEntry: Equatable, Sendable {
    public var outcome: RouteOutcome
    public var drawnSegments: Int

    public init(outcome: RouteOutcome, drawnSegments: Int) {
        self.outcome = outcome
        self.drawnSegments = drawnSegments
    }
}

/// §5.5's route resolution state, for **one** journey.
///
/// ``JourneyRouteState`` is the same five states as §11.1 shapes them, and
/// ``journeyRouteState(reason:)`` bridges to it. It is not simply used instead,
/// because that shape deliberately reduces a partial solve to a single `reason`
/// string: §8.4 requires the interface to say which stretch is missing ("失敗時
/// 明確受影響區間"), so the gaps travel all the way to the screen rather than
/// being flattened into "something failed".
public enum RideRouteStatus: Equatable, Sendable {
    /// Nothing has been asked yet — no solve has started (§5.5 `unknown`).
    case unknown
    /// A solve is running for this journey (§5.5 `resolving`).
    case resolving
    /// Every section came back with geometry (§5.5 `resolved`).
    case resolved(sections: Int)
    /// Some sections drew and some did not (§5.5 `needsReview`).
    case needsReview(solved: Int, expected: Int, gaps: [SectionGap])
    /// Sections were asked for and none drew (§5.5 `unavailable`).
    ///
    /// `reason` is a record value — a load failure the reader can act on —
    /// never a catalog key. Nil means the ordinary case: the solver found no
    /// path that fits the constraints, which the card explains in the
    /// catalog's own words.
    case unavailable(expected: Int, reason: String?)
    /// The journey has no drawable section at all — no two adjacent stops are
    /// marked ridden, so there is nothing for the solver to be asked.
    ///
    /// Kept apart from ``unavailable(expected:reason:)`` because the recovery
    /// is different: nothing failed, the reader has not said which stretch
    /// they rode yet.
    case noRoute

    /// §8.4 / §5.6: starting playback or a video export over a route that is
    /// not whole would be a claim the data does not support.
    public var blocksPlayback: Bool {
        if case .resolved = self { return false }
        return true
    }

    /// §7.5: a success state is not a permanent badge. Only these states are
    /// worth taking space in a Hero for.
    public var isNoteworthy: Bool {
        switch self {
        case .resolved: false
        default: true
        }
    }

    /// The same state as §11.1 spells it, so a surface already rendering
    /// `JourneyPresentation` gets the richer answer for free.
    ///
    /// The gap list collapses into `reason` here — that is the shape §11.1
    /// defines — and every caller that wants the sections themselves reads
    /// this enum instead.
    public func journeyRouteState(reason: String = "") -> JourneyRouteState {
        switch self {
        case .unknown: .unknown
        case .resolving: .resolving(completed: nil, total: nil)
        case .resolved: .resolved
        case .needsReview(let solved, let expected, _):
            .needsReview(reason: reason.isEmpty ? "\(solved)/\(expected)" : reason)
        case .unavailable(_, let failure):
            .unavailable(reason: reason.isEmpty ? (failure ?? "") : reason)
        case .noRoute: .unavailable(reason: reason)
        }
    }
}

/// Which of §5.5's five states one journey is in.
///
/// Pure: it is handed the whole of what the app's status centre knows and
/// answers without reading it back, so the app object keeps the observable
/// storage and this keeps the rules.
public enum RouteStatusResolver {

    /// - Parameters:
    ///   - id: the journey being asked about.
    ///   - resolvingIDs: journeys with a solve in flight right now — a
    ///     single-journey rebuild (§8.4), which the store-wide `phase` cannot
    ///     express. Checked first: a rebuild in progress outranks whatever the
    ///     previous solve recorded.
    ///   - entries: what the last completed solve produced, per journey.
    ///   - phase: the store-wide load phase.
    public static func status(
        id: String,
        resolvingIDs: Set<String>,
        entries: [String: RouteStatusEntry],
        phase: RouteLoadPhase
    ) -> RideRouteStatus {
        if resolvingIDs.contains(id) { return .resolving }
        guard let entry = entries[id] else {
            switch phase {
            case .idle: return .unknown
            // Store-wide, so a journey nobody has reported on yet is still
            // being worked on rather than known to have failed.
            case .loading: return .resolving
            case .loaded: return .noRoute
            // §8.8: a route dataset that would not load is not evidence that
            // this journey has nothing to draw, so it is not reported as
            // such — it is a route that is unavailable, for a stated reason.
            case .failed(let message): return .unavailable(expected: 0, reason: message)
            }
        }
        switch entry.outcome {
        case .resolved:
            return .resolved(sections: max(entry.drawnSegments, 1))
        case .partial(let solved, let expected, let unsolved):
            return .needsReview(solved: solved, expected: expected, gaps: unsolved)
        case .unavailable(let expected):
            // `expected == 0` is the store's spelling for "this journey asked
            // for nothing": `solveMissing` skips a train whose canonical
            // section list is empty, and the publish below records the ones it
            // skipped rather than leaving them indistinguishable from a
            // journey it never saw.
            return expected == 0
                ? .noRoute : .unavailable(expected: expected, reason: nil)
        }
    }
}
