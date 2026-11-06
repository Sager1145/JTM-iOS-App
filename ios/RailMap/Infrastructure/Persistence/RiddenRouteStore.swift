import CryptoKit
import Foundation
import MapKit
import Observation
import os
import RailCore
import RailPresentation

/// Ridden geometry for every journey in the working set. Bundled examples and
/// the reader's own journeys resolve the same way: the per-journey route
/// cache, then the on-device solver. The map consumes the solved source
/// coordinates for statistics and slices the complete railway for display.
@MainActor
@Observable
final class RiddenRouteStore {
    /// Native selection semantics, separate from the attested JS solver's
    /// version. Shared reference datasets are never relabeled with this value.
    // Recheck registered row ownership and reject foreign continuation prefixes.
    private nonisolated static let resolutionSemantics = "physical-section-evidence-v5"
    typealias PhysicalRouteSelection = RideRouteResolution.PhysicalRouteSelection
    typealias PhysicalGap = RideRouteResolution.PhysicalGap

    struct DrawnSegment: Sendable {
        let segmentIndex: Int
        /// Which part of a MultiLineString this stroke came from — 0 for a
        /// plain LineString or a single-part feature. `segmentIndex` alone
        /// aliases every part of one feature when the dataset's own indices
        /// are authoritative (they are then equal across every part), so a
        /// cache or lookup keyed on identity rather than section semantics
        /// must include this too.
        let partIndex: Int
        let from: String?
        let to: String?
        /// Canonical WGS84 geometry used by the solver, cache and statistics.
        /// It must remain in the same datum as the region's edge index.
        let sourceCoordinates: [Coordinate]
        /// The drawn path in WGS84 — what ``coordinates`` is the displaced
        /// presentation OF, and the array the route cache persists. Kept
        /// because the displacement is not reversible in this direction: a
        /// cache holding the GCJ-02 copy would displace it a second time on
        /// the next load.
        let drawnCoordinates: [Coordinate]
        /// Geometry presented to MapKit. This differs for Taiwan, Hong Kong,
        /// Macao and Korea, where Apple's basemap is displaced to GCJ-02.
        let coordinates: [Coordinate]
        let boundingRect: MKMapRect
        /// History-overlay identifiers carried from the solved section.
        /// Empty for current track and for precomputed dataset geometry,
        /// which has no provenance of its own.
        let historyIDs: [String]
        let validFrom: String?
        let validTo: String?
        let temporalKind: RouteGraph.TemporalKind
        /// The physical choice that produced both source and display geometry.
        /// Every part carries it; consumers count it once per section.
        let physicalRoute: PhysicalRouteSelection?

        /// - Parameter sourceCoordinates: the N02-datum path, when it is not
        ///   the same array as what gets drawn. A hop re-drawn against the
        ///   display line is a different geometry from the one the solver
        ///   walked — groomed, welded at junction anchors, and at 東京駅 on
        ///   surveyed OpenStreetMap track N02 does not carry — so a caller
        ///   that canonicalises MUST hand the solver's own path in here.
        ///   Defaulting to `coordinates` keeps every caller that does not
        ///   canonicalise exactly as it was.
        ///
        ///   Handing the drawn path to both is what made the statistics
        ///   measure a ride against a network it was not matched on. It also
        ///   double-counted: the display network cuts an N02 edge in half at
        ///   a station anchor, so the same track ridden once each way holds
        ///   the whole edge and its two halves, and a deduped union over edge
        ///   ids cannot see that they are the same rail.
        init(
            segmentIndex: Int, partIndex: Int = 0, from: String?, to: String?,
            coordinates: [Coordinate], sourceCoordinates: [Coordinate]? = nil,
            country: String,
            historyIDs: [String] = [],
            validFrom: String? = nil,
            validTo: String? = nil,
            temporalKind: RouteGraph.TemporalKind = .current,
            physicalRoute: PhysicalRouteSelection? = nil
        ) {
            self.segmentIndex = segmentIndex
            self.partIndex = partIndex
            self.from = from
            self.to = to
            self.sourceCoordinates = sourceCoordinates ?? coordinates
            drawnCoordinates = coordinates
            self.coordinates = AppleMapDatum.display(coordinates, country: country)
            self.historyIDs = historyIDs
            self.validFrom = validFrom
            self.validTo = validTo
            self.temporalKind = temporalKind
            self.physicalRoute = physicalRoute
            var bounds = MKMapRect.null
            for coordinate in self.coordinates {
                let point = MKMapPoint(CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
                bounds = bounds.union(MKMapRect(origin: point, size: MKMapSize(width: 0.001, height: 0.001)))
            }
            boundingRect = bounds
        }
    }

    /// What became of one journey's route, per journey rather than per store.
    ///
    /// The type itself is `RailPresentation.RouteOutcome`: deciding what a
    /// route outcome MEANS for a surface is a rule, and a rule in the app
    /// target is a rule with no test under it. These two spellings stay
    /// because they are what six files already say, and because a route
    /// outcome is still the store's to produce — only not its to interpret.
    typealias RouteOutcome = RailPresentation.RouteOutcome

    /// One stretch that has no drawn railway, named by its own endpoints.
    typealias SectionGap = RailPresentation.SectionGap

    struct DrawnRide: Identifiable, Sendable {
        let id: String
        /// The service description drives journey-station level of detail:
        /// sparse high-speed and limited services reveal their calls before a
        /// dense local service does.
        let trainType: String?
        /// The region this ride was solved against — `"jp"`, `"tw"`, `"hk"`,
        /// `"mo"` or `"kr"`.
        ///
        /// Carried on the ride rather than looked up from the train, because
        /// the map is handed rides and not journeys: the ridden-line category
        /// filter classifies a drawn segment against its own region's N02 edge
        /// index, and picking the wrong region's index would not fail — it
        /// would answer, wrongly.
        let country: String
        let colorHex: String
        let visible: Bool
        let segments: [DrawnSegment]
        /// What became of the route. See ``RouteOutcome``.
        let route: RouteOutcome
        /// The journey's stops, in order, carrying the two fields the map
        /// cannot otherwise know: which calls were ridden (`rideSegment`) and
        /// which stations are rolled through rather than called at
        /// (`stopType`). Without them every drawn segment has to be assumed
        /// ridden and every section boundary assumed a call, and a
        /// pass-through drawn as a stop is a claim about the journey that the
        /// reader did not make.
        let stops: [Stop]
        /// Explicit display positions for network previews whose continuous
        /// geometry does not split at every platform. Recorded rides use endpoints.
        var markerPositions: [Int: Coordinate] = [:]
        /// Optional resource failures from this record's current route request.
        /// Kept beside its geometry so another record cannot clear or inherit them.
        var resourceWarnings: [String] = []
        var physicalGaps: [PhysicalGap] = []
        /// Sections drawn from track a plausibility guard rejected: shown
        /// dotted, never counted in distance, coverage or traversed lines.
        var unprovenSegmentIndices: Set<Int> {
            Set(physicalGaps.lazy.filter(\.isUnproven).map(\.segmentIndex))
        }
        var indicesAreAuthoritative = true
        var expectedSectionCount = 0
        /// The route sections this ride was solved for (`Result.expectedSections`),
        /// which ``RiddenLineSequence`` reads section by section. In memory
        /// only: the route cache recomputes them from the train on load.
        var expectedSections: [RouteSection] = []
        var recordedRouteMapping: RecordedRouteMapping? = nil
        /// Endpoint ownership is independent of the number of drawn geometry
        /// parts belonging to one physical section.
        var sectionPartRanges: [Int: ClosedRange<Int>] = [:]

        func stopInterval(forSectionIndex index: Int) -> Int? {
            recordedRouteMapping?.stopInterval(forSectionIndex: index)
        }

        func recordedStopIndices(for segment: DrawnSegment) -> (from: Int?, to: Int?) {
            guard let parts = sectionPartRanges[segment.segmentIndex] else { return (nil, nil) }
            return (
                segment.partIndex == parts.lowerBound
                    ? recordedRouteMapping?.stopIndex(atSectionBoundary: segment.segmentIndex) : nil,
                segment.partIndex == parts.upperBound
                    ? recordedRouteMapping?.stopIndex(atSectionBoundary: segment.segmentIndex + 1) : nil)
        }
        /// The calendar days this itinerary touches and where it crosses them,
        /// so an overnight ride can draw the half that runs on the other day
        /// differently — `Dates.segmentDate(_:segmentIndex:)` maps a segment to
        /// its day.
        let daySpan: Dates.DaySpan
        /// A precomputed identity for the actual vertices.
        ///
        /// The map compares rides during every SwiftUI update. Walking all
        /// coordinates there makes a sheet drag pay for route geometry on
        /// every frame; comparing only `vertexCount` misses a rebuilt route
        /// whose new geometry happens to have the same number of points.
        /// Hash once when the ride is decoded and both paths stay cheap.
        let geometryDigest: Int
        var strokes: [[Coordinate]] { segments.map(\.coordinates) }
        var vertexCount: Int { strokes.reduce(0) { $0 + $1.count } }
    }

    enum LoadState {
        case idle
        case loading
        case loaded(rides: [DrawnRide])
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var rides: [DrawnRide] = [] {
        didSet {
            // Bumped only when the (id, geometryDigest) sequence moves, which
            // is exactly what the statistics load key observes; see
            // `AppShell.statisticsLoadKey`. Runs on mutation, not on read.
            guard rides.count != oldValue.count
                || zip(rides, oldValue).contains(where: {
                    $0.id != $1.id || $0.geometryDigest != $1.geometryDigest })
            else { return }
            ridesKeyGeneration &+= 1
        }
    }
    /// Changes iff the ordered ride ids or geometry digests change.
    private(set) var ridesKeyGeneration = 0
    /// Stable, already-filtered input for the map.
    ///
    /// Filtering in `RailWorkspaceView.body` allocated a fresh array on every
    /// sheet-height sample, defeating the renderer's shared-storage fast path
    /// even when no journey had changed.
    private(set) var visibleRides: [DrawnRide] = []
    private var loadTask: Task<Void, Never>?
    private var loadRevision = 0
    /// Same records arriving again must join the current batch, not restart it.
    private var loadingInputs: [String: Train]?
    private var requestedOrder: [String] = []
    /// Full records remain the invalidation boundary. Reuse happens per
    /// journey, so a same-ID edit cannot leave stale route geometry behind.
    private var completedInputs: [String: Train] = [:]
    /// The last full set `load` was asked for, so "reload all" re-resolves
    /// exactly what the map was given — the same scoped, capped set.
    private var lastRequestedInputs: [String: Train] = [:]
    /// True from `reloadAll` until its load finishes, fails or is stopped.
    private var reloadingAll = false
    /// Set while `reloadAll` waits for the previous work to stop and the
    /// cache to be discarded, so a second confirm cannot start it twice.
    private var reloadStarting = false
    private var resolutionTickets: [String: UUID] = [:]
    /// Per-ride landing stamp. A resolution task stamps the ride it lands; a
    /// load publishes its older batch snapshot only for rides not stamped since
    /// the load began, so the latest landing always wins.
    private var landingCounter = 0
    private var landedAt: [String: Int] = [:]
    private var resolutionTasks: [String: Task<Void, Never>] = [:]
    /// What the last completed solve produced, per journey. Which §5.5 state
    /// that is remains ``RouteStatusResolver``'s rule.
    private(set) var routeEntries: [String: RouteStatusEntry] = [:]
    /// Single-journey solves in flight. Replacing the entry table clears the
    /// set; finishing or abandoning one solve touches only that id.
    private(set) var resolvingIDs: Set<String> = []
    /// Detected railways for the rides this store is drawing. The same instance
    /// is injected for every surface that shows those lines.
    let lineDetector = TraversedLineDetector()

    /// Selected records have settled geometry or the existing terminal batch
    /// failure leaves their distance unknown. This never marks failed inputs
    /// completed, so an explicit retry still resolves them normally.
    func hasSettledRoutes(in trains: [Train], matching includes: (Train) -> Bool) -> Bool {
        let failed: Bool
        if case .failed = state { failed = true } else { failed = false }
        return trains.allSatisfy { train in
            !includes(train) || (resolutionTickets[train.id] == nil
                && (completedInputs[train.id] == train || failed))
        }
    }

    /// Only diagnostics produced for the exact record currently displayed.
    func resourceWarnings(for train: Train) -> [String] {
        guard completedInputs[train.id] == train else { return [] }
        return rides.first(where: { $0.id == train.id })?.resourceWarnings ?? []
    }

    /// §5.5 for one journey. Confirmation ids belong to the itinerary; this
    /// store supplies the solve inputs and does not decide the state.
    func status(
        forTrainID id: String, pendingConfirmationIDs: Set<String>
    ) -> RideRouteStatus {
        RouteStatusResolver.status(
            id: id, resolvingIDs: resolvingIDs, entries: routeEntries,
            phase: routePhase, pendingConfirmationIDs: pendingConfirmationIDs)
    }

    /// Solve one journey again. Always starts: the store is the route owner,
    /// so there is no missing wire to report.
    @discardableResult
    func resolveAgain(_ train: Train) -> Bool {
        resolve(train)
        return true
    }

    private var routePhase: RouteLoadPhase {
        switch state {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .failed(let message): .failed(message)
        }
    }

    /// Replace the solved-route table, keeping `landed` entries and the
    /// resolving status of solves still in flight (they hold a live ticket).
    private func noteRouteEntries(for rides: [DrawnRide], wanted: [String], keeping landed: Set<String> = []) {
        let kept = routeEntries.filter { landed.contains($0.key) }
        routeEntries = Self.statusEntries(for: rides, wanted: wanted)
        for (id, entry) in kept { routeEntries[id] = entry }
        // A solve still in flight keeps its resolving status until it lands.
        resolvingIDs = resolvingIDs.filter { resolutionTickets[$0] != nil }
    }

    private func landedSince(_ mark: Int) -> Set<String> {
        Set(landedAt.filter { $0.value > mark }.keys)
    }

    /// `retained + batch`, except rides a resolution landed after `mark`: the
    /// current entry (or its absence) wins over the batch's older snapshot.
    private func mergedRides(retained: [DrawnRide], batch: [DrawnRide], since mark: Int) -> [DrawnRide] {
        let landed = landedSince(mark)
        guard !landed.isEmpty else { return ordered(retained + batch) }
        let current = rides.filter { landed.contains($0.id) }
        return ordered(retained.filter { !landed.contains($0.id) }
            + batch.filter { !landed.contains($0.id) } + current)
    }

