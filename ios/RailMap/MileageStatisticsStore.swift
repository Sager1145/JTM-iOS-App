import Foundation
import Observation
import RailCore

/// Owner of the 里程統計 numbers.
///
/// Every figure on the statistics screen comes out of `RailCore.Statistics`,
/// which is the ported reference implementation and is covered by parity
/// fixtures. Nothing is aggregated here — this type only decides *when* the
/// ported functions run, on which inputs, and what the screen is told while
/// they are running.
///
/// Three things beyond the original port live here:
///
/// - **A date scope of its own.** `app-stats.js` reads the one global
///   `selectedDate` that the date bar writes, so the web panel silently
///   follows the ride list's filter. The native app has a tab bar rather than
///   one page, and the rides workspace owns its own `selectedDate`; a
///   statistics screen that changed the ride list's filter (or was changed by
///   it) from another tab would be a filter that moves while you are not
///   looking at it. So the scope is held here and nowhere else.
/// - **Stages (§7.8 / §13.2).** Building the edge index parses the whole rail
///   network, which is seconds, not milliseconds. A bare spinner would say
///   nothing for that whole time, so the phase in flight — and the ride count
///   while rides are being matched — is published as it goes.
/// - **A cache with a fingerprint in front of it.** The web panel is rebuilt
///   when its one page re-renders; this store is asked to reload whenever
///   anything about a journey changes, because the shell's route key is the
///   whole record (see `ContentView.statisticsLoadKey`, and the reason it is
///   deliberately coarse). Renaming a journey, recolouring it or hiding it
///   from the map changes nothing a kilometre is made of, and re-answering
///   the same question is not free: it walks every vertex of every ride
///   against a 377,620-edge index, and it takes the numbers off the screen
///   and puts a progress stage in their place while it does. So ``load`` now
///   opens by fingerprinting exactly what the figures are a function of, and
///   returns having touched nothing when that has not moved. See
///   ``Fingerprint``. A rename, a company correction or any other edit to a
///   passport-only field still has to move `self.passport`, but it changes
///   nothing the mileage half reads — so when a fingerprint's difference is
///   confined to `Journey.passport`, ``load`` skips straight to regrouping
///   the passport from the entries the last full load already matched,
///   rather than re-reading the network and re-matching every ride to answer
///   a question mileage never asked. See ``reloadPassportOnly(fingerprint:trains:entries:)``.
@MainActor
@Observable
final class MileageStatisticsStore {
    enum State {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// §7.8 ProgressSummary: the stage in flight, how far it has got when that
    /// is knowable, and whether the reader has to wait for it.
    struct Progress: Equatable {
        enum Stage: Equatable {
            /// Reading and indexing `rail-sections*.json`.
            case readingNetwork
            /// Matching each ride's drawn geometry onto network edges.
            case matchingRides
            /// The deduped union, the service rows, the most-ridden sections.
            case aggregating
            /// Re-running the day slice after the scope changed.
            case scopingDay

            var localizationKey: String {
                switch self {
                case .readingNetwork: "ios.stats.stage.readingNetwork"
                case .matchingRides: "ios.stats.stage.matchingRides"
                case .aggregating: "ios.stats.stage.aggregating"
                case .scopingDay: "ios.stats.stage.scopingDay"
                }
            }
        }

        var stage: Stage
        var completed: Int?
        var total: Int?
        /// Nothing here blocks the rest of the app, and the screen keeps the
        /// previous answer on display while a rescope runs.
        var interactionContinues: Bool = true
    }

    private(set) var state: State = .idle
    private(set) var view: Statistics.MileageStatsView?
    private(set) var totalsByMask: [Int: Double] = [:]
    /// `idx.totals.all` — the denominator of the headline coverage figure.
    private(set) var totalKm: Double = 0
    private(set) var lineTotals: [(name: String, byMask: [Int: Double])] = []
    private(set) var lineOperators: [String: String] = [:]
    /// The per-journey grouping the passport's Flighty-shaped cards read —
    /// the distributions, the ranked lists, the superlatives. See
    /// ``PassportStatistics``, which is where the reasoning lives.
    ///
    /// All-time for the region in scope, like ``view``'s `overall` and unlike
    /// its `daily`: the day slice answers a question the reader asked in the
    /// panel header, and these cards answer the passport's own. So it is
    /// computed once per load and left alone by ``selectDate(_:)``.
    private(set) var passport: PassportStatistics?
    private(set) var progress: Progress?

