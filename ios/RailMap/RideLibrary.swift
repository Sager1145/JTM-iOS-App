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
    @ObservationIgnored private let storage: RideStorage
    @ObservationIgnored private let operations = RidePersistenceQueue()

    init(storage: RideStorage = .shared) {
        self.storage = storage
    }
    /// Consecutive saves waiting behind the same operation may share one
    /// write. A read, backup, restore or delete seals the batch immediately.
    @MainActor
    private final class SaveBatch {
        var store: TrainStore
        var started = false
        var completion: Task<Bool, Never>?
        init(_ store: TrainStore) {
            self.store = store
        }
        func take() -> TrainStore {
            started = true
            return store
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
        let storage = storage
        return operations.enqueue { try await work(storage) }
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
        try await storage.decodeSample(resource)
    }

    /// Read after all earlier writes have landed.
    func savedStore() async throws -> TrainStore {
        try await enqueue { try await $0.decodeStore() }.value
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
    /// Returns whether THIS save landed, not whether the batch it may have
    /// been folded into did — a caller several saves back in a coalesced
    /// batch still gets the batch's actual outcome, since it is the same
    /// bytes and the same write. What this buys a caller like `ImportFlow`
    /// is a result it can read straight off the value returned to it,
    /// instead of reading ``lastSaveError`` afterward and hoping no later
    /// save has already overwritten it — `sequence == saveSequence` guards
    /// that shared property, but this return value needs no such guard.
    @discardableResult
    func save(_ store: TrainStore) -> Task<Bool, Never> {
        do {
            for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        } catch {
            pendingSave = nil
            saveSequence += 1
            lastSaveError = error.localizedDescription
            return Task { false }
        }
        if let batch = pendingSave, !batch.started,
            let completion = batch.completion
        {
            batch.store = store
            return completion
        }
        let batch = SaveBatch(store)
        let revision = deletionRevision
        saveSequence += 1
        let sequence = saveSequence
        let write = enqueue { storage in
            let snapshot = await batch.take()
            return try await storage.writeStore(snapshot)
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
            created: Date(), trainCount: store.trains.count, reason: reason)
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
        let restore = enqueue { try await $0.restoreBackup() }
        backup = nil
        lastSaveError = nil
        let outcome = await restore.result
        // Read back rather than assumed: a restore that did not land leaves
        // the recovery copy where it was, and the screen has to offer it again
        // instead of claiming it was consumed.
        await refreshSavedState()
        if case .failure(let error) = outcome { throw error }
        return restoring
    }

    func discardBackup() {
        enqueue { await $0.discardBackup() }
        backup = nil
    }

    func deleteSavedStore() {
        deletionRevision += 1
        enqueue { await $0.removeStore() }
        hasSavedStore = false
        savedStoreDate = nil
        forgetLoadedSamples()
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