    /// Solve and draw every ride, whatever region each belongs to.
    ///
    /// The web app is handed one dataset and one country because it has one
    /// region open. Here each ride names its own region (`Train.region`), the
    /// pipeline groups by it, and the per-region resources — the sections
    /// file, the station table, the package, the route cache — are loaded once
    /// per region that actually has rides rather than once per app.
    func load(
        trains: [Train], preferredTrainID: String? = nil,
        priority: TaskPriority = .userInitiated
    ) {
        bindPendingOwner()
        // Trips in a disabled region stay in the store but are never cached,
        // solved or drawn. Their route-cache files are left on disk.
        let trains = trains.filter { Region.resolved($0).isEnabled }
        let wanted = Dictionary(trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedIDs = trains.map(\.id)
        requestedOrder = wantedIDs
        lastRequestedInputs = wanted
        // View remounts and an order-only change share the batch already running.
        // Neither network rendering arrivals nor partial route publications are
        // solver inputs. Resource revisions are immutable for this app launch.
        if loadingInputs == wanted {
            rides = ordered(rides)
            visibleRides = rides.filter(\.visible)
            return
        }
        if completedInputs == wanted, case .loaded = state {
            rides = ordered(rides)
            visibleRides = rides.filter(\.visible)
            state = .loaded(rides: rides)
            return
        }
        loadTask?.cancel()
        cancelResolutions()
        reloadingAll = false
        loadRevision += 1
        let revision = loadRevision
        let landingMark = landingCounter
        loadingInputs = wanted
        let unchanged = Set(wanted.compactMap { id, train in
            completedInputs[id] == train ? id : nil
        })
        let retained = rides.filter { unchanged.contains($0.id) }
        let pending = wanted.filter { !unchanged.contains($0.key) }
        completedInputs = completedInputs.filter { unchanged.contains($0.key) }

        rides = ordered(retained)
        visibleRides = rides.filter(\.visible)
        lineDetector.publishSelected(rides: rides)
        if pending.isEmpty {
            loadingInputs = nil
            loadTask = nil
            state = .loaded(rides: rides)
            noteRouteEntries(for: rides, wanted: wantedIDs)
            detectTraversedLines()
            return
        }
        state = .loading
        noteRouteEntries(for: rides, wanted: [])
        // A cold load publishes once per solved journey, and every publish
        // rebuilt the whole map, the ride status list and line detection on
        // the main thread: 284 journeys meant a 120–230 ms map rebuild every
        // ~150 ms for the length of the load. Partial results are coalesced
        // instead; the final result below still lands at once.
        let partials = PartialRidePublication()
        let inbox = PartialRideInbox()
        let owner = pendingSolveOwner
        loadTask = Task(priority: priority) {
            await Self.$activePendingOwner.withValue(owner) {
            do {
                let preread = try await Self.loadPreferred(id: preferredTrainID, wanted: pending)
                let primed = preread.rides.first
                try Task.checkCancellation()
                guard loadRevision == revision else { return }
                if let primed {
                    rides = mergedRides(retained: retained, batch: [primed], since: landingMark)
                    visibleRides = rides.filter(\.visible)
                    if !landedSince(landingMark).contains(primed.id) { completedInputs[primed.id] = wanted[primed.id] }
                    noteRouteEntries(for: rides, wanted: [], keeping: landedSince(landingMark))
                    lineDetector.publishSelected(rides: rides)
                }
                let decoded = try await Self.decode(
                    wanted: pending, requestedOrder: wantedIDs,
                    preferredTrainID: preferredTrainID, primed: primed, preread: preread
                ) { partial in
                    if inbox.post(partial) {
                        Task { @MainActor in
                            guard let p = inbox.take(),
                                  self.loadRevision == revision else { return }
                            partials.submit(p) { partial in
                                guard self.loadRevision == revision else { return }
                                self.rides = self.mergedRides(retained: retained, batch: partial, since: landingMark)
                                self.visibleRides = self.rides.filter(\.visible)
                                let landed = self.landedSince(landingMark)
                                for ride in partial where !landed.contains(ride.id) { self.completedInputs[ride.id] = wanted[ride.id] }
                                self.noteRouteEntries(for: self.rides, wanted: [], keeping: landed)
                                // Line rows are not republished per partial:
                                // each pass walks every segment and re-renders
                                // every row. The final `detectTraversedLines`
                                // publishes once; recorded names cover until then.
                                RailSignpost.data.mark("routes.partial.publish", partial.count)
                            }
                        }
                    }
                }
                inbox.close()
                partials.cancel()
                try Task.checkCancellation()
                guard loadRevision == revision else { return }
                let landed = landedSince(landingMark)
                rides = mergedRides(retained: retained, batch: decoded, since: landingMark)
                visibleRides = rides.filter(\.visible)
                var finalInputs = wanted
                for id in landed { if let latest = completedInputs[id] { finalInputs[id] = latest } }
                completedInputs = finalInputs
                loadingInputs = nil
                loadTask = nil
                reloadingAll = false
                state = .loaded(rides: rides)
                noteRouteEntries(for: rides, wanted: wantedIDs, keeping: landed)
                detectTraversedLines()
                Self.sweepRouteCacheOnce(protecting: Set(completedInputs.keys))
            } catch is CancellationError {
                inbox.close()
                partials.cancel()
                if loadRevision == revision { loadingInputs = nil; loadTask = nil }
                return
            } catch {
                // What was solved before the failure is still worth drawing.
                if let pending = inbox.take() {
                    partials.submit(pending) { partial in
                        guard self.loadRevision == revision else { return }
                        self.rides = self.mergedRides(retained: retained, batch: partial, since: landingMark)
                        self.visibleRides = self.rides.filter(\.visible)
                        let landed = self.landedSince(landingMark)
                        for ride in partial where !landed.contains(ride.id) { self.completedInputs[ride.id] = wanted[ride.id] }
                        self.noteRouteEntries(for: self.rides, wanted: [], keeping: landed)
                        self.lineDetector.publishSelected(rides: self.rides)
                    }
                }
                inbox.close()
                partials.applyPending()
                guard loadRevision == revision else { return }
                loadingInputs = nil
                loadTask = nil
                reloadingAll = false
                state = .failed(error.localizedDescription)
                noteRouteEntries(for: rides, wanted: [], keeping: landedSince(landingMark))
            }
            }
        }
    }

    // MARK: - Reload all

    struct ReloadProgress: Equatable {
        var done: Int
        var total: Int
    }

    /// `n of N` while a reader-started reload runs; nil otherwise. Advances
    /// as coalesced partial results land, never per journey.
    var reloadProgress: ReloadProgress? {
        guard reloadingAll, case .loading = state else { return nil }
        let done = requestedOrder.reduce(0) { $0 + (completedInputs[$1] == nil ? 0 : 1) }
        return ReloadProgress(done: done, total: requestedOrder.count)
    }

    /// True while a load is resolving. Derived products that summarise every
    /// trip (statistics, passport) wait for this to clear instead of
    /// recomputing on each partial publish.
    var isLoading: Bool {
        if case .loading = state { true } else { false }
    }

    /// Whether `load` has been handed any trips yet.
    var requestedIsEmpty: Bool { requestedOrder.isEmpty }

    /// Whether there is anything to reload.
    var canReloadAll: Bool { !requestedOrder.isEmpty && !reloadingAll && !reloadStarting }

    /// Forget every solved route and resolve the current set again.
    ///
    /// Runs through `load`, so it is the same path, the same single solve
    /// permit and the same coalesced map updates as any load — at `.utility`
    /// priority, so the reader can keep using the app while it runs. The disk
    /// cache is removed first and each entry is rewritten atomically as its
    /// journey lands, so stopping or restarting midway leaves only complete
    /// entries; whatever was not reached is solved by the next load.
    func reloadAll() async {
        guard !reloadStarting, !reloadingAll, !requestedOrder.isEmpty else { return }
        reloadStarting = true
        defer { reloadStarting = false }
        // Stop everything that could still publish or write a route, and wait
        // for it: a cancelled solve that lands after the cache is gone would
        // be replayed by the reload instead of being solved again.
        let previousLoad = loadTask
        let previousResolutions = Array(resolutionTasks.values)
        loadRevision += 1
        previousLoad?.cancel()
        cancelResolutions()
        loadTask = nil
        loadingInputs = nil
        await previousLoad?.value
        for task in previousResolutions { await task.value }
        completedInputs = [:]
        await Self.discardSolvedRoutes()
        completedInputs = [:]
        // Read after the waits: a load that arrived meanwhile (an import, an
        // edit) is the set to reload, not the one this call started with.
        let trains = requestedOrder.compactMap { lastRequestedInputs[$0] }
        guard !trains.isEmpty else { return }
        load(trains: trains, priority: .utility)
        if case .loading = state { reloadingAll = true }
    }

    /// Stop a forced reload. What it already solved stays; the rest of the
    /// set goes back to an ordinary load — cached routes replay, missing ones
    /// solve — so no trip is left without a route or a status.
    func cancelReloadAll() {
        guard reloadingAll else { return }
        let trains = requestedOrder.compactMap { lastRequestedInputs[$0] }
        // Not joined to the reload's batch: `load` would share a batch with
        // the same inputs. The ordinary load below replaces it.
        loadRevision += 1
        loadTask?.cancel()
        loadTask = nil
        loadingInputs = nil
        load(trains: trains, priority: .utility)
        reloadingAll = false
    }

    /// The route cache on disk plus every in-memory memo of a solve, so a
    /// reload solves rather than replays.
    @concurrent nonisolated static func discardSolvedRoutes() async {
        let base = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory).appending(path: "RailMap/Routes", directoryHint: .isDirectory)
        RouteDigestIndexStore.shared.clear()
        try? FileManager.default.removeItem(at: base)
        await sharedJourneyWork.clear()
        // Only the memoised section solves are dropped; the ~26 MB of decoded
        // inputs stay, so Reload all solves again without decoding again.
        await SolverInputCache.shared.clearResolutionMemo()
        // A failed history read is retried on reload, as before.
        historyStateCache.withLock { states in
            states = states.filter { if case .invalid = $0.value { false } else { true } }
        }
    }

    private func ordered(_ values: [DrawnRide]) -> [DrawnRide] {
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return requestedOrder.compactMap { byID[$0] }
    }

    /// Read the last-viewed route only. A miss deliberately does not solve:
    /// the complete decoder below owns expensive work and its cancellation.
    /// A miss hands its canonical input and digest to the decoder, so the
    /// preferred journey is enriched and read once rather than three times.
    @concurrent private nonisolated static func loadPreferred(
        id: String?, wanted: [String: Train]
    ) async throws -> CacheBatch {
        guard let id, let train = wanted[id] else { return CacheBatch() }
        return try await loadCached([train], country: RouteScope(train).code)
    }

    func clear() {
        reloadingAll = false
        loadingInputs = nil
        requestedOrder = []
        loadRevision += 1
        completedInputs = [:]
        resolutionTickets = [:]
        cancelResolutions()
        loadTask?.cancel()
        rides = []
        visibleRides = []
        state = .idle
        routeEntries = [:]
        resolvingIDs = []
        lineDetector.reset()
    }

    /// The railways every current ride actually ran over — a detection kept
    /// alongside the route entries this store already publishes, off the
    /// recorded `line_names` entirely. See ``TraversedLineDetector``.
    ///
    /// Called only where `state` settles to `.loaded(rides:)` and at the end
    /// of ``resolve(_:)``, not on every intermediate publish: detection waits
    /// for the full ride set so a launch does not re-walk every ride once per
    /// partial batch, and the recorded names cover the rows until then.
    private func detectTraversedLines() {
        lineDetector.update(rides: rides)
    }

    private enum SingleResolve: Sendable {
        case ride(DrawnRide?)
        case invalidHistory(String)
        case failed
    }

    /// Solve one journey's route again, in place (§8.4).
    ///
    /// The failure this guards against: the drawn line stops being a picture
    /// of the record it claims to be — OLD geometry under a NEW section list,
    /// which is worse than showing nothing. The shell's route key now covers
    /// the whole record, so a full reload would eventually correct it; this
    /// corrects the one journey the reader just rebuilt without waiting for
    /// the other two hundred to be read back.
    ///
    /// Nothing is deleted from the itinerary store here, and nothing is
    /// straight-lined: a journey whose new sections solve to nothing keeps its
    /// record and loses its strokes, which is what "unavailable" means.
    func resolve(_ train: Train) {
        let scope = RouteScope(train)
        let id = train.id
        let revision = loadRevision
        let ticket = UUID()
        resolutionTasks[id]?.cancel()
        resolutionTickets[id] = ticket
        resolvingIDs.insert(id)
        bindPendingOwner()
        let owner = pendingSolveOwner
        resolutionTasks[id] = Task(priority: .userInitiated) {
            await Self.$activePendingOwner.withValue(owner) {
            let resolved: SingleResolve
            do {
                let ride = try await Self.resolveOne(train, scope: scope)
                try Task.checkCancellation()
                resolved = .ride(ride)
            } catch is CancellationError {
                // Another solve, or a load that replaced the table, owns the
                // outcome. Leaving here does not clear any journey's entry.
                return
            } catch let error as LoadError {
                if case .invalidHistory = error {
                    resolved = .invalidHistory(error.localizedDescription)
                } else {
                    resolved = .failed
                }
            } catch {
                resolved = .failed
            }

            guard !Task.isCancelled, loadRevision == revision,
                  resolutionTickets[id] == ticket else { return }
            // A record removed from the working set must not reappear as a ride
            // or as a solved entry. Only this id is dropped.
            guard requestedOrder.contains(id) else {
                resolvingIDs.remove(id)
                resolutionTasks[id] = nil
                resolutionTickets[id] = nil
                return
            }
            resolutionTasks[id] = nil
            resolutionTickets[id] = nil
            completedInputs[id] = train
            landingCounter += 1
            landedAt[id] = landingCounter
            let entry: RouteStatusEntry
            switch resolved {
            case .ride(let solved):
                if let solved {
                    if let index = rides.firstIndex(where: { $0.id == id }) {
                        rides[index] = solved
                    } else {
                        rides.append(solved)
                    }
                } else {
                    rides.removeAll { $0.id == id }
                }
                entry = solved.map {
                    RouteStatusEntry(outcome: $0.route, drawnSegments: $0.segments.count)
                } ?? RouteStatusEntry(outcome: .unavailable(expected: 0), drawnSegments: 0)
            case .invalidHistory(let message):
                // No DrawnRide to publish. Removing the journey here would make
                // the next read report noRoute once the entry was lost.
                entry = RouteStatusEntry(
                    outcome: .historyDatabaseInvalid(message), drawnSegments: 0)
            case .failed:
                entry = RouteStatusEntry(
                    outcome: .unavailable(expected: 1), drawnSegments: 0)
            }
            visibleRides = rides.filter(\.visible)
            if case .loaded = state { state = .loaded(rides: rides) }
            resolvingIDs.remove(id)
            routeEntries[id] = entry
            detectTraversedLines()
            }
        }
    }