    /// The statistics screen's own date bucket, in the same vocabulary the
    /// date bar uses: `Dates.allDates`, `Dates.undated`, or `YYYY-MM-DD`.
    ///
    /// Deliberately not shared with `RailWorkspaceView.selectedDate`.
    private(set) var selectedDate: String = Dates.allDates

    /// The date buckets the loaded rides actually occupy, in date-bar order.
    /// Used to keep a stale scope from surviving a reload.
    private(set) var availableDates: [String] = []

    private var task: Task<Void, Never>?
    private var passportTask: Task<Void, Never>?
    private var scopeTask: Task<Void, Never>?
    private var context: Context?

    /// The fingerprint the published figures answer for, or `nil` when they
    /// answer for nothing — before the first load, and after any failure.
    ///
    /// Written when a load STARTS rather than when it finishes, so that a
    /// second call with the same inputs while the first is still matching
    /// rides joins the answer already coming instead of cancelling it and
    /// starting again. Cleared on failure so that a retry is a retry: an
    /// error is not an answer to be reused, and a screen stuck on "could not
    /// be calculated" until an unrelated edit moves the key would be the cache
    /// remembering the wrong thing.
    private var servedFingerprint: Fingerprint?

    /// The fingerprint `context` was actually built for — set only where
    /// `self.context` is set, on a load that RAN TO COMPLETION, and cleared
    /// wherever `context` is cleared.
    ///
    /// Distinct from `servedFingerprint`, which is written when a load
    /// STARTS: a passport-only reload has to pair the new `trains` against
    /// `context.entries`, and it may only do that when `context` itself was
    /// built for inputs that are still current — not merely started for them.
    /// Without this, a passport edit that arrives while a full load is still
    /// matching rides would regroup stale entries instead of joining, or
    /// waiting for, the load already in flight.
    private var contextFingerprint: Fingerprint?

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    /// Load the numbers for one region, or for all of them at once.
    ///
    /// `countries` is a list because §5.3.1's scope now has an 全部 entry. One
    /// entry behaves exactly as this method always did; several are read as a
    /// single network — see `EdgeIndexCache.merged`, and `categoryCountry`
    /// for which vocabulary the rows are then named in.
    ///
    /// Returns immediately, having changed nothing, when the fingerprint of
    /// what it was handed matches the one on screen. That is the ordinary case
    /// now: the shell re-keys this load on the whole record of every journey,
    /// so an edit to a colour, a name, a note or a visibility flag arrives
    /// here as a call with identical inputs. See ``Fingerprint``.
    ///
    /// An empty journey list is answered synchronously without reading a rail
    /// package. The screen already has a dedicated empty state, so there is no
    /// numerator to match and no coverage denominator to build. Keeping this
    /// guard here (rather than only in the shell) also makes every caller obey
    /// the same no-work contract and lets an empty reload cancel an older
    /// calculation that may still be running.
    func load(countries: [String], trains: [Train], rides: [RiddenRouteStore.DrawnRide]) {
        let fingerprint = Self.fingerprint(countries: countries, trains: trains, rides: rides)
        guard fingerprint != servedFingerprint else { return }
        guard !trains.isEmpty else {
            clearForEmpty(fingerprint: fingerprint)
            return
        }
        // The entries this load would produce, journey for journey, are
        // exactly the ones the last completed load already matched — nothing
        // `collectTrainStatsEntry` reads moved. Regroup those against the new
        // `trains` (so the edited fields land in the passport) instead of
        // reopening the network and rewalking every ride's geometry. `context`
        // is only ever the last COMPLETED load's context (see the `catch`
        // below, which clears it on failure), so its entries are never a
        // half-finished answer.
        if let previous = servedFingerprint, let context, let built = contextFingerprint,
            case .loaded = state,
            Self.sameMileageInputs(built, previous),
            Self.differsOnlyInPassport(previous, fingerprint)
        {
            reloadPassportOnly(fingerprint: fingerprint, trains: trains, entries: context.entries)
            return
        }
        servedFingerprint = fingerprint
        task?.cancel()
        passportTask?.cancel()
        scopeTask?.cancel()
        state = .loading
        let total = trains.count
        let country = Self.categoryCountry(for: countries)
        task = Task { [weak self] in
            guard let self else { return }
            let interval = RailSignpost.jobs.begin("stats.load")
            defer { RailSignpost.jobs.end("stats.load", interval) }
#if DEBUG
            let started = ContinuousClock.now
#endif
            do {
                self.progress = Progress(stage: .readingNetwork)
                let index = try await Self.readNetwork(countries: countries)
                try Task.checkCancellation()
#if DEBUG
                let indexed = ContinuousClock.now
#endif

                self.progress = Progress(stage: .matchingRides, completed: 0, total: total)
                // The entry cache is only valid against the index it was
                // matched on — its edge ids are indices into that index's
                // arrays — so a change of scope starts from nothing.
                let indexKey = countries.joined(separator: ",")
                if self.entryCacheIndexKey != indexKey {
                    self.entryCache = [:]
                    self.entryCacheIndexKey = indexKey
                }
                let prepared = try await Self.matchRides(
                    trains: trains, journeys: fingerprint.journeys, rides: rides, index: index,
                    cache: self.entryCache,
                    report: { [weak self] done in
                        Task { @MainActor in
                            guard let self, self.servedFingerprint == fingerprint,
                                self.progress?.stage == .matchingRides else { return }
                            self.progress = Progress(
                                stage: .matchingRides, completed: done, total: total)
                        }
                    })
                try Task.checkCancellation()
#if DEBUG
                let matched = ContinuousClock.now
#endif

                self.progress = Progress(stage: .aggregating)
                let context = Context(
                    country: country, index: index,
                    trains: prepared.trains, entries: prepared.entries)

                // A scope that no longer names a real day cannot be answered.
                // Falling back to the combined view rather than to the first
                // remaining day keeps the reset visible: the screen says 全部
                // and reads `--`, instead of quietly reporting a day nobody
                // asked about.
                let dates = Dates.availableDates(prepared.trains.map(\.forDateBucket))
                if self.selectedDate != Dates.allDates,
                    !dates.contains(self.selectedDate)
                {
                    self.selectedDate = Dates.allDates
                }
                let scope = self.selectedDate

                let result = try await Self.aggregate(context: context, selectedDate: scope)
                try Task.checkCancellation()
                // Grouped from the entries that were just matched, off the
                // main actor for the same reason the aggregate is: it is a
                // pass over every stop of every journey, and the panel it
                // lands in is a scroll view the reader may already be moving.
                let grouped = await Self.group(trains: trains, entries: prepared.entries)
                try Task.checkCancellation()
#if DEBUG
                let finished = ContinuousClock.now
                NSLog("[stats.timing] regions=%@ rides=%d read=%@ match=%@ aggregate=%@ total=%@",
                    countries.joined(separator: ","), total,
                    String(describing: started.duration(to: indexed)),
                    String(describing: indexed.duration(to: matched)),
                    String(describing: matched.duration(to: finished)),
                    String(describing: started.duration(to: finished)))
#endif

                self.context = context
                self.contextFingerprint = fingerprint
                self.entryCache = prepared.cache
                self.availableDates = dates
                self.view = result
                self.totalsByMask = index.totalsByMask
                self.totalKm = index.totalKm
                self.lineTotals = index.lineTotByCat.pairs.map { ($0.key, $0.value) }
                self.lineOperators = Dictionary(
                    index.lineOperator.pairs.map { ($0.key, $0.value) },
                    uniquingKeysWith: { first, _ in first })
                self.passport = grouped
                self.progress = nil
                self.state = .loaded
                // The scope can be moved while the load is still running; the
                // answer just computed is then for the wrong day.
                if self.selectedDate != scope { self.rescope() }
            } catch is CancellationError {
                return
            } catch {
                // Only if these figures are still ours to clear. A load that
                // was superseded can reach here between two cancellation
                // checkpoints, and it must not take down the answer the load
                // that replaced it is producing.
                guard self.servedFingerprint == fingerprint else { return }
                self.servedFingerprint = nil
                self.context = nil
                self.contextFingerprint = nil
                self.view = nil
                self.passport = nil
                self.availableDates = []
                self.lineTotals = []
                self.lineOperators = [:]
                self.progress = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    /// Whether `a` and `b` name the same country scope and the same journeys,
    /// in the same order, with none of `id`, `trainType`, `date` or `entry`
    /// moved — everything a mileage figure reads. `Journey.passport` may
    /// differ or not; this says nothing about it.
    ///
    /// A positional comparison is enough to also confirm the two fingerprints
    /// name the same journeys in the same order: `Journey.id` is one of the
    /// fields compared at each position, so two fingerprints that pass this
    /// check were built from `trains` arrays holding the same journeys,
    /// identically ordered — which is exactly what lets
    /// ``reloadPassportOnly(fingerprint:trains:entries:)`` pair the new
    /// `trains` against the old `entries` positionally.
    private nonisolated static func sameMileageInputs(_ a: Fingerprint, _ b: Fingerprint) -> Bool {
        guard a.countries == b.countries, a.journeys.count == b.journeys.count else { return false }
        for (x, y) in zip(a.journeys, b.journeys) {
            guard x.id == y.id, x.trainType == y.trainType, x.date == y.date, x.entry == y.entry
            else { return false }
        }
        return true
    }

    /// Whether `a` and `b` differ ONLY in `Journey.passport`: ``sameMileageInputs``
    /// holds, and at least one journey's passport actually moved.
    private nonisolated static func differsOnlyInPassport(_ a: Fingerprint, _ b: Fingerprint) -> Bool {
        guard sameMileageInputs(a, b) else { return false }
        return zip(a.journeys, b.journeys).contains { $0.passport != $1.passport }
    }

    /// The cheap half of ``load``, for an edit that only moved a passport-only
    /// field.
    ///
    /// `PassportStatistics.build` is a pure function of `trains` and
    /// `entries`; `entries` is untouched by this kind of edit, so this reruns
    /// only that grouping pass, against the new `trains` so the edit actually
    /// lands, and publishes nothing else — `context`, `view`, the totals and
    /// `availableDates` all still answer for the same mileage inputs they
    /// always did.
    ///
    /// Follows ``load``'s own discipline: `servedFingerprint` is written
    /// before the work starts, so a second identical call joins this one
    /// instead of restarting it; the previous passport-only task is
    /// cancelled; and the eventual publish is guarded so a load that
    /// supersedes this one — full or passport-only — is never overwritten by
    /// a slower straggler.
    ///
    /// Deliberately touches nothing but `passport`: `state`, `progress`,
    /// `context` and `view` are left exactly as the last full load set them,
    /// because the figures they answer for are already correct for everything
    /// but the passport, so there is nothing to blank, no phase to announce,
    /// and no ownership of `context` to hand off.
    ///
    /// Runs on its own `passportTask` rather than the shared `task` so that
    /// this can never cancel a FULL load — the gate in ``load`` that calls
    /// this already guarantees no full load is in flight, but a later full
    /// load must still be able to tell the two apart and cancel only this
    /// one. `scopeTask` is left running: `context` is unchanged by this path,
    /// so a rescope already under way is still computing the right answer.
    private func reloadPassportOnly(
        fingerprint: Fingerprint, trains: [Train], entries: [Statistics.TrainEntry]
    ) {
        servedFingerprint = fingerprint
        passportTask?.cancel()
        passportTask = Task { [weak self] in
            guard let self else { return }
            let interval = RailSignpost.jobs.begin("stats.passportOnly")
            defer { RailSignpost.jobs.end("stats.passportOnly", interval) }
            let grouped = await Self.group(trains: trains, entries: entries)
            guard !Task.isCancelled, self.servedFingerprint == fingerprint else { return }
            self.passport = grouped
        }
    }

    /// Publish the absence of statistics without touching ``EdgeIndexCache``.
    ///
    /// Every value from the previous answer is cleared together. In
    /// particular, retaining `context` would let a later date selection
    /// aggregate the deleted journeys again, while retaining `progress` would
    /// leave the empty card claiming that a calculation was still underway.
    private func clearForEmpty(fingerprint: Fingerprint) {
        task?.cancel()
        passportTask?.cancel()
        scopeTask?.cancel()
        task = nil
        passportTask = nil
        scopeTask = nil
        servedFingerprint = fingerprint
        context = nil
        contextFingerprint = nil
        view = nil
        totalsByMask = [:]
        totalKm = 0
        lineTotals = []
        lineOperators = [:]
        passport = nil
        progress = nil
        selectedDate = Dates.allDates
        availableDates = []
        entryCache = [:]
        entryCacheIndexKey = ""
        state = .idle
    }

    /// Move the statistics screen's own date scope.
    ///
    /// Only the day slice depends on it — `overall` is computed from every
    /// entry regardless — but the whole view model is rebuilt through the same
    /// `buildMileageStatsView` the web app calls, rather than assembling a
    /// `MileageStatsView` here out of parts. Recomputing an aggregate we could
    /// have cached is cheap next to the risk of a hand-assembled view drifting
    /// from the ported one; the expensive half (reading the network, matching
    /// every ride) is what the cached `Context` skips.
    func selectDate(_ date: String) {
        guard date != selectedDate else { return }
        selectedDate = date
        rescope()
    }

    private func rescope() {
        guard let context else { return }
        // The fingerprint `context` was built for — `contextFingerprint`,
        // not `servedFingerprint`. A load that replaces `context` also
        // replaces `contextFingerprint` (see ``load``, which writes both
        // under one `self.context = context` / no intervening suspension), so
        // comparing against the fingerprint captured here — rather than
        // reusing the `context` local, which stays the OLD value for the life
        // of this task — is what stops a rescope that started before a
        // replacement load from publishing its stale answer after that load
        // finishes. `servedFingerprint` would be wrong here: a passport-only
        // reload moves it without touching `context`, and this rescope must
        // still recognise itself as owning the same, unchanged context.
        let owningFingerprint = contextFingerprint
        scopeTask?.cancel()
        let scope = selectedDate
        scopeTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.progress = Progress(stage: .scopingDay)
                let result = try await Self.aggregate(context: context, selectedDate: scope)
                try Task.checkCancellation()
                guard self.contextFingerprint == owningFingerprint else { return }
                self.view = result
                self.progress = nil
                self.state = .loaded
            } catch is CancellationError {
                return
            } catch {
                // The day slice failed, so what is on screen is no longer the
                // answer to anything. Forgetting `servedFingerprint` is what
                // lets the next identical load actually run and recover — but
                // only if this rescope still owns the figures on screen,
                // checked against `contextFingerprint`; a rescope superseded
                // by a new load, or by a passport-only reload that replaced
                // `servedFingerprint` without touching `context`, must not
                // clear a fingerprint out from under it.
                guard self.contextFingerprint == owningFingerprint else { return }
                self.servedFingerprint = nil
                self.progress = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - the phases

    /// The region's edge index, from the cache that owns it.
    ///
    /// This used to read and index `rail-sections*.json` itself, once per
    /// load. The numbers now reload on every edit rather than only on an add
    /// or a delete, and the network is the same file every time — see
    /// ``EdgeIndexCache``, which is also what the map's ridden-line category
    /// filter classifies against.
    private nonisolated static func readNetwork(
        countries: [String]
    ) async throws -> Statistics.EdgeIndex {
        let interval = RailSignpost.jobs.begin("stats.readNetwork")
        defer { RailSignpost.jobs.end("stats.readNetwork", interval) }
        let index = try await EdgeIndexCache.shared.merged(countries: countries)
        try Task.checkCancellation()
        return index
    }

    /// Whose vocabulary the category rows are named in.
    ///
    /// One region answers for itself. Several have no single answer, and the
    /// catalog's own default is the one that fits: `Statistics.categories`
    /// falls through to the FULL list — 新幹線, 在來線, JR, 地下鐵, 私鐵, 路面
    /// 電車 — which is exactly the union an all-regions panel has to be able
    /// to show. Naming it after any one of the five would hide the rows the
    /// other four need.
    private nonisolated static func categoryCountry(for countries: [String]) -> String {
        countries.count == 1 ? countries[0] : Region.jp.code
    }

    /// One journey's matched entry, with the digest of everything it was
    /// computed from.
    ///
    /// `collectTrainStatsEntry` is a pure function of four things: the drawn
    /// geometry, each section's two endpoint names, which sections were
    /// RIDDEN, and the edge index. So an entry can be reused exactly when all
    /// four are unchanged, and the digest is those four and nothing else — a
    /// key built from fewer would reuse an entry the reader's edit had
    /// invalidated, which is a mileage figure that silently does not move.
    struct CachedEntry: Sendable {
        let digest: Int
        let entry: Statistics.TrainEntry
    }

    /// Every journey's entry from the last load, and the index they were
    /// matched against.
    ///
    /// The second of the two caches, and the one that survives a load which
    /// actually has work to do. Measured over the national sample in release
    /// (`ios/tools/bench`, Apple silicon), against the 377,620-edge Japanese
    /// index: matching all 201 journeys is **425 ms**, and matching one is
    /// 1.96 ms — so an edit that moves one journey pays for one, not 201.
    ///
    /// ``Fingerprint`` sits in front of it and answers a different question.
    /// This one asks, per journey, "may I reuse the entry I matched last
    /// time"; the fingerprint asks, of the whole load, "is there anything to
    /// re-answer at all" — and when there is not, none of this runs, the
    /// network is not re-read, and the figures never leave the screen. Before
    /// either existed, recolouring one journey re-walked every vertex of every
    /// other one, because the shell's route key is the whole record.
    private var entryCache: [String: CachedEntry] = [:]
    /// Which index `entryCache` was built against; a scope change invalidates
    /// every entry in it, because the edge ids an entry holds are indices into
    /// that index's own arrays.
    private var entryCacheIndexKey = ""

    private nonisolated static func matchRides(
        trains: [Train], journeys: [Fingerprint.Journey],
        rides: [RiddenRouteStore.DrawnRide], index: Statistics.EdgeIndex,
        cache: [String: CachedEntry],
        report: @Sendable (Int) -> Void
    ) async throws -> Prepared {
        let interval = RailSignpost.jobs.begin("stats.matchRides")
        defer { RailSignpost.jobs.end("stats.matchRides", interval) }
        let ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var statisticsTrains: [Statistics.Train] = []
        var entries: [Statistics.TrainEntry] = []
        var fresh: [String: CachedEntry] = [:]
        statisticsTrains.reserveCapacity(trains.count)
        entries.reserveCapacity(trains.count)
        fresh.reserveCapacity(trains.count)

        // `journeys` was built from `trains`, in this order, one element each —
        // it is the value ``load`` compared to decide this run was needed at
        // all. Read here rather than recomputed so the date bucket and the
        // entry digest have exactly one definition: a fingerprint that said
        // "unchanged" while the matcher keyed on something else would be a
        // cache that hides an edit.
        for (position, pair) in zip(trains, journeys).enumerated() {
            let (train, journey) = pair
            try Task.checkCancellation()
            let stops = train.stops.map {
                Statistics.Stop(
                    arrival: $0.arrival, departure: $0.departure,
                    stopType: $0.stopType, rideSegment: $0.rideSegment)
            }
            // `date` carries the normalised date BUCKET, not the raw field:
            // the day slice compares it against a bucket the date bar named,
            // and `getTrainDate` in the web app normalises there too. A train
            // with no usable date lands in `Dates.undated`, which is a bucket
            // the reader can select, not a missing value.
            let statisticsTrain = Statistics.Train(
                id: train.id, trainType: train.trainType,
                date: journey.date, stops: stops)
            statisticsTrains.append(statisticsTrain)
            let ride = ridesByID[train.id]
            let digest = journey.entry
            if let cached = cache[train.id], cached.digest == digest {
                entries.append(cached.entry)
                fresh[train.id] = cached
                if position % 25 == 24 { report(position + 1) }
                continue
            }
            let features = ride?.segments.map { segment in
                Statistics.RouteFeature(
                    // Statistics indexes the canonical WGS84 rail package.
                    // `coordinates` is presentation-only GCJ-02 in four
                    // regions and will not match that index there.
                    lines: [segment.sourceCoordinates], hasGeometry: true,
                    rideSegment: Statistics.isRideSegment(
                        stops, segmentIndex: segment.segmentIndex),
                    from: segment.from, to: segment.to)
            } ?? []
            let entry = Statistics.collectTrainStatsEntry(features: features, index: index)
            entries.append(entry)
            fresh[train.id] = CachedEntry(digest: digest, entry: entry)
            // Reported in blocks: one hop to the main actor per train would
            // cost more than the matching itself on a small store.
            if position % 25 == 24 { report(position + 1) }
        }
        report(trains.count)
        return Prepared(trains: statisticsTrains, entries: entries, cache: fresh)
    }

    // MARK: - what the numbers are a function of

    /// Every input the published figures depend on, and nothing else.
    ///
    /// The shell cannot key this load precisely — it holds whole `Train`
    /// records and has no opinion on which of their forty fields a kilometre
    /// is made of — so the decision is made here, where that IS known. What a
    /// figure on this screen depends on is:
    ///
    ///   - the region scope, because it picks the edge index every distance is
    ///     measured against and the vocabulary the category rows are named in;
    ///   - per journey, in order: the id, the service description that groups
    ///     the 種別 rows, the normalised date bucket the day slice compares
    ///     against, ``entryDigest(train:ride:)`` — which is itself the four
    ///     things `collectTrainStatsEntry` reads — and ``passportDigest(train:)``,
    ///     which covers everything ``PassportStatistics/build(trains:entries:)``
    ///     reads off the record directly that is not already one of the first
    ///     three. ``passport`` is grouped from the same matched entries this
    ///     load produces, so a load is still the one place both screens'
    ///     numbers come from — see ``Fingerprint``'s own note on why the
    ///     operator is in scope here even though no *mileage* figure reads it.
    ///
    /// **In order**, and that is not incidental: the deduped union walks the
    /// ridden set in insertion order, so two stores with the same journeys
    /// listed differently are not guaranteed the same last bit of a total.
    /// `StatisticsParityTests.orderOfTheRiddenSet` is the test that says so.
    ///
    /// Everything a journey carries that is NOT here — colour, visibility,
    /// notes, the ride's own region tag, the route policy — changes no figure
    /// on this screen, which is exactly why the fingerprint is a listing
    /// rather than a hash of the record.
    ///
    /// The operator is the one exception noted above: it moves nothing this
    /// struct computes itself, but it moves ``PassportStatistics/operators``,
    /// which is grouped from the same journeys this load matches. So is every
    /// field ``passportDigest(train:)`` reads — see there for the list — and
    /// each is covered by `Journey.passport` below, not by pretending the
    /// passport screen reads a strict subset of what this one does.
    struct Fingerprint: Equatable, Sendable {
        let countries: [String]
        let journeys: [Journey]

        struct Journey: Equatable, Sendable {
            let id: String
            let trainType: String?
            /// `Dates.trainDate` — the bucket, not the raw field.
            let date: String
            /// ``entryDigest(train:ride:)``.
            let entry: Int
            /// ``passportDigest(train:)``. Split out from the other four
            /// fields rather than folded into one of them, so that an edit
            /// which moves ONLY this one — a rename, a company correction, a
            /// stop name or code — can be told apart from an edit that also
            /// moves mileage. ``differsOnlyInPassport(_:_:)`` is what looks
            /// for exactly that difference, and ``reloadPassportOnly`` is
            /// what a positive answer skips straight to.
            let passport: Int
        }
    }

    private nonisolated static func fingerprint(
        countries: [String], trains: [Train], rides: [RiddenRouteStore.DrawnRide]
    ) -> Fingerprint {
        let interval = RailSignpost.jobs.begin("stats.fingerprint")
        defer { RailSignpost.jobs.end("stats.fingerprint", interval) }
        let ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Fingerprint(
            countries: countries,
            journeys: trains.map { train in
                Fingerprint.Journey(
                    id: train.id,
                    trainType: train.trainType,
                    // The stops are dropped rather than mapped: no branch of
                    // `normalizeTrainDate` reads them — it takes the explicit
                    // date, then the eight digits spelled in the id, then
                    // `undated` — and building every stop of every journey to
                    // answer a question that ignores them is the cost this
                    // whole fingerprint exists to avoid paying.
                    date: Dates.trainDate(
                        Dates.Train(id: train.id, date: train.date, stops: [])),
                    entry: entryDigest(train: train, ride: ridesByID[train.id]),
                    passport: passportDigest(train: train))
            })
    }

    /// Everything ``PassportStatistics/build(trains:entries:)`` reads off one
    /// `Train` directly that is not already covered by `Journey.trainType`,
    /// `Journey.date` (the bucket) or ``entryDigest(train:ride:)`` (the stop
    /// fields `effectivelyRiddenStopIndexes` and `trainRideMinutes` read).
    ///
    /// That leaves: the raw `date` string — `journeyClock.rideMinutes(on:)`
    /// reads the record's own field, not the normalised bucket, so two
    /// journeys sharing a bucket but not a timestamp can still owe different
    /// minutes; `number`, which `JourneyTitle.compact` reads together with
    /// `trainType`; `company`, which groups ``PassportStatistics/operators``;
    /// `region`, plus each stop's `n02StationCode` and each route section's
    /// endpoint codes, which is everything `RegionScopeRule.matched` (via
    /// `Region.resolved`) reads to decide a journey's region — and each stop's
    /// `name`, which is what a station or route row is keyed and named on.
    ///
    /// This is deliberately a flat listing rather than a hash of the whole
    /// `Train`, for the same reason ``entryDigest(train:ride:)`` is: a hash of
    /// everything would also change on a colour, a note or a visibility flag,
    /// which is exactly the re-walk this fingerprint exists to skip.
    private nonisolated static func passportDigest(train: Train) -> Int {
        var hasher = Hasher()
        hasher.combine(train.date)
        hasher.combine(train.number)
        hasher.combine(train.company)
        hasher.combine(train.region)
        for stop in train.stops {
            hasher.combine(stop.name)
            hasher.combine(stop.n02StationCode)
        }
        for section in train.routeSections ?? [] {
            hasher.combine(section.fromN02StationCode)
            hasher.combine(section.toN02StationCode)
        }
        return hasher.finalize()
    }

    /// Everything ``Statistics/collectTrainStatsEntry(features:index:)`` reads
    /// about one journey, as one number.
    ///
    /// The geometry arrives already digested — `DrawnRide.geometryDigest`
    /// covers the section count, each section's index and each section's
    /// canonical WGS84 coordinates — so this adds the two things it does not
    /// cover and that the entry does read: each section's `from`/`to`, which
    /// decide whether a section is attributed at all, and the stop fields
    /// `isRideSegment` consults.
    ///
    /// A journey with no drawn route is distinguished from one whose route
    /// arrived: both produce an empty feature list today, but the second will
    /// stop doing so the moment it solves, and a digest that could not tell
    /// them apart would keep serving the empty answer.
    private nonisolated static func entryDigest(
        train: Train, ride: RiddenRouteStore.DrawnRide?
    ) -> Int {
        var hasher = Hasher()
        if let ride {
            hasher.combine(true)
            hasher.combine(ride.geometryDigest)
            for segment in ride.segments {
                hasher.combine(segment.from)
                hasher.combine(segment.to)
            }
        } else {
            hasher.combine(false)
        }
        for stop in train.stops {
            hasher.combine(stop.arrival)
            hasher.combine(stop.departure)
            hasher.combine(stop.stopType)
            hasher.combine(stop.rideSegment)
        }
        return hasher.finalize()
    }

    private nonisolated static func aggregate(
        context: Context, selectedDate: String
    ) async throws -> Statistics.MileageStatsView {
        let interval = RailSignpost.jobs.begin("stats.aggregate")
        defer { RailSignpost.jobs.end("stats.aggregate", interval) }
        try Task.checkCancellation()
        // `dateLabel` is the identity: the label is a translation, so the day
        // bucket travels to the screen unresolved and `Dates.dateLabelKey` is
        // read there. That is exactly why the port made it a parameter.
        return Statistics.buildMileageStatsView(
            index: context.index, trains: context.trains, entries: context.entries,
            country: context.country, selectedDate: selectedDate,
            trainDate: { $0.date ?? Dates.undated },
            dateLabel: { $0 })
    }

    /// The passport's per-journey grouping, off the main actor.
    ///
    /// `async` for that reason alone — nothing in it awaits. A `nonisolated`
    /// async function runs on the generic executor, which is what keeps a pass
    /// over every stop of every journey out of the frame the panel is drawing.
    private nonisolated static func group(
        trains: [Train], entries: [Statistics.TrainEntry]
    ) async -> PassportStatistics {
        let interval = RailSignpost.jobs.begin("stats.group")
        defer { RailSignpost.jobs.end("stats.group", interval) }
        return PassportStatistics.build(trains: trains, entries: entries)
    }

    private struct Context: Sendable {
        let country: String
        let index: Statistics.EdgeIndex
        let trains: [Statistics.Train]
        let entries: [Statistics.TrainEntry]
    }

    private struct Prepared: Sendable {
        let trains: [Statistics.Train]
        let entries: [Statistics.TrainEntry]
        /// Only the journeys this load actually saw. Rebuilt rather than
        /// merged so a deleted journey's entry leaves with it: an entry cache
        /// that only ever grows is a leak with a plausible name.
        let cache: [String: CachedEntry]
    }
}

private extension Statistics.Train {
    /// The already-normalised bucket, handed back to `Dates` so the screen's
    /// date list is built by the same rule the date bar uses.
    var forDateBucket: Dates.Train {
        Dates.Train(id: id, date: date, stops: [])
    }
}
