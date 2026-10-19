import Foundation
import Observation
import RailCore
import RailApplication
import RailPresentation

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
///   whole record (see `AppShell.statisticsLoadKey`, and the reason it is
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
    /// Zero while ``coverageDenominatorKnown`` is false: a missing length is
    /// not a finished 0% of the network.
    private(set) var totalKm: Double = 0
    /// True only after a completed index publish whose edge lengths and
    /// total are a real positive denominator.
    private(set) var coverageDenominatorKnown = false
    /// Set when the mileage view is usable but the passport pairing is not.
    private var passportFailure: String?
    private(set) var lineTotals: [(name: String, byMask: [Int: Double])] = []
    private(set) var lineOperators: [String: String] = [:]
    /// The per-journey grouping the passport's Flighty-shaped cards read —
    /// the distributions, the ranked lists, the superlatives. See
    /// ``PassportStatistics``, which is where the reasoning lives.
    ///
    /// For the selected year and region, like ``view``'s `overall` and unlike
    /// its `daily`: the day slice answers a question the reader asked in the
    /// panel header, and these cards answer the passport's own. So it is
    /// computed once per load and left alone by ``selectDate(_:)``.
    private(set) var passport: PassportStatistics?
    private(set) var progress: Progress?
    /// The caller-provided identity of the inputs that produced the currently
    /// published view/passport pair.
    private(set) var publishedInputsKey: String?
    /// Changes whenever a view or passport answer is published.
    private(set) var publishGeneration = 0

    /// The statistics screen's own date bucket, in the same vocabulary the
    /// date bar uses: `Dates.allDates`, `Dates.undated`, or `YYYY-MM-DD`.
    ///
    /// Deliberately not shared with `RailWorkspaceView.selectedDate`.
    private(set) var selectedDate: String = Dates.allDates

    /// Passport's time range. `nil` includes every year and undated rides.
    private(set) var selectedYear: Int?

    enum Classification: String, CaseIterable {
        case date, journeyGroup
    }

    private(set) var classification: Classification = .date
    private(set) var dateSelection = StatisticsDateSelection()
    private(set) var selectedJourneyGroupID: String?

    /// Starts an independent statistics surface from another surface's scope.
    func adoptSelection(from other: MileageStatisticsStore) {
        selectedYear = other.selectedYear
        classification = other.classification
        dateSelection = other.dateSelection
        selectedDate = other.selectedDate
        selectedJourneyGroupID = other.selectedJourneyGroupID
        invalidateScope()
    }

    func selectClassification(_ mode: Classification) {
        guard mode != classification else { return }
        classification = mode
        selectedJourneyGroupID = nil
        dateSelection.clear()
        selectedDate = Dates.allDates
        invalidateScope()
    }

    func selectJourneyGroup(_ groupID: String?) {
        guard groupID != selectedJourneyGroupID || classification != .journeyGroup else { return }
        classification = .journeyGroup
        selectedJourneyGroupID = groupID
        dateSelection.clear()
        selectedDate = Dates.allDates
        invalidateScope()
    }

    func includesJourneyGroup(_ train: Train) -> Bool {
        StatisticsMembership.Selection(groupID: selectedJourneyGroupID).includes(train)
    }

    func includesDate(_ train: Train) -> Bool {
        StatisticsMembership.Selection(dates: dateSelection).includes(train)
    }

    func tapDate(_ date: String, availableDates: Set<String>) {
        var selection = dateSelection
        selection.tap(date, availableDates: availableDates)
        guard selection != dateSelection else { return }
        classification = .date
        selectedJourneyGroupID = nil
        dateSelection = selection
        // The day ticket remains meaningful only for a single-day scope.
        selectedDate = selection.start == selection.end
            ? selection.start ?? Dates.allDates : Dates.allDates
        invalidateScope()
    }

    func clearDates() {
        guard !dateSelection.isEmpty || selectedDate != Dates.allDates else { return }
        dateSelection.clear()
        selectedDate = Dates.allDates
        invalidateScope()
    }

    /// Independent card dates can cross years while preserving their current range.
    func removeYearRestriction() {
        guard selectedYear != nil else { return }
        selectedYear = nil
        invalidateScope()
    }

    func selectYear(_ year: Int?) {
        guard year != selectedYear || !dateSelection.isEmpty || selectedDate != Dates.allDates else { return }
        selectedYear = year
        dateSelection.clear()
        selectedDate = Dates.allDates
        invalidateScope()
    }

    private func invalidateScope() {
        task?.cancel()
        passportTask?.cancel()
        scopeTask?.cancel()
        servedFingerprint = nil
        context = nil
        contextFingerprint = nil
        availableDates = []
        view = nil
        passport = nil
        publishedInputsKey = nil
        progress = Progress(stage: .aggregating)
        state = .loading
    }

    static func year(of train: Train) -> Int? {
        StatisticsMembership.year(of: train)
    }

    func includesYear(_ train: Train) -> Bool {
        StatisticsMembership.Selection(year: selectedYear).includes(train)
    }

    /// The date buckets the loaded rides actually occupy, in date-bar order.
    /// Used to keep a stale scope from surviving a reload.
    private(set) var availableDates: [String] = []

    private var task: Task<Void, Never>?
    private var passportTask: Task<Void, Never>?
    private var scopeTask: Task<Void, Never>?
    private var context: Context?

    deinit {
        MainActor.assumeIsolated {
            task?.cancel()
            passportTask?.cancel()
            scopeTask?.cancel()
        }
    }

    func cancelAll() {
        task?.cancel()
        passportTask?.cancel()
        scopeTask?.cancel()
        task = nil
        passportTask = nil
        scopeTask = nil
        progress = nil
    }

    // Identical inputs may acquire a new caller key while the calculation is running.
    private var latestInputsKey: String?

    private func markPublished(inputsKey: String?) {
        publishedInputsKey = inputsKey
        publishGeneration &+= 1
    }

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
        return passportFailure
    }

    /// The ridden share of a known denominator. `nil` when the network length
    /// was never established, or when this category has no length to share.
    func coverageFraction(ridden: Double, denominator: Double) -> Double? {
        guard coverageDenominatorKnown, denominator.isFinite, denominator > 0,
              ridden.isFinite, ridden >= 0 else { return nil }
        return ridden / denominator
    }

    private static let passportNotComputable =
        "Passport statistics are not computable for these records."

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
    func load(scope: StatisticsScope, trains: [Train], rides: [RiddenRouteStore.DrawnRide]) {
        let members = Set(scope.filter(trains, rides: rides).map(\.id))
        let selected = StatisticsMembership.slice(
            trains: trains, regionCode: nil, rule: Region.scopeRule,
            selection: .init(year: selectedYear, groupID: selectedJourneyGroupID,
                             dates: dateSelection), memberIDs: members).trains
        let ids = Set(selected.map(\.id))
        load(countries: scope.countries, japanLeaves: scope.japanLeavesForIndex,
             trains: selected, rides: rides.filter { ids.contains($0.id) })
    }

    func load(countries: [String], japanLeaves: Set<JapanAreaLeaf>? = nil,
        trains: [Train], rides: [RiddenRouteStore.DrawnRide], inputsKey: String? = nil
    ) {
        latestInputsKey = inputsKey
        let leavesKey = japanLeaves.map { $0.map(\.rawValue).sorted().joined(separator: ",") } ?? "*"
        let fingerprint = Self.fingerprint(
            countries: countries, japanLeavesKey: leavesKey, trains: trains, rides: rides)
        guard fingerprint != servedFingerprint else {
            if case .loaded = state, publishedInputsKey != inputsKey {
                markPublished(inputsKey: inputsKey)
            }
            return
        }
        guard !trains.isEmpty else {
            clearForEmpty(fingerprint: fingerprint, inputsKey: inputsKey)
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
            reloadPassportOnly(
                fingerprint: fingerprint, trains: trains, entries: context.entries,
                inputsKey: inputsKey)
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
                let index = try await Self.readNetwork(countries: countries, japanLeaves: japanLeaves)
                try Task.checkCancellation()
#if DEBUG
                let indexed = ContinuousClock.now
#endif

                self.progress = Progress(stage: .matchingRides, completed: 0, total: total)
                // The entry cache is only valid against the index it was
                // matched on — its edge ids are indices into that index's
                // arrays — so a change of scope starts from nothing.
                // `attribution-policy-v2` is part of that identity: in-place
                // retirement stays in the reference-geometry denominator, and
                // a country-only key would reuse entries matched under the
                // previous attribution. No history or package revision is in
                // scope here, so the key does not carry one.
                let indexKey = countries.joined(separator: ",") + "|" + leavesKey
                    + "|attribution-policy-v2"
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
                let dates = Dates.availableDates(prepared.trains)
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
                // A date or region load that was superseded during `group`
                // can still be the one running here. It must not publish over
                // the fingerprint now being served. Same check as the progress
                // updates and the failure path.
                guard !Task.isCancelled, self.servedFingerprint == fingerprint else { return }

                self.context = context
                self.contextFingerprint = fingerprint
                self.entryCache = prepared.cache
                self.availableDates = dates
                self.view = result
                self.publishCoverage(of: index)
                self.lineTotals = index.lineTotByCat.pairs.map { ($0.key, $0.value) }
                self.lineOperators = Dictionary(
                    index.lineOperator.pairs.map { ($0.key, $0.value) },
                    uniquingKeysWith: { first, _ in first })
                self.passport = grouped
                self.passportFailure = grouped == nil ? Self.passportNotComputable : nil
                self.progress = nil
                self.state = .loaded
                self.markPublished(inputsKey: self.latestInputsKey)
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
                self.passportFailure = nil
                self.clearCoverage()
                self.publishedInputsKey = nil
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
        guard a.countries == b.countries, a.japanLeavesKey == b.japanLeavesKey,
              a.journeys.count == b.journeys.count else { return false }
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
        fingerprint: Fingerprint, trains: [Train], entries: [Statistics.TrainEntry],
        inputsKey: String?
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
            self.passportFailure = grouped == nil ? Self.passportNotComputable : nil
            self.markPublished(inputsKey: self.latestInputsKey)
        }
    }

    /// Publish the absence of statistics without touching ``EdgeIndexCache``.
    ///
    /// Every value from the previous answer is cleared together. In
    /// particular, retaining `context` would let a later date selection
    /// aggregate the deleted journeys again, while retaining `progress` would
    /// leave the empty card claiming that a calculation was still underway.
    private func clearForEmpty(fingerprint: Fingerprint, inputsKey: String?) {
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
        clearCoverage()
        lineTotals = []
        lineOperators = [:]
        passport = nil
        passportFailure = nil
        progress = nil
        availableDates = []
        entryCache = [:]
        entryCacheIndexKey = ""
        state = .loaded
        markPublished(inputsKey: inputsKey)
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
                self.publishGeneration &+= 1
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
                self.passportFailure = nil
                self.clearCoverage()
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
        countries: [String], japanLeaves: Set<JapanAreaLeaf>?
    ) async throws -> Statistics.EdgeIndex {
        let interval = RailSignpost.jobs.begin("stats.readNetwork")
        defer { RailSignpost.jobs.end("stats.readNetwork", interval) }
        let index = try await EdgeIndexCache.shared.scoped(
            countries: countries, japanLeaves: japanLeaves)
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
    /// `collectTrainStatsEntry` is a pure function of the drawn geometry, each
    /// section's two endpoint names, which sections were RIDDEN, the edge
    /// index, and the ride date (`Dates.trainDate` — the day the walk keeps
    /// an edge only when it is in service). So an entry can be reused exactly
    /// when all of those are unchanged, and the digest is those inputs and
    /// nothing else — a key built from fewer would reuse an entry the reader's
    /// edit had invalidated, which is a mileage figure that silently does not
    /// move. The date is an input even when the geometry is identical.
    typealias CachedEntry = MileageMatching.CachedEntry

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
    /// that index's own arrays. The string is the country list joined by
    /// commas, then `|attribution-policy-v2`.
    private var entryCacheIndexKey = ""

    private nonisolated static func matchRides(
        trains: [Train], journeys: [Fingerprint.Journey],
        rides: [RiddenRouteStore.DrawnRide], index: Statistics.EdgeIndex,
        cache: [String: CachedEntry],
        report: @Sendable (Int) -> Void
    ) async throws -> Prepared {
        let interval = RailSignpost.jobs.begin("stats.matchRides")
        defer { RailSignpost.jobs.end("stats.matchRides", interval) }
        guard trains.count == journeys.count else { throw RecordMismatch() }
        for (train, journey) in zip(trains, journeys) {
            guard train.id == journey.id else { throw RecordMismatch() }
        }
        let ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The fingerprint and matcher share date/digest definitions. Map only
        // platform route values here; the use case owns matching, cache reuse,
        // ordered entries and pruning. Coordinate arrays retain their storage.
        let snapshots = try zip(trains, journeys).map { train, journey in
            try Task.checkCancellation()
            // A valid cached entry needs no route payload. Preserve the fast
            // path instead of mapping all segments for already-matched rides.
            let segments: [MileageMatching.Segment]
            if train.requiresRouteConfirmation || cache[train.id]?.digest == journey.entry {
                segments = []
            } else {
                let ride = ridesByID[train.id]
                let uncertified = Set(ride?.physicalGaps.filter { !$0.isBoundary }.map(\.segmentIndex) ?? [])
                segments = ride?.segments.filter { !uncertified.contains($0.segmentIndex) }.map {
                    MileageMatching.Segment(
                        sourceCoordinates: $0.sourceCoordinates, segmentIndex: $0.segmentIndex,
                        from: $0.from, to: $0.to)
                } ?? []
            }
            return MileageMatching.Journey(
                train: train,
                statisticsDate: journey.date,
                entryDigest: journey.entry,
                segments: segments,
                routeConfirmation: train.routeConfirmation,
                fullDistanceKnown: fullDistanceKnown(train: train, ride: ridesByID[train.id]),
                recordedRouteMapping: ridesByID[train.id]?.recordedRouteMapping)
        }
        return try MileageMatching.match(journeys: snapshots, index: index, cache: cache, report: report)
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
    ///     against, ``entryDigest(train:ride:)`` — geometry, endpoints, ridden
    ///     stops, and the ride date `collectTrainStatsEntry` reads — and
    ///     ``passportDigest(train:)``,
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
        let japanLeavesKey: String
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
        countries: [String], japanLeavesKey: String,
        trains: [Train], rides: [RiddenRouteStore.DrawnRide]
    ) -> Fingerprint {
        let interval = RailSignpost.jobs.begin("stats.fingerprint")
        defer { RailSignpost.jobs.end("stats.fingerprint", interval) }
        let ridesByID = Dictionary(rides.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Fingerprint(
            countries: countries,
            japanLeavesKey: japanLeavesKey,
            journeys: trains.map { train in
                Fingerprint.Journey(
                    id: train.id,
                    trainType: train.trainType,
                    // Explicit normalized bucket, not the raw `date` field.
                    // `trainDate` reads that field, then the eight digits
                    // spelled in the id, then `undated`. It does not read stops.
                    date: Dates.trainDate(train),
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

    /// Everything ``Statistics/collectTrainStatsEntry(features:index:rideDate:)`` reads
    /// about one journey, as one number.
    ///
    /// The geometry arrives already digested — `DrawnRide.geometryDigest`
    /// covers the section count, each section's index and each section's
    /// canonical WGS84 coordinates — so this adds what that digest does not
    /// cover and that the entry does read: each section's `from`/`to`, which
    /// decide whether a section is attributed at all, the stop fields
    /// `isRideSegment` consults, and the ride date (`Dates.trainDate`). A
    /// date change with identical geometry must miss the cached entry.
    ///
    /// A journey with no drawn route is distinguished from one whose route
    /// arrived: both produce an empty feature list today, but the second will
    /// stop doing so the moment it solves, and a digest that could not tell
    /// them apart would keep serving the empty answer.
    /// Missing unridden sections do not make the selected ridden total unknown.
    /// A disconnected boundary matters when both adjacent sections were ridden.
    private nonisolated static func fullDistanceKnown(
        train: Train, ride: RiddenRouteStore.DrawnRide?
    ) -> Bool {
        let stops = train.stops
        let hasRiddenSection = (0..<max(0, stops.count - 1)).contains {
            Statistics.isRideSegment(stops, segmentIndex: $0)
        }
        guard let ride else { return !hasRiddenSection }
        func isRidden(_ sectionIndex: Int) -> Bool {
            guard let stopInterval = ride.stopInterval(forSectionIndex: sectionIndex) else { return false }
            return Statistics.isRideSegment(stops, segmentIndex: stopInterval)
        }
        for gap in ride.physicalGaps {
            if isRidden(gap.segmentIndex),
               !gap.isBoundary || isRidden(gap.segmentIndex - 1) {
                return false
            }
        }
        if case .partial(_, _, let gaps) = ride.route {
            if gaps.contains(where: {
                isRidden($0.segmentIndex) && (!$0.isBoundary || isRidden($0.segmentIndex - 1))
            }) { return false }
        }
        if case .unavailable = ride.route { return !hasRiddenSection }
        if case .historyDatabaseInvalid = ride.route { return !hasRiddenSection }
        return true
    }

    private nonisolated static func entryDigest(
        train: Train, ride: RiddenRouteStore.DrawnRide?
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(train.requiresRouteConfirmation)
        hasher.combine(fullDistanceKnown(train: train, ride: ride))
        if let ride, !train.requiresRouteConfirmation {
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
        // The walk keeps an edge only when it is in service on this date.
        hasher.combine(Dates.trainDate(train))
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
            // The bucket `Dates.trainDate` already stored on the fingerprint.
            // Reading `Train.date` here would skip id inference and invalid
            // dates, and would not be the day the mileage walk used.
            trainDate: { Dates.trainDate($0) },
            dateLabel: { $0 })
    }

    /// The passport's per-journey grouping, off the main actor.
    ///
    /// `async` for that reason alone — nothing in it awaits. A `nonisolated`
    /// async function runs on the generic executor, which is what keeps a pass
    /// over every stop of every journey out of the frame the panel is drawing.
    private nonisolated static func group(
        trains: [Train], entries: [Statistics.TrainEntry]
    ) async -> PassportStatistics? {
        let interval = RailSignpost.jobs.begin("stats.group")
        defer { RailSignpost.jobs.end("stats.group", interval) }
        return PassportStatistics.build(trains: trains, entries: entries)
    }

    private struct RecordMismatch: LocalizedError {
        var errorDescription: String? {
            "Mileage records are not computable because the journeys and their fingerprints do not match."
        }
    }

    private func publishCoverage(of index: Statistics.EdgeIndex) {
        let known = !index.km.isEmpty && index.totalKm.isFinite && index.totalKm > 0
        coverageDenominatorKnown = known
        totalKm = known ? index.totalKm : 0
        totalsByMask = known ? index.totalsByMask : [:]
    }

    private func clearCoverage() {
        coverageDenominatorKnown = false
        totalKm = 0
        totalsByMask = [:]
    }

    private struct Context: Sendable {
        let country: String
        let index: Statistics.EdgeIndex
        let trains: [Train]
        let entries: [Statistics.TrainEntry]
    }

    private typealias Prepared = MileageMatching.Result

}

extension MileageStatisticsStore {
    /// The same measured values feed the dashboard and every share-card shape.
    func widgetData(
        _ kind: StatisticsCardKind, trains: [Train], scopeName: String,
        region: Region? = nil, localization: AppLocalization
    ) -> StatsWidgetData? {
        let passport = self.passport.flatMap { $0.isEmpty ? nil : $0 }
        let widgetDateScope: String? = {
            let dates = dateSelection
            if let start = dates.start {
                let end = dates.end ?? start
                let range = start == end ? StatisticsFormat.dayLabel(start, localization: localization) : "\(StatisticsFormat.dayLabel(start, localization: localization)) – \(StatisticsFormat.dayLabel(end, localization: localization))"
                let excluded = dates.excludedDates.sorted().map { "− \(StatisticsFormat.dayLabel($0, localization: localization))" }
                return ([range] + excluded).joined(separator: " · ")
            }
            return selectedYear.map { String($0) }
        }()

        func serviceWidgetRows(_ groups: Statistics.ServiceGroups) -> [StatsWidgetRow] {
            let values = StatisticsFormat.serviceRows(groups)
            let total = values.reduce(0) { $0 + $1.group.km }
            return values.map { row in
                StatsWidgetRow(
                    id: row.id, label: localization.statsCategoryText(row.key),
                    value: "\(StatisticsFormat.km(row.group.km)) km",
                    fraction: total > 0 ? row.group.km / total : 0)
            }
        }

        func tallyWidgetRows(
            _ tallies: [PassportStatistics.Tally],
            label: (PassportStatistics.Tally) -> String
        ) -> [StatsWidgetRow] {
            let peak = Double(tallies.first?.count ?? 0)
            return tallies.map { tally in
                StatsWidgetRow(
                    id: tally.id, label: label(tally), value: StatisticsFormat.rideCount(tally.count, localization: localization),
                    fraction: peak > 0 ? Double(tally.count) / peak : 0)
            }
        }

        func normalizedRows(
            _ values: [(String, String, String, Double, String?)]
        ) -> [StatsWidgetRow] {
            let peak = values.map { $0.3 }.max() ?? 0
            return values.map { id, label, value, magnitude, emblem in
                StatsWidgetRow(
                    id: id, label: label, value: value,
                    fraction: peak > 0 ? magnitude / peak : 0, emblem: emblem)
            }
        }

        func widgetJourneyDetail(
            _ journey: PassportStatistics.Journey, trains: [Train],
            kind: StatisticsCardKind
        ) -> String {
            var detail: [String] = []
            if !journey.date.isEmpty { detail.append(StatisticsFormat.dayLabel(journey.date, localization: localization)) }
            if let train = trains.first(where: { $0.id == journey.id }) {
                let indexes = Statistics.effectivelyRiddenStopIndexes(train.stops)
                if let first = indexes.first, let last = indexes.last {
                    let start = train.stops[first].departure ?? train.stops[first].arrival
                    let end = train.stops[last].arrival ?? train.stops[last].departure
                    let times = [start, end].compactMap { $0 }.filter { !$0.isEmpty }
                    if !times.isEmpty { detail.append(times.joined(separator: " → ")) }
                }
            }
            if kind == .distance, journey.minutes > 0 {
                detail.append(StatisticsFormat.duration(journey.minutes, localization))
            } else if kind == .time, journey.distanceIsKnown {
                detail.append("\(StatisticsFormat.km(journey.km)) km")
            }
            return detail.filter { !$0.isEmpty }.joined(separator: " · ")
        }

        func journeyEndpoints(_ journey: PassportStatistics.Journey) -> String {
            "\(StatisticsFormat.placeName(journey.from, in: journey.region, region: region, localization: localization)) → \(StatisticsFormat.placeName(journey.to, in: journey.region, region: region, localization: localization))"
        }

        let title = localization.text(kind.localizationKey)
        let empty = localization.text("ios.stats.shareNoData")
        func data(
            hero: String = "", unit: String = "", supporting: String? = nil,
            contextDetail: String? = nil, secondaryValue: String? = nil, secondaryLabel: String? = nil,
            rows: [StatsWidgetRow] = [], alternateRows: [StatsWidgetRow] = [],
            columns: [StatsWidgetColumn] = []
        ) -> StatsWidgetData {
            StatsWidgetData(
                title: title, hero: hero, unit: unit, supporting: supporting,
                scopeLabel: scopeName, contextDetail: contextDetail ?? widgetDateScope,
                secondaryValue: secondaryValue, secondaryLabel: secondaryLabel,
                rows: rows, alternateRows: alternateRows, columns: columns,
                emptyMessage: empty)
        }

        guard let stats = view else {
            guard case .loaded = state, trains.isEmpty else { return nil }
            return data()
        }
        switch kind {
        case .recordTicket:
            return data()
        case .rides:
            return data(hero: (passport?.journeys ?? 0).formatted())
        case .dailyTicket:
            guard let daily = stats.daily else { return data() }
            return data(
                hero: StatisticsFormat.km(daily.stats.services.km), unit: "km",
                supporting: StatisticsFormat.duration(daily.stats.rideMinutes, localization),
                contextDetail: StatisticsFormat.dayLabel(daily.date, localization: localization),
                secondaryValue: daily.trainCount.formatted(),
                secondaryLabel: localization.text("ios.ticket.label.rides"),
                rows: serviceWidgetRows(daily.stats.services))
        case .rhythm:
            guard let passport else { return data() }
            let months = passport.months(in: selectedYear)
            var rhythmContext = [widgetDateScope ?? localization.text("ios.stats.shareAllYears")]
            if passport.undated > 0 {
                rhythmContext.append(localization.text(
                    "ios.stats.shareUndatedExcluded", params: ["n": .number(Double(passport.undated))]))
            }
            guard months.contains(where: { $0.count > 0 }) else {
                return data(contextDetail: rhythmContext.joined(separator: " · "))
            }
            let best = months.filter { $0.count > 0 }.max { $0.count < $1.count }
            let weekdays = passport.weekdays(in: selectedYear)
            return data(
                hero: best.map { StatisticsFormat.monthName($0.id, localization: localization) } ?? "",
                supporting: best.map { StatisticsFormat.journeyCount($0.count, localization: localization) },
                contextDetail: rhythmContext.joined(separator: " · "),
                alternateRows: normalizedRows(weekdays.map {
                    ("weekday-\($0.id)", StatisticsFormat.weekdayLabel($0.id, short: true, localization: localization),
                     StatisticsFormat.journeyCount($0.count, localization: localization), Double($0.count), nil)
                }),
                columns: months.map {
                    StatsWidgetColumn(id: $0.id, label: $0.id.formatted(), value: $0.count)
                })
        case .distance:
            guard let passport, let longest = passport.longestByDistance else { return data() }
            var rows: [StatsWidgetRow] = []
            rows.append(StatsWidgetRow(
                id: "average", label: localization.text("ios.stats.perJourney"),
                value: "\(StatisticsFormat.km(passport.averageKm)) km",
                fraction: longest.km > 0 ? passport.averageKm / longest.km : 0))
            if let shortest = passport.shortestByDistance, shortest.id != longest.id {
                rows.append(StatsWidgetRow(
                    id: "shortest", label: localization.text("ios.stats.shortestByDistance"),
                    value: "\(StatisticsFormat.km(shortest.km)) km",
                    fraction: longest.km > 0 ? shortest.km / longest.km : 0))
            }
            return data(
                hero: StatisticsFormat.km(longest.km), unit: "km",
                supporting: journeyEndpoints(longest),
                contextDetail: widgetJourneyDetail(longest, trains: trains, kind: .distance), rows: rows)
        case .time:
            guard let passport, let longest = passport.longestByTime else { return data() }
            var rows: [StatsWidgetRow] = []
            rows.append(StatsWidgetRow(
                id: "average", label: localization.text("ios.stats.perJourney"),
                value: StatisticsFormat.duration(passport.averageMinutes, localization),
                fraction: longest.minutes > 0 ? passport.averageMinutes / longest.minutes : 0))
            return data(
                hero: StatisticsFormat.duration(longest.minutes, localization),
                supporting: journeyEndpoints(longest),
                contextDetail: widgetJourneyDetail(longest, trains: trains, kind: .time), rows: rows)
        case .coverage:
            let total = totalKm
            let overall = coverageReading(ridden: stats.overall.networkKm, denominator: total, localization: localization)
            var rows = [StatsWidgetRow(
                id: "overall", label: localization.statsCategoryText("stat.all"),
                value: overall.bar, fraction: overall.fraction)]
            rows += stats.categories.map { category in
                let ridden = stats.overall.riddenByMask[category.mask] ?? 0
                let categoryTotal = totalsByMask[category.mask] ?? 0
                let reading = coverageReading(ridden: ridden, denominator: categoryTotal, localization: localization)
                return StatsWidgetRow(
                    id: "category-\(category.mask)",
                    label: localization.statsCategoryText(category.i18n),
                    value: reading.bar, fraction: reading.fraction)
            }
            return data(hero: overall.bar, rows: rows)
        case .service:
            let rows = serviceWidgetRows(stats.overall.services)
            let best = rows.max { $0.fraction < $1.fraction }
            return data(
                hero: best.map { "\(StatisticsFormat.percent($0.fraction * 100))%" } ?? "",
                supporting: best?.label,
                contextDetail: [widgetDateScope, localization.text("ios.stats.shareDistanceShare")]
                    .compactMap { $0 }.joined(separator: " · "), rows: rows)
        case .stations:
            guard let passport else { return data() }
            return data(
                hero: passport.stations.count.formatted(),
                unit: localization.text("ios.stats.unit.stations"),
                supporting: passport.stations.first.map {
                    "\(localization.text("ios.stats.shareMostVisited")) · \(StatisticsFormat.placeName($0.name, in: $0.region, region: region, localization: localization))"
                },
                rows: tallyWidgetRows(passport.stations) { StatisticsFormat.placeName($0.name, in: $0.region, region: region, localization: localization) })
        case .operators:
            guard let passport else { return data() }
            return data(
                hero: passport.operators.count.formatted(),
                unit: localization.text("ios.stats.unit.operators"),
                supporting: passport.operators.first.map {
                    "\(localization.text("ios.stats.shareMostRidden")) · \(StatisticsFormat.companyLabel($0.name))"
                },
                rows: tallyWidgetRows(passport.operators) { StatisticsFormat.companyLabel($0.name) })
        case .routes:
            guard let passport else { return data() }
            return data(
                hero: passport.routes.count.formatted(),
                unit: localization.text("ios.stats.unit.routes"),
                supporting: passport.routes.first.map {
                    "\(localization.text("ios.stats.shareMostRidden")) · \(StatisticsFormat.routeLabel($0, region: region, localization: localization))"
                },
                rows: tallyWidgetRows(passport.routes, label: { StatisticsFormat.routeLabel($0, region: region, localization: localization) }))
        case .topSegments:
            let segments = stats.overall.topSegments?.all ?? []
            let peak = Double(segments.first?.count ?? 0)
            let rows = segments.map { row in
                StatsWidgetRow(
                    id: "\(row.from)\u{1f}\(row.to)", label: StatisticsFormat.sectionLabel(row, region: region, localization: localization),
                    value: StatisticsFormat.rideCount(row.count, localization: localization),
                    fraction: peak > 0 ? Double(row.count) / peak : 0)
            }
            return data(
                hero: segments.first.map { $0.count.formatted() } ?? "",
                unit: localization.text("ios.stats.card.rides"),
                supporting: segments.first.map { StatisticsFormat.sectionLabel($0, region: region, localization: localization) }, rows: rows)
        case .regions:
            guard let passport, !passport.regions.isEmpty else { return data() }
            let peak = passport.regions.map(\.km).max() ?? 0
            let rows = passport.regions.map { tally in
                StatsWidgetRow(
                    id: tally.id, label: StatisticsFormat.regionName(tally.region, localization: localization),
                    value: "\(StatisticsFormat.km(tally.km)) km",
                    fraction: peak > 0 ? tally.km / peak : 0, emblem: StatisticsFormat.flag(tally.region))
            }
            return data(
                hero: passport.regions.count.formatted(),
                unit: localization.text("ios.stats.unit.regions"),
                supporting: passport.regions.map { StatisticsFormat.flag($0.region) }.joined(separator: " "),
                rows: rows)
        case .lineDetail:
            let lines = StatisticsLineCoverage.widgetRows(
                masks: stats.categories.map(\.mask), totals: lineTotals,
                operators: lineOperators, ridden: stats.overall.lineRidByCat)
            let rows = lines.sorted { $0.percent > $1.percent }.map { line in
                StatsWidgetRow(
                    id: line.id, label: line.name,
                    value: "\(StatisticsFormat.percent(line.percent))%",
                    fraction: line.percent / 100)
            }
            return data(hero: lines.count.formatted(),
                        unit: localization.text("ios.stats.unit.lines"),
                        supporting: rows.first?.label, rows: rows)
        }
    }

    func recordTicketContent(
        trains: [Train], localization: AppLocalization
    ) -> (displays: [TicketDisplay], fields: [TicketField], span: String?)? {
        guard let stats = view?.overall else { return nil }
        let total = totalKm
        // The headline distance and the coverage fraction are two different
        // numbers and always were — see ``Statistics/MileageStats/networkKm``.
        // 総乗車距離 is every kilometre the reader rode; the percentage below
        // it is a fraction of the classified network, and the distance that
        // reached none of it cannot raise the share of it said to be covered.
        let coverageReading = coverageReading(ridden: stats.networkKm, denominator: total, localization: localization)
        let pending = trains.contains(where: \.requiresRouteConfirmation)
        let allPending = !trains.isEmpty && trains.allSatisfy(\.requiresRouteConfirmation)
        let distance = allPending ? localization.text("ios.routeGuide.unknownDistance")
            : StatisticsFormat.km(stats.riddenAll)
        let rides = trains.count.formatted()
        let stops = trains.reduce(0) { $0 + $1.stops.count }.formatted()
        let coverage = coverageReading.text
        let operators = riddenOperatorCount(stats).formatted()
        let ridesUnit = localization.text("ios.ticket.unit.rides")
        let stopsUnit = localization.text("ios.ticket.unit.stops")
        let operatorsUnit = localization.text("ios.ticket.unit.operators")
        let displays: [TicketDisplay] = [
            .figure(
                label: pending ? localization.text("ios.routeGuide.confirmedDistance")
                    : localization.text("ios.ticket.label.distance"),
                value: distance,
                unit: allPending ? "" : "KM",
                spoken: allPending ? distance : "\(distance) km"),
            StatisticsFormat.ticketRideTime(stats.rideMinutes, localization: localization),
        ]
        let fields: [TicketField] = [
            TicketField(
                label: localization.text("ios.ticket.label.rides"),
                value: rides,
                unit: ridesUnit,
                spoken: StatisticsFormat.ticketSpoken(rides, ridesUnit)),
            TicketField(
                label: localization.text("ios.stops", fallback: "Stops"),
                value: stops,
                unit: stopsUnit,
                spoken: StatisticsFormat.ticketSpoken(stops, stopsUnit)),
            TicketField(
                label: localization.text("ios.ticket.label.coverage"),
                value: allPending ? distance : coverage,
                unit: allPending || !coverageReading.known
                    ? "" : localization.text("ios.ticket.unit.percent"),
                spoken: allPending ? distance : coverageReading.spoken),
            TicketField(
                label: localization.text("ios.stats.operatorsLabel"),
                value: operators,
                unit: operatorsUnit,
                spoken: StatisticsFormat.ticketSpoken(operators, operatorsUnit)),
        ]
        return (displays, fields, StatisticsFormat.issuedSpan(trains: trains, localization: localization))
    }

    private func riddenOperatorCount(_ stats: Statistics.MileageStats) -> Int {
        var operators: Set<String> = []
        for (name, byMask) in stats.lineRidByCat.pairs {
            guard byMask.values.contains(where: { $0 > 0 }) else { continue }
            let operatorName = lineOperators[name] ?? ""
            if !operatorName.isEmpty { operators.insert(operatorName) }
        }
        return operators.count
    }


    func coverageReading(ridden: Double, denominator: Double,
                         localization: AppLocalization) -> StatisticsFormat.CoverageReading {
        StatisticsFormat.coverageReading(
            ridden: ridden, denominator: denominator,
            fraction: coverageFraction(ridden: ridden, denominator: denominator), localization: localization)
    }
}