    /// A record edit also triggers AppShell's load. That load owns the new
    /// working set; superseded single-route work must stop consuming CPU.
    private func cancelResolutions() {
        for task in resolutionTasks.values { task.cancel() }
        resolutionTasks.removeAll()
        resolutionTickets.removeAll()
    }

    /// Whether this region can answer date-specific route questions.
    nonisolated static func hasDatedNetwork(region: String) -> Bool {
        railHistoryURL(region: region) != nil
    }

    struct RouteAvailability: Sendable {
        let undatedResolved: Bool
        let datedResolved: Bool
    }

    /// The graph a historical-connection probe solves on, kept for the next
    /// probe in the same area. Built only from the rail sections near the
    /// two stations, so even the solver's last-resort full-graph pass stays
    /// regional: the national graph is never built for a probe.
    private final class ProbeGraphCache: @unchecked Sendable {
        static let shared = ProbeGraphCache()
        private let lock = NSLock()
        private var entry: (key: String, store: UncheckedGraphStoreBox)?

        func store(key: String, build: () -> RouteGraph.RouteGraphStore) -> UncheckedGraphStoreBox {
            lock.lock()
            defer { lock.unlock() }
            if let entry, entry.key == key { return entry.store }
            let built = UncheckedGraphStoreBox(store: build())
            entry = (key, built)
            return built
        }

        var isEmpty: Bool {
            lock.lock()
            defer { lock.unlock() }
            return entry == nil
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            entry = nil
        }
    }

    #if DEBUG
    /// Test seam: whether a probe graph is memoised, and a way to put one there.
    nonisolated static var probeGraphIsCached: Bool { !ProbeGraphCache.shared.isEmpty }

    nonisolated static func seedProbeGraphCacheForTesting() {
        _ = ProbeGraphCache.shared.store(key: "test-seed") { RouteGraph.RouteGraphStore(sections: []) }
    }
    #endif

    /// Whether a line connected the train's two stations on its ride date,
    /// for the editor's historical-line notice. Dated only: the planner has
    /// already found no route on today's network. Never publishes or saves.
    @concurrent nonisolated static func historicalConnection(
        _ train: Train, between from: Coordinate, and to: Coordinate
    ) async throws -> Bool {
        try Task.checkCancellation()
        let scope = RouteScope(train)
        let inputs = try await SolverInputCache.shared.inputs(scope: scope)
        try Task.checkCancellation()
        let ends = RouteGraph.BBox(
            minX: min(from.lon, to.lon), minY: min(from.lat, to.lat),
            maxX: max(from.lon, to.lon), maxY: max(from.lat, to.lat))
        // The solver's widest regional margin for this span.
        let margin = max(90_000, RouteGraph.bboxDiagonalMeters(ends) * 1.5)
        let area = RouteGraph.quantizeBBoxOutward(RouteGraph.padBBoxMeters(ends, meters: margin))
        let key = ([scope.key, String(describing: inputs.snapshotID)]
            + area.array.map { String(format: "%.3f", $0) })
            .joined(separator: "\u{1f}")
        let graphStore = ProbeGraphCache.shared.store(key: key) {
            let nearby = inputs.sections.filter { feature in
                RouteGraph.featureBBox(feature).map { RouteGraph.bboxIntersects($0, area) } ?? false
            }
            return RouteGraph.RouteGraphStore(
                sections: nearby, policy: .physicalRailway, junctions: inputs.physicalJunctions,
                cachePolicy: .bounded(maximumNodes: 100_000),
                identityPeriods: inputs.identityPeriods, sourceSnapshotID: inputs.snapshotID)
        }
        try Task.checkCancellation()
        let ride = try await RouteSolveLimiter.shared.withPermit {
            try await solveMissingSequentialWithPermit(
                [train], scope: scope, allowLegacy: true,
                graphStore: graphStore.store, providedInputs: inputs,
                publish: { _ in }, saveRoutes: false).first
        }
        return ride?.route.isResolved == true
    }

    /// Probe together so both passes reuse one mutable graph and never publish or persist.
    @concurrent nonisolated static func routeAvailabilities(
        _ datedTrains: [Train]
    ) async throws -> [RouteAvailability] {
        try Task.checkCancellation()
        var byScope: [RouteScope: [(Int, Train)]] = [:]
        for (index, train) in datedTrains.enumerated() {
            try Task.checkCancellation()
            byScope[RouteScope(train), default: []].append((index, train))
        }

        // This helper's graph lifetime ends before the next scope loads inputs.
        func resolvedScope(
            _ scope: RouteScope, entries: [(Int, Train)]
        ) async throws -> [(Int, RouteAvailability)] {
            var graphStore: UncheckedGraphStoreBox?
            var providedInputs: SolverInputs?
            func resolved(dated: Bool) async throws -> [Bool] {
                var answers = [Bool](repeating: false, count: entries.count)
                var missing: [(Int, Train)] = []
                for (position, entry) in entries.enumerated() {
                    try Task.checkCancellation()
                    var train = entry.1
                    if !dated { train.date = nil }
                    let ride = try await loadCached([train], country: scope.code).rides.first
                    try Task.checkCancellation()
                    if let ride {
                        answers[position] = ride.route.isResolved
                    } else {
                        missing.append((position, train))
                    }
                }
                guard !missing.isEmpty else { return answers }
                try Task.checkCancellation()
                if graphStore == nil {
                    async let displayNetworkResult = try? await DisplayNetworkCache.shared.network(scope: scope)
                    let inputs = try await SolverInputCache.shared.inputs(scope: scope)
                    let displayNetwork = await displayNetworkResult
                    try Task.checkCancellation()
                    // Availability probes keep the small bound: this store is
                    // built before the solve permit, so a full JP graph here
                    // would coexist with the batch solve's.
                    graphStore = UncheckedGraphStoreBox(store: fallbackGraphStore(
                        inputs: inputs, displayNetwork: displayNetwork,
                        maximumNodes: 100_000))
                    providedInputs = inputs
                }
                guard let graphStore, let inputs = providedInputs else { return answers }
                let pending = missing
                try Task.checkCancellation()
                let solved = try await RouteSolveLimiter.shared.withPermit {
                    var results: [(Int, Bool)] = []
                    results.reserveCapacity(pending.count)
                    for (position, train) in pending {
                        try Task.checkCancellation()
                        let ride = try await solveMissingSequentialWithPermit(
                            [train], scope: scope, allowLegacy: true,
                            graphStore: graphStore.store, providedInputs: inputs,
                            publish: { _ in }, saveRoutes: false).first
                        try Task.checkCancellation()
                        results.append((position, ride?.route.isResolved == true))
                    }
                    return results
                }
                try Task.checkCancellation()
                for (position, value) in solved { answers[position] = value }
                return answers
            }

            let undated = try await resolved(dated: false)
            try Task.checkCancellation()
            // Historical railway can be unavailable undated but valid on the
            // ride date. Always validate the dated snapshot independently.
            let dated = try await resolved(dated: true)
            try Task.checkCancellation()
            return entries.indices.map {
                (entries[$0].0, RouteAvailability(
                    undatedResolved: undated[$0], datedResolved: dated[$0]))
            }
        }

        var result = [RouteAvailability](repeating: .init(
            undatedResolved: false, datedResolved: false), count: datedTrains.count)
        for scope in RouteScope.ordered(byScope.keys) {
            try Task.checkCancellation()
            guard let entries = byScope[scope] else { continue }
            let scoped = try await resolvedScope(scope, entries: entries)
            try Task.checkCancellation()
            for (index, availability) in scoped { result[index] = availability }
        }
        try Task.checkCancellation()
        return result
    }

    /// One journey through the same cache-then-solve path a full load uses.
    ///
    /// `nil` means the journey asked for no sections at all, which the caller
    /// records as `unavailable(expected: 0)` rather than as silence.
    @concurrent private nonisolated static func resolveOne(
        _ train: Train, scope: RouteScope
    ) async throws -> DrawnRide? {
        try Task.checkCancellation()
        guard !train.requiresRouteConfirmation else { return nil }
        let cached = try await loadCached([train], country: scope.code)
        cached.noteCurrentDigests()
        RouteDigestIndexStore.shared.flush()
        if let ride = cached.rides.first { return ride }
        return try await solveMissing(cached.missing, scope: scope, prepared: cached.prepared).first
    }

    /// What each journey the load was asked about ended up with.
    ///
    /// A train that produced no `DrawnRide` at all is recorded as
    /// `unavailable(expected: 0)`: `solveMissing` skips a train whose
    /// canonical section list is empty, and leaving those absent would make
    /// "this journey has nothing to draw" indistinguishable from "this journey
    /// was never looked at".
    private nonisolated static func statusEntries(
        for rides: [DrawnRide], wanted: [String]
    ) -> [String: RouteStatusEntry] {
        var entries: [String: RouteStatusEntry] = [:]
        for ride in rides {
            entries[ride.id] = RouteStatusEntry(
                outcome: ride.route, drawnSegments: ride.segments.count)
        }
        for id in wanted where entries[id] == nil {
            entries[id] = RouteStatusEntry(
                outcome: .unavailable(expected: 0), drawnSegments: 0)
        }
        return entries
    }

    /// Cache, then solve — per region, the same for every journey.
    ///
    /// Bundled examples carry no precomputed geometry of their own. They are
    /// folded into the working set like an imported file and resolved here
    /// like any journey the reader added; every solved route is written to
    /// the per-journey cache, so a relaunch reads instead of solving.
    ///
    /// ## Two phases, and the map is handed the first one
    ///
    /// The cache read is the whole of a warm load and costs ~20 ms for 201
    /// journeys; the solve is the cold one and costs
    /// seconds, because they read a country's `rail-sections*.json` and
    /// `stations*.json` (11.8 MB and 3.2 MB for Japan). Returning one array at
    /// the end meant a single uncached journey held every cached journey off
    /// the map for as long as its country took to read.
    ///
    /// So `publish` is called with everything the cache answered before any
    /// solver input is read, and again as each remaining journey finishes. A warm
    /// load calls it zero times and is byte for byte what it was.
    ///
    /// ## …cheapest scope first, and in a fixed order
    ///
    /// The scopes are walked in ``RouteScope/ordered(_:)``'s order rather than
    /// the grouping dictionary's. Two things come of that. A reader whose
    /// uncached journeys are Taiwanese sees them without waiting for Japan's
    /// datasets to be read for the one Japanese journey behind them. And the
    /// order stops being a per-process accident: Swift seeds dictionary
    /// hashing per launch, so the countries used to be walked differently
    /// every time — and this order is the order the rides reach the map, which
    /// is the order the overlays are added in and therefore which line is
    /// drawn over which.
    @concurrent private nonisolated static func decode(
        wanted: [String: Train], requestedOrder: [String],
        preferredTrainID: String?, primed: DrawnRide? = nil, preread: CacheBatch = CacheBatch(),
        publish: @Sendable ([DrawnRide]) async -> Void = { _ in }
    ) async throws -> [DrawnRide] {
        var result: [DrawnRide] = primed.map { [$0] } ?? []
        preread.noteCurrentDigests()
        var prepared = preread.prepared
        var unresolved: [(
            scope: RouteScope, trains: [Train], graphStore: RouteGraph.RouteGraphStore?,
            providedInputs: SolverInputs?
        )] = []
        var seen: Set<String> = []
        let remaining = requestedOrder.compactMap { id -> Train? in
            guard seen.insert(id).inserted, let train = wanted[id],
                  id != primed?.id, !train.requiresRouteConfirmation else { return nil }
            return train
        }
        // Grouped by SCOPE rather than by region, which for every journey that
        // stays inside one country is the same grouping it always was. A
        // journey that crosses a border forms its own group, so the two
        // packages it needs are loaded once for all the journeys that cross it
        // the same way.
        //
        // Scope home selects the normalization rules and route-cache directory;
        // the canonical key lets compatible scopes reuse the display network.
        // A shared working set never supplies an unevidenced physical edge.
        let byScope = Dictionary(grouping: remaining, by: RouteScope.init)
        // In a fixed order — cheapest scopes first — rather than in the
        // dictionary's. See ``RouteScope/ordered(_:)``: the grouping's own
        // order is seeded per process, so this loop used to walk the countries
        // differently on every launch, and the order rides come back in is the
        // order the map is handed them in and therefore which line is drawn
        // over which.
        for scope in RouteScope.ordered(byScope.keys) where scope.home.isEnabled {
            guard let trains = byScope[scope] else { continue }
            let cached = try await loadCachedConcurrently(trains, country: scope.code, prepared: prepared)
            cached.noteCurrentDigests()
            prepared.merge(cached.prepared) { _, new in new }
            result += cached.rides
            if !cached.missing.isEmpty { unresolved.append((scope, cached.missing, nil, nil)) }
        }
        RouteDigestIndexStore.shared.flush(includeUsage: true)

        // Everything the on-disk cache could answer, on the map before a
        // single dataset is opened.
        //
        // This is the whole of a warm load — 201 journeys read in ~20 ms — and
        // until now it waited behind the cold half regardless. One journey
        // imported yesterday and not yet cached meant the two hundred that
        // WERE cached stayed off the map while its country's solver datasets
        // were read (Japan: 11.8 MB of sections and 3.2 MB of stations), which
        // is a blank map for seconds to draw one line.
        if !unresolved.isEmpty { await publish(result) }

        // Finish the selected journey through every fallback before starting
        // the remaining scopes. Cache hits above still reach the map first.
        if let preferredTrainID,
           let index = unresolved.firstIndex(where: { batch in
               batch.trains.contains { $0.id == preferredTrainID }
           }),
           let preferred = unresolved[index].trains.first(where: { $0.id == preferredTrainID }) {
            let scope = unresolved[index].scope
            async let displayNetworkResult = try? await DisplayNetworkCache.shared.network(scope: scope)
            let inputs = try await SolverInputCache.shared.inputs(scope: scope)
            let displayNetwork = await displayNetworkResult
            let graphStore = fallbackGraphStore(inputs: inputs, displayNetwork: displayNetwork)
            unresolved[index].graphStore = graphStore
            unresolved[index].providedInputs = inputs
            result = try await decodeUncached(
                [preferred], scope: scope, previous: result, graphStore: graphStore,
                providedInputs: inputs, prepared: prepared,
                publish: publish)
            unresolved[index].trains.removeAll { $0.id == preferredTrainID }
            if unresolved[index].trains.isEmpty {
                unresolved[index].graphStore = nil
                unresolved[index].providedInputs = nil
            }
        }

        // All other journeys retain requested order within the ordered scopes.
        for index in unresolved.indices where !unresolved[index].trains.isEmpty {
            let scope = unresolved[index].scope
            let trains = unresolved[index].trains
            if unresolved[index].graphStore == nil {
                async let displayNetworkResult = try? await DisplayNetworkCache.shared.network(scope: scope)
                let inputs = try await SolverInputCache.shared.inputs(scope: scope)
                let displayNetwork = await displayNetworkResult
                unresolved[index].graphStore = fallbackGraphStore(
                    inputs: inputs, displayNetwork: displayNetwork)
                unresolved[index].providedInputs = inputs
            }
            result = try await decodeUncached(
                trains, scope: scope, previous: result,
                graphStore: unresolved[index].graphStore,
                providedInputs: unresolved[index].providedInputs, prepared: prepared, publish: publish)
            unresolved[index].graphStore = nil
            unresolved[index].providedInputs = nil
        }
        return result
    }

