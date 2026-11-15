import Foundation

// Decisions the map's draw pipeline takes when trips or lines arrive, kept as
// plain values so they can be tested on a Mac without a map view. The
// coordinator asks; it does not re-derive these rules inline.

/// Why a full rebuild started. The raw values are the numbers carried by the
/// `map.rebuild.trigger` signpost, so Instruments traces stay comparable.
public enum MapRebuildTrigger: Int, CaseIterable, Sendable {
    /// `update(...)` found changed inputs.
    case update = 1
    /// A gesture or camera settle released a deferred rebuild.
    case cameraSettled = 2
    case viewportResized = 3
    case appearanceChanged = 4
    /// A line-geometry preparation landed.
    case geometryPrepared = 5
    /// A ride-polyline preparation landed.
    case rideStrokesPrepared = 6
    /// Playback ended and released a rebuild it had deferred.
    case playbackReleased = 7
    /// A trip-to-line matching run finished.
    case strokeMatching = 8
    /// Only trips changed and the small update could not answer.
    case tripsOnly = 9
    /// The prepared geometry level was swapped in while the fingers were down.
    case levelSwapped = 10
    /// Newly loaded area was added at the installed level while the camera moved.
    case movingExtended = 11
    /// The camera still wanted another level after a landed level was
    /// installed, so the wanted level started preparing (a second rebuild).
    case wantedLevelFollowUp = 12
}

/// What the map owes after a change owes it a full rebuild.
public struct MapRebuildOwedPolicy: Equatable, Sendable {
    /// Only trips arrived, changed or left. Lines, stations, camera, layers,
    /// selection, display and date are all as they were.
    public var tripsOnly: Bool
    /// Only lines and/or stations (residency loads and evictions, a station
    /// edit) changed, and the temporal era key (`geometryEraKey`) is as it was.
    /// The preparation's landing keeps just the lines whose inputs still match
    /// (``PreparedGeometryAdmission``), so nothing in flight needs cancelling.
    public var lineDataOnly: Bool

    public init(tripsOnly: Bool, lineDataOnly: Bool = false) {
        self.tripsOnly = tripsOnly
        self.lineDataOnly = lineDataOnly
    }

    /// An in-flight line preparation is for the same lines and the same zoom
    /// frame whatever trips arrive, so its result stays valid. Cancelling it
    /// on each arrival restarts an all-or-nothing job that can then never
    /// finish while arrivals keep coming. Anything else that owes a rebuild
    /// may have changed what the preparation was asked for.
    public var cancelsGeometryPreparation: Bool { !tripsOnly && !lineDataOnly }

    /// The zoom bucket is always forgotten: the rebuild guard must let the
    /// rebuild through so the changed trips are drawn.
    public var invalidatesZoomBucket: Bool { true }

    /// The lane scale the last full draw was built at stays valid when only
    /// trips moved; the zoom bucket alone is enough to let the rebuild run.
    public var invalidatesLaneZoom: Bool { !tripsOnly }

    /// Markers are placed against the rides on screen, which just changed.
    public var invalidatesMarkerContext: Bool { true }

    public var trigger: MapRebuildTrigger { tripsOnly ? .tripsOnly : .update }
}

/// Which results of a finished line preparation may still be stored. A
/// preparation is built from a copy of each line's inputs; lines loaded or
/// evicted while it ran do not invalidate the others. A result is kept only
/// when its line's current inputs still equal the copy it was built from.
public enum PreparedGeometryAdmission {
    public static func admitted<Inputs: Equatable>(
        ids: some Sequence<String>, requested: [String: Inputs], current: [String: Inputs]
    ) -> Set<String> {
        var kept = Set<String>()
        for id in ids {
            guard let wanted = requested[id], let now = current[id], wanted == now else { continue }
            kept.insert(id)
        }
        return kept
    }
}

/// When a ride segment without a ready chain reference may be built from its
/// raw surveyed coordinates. That fallback is the most expensive ride build
/// and its result is discarded once the matched, chain-sliced key arrives, so
/// it waits while matching is still due.
public enum RideStrokeBuildPolicy {
    public static func defersFallback(
        hasStroke: Bool, matchIsCurrent: Bool, matchingPending: Bool
    ) -> Bool {
        !hasStroke && !matchIsCurrent && matchingPending
    }
}

