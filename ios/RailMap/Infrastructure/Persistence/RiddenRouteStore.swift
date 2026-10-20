import CryptoKit
import Foundation
import MapKit
import Observation
import os
import RailCore
import RailPresentation

/// Precomputed ridden geometry shipped by the main fork's progressive sample
/// datasets. Each part contains one canonical train plus the exact route
/// features produced by the web solver; the native map consumes those
/// source coordinates for statistics and slices the complete railway for display.
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
        var indicesAreAuthoritative = true
        var expectedSectionCount = 0
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
    private(set) var rides: [DrawnRide] = []
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

    /// Replace the solved-route table and drop every in-flight single solve.
    /// A later finish for a superseded ticket must not write back into this table.
    private func noteRouteEntries(for rides: [DrawnRide], wanted: [String], keeping landed: Set<String> = []) {
        let kept = routeEntries.filter { landed.contains($0.key) }
        routeEntries = Self.statusEntries(for: rides, wanted: wanted)
        for (id, entry) in kept { routeEntries[id] = entry }
        resolvingIDs.removeAll()
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
    func load(trains: [Train], preferredTrainID: String? = nil) {
        bindPendingOwner()
        let wanted = Dictionary(trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wantedIDs = trains.map(\.id)
        requestedOrder = wantedIDs
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
        loadTask = Task(priority: .userInitiated) {
            await Self.$activePendingOwner.withValue(owner) {
            do {
                let primed = try await Self.loadPreferred(id: preferredTrainID, wanted: pending)
                try Task.checkCancellation()
                guard loadRevision == revision else { return }
                if let primed {
                    rides = mergedRides(retained: retained, batch: [primed], since: landingMark)
                    visibleRides = rides.filter(\.visible)
                    if !landedSince(landingMark).contains(primed.id) { completedInputs[primed.id] = wanted[primed.id] }
                    noteRouteEntries(for: rides, wanted: [])
                    lineDetector.publishSelected(rides: rides)
                }
                let decoded = try await Self.decode(
                    wanted: pending, requestedOrder: wantedIDs,
                    preferredTrainID: preferredTrainID, primed: primed
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
                                self.lineDetector.publishSelected(rides: self.rides)
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
                state = .loaded(rides: rides)
                noteRouteEntries(for: rides, wanted: wantedIDs, keeping: landed)
                detectTraversedLines()
                Self.sweepRouteCacheOnce()
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
                state = .failed(error.localizedDescription)
                noteRouteEntries(for: rides, wanted: [])
            }
            }
        }
    }

    private func ordered(_ values: [DrawnRide]) -> [DrawnRide] {
        let byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return requestedOrder.compactMap { byID[$0] }
    }

    /// Read the last-viewed route only. A miss deliberately does not solve:
    /// the complete decoder below owns expensive work and its cancellation.
    @concurrent private nonisolated static func loadPreferred(
        id: String?, wanted: [String: Train]
    ) async throws -> DrawnRide? {
        guard let id, let train = wanted[id] else { return nil }
        return try await loadCached([train], country: RouteScope(train).code).rides.first
    }

    func clear() {
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
                    let inputs = try await SolverInputCache.shared.inputs(scope: scope)
                    try Task.checkCancellation()
                    let displayNetwork = try? await DisplayNetworkCache.shared.network(scope: scope)
                    try Task.checkCancellation()
                    graphStore = UncheckedGraphStoreBox(store: fallbackGraphStore(
                        inputs: inputs, displayNetwork: displayNetwork))
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
                            rejectPrecomputed: { _ in },
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
        if let ride = cached.rides.first { return ride }
        return try await solveMissing(cached.missing, scope: scope).first
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

    /// Cache, then the precomputed datasets, then solve — per region.
    ///
    /// The order is the reverse of the web app's, and the reason is the merged
    /// store. The web app reads its one dataset first because that dataset IS
    /// its store; here a reader can hold the 201-journey Japanese sample, the
    /// New Year loop and their own rides at once, so "which dataset?" has no
    /// single answer and scanning every candidate on every reload would decode
    /// 11 MB of parts to answer a question the on-disk cache has already
    /// answered. Rides that come out of a dataset are written into that cache,
    /// so the scan happens once per journey rather than once per load.
    ///
    /// ## Two phases, and the map is handed the first one
    ///
    /// The cache read is the whole of a warm load and costs ~20 ms for 201
    /// journeys; the dataset scan and the solve are the cold one and cost
    /// seconds, because they read a country's `rail-sections*.json` and
    /// `stations*.json` (11.8 MB and 3.2 MB for Japan). Returning one array at
    /// the end meant a single uncached journey held every cached journey off
    /// the map for as long as its country took to read.
    ///
    /// So `publish` is called with everything the cache answered before any
    /// dataset is opened, and again as each remaining journey finishes. A warm
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
        preferredTrainID: String?, primed: DrawnRide? = nil,
        publish: @Sendable ([DrawnRide]) async -> Void = { _ in }
    ) async throws -> [DrawnRide] {
        var result: [DrawnRide] = primed.map { [$0] } ?? []
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
        for scope in RouteScope.ordered(byScope.keys) {
            guard let trains = byScope[scope] else { continue }
            let cached = try await loadCachedConcurrently(trains, country: scope.code)
            result += cached.rides
            if !cached.missing.isEmpty { unresolved.append((scope, cached.missing, nil, nil)) }
        }

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
            let inputs = try await SolverInputCache.shared.inputs(scope: scope)
            let displayNetwork = try? await DisplayNetworkCache.shared.network(scope: scope)
            let graphStore = fallbackGraphStore(inputs: inputs, displayNetwork: displayNetwork)
            unresolved[index].graphStore = graphStore
            unresolved[index].providedInputs = inputs
            result = try await decodeUncached(
                [preferred], scope: scope, previous: result, graphStore: graphStore,
                providedInputs: inputs,
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
                let inputs = try await SolverInputCache.shared.inputs(scope: scope)
                let displayNetwork = try? await DisplayNetworkCache.shared.network(scope: scope)
                unresolved[index].graphStore = fallbackGraphStore(
                    inputs: inputs, displayNetwork: displayNetwork)
                unresolved[index].providedInputs = inputs
            }
            result = try await decodeUncached(
                trains, scope: scope, previous: result,
                graphStore: unresolved[index].graphStore,
                providedInputs: unresolved[index].providedInputs, publish: publish)
            unresolved[index].graphStore = nil
            unresolved[index].providedInputs = nil
        }
        return result
    }

    /// The shared inference, dataset, and solver pipeline after a cache miss.
    @concurrent private nonisolated static func decodeUncached(
        _ trains: [Train], scope: RouteScope, previous: [DrawnRide],
        graphStore: RouteGraph.RouteGraphStore? = nil,
        providedInputs: SolverInputs? = nil,
        publish: @Sendable ([DrawnRide]) async -> Void
    ) async throws -> [DrawnRide] {
        try Task.checkCancellation()
        var result = previous
        var missing = Dictionary(
            trains.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A fresh JS precompute remains a valid legacy fallback, but cannot
        // decide a different physical route before station inference.
        // Both solver passes share this scope's graph and its corridor memos.
        let previous = result
        let rejections = PrecomputedRouteRejections()
        let inferred = try await solveMissing(
            trains, scope: scope, allowLegacy: false, graphStore: graphStore,
            providedInputs: providedInputs,
            rejectPrecomputed: { await rejections.reject($0) }) { partial in
                await publish(previous + partial)
            }
        for ride in inferred { missing.removeValue(forKey: ride.id) }
        result += inferred
        for dataset in RideLibrary.routeDatasets(for: scope.home) {
            let eligible = await rejections.allowed(missing)
            if eligible.isEmpty { break }
            let previous = result
            let found = try await datasetRides(
                dataset: dataset, country: scope.code, wanted: eligible) { partial in
                    await publish(previous + partial)
                }
            for ride in found { missing.removeValue(forKey: ride.id) }
            result += found
        }
        if !missing.isEmpty {
            let previous = result
            result += try await solveMissing(
                trains.filter { missing[$0.id] != nil }, scope: scope,
                graphStore: graphStore, providedInputs: providedInputs, publish: { partial in
                    await publish(previous + partial)
                })
        }
        return result
    }

    /// The rides one precomputed dataset can answer for.
    ///
    /// A part is accepted only when its train's route-cache digest matches the
    /// one in the store, which is what makes searching several datasets safe:
    /// geometry solved for another itinerary is rejected rather than drawn.
    ///
    /// Which parts are even worth opening comes from ``DatasetPartIndex``.
    /// This used to walk the manifest and decode every part in it before
    /// reading the train id it had just paid for, so one journey missing from
    /// the route cache cost the whole dataset — 201 files and 7 MB for the
    /// Japanese sample — and the next journey cost it again.
    @concurrent private nonisolated static func datasetRides(
        dataset: String,
        country: String,
        wanted: [String: Train],
        publish: @Sendable ([DrawnRide]) async -> Void = { _ in }
    ) async throws -> [DrawnRide] {
        let interval = RailSignpost.data.begin("route.datasetLookup")
        defer { RailSignpost.data.end("route.datasetLookup", interval) }
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest", withExtension: "json", subdirectory: dataset),
              let manifest = try? JSONDecoder().decode(
                PrecomputedSources.self, from: Data(contentsOf: manifestURL)),
              resourceRevisions?.acceptsPrecomputed(
                sourceHashes: manifest.sourceHashes, country: country) == true
        else { return [] }
        let index = try await DatasetPartIndex.shared.parts(in: dataset)
        // Sorted back into manifest order, because `wanted` is a dictionary
        // and has none of its own, and the order rides come back in is the
        // order the map is handed them in.
        let hits = wanted.keys
            .flatMap { index[$0] ?? [] }
            .sorted { $0.position < $1.position }
        let displayNetwork = try? await DisplayNetworkCache.shared.network(country: country)
        var projectionCache = RouteProjectionCache()
        var result: [DrawnRide] = []
        result.reserveCapacity(hits.count)
        // A journey whose route spans several bundled parts hits this loop
        // once per part but is the same `wanted` train every time — normalised
        // once here and reused for the digest, the template digest, the
        // expected sections, and the cache write below, all of which used to
        // each normalise it again.
        var normalizedByID: [String: CanonicalRouteInput] = [:]
        func canonical(for train: Train) async throws -> CanonicalRouteInput {
            if let cached = normalizedByID[train.id] { return cached }
            let value = try await canonicalRouteInput(train, country: country)
            normalizedByID[train.id] = value
            return value
        }
        for hit in hits {
            try Task.checkCancellation()
            guard let partURL = Bundle.main.url(
                forResource: hit.name,
                withExtension: "json",
                subdirectory: dataset
            ) else { throw LoadError.missingPart(dataset, hit.name) }
            let part = try JSONDecoder().decode(Part.self, from: Data(contentsOf: partURL))
            guard resourceRevisions?.acceptsPrecomputed(
                manifestSourceHashes: manifest.sourceHashes,
                partSourceHashes: part.sourceHashes, country: country) == true else { continue }
            guard let train = wanted[part.train.id], !train.requiresRouteConfirmation,
                  !RouteScope(train).crossesBorder else { continue }
            guard let precomputedRoute = part.route,
                  let precomputedFeatures = precomputedRoute.features else { continue }
            let routeInput = try await canonical(for: train)
            let trainCanonical = routeInput.train
            // Physical identities select package survey intervals directly.
            // A legacy N02 precompute can attest the journey, but cannot
            // attest which of the closely parallel platform tracks it rode.
            if trainCanonical.routeSections?.contains(where: { $0.sectionCodes?.isEmpty == false }) == true {
                continue
            }
            let trainDigest = await routeCacheDigest(trainCanonical, raw: train, country: country)
            let partDigest = await routeCacheDigest(
                normalizedTrain(part.train, country: country), raw: part.train, country: country)
            guard trainDigest == partDigest else { continue }
            guard let expectedDigest = trainDigest,
                  let revisions = historyRevisionSet(for: train) else { continue }
            guard RailPrecomputedRouteGate.accepts(
                precomputedRoute.solverContext,
                expectedDigest: expectedDigest,
                solverVersion: RouteGraph.routeSolverCacheVersion,
                rideDate: Dates.normalizeDateString(train.date),
                revisions: revisions,
                expectedHashes: !revisions.contentHashes.isEmpty ? revisions.contentHashes : nil
            ) else { continue } // Missing historical content attestation requires an on-demand solve.
            let expectedTemplate = routeTemplateDigest(trainCanonical, country: country)
            let matchingFeatures = precomputedFeatures.filter { feature in
                guard let expectedTemplate else { return true }
                return feature.properties?.routeTemplateKey == expectedTemplate
            }
            let indicesAreAuthoritative = matchingFeatures
                .allSatisfy { $0.properties?.segmentIndex != nil }
            // The precompute may contain a graph connector across a curve
            // (Daimon–Akabanebashi). Slice the same complete display railway
            // as the live solver, but keep its source path in the separate
            // field consumed by statistics and exports.
            // `partIndex` is assigned AFTER resolving each stroke's
            // `segmentIndex` and dropping the too-short ones, using the same
            // per-`segmentIndex` output-order counter `readCached` uses — see
            // ``assigningPartIndex(to:segmentIndex:)``. Assigning it from the
            // stroke's own position within its feature (as before) collided
            // whenever a short part was dropped, a feature carried no
            // authoritative `segment_index` (so the count restarted per
            // feature), or two features shared a `segmentIndex`.
            let sections = canonicalSections(trainCanonical)
            // Legacy precomputes have no qualified endpoint provenance. A
            // continuous itinerary must be assembled by the physical solver.
            if zip(sections, sections.dropFirst()).contains(where: {
                routeSectionBoundarySharesExplicitStop($0.0, $0.1)
            }) { continue }
            let usableStrokes = matchingFeatures.flatMap { feature in
                feature.geometry.strokes.enumerated().compactMap { offset, coordinates
                    -> (segmentIndex: Int, from: String?, to: String?, source: [Coordinate],
                        hints: RouteHints, temporal: RouteGraph.TemporalKind, properties: Properties?)? in
                    guard coordinates.count >= 2 else { return nil }
                    let index = feature.properties?.segmentIndex ?? offset
                    let section = sections.indices.contains(index) ? sections[index] : nil
                    let properties = feature.properties
                    return (
                        segmentIndex: index, from: properties?.from, to: properties?.to,
                        source: coordinates,
                        hints: RouteHints(
                            requiredLineNames: properties?.requiredLineNames ?? section?.lineNames ?? [],
                            preferredLineNames: properties?.preferredLineNames ?? [],
                            requiredOperatorNames: properties?.requiredOperatorNames ?? section?.operatorNames ?? [],
                            preferredOperatorNames: properties?.preferredOperatorNames ?? [],
                            requiredLineIDs: properties?.requiredLineIDs ?? section?.lineIDs ?? [],
                            sectionCodes: properties?.sectionCodes ?? section?.sectionCodes ?? [],
                            fromStationCode: SolverRegistryInput.persistedHopCode(
                                persisted: properties?.fromStationCode,
                                sectionCode: section?.fromN02StationCode,
                                stationID: section?.fromStationID, region: country),
                            toStationCode: SolverRegistryInput.persistedHopCode(
                                persisted: properties?.toStationCode,
                                sectionCode: section?.toN02StationCode,
                                stationID: section?.toStationID, region: country)),
                        temporal: properties?.temporalKind ?? .current, properties: properties)
                }
            }
            let displayed = usableStrokes.flatMap { entry in
                let parts = displayNetwork?.precomputedDisplayParts(
                    source: entry.source, hints: entry.hints, temporalKind: entry.temporal,
                    cache: &projectionCache)
                return (parts ?? [.init(coordinates: entry.source, sourceCoordinates: entry.source)])
                    .map { (entry: entry, part: $0) }
            }
            let segments = assigningPartIndex(to: displayed, segmentIndex: { $0.entry.segmentIndex })
                .map { entry, partIndex -> DrawnSegment in
                    DrawnSegment(
                        segmentIndex: entry.entry.segmentIndex, partIndex: partIndex,
                        from: entry.entry.from, to: entry.entry.to,
                        coordinates: entry.part.coordinates,
                        sourceCoordinates: entry.part.sourceCoordinates, country: country,
                        historyIDs: entry.entry.properties?.historyIDs ?? [],
                        validFrom: entry.entry.properties?.validFrom,
                        validTo: entry.entry.properties?.validTo,
                        temporalKind: entry.entry.temporal,
                        physicalRoute: RideRouteResolution.displaySelection(
                            lineIDs: entry.part.displayLineIDs, sectionCodes: entry.part.matchedSectionCodes,
                            hints: entry.entry.hints, network: displayNetwork,
                            sourceCoordinates: entry.entry.source))
                }
            guard !segments.isEmpty else { continue }
            let ride = drawnRide(
                train,
                country: country,
                segments: segments,
                expectedSections: canonicalSections(trainCanonical),
                indicesAreAuthoritative: indicesAreAuthoritative,
                timetableFailure: routeInput.timetableFailure)
            // Written into the same cache a solve writes to, so the next load
            // finds this journey without opening a dataset at all. That is
            // what keeps the dataset search a first-load cost rather than a
            // per-load one.
            if let trainDigest { try? saveCache(ride, digest: trainDigest, country: country, resourceScope: Region.scopeKey(Region.regionsTouched(train))) }
            result.append(ride)
            try Task.checkCancellation()
            await publish(result)
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
                from: section.from, to: section.to, isBoundary: gap.isBoundary)
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
        for gap in physicalGaps { geometryHasher.combine(gap.segmentIndex); geometryHasher.combine(gap.isBoundary) }
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

    /// Solve the journeys no cache and no dataset could answer for.
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
        rejectPrecomputed: @Sendable (String) async -> Void = { _ in },
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
            let routeInput = try await canonicalRouteInput(train, country: scope.code)
            let canonical = routeInput.train
            let digest = await routeCacheDigest(canonical, raw: train, country: scope.code)
            // Joining happens before admission. Only the producer acquires the
            // sole permit, so a subscriber never holds it while awaiting work.
            let operation: @Sendable () async throws -> [DrawnRide] = {
                try await RouteSolveLimiter.shared.withPermit {
                    try await solveMissingSequentialWithPermit(
                        [train], scope: scope, allowLegacy: allowLegacy,
                        graphStore: graphStoreBox?.store, providedInputs: inputs,
                        providedCanonicalInputs: [routeInput],
                        rejectPrecomputed: { _ in }, publish: { _ in }, saveRoutes: false)
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
            } else if !allowLegacy {
                // A no-result first pass may have rejected ambiguous station
                // choices. Keep that decision local to each subscriber.
                let rejection = await SolverInputCache.shared.inferenceIsAmbiguous(
                    train: canonical, raw: train, scope: scope, inputs: inputs)
                if rejection { await rejectPrecomputed(train.id) }
            }
        }
        return results
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
    /// Mutable graphs stay private to one sequential worker.
    private actor SolverInputCache {
        static let shared = SolverInputCache()
        private var completed: (key: String, inputs: SolverInputs)?
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

        func inferenceIsAmbiguous(train: Train, raw: Train, scope: RouteScope, inputs: SolverInputs) async -> Bool {
            guard let network = try? await DisplayNetworkCache.shared.network(scope: scope) else { return false }
            let prepared = networkIndexes(scope: scope, network: network, inputs: inputs)
            let resolver = RideRouteResolution(inputs: inputs, country: scope.code, network: prepared)
            return resolver.hasAmbiguousStationChoice(.init(train: raw, canonicalTrain: train))
        }

        private func releaseCompleted() { completed = nil }

        private func retain(_ inputs: SolverInputs, key: String) {
            completed = (key, inputs)
        }

        func inputs(scope: RouteScope) async throws -> SolverInputs {
            try Task.checkCancellation()
            let revision = RiddenRouteStore.resourceRevisions?.revision(for: scope.key) ?? "unversioned"
            let key = scope.key + ":" + revision
            if let completed, completed.key == key { return completed.inputs }
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
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf: registryURL))
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
    /// Shipping builds retain the bounded 100,000-node policy.
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
        guard let nodeValue else { return .bounded(maximumNodes: 100_000) }
        guard let nodes = Int(nodeValue), (1...2_000_000).contains(nodes) else {
            throw invalid("\(nodesFlag) requires one integer between 1 and 2000000.")
        }
        return .bounded(maximumNodes: nodes)
    }
    #endif

    private nonisolated static func fallbackGraphStore(
        inputs: SolverInputs, displayNetwork: RouteNetwork?
    ) -> RouteGraph.RouteGraphStore {
        let sections = inputs.sections
        #if RAIL_DIAGNOSTICS
        // Request admission reports malformed options before a route batch starts.
        let cachePolicy = (try? diagnosticGraphCacheConfiguration())?.policy
            ?? .bounded(maximumNodes: 100_000)
        #else
        let cachePolicy = RouteGraph.GraphCachePolicy.bounded(maximumNodes: 100_000)
        #endif
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway, junctions: inputs.physicalJunctions,
            cachePolicy: cachePolicy,
            identityPeriods: inputs.identityPeriods, sourceSnapshotID: inputs.snapshotID)
        return graphStore
    }

    private actor PrecomputedRouteRejections {
        private var ids: Set<String> = []
        func reject(_ id: String) { ids.insert(id) }
        func allowed(_ trains: [String: Train]) -> [String: Train] {
            trains.filter { !ids.contains($0.key) }
        }
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
                    providedInputs: providedInputs,
                    rejectPrecomputed: { _ in }, publish: publish)
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
                                    rejectPrecomputed: { _ in },
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
        rejectPrecomputed: @Sendable (String) async -> Void,
        publish: @Sendable ([DrawnRide]) async -> Void,
        saveRoutes: Bool = true
    ) async throws -> [DrawnRide] {
        guard trains.contains(where: { !$0.requiresRouteConfirmation }) else { return [] }
        let country = scope.code
        let displayNetwork = try? await DisplayNetworkCache.shared.network(scope: scope)
        let inputs: SolverInputs
        if let providedInputs { inputs = providedInputs }
        else { inputs = try await SolverInputCache.shared.inputs(scope: scope) }
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
            if result.requiresPrecomputedRejection { await rejectPrecomputed(train.id) }
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
                let overlay = try RailHistoryOverlay.decode(data)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                state = .loaded(overlay, contentHash: hash)
            }
            catch { state = .invalid(String(describing: error)) }
        } else {
            state = .absent
        }
        historyStateCache.withLock { $0[region] = state }
        return state
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
        let registry = try PhysicalRailJunctionRegistry(data: Data(contentsOf: url))
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

    private nonisolated static func routeTemplateDigest(
        _ canonical: Train, country: String
    ) -> String? {
        let canonicalSections = canonical.routeSections ?? []
        let sections = canonicalSections.map(RouteGraph.RouteSection.init)
        guard !sections.isEmpty else { return nil }
        return RouteGraph.keyDigest(RouteGraph.templateKey(sections: sections))
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
            return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        return digest
    }

    private nonisolated static func loadCached(
        _ trains: [Train], country: String
    ) async throws -> (rides: [DrawnRide], missing: [Train]) {
        var rides: [DrawnRide] = []
        var missing: [Train] = []
        for train in trains {
            if let ride = try await readCached(train, country: country) {
                rides.append(ride)
            } else {
                missing.append(train)
            }
        }
        return (rides, missing)
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
        _ trains: [Train], country: String
    ) async throws -> (rides: [DrawnRide], missing: [Train]) {
        guard trains.count > 1 else { return try await loadCached(trains, country: country) }
        let interval = RailSignpost.data.begin("route.cacheRead")
        defer { RailSignpost.data.end("route.cacheRead", interval) }
        var found = [DrawnRide?](repeating: nil, count: trains.count)
        try await withThrowingTaskGroup(of: (Int, DrawnRide?).self) { group in
            var next = 0
            func addNext() {
                guard next < trains.count else { return }
                let position = next
                let train = trains[position]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    return (position, try await readCached(train, country: country))
                }
            }
            for _ in 0..<Swift.min(cacheReadWidth, trains.count) { addNext() }
            while let (position, ride) = try await group.next() {
                found[position] = ride
                addNext()
            }
        }
        var rides: [DrawnRide] = []
        var missing: [Train] = []
        for (position, ride) in found.enumerated() {
            if let ride { rides.append(ride) } else { missing.append(trains[position]) }
        }
        return (rides, missing)
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

    /// One journey's cached route, or `nil` if there is not a usable one.
    private nonisolated static func readCached(
        _ train: Train, country: String
    ) async throws -> DrawnRide? {
        guard !train.requiresRouteConfirmation else { return nil }
        // Normalised once and reused for the digest and the expected
        // sections below, instead of each calling `normalizeExportTrain`
        // again for the same train.
        let routeInput = try await canonicalRouteInput(train, country: country)
        let canonical = routeInput.train
        guard let revision = runtimeResourceRevision(scope: Region.scopeKey(Region.regionsTouched(train))),
              let digest = await routeCacheDigest(canonical, raw: train, country: country),
              let data = try? Data(contentsOf: cacheURL(country: country, digest: digest)),
              let cache = try? JSONDecoder().decode(RuntimeCache.self, from: data),
              cache.version == RouteGraph.routeDrawnCacheVersion,
              cache.resolutionSemantics == resolutionSemantics,
              cache.digest == digest,
              cache.resourceRevision == revision
        else { return nil }
        // Re-resolve malformed metadata without invalidating unrelated cache
        // entries or treating geometry-only selections as interval proof.
        guard cache.segments.allSatisfy({ segment in
            guard let selection = segment.physicalRoute else { return true }
            return RouteBatchInspection.Selection(
                fromCode: selection.fromStationCode, toCode: selection.toStationCode,
                intervals: selection.intervals, provenance: selection.provenance.rawValue)
                .isStructurallyValid
        }) else { return nil }
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
        guard !segments.isEmpty else { return nil }
        return drawnRide(
            train,
            country: country,
            segments: segments,
            expectedSections: canonicalSections(canonical), indicesAreAuthoritative: cache.indicesAreAuthoritative ?? true,
            physicalGaps: cache.physicalGaps, timetableFailure: routeInput.timetableFailure)
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
    /// new file and orphans the old one, correct and never read again.
    private nonisolated static let routeCacheEntryBudget = 512

    private static var didSweepRouteCache = false

    /// Trim the route cache once per launch, after the load that filled it.
    ///
    /// Last rather than first, so the sweep never competes with solving, and
    /// once rather than per write, so a reader who reworks one journey twenty
    /// times in a session pays for the tidying on the next launch instead of
    /// twenty times over. A cancelled load never reaches here, so the flag is
    /// only ever spent on a load that finished.
    private static func sweepRouteCacheOnce() {
        guard !didSweepRouteCache else { return }
        didSweepRouteCache = true
        // Detached and low priority: nothing waits on the answer, and the
        // reader is already looking at their map by the time it runs.
        Task.detached(priority: .utility) {
            _ = sweepRouteCache()
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
    private nonisolated static func sweepRouteCache() -> Int {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        var removed = 0
        for region in Region.ordered {
            guard let contents = try? manager.contentsOfDirectory(
                at: cacheDirectory(country: region.code),
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            else { continue }
            let entries = contents.compactMap { url -> (url: URL, written: Date)? in
                guard url.pathExtension == "json",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            guard entries.count > routeCacheEntryBudget else { continue }
            let doomed = entries
                .sorted { $0.written < $1.written }
                .prefix(entries.count - routeCacheEntryBudget)
            for entry in doomed {
                // A failure needs no handling: the entry either went or it did
                // not, and either way the next load re-solves what is missing.
                guard (try? manager.removeItem(at: entry.url)) != nil else { continue }
                removed += 1
            }
        }
        return removed
    }

    private nonisolated static func routeSectionBoundarySharesExplicitStop(
        _ previous: RouteSection, _ next: RouteSection
    ) -> Bool {
        RouteSolver.routeSectionBoundarySharesExplicitStop(previous, next)
    }

    private struct Part: Decodable {
        let train: Train
        let route: CachedRoute?
        let sourceHashes: [String: String]?
        enum CodingKeys: String, CodingKey {
            case train, route
            case sourceHashes = "source_hashes"
        }
    }

    private struct CachedRoute: Decodable {
        let features: [Feature]?
        let solverContext: RailPrecomputedSolverContext?

        private enum CodingKeys: String, CodingKey {
            case features
            case solverContext = "solver_context"
        }
    }

    private struct Feature: Decodable {
        let properties: Properties?
        let geometry: Geometry
    }

    private struct Properties: Decodable {
        let routeTemplateKey: String?
        let segmentIndex: Int?
        let from: String?
        let to: String?
        let requiredLineNames: [String]?
        let preferredLineNames: [String]?
        let requiredOperatorNames: [String]?
        let preferredOperatorNames: [String]?
        let requiredLineIDs: [String]?
        let sectionCodes: [String]?
        let fromStationCode: String?
        let toStationCode: String?
        let temporalKind: RouteGraph.TemporalKind?
        let historyIDs: [String]?
        let validFrom: String?
        let validTo: String?
        private enum CodingKeys: String, CodingKey {
            case routeTemplateKey = "route_template_key"
            case segmentIndex = "segment_index"
            case from, to
            case requiredLineNames = "required_line_names"
            case preferredLineNames = "preferred_line_names"
            case requiredOperatorNames = "required_operator_names"
            case preferredOperatorNames = "preferred_operator_names"
            case requiredLineIDs = "required_line_ids"
            case sectionCodes = "section_codes"
            case fromStationCode = "from_n02_station_code"
            case toStationCode = "to_n02_station_code"
            case temporalKind = "temporal_kind"
            case historyIDs = "history_ids"
            case validFrom = "valid_from"
            case validTo = "valid_to"
        }
    }

    private nonisolated static let resourceRevisionState = Result { try RailResourceRevisions.bundled() }

    /// An unavailable attestation disables disk cache reuse and precomputed
    /// routes; the physical solver remains usable and the reason stays visible.
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

    private struct PrecomputedSources: Decodable {
        let sourceHashes: [String: String]?
        enum CodingKeys: String, CodingKey { case sourceHashes = "source_hashes" }
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

    private struct Geometry: Decodable {
        let strokes: [[Coordinate]]

        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .type) {
            case "LineString":
                let raw = try container.decode([[Double]].self, forKey: .coordinates)
                strokes = [Self.coordinates(raw)]
            case "MultiLineString":
                let raw = try container.decode([[[Double]]].self, forKey: .coordinates)
                strokes = raw.map(Self.coordinates)
            default:
                strokes = []
            }
        }

        private static func coordinates(_ raw: [[Double]]) -> [Coordinate] {
            raw.compactMap { pair in
                guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite else { return nil }
                return Coordinate(lon: pair[0], lat: pair[1])
            }
        }
    }

    enum LoadError: LocalizedError {
        case missingManifest(String)
        case missingPart(String, String)
        case missingSolverResources(String)
        case invalidHistory(String, String)

        var errorDescription: String? {
            switch self {
            case .missingManifest(let dataset):
                "\(dataset)/manifest.json is missing from the app bundle."
            case .missingPart(let dataset, let name):
                "\(dataset)/\(name).json is missing from the app bundle."
            case .missingSolverResources(let country):
                "Runtime solver resources for \(country) are missing from the app bundle."
            case .invalidHistory(let country, let reason):
                "Rail history database for \(country) is invalid: \(reason)"
            }
        }
    }
}

/// Which precomputed part holds which journey, built once per dataset.
///
/// The scan it replaces was paid per journey rather than per dataset: with a
/// cold route cache, every train the load could not answer for reopened and
/// re-decoded all 201 parts of the Japanese sample to discover that 200 of
/// them belonged to somebody else.
///
/// Complete manifest identities answer the first ask without opening any parts.
/// Legacy or incomplete identity maps fall back to the original one-time scan.
/// Selected parts still undergo the normal route decode and provenance checks.
///
/// An `actor` rather than a lock, for the reason ``EdgeIndexCache`` is one:
/// two regions can be decoding at the same time, and the second must wait on
/// the first build instead of starting a second one beside it.
private actor DatasetPartIndex {
    static let shared = DatasetPartIndex()

    /// Positions preserve manifest order, including repeated train identities.
    typealias PartRef = DatasetManifestIndex.PartRef

    private var indexes: [String: [String: [PartRef]]] = [:]
    private var inFlight: [String: Task<[String: [PartRef]], Error>] = [:]

    /// The index for one dataset, building it if this is the first ask.
    func parts(in dataset: String) async throws -> [String: [PartRef]] {
        if let ready = indexes[dataset] { return ready }
        if let running = inFlight[dataset] { return try await running.value }

        let task = Task.detached(priority: .userInitiated) {
            try Self.build(dataset: dataset)
        }
        inFlight[dataset] = task
        defer { inFlight[dataset] = nil }
        // Detached, so a load cancelled halfway through the scan does not take
        // it down and leave the next load to start it over. The scan is worth
        // finishing: it is the only thing that ever has to read these files.
        let built = try await task.value
        indexes[dataset] = built
        return built
    }

    /// Use manifest identities when complete; otherwise read each part for its id.
    ///
    /// ``PartIdentity`` deliberately cannot see the route: the coordinate
    /// arrays are nearly all of a part's bytes and the scan needs none of
    /// them, so what would have been a full geometry decode is now a parse
    /// that keeps one string.
    private nonisolated static func build(dataset: String) throws -> [String: [PartRef]] {
        guard let manifestURL = Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: dataset
        ) else { throw RiddenRouteStore.LoadError.missingManifest(dataset) }

        let manifest = try JSONDecoder().decode(
            DatasetManifestIndex.self,
            from: Data(contentsOf: manifestURL)
        )
        if let index = manifest.indexedParts { return index }
        var index: [String: [PartRef]] = [:]
        index.reserveCapacity(manifest.parts.count)
        for (position, name) in manifest.parts.enumerated() {
            guard let partURL = Bundle.main.url(
                forResource: name,
                withExtension: "json",
                subdirectory: dataset
            ) else { throw RiddenRouteStore.LoadError.missingPart(dataset, name) }
            let identity = try JSONDecoder().decode(
                PartIdentity.self, from: Data(contentsOf: partURL))
            // Appended rather than assigned. The datasets that ship carry one
            // part per journey, but a dataset that ever carried two for the
            // same id would have had both searched before, and dropping one
            // here would silently stop drawing a route that used to draw.
            index[identity.train.id, default: []].append(
                PartRef(name: name, position: position))
        }
        return index
    }

    private struct PartIdentity: Decodable {
        let train: TrainIdentity

        struct TrainIdentity: Decodable {
            let id: String
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