    /// The shared inference and solver pipeline after a cache miss.
    @concurrent private nonisolated static func decodeUncached(
        _ trains: [Train], scope: RouteScope, previous: [DrawnRide],
        graphStore: RouteGraph.RouteGraphStore? = nil,
        providedInputs: SolverInputs? = nil,
        prepared: [String: PreparedRoute] = [:],
        publish: @Sendable ([DrawnRide]) async -> Void
    ) async throws -> [DrawnRide] {
        try Task.checkCancellation()
        var result = previous
        var missing = Dictionary(
            trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Every journey — a bundled example or the reader's own — takes this
        // one path: station inference first, then the legacy pass for what
        // inference left. Both passes share this scope's graph and its
        // corridor memos, and every answer lands in the per-journey cache.
        let previous = result
        let inferred = try await solveMissing(
            trains, scope: scope, allowLegacy: false, graphStore: graphStore,
            providedInputs: providedInputs, prepared: prepared) { partial in
                await publish(previous + partial)
            }
        for ride in inferred { missing.removeValue(forKey: ride.id) }
        result += inferred
        if !missing.isEmpty {
            let previous = result
            result += try await solveMissing(
                trains.filter { missing[$0.id] != nil }, scope: scope,
                graphStore: graphStore, providedInputs: providedInputs, prepared: prepared, publish: { partial in
                    await publish(previous + partial)
                })
        }
        return result
    }

    /// Build one drawn ride, deciding its ``RouteOutcome`` from which of the
    /// journey's sections actually came back with geometry.
    ///
    /// The outcome is *derived* rather than stored, which is why the on-disk
    /// route cache needed no new field and no version bump: a cached ride
    /// carries its segments' indices, and the sections it was solved for are
    /// recomputed from the train beside it. A stored copy would be a second
    /// answer that could disagree with the first.
    private nonisolated static func drawnRide(
        _ train: Train,
        country: String,
        segments: [DrawnSegment],
        expectedSections: [RouteSection],
        indicesAreAuthoritative: Bool = true,
        physicalGaps: [PhysicalGap] = [],
        timetableFailure: String? = nil
    ) -> DrawnRide {
        let expected = expectedSections.count
        let recordedMapping = RecordedRouteMapping(stops: train.stops, sections: expectedSections)
        let solved = Set(segments.map(\.segmentIndex))
        var unsolved: [SectionGap] = expectedSections.enumerated()
            .compactMap { index, section in
                solved.contains(index)
                    ? nil
                    : SectionGap(segmentIndex: index, from: section.from, to: section.to)
            }
        for gap in physicalGaps where expectedSections.indices.contains(gap.segmentIndex) {
            let section = expectedSections[gap.segmentIndex]
            let sectionGap = SectionGap(segmentIndex: gap.segmentIndex,
                from: section.from, to: section.to, isBoundary: gap.isBoundary,
                isUnproven: gap.isUnproven)
            if let existing = unsolved.firstIndex(where: { $0.segmentIndex == gap.segmentIndex }) {
                // An interior failure must remain visible even if a boundary was recorded first.
                if unsolved[existing].isBoundary && !gap.isBoundary {
                    unsolved[existing] = sectionGap
                }
            } else {
                unsolved.append(sectionGap)
            }
        }
        let certified = solved.subtracting(physicalGaps.map(\.segmentIndex))
        let outcome: RouteOutcome
        if expected == 0 || unsolved.isEmpty || (!indicesAreAuthoritative && physicalGaps.isEmpty) {
            // `indicesAreAuthoritative` is false for a precomputed part whose
            // features carry no `segment_index`: there the index is the
            // stroke's position, which says nothing about which SECTION it
            // came from, and comparing it against the canonical sections would
            // manufacture gaps that are not there.
            outcome = .resolved
        } else if segments.isEmpty {
            outcome = .unavailable(expected: expected)
        } else {
            outcome = .partial(solved: certified.count, expected: expected, unsolved: unsolved)
        }
        var geometryHasher = Hasher()
        geometryHasher.combine(segments.count)
        geometryHasher.combine(recordedMapping?.sectionStopIntervals)
        geometryHasher.combine(recordedMapping?.stopSectionBoundaries)
        for gap in physicalGaps { geometryHasher.combine(gap.segmentIndex); geometryHasher.combine(gap.isBoundary)
            geometryHasher.combine(gap.isUnproven) }
        for segment in segments {
            geometryHasher.combine(segment.segmentIndex)
            geometryHasher.combine(segment.partIndex)
            geometryHasher.combine(segment.sourceCoordinates)
            geometryHasher.combine(segment.physicalRoute?.intervals)
            for line in segment.physicalRoute?.lines ?? [] {
                geometryHasher.combine(line.lineID)
                geometryHasher.combine(line.name)
                geometryHasher.combine(line.operatorName)
                geometryHasher.combine(line.km)
            }
        }
        var ride = DrawnRide(
            id: train.id,
            trainType: train.trainType,
            country: country,
            colorHex: train.style?.color ?? "#0a84ff",
            visible: train.visible != false,
            segments: segments,
            route: outcome,
            stops: train.stops,
            daySpan: Dates.daySpan(train),
            geometryDigest: geometryHasher.finalize())
        let resourceScope = RouteScope(train).key
        ride.resourceWarnings = [timetableFailure, resourceRevisionFailure(for: resourceScope),
                                 DisplayNetworkCache.shared.resourceRevisionFailure(for: resourceScope)]
            .compactMap { $0 }
            .reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        ride.physicalGaps = physicalGaps
        ride.indicesAreAuthoritative = indicesAreAuthoritative
        ride.expectedSectionCount = expected
        ride.expectedSections = expectedSections
        ride.recordedRouteMapping = recordedMapping
        for segment in segments {
            let old = ride.sectionPartRanges[segment.segmentIndex] ?? segment.partIndex...segment.partIndex
            ride.sectionPartRanges[segment.segmentIndex] = min(old.lowerBound, segment.partIndex)...max(old.upperBound, segment.partIndex)
        }
        return ride
    }

    /// The one normalisation the solver, the cache digest, and the template
    /// digest all read from — computed once per train and passed to whichever
    /// of them needs it, instead of each calling `normalizeExportTrain` again
    /// for a train a caller a few lines up had just normalised.
    private nonisolated static func normalizedTrain(
        _ train: Train, country: String
    ) -> Train {
        RecordedRouteAdmission.applyingCorridorPreference(to: TrainValidation.normalizeExportTrain(
            TrainValidation.restoringRouteSectionEndpointNames(train),
            country: country,
            stations: TrainValidation.StationTable.empty))
    }

    private struct CanonicalRouteInput: Sendable {
        let train: Train
        let databaseSections: Set<Int>
        let databaseProvenance: TimetablePhysicalRouteMatch.Provenance?
        let timetableFailure: String?
    }

    /// Registry ids the solver reads. A pending region leaves the stored train alone.
    nonisolated static func upgradedSolveTrain(_ raw: Train) -> Train {
        BundledRegistry.upgradeIfReady(raw)
    }

    private nonisolated static func canonicalRouteInput(_ raw: Train, country: String) async throws -> CanonicalRouteInput {
        let raw = Self.upgradedSolveTrain(raw)
        var base = TrainValidation.normalizeExportTrain(
            TrainValidation.restoringRouteSectionEndpointNames(raw), country: country,
            stations: TrainValidation.StationTable.empty)
        let originalSections = base.routeSections ?? []
        let match: TimetablePhysicalRouteMatch.Match?
        var timetableFailure: String?
        let interval = RailSignpost.data.begin("route.enrich")
        defer { RailSignpost.data.end("route.enrich", interval) }
        do {
            match = try await TimetableRouteEvidence.enrich(train: raw, country: country, sections: originalSections)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Carry this request's failure with its result while preserving
            // recorded physical sections. Cancellation remains a thrown result.
            timetableFailure = error.localizedDescription
            match = nil
        }
        if let match {
            base.routeSections = match.enrichedRouteSections
            base.date = match.serviceDate
            let added = Set(originalSections.indices.filter { originalSections[$0].sectionCodes?.isEmpty != false })
            return CanonicalRouteInput(train: RecordedRouteAdmission.applyingCorridorPreference(to: base),
                databaseSections: added, databaseProvenance: match.provenance, timetableFailure: nil)
        }
        return CanonicalRouteInput(train: RecordedRouteAdmission.applyingCorridorPreference(to: base),
            databaseSections: [], databaseProvenance: nil, timetableFailure: timetableFailure)
    }

    /// The canonical route sections a journey asks for — the same normalisation
    /// the solver and the cache digest run, so "expected" means the same thing
    /// in all three. Takes the already-normalised train; see
    /// ``normalizedTrain(_:country:)``.
    private nonisolated static func canonicalSections(
        _ canonical: Train
    ) -> [RouteSection] {
        canonical.requiresRouteConfirmation ? [] : canonical.routeSections ?? []
    }

    /// Solve the journeys the cache could not answer for.
    ///
    /// The scope, not a country, because of the three trains that cross the
    /// Canada–United States border. Their stops are split between two packages
    /// — a package says what one country's railways are, and half of the Maple
    /// Leaf is not one of Canada's — so solving one against a single country's
    /// graph can only fail at the crossing. Both countries' sections and
    /// stations are loaded and concatenated instead.
    ///
    /// This is the one place in the app where two countries' solver datasets
    /// are read together, and `app-config.js` is right that doing it carelessly
    /// is dangerous: two networks in one graph let a same-named station in the
    /// wrong country capture a hop. It is safe HERE, and only here, because
    /// (1) it happens only for a journey whose own stops name both regions,
    /// (2) the two graphs are joined only where real track crosses the border,
    /// and (3) the hops are matched on `n02_station_code`, which the North
    /// American build prefixes with the region (`US-…`, `CA-…`) precisely so a
    /// Windsor in Ontario cannot answer for a Windsor in Connecticut.
    /// Bulk loads and single-journey rebuilds share the same CPU budget.
    /// Inference is serial. The legacy pass uses a small set of persistent
    /// workers, each with its own mutable graph store and per-journey limiter permits.
    @concurrent private nonisolated static func solveMissing(
        _ trains: [Train], scope: RouteScope,
        allowLegacy: Bool = true,
        graphStore: RouteGraph.RouteGraphStore? = nil,
        providedInputs: SolverInputs? = nil,
        prepared: [String: PreparedRoute] = [:],
        publish: @Sendable ([DrawnRide]) async -> Void = { _ in }
    ) async throws -> [DrawnRide] {
        guard trains.contains(where: { !$0.requiresRouteConfirmation }) else { return [] }
        let inputs: SolverInputs
        if let providedInputs { inputs = providedInputs }
        else { inputs = try await SolverInputCache.shared.inputs(scope: scope) }
        let graphStoreBox = graphStore.map(UncheckedGraphStoreBox.init)
        let skipped = await awaitScopeRegistry(scope, trains: trains)
        var results: [DrawnRide] = []
        for train in trains where !train.requiresRouteConfirmation && !skipped.contains(train.id) {
            try Task.checkCancellation()
            // The cache read already enriched and digested this journey.
            let routeInput: CanonicalRouteInput
            let digest: String?
            if let known = prepared[train.id], known.train == train, known.registrySettled {
                routeInput = known.input
                digest = known.digest
            } else {
                routeInput = try await canonicalRouteInput(train, country: scope.code)
                digest = await routeCacheDigest(routeInput.train, raw: train, country: scope.code)
            }
            let canonical = routeInput.train
            // Joining happens before admission. Only the producer acquires the
            // sole permit, so a subscriber never holds it while awaiting work.
            let operation: @Sendable () async throws -> [DrawnRide] = {
                try await RouteSolveLimiter.shared.withPermit {
                    try await solveMissingSequentialWithPermit(
                        [train], scope: scope, allowLegacy: allowLegacy,
                        graphStore: graphStoreBox?.store, providedInputs: inputs,
                        providedCanonicalInputs: [routeInput], publish: { _ in }, saveRoutes: false)
                }
            }
            let solved: [DrawnRide]
            var requestTrain = train
            if canonicalSections(canonical).allSatisfy({ $0.from?.isEmpty == false && $0.to?.isEmpty == false }) {
                requestTrain.id = ""
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let digest, let request = try? encoder.encode(requestTrain) {
                solved = try await sharedJourneyWork.value(for: JourneyWorkKey(
                    snapshotID: inputs.snapshotID, scope: scope.key, digest: digest, request: request,
                    allowLegacy: allowLegacy), operation: operation)
            } else { solved = try await operation() }
            try Task.checkCancellation()
            if let shared = solved.first {
                let ride = drawnRide(train, country: scope.code, segments: shared.segments,
                    expectedSections: canonicalSections(canonical), indicesAreAuthoritative: shared.indicesAreAuthoritative,
                    physicalGaps: shared.physicalGaps, timetableFailure: routeInput.timetableFailure)
                results.append(ride)
                if !ride.segments.isEmpty, let digest {
                    try? saveCache(ride, digest: digest, country: scope.code, resourceScope: scope.key)
                }
                await publish(results)
            }
        }
        return results
    }

    /// Between journeys of a long solve: let the rest of the app run, and
    /// back off while the device is hot rather than holding a core flat out.
    private nonisolated static func yieldForDevice() async {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: try? await Task.sleep(for: .milliseconds(250))
        case .critical: try? await Task.sleep(for: .seconds(1))
        default: await Task.yield()
        }
    }

    private struct JourneyWorkKey: Hashable, Sendable {
        let snapshotID: UUID
        let scope: String
        let digest: String
        let request: Data
        let allowLegacy: Bool
    }

    private nonisolated static let sharedJourneyWork = SharedRouteWork<JourneyWorkKey, [DrawnRide]>(
        maxEntries: 64, maxCost: 150_000, cost: { rides in
            let count = rides.reduce(0) { $0 + $1.vertexCount }
            return count > 0 ? count : nil
        })

    struct SharedWorkCounters: Encodable, Sendable {
        let scope = "processLifetime"
        let startedOperations: Int
        let joinedRequests: Int
        let cacheHits: Int
        let completedOperations: Int
        let inFlight: Int
        let subscribers: Int
        let retainedEntries: Int
        let retainedVertices: Int
    }

    nonisolated static func sharedWorkCounters() async -> SharedWorkCounters {
        let value = await sharedJourneyWork.snapshot()
        return SharedWorkCounters(startedOperations: value.startedOperationCount,
            joinedRequests: value.joinedRequestCount, cacheHits: value.cacheHitCount,
            completedOperations: value.completedOperationCount, inFlight: value.inFlightCount,
            subscribers: value.subscriberCount, retainedEntries: value.cachedEntryCount,
            retainedVertices: value.retainedCost)
    }

    /// The legacy coordinator gives this mutable memoized store only to worker
    /// zero. Every other worker constructs its own store from immutable inputs.
    private struct UncheckedGraphStoreBox: @unchecked Sendable {
        let store: RouteGraph.RouteGraphStore
    }

    private struct IndexedJourneyResult: Sendable {
        let index: Int
        let rides: [DrawnRide]
    }

    private actor JourneyWorkQueue {
        private let indices: [Int]
        private var cursor = 0

        init(indices: [Int]) { self.indices = indices }

        func next() -> Int? {
            guard cursor < indices.count else { return nil }
            defer { cursor += 1 }
            return indices[cursor]
        }
    }

    private nonisolated static var maximumJourneyWorkers: Int {
        // Prioritize memory on every device: each worker retains its mutable
        // graph store across journeys, including while waiting for a permit.
        // One worker takes the exact serial path without extra graph stores
        // or completed geometries waiting behind an earlier journey.
        1
    }

    private typealias SolverInputs = RideRouteResolution.SourceInputs

    /// Immutable source/history inputs are shared by edits and batch loads.
    /// Mutable graphs stay private to one sequential worker. Completed inputs
    /// keep ``ResourceProfile/countryCacheSlots`` slots (one on a compact
    /// device); with two, the Japan-only scope is never the one evicted.
    private actor SolverInputCache {
        static let shared = SolverInputCache()
        /// Completed inputs, oldest first, at most ``slotCount``.
        private var completed: [(key: String, inputs: SolverInputs)] = []
        private let slotCount = ResourceProfile.current.countryCacheSlots
        private static let pinnedScopeKey = RouteScope(regions: [.jp]).key
        // Independent admission avoids nesting the global route/display permit.
        private let decodeLimiter = RouteSolveLimiter(limit: 1)
        private var running: [String: Task<SolverInputs, Error>] = [:]
        private var indexes: [String: RideRouteResolution.NetworkInputs] = [:]
        private var intervalIndexes: [String: RideRouteResolution.OfficialIntervals] = [:]

        /// Only the legacy fallback reads the official interval index, and
        /// building it is the largest single cost of a cold load (~1.8 s for
        /// Japan on a Mac). Sections with recorded physical intervals never
        /// pay for it.
        func officialIntervals(
            scope: RouteScope, inputs: SolverInputs
        ) -> RideRouteResolution.OfficialIntervals {
            let revision = RiddenRouteStore.resourceRevisions?.revision(for: scope.key) ?? "unversioned"
            let key = scope.key + ":" + revision
            if let ready = intervalIndexes[key] { return ready }
            if intervalIndexes.count >= 2 { intervalIndexes.removeAll() }
            let owner = inputs.officialIntervals
            intervalIndexes[key] = owner
            return owner
        }

        func networkIndexes(
            scope: RouteScope, network: RouteNetwork, inputs: SolverInputs
        ) -> RideRouteResolution.NetworkInputs {
            let revision = RiddenRouteStore.resourceRevisions?.revision(for: scope.key) ?? "unversioned"
            let key = scope.key + ":" + revision
            if let ready = indexes[key] { return ready }
            let built = RideRouteResolution.NetworkInputs(network: network, inputs: inputs)
            if indexes.count >= 2 { indexes.removeAll() }
            indexes[key] = built
            return built
        }

        private nonisolated static func isPinned(_ key: String) -> Bool {
            key.hasPrefix(pinnedScopeKey + ":")
        }

        /// Frees a slot before a decode allocates its replacement: with one
        /// slot the completed inputs are dropped, as before; with two, the
        /// oldest that is not Japan's goes first.
        private func releaseCompleted() {
            while !completed.isEmpty, completed.count >= slotCount {
                let victim = completed.firstIndex { !Self.isPinned($0.key) } ?? 0
                completed.remove(at: victim)
            }
        }

        /// Forces fresh solves from the retained inputs without re-decoding.
        func clearResolutionMemo() {
            for entry in completed { entry.inputs.clearResolutionMemo() }
            // The network indexes carry the station-interval memo; they are
            // cheap to rebuild next to the decoded inputs that stay.
            indexes.removeAll()
        }

        /// Drops the completed inputs and their derived indexes. In-flight
        /// decodes keep running, and their callers keep their own copies.
        func releaseForMemoryPressure() {
            completed.removeAll()
            indexes.removeAll()
            intervalIndexes.removeAll()
        }

        private func retain(_ inputs: SolverInputs, key: String) {
            completed.removeAll { $0.key == key }
            completed.append((key, inputs))
            while completed.count > slotCount {
                let victim = completed.firstIndex { !Self.isPinned($0.key) && $0.key != key } ?? 0
                completed.remove(at: victim)
            }
        }

        func inputs(scope: RouteScope) async throws -> SolverInputs {
            try Task.checkCancellation()
            let revision = RiddenRouteStore.resourceRevisions?.revision(for: scope.key) ?? "unversioned"
            let key = scope.key + ":" + revision
            if let ready = completed.first(where: { $0.key == key }) { return ready.inputs }
            if let task = running[key] {
                let inputs = try await task.value
                try Task.checkCancellation()
                return inputs
            }
            let limiter = decodeLimiter
            let task = Task.detached(priority: .userInitiated) {
                try await limiter.withPermit {
                    await self.releaseCompleted()
                    let inputs = try RiddenRouteStore.prepareSolverInputs(scope: scope)
                    // Publish before releasing admission; late waiters never
                    // restore an older country beside its replacement decode.
                    await self.retain(inputs, key: key)
                    return inputs
                }
            }
            running[key] = task
            do {
                let inputs = try await task.value
                if running[key] == task { running[key] = nil }
                try Task.checkCancellation()
                return inputs
            } catch {
                if running[key] == task { running[key] = nil }
                throw error
            }
        }
    }

    private nonisolated static func prepareSolverInputs(scope: RouteScope) throws -> SolverInputs {
        var sections: [RouteGraph.SectionFeature] = []
        var stationFeatures: [Stations.Feature] = []
        var identityPeriods: [RailHistoryOverlay.IdentityPeriod] = []
        // In the CATALOG's order, not the ride's — see
        // ``RouteScope/graphRegions``. `Stations.Index` resolves an ambiguous
        // NAME to the first feature carrying it, so the two directions of the
        // same crossing would otherwise pick opposite sides of the border for
        // a section that names a station without a code. The same track, asked
        // about twice, has to answer the same.
        for region in scope.graphRegions {
            try Task.checkCancellation()
            guard let sectionsURL = Bundle.main.url(
                forResource: Region.countrySuffixed("rail-sections", country: region.code),
                withExtension: "json"),
                  let stationsURL = Bundle.main.url(
                    forResource: Region.countrySuffixed("stations", country: region.code),
                    withExtension: "json")
            else { throw LoadError.missingSolverResources(region.code) }
            var regionSections = try RouteGraph.SectionFeatureCollection
                .load(contentsOf: sectionsURL).features
            var regionStations = try Stations.FeatureCollection
                .load(contentsOf: stationsURL).features
            // ADR 0011: fold the region's dated history overlay in before the
            // graph and the station-transfer connectors see the features.
            try applyRailHistory(
                region: region.code, sections: &regionSections, stations: &regionStations)
            if case .loaded(let overlay, _) = historyState(region: region.code) {
                identityPeriods.append(contentsOf: overlay.identityPeriods)
            }
            sections += regionSections
            stationFeatures += regionStations
        }
        let stationCollection = Stations.FeatureCollection(features: stationFeatures)
        guard let registryURL = Bundle.main.url(forResource: "physical-rail-junctions", withExtension: "json") else {
            throw LoadError.missingSolverResources("physical-rail-junctions")
        }
        let registry = try cachedJunctionRegistry(at: registryURL)
        let junctions = scope.regions.flatMap { registry.junctions(for: $0.code) }
        return SolverInputs(sections: sections, stationCollection: stationCollection,
                            physicalJunctions: junctions,
                            identityPeriods: identityPeriods)
    }

    #if RAIL_DIAGNOSTICS
    enum DiagnosticGraphCacheConfiguration: Sendable {
        case standard
        case bounded(maximumNodes: Int)

        nonisolated var mode: String {
            switch self {
            case .standard: "standard"
            case .bounded: "bounded"
            }
        }
        nonisolated var maximumNodesDescription: String {
            switch self {
            case .standard: "not-applicable"
            case .bounded(let nodes): String(nodes)
            }
        }
        nonisolated var policy: RouteGraph.GraphCachePolicy {
            switch self {
            case .standard: .standard
            case .bounded(let nodes): .bounded(maximumNodes: nodes)
            }
        }
    }

    /// Select existing cache behavior for one explicitly requested diagnostic run.
    /// Without options the bounded policy uses the device profile's load
    /// budget, as shipping builds do.
    nonisolated static func diagnosticGraphCacheConfiguration(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) throws -> DiagnosticGraphCacheConfiguration {
        func invalid(_ message: String) -> NSError {
            NSError(domain: "RailDiagnostics", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        func value(for flag: String) throws -> String? {
            let matches = arguments.indices.filter { arguments[$0] == flag }
            guard !matches.isEmpty else { return nil }
            guard matches.count == 1, let index = matches.first,
                  arguments.indices.contains(index + 1) else {
                throw invalid("\(flag) requires exactly one value.")
            }
            return arguments[index + 1]
        }
        let modeFlag = "--diagnostic-graph-cache-mode"
        let nodesFlag = "--diagnostic-graph-cache-nodes"
        let mode = try value(for: modeFlag) ?? "bounded"
        let nodeValue = try value(for: nodesFlag)
        guard mode == "standard" || mode == "bounded" else {
            throw invalid("\(modeFlag) requires standard or bounded.")
        }
        if mode == "standard" {
            guard nodeValue == nil else {
                throw invalid("\(nodesFlag) cannot be used with standard graph cache mode.")
            }
            return .standard
        }
        guard let nodeValue else {
            return .bounded(maximumNodes: ResourceProfile.current.regionalGraphLoadNodeBudget)
        }
        guard let nodes = Int(nodeValue), (1...2_000_000).contains(nodes) else {
            throw invalid("\(nodesFlag) requires one integer between 1 and 2000000.")
        }
        return .bounded(maximumNodes: nodes)
    }
    #endif

    private nonisolated static func fallbackGraphStore(
        inputs: SolverInputs, displayNetwork: RouteNetwork?,
        maximumNodes: Int = ResourceProfile.current.regionalGraphLoadNodeBudget
    ) -> RouteGraph.RouteGraphStore {
        let sections = inputs.sections
        #if RAIL_DIAGNOSTICS
        // Request admission reports malformed options before a route batch starts.
        let cachePolicy = (try? diagnosticGraphCacheConfiguration())?.policy
            ?? .bounded(maximumNodes: maximumNodes)
        #else
        // Trade-off: the budget admits the full JP graph (~377k nodes, a few
        // hundred MB) for the life of this batch store (one scope; it is
        // dropped after the scope), raising transient peak memory in exchange
        // for not rebuilding that graph on every full-graph fallback.
        let cachePolicy = RouteGraph.GraphCachePolicy.bounded(
            maximumNodes: maximumNodes)
        #endif
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway, junctions: inputs.physicalJunctions,
            cachePolicy: cachePolicy,
            identityPeriods: inputs.identityPeriods, sourceSnapshotID: inputs.snapshotID)
        return graphStore
    }

    /// Production uses one worker to bound retained graph memory. Keep the
    /// parallel implementation dormant; W=1 takes exactly the serial path,
    /// with no task group, additional graph stores or completion backlog.
    @concurrent private nonisolated static func solveMissingConcurrently(
        _ trains: [Train], scope: RouteScope,
        graphStore: UncheckedGraphStoreBox?,
        providedInputs: SolverInputs?,
        publish: @Sendable ([DrawnRide]) async -> Void
    ) async throws -> [DrawnRide] {
        let indices = trains.indices.filter { !trains[$0].requiresRouteConfirmation }
        guard !indices.isEmpty else { return [] }
        let workerCount = min(maximumJourneyWorkers, indices.count)
        if workerCount == 1 {
            return try await RouteSolveLimiter.shared.withPermit {
                try await solveMissingSequentialWithPermit(
                    trains, scope: scope, allowLegacy: true, graphStore: graphStore?.store,
                    providedInputs: providedInputs, publish: publish)
            }
        }
        let queue = JourneyWorkQueue(indices: indices)
        let inputs: SolverInputs
        if let providedInputs { inputs = providedInputs }
        else { inputs = try await SolverInputCache.shared.inputs(scope: scope) }
        let displayNetwork = try? await DisplayNetworkCache.shared.network(scope: scope)
        let (completions, completionChannel) = AsyncThrowingStream<IndexedJourneyResult, Error>
            .makeStream()
        var finished: [Int: IndexedJourneyResult] = [:]
        var nextIndex = indices[0]
        var rides: [DrawnRide] = []

        return try await withThrowingTaskGroup(of: Void.self) { group in
            for workerIndex in 0..<workerCount {
                group.addTask {
                    do {
                        let workerStore = UncheckedGraphStoreBox(store: workerIndex == 0
                            ? graphStore?.store
                                ?? fallbackGraphStore(inputs: inputs, displayNetwork: displayNetwork)
                            : fallbackGraphStore(inputs: inputs, displayNetwork: displayNetwork))
                        while let index = await queue.next() {
                            try Task.checkCancellation()
                            let solved = try await RouteSolveLimiter.shared.withPermit {
                                let solved = try await solveMissingSequentialWithPermit(
                                    [trains[index]], scope: scope, allowLegacy: true,
                                    graphStore: workerStore.store, providedInputs: inputs,
                                    publish: { _ in }, saveRoutes: false)
                                return solved
                            }
                            completionChannel.yield(
                                IndexedJourneyResult(index: index, rides: solved))
                        }
                    } catch {
                        completionChannel.finish(throwing: error)
                        throw error
                    }
                }
            }

            var iterator = completions.makeAsyncIterator()
            for _ in indices {
                try Task.checkCancellation()
                guard let completed = try await iterator.next() else {
                    throw CancellationError()
                }
                finished[completed.index] = completed
                while let result = finished.removeValue(forKey: nextIndex) {
                    try Task.checkCancellation()
                    if let ride = result.rides.first {
                        let train = trains[nextIndex]
                        let canonical = try await canonicalRouteInput(train, country: scope.code).train
                        if !ride.segments.isEmpty,
                           let digest = await routeCacheDigest(canonical, raw: train, country: scope.code) {
                            try? saveCache(
                                ride, digest: digest, country: scope.code, resourceScope: scope.key)
                        }
                        rides.append(ride)
                        try Task.checkCancellation()
                        await publish(rides)
                    }
                    nextIndex += 1
                    while nextIndex < trains.count, trains[nextIndex].requiresRouteConfirmation {
                        nextIndex += 1
                    }
                }
            }
            group.cancelAll()
            completionChannel.finish()
            try await group.waitForAll()
            return rides
        }
    }

    @concurrent private nonisolated static func solveMissingSequentialWithPermit(
        _ trains: [Train], scope: RouteScope,
        allowLegacy: Bool,
        graphStore: RouteGraph.RouteGraphStore? = nil,
        providedInputs: SolverInputs? = nil,
        providedCanonicalInputs: [CanonicalRouteInput]? = nil,
        publish: @Sendable ([DrawnRide]) async -> Void,
        saveRoutes: Bool = true
    ) async throws -> [DrawnRide] {
        guard trains.contains(where: { !$0.requiresRouteConfirmation }) else { return [] }
        let country = scope.code
        async let displayNetworkResult = try? await DisplayNetworkCache.shared.network(scope: scope)
        let inputs: SolverInputs
        if let providedInputs { inputs = providedInputs }
        else { inputs = try await SolverInputCache.shared.inputs(scope: scope) }
        let displayNetwork = await displayNetworkResult
        let preparedNetwork: RideRouteResolution.NetworkInputs?
        if let displayNetwork {
            preparedNetwork = await SolverInputCache.shared.networkIndexes(
                scope: scope, network: displayNetwork, inputs: inputs)
        } else { preparedNetwork = nil }
        let skipped = await awaitScopeRegistry(scope, trains: trains)
        let officialIntervals = await SolverInputCache.shared.officialIntervals(scope: scope, inputs: inputs)
        var resolver = RideRouteResolution(inputs: inputs, country: country, network: preparedNetwork,
            officialIntervals: officialIntervals, graphStore: graphStore)

        var rides: [DrawnRide] = []
        precondition(providedCanonicalInputs == nil || providedCanonicalInputs?.count == trains.count)
        for (trainIndex, train) in trains.enumerated() {
            try Task.checkCancellation()
            guard !train.requiresRouteConfirmation, !skipped.contains(train.id) else { continue }
            await yieldForDevice()
            let routeInput: CanonicalRouteInput
            if let prepared = providedCanonicalInputs {
                routeInput = prepared[trainIndex]
            } else {
                routeInput = try await canonicalRouteInput(train, country: country)
            }
            let canonical = routeInput.train
            let result = try resolver.resolve(.init(train: train, canonicalTrain: canonical,
                databaseSections: routeInput.databaseSections, databaseProvenance: routeInput.databaseProvenance),
                allowLegacy: allowLegacy)
            switch result.disposition {
            case .unsupported, .awaitingConfirmation, .noSections: continue
            case .geometry, .unavailable: break
            }
            let segments = try result.segments.map { part in
                try Task.checkCancellation()
                return DrawnSegment(segmentIndex: part.segmentIndex, partIndex: part.partIndex,
                    from: part.from, to: part.to, coordinates: part.drawnCoordinates,
                    sourceCoordinates: part.sourceCoordinates, country: country,
                    historyIDs: part.historyIDs, validFrom: part.validFrom, validTo: part.validTo,
                    temporalKind: part.temporalKind, physicalRoute: part.physicalRoute)
            }
            // Native datum/bounds work precedes the cache-write cancellation fence.
            try Task.checkCancellation()
            // Emitted even when NOTHING solved. The old code appended only
            // `if !segments.isEmpty`, which is how a journey with no drawable
            // route became a journey the interface had never heard of — and a
            // ride that is absent cannot be told from a ride that is still
            // being solved. It is reported as `unavailable` instead.
            let ride = drawnRide(
                train, country: country, segments: segments, expectedSections: result.expectedSections,
                physicalGaps: result.physicalGaps, timetableFailure: routeInput.timetableFailure)
            rides.append(ride)
            if saveRoutes, !segments.isEmpty,
               let digest = await routeCacheDigest(canonical, raw: train, country: country) {
                try? saveCache(ride, digest: digest, country: country, resourceScope: scope.key)
            }
            try Task.checkCancellation()
            await publish(rides)
        }
        return rides
    }

    private nonisolated static let routesLog = Logger(subsystem: "com.JRM.RailMap", category: "routes")

    private nonisolated static func railHistoryURL(region: String) -> URL? {
        Bundle.main.url(
            forResource: Region.countrySuffixed("rail-history", country: region),
            withExtension: "json")
    }

    private enum RailHistoryLoadState: Sendable {
        case absent
        case loaded(RailHistoryOverlay, contentHash: String)
        case invalid(String)
    }

    private nonisolated static let historyStateCache = OSAllocatedUnfairLock(
        initialState: [String: RailHistoryLoadState]())

    private nonisolated static func historyState(region: String) -> RailHistoryLoadState {
        if let cached = historyStateCache.withLock({ $0[region] }) { return cached }
        let state: RailHistoryLoadState
        if let url = railHistoryURL(region: region) {
            do {
                let data = try Data(contentsOf: url)
                // One decoded overlay per file: `cachedHistoryOverlay` serves
                // the edge index and journey admission from the same entry.
                let overlay: RailHistoryOverlay
                if let shared = overlayByURLCache.withLock({ $0[url] }) {
                    overlay = shared
                } else {
                    overlay = try RailHistoryOverlay.decode(data)
                    overlayByURLCache.withLock { $0[url] = overlay }
                }
                let hash = SHA256.hash(data: data).hex
                state = .loaded(overlay, contentHash: hash)
            }
            catch { state = .invalid(String(describing: error)) }
        } else {
            state = .absent
        }
        historyStateCache.withLock { $0[region] = state }
        return state
    }

    /// The bundled junction registry is ~10 MB of JSON and immutable for the
    /// process lifetime, so decode it once per URL. Failures are not cached.
    private nonisolated static let junctionRegistryCache = OSAllocatedUnfairLock(
        initialState: [URL: PhysicalRailJunctionRegistry]())

    private nonisolated static func cachedJunctionRegistry(
        at url: URL
    ) throws -> PhysicalRailJunctionRegistry {
        if let cached = junctionRegistryCache.withLock({ $0[url] }) { return cached }
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf: url))
        junctionRegistryCache.withLock { $0[url] = registry }
        return registry
    }