/// The life of the line preparation, as counted. The coordinator records
/// every start, cancellation and finish here; tests drive the same type to
/// pin how arrivals interact with a preparation.
public struct GeometryPreparationLedger: Equatable, Sendable {
    public private(set) var started = 0
    public private(set) var cancelled = 0
    public private(set) var finished = 0
    public private(set) var inFlightKey: String?

    public init() {}

    public var isInFlight: Bool { inFlightKey != nil }

    /// A request for `key`. Starts a preparation unless one is in flight;
    /// returns whether it started.
    @discardableResult
    public mutating func request(key: String) -> Bool {
        guard inFlightKey == nil else { return false }
        inFlightKey = key
        started += 1
        return true
    }

    /// Returns whether a preparation was in flight and is now counted cancelled.
    @discardableResult
    public mutating func cancel() -> Bool {
        guard inFlightKey != nil else { return false }
        inFlightKey = nil
        cancelled += 1
        return true
    }

    public mutating func finish() {
        guard inFlightKey != nil else { return }
        inFlightKey = nil
        finished += 1
    }

    /// Applies a gate decision the way the coordinator does.
    public mutating func apply(_ decision: GeometryPreparationGate.Decision, key: String) {
        if decision.cancelInFlight { cancel() }
        if decision.start { request(key: key) }
    }

    /// The preparation ended without a result and was not cancelled by us.
    public mutating func abort() { inFlightKey = nil }
}

/// What `prepareNetworkGeometry` does about the line preparation, given the
/// frame it was asked for and the work still missing. The coordinator calls
/// this for every decision, so the tests pin the rule the app runs.
public enum GeometryPreparationGate {
    public struct Decision: Equatable, Sendable {
        /// True only when an in-flight preparation for another frame can no
        /// longer install (``inFlightCanInstall(rectCoversView:stopped:isRequestedLevel:)``
        /// said so). Otherwise a preparation in flight is never cancelled for
        /// another frame: it finishes and caches its frame, and its landing
        /// rebuild asks for the newest wanted frame (latest wins). Cancelling
        /// on every camera step starved every preparation during a zoom.
        public var cancelInFlight: Bool
        /// Start a preparation for the requested frame.
        public var start: Bool
        /// Nothing is missing: the rebuild may draw now.
        public var drawNow: Bool
        /// The idle neighbour prebuild is already building the requested
        /// frame: do not start a second preparation and do not cancel it.
        /// Its landing installs the level (adoption).
        public var adoptPrebuild: Bool

        public init(cancelInFlight: Bool, start: Bool, drawNow: Bool, adoptPrebuild: Bool = false) {
            self.cancelInFlight = cancelInFlight
            self.start = start
            self.drawNow = drawNow
            self.adoptPrebuild = adoptPrebuild
        }
    }

    /// `prebuildKey` is the frame the idle neighbour prebuild is building, if
    /// any. A preparation already in flight wins over adoption.
    public static func decide(
        inFlightKey: String?, requestedKey: String, prebuildKey: String?, missingWork: Bool,
        inFlightCanInstall: Bool = true
    ) -> Decision {
        guard missingWork else { return Decision(cancelInFlight: false, start: false, drawNow: true) }
        if inFlightKey == nil, let prebuildKey, prebuildKey == requestedKey {
            return Decision(cancelInFlight: false, start: false, drawNow: false, adoptPrebuild: true)
        }
        let cancel = inFlightKey != nil && inFlightKey != requestedKey && !inFlightCanInstall
        return Decision(cancelInFlight: cancel, start: inFlightKey == nil || cancel, drawNow: false)
    }

    /// Whether the running preparation can still be installed. Its rect must
    /// cover the view. Once the camera has stopped, only the wanted level may
    /// hold the geometry permit: a preparation for another level is
    /// cancelled, whether or not the installed level covers the view.
    public static func inFlightCanInstall(
        rectCoversView: Bool, stopped: Bool, isRequestedLevel: Bool
    ) -> Bool {
        rectCoversView && (isRequestedLevel || !stopped)
    }

    /// Touch-down hands the camera to the reader. A preparation whose
    /// geometry level the camera still wants (or will want next) keeps
    /// running; only one for a level it has left is cancelled.
    public static func cancelsOnTouchDown(
        inFlightLevel: Int?, zoom: Double, installedLevel: Int?
    ) -> Bool {
        guard let inFlightLevel else { return false }
        return !GeometryZoomLevels.isStillWanted(
            level: inFlightLevel, zoom: zoom, installed: installedLevel)
    }
}

