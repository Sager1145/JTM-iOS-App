import RailApplication
import Foundation
import Observation
import RailCore
import RailPresentation

/// Set only while `runImport` is delivering a progress callback on this task.
/// A nested product import may publish a newer baseline; every other task
/// still sees the busy flag and is refused.
private enum ItineraryImportReentry {
    @TaskLocal static var isProgressCallback = false
}

/// The rides — what this app is actually for.
///
/// The web app is *N02 特急列車管理*: a tool for recording which trains you have
/// ridden. The network drawn underneath is context; the itineraries are the
/// subject. This loads them from the same committed stores the web app reads.
///
/// Decoding and grouping both come from `RailCore` — `Train` and `Dates` are
/// ported and checked against the JavaScript by fixtures — so this type holds
/// no rules of its own. That is deliberate: a date grouped differently here
/// than in the web app would be a silent divergence no fixture could catch,
/// because it would live outside the tier the fixtures cover.
@MainActor
@Observable
final class ItineraryStore {

    enum LoadState {
        case idle
        case loading
        case loaded(Loaded)
        case failed(String)
    }

    struct Loaded {
        /// Which regions these rides touch, in the interface's order. The map
        /// draws all five networks whatever this says; it is here because the
        /// screens that summarise the rides — statistics, the data screen —
        /// have to say which regions they are summarising.
        var regions: [Region]
        var trains: [Train]
        /// Dates in the order the web app's date bar shows them, each with the
        /// trains whose own bucket is that date.
        ///
        /// Deliberately *not* "the trains that run on this date": an overnight
        /// train belongs to one bucket while spanning two days on the map. The
        /// distinction is `Dates`', and it is documented there — conflating
        /// the two would list the Sunrise twice.
        var days: [Day]
        var elapsed: Duration

        typealias Day = JourneyDay
    }

    private(set) var state: LoadState = .idle

    /// Every id in the working set. An id edit must not silently overwrite
    /// another record, and the editor can only warn about a collision it can see.
    private(set) var trainIDs: Set<String> = []
    /// Journeys whose route the reader has not confirmed.
    private(set) var pendingConfirmationIDs: Set<String> = []

    /// The train the reader is looking at. Selection lives here rather than in
    /// a view because the map and the list both need it, and they are in
    /// different halves of the layout.
    var selectedTrainID: String? {
        didSet {
            if oldValue != selectedTrainID { selectionRevision &+= 1 }
            // `nil` means "back to the list", not "forget what was last on
            // the map". Keeping the last non-nil value lets the route store
            // warm exactly one cache entry on the next launch without forcing
            // the detail card back open.
            guard let selectedTrainID, selectedTrainID != lastViewedTrainID else { return }
            lastViewedTrainID = selectedTrainID
            preferences.set(selectedTrainID, forKey: Self.lastViewedTrainKey)
        }
    }