    /// Decoded `rail-history*.json` overlay shared by callers outside the
    /// store (edge index, journey admission). Bundled files never change at
    /// runtime; failures are rethrown uncached so error behaviour is unchanged.
    private nonisolated static let overlayByURLCache = OSAllocatedUnfairLock(
        initialState: [URL: RailHistoryOverlay]())

    /// Releases the process-lifetime decodes this store keeps for speed:
    /// solver inputs and their indexes, the junction registry and the
    /// history overlays, and the historical-line probe's regional graph. Every
    /// one is a pure memo of a bundled file, so the
    /// next use decodes it again with the same answer. Called on a memory
    /// warning, when keeping them risks the process rather than a reload.
    nonisolated static func releaseCachesForMemoryPressure() async {
        junctionRegistryCache.withLock { $0.removeAll() }
        overlayByURLCache.withLock { $0.removeAll() }
        historyStateCache.withLock { $0.removeAll() }
        ProbeGraphCache.shared.clear()
        await SolverInputCache.shared.releaseForMemoryPressure()
    }

    nonisolated static func cachedHistoryOverlay(from url: URL) throws -> RailHistoryOverlay {
        if let cached = overlayByURLCache.withLock({ $0[url] }) { return cached }
        let overlay = try RailHistoryOverlay.load(from: url)
        overlayByURLCache.withLock { $0[url] = overlay }
        return overlay
    }

