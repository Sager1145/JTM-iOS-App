import Foundation
import Observation
import RailCore

/// Where the rides come from, and where the reader's own rides are kept.
///
/// The web app offers two things behind its 載入*示例資料 and 保存為我的資料
/// buttons: a set of sample itineraries to look at, and one store of your own
/// that survives a reload. This is both, and it draws the same distinction —
/// a sample is read-only reference material, your own store is the thing you
/// are building.
///
/// Persistence is a JSON file in Application Support, written in the canonical
/// spelling the web app's export produces. That is not laziness about
/// databases: it means the file you save here is the file the web app imports,
/// and vice versa. A SQLite schema of our own would be faster to query and
/// would immediately be a second format nobody else can read.
///
/// The files themselves are touched by ``RideStorage``, which is not the main
/// actor. What is left here is the state the screens read — whether there is a
/// saved store, when it was written, what went wrong — and the order the file
/// operations are asked for in.
@MainActor
@Observable
final class RideLibrary {

    /// A source the reader can load. The seven samples mirror index.html's
    /// buttons exactly, including which region each belongs to — which now
    /// says where a sample's rides will appear on a map that draws every
    /// region at once, rather than which region has to be switched on first.
    struct Sample: Identifiable, Hashable {
        var id: String { resource }
        var resource: String
        var title: String
        var region: Region

        static let all: [Sample] = [
            .init(resource: "train-store", title: "日本 全部示例資料", region: .jp),
            .init(resource: "new-year-grand-loop", title: "跨年大回行程", region: .jp),
            .init(resource: "tokyo-limited-express-loop", title: "東京特急大回行程", region: .jp),
            .init(resource: "train-store-tw", title: "台灣示例資料", region: .tw),
            .init(resource: "train-store-hk", title: "香港示例資料", region: .hk),
            .init(resource: "train-store-mo", title: "澳門示例資料", region: .mo),
            .init(resource: "train-store-kr", title: "韓國示例資料", region: .kr),
        ]

        static func forRegion(_ region: Region) -> [Sample] {
            all.filter { $0.region == region }
        }

        /// The catalog key index.html gives this sample's own button, so the
        /// list reads in the interface language instead of in Chinese for
        /// everybody. ``title`` stays as the untranslated fallback: it is read
        /// by another port's file, and a name is a poor thing to change under
        /// a caller who did not ask.
        var titleKey: String {
            switch resource {
            case "train-store": "btn.loadSampleAll"
            case "train-store-tw": "btn.loadSampleAllTw"
            case "train-store-hk": "btn.loadSampleAllHk"
            case "train-store-mo": "btn.loadSampleAllMo"
            case "train-store-kr": "btn.loadSampleAllKr"
            case "new-year-grand-loop": "btn.loadNewYearGrandLoop"
            case "tokyo-limited-express-loop": "btn.loadTokyoLimitedExpressLoop"
            default: ""
            }
        }
    }