    /// The route to publish first on the next launch.
    ///
    /// This is deliberately separate from ``selectedTrainID``: restoring the
    /// selection would change navigation state, while restoring its cached
    /// geometry only changes how soon the map becomes useful.
    private(set) var lastViewedTrainID: String?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var settleRegistration: BundledRegistry.SettledRegistration?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        lastViewedTrainID = preferences.string(forKey: Self.lastViewedTrainKey)
        settleRegistration = BundledRegistry.SettledRegistration { [weak self] region in
            Task { @MainActor in
                self?.applySettledIdentity(region: region)
            }
        }
    }

    /// Fills registry ids on in-memory rides of one settled region and saves
    /// through the normal commit, so the UI and the file both see them.
    func applySettledIdentity(region: String) {
        guard var current = store else { return }
        let cc = region.lowercased()
        var changed = false
        for index in current.trains.indices {
            guard current.trains[index].region?.lowercased() == cc else { continue }
            let upgraded = BundledRegistry.upgradeIfReady(current.trains[index])
            if upgraded != current.trains[index] {
                current.trains[index] = upgraded
                changed = true
            }
        }
        guard changed else { return }
        _ = commitWorkingSet(current)
        publishRecordIndex()
        regroup(self.store ?? current)
    }

    private(set) var selectionRevision = 0

    /// A temporary menu may return the selection only if no later navigation claimed it.
    @discardableResult
    func restoreSelection(_ previous: String?, ifUnchangedSince revision: Int) -> Bool {
        guard selectionRevision == revision else { return false }
        selectedTrainID = previous.flatMap { id in trainIDs.contains(id) ? id : nil }
        return true
    }

    private static let lastViewedTrainKey = "last-viewed-train-id"
    /// No persistence library is attached, so a published working set cannot be written.
    private static let unavailableSave = "The current journeys are unavailable to save."

    /// The library that receives the one save queued for each commit.
    @ObservationIgnored private var persistenceLibrary: RideLibrary?
    /// Nested `runImport` calls (a progress callback applying a newer import)
    /// share one busy flag. Only the outermost call clears it.
    private var importDepth = 0

    /// Loads whatever the library says is current — a bundled sample, or the
    /// reader's own saved store.
    ///
    /// The store is held here as well as decoded, because saving needs the
    /// whole `TrainStore` (schema version included) and not just the trains.
    private(set) var store: TrainStore?

    /// Groups retain the first authored record for each ID, in display order.
    var orderedJourneyGroups: [JourneyGroup] {
        var seen = Set<String>()
        return (store?.trains ?? loaded?.trains ?? [])
            .compactMap(\.journeyGroup).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What a save actually did (§8.3).
    ///
    /// `replace` used to return nothing, which meant the two ways it can
    /// decline — an import owns the store, or the new id belongs to another
    /// journey — were indistinguishable from success at every call site. The
    /// id collision in particular was resolved *silently*: the record was
    /// written back under its old id and nobody was told. §8.3 forbids the
    /// louder version of that ("ID 冲突不能静默覆盖另一条记录"), and this is
    /// what lets a surface say which of the two happened.
    ///
    /// Adding a return value keeps every existing `itineraries.replace(...)`
    /// call compiling untouched.
    enum SaveOutcome: Equatable {
        case saved
        /// Written, but under `keptID`: `requestedID` is another journey's.
        case savedKeepingID(keptID: String, requestedID: String)
        /// Nothing was written — an import owns the store right now.
        case refusedImportRunning
        /// Nothing was written — no journey with that id is in the store.
        case notFound
        /// Nothing was written — the draft names a region the app does not support.
        case unsupportedRegion(String)
    }

    /// What `mutate` and `replaceAll` did, in the two parts a caller cannot
    /// tell apart from the mutated value alone: whether it landed, and — if
    /// it did — what to select next.
    ///
    /// Before this, a refusal (an import owns the store, or the working set
    /// is not there yet) returned the SAME value success with "nothing
    /// changed" would: `mutate` handed back the existing `selectedTrainID`
    /// either way, and a caller like `JourneyEditing` persisted and selected
    /// on the strength of that value without any way to see the refusal.
    enum MutationOutcome: Equatable {
        case committed(selectedID: String?)
        case refused

        var isCommitted: Bool {
            if case .committed = self { return true }
            return false
        }

        var committedSelectedID: String? {
            if case .committed(let id) = self { return id }
            return nil
        }
    }

    /// One publication of the working set and the single save queued for it.
    ///
    /// The working set and the file are not one transaction. `save == nil`
    /// means nothing was published. A finished save with `saved == false`
    /// means the change is already in memory and the disk write failed.
    struct Commit<Outcome> {
        var outcome: Outcome
        var save: Task<RideLibrary.SaveResult, Never>?

        static func refused(_ outcome: Outcome) -> Commit {
            Commit(outcome: outcome, save: nil)
        }
    }

    /// Remembers which library later commits write to. `load(from:)` does this.
    func attach(_ library: RideLibrary) {
        persistenceLibrary = library
    }

    /// `merge`'s own outcome: the ids folded in on success, distinct from a
    /// refusal — which otherwise reads exactly like "merged 0 ids" (§8.7).
    enum MergeOutcome: Equatable {
        case committed(ids: [String])
        case refused
    }

    /// Replace one edited train and rebuild the date buckets from the same
    /// ported rules used on load. The editor commits a complete draft once,
    /// so views never observe a half-edited canonical record.
    ///
    /// Validates the candidate, checks the import baseline, publishes the
    /// working set, and queues one save. A disk failure leaves the replacement
    /// in memory; `save` reports it.
    @discardableResult
    func replace(_ train: Train, replacing originalID: String) -> Commit<SaveOutcome> {
        // A running import owns the store (§8.7): an edit committed against
        // the pre-import trains would be overwritten seconds later without a
        // trace of what happened to it.
        guard !isImporting else { return .refused(.refusedImportRunning) }
        do { try TrainValidation.validateSupportedRegions(train) }
        catch { return .refused(.unsupportedRegion(error.localizedDescription)) }
        guard var next = store,
            let index = next.trains.firstIndex(where: { $0.id == originalID })
        else { return .refused(.notFound) }

        // An id edit cannot silently collide with another record. Leave the
        // original id in place; the validation surface can explain the
        // collision without destroying either journey.
        var candidate = train
        var outcome = SaveOutcome.saved
        if candidate.id != originalID,
            next.trains.contains(where: { $0.id == candidate.id })
        {
            outcome = .savedKeepingID(keptID: originalID, requestedID: candidate.id)
            candidate.id = originalID
        }
        next.trains[index] = candidate.taggingRegion()
        let save = commitWorkingSet(next)
        // Editing a different row is not a navigation command. Follow an ID
        // rename only when the edited journey was already selected.
        if selectedTrainID == originalID { selectedTrainID = candidate.id }
        publishRecordIndex()

        regroup(self.store ?? next)
        return Commit(outcome: outcome, save: save)
    }

    /// Inserts a completed editor draft atomically: cancelling the sheet
    /// never leaves a blank journey in the store.
    @discardableResult
    func add(_ train: Train) -> Commit<String?> {
        guard (try? TrainValidation.validateSupportedRegions(train)) != nil else { return .refused(nil) }
        let commit = mutate(region: Region.resolved(train)) { workspace in
            StoreOperations.addTrain(train.taggingRegion(), in: &workspace)
        }
        return Commit(outcome: commit.outcome.committedSelectedID, save: commit.save)
    }

    /// Inserts every accepted draft in one publication and queues one save.
    /// A train whose region is not supported is skipped. An empty result
    /// publishes nothing and does not write.
    @discardableResult
    func add(_ trains: [Train]) -> Commit<[String]> {
        guard !isImporting, let store, let first = trains.first else { return .refused([]) }
        var workspace = StoreOperations.Workspace(
            store: store,
            selectedTrainID: selectedTrainID,
            focusedTrainID: nil,
            country: Region.resolved(first).code
        )
        var ids: [String] = []
        for train in trains {
            guard (try? TrainValidation.validateSupportedRegions(train)) != nil else { continue }
            guard StoreOperations.addTrain(train.taggingRegion(), in: &workspace) != nil,
                let id = workspace.selectedTrainID
            else { continue }
            ids.append(id)
        }
        guard !ids.isEmpty else { return .refused([]) }
        guard workspace.store.trains.allSatisfy({
            (try? TrainValidation.validateSupportedRegions($0)) != nil
        }) else { return .refused([]) }
        let next = MergedStore.tagged(workspace.store)
        let save = commitWorkingSet(next)
        selectedTrainID = workspace.selectedTrainID
        publishRecordIndex()
        regroup(self.store ?? next, reassertingSelection: true)
        return Commit(outcome: ids, save: save)
    }

    @discardableResult
    func duplicate(_ id: String) -> Commit<String?> {
        let commit = mutate(region: region(of: id)) { workspace in
            StoreOperations.duplicateTrain(id, in: &workspace)
        }
        return Commit(outcome: commit.outcome.committedSelectedID, save: commit.save)
    }

    @discardableResult
    func delete(_ id: String) -> Commit<Bool> {
        let commit = mutate(region: region(of: id)) { workspace in
            StoreOperations.deleteTrain(id, in: &workspace)
        }
        return Commit(outcome: commit.outcome.isCommitted, save: commit.save)
    }

    @discardableResult
    func toggleVisibility(_ id: String) -> Commit<Bool> {
        let commit = mutate(region: region(of: id)) { workspace in
            StoreOperations.toggleTrainVisibility(id, in: &workspace)
        }
        return Commit(outcome: commit.outcome.isCommitted, save: commit.save)
    }

    /// The region of the ride an operation acts on.
    ///
    /// Most `StoreOperations` transitions do not read the workspace's country
    /// at all — only `addTrain` does, for its blank scaffold — but handing one
    /// the wrong region would be a fact stated wrongly, and a later transition
    /// that starts reading it would inherit the mistake silently.
    private func region(of id: String) -> Region {
        store?.trains.first { $0.id == id }.map(Region.resolved) ?? .jp
    }

    /// What a rebuild did, in the two parts §8.4 asks the interface to keep
    /// apart: the sections were recomputed from the stops, and *then* the
    /// geometry is solved for them.
    struct RebuildOutcome {
        /// Route sections written back to the record.
        var sections: Int
        /// Whether a geometry solve actually started. False when the app is
        /// running without a route store beneath it, and the surface then says
        /// "sections rebuilt" instead of claiming a solve nobody is running.
        var solving: Bool
        /// The one save queued for the rebuilt record. Nil when the replacement
        /// was refused. A finished failure means the sections are in memory.
        var save: Task<RideLibrary.SaveResult, Never>?
    }

    /// Recompute the recorded sections and request their geometry from the caller's route store.
    ///
    /// Recomputing `route_sections` changes the record, and until now that was
    /// the whole operation. The shell's route key covers the whole record now
    /// (see `AppShell.routeLoadKey`), so the reload is no longer in doubt —
    /// but it reloads the *set*, and this journey is the one the reader is
    /// waiting on. Solving it directly is what puts its own geometry back
    /// under its own section list immediately, and what lets §8.4's surface
    /// say whether a solve started rather than only that sections were
    /// rewritten. The route store is the caller's; this type does not keep one.
    @discardableResult
    func rebuildRoute(_ id: String, routes: RiddenRouteStore? = nil) -> RebuildOutcome? {
        guard let train = store?.trains.first(where: { $0.id == id }) else { return nil }
        var rebuilt = train
        rebuilt.routeSections = TrainValidation.normalizeExportTrain(
            train, country: Region.resolved(train).code, stations: .empty).routeSections
        let commit = replace(rebuilt, replacing: id)
        guard case .saved = commit.outcome else { return nil }
        let solving = routes?.resolveAgain(rebuilt) ?? false
        return RebuildOutcome(
            sections: rebuilt.routeSections?.count ?? 0, solving: solving, save: commit.save)
    }

    /// Record the ids the store holds, so the editor can see an id collision
    /// before the save is refused rather than after (§8.3).
    private func publishRecordIndex() {
        let trains = store?.trains ?? []
        trainIDs = Set(trains.map(\.id))
        pendingConfirmationIDs = Set(trains.filter(\.requiresRouteConfirmation).map(\.id))
    }

    @discardableResult
    func move(_ id: String, by offset: Int) -> Commit<Bool> {
        let commit = mutate(region: region(of: id)) { workspace in
            StoreOperations.moveTrain(id, by: offset, in: &workspace)
        }
        return Commit(outcome: commit.outcome.isCommitted, save: commit.save)
    }

    /// One import's per-journey position, as the engine reports it.
    struct ImportProgress: Sendable {
        var completed: Int
        var total: Int
        /// The id the engine has just appended. The JSON-text door reports a
        /// count without one — its event carries a message KEY, not an id —
        /// so this is nil in replace mode rather than filled with a guess.
        var trainID: String?
    }

    struct ImportSummary: Sendable {
        var mode: ImportPreflight.Mode
        var imported: Int
        var ids: [String]
        /// Journeys in the store once the commit landed.
        var storeCount: Int
        /// Disk result of the one save queued after publication.
        /// `saved == false` means the imported working set is in memory and the write failed.
        var save: RideLibrary.SaveResult
    }

    /// A progressive load owns the store while it streams journeys in.
    ///
    /// `ImportEngine.Session` has this flag too, but it lives on a scratch
    /// copy that the shell throws away; this is the shell's own, and it is
    /// what keeps an edit made while a large import runs from being silently
    /// overwritten by the commit (§8.7 — "防止并发修改造成不明确结果").
    private(set) var isImporting = false

    /// Read-only mirror of ``mutate(region:operation:)``'s own refusal
    /// condition — a caller (a screen deciding whether to even ASK for a
    /// backup before a destructive action) needs to know it will be refused
    /// before spending a backup write on an action that was never going to
    /// land, not after.
    var canMutate: Bool { !isImporting && store != nil }

    /// Read-only mirror of ``replaceAll(with:into:)``'s own refusal
    /// condition, checked before the suspension inside it re-checks the
    /// same three facts. See ``canMutate``.
    var canReplace: Bool { !isImporting && store != nil && !loadInFlight }

    /// The staged import: parse and validate off the main actor, report every
    /// journey as it lands, and only then replace the store in one assignment.
    ///
    /// The engine is unchanged and undriven by this method — it runs its own
    /// door end to end. What is new is that the door's per-journey events are
    /// forwarded out instead of being dropped, which is the whole difference
    /// between "importing 47/201" and a spinner.
    ///
    /// Atomicity is structural rather than promised: the door mutates a
    /// scratch `Session` on a detached task, and the three lines that publish
    /// its result run together on the main actor after it has finished. A
    /// throw anywhere before them leaves the store exactly as it was, which is
    /// what lets the error surface say so (§13.3).
    ///
    /// Cancelling does not stop the engine — its loop has no interruption
    /// point, and pretending otherwise would mean re-implementing the loop and
    /// its fixture-pinned ordering. It stops the RESULT from being applied,
    /// so the store is left untouched either way.
    func runImport(
        text: String,
        region: Region,
        mode: ImportPreflight.Mode,
        sourceLabel: String = "JSON",
        library: RideLibrary? = nil,
        onProgress: @MainActor (ImportProgress) async -> Void,
        onCommit: @MainActor () -> Void = {}
    ) async throws -> ImportSummary {
        if let library { attach(library) }
        // A progress callback on this task may apply a newer product import.
        // Every other caller still stops at the busy check.
        let nested = ItineraryImportReentry.isProgressCallback
        if !nested {
            guard !isImporting else { throw ImportBusy() }
        }
        guard let baseline = store, !loadInFlight else { throw ImportNotReady() }
        let generation = storeGeneration
        importDepth += 1
        isImporting = true
        defer {
            importDepth -= 1
            if importDepth == 0 { isImporting = false }
        }

        let current = baseline.trains
        let (stream, continuation) = AsyncStream<ImportProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(1))

        let work = Task.detached(priority: .userInitiated) { () throws -> ImportStaging.Snapshot in
            defer { continuation.finish() }
            return try ImportStaging.stage(
                text: text, currentTrains: current, country: region.code,
                mode: mode, sourceLabel: sourceLabel
            ) { progress in
                continuation.yield(
                    ImportProgress(
                        completed: progress.completed, total: progress.total,
                        trainID: progress.trainID))
            }
        }

        for await progress in stream {
            await ItineraryImportReentry.$isProgressCallback.withValue(true) {
                await onProgress(progress)
            }
        }
        let commit = try await work.value
        // A cancelled import discards a finished result rather than applying
        // half of it: the store is the one thing that must not be left in a
        // state nobody asked for.
        try Task.checkCancellation()
        // The imported journeys were normalised under one region's company
        // rules, so they are tagged with that region here rather than being
        // re-derived from stops that may carry no codes at all.
        let next = TrainStore(
            schemaVersion: TrainValidation.schemaVersion,
            trains: commit.trains.map { train in
                var copy = train
                copy.region = train.region ?? region.code
                return copy
            })
        for train in next.trains { try TrainValidation.validateSupportedRegions(train) }
        // Finish every cancellable phase before publishing. Once this
        // operation commits, it must return its result to the caller's save
        // path even if cancellation arrives immediately after onCommit.
        let grouped = try await Self.group(store: next)
        try Task.checkCancellation()
        guard storeGeneration == generation, !loadInFlight else { throw ImportBaselineChanged() }
        regroupTask?.cancel()
        groupingTicket += 1
        onCommit()
        let saveTask = commitWorkingSet(next)
        selectedTrainID = commit.selectedTrainID
        state = .loaded(grouped)
        publishRecordIndex()
        // Cancellation after onCommit must not skip this write. The task does
        // not throw, so a cancel that arrived in onCommit still reports the
        // disk result of the snapshot that was just published.
        let save = await saveTask.value
        return ImportSummary(
            mode: mode, imported: commit.ids.count, ids: commit.ids,
            storeCount: commit.trains.count, save: save)
    }

    struct ImportNotReady: LocalizedError {
        var errorDescription: String? {
            "Journeys are still loading. Try the import again after loading finishes."
        }
    }

    struct ImportBaselineChanged: LocalizedError {
        var errorDescription: String? {
            "Journeys changed while the import was being prepared. Check the import again."
        }
    }

    struct ImportBusy: LocalizedError {
        var errorDescription: String? {
            "An import is already running; it owns the journeys until it finishes."
        }
    }

    /// Clears the working set without writing it.
    ///
    /// The debug import-reopen launch uses this so a screenshot run does not
    /// replace the saved file. The product delete is ``deleteAll(clearing:)``,
    /// which publishes that same candidate and then queues one save.
    @discardableResult
    func deleteAll() -> Commit<Bool> {
        let commit = mutate(region: .jp, persisting: false) { workspace in
            StoreOperations.deleteAllTrains(in: &workspace)
        }
        return Commit(outcome: commit.outcome.isCommitted, save: nil)
    }

    /// Same, plus the note about which samples are in the working set — which
    /// is no longer true of an empty one. Only when the delete actually
    /// landed: an import owning the store must not also forget the samples
    /// as though the store had been emptied. The caller takes the backup
    /// before this; this queues the one save of the emptied working set.
    @discardableResult
    func deleteAll(clearing library: RideLibrary) -> Commit<Bool> {
        attach(library)
        let cleared = deleteAll()
        guard cleared.outcome, let snapshot = store else { return cleared }
        library.forgetLoadedSamples()
        return Commit(outcome: true, save: enqueueSave(snapshot))
    }

    /// The canonical JSON for every ride, whatever region each belongs to.
    func exportJSON() async -> String? {
        guard let store else { return nil }
        let worker = Task.detached(priority: .userInitiated) { MergedStore.export(store) }
        return await withTaskCancellationHandler {
            let text = await worker.value
            return Task.isCancelled ? nil : text
        } onCancel: { worker.cancel() }
    }

    /// Run one of RailCore's verified store transitions and rebuild the view
    /// model once. The selected id returned is useful for presenting a newly
    /// added or duplicated journey immediately.
    @discardableResult
    private func mutate(
        region: Region,
        persisting: Bool = true,
        operation: (inout StoreOperations.Workspace) -> StoreOperations.MutationResult?
    ) -> Commit<MutationOutcome> {
        // Refused rather than answered with the existing `selectedTrainID`:
        // that used to be indistinguishable from a mutation that ran and
        // happened to leave the selection unchanged, and a caller acting on
        // it (persisting, selecting) could not tell the two apart.
        guard !isImporting else { return .refused(.refused) }
        guard let store else { return .refused(.refused) }
        var workspace = StoreOperations.Workspace(
            store: store,
            selectedTrainID: selectedTrainID,
            focusedTrainID: nil,
            country: region.code
        )
        guard operation(&workspace) != nil else { return .refused(.refused) }
        // A journey created by one of these transitions — `addTrain`'s blank
        // scaffold, `duplicateTrain`'s copy — arrives without a region, and
        // the scaffold's stops are the only thing that could say. Tagging the
        // whole store settles it once, here, rather than at every reader.
        guard workspace.store.trains.allSatisfy({
            (try? TrainValidation.validateSupportedRegions($0)) != nil
        }) else { return .refused(.refused) }
        let next = MergedStore.tagged(workspace.store)
        // `persisting` is false only for the debug in-memory clear. Every
        // product mutation publishes and queues one save together.
        let save: Task<RideLibrary.SaveResult, Never>?
        if persisting {
            save = commitWorkingSet(next)
        } else {
            publishWorkingSet(next)
            save = nil
        }
        selectedTrainID = workspace.selectedTrainID
        publishRecordIndex()
        regroup(self.store ?? next, reassertingSelection: true)
        return Commit(outcome: .committed(selectedID: workspace.selectedTrainID), save: save)
    }

    /// The reader's own rides, or nothing at all.
    ///
    /// **Nothing at all is the first-launch state, deliberately.** The web app
    /// boots into a sample so that a browser tab arriving from a link has
    /// something on it; this app does not, because a sample loaded without
    /// being asked for is 201 journeys the reader has to delete before their
    /// own store means anything. The samples are on the data screen, one
    /// region at a time, and loading one is an action.
    func load(from library: RideLibrary) {
        attach(library)
        state = .loading
        loadInFlight = true
        // Taken before the first suspension. What this load reads is only
        // publishable while the working set is still the one it started from.
        let generation = storeGeneration

        Task {
            do {
                // All three touch the store file, and a cold one is a megabyte
                // of JSON: read on the main actor, this was the launch the app
                // spent not drawing. They are awaited in this order rather than
                // started together because each one has to see what the one
                // before it left on disk.
                await library.migrateLegacyStores()
                await library.refreshSavedState()
                let loaded: TrainStore
                if library.hasSavedStore {
                    loaded = try await library.savedStore()
                } else {
                    loaded = TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [])
                }
                // A store saved before `number_en` existed carries the Latin
                // name inside the caption. Split once, here; written back
                // below, only if this load is still the one being published.
                // Pending markers remain unchanged: station codes cannot
                // distinguish a user's explicit pending choice from an old
                // inferred marker or establish physical route confirmation.
                var saved = loaded
                let migratedCaptions = ServiceCaption.migrateLegacyCaptions(loaded.trains)
                if let migratedCaptions { saved.trains = migratedCaptions }
                for train in saved.trains { try TrainValidation.validateSupportedRegions(train) }
                let store = try await MergedStore.regionTagged(saved)
                // Somebody published while this was reading the file — a
                // sample folded in, an import committed, a journey edited.
                // Theirs is the newer working set and it has already been
                // saved; this is the file as it was BEFORE that happened, so
                // it is abandoned rather than written over the top. The door
                // that published has already republished `state`.
                guard generation == storeGeneration else {
                    loadInFlight = false
                    return
                }
                publishWorkingSet(store)
                // Write a store migration only after this load has passed
                // the generation guard and published its snapshot.
                if migratedCaptions != nil {
                    _ = enqueueSave(saved)
                }
                publishRecordIndex()
                // Taken, not bumped.
                //
                // This used to be `groupingTicket += 1` after the grouping,
                // meaning "mine is the newest answer". That is false for a
                // rebuild asked for AFTER this grouping started: such a
                // rebuild is strictly newer, and bumping the ticket killed it
                // so that this older grouping could publish in its place. Take
                // a ticket first and check it after, exactly as `regroup`
                // does.
                regroupTask?.cancel()
                groupingTicket += 1
                let ticket = groupingTicket
                let grouped = try await Self.group(store: self.store ?? store)
                guard ticket == groupingTicket else {
                    loadInFlight = false
                    return
                }
                state = .loaded(grouped)
                selectedTrainID = nil
                // Written back, because the point of the pass is that it
                // happens once: a correction that is not saved is a correction
                // that runs again on every launch. Only when it changed
                // something — a store this app wrote is already tagged, and
                // rewriting it on every launch would be a file touched for
                // nothing.
                if store != saved { _ = enqueueSave(self.store ?? store) }
                loadInFlight = false
            } catch {
                // A failure from a load nobody is waiting on any more must not
                // replace a working set that arrived while it was reading.
                loadInFlight = false
                guard generation == storeGeneration else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Fold a store — a bundled sample, or a file the reader opened — into the
    /// working set and save the result.
    ///
    /// Returns the ids that were added or updated, so the caller can say how
    /// many rides arrived rather than how many the file held — or `.refused`,
    /// distinct from ``MergeOutcome/committed(ids:)`` holding an empty list,
    /// so a caller cannot mistake "an import owns the store" for "merged
    /// nothing".
    @discardableResult
    func merge(_ incoming: TrainStore, into library: RideLibrary) async throws -> Commit<MergeOutcome> {
        // Placed BEFORE the fold, not corrected after it. Every bundled sample
        // is a web-app store with no `region` in it, and outside Japan its
        // codes name no region on their face — so a sample folded in untagged
        // is drawn and solved as Japanese, and the Macanese one reported
        // 無法繪製路線 until the app was next launched. See ``RegionCodeIndex``.
        // A running import owns the store, exactly as it does for `replace`
        // and `mutate`. `runImport` reads the trains at entry and writes the
        // result seconds later, so a fold that lands in between is discarded
        // without a trace. Until now the only thing preventing that was a
        // `.disabled` modifier on one screen — a UI accident, not an
        // invariant, and one that says nothing about the sample load already
        // in flight when the import starts.
        guard !isImporting, incoming.trains.allSatisfy({
            (try? TrainValidation.validateSupportedRegions($0)) != nil
        }) else { return .refused(.refused) }
        let tagged = try await MergedStore.regionTagged(incoming)
        // Refused while the working set is still being read from disk, OR
        // while an import has started claiming the store since the guard
        // above ran — `await` is a suspension point, so both facts have to be
        // re-read rather than trusted from before it. Folding into a store
        // that is not there yet would merge into nothing and then SAVE that —
        // which is how loading a sample seconds after launch deletes every
        // ride the reader already had.
        guard !isImporting, let current = store else { return .refused(.refused) }
        attach(library)
        let next = MergedStore.merging(tagged, into: current)
        let save = commitWorkingSet(next)
        publishRecordIndex()
        regroup(self.store ?? next)
        return Commit(outcome: .committed(ids: incoming.trains.map(\.id)), save: save)
    }

    /// Replace the whole working set with one store — the 重置示例 action,
    /// which is the only place the web app's "this sample IS the store"
    /// meaning survives.
    @discardableResult
    func replaceAll(with incoming: TrainStore, into library: RideLibrary) async throws -> Commit<MutationOutcome> {
        // As `merge`: a running import owns the store.
        guard !isImporting, incoming.trains.allSatisfy({
            (try? TrainValidation.validateSupportedRegions($0)) != nil
        }) else { return .refused(.refused) }
        let next = try await MergedStore.regionTagged(incoming)
        // Re-checked after the suspension above: an import may have started claiming the
        // store, or a load may still be reading the file this would otherwise
        // overwrite, since the guard above ran.
        guard !isImporting, store != nil, !loadInFlight else { return .refused(.refused) }
        attach(library)
        let save = commitWorkingSet(next)
        selectedTrainID = nil
        publishRecordIndex()
        regroup(self.store ?? next)
        return Commit(outcome: .committed(selectedID: nil), save: save)
    }

    /// The number of the most recent rebuild that was asked for.
    ///
    /// See ``regroup(_:reassertingSelection:)``.
    private var groupingTicket = 0
    private var regroupTask: Task<Void, Never>?

    /// How many times the working set has been published.
    ///
    /// ``load(from:)`` is the only door that reads the store off disk, and
    /// reading a cold one is five suspension points long. Everything the
    /// reader can do in that window publishes a newer working set — folding in
    /// a sample, committing an import, editing a journey — and `load` then
    /// resumed, overwrote it with the snapshot it had started from, and SAVED
    /// that snapshot on top. The sample the reader had just loaded was gone
    /// from the list, from memory, and from the file, with nothing said.
    ///
    /// This is the hazard two racing regroups have, one tier down, and it
    /// takes the same answer: work that suspended may only publish if nothing
    /// published while it was away. `groupingTicket` guards the grouping;
    /// this guards the store the grouping is derived FROM.
    private(set) var storeGeneration = 0

    /// Whether the initial file read is still in flight. Replacing the
    /// whole store must wait until that read has finished.
    private var loadInFlight = false

    /// The one door onto the working set.
    ///
    /// Every assignment goes through here so that a future one cannot forget
    /// to count itself. A generation that misses a writer is worse than no
    /// generation at all, because `load` would then believe it was safe.
    ///
    private func publishWorkingSet(_ next: TrainStore) {
        store = next
        storeGeneration &+= 1
    }

    /// The one itinerary commit. The caller has already validated the candidate
    /// and checked the baseline. This publishes that working set and queues
    /// exactly one save of it.
    ///
    /// Applying memory and writing the file are not one transaction. The
    /// returned task finishes with `saved == false` when the working set is
    /// already published and the disk write failed. It does not roll the
    /// working set back.
    @discardableResult
    private func commitWorkingSet(_ next: TrainStore) -> Task<RideLibrary.SaveResult, Never> {
        publishWorkingSet(next)
        return enqueueSave(next)
    }

    /// Queues one write of an already published snapshot. Does not add,
    /// replace, or otherwise change the working set. A retry of a failed
    /// screenshot or import save uses this so it cannot insert the records again.
    @discardableResult
    func saveWorkingSet() -> Task<RideLibrary.SaveResult, Never> {
        guard let store else {
            let message = Self.unavailableSave
            return Task { RideLibrary.SaveResult(saved: false, error: message) }
        }
        return enqueueSave(store)
    }

    private func enqueueSave(_ snapshot: TrainStore) -> Task<RideLibrary.SaveResult, Never> {
        guard let persistenceLibrary else {
            let message = Self.unavailableSave
            return Task { RideLibrary.SaveResult(saved: false, error: message) }
        }
        return persistenceLibrary.saveResult(snapshot)
    }

    /// Rebuild the date buckets for `store` and publish them — unless a later
    /// edit has asked for a rebuild of its own since this one started.
    ///
    /// Grouping runs off the main actor, so two edits a moment apart can
    /// finish in either order, and the older one publishing last leaves the
    /// list and the date bar showing the store as it was BEFORE the newer
    /// edit — a wrong answer that stays on screen until something else happens
    /// to rebuild. Same hazard as two saves racing to one file, and the same
    /// answer: only the latest rebuild asked for may speak.
    ///
    /// `reassertingSelection` is for the two callers that add or rename a
    /// journey. Their new record is not in the published grouping until this
    /// rebuild lands, so a surface reading `loaded` can drop a selection it
    /// cannot find in the meantime; those two put it back.
    private func regroup(_ store: TrainStore, reassertingSelection: Bool = false) {
        regroupTask?.cancel()
        groupingTicket += 1
        let ticket = groupingTicket
        let selection = selectedTrainID
        let selectionRevision = self.selectionRevision
        regroupTask = Task {
            do {
                // A burst of additions needs only its final date grouping.
                // Yield before retaining more CPU work for superseded stores.
                await Task.yield()
                try Task.checkCancellation()
                let grouped = try await Self.group(store: store)
                guard ticket == groupingTicket, !Task.isCancelled else { return }
                state = .loaded(grouped)
                if reassertingSelection, selectionRevision == self.selectionRevision {
                    selectedTrainID = selection
                }
            } catch is CancellationError {
                // A newer mutation owns the next publish.
            } catch {
                guard ticket == groupingTicket else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Grouping runs off the main actor and checks cancellation between
    /// phases so superseded large stores stop consuming background work.
    private nonisolated static func group(store: TrainStore) async throws -> Loaded {
        try Task.checkCancellation()
        let interval = RailSignpost.ui.begin("itinerary.group")
        defer { RailSignpost.ui.end("itinerary.group", interval) }
        let started = ContinuousClock.now

        // Both the ordering and the bucketing are the web app's, ported. The
        // date bar's order comes from `availableDates`, which sorts on a
        // purpose-built key rather than on the date string; the membership
        // comes from `trains(_:inBucket:)`. Neither is reinvented here.
        // Sorting the records themselves keeps two journeys that share an id
        // as two journeys: the store allows that, and the import path renames
        // rather than merges.
        let sorted = Dates.sortByDateAndDeparture(store.trains)
        try Task.checkCancellation()

        // One `trainDate` per ride, rather than one per ride per date.
        // `availableDates` names the buckets with the same `trainDate` that
        // `trains(_:inBucket:)` filters on, so collecting the rides under it
        // directly is the answer the two of them gave together.
        var buckets: [String: [Train]] = [:]
        for (index, train) in sorted.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            buckets[Dates.trainDate(train), default: []].append(train)
        }
        let days = Dates.availableDates(sorted).map { date in
            Loaded.Day(date: date, trains: buckets[date] ?? [])
        }
        return Loaded(
            regions: MergedStore.regions(of: sorted),
            trains: sorted,
            days: days,
            elapsed: ContinuousClock.now - started
        )
    }

    var loaded: Loaded? {
        if case .loaded(let value) = state { return value }
        return nil
    }

    var selectedTrain: Train? {
        guard let id = selectedTrainID else { return nil }
        return loaded?.trains.first { $0.id == id }
    }

    enum LoadError: LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                """
                \(name).json is not in the app bundle. Run ios/copy-rail-packages.sh — \
                the itinerary stores are read from app/data rather than committed twice.
                """
            }
        }
    }
}