    private enum LatestValidFromState: Sendable {
        case none
        case value(String)
    }

    private nonisolated static let latestValidFromCache = OSAllocatedUnfairLock(
        initialState: [String: LatestValidFromState]())

    /// The newest possible opening bounds whether an older date can differ from today.
    nonisolated static func latestValidFrom(region: String) throws -> String? {
        if let cached = latestValidFromCache.withLock({ $0[region] }) {
            if case .value(let value) = cached { return value }
            return nil
        }
        var values: [String] = []
        func append(_ value: String?) {
            guard let value, Dates.normalizeDateString(value) == value else { return }
            values.append(value)
        }
        if case .invalid(let reason) = historyState(region: region) {
            throw LoadError.invalidHistory(region, reason)
        }
        if case .loaded(let overlay, _) = historyState(region: region) {
            for section in overlay.sections { append(section.properties.validFrom) }
            for station in overlay.stations { append(Stations.stationValidFrom(station)) }
            for retirement in overlay.retirements {
                let bounds = RailServiceValidity.bounds(
                    service: retirement.serviceValidity,
                    infrastructure: retirement.infrastructureValidity,
                    validFrom: retirement.validFrom, validTo: retirement.validTo,
                    hasLegacy: retirement.validFrom != nil || retirement.validTo != nil)
                append(bounds.0)
            }
            for period in overlay.identityPeriods {
                append(period.validFrom)
                // The following identity starts when this historical one ends.
                append(period.validTo)
            }
        }
        if region == Region.jp.code {
            let catalog = try JapanThroughServices.loadBundled()
            for pattern in catalog.patterns {
                append(pattern.validFrom)
                for leg in pattern.legs { append(leg.validFrom) }
                for variant in pattern.legVariants ?? [] { append(variant.validFrom) }
            }
            for connector in catalog.connectors { append(connector.validFrom) }
        }
        guard let url = Bundle.main.url(forResource: "physical-rail-junctions", withExtension: "json") else {
            throw LoadError.missingSolverResources("physical-rail-junctions")
        }
        let registry = try cachedJunctionRegistry(at: url)
        for junction in registry.junctions(for: region) { append(junction.validFrom) }
        let latest = values.max()
        latestValidFromCache.withLock {
            $0[region] = latest.map(LatestValidFromState.value)
                ?? LatestValidFromState.none
        }
        return latest
    }

    /// Stamp history before any graph or station index is built. A broken
    /// bundled overlay is a load error, never a current-only solve.
    private nonisolated static func applyRailHistory(
        region: String,
        sections: inout [RouteGraph.SectionFeature],
        stations: inout [Stations.Feature]
    ) throws {
        let overlay: RailHistoryOverlay
        switch historyState(region: region) {
        case .absent: return
        case .loaded(let value, _): overlay = value
        case .invalid(let reason): throw LoadError.invalidHistory(region, reason)
        }
        let report = RailHistory.apply(overlay, sections: &sections, stations: &stations)
        routesLog.info(
            "rail-history \(region, privacy: .public) rev \(overlay.revision, privacy: .public): +\(report.sectionsAdded) sections, +\(report.stationsAdded) stations, \(report.retirementsApplied.count) retirements applied")
        if !report.unmatchedRetirements.isEmpty {
            throw LoadError.invalidHistory(
                region, "unmatched retirements: \(report.unmatchedRetirements.joined(separator: ", "))")
        }
    }

    private nonisolated static func railHistoryRevision(region: String) -> String? {
        if case .loaded(let overlay, _) = historyState(region: region) { return overlay.revision }
        return nil
    }

    private nonisolated static let retiredStationsCache = OSAllocatedUnfairLock(
        initialState: [String: [RetiredStation]]())

    /// ADR 0011 overlay stations as a picker directory; [] when the region has
    /// no overlay or it failed to load. Built once per region.
    nonisolated static func retiredStations(region: String) -> [RetiredStation] {
        if let cached = retiredStationsCache.withLock({ $0[region] }) { return cached }
        let stations: [RetiredStation]
        if case .loaded(let overlay, _) = historyState(region: region) {
            stations = RailHistoryStations.directory(overlay)
        } else {
            stations = []
        }
        retiredStationsCache.withLock { $0[region] = stations }
        return stations
    }

    private nonisolated static func historyRevisionSet(for train: Train) -> RailHistoryRevisionSet? {
        let regions = RouteScope(train).graphRegions
        guard regions.allSatisfy({ region in
            if case .invalid = historyState(region: region.code) { return false }
            return true
        }) else { return nil }
        let hashes = Dictionary(uniqueKeysWithValues: regions.compactMap { region -> (String, String)? in
            if case .loaded(_, let hash) = historyState(region: region.code) {
                return (region.code, hash)
            }
            return nil
        })
        return RailHistoryRevisionSet(Dictionary(uniqueKeysWithValues:
            regions.map { ($0.code, railHistoryRevision(region: $0.code)) }), contentHashes: hashes)
    }

    @TaskLocal nonisolated static var activePendingOwner: PendingSolveOwner?

    let pendingSolveOwner = PendingSolveOwner()

    func bindPendingOwner() {
        pendingSolveOwner.store = self
        PendingSolveRegistry.register(pendingSolveOwner)
    }

    /// Replay only the ids this store had waiting on the settled region.
    /// The train is upgraded before `resolve`, because the itinerary publish
    /// that fills memory is a separate task.
    func replayPending(_ ids: [String]) {
        for id in ids where requestedOrder.contains(id) {
            guard var train = completedInputs[id] ?? loadingInputs?[id] else { continue }
            train = Self.upgradedSolveTrain(train)
            if completedInputs[id] != nil { completedInputs[id] = train }
            if var loading = loadingInputs, loading[id] != nil {
                loading[id] = train
                loadingInputs = loading
            }
            resolve(train)
        }
    }

    /// Waits out a pending registry before a production solve. A waiting solve
    /// always solves after the settle itself; the replay never claims it.
    /// Returns the ids to skip, which is always empty now and kept for callers.
    private nonisolated static func awaitScopeRegistry(_ scope: RouteScope, trains: [Train]) async -> Set<String> {
        let owner = activePendingOwner
        for train in trains where !train.requiresRouteConfirmation {
            let pendingRegions = Set(RouteScope(train).graphRegions.compactMap { region -> String? in
                if case .pending = RegistryIdentityLookup.phase(forRegion: region.code) {
                    return region.code.lowercased()
                }
                return nil
            })
            if !pendingRegions.isEmpty {
                owner?.noteAwaiting(id: train.id, regions: pendingRegions)
            }
        }
        for region in scope.graphRegions {
            _ = await SolverRegistryInput.awaitReady(region: region.code)
        }
        if let owner {
            for train in trains where !train.requiresRouteConfirmation {
                owner.finishAwaiting(id: train.id)
                // Settled without a registry: remember it so a later settle can replay it.
                let missing = Set(RouteScope(train).graphRegions.compactMap { region -> String? in
                    if case .ready = RegistryIdentityLookup.phase(forRegion: region.code) { return nil }
                    return region.code.lowercased()
                })
                if !missing.isEmpty { owner.noteSolvedUnavailable(id: train.id, regions: missing) }
            }
        }
        return []
    }