/// How often the draw pipeline did each costly thing. Read by tests and
/// reported as signposts; never used for decisions.
public struct MapDrawCounters: Equatable, Sendable {
    public var preparations = GeometryPreparationLedger()
    public private(set) var fullRebuilds: [MapRebuildTrigger: Int] = [:]
    public private(set) var rideCacheMisses: [MapRebuildTrigger: Int] = [:]

    public init() {}

    public mutating func noteFullRebuild(_ trigger: MapRebuildTrigger) {
        fullRebuilds[trigger, default: 0] += 1
    }

    public mutating func noteRideCacheMisses(_ count: Int, trigger: MapRebuildTrigger) {
        guard count > 0 else { return }
        rideCacheMisses[trigger, default: 0] += count
    }

    public var totalFullRebuilds: Int { fullRebuilds.values.reduce(0, +) }
    public var totalRideCacheMisses: Int { rideCacheMisses.values.reduce(0, +) }
}

/// Tap-index builds: one per settled load, plus any a tap forced.
public struct TapIndexCounters: Equatable, Sendable {
    public private(set) var prebuilt = 0
    public private(set) var onDemand = 0
    public private(set) var abandoned = 0

    public init() {}

    public mutating func notePrebuilt() { prebuilt += 1 }
    public mutating func noteOnDemand() { onDemand += 1 }
    public mutating func noteAbandoned() { abandoned += 1 }
}

/// When the tap index may be built ahead of a tap.
public enum TapIndexPrebuildPolicy {
    /// Not while trips are loading: each arrival replaces the geometry, so a
    /// build would be thrown away. A tap during a load builds on demand; the
    /// load settling builds once.
    public static func mayPrebuild(ridesAreLoading: Bool, hasIndex: Bool, hasSnapshotProvider: Bool) -> Bool {
        !ridesAreLoading && !hasIndex && hasSnapshotProvider
    }
}

/// The identity of one drawn trip segment's polyline in the frame cache.
///
/// A segment drawn from a built network line carries that line's id, the
/// generation of the stroke build it was sliced from, and the span it slices.
/// A rebuilt line gets a new generation, so a polyline made from the old
/// build can never be found again; a trip on another line keeps its key.
public struct RideLineCacheKey: Hashable, Sendable {
    public struct Stroke: Hashable, Sendable {
        public var lineID: String
        public var generation: Int
        public var from: Double
        public var to: Double

        public init(lineID: String, generation: Int, from: Double, to: Double) {
            self.lineID = lineID
            self.generation = generation
            self.from = from
            self.to = to
        }
    }

    public var rideID: String
    public var geometryDigest: Int
    public var segmentIndex: Int
    public var partIndex: Int
    /// Nil for a segment drawn from its own surveyed coordinates.
    public var stroke: Stroke?

    public init(
        rideID: String, geometryDigest: Int, segmentIndex: Int, partIndex: Int, stroke: Stroke?
    ) {
        self.rideID = rideID
        self.geometryDigest = geometryDigest
        self.segmentIndex = segmentIndex
        self.partIndex = partIndex
        self.stroke = stroke
    }

    /// The same segment without the line it was sliced from.
    public var segmentIdentity: SegmentIdentity {
        SegmentIdentity(
            rideID: rideID, geometryDigest: geometryDigest,
            segmentIndex: segmentIndex, partIndex: partIndex)
    }

    public struct SegmentIdentity: Hashable, Sendable {
        public var rideID: String
        public var geometryDigest: Int
        public var segmentIndex: Int
        public var partIndex: Int

        public init(rideID: String, geometryDigest: Int, segmentIndex: Int, partIndex: Int) {
            self.rideID = rideID
            self.geometryDigest = geometryDigest
            self.segmentIndex = segmentIndex
            self.partIndex = partIndex
        }
    }

    /// Whether the pixels under this key still come from the line's current
    /// build. A segment with no line is always current.
    public func isCurrent(lineGenerations: [String: Int]) -> Bool {
        guard let stroke else { return true }
        return lineGenerations[stroke.lineID] == stroke.generation
    }
}