    /// Which samples have been loaded into the working set, so the data
    /// screen can say "loaded" beside one instead of offering seven buttons
    /// that all look untouched.
    ///
    /// A note about the reader's own store, not a claim about its contents:
    /// rides loaded from a sample can be edited and deleted like any other,
    /// and this is cleared when everything is.
    private(set) var loadedSamples: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: RideLibrary.loadedSamplesKey) ?? [])

    private static let loadedSamplesKey = "loaded-samples"

    /// Whether a saved store exists on disk, so the interface can offer
    /// "restore" only when there is something to restore.
    private(set) var hasSavedStore = false

    private(set) var lastSaveError: String?

    /// Reports a failure through the same surface a failed save uses, for a
    /// caller that runs off this actor's own write queue — `ItineraryStore`'s
    /// North America toggle reads `northAmericaStore()` directly rather than
    /// through `enqueue`'s own error handling, so it needs a door of its own
    /// to say what went wrong.
    func reportError(_ description: String) {
        lastSaveError = description
    }

    /// Whether the working set `ItineraryStore` is showing right now actually
    /// contains the North America rides — set by `ItineraryStore`, never
    /// derived from the switch.
    ///
    /// This is the fix for a data-loss path the switch alone cannot answer:
    /// `Region.northAmericaEnabled` says what the reader WANTS, but a save
    /// mid-load, mid-toggle, or before the first load has finished can be
    /// asked to write a working set that does not yet reflect that want. A
    /// full replace of `train-store-na.json` keyed on the switch would then
    /// wipe the file out from under rides it never actually held in memory.
    /// Keyed on this instead, a full replace only happens when the working
    /// set is known, at the moment of the write, to hold them.
    var northAmericaInWorkingSet = false

    /// When the saved store was last written, so the data screen can say more
    /// than "saved" — a date is what tells a reader whether the copy on this
    /// device is the one they think it is.
    private(set) var savedStoreDate: Date?

    /// The one-deep undo behind every destructive data action.
    ///
    /// §5.8 asks that deleting everything explain what can be recovered, and
    /// §8.6 that a recovery path be offered in preference to a confirmation
    /// wall. Neither is possible without something to recover FROM, so the
    /// destructive actions write one of these first. It is deliberately one
    /// deep and deliberately not a version history: a second backup would
    /// raise the question of which one a reader is restoring, and the answer
    /// would have to be a list of dates nobody keeps track of.
    struct Backup: Equatable, Sendable, Codable {
        enum Reason: String, Codable, Sendable {
            case beforeImport
            case beforeDeleteAll
            case beforeReplace

            var localizationKey: String {
                switch self {
                case .beforeImport: "data.backupReasonImport"
                case .beforeDeleteAll: "data.backupReasonDeleteAll"
                case .beforeReplace: "data.backupReasonReplace"
                }
            }
        }

        var created: Date
        var trainCount: Int
        var reason: Reason
        /// Whether the store this backup was taken from held North America
        /// rides in its working set, so ``restoreBackup()`` can write them
        /// back through the same partition rule the original save used
        /// rather than guessing from whatever the switch says now.
        ///
        /// Decodes a sidecar written before this field existed as `false` —
        /// which is correct for it: the switch did not exist yet, so no
        /// backup from that era could have held a North American ride in the
        /// first place.
        var includesNorthAmerica: Bool = false

        enum CodingKeys: String, CodingKey {
            case created, trainCount, reason, includesNorthAmerica
        }

        init(created: Date, trainCount: Int, reason: Reason, includesNorthAmerica: Bool = false) {
            self.created = created
            self.trainCount = trainCount
            self.reason = reason
            self.includesNorthAmerica = includesNorthAmerica
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            created = try container.decode(Date.self, forKey: .created)
            trainCount = try container.decode(Int.self, forKey: .trainCount)
            reason = try container.decode(Reason.self, forKey: .reason)
            includesNorthAmerica =
                try container.decodeIfPresent(Bool.self, forKey: .includesNorthAmerica) ?? false
        }
    }

    private(set) var backup: Backup?

    // MARK: - the order the files are touched in

    /// The tail of the queue every file operation joins.
    ///
    /// Moving the writes off the main actor introduces a hazard the
    /// synchronous version could not have: two saves in flight at once, the
    /// older one landing last and putting back the store the reader has
    /// already edited. An actor does not prevent that on its own — it runs one
    /// message at a time but promises nothing about which message it takes
    /// next — so each operation is made to wait for the one enqueued before
    /// it, and the chain is built here, on the main actor, in the order the
    /// app asked.
    ///
    /// That ordering is also what keeps "write the recovery copy, THEN delete
    /// everything" in that order across a suspension point, and what makes the
    /// read that ``ItineraryStore`` does after a restore see the restored file
    /// rather than the one it replaced.
    private var queue: Task<Void, Never>?
    /// Consecutive saves waiting behind the same operation may share one
    /// write. A read, backup, restore or delete seals the batch immediately.
    @MainActor
    private final class SaveBatch {
        var store: TrainStore
        let includeNorthAmerica: Bool
        var started = false
        var completion: Task<Bool, Never>?
        init(_ store: TrainStore, includeNorthAmerica: Bool) {
            self.store = store
            self.includeNorthAmerica = includeNorthAmerica
        }
        func take() -> (TrainStore, Bool) {
            started = true
            return (store, includeNorthAmerica)
        }
    }
    private var pendingSave: SaveBatch?
    private var deletionRevision = 0
    /// Bumped once per save that actually starts a new write (coalesced
    /// snapshot updates on an unstarted batch share the same sequence). A
    /// completion only sets or clears ``lastSaveError`` when its own sequence
    /// is still the latest one — an older save's completion landing after a
    /// newer one must not stomp the newer result, whichever way either went.
    private var saveSequence = 0

    /// Put one operation at the back of the queue.
    ///
    /// The returned task is how a caller waits for its own operation without
    /// waiting for anybody else's; discarding it is the fire-and-forget form,
    /// which is what the buttons that only publish an error afterwards use.
    @discardableResult
    private func enqueue<T: Sendable>(
        _ work: @escaping @Sendable (RideStorage) async throws -> T
    ) -> Task<T, Error> {
        pendingSave = nil
        let previous = queue
        let operation = Task<T, Error> {
            await previous?.value
            return try await work(RideStorage.shared)
        }
        // The tail swallows the outcome deliberately: a failed write must not
        // cancel the operations queued behind it, only report itself to the
        // caller that asked for it.
        queue = Task { _ = await operation.result }
        return operation
    }

    // MARK: - reading

    /// A bundled sample.
    ///
    /// Deliberately not queued: the samples ship inside the app bundle and
    /// nothing in this app ever writes them, so there is no order to keep them
    /// in, and putting the largest read in the app behind a save would be a
    /// wait for nothing. It goes to the storage actor for the other reason —
    /// the Japanese sample is 1.2 MB of JSON, and decoding it where the map is
    /// drawn is a load that stops the app rather than one that takes a moment.
    func sample(_ resource: String) async throws -> TrainStore {
        try await RideStorage.shared.decodeSample(resource)
    }

    /// The saved store, and whether North America was actually decoded into
    /// it — the caller (`ItineraryStore.load`) needs the second half to set
    /// ``northAmericaInWorkingSet`` correctly, rather than assuming the
    /// switch's current value describes a read that may have started before
    /// it last changed.
    ///
    /// An unreadable NA file must not block the main rides: `decodeStore`
    /// answers `includedNorthAmerica: false` when that happens, and the
    /// decode failure is surfaced here as ``lastSaveError`` rather than
    /// thrown, since the load this feeds still succeeded.
    func savedStore() async throws -> (store: TrainStore, includedNorthAmerica: Bool) {
        let includeNorthAmerica = Region.northAmericaEnabled
        let result = try await enqueue {
            try await $0.decodeStore(includeNorthAmerica: includeNorthAmerica)
        }.value
        if let naError = result.naError {
            lastSaveError = naError.localizedDescription
        }
        return (result.store, result.includedNorthAmerica)
    }

    /// The rides kept in the North America file, or an empty store if there
    /// is none yet — the file is only written once a North American ride
    /// exists to put in it.
    func northAmericaStore() async throws -> TrainStore {
        try await enqueue { try await $0.decodeNorthAmericaStore() }.value
    }

    func refreshSavedState() async {
        guard let state = try? await enqueue({ await $0.savedState() }).value else { return }
        hasSavedStore = state.hasStore
        savedStoreDate = state.storeDate
        backup = state.backup
    }

    // MARK: - writing

    /// Saves as the reader's own store for this country.
    ///
    /// The bytes come from `StoreOperations.exportTrainStore`, which is the
    /// web app's own 匯出 JSON ported and checked against it — **not** from
    /// `JSONEncoder`.
    ///
    /// That distinction is the whole point of saving a JSON file rather than
    /// using a database. `JSONEncoder` has no setting that emits insertion
    /// order, and insertion order *is* the format: with `.sortedKeys` this
    /// wrote a third spelling, neither of the two the web app produces, so the
    /// file was interchangeable with nothing. The first version of this file
    /// did exactly that.
    ///
    /// Written atomically: a store half-written because the app was killed
    /// mid-save is worse than no store, because the reader would not find out
    /// until the next launch.
    ///
    /// Returns before the file exists. Consecutive saves that have not started
    /// serialize their latest snapshot once. Every intervening file operation
    /// seals that snapshot, preserving read/backup/restore/delete ordering.
    ///
    /// The returned task finishes once the outcome has been published, which
    /// is what a caller that has to *report* the save waits for: the import
    /// summary says whether it landed, and ``lastSaveError`` answers that only
    /// after the write it is being asked about. Everything else discards the
    /// task and leaves the reporting to the data screen's error card.
    @discardableResult
    func save(_ store: TrainStore) -> Task<Bool, Never> {
        // `northAmericaInWorkingSet`, not the switch: whether a full replace
        // of the NA file is safe depends on whether `store` actually holds
        // those rides right now, which only `ItineraryStore` can say.
        save(store, includeNorthAmerica: northAmericaInWorkingSet)
    }

    /// Same as ``save(_:)``, but flushes the North America rides to their own
    /// file even while the switch is off — used to hand them off explicitly
    /// (`ItineraryStore.setNorthAmericaEnabled` turning off) rather than
    /// relying on the stray-merge path.
    @discardableResult
    func saveIncludingNorthAmerica(_ store: TrainStore) -> Task<Bool, Never> {
        save(store, includeNorthAmerica: true)
    }

    /// Returns whether THIS save landed, not whether the batch it may have
    /// been folded into did — a caller several saves back in a coalesced
    /// batch still gets the batch's actual outcome, since it is the same
    /// bytes and the same write. What this buys a caller like `ImportFlow`
    /// is a result it can read straight off the value returned to it,
    /// instead of reading ``lastSaveError`` afterward and hoping no later
    /// save has already overwritten it — `sequence == saveSequence` guards
    /// that shared property, but this return value needs no such guard.
    @discardableResult
    private func save(_ store: TrainStore, includeNorthAmerica: Bool) -> Task<Bool, Never> {
        if let batch = pendingSave, !batch.started, batch.includeNorthAmerica == includeNorthAmerica,
            let completion = batch.completion
        {
            batch.store = store
            return completion
        }
        let batch = SaveBatch(store, includeNorthAmerica: includeNorthAmerica)
        let revision = deletionRevision
        saveSequence += 1
        let sequence = saveSequence
        let write = enqueue { storage in
            let (snapshot, includeNorthAmerica) = await batch.take()
            return try await storage.writeStore(snapshot, includeNorthAmerica: includeNorthAmerica)
        }
        let completion = Task {
            do {
                let date = try await write.value
                guard deletionRevision == revision else { return false }
                savedStoreDate = date
                hasSavedStore = true
                if sequence == saveSequence { lastSaveError = nil }
                return true
            } catch {
                guard deletionRevision == revision else { return false }
                if sequence == saveSequence { lastSaveError = error.localizedDescription }
                return false
            }
        }
        batch.completion = completion
        pendingSave = batch
        return completion
    }

    /// Writes the recovery copy a destructive action can be undone from.
    ///
    /// Same canonical bytes as ``save(_:)`` — a backup that cannot be
    /// re-imported by the web app is not a backup of this store, it is a
    /// second format.
    ///
    /// The destructive action that follows must be queued behind this one AND
    /// must not run at all if this fails — a destructive step that ran
    /// without a landed recovery copy would be exactly the data loss the
    /// backup exists to prevent. Failure is reported by throwing, and by
    /// ``backup`` staying nil: the recovery card the screen offers is drawn
    /// from that, so a backup that did not land is a card that never appears
    /// rather than one that promises a file nobody wrote.
    func snapshotBackup(_ store: TrainStore, reason: Backup.Reason) async throws {
        let meta = Backup(
            created: Date(), trainCount: store.trains.count, reason: reason,
            includesNorthAmerica: northAmericaInWorkingSet)
        // Still enqueued on the same serial queue, so it stays ordered ahead
        // of any destructive write the caller issues after it lands.
        let write = enqueue { try await $0.writeBackup(store, meta: meta) }
        do {
            try await write.value
            backup = meta
        } catch {
            // A failed write now leaves the OLD backup pair intact (see
            // `writeBackup`), so `backup` must only go to nil when there
            // really is nothing left to recover — re-read rather than
            // assumed, since a stale `backup` describing bytes that no
            // longer landed would be exactly the wrong-card failure this
            // path used to risk.
            if let recovered = try? await enqueue({ await $0.recoverableBackup() }).value {
                backup = recovered
            } else {
                backup = nil
            }
            lastSaveError = error.localizedDescription
            throw error
        }
    }

    /// Puts the backup back as the reader's own store, and returns the one
    /// being restored so a caller can say what it was.
    ///
    /// The backup is consumed: leaving it in place after a restore would offer
    /// a "restore" button that now restores what is already on screen, which
    /// reads as a second undo that does nothing.
    ///
    /// The copy is queued rather than written here, so that it cannot overtake
    /// a save still in flight and be undone by it a moment later. It is then
    /// awaited rather than left running, so that a recovery copy that could not
    /// be read, decoded or written still reaches the caller's `catch` and is
    /// reported where the reader asked for the restore.
    @discardableResult
    func restoreBackup() async throws -> Backup {
        guard let restoring = backup else { throw LibraryError.missingBackup }
        // The backup's OWN answer, not the switch's current one: a backup
        // taken while North America was in the working set must be restored
        // that way even if the switch has since turned off, or its rides
        // would be silently left out of the restore.
        let restore = enqueue {
            try await $0.restoreBackup(includeNorthAmerica: restoring.includesNorthAmerica)
        }
        backup = nil
        lastSaveError = nil
        let outcome = await restore.result
        // Read back rather than assumed: a restore that did not land leaves
        // the recovery copy where it was, and the screen has to offer it again
        // instead of claiming it was consumed.
        await refreshSavedState()
        if case .failure(let error) = outcome { throw error }
        // Left for `ItineraryStore` to set: whatever reloads after this
        // (`load(from:)`) reads the file just written and sets
        // ``northAmericaInWorkingSet`` from what it actually decoded, which
        // is the one rule this flag has.
        return restoring
    }

    func discardBackup() {
        enqueue { await $0.discardBackup() }
        backup = nil
    }

    func deleteSavedStore() {
        deletionRevision += 1
        // `northAmericaInWorkingSet`, not the switch: whether the NA file
        // holds rides the working set actually published, not whether the
        // switch happens to say on right now (see `save(_:)` above).
        let includeNorthAmerica = northAmericaInWorkingSet
        enqueue { await $0.removeStore(includeNorthAmerica: includeNorthAmerica) }
        hasSavedStore = false
        savedStoreDate = nil
        forgetLoadedSamples()
    }

    /// Merges North American rides straight into their own file, bypassing
    /// the working set entirely.
    ///
    /// This is the door `ItineraryStore.publishWorkingSet` uses when North
    /// America rides arrive — an import, a sample, a `replaceAll` — while the
    /// switch is off: the working set the reader sees never held them, so
    /// there is nothing for the ordinary save to carry, and this is what
    /// keeps them from being silently dropped instead.
    func stashHidden(_ trains: [Train]) {
        guard !trains.isEmpty else { return }
        let write = enqueue { try await $0.mergeIntoNorthAmerica(trains) }
        Task {
            if case .failure(let error) = await write.result {
                lastSaveError = error.localizedDescription
            }
        }
    }

    /// Remember that a sample's rides are in the working set.
    ///
    /// Persisted, because the claim it makes — "these rides are already here" —
    /// outlives the launch that loaded them, and a checkmark that disappeared
    /// overnight would invite loading the same 201 journeys again.
    func noteSampleLoaded(_ resource: String) {
        loadedSamples.insert(resource)
        persistLoadedSamples()
    }

    func forgetLoadedSamples() {
        loadedSamples.removeAll()
        persistLoadedSamples()
    }

    private func persistLoadedSamples() {
        UserDefaults.standard.set(Array(loadedSamples).sorted(), forKey: Self.loadedSamplesKey)
    }

    /// The precomputed route directories a region's rides may have been solved
    /// into, most likely first.
    ///
    /// The web app knows which one to read because it has one store open at a
    /// time and that store came from one place. A merged store has no such
    /// provenance — a reader can hold the 201-journey Japanese sample, the
    /// New Year loop and their own rides at once — so the route store searches
    /// this list instead. That is safe rather than approximate: every part is
    /// matched by the same route-cache digest the web app uses, so a part
    /// belonging to another itinerary is rejected rather than drawn.
    nonisolated static func routeDatasets(for region: Region) -> [String] {
        switch region {
        case .jp: ["sample-data", "new-year-grand-loop-data", "tokyo-limited-express-loop-data"]
        case .tw: ["sample-data-tw"]
        case .hk: ["sample-data-hk"]
        case .mo: ["sample-data-mo"]
        case .kr: ["sample-data-kr"]
        // No precomputed route dataset for the two North American networks,
        // and that is a decision rather than a gap: a precomputed part exists
        // to save the solver from re-deriving a route the web app already
        // solved, and the web app has never had these packages open. Their
        // sample journeys go through the on-device solver like any journey the
        // reader records themselves, and are written into the route cache the
        // first time — which is the same path, one solve later.
        case .us, .ca: []
        }
    }

    /// Fold any per-region stores left by an earlier version into the merged
    /// one, once.
    ///
    /// Runs before the first read and does nothing when there is nothing to
    /// do. The legacy files are left on disk rather than deleted: the merge is
    /// the kind of one-way step that is worth being able to check afterwards,
    /// and five small JSON files are a cheap receipt. A subsequent launch sees
    /// the merged file and skips this entirely.
    func migrateLegacyStores() async {
        do {
            if let written = try await enqueue({ try await $0.foldLegacyStores() }).value {
                savedStoreDate = written
                hasSavedStore = true
            }
            // Independent of the fold above and of the switch: a
            // `train-store.json` from before this feature existed may hold
            // North American rides that now belong in their own file.
            if let written = try await enqueue({ try await $0.splitNorthAmericaFromMainStore() })
                .value
            {
                savedStoreDate = written
                hasSavedStore = true
            }
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    enum LibraryError: LocalizedError {
        case missingSample(String)
        case missingBackup

        var errorDescription: String? {
            switch self {
            case .missingSample(let name):
                """
                \(name).json is not in the app bundle. Run ios/copy-rail-packages.sh — \
                the samples are read from app/data rather than committed twice.
                """
            case .missingBackup:
                "There is no recovery copy on this device to restore from."
            }
        }
    }
}

/// Every touch of the files under Application Support, off the main actor.
///
/// A 201-journey store is a megabyte of JSON coming in and a megabyte going
/// out through the canonical stringifier, and both used to happen on the actor
/// that draws the map: the launch that decoded the saved store and the frame
/// after every edit were the two the app dropped.
///
/// It owns the paths as well as the work, so that nothing above it needs to
/// know where the file is — and so that a second writer cannot be added on the
/// main actor by reaching for a URL that is lying around.
///
/// Application Support rather than Documents because this is app state the
/// reader did not create as a document, and it is excluded from iCloud backup
/// only where it is a cache — this is not, so it is backed up.
actor RideStorage {

    static let shared = RideStorage()
    private var exportCache = MergedStore.ExportCache()

    /// What the data screen says about the copy on this device, read in one
    /// pass so the screen does not pay for four separate trips to the disk.
    struct SavedState: Sendable {
        var hasStore = false
        var storeDate: Date?
        var backup: RideLibrary.Backup?
    }

    // MARK: - reading

    func savedState() -> SavedState {
        let url = Self.storeURL()
        let mainExists = FileManager.default.fileExists(atPath: url.path)
        let naExists = FileManager.default.fileExists(atPath: Self.northAmericaStoreURL().path)
        return SavedState(
            hasStore: mainExists || naExists,
            storeDate: mainExists
                ? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate : nil,
            backup: recoverableBackup())
    }

    /// Reads the sidecar rather than the backup itself: what the screen shows
    /// is a date and a count, and decoding a 201-journey store to learn them
    /// would be a megabyte of work every time the tab is opened.
    func recoverableBackup() -> RideLibrary.Backup? {
        guard FileManager.default.fileExists(atPath: Self.backupURL().path),
            let data = try? Data(contentsOf: Self.backupMetaURL()),
            let decoded = try? metaDecoder.decode(RideLibrary.Backup.self, from: data)
        else { return nil }
        return decoded
    }

    /// One of the seven read-only itineraries the app ships with.
    func decodeSample(_ resource: String) throws -> TrainStore {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw RideLibrary.LibraryError.missingSample(resource)
        }
        return try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
    }

    /// The working set: the visible store, and — when North America is
    /// enabled — the North American rides appended after it.
    ///
    /// Non-NA rides come first and NA rides are concatenated after, deduped
    /// by id keeping the first: the two files are not expected to collide,
    /// but a stray duplicate must not be shown twice.
    func decodeStore(includeNorthAmerica: Bool) throws -> (
        store: TrainStore, includedNorthAmerica: Bool, naError: Error?
    ) {
        let main = try decodeStoreFile(Self.storeURL())
        guard includeNorthAmerica else { return (main, false, nil) }
        let na: TrainStore
        do {
            na = try decodeNorthAmericaStore()
        } catch {
            // The NA file exists but failed to decode. The main rides must
            // still load — a broken NA file is not a reason to lose the
            // reader's whole store — and `includedNorthAmerica: false` keeps
            // a save issued on the strength of this read from full-replacing
            // the unreadable file (see `RideStorage.writeStore`).
            return (main, false, error)
        }
        guard !na.trains.isEmpty else { return (main, true, nil) }
        var seen = Set(main.trains.map(\.id))
        var trains = main.trains
        for train in na.trains where !seen.contains(train.id) {
            seen.insert(train.id)
            trains.append(train)
        }
        return (TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: trains), true, nil)
    }

    /// The North America file alone, or an empty store when it does not
    /// exist yet — nothing has ever put a North American ride away.
    func decodeNorthAmericaStore() throws -> TrainStore {
        let url = Self.northAmericaStoreURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [])
        }
        return try decodeStoreFile(url)
    }

    private func decodeStoreFile(_ url: URL) throws -> TrainStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [])
        }
        return try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
    }

    // MARK: - writing

    /// The canonical bytes, atomically, and the moment they landed.
    ///
    /// Partitions `store.trains` by ``Region/isNorthAmerica(_:)``: the non-NA
    /// part always replaces `train-store.json`. The NA part's fate depends on
    /// `includeNorthAmerica` — see the doc on the call sites in `RideLibrary`
    /// for why this cannot just always be true. When the switch is off and
    /// the NA part is non-empty (a stray — the working set should not have
    /// held any), it is merged into the NA file by id, incoming winning,
    /// rather than dropped or used to overwrite the file outright.
    func writeStore(_ store: TrainStore, includeNorthAmerica: Bool) throws -> Date {
        try createDirectory()
        var mainTrains: [Train] = []
        var naTrains: [Train] = []
        for train in store.trains {
            if Region.isNorthAmerica(train) { naTrains.append(train) } else { mainTrains.append(train) }
        }
        let mainStore = TrainStore(schemaVersion: store.schemaVersion, trains: mainTrains)
        try writeExport(mainStore, to: Self.storeURL())
        if includeNorthAmerica {
            // Full replace, even when empty — this is the user deleting rides
            // while North America is visible, and leaving the old file behind
            // would resurrect them the next time the switch is turned on.
            let naStore = TrainStore(schemaVersion: store.schemaVersion, trains: naTrains)
            try writeExport(naStore, to: Self.northAmericaStoreURL())
        } else if !naTrains.isEmpty {
            try mergeIntoNorthAmerica(naTrains)
        }
        return Date()
    }

    /// The canonical bytes, atomically, to an arbitrary location.
    ///
    /// Kept as its own function — rather than folded into every call site —
    /// so that ``writeBackup(_:meta:)`` and this one are the only two places
    /// that call the exporter with the write cache. A verify.sh contract
    /// counts that call's exact spelling; a third writer that lost it
    /// somewhere else is the failure it exists to catch.
    private func writeExport(_ store: TrainStore, to url: URL) throws {
        try Data(MergedStore.export(store, cache: &exportCache).utf8).write(to: url, options: .atomic)
    }

    /// Folds rides into the North America file by id, without touching the
    /// file at all when there is nothing to add.
    ///
    /// `existingWins` is for the legacy fold: a `train-store-us.json` from
    /// before this feature existed must not overwrite anything the reader has
    /// already recorded under this feature. Every other caller — a stray from
    /// an ordinary save, or a hidden ride an import handed off — is newer than
    /// whatever the NA file already holds, so incoming wins there instead.
    @discardableResult
    func mergeIntoNorthAmerica(_ trains: [Train], existingWins: Bool = false) throws -> Date? {
        guard !trains.isEmpty else { return nil }
        try createDirectory()
        let incoming = TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: trains)
        let existing: TrainStore
        do {
            existing = try decodeNorthAmericaStore()
        } catch {
            // The NA file exists but is unreadable. Do not throw the incoming
            // rides away with it: park them next to the broken file, under
            // their own name, so they survive to be recovered by hand — the
            // unreadable file itself is left untouched, since overwriting it
            // is exactly the data loss this is trying to avoid — then report
            // the original decode failure exactly as before.
            let recoveredURL = Self.northAmericaStoreURL()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "train-store-na.recovered-\(Int(Date().timeIntervalSince1970)).json")
            try writeExport(incoming, to: recoveredURL)
            throw error
        }
        let merged =
            existingWins
            ? MergedStore.merging(existing, into: incoming)
            : MergedStore.merging(incoming, into: existing)
        try writeExport(merged, to: Self.northAmericaStoreURL())
        return Date()
    }

    func writeBackup(_ store: TrainStore, meta: RideLibrary.Backup) throws {
        try createDirectory()
        // The new bytes are written to a staging file first, so a failure
        // partway through export/encode never touches the previous backup
        // pair — a reader who asked for a snapshot before a destructive
        // action must still find the OLD backup intact if this throws. Only
        // once the staging file has landed completely is it swapped in for
        // the real backup, and only once THAT swap has landed is the old
        // sidecar replaced. A crash between the swap and the sidecar write
        // can never pair new backup bytes with the OLD sidecar, because
        // `recoverableBackup()` requires both files to exist to report a
        // backup at all — a missing sidecar reads as "no backup" rather than
        // the wrong one.
        let staging = Self.backupStagingURL()
        try? FileManager.default.removeItem(at: staging)
        do {
            try Data(MergedStore.export(store, cache: &exportCache).utf8).write(to: staging, options: .atomic)
            if FileManager.default.fileExists(atPath: Self.backupURL().path) {
                _ = try FileManager.default.replaceItemAt(Self.backupURL(), withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: Self.backupURL())
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        try metaEncoder.encode(meta).write(to: Self.backupMetaURL(), options: .atomic)
    }

    /// Decodes the recovery bytes and re-exports them through the same
    /// partitioning write every store goes through, then consumes the backup.
    ///
    /// Decoded rather than byte-copied: the backup may hold North American
    /// rides that must be split into `train-store.json`/`train-store-na.json`
    /// exactly as any other write is (see `writeStore`), which a raw copy
    /// over `train-store.json` alone could not do, and would leave the NA
    /// rides in the restored store's bytes but never written to their own
    /// file. `includeNorthAmerica` is the backup's OWN answer — see
    /// `RideLibrary.Backup.includesNorthAmerica` — not whatever the switch
    /// says now.
    func restoreBackup(includeNorthAmerica: Bool) throws {
        let bytes = try Data(contentsOf: Self.backupURL())
        let store = try JSONDecoder().decode(TrainStore.self, from: bytes)
        _ = try writeStore(store, includeNorthAmerica: includeNorthAmerica)
        discardBackup()
    }

    func discardBackup() {
        try? FileManager.default.removeItem(at: Self.backupURL())
        try? FileManager.default.removeItem(at: Self.backupMetaURL())
    }

    func removeStore(includeNorthAmerica: Bool) {
        try? FileManager.default.removeItem(at: Self.storeURL())
        if includeNorthAmerica {
            try? FileManager.default.removeItem(at: Self.northAmericaStoreURL())
        }
    }

    /// Folds the per-region stores an earlier version wrote into the merged
    /// one, and reports when the merged file was written — or nothing at all,
    /// which is what every launch after the first one gets.
    func foldLegacyStores() throws -> Date? {
        // Durable rather than "merged file absent": deleting the merged store
        // (`removeStore`) must not make the next launch re-fold the legacy
        // files behind its back. Gated on both the marker AND the merged
        // file's absence, so an existing install with a merged file already
        // on disk — which never ran this fold, and must not now — gets the
        // marker backfilled instead of a fold.
        let marker = Self.legacyFoldMarkerURL()
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        guard !FileManager.default.fileExists(atPath: Self.storeURL().path) else {
            try createDirectory()
            FileManager.default.createFile(atPath: marker.path, contents: nil)
            return nil
        }
        var trains: [Train] = []
        var seen = Set<String>()
        for (region, name) in Self.legacyStoreURLs {
            let url = Self.directory().appending(path: name)
            guard let data = try? Data(contentsOf: url),
                  let store = try? JSONDecoder().decode(TrainStore.self, from: data)
            else { continue }
            for train in store.trains {
                var copy = train
                copy.region = region.code
                // Two regions could have written the same id — nothing stopped
                // them while the stores were separate. Renaming rather than
                // dropping keeps both rides; losing one silently would be the
                // migration eating data.
                let id =
                    seen.contains(copy.id)
                    ? TrainValidation.makeUniqueTrainId("\(copy.id)-\(region.code)", existingIDs: seen)
                    : copy.id
                copy.id = id
                seen.insert(id)
                trains.append(copy)
            }
        }
        try createDirectory()
        guard !trains.isEmpty else {
            FileManager.default.createFile(atPath: marker.path, contents: nil)
            return nil
        }
        var mainTrains: [Train] = []
        var naTrains: [Train] = []
        for train in trains {
            if Region.isNorthAmerica(train) { naTrains.append(train) } else { mainTrains.append(train) }
        }
        // Existing-wins, not a full replace: a legacy `train-store-us.json`/
        // `train-store-ca.json` predates the switch entirely, and its rides
        // must not overwrite anything the reader already recorded through the
        // NA file since — a fold is the oldest data in the app, not the
        // newest.
        try mergeIntoNorthAmerica(naTrains, existingWins: true)
        let mainStore = TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: mainTrains)
        try writeExport(mainStore, to: Self.storeURL())
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        return Date()
    }

    /// Moves any North American ride sitting in `train-store.json` out to the
    /// North America file, merging it in by id, and rewrites the main file
    /// without them.
    ///
    /// One-time in effect, not in code: a `train-store.json` that already
    /// holds no NA rides — every launch after the first that runs this — does
    /// nothing, because there is nothing to move. Written NA-file-first, then
    /// main file, so a crash between the two loses nothing: the ride is
    /// either still in the main file, or already safe in both.
    ///
    /// NA rides are found with ``Region/isNorthAmerica(_:)`` — which reads
    /// `US-`/`CA-`-prefixed station codes synchronously — plus an explicit
    /// `train.region` of `"us"`/`"ca"`, which needs no codes to read at all.
    ///
    /// Gated on a `UserDefaults` marker set only after both writes succeed:
    /// without it, this would decode `train-store.json` — a megabyte of JSON
    /// for a national store — on every single launch forever, to learn the
    /// same "nothing to move" answer every launch after the first one gets.
    @discardableResult
    func splitNorthAmericaFromMainStore() throws -> Date? {
        guard !UserDefaults.standard.bool(forKey: Self.naSplitMarkerKey) else { return nil }
        let mainStore = try decodeStoreFile(Self.storeURL())
        var strayed: [Train] = []
        var kept: [Train] = []
        for train in mainStore.trains {
            if Region.isNorthAmerica(train) || train.region == "us" || train.region == "ca" {
                strayed.append(train)
            } else {
                kept.append(train)
            }
        }
        guard !strayed.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.naSplitMarkerKey)
            return nil
        }
        try mergeIntoNorthAmerica(strayed)
        try createDirectory()
        let rewritten = TrainStore(schemaVersion: mainStore.schemaVersion, trains: kept)
        try writeExport(rewritten, to: Self.storeURL())
        UserDefaults.standard.set(true, forKey: Self.naSplitMarkerKey)
        return Date()
    }

    /// Set once ``splitNorthAmericaFromMainStore()`` has run to completion —
    /// including the case where it found nothing to move — so that every
    /// launch after the first skips decoding the main store to check again.
    private static let naSplitMarkerKey = "rides-na-split-v1"

    private func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: Self.directory(), withIntermediateDirectories: true)
    }

    // MARK: - locations

    /// One file, holding every region.
    ///
    /// It used to be one file per region, because the app had a region switch
    /// and "load the Taiwan sample" had to be unambiguous about what it
    /// replaced. With every region drawn at once there is one working set, so
    /// there is one file — and each ride says which region it belongs to
    /// (`Train.region`) rather than being told by which file it was in.
    private static func storeURL() -> URL {
        directory().appending(path: "train-store.json")
    }

    /// The North American rides, kept apart so that turning the switch off
    /// never has to touch — or risk — the store everyone else's rides live
    /// in.
    private static func northAmericaStoreURL() -> URL {
        directory().appending(path: "train-store-na.json")
    }

    /// The per-region files this app wrote before the merge, in the order they
    /// are folded into the merged store.
    private static let legacyStoreURLs: [(Region, String)] = Region.ordered.map {
        ($0, "train-store-\($0.rawValue).json")
    }

    /// The recovery copy and its sidecar. The sidecar is separate so that the
    /// backup file itself stays byte-identical to an export — a date stamped
    /// inside it would make it a different document from the one it copies.
    private static func backupURL() -> URL {
        directory().appending(path: "train-store.backup.json")
    }

    private static func backupMetaURL() -> URL {
        directory().appending(path: "train-store.backup-meta.json")
    }

    /// Where ``writeBackup(_:meta:)`` lands the new bytes before swapping
    /// them in for ``backupURL()`` — never read from directly.
    private static func backupStagingURL() -> URL {
        directory().appending(path: "train-store.backup.json.staging")
    }

    /// Set once ``foldLegacyStores()`` has run to completion — including the
    /// backfill case where a merged store already existed and there was
    /// nothing to fold — so that deleting the merged store afterwards
    /// (``removeStore(includeNorthAmerica:)``) can never make a later launch
    /// re-fold the same legacy files back in.
    private static func legacyFoldMarkerURL() -> URL {
        directory().appending(path: "legacy-folded.marker")
    }

    private let metaEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let metaDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        return base.appending(path: "Rides", directoryHint: .isDirectory)
    }
}