    private nonisolated static func routeCacheDigest(
        _ canonical: Train, raw: Train, country: String
    ) async -> String? {
        let interval = RailSignpost.data.begin("route.digest")
        defer { RailSignpost.data.end("route.digest", interval) }
        let canonicalSections = canonical.routeSections ?? []
        let sections = canonicalSections.map(RouteGraph.RouteSection.init)
        let policy = canonical.routePolicy
        guard let history = historyRevisionSet(for: raw) else { return nil }
        let cacheTrain = RouteGraph.CacheKeyTrain(
            // id/number/origin/destination/trainType come from the raw train,
            // matching the inputs `routeContext(train)` uses to solve — the
            // fields normalization only re-shapes (`trainType ?? ""`) rather
            // than actually changes. `company` stays on the normalized train
            // because `normalizeTrainCompany` can genuinely alter its value.
            id: raw.id, number: raw.number,
            trainType: raw.trainType ?? "", company: canonical.company ?? "",
            origin: raw.origin, destination: raw.destination,
            preferredLineNames: policy?.preferredLineNames ?? [],
            preferredOperatorNames: policy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: policy?.allowedInstitutionTypeCodes,
            institutionFilterMode: policy?.institutionFilterMode,
            operatorID: raw.operatorID ?? canonical.operatorID,
            operatorIDs: raw.operatorIDs ?? canonical.operatorIDs ?? [])
        guard let context = await RouteGraph.solveContextAwaitingRegistry(
            train: cacheTrain, routeSections: sections, country: country,
            rideDate: Dates.normalizeDateString(canonical.date),
            historyRevision: history.canonical) else { return nil }
        let digest = RouteGraph.keyDigest(context.cacheKey)
        // Endpoint names may be restored later from the station snapshot. Until
        // then an id-derived service constraint must not alias another record.
        if canonicalSections.contains(where: { $0.from?.isEmpty != false || $0.to?.isEmpty != false }),
           let bytes = try? JSONEncoder().encode([digest, raw.id]) {
            return SHA256.hash(data: bytes).hex
        }
        return digest
    }

    /// A journey's canonical input and digest, computed once by the cache read
    /// that missed and reused by the solve that follows it.
    private struct PreparedRoute: Sendable {
        /// The raw train these were computed for; reuse requires equality.
        let train: Train
        let input: CanonicalRouteInput
        let digest: String?
        /// Every graph region's registry had settled before `input` was
        /// computed, so the solve's own post-settle canonicalisation would
        /// produce the same value.
        let registrySettled: Bool
    }

    private enum CacheRead: Sendable {
        case hit(DrawnRide, digest: String)
        case miss(PreparedRoute?, digest: String?)
    }

    /// What a batch of cache reads answered, plus what the misses already
    /// computed and every digest the batch resolved.
    private struct CacheBatch: Sendable {
        var rides: [DrawnRide] = []
        var missing: [Train] = []
        var prepared: [String: PreparedRoute] = [:]
        var digests: [String: String] = [:]

        mutating func append(_ read: CacheRead, for train: Train) {
            switch read {
            case .hit(let ride, let digest):
                rides.append(ride)
                digests[train.id] = digest
            case .miss(let route, let digest):
                missing.append(train)
                if let route { prepared[train.id] = route }
                if let digest { digests[train.id] = digest }
            }
        }

        /// Marks these digests as the current working set's, which the
        /// route-cache sweep never evicts. Only load and resolve batches call
        /// this; availability probes read altered trains.
        func noteCurrentDigests() {
            for (id, digest) in digests { CurrentRouteDigests.shared.note(id: id, digest: digest) }
        }
    }

    private nonisolated static func loadCached(
        _ trains: [Train], country: String, prepared: [String: PreparedRoute] = [:]
    ) async throws -> CacheBatch {
        var batch = CacheBatch()
        for train in trains {
            batch.append(try await readCached(train, country: country, prepared: prepared[train.id]), for: train)
        }
        return batch
    }

    /// The same answer, reading several journeys' cache files at once.
    ///
    /// One journey is one small file, and 201 of them read one after another
    /// is the whole of a warm load: measured over the shipped sample's 201
    /// parts — the same count and shape as the cache files — reading and
    /// decoding them takes **58.4 ms sequentially and 25.3 ms four at a time**
    /// (`ios/tools/bench`, release, Apple silicon), against 4.7 ms for all 201
    /// cache digests. The files are independent, so the sequence was the only
    /// thing making this slow.
    ///
    /// Four rather than "as many as there are", and the reason is memory
    /// rather than politeness: each task holds one file's bytes and its
    /// decoded coordinates at once, and a journey the length of a whole
    /// Shinkansen run is not small. Four keeps the flash busy — the measured
    /// step from four to eight is a further 5 ms — without holding two hundred
    /// decodes in the air.
    ///
    /// **The order is the sequential version's, not the scheduler's.** Results
    /// are placed by index and read back in order, so this returns exactly
    /// what the loop returned — including which journeys land in `missing`,
    /// and in what order. Appending as answers arrived would have made the
    /// order a property of which file the filesystem happened to finish first,
    /// and that order reaches the map: it is the order the overlays are added
    /// in, and therefore which line is drawn over which.
    private nonisolated static func loadCachedConcurrently(
        _ trains: [Train], country: String, prepared: [String: PreparedRoute] = [:]
    ) async throws -> CacheBatch {
        guard trains.count > 1 else {
            return try await loadCached(trains, country: country, prepared: prepared)
        }
        let interval = RailSignpost.data.begin("route.cacheRead")
        defer { RailSignpost.data.end("route.cacheRead", interval) }
        var found = [CacheRead?](repeating: nil, count: trains.count)
        try await withThrowingTaskGroup(of: (Int, CacheRead).self) { group in
            var next = 0
            func addNext() {
                guard next < trains.count else { return }
                let position = next
                let train = trains[position]
                let known = prepared[train.id]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    return (position, try await readCached(train, country: country, prepared: known))
                }
            }
            for _ in 0..<Swift.min(cacheReadWidth, trains.count) { addNext() }
            while let (position, read) = try await group.next() {
                found[position] = read
                addNext()
            }
        }
        var batch = CacheBatch()
        for (position, read) in found.enumerated() {
            batch.append(read ?? .miss(nil, digest: nil), for: trains[position])
        }
        return batch
    }

    /// How many cache files are read at once. See ``loadCachedConcurrently``.
    private nonisolated static let cacheReadWidth = 4

    /// Assigns each item a `partIndex`: its occurrence count, so far, among
    /// items sharing its `segmentIndex` — counted in the order `items`
    /// already comes in.
    ///
    /// Both the live dataset path and ``readCached`` need the SAME rule here
    /// (a per-`segmentIndex` counter over parts actually emitted, in output
    /// order), or the two can disagree on which cached entry is which part:
    /// a short part dropped upstream, a feature with no authoritative
    /// `segment_index` restarting its own count, or two features sharing a
    /// `segmentIndex` would each desynchronise the two paths if they counted
    /// differently.
    private nonisolated static func assigningPartIndex<Item>(
        to items: [Item], segmentIndex: (Item) -> Int
    ) -> [(item: Item, partIndex: Int)] {
        var nextPartIndex: [Int: Int] = [:]
        return items.map { item in
            let index = segmentIndex(item)
            let partIndex = nextPartIndex[index, default: 0]
            nextPartIndex[index] = partIndex + 1
            return (item, partIndex)
        }
    }

    /// One journey's cached route, or a miss carrying whatever the read
    /// computed on the way.
    ///
    /// The digest comes from the persisted ``RouteDigestIndex`` when it has an
    /// entry for this exact train under the current inputs; only a miss there
    /// runs timetable enrichment and the digest, and records the answer.
    /// `prepared` is a miss this load already computed: it is returned as is.
    private nonisolated static func readCached(
        _ train: Train, country: String, prepared: PreparedRoute? = nil
    ) async throws -> CacheRead {
        guard !train.requiresRouteConfirmation else { return .miss(nil, digest: nil) }
        if let prepared, prepared.train == train { return .miss(prepared, digest: prepared.digest) }
        guard let revision = runtimeResourceRevision(scope: Region.scopeKey(Region.regionsTouched(train)))
        else { return .miss(nil, digest: nil) }
        let indexInputs = await digestIndexInputs(for: train, country: country, revision: revision)
        let indexKey = indexInputs.flatMap { RouteDigestIndex.key(train: train, inputs: $0) }
        let resolvedDigest: String?
        let expectedSections: [RouteSection]
        let timetableFailure: String?
        var computed: PreparedRoute?
        if let indexKey, let entry = RouteDigestIndexStore.shared.lookup(indexKey) {
            resolvedDigest = entry.digest
            expectedSections = entry.expectedSections
            timetableFailure = nil
        } else {
            // Normalised once and reused for the digest and the expected
            // sections below, instead of each calling `normalizeExportTrain`
            // again for the same train.
            let settled = RouteDigestIndexIdentity.registry(regions: digestIndexRegions(train, country: country)) != nil
            let routeInput = try await canonicalRouteInput(train, country: country)
            let canonical = routeInput.train
            let digest = await routeCacheDigest(canonical, raw: train, country: country)
            resolvedDigest = digest
            expectedSections = canonicalSections(canonical)
            timetableFailure = routeInput.timetableFailure
            computed = PreparedRoute(
                train: train, input: routeInput, digest: digest, registrySettled: settled)
            // Recorded only for a clean answer whose inputs held still while
            // it was computed (no registry settle, no editor-applied occurrence).
            if let indexKey, let digest, routeInput.timetableFailure == nil,
               currentDigestIndexInputs(for: train, country: country, revision: revision) == indexInputs,
               RouteDigestIndex.roundTrips(expectedSections) {
                RouteDigestIndexStore.shared.record(indexKey, digest: digest, expectedSections: expectedSections)
            }
        }
        guard let digest = resolvedDigest,
              let data = try? Data(contentsOf: cacheURL(country: country, digest: digest)),
              let cache = try? JSONDecoder().decode(RuntimeCache.self, from: data),
              cache.version == RouteGraph.routeDrawnCacheVersion,
              cache.resolutionSemantics == resolutionSemantics,
              cache.digest == digest,
              cache.resourceRevision == revision
        else { return .miss(computed, digest: resolvedDigest) }
        // Re-resolve malformed metadata without invalidating unrelated cache
        // entries or treating geometry-only selections as interval proof.
        guard cache.segments.allSatisfy({ segment in
            guard let selection = segment.physicalRoute else { return true }
            return RouteBatchInspection.Selection(
                fromCode: selection.fromStationCode, toCode: selection.toStationCode,
                intervals: selection.intervals, provenance: selection.provenance.rawValue)
                .isStructurallyValid
        }) else { return .miss(computed, digest: digest) }
        // A given `segmentIndex` can carry more than one cached entry — one
        // per `MultiLineString` part, written in part order by `saveCache`.
        // Counting occurrences here, the same way the live dataset path
        // enumerates a feature's strokes, recovers each part's identity
        // without a cache format change. See ``assigningPartIndex(to:segmentIndex:)``.
        let usable = cache.segments.compactMap { cached -> (CachedSegment, [Coordinate], [Coordinate])? in
            // Both halves come back as they went in: the map redraws the slice
            // it drew before, and the statistics keep matching N02.
            let source = cached.coordinates.compactMap(Coordinate.init(pair:))
            let drawn = cached.drawnCoordinates.compactMap(Coordinate.init(pair:))
            guard source.count >= 2, drawn.count >= 2 else { return nil }
            return (cached, source, drawn)
        }
        let segments = assigningPartIndex(to: usable, segmentIndex: { $0.0.segmentIndex })
            .map { entry, partIndex -> DrawnSegment in
                let (cached, source, drawn) = entry
                return DrawnSegment(
                    segmentIndex: cached.segmentIndex, partIndex: partIndex, from: cached.from,
                    to: cached.to, coordinates: drawn, sourceCoordinates: source,
                    country: country,
                    historyIDs: cached.historyIDs, validFrom: cached.validFrom,
                    validTo: cached.validTo, temporalKind: cached.temporalKind,
                    physicalRoute: cached.physicalRoute)
            }
        guard !segments.isEmpty else { return .miss(computed, digest: digest) }
        return .hit(drawnRide(
            train,
            country: country,
            segments: segments,
            expectedSections: expectedSections, indicesAreAuthoritative: cache.indicesAreAuthoritative ?? true,
            physicalGaps: cache.physicalGaps, timetableFailure: timetableFailure), digest: digest)
    }

    /// Every input besides the train that the enriched canonical input and
    /// its digest depend on, after the scope's registry settles (the digest
    /// waits for it anyway). `nil` disables the index for this read: a
    /// registry still decoding, no history revision, no build identity, or
    /// an editor-applied occurrence that enrichment could prefer.
    private nonisolated static func digestIndexInputs(
        for train: Train, country: String, revision: String
    ) async -> RouteDigestIndex.Inputs? {
        _ = await SolverRegistryInput.awaitReady(region: country)
        return currentDigestIndexInputs(for: train, country: country, revision: revision)
    }

    /// The regions whose registry can change this train's canonical input:
    /// its graph regions, the scope home and its own region.
    private nonisolated static func digestIndexRegions(_ train: Train, country: String) -> [String] {
        RouteScope(train).graphRegions.map(\.code) + [country] + (train.region.map { [$0] } ?? [])
    }

    private nonisolated static func currentDigestIndexInputs(
        for train: Train, country: String, revision: String
    ) -> RouteDigestIndex.Inputs? {
        guard !TimetableRouteEvidence.holdsAppliedOccurrences,
              let build = RouteDigestIndexIdentity.build,
              let history = historyRevisionSet(for: train)
        else { return nil }
        guard let registry = RouteDigestIndexIdentity.registry(
            regions: digestIndexRegions(train, country: country)) else { return nil }
        return RouteDigestIndex.Inputs(
            country: country, resourceRevision: revision,
            timetableEvidenceRevision: TimetableRouteEvidence.evidenceRevision,
            solverCacheVersion: RouteGraph.routeSolverCacheVersion,
            drawnCacheVersion: RouteGraph.routeDrawnCacheVersion,
            resolutionSemantics: resolutionSemantics,
            historyRevision: history.canonical, registry: registry, build: build)
    }

    /// Writes the route cache entry for an already-computed digest. The
    /// caller normalises the train once (for the digest, the sections, or
    /// both) and passes the digest through rather than this function
    /// re-deriving it from the train again.
    private nonisolated static func runtimeResourceRevision(scope: String) -> String? {
        guard let resources = resourceRevisions, let rail = resources.revision(for: scope) else { return nil }
        return scope.split(separator: "+").contains("jp") ? rail + "|timetable:" + resources.timetableRevision : rail
    }

    private nonisolated static func saveCache(
        _ ride: DrawnRide, digest: String, country: String, resourceScope: String
    ) throws {
        guard let revision = runtimeResourceRevision(scope: resourceScope) else { return }
        let directory = cacheDirectory(country: country)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let cache = RuntimeCache(
            version: RouteGraph.routeDrawnCacheVersion, resolutionSemantics: resolutionSemantics,
            digest: digest, resourceRevision: revision, indicesAreAuthoritative: ride.indicesAreAuthoritative,
            physicalGaps: ride.physicalGaps,
            segments: ride.segments.map {
                CachedSegment(
                    segmentIndex: $0.segmentIndex, from: $0.from, to: $0.to,
                    coordinates: $0.sourceCoordinates.map(\.pair),
                    drawnCoordinates: $0.drawnCoordinates.map(\.pair),
                    historyIDs: $0.historyIDs, validFrom: $0.validFrom,
                    validTo: $0.validTo, temporalKind: $0.temporalKind,
                    physicalRoute: $0.physicalRoute)
            })
        try JSONEncoder().encode(cache).write(
            to: cacheURL(country: country, digest: digest), options: .atomic)
    }

    private nonisolated static func cacheURL(country: String, digest: String) -> URL {
        cacheDirectory(country: country).appending(path: "\(digest).json")
    }

    private nonisolated static func cacheDirectory(country: String) -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return base.appending(path: "RailMap/Routes/\(country)", directoryHint: .isDirectory)
    }

    /// How many solved routes one region's cache may keep.
    ///
    /// Set well above any working set that ships — the largest bundled dataset
    /// is 201 journeys and a reader can hold all three Japanese ones at once —
    /// because what fills the remainder is not journeys but revisions of them.
    /// A digest covers a journey's sections and policy, so every edit writes a
    /// new file and orphans the old one, correct and never read again. A
    /// history-revision change orphans a whole set at once. The sweep never
    /// removes a digest the current load uses, so a smaller budget only
    /// trims orphans sooner.
    private nonisolated static let routeCacheEntryBudget = 1024

    private static var didSweepRouteCache = false

    /// Trim the route cache once per launch, after the load that filled it.
    ///
    /// Last rather than first, so the sweep never competes with solving, and
    /// once rather than per write, so a reader who reworks one journey twenty
    /// times in a session pays for the tidying on the next launch instead of
    /// twenty times over. A cancelled load never reaches here, so the flag is
    /// only ever spent on a load that finished.
    private static func sweepRouteCacheOnce(protecting ids: Set<String>) {
        guard !didSweepRouteCache else { return }
        didSweepRouteCache = true
        // Detached and low priority: nothing waits on the answer, and the
        // reader is already looking at their map by the time it runs.
        Task.detached(priority: .utility) {
            _ = sweepRouteCache(protecting: CurrentRouteDigests.shared.digests(for: ids))
        }
    }

    /// Trim each region's cache back to ``routeCacheEntryBudget``, oldest
    /// first, and answer how many entries went.
    ///
    /// Bounded by count and not by age on purpose. An entry is rewritten only
    /// when its route is solved again, so a sample loaded once and never
    /// edited keeps its original dates for as long as the install lasts; an
    /// age rule would eventually delete all 201 of the Japanese sample's
    /// routes and make the next launch re-solve them, which is exactly the
    /// wait this cache exists to remove. Oldest-first still evicts a
    /// superseded revision before the replacement that outdates it, and an
    /// entry evicted while still live is solved again and rewritten with a
    /// fresh date, which moves it out of the firing line by itself.
    ///
    /// Everything it can reach is derived: only `RailMap/Routes/<code>` under
    /// the caches directory, only for the five region codes this app knows,
    /// only regular files directly inside one, and only those named `*.json`.
    /// Each is a file `solveMissing` builds again from the bundled network, so
    /// the worst a mistake here can cost is a re-solve — the same cost iOS
    /// imposes whenever it purges the caches directory on its own.
    ///
    /// The count is returned rather than reported because nothing in this app
    /// logs; it is there so a sweep that removes nothing, or everything, is
    /// visible to whoever next has a debugger on this.
    private nonisolated static func sweepRouteCache(protecting protected: Set<String>) -> Int {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var removed = 0
        for region in Region.ordered {
            guard let contents = try? manager.contentsOfDirectory(
                at: cacheDirectory(country: region.code),
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            else { continue }
            let entries = contents.compactMap { url -> RouteCacheSweep.Entry? in
                guard url.pathExtension == "json",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else { return nil }
                return RouteCacheSweep.Entry(
                    digest: url.deletingPathExtension().lastPathComponent,
                    written: values.contentModificationDate ?? .distantPast)
            }
            for entry in RouteCacheSweep.victims(entries, budget: routeCacheEntryBudget, protected: protected) {
                // A failure needs no handling: the entry either went or it did
                // not, and either way the next load re-solves what is missing.
                guard (try? manager.removeItem(at: cacheURL(country: region.code, digest: entry.digest))) != nil
                else { continue }
                removed += 1
            }
        }
        return removed
    }

    private nonisolated static let resourceRevisionState = Result { try RailResourceRevisions.bundled() }

    /// An unavailable attestation disables disk cache reuse; the physical
    /// solver remains usable and the reason stays visible.
    private nonisolated static func resourceRevisionFailure(for country: String) -> String? {
        do {
            _ = try resourceRevisionState.get().requiredRevision(for: country)
            return nil
        } catch { return error.localizedDescription }
    }

    private nonisolated static var resourceRevisions: RailResourceRevisions? {
        if case .success(let revisions) = resourceRevisionState { return revisions }
        return nil
    }

    private struct RuntimeCache: Codable {
        let version: String
        let resolutionSemantics: String
        let digest: String
        let resourceRevision: String?
        var indicesAreAuthoritative: Bool? = nil
        let physicalGaps: [PhysicalGap]
        let segments: [CachedSegment]
    }

    private struct CachedSegment: Codable {
        let segmentIndex: Int
        let from: String?
        let to: String?
        /// The N02-datum path the statistics match, under the name it has
        /// always had on disk.
        let coordinates: [[Double]]
        /// The path the map draws — the canonical slice, where there was one.
        ///
        /// Required rather than optional on purpose. An entry written before
        /// the two were told apart carries one array, and it is the drawn one:
        /// it cannot answer for both, and reading it as if it could is the
        /// error this field exists to end. Decoding such an entry fails,
        /// ``readCached(_:country:)`` answers `nil`, and the journey is solved
        /// again — which retires every stale entry without spending a cache
        /// version on it.
        let drawnCoordinates: [[Double]]
        let historyIDs: [String]
        let validFrom: String?
        let validTo: String?
        let temporalKind: RouteGraph.TemporalKind
        let physicalRoute: PhysicalRouteSelection?

        private enum CodingKeys: String, CodingKey {
            case segmentIndex, from, to, coordinates, drawnCoordinates
            case historyIDs, validFrom, validTo, temporalKind, physicalRoute
        }

        init(
            segmentIndex: Int, from: String?, to: String?,
            coordinates: [[Double]], drawnCoordinates: [[Double]],
            historyIDs: [String], validFrom: String?, validTo: String?,
            temporalKind: RouteGraph.TemporalKind, physicalRoute: PhysicalRouteSelection?
        ) {
            self.segmentIndex = segmentIndex
            self.from = from
            self.to = to
            self.coordinates = coordinates
            self.drawnCoordinates = drawnCoordinates
            self.historyIDs = historyIDs
            self.validFrom = validFrom
            self.validTo = validTo
            self.temporalKind = temporalKind
            self.physicalRoute = physicalRoute
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            segmentIndex = try c.decode(Int.self, forKey: .segmentIndex)
            from = try c.decodeIfPresent(String.self, forKey: .from)
            to = try c.decodeIfPresent(String.self, forKey: .to)
            coordinates = try c.decode([[Double]].self, forKey: .coordinates)
            drawnCoordinates = try c.decode([[Double]].self, forKey: .drawnCoordinates)
            // A version-23 file written before these keys existed, or one that
            // omits them, is current track — not a cache miss.
            historyIDs = try c.decodeIfPresent([String].self, forKey: .historyIDs) ?? []
            validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom)
            validTo = try c.decodeIfPresent(String.self, forKey: .validTo)
            temporalKind = try c.decodeIfPresent(
                RouteGraph.TemporalKind.self, forKey: .temporalKind) ?? .current
            physicalRoute = try c.decodeIfPresent(PhysicalRouteSelection.self, forKey: .physicalRoute)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(segmentIndex, forKey: .segmentIndex)
            try c.encodeIfPresent(from, forKey: .from)
            try c.encodeIfPresent(to, forKey: .to)
            try c.encode(coordinates, forKey: .coordinates)
            try c.encode(drawnCoordinates, forKey: .drawnCoordinates)
            try c.encode(historyIDs, forKey: .historyIDs)
            try c.encodeIfPresent(validFrom, forKey: .validFrom)
            try c.encodeIfPresent(validTo, forKey: .validTo)
            try c.encode(temporalKind, forKey: .temporalKind)
            try c.encodeIfPresent(physicalRoute, forKey: .physicalRoute)
        }
    }

    enum LoadError: LocalizedError {
        case missingSolverResources(String)
        case invalidHistory(String, String)

        var errorDescription: String? {
            switch self {
            case .missingSolverResources(let country):
                "Runtime solver resources for \(country) are missing from the app bundle."
            case .invalidHistory(let country, let reason):
                "Rail history database for \(country) is invalid: \(reason)"
            }
        }
    }
}


/// Latest solver partial, posted off the main actor. ``post`` returns true only
/// for the caller that must schedule the drain; later posts replace ``latest``
/// until that drain runs. ``close`` drops anything still held so a partial
/// cannot land after the load's final result. ``PartialRidePublication`` still
/// coalesces the actual apply.
private final class PartialRideInbox: Sendable {
    private struct State: Sendable {
        var latest: [RiddenRouteStore.DrawnRide]?
        var drainScheduled = false
        var closed = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    /// Stores the newest partial. True only when this caller should schedule a drain.
    func post(_ rides: [RiddenRouteStore.DrawnRide]) -> Bool {
        lock.withLock { state in
            guard !state.closed else { return false }
            state.latest = rides
            guard !state.drainScheduled else { return false }
            state.drainScheduled = true
            return true
        }
    }

    /// The newest partial, or nil once ``close`` has run. Clears the slot either way
    /// when still open, and allows the next ``post`` to schedule another drain.
    func take() -> [RiddenRouteStore.DrawnRide]? {
        lock.withLock { state in
            guard !state.closed else { return nil }
            let rides = state.latest
            state.latest = nil
            state.drainScheduled = false
            return rides
        }
    }

    func close() {
        lock.withLock { state in
            state.closed = true
            state.latest = nil
        }
    }
}

/// The partial ride lists one route load publishes, coalesced so the map and
/// the status list take at most one of them per ``interval``.
///
/// The first partial applies at once, so a cold launch still shows its first
/// journeys immediately. Later ones within the interval replace each other
/// and the newest is applied when it ends. ``cancel()`` drops a pending one:
/// the load calls it before it applies its complete result, so a stale
/// partial can never land on top of that.
@MainActor
private final class PartialRidePublication {
    static let interval: Duration = .milliseconds(750)

    private var lastApplied: ContinuousClock.Instant?
    private var pending: [RiddenRouteStore.DrawnRide]?
    private var pendingApply: (@MainActor ([RiddenRouteStore.DrawnRide]) -> Void)?
    private var flush: Task<Void, Never>?

    func submit(
        _ partial: [RiddenRouteStore.DrawnRide],
        apply: @escaping @MainActor ([RiddenRouteStore.DrawnRide]) -> Void
    ) {
        let now = ContinuousClock.now
        if flush == nil, lastApplied.map({ now - $0 >= Self.interval }) ?? true {
            lastApplied = now
            apply(partial)
            return
        }
        pending = partial
        pendingApply = apply
        guard flush == nil else { return }
        let wait = Self.interval - (now - (lastApplied ?? now))
        flush = Task { @MainActor [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, !Task.isCancelled else { return }
            self.applyPending()
        }
    }

    /// Applies the newest held partial now, if there is one.
    func applyPending() {
        let partial = pending, apply = pendingApply
        cancel()
        guard let partial, let apply else { return }
        lastApplied = .now
        apply(partial)
    }

    func cancel() {
        flush?.cancel()
        flush = nil
        pending = nil
        pendingApply = nil
    }
}

/// One route store's pending solves. Several stores each keep their own box.
final class PendingSolveOwner: @unchecked Sendable {
    weak var store: RiddenRouteStore?
    private let lock = NSLock()
    /// Solves still waiting on the registry. They solve themselves after the
    /// settle, so a replay never touches these.
    private var awaiting: [String: Set<String>] = [:]
    /// Solves that completed while a region had no registry. Only these replay.
    private var solvedUnavailable: [String: Set<String>] = [:]

    func noteAwaiting(id: String, regions: Set<String>) {
        guard !id.isEmpty, !regions.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        awaiting[id] = regions
    }

    func finishAwaiting(id: String) {
        lock.lock()
        defer { lock.unlock() }
        awaiting.removeValue(forKey: id)
    }

    func isAwaiting(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return awaiting[id] != nil
    }

    func noteSolvedUnavailable(id: String, regions: Set<String>) {
        guard !id.isEmpty, !regions.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        solvedUnavailable[id] = regions
    }

    /// Ids that already solved without `region`'s registry; each is claimed once.
    /// An id whose solve is still waiting is never returned.
    func claimForReplay(region: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let cc = region.lowercased()
        let claimed = solvedUnavailable.compactMap { id, regions -> String? in
            regions.contains(cc) && awaiting[id] == nil ? id : nil
        }
        for id in claimed { solvedUnavailable.removeValue(forKey: id) }
        return claimed
    }
}

enum PendingSolveRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var owners: [PendingSolveOwner] = []
    private static let installed: Void = {
        BundledRegistry.addSettledHandler { region in
            lock.lock()
            owners = owners.filter { $0.store != nil }
            let snapshot = owners
            lock.unlock()
            for owner in snapshot {
                let ids = owner.claimForReplay(region: region)
                guard !ids.isEmpty, let store = owner.store else { continue }
                Task { @MainActor in
                    store.replayPending(ids)
                }
            }
        }
    }()

    static func register(_ owner: PendingSolveOwner) {
        _ = installed
        lock.lock()
        if !owners.contains(where: { $0 === owner }) {
            owners.append(owner)
        }
        lock.unlock()
    }
}
