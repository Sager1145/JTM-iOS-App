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
    private var queue: Task<Void, Never>?

    /// Put one operation at the back of the queue.
    ///
    /// The returned task is how a caller waits for its own operation without
    /// waiting for anybody else's; discarding it is the fire-and-forget form,
    /// which is what the buttons that only publish an error afterwards use.
    @discardableResult
    private func enqueue<T: Sendable>(
        _ work: @escaping @Sendable (RideStorage) async throws -> T
    ) -> Task<T, Error> {
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
    /// Returns before the file exists. `store` is a value, so what is written
    /// is what the caller handed over however long the queue ahead of it is.
    ///
    /// The returned task finishes once the outcome has been published, which
    /// is what a caller that has to *report* the save waits for: the import
    /// summary says whether it landed, and ``lastSaveError`` answers that only
    /// after the write it is being asked about. Everything else discards the
    /// task and leaves the reporting to the data screen's error card.
    @discardableResult
    func save(_ store: TrainStore) -> Task<Void, Never> {
        lastSaveError = nil
        let write = enqueue { try await $0.writeStore(store) }
        return Task {
            do {
                savedStoreDate = try await write.value
                hasSavedStore = true
            } catch {
                lastSaveError = error.localizedDescription
            }
        }
    }

    /// Writes the recovery copy a destructive action can be undone from.
    ///
    /// Same canonical bytes as ``save(_:)`` — a backup that cannot be
    /// re-imported by the web app is not a backup of this store, it is a
    /// second format.
    ///
    /// The destructive action that follows is queued behind this one, so it
    /// cannot overtake the copy it is meant to be undoable from. Failure is
    /// reported rather than thrown, and it is reported by ``backup`` staying
    /// nil: the recovery card the screen offers is drawn from that, so a
    /// backup that did not land is a card that never appears rather than one
    /// that promises a file nobody wrote.
    func snapshotBackup(_ store: TrainStore, reason: Backup.Reason) {
        let meta = Backup(created: Date(), trainCount: store.trains.count, reason: reason)
        let write = enqueue { try await $0.writeBackup(store, meta: meta) }
        Task {
            do {
                try await write.value
                backup = meta
            } catch {
                lastSaveError = error.localizedDescription
            }
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
            guard let written = try await enqueue({ try await $0.foldLegacyStores() }).value
            else { return }
            savedStoreDate = written
            hasSavedStore = true
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
        let exists = FileManager.default.fileExists(atPath: url.path)
        return SavedState(
            hasStore: exists,
            storeDate: exists
                ? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate : nil,
            backup: recoverableBackup())
    }

    /// Reads the sidecar rather than the backup itself: what the screen shows
    /// is a date and a count, and decoding a 201-journey store to learn them
    /// would be a megabyte of work every time the tab is opened.
    private func recoverableBackup() -> RideLibrary.Backup? {
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

    func decodeStore() throws -> TrainStore {
        try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: Self.storeURL()))
    }

    // MARK: - writing

    /// The canonical bytes, atomically, and the moment they landed.
    func writeStore(_ store: TrainStore) throws -> Date {
        try createDirectory()
        try Data(MergedStore.export(store).utf8).write(to: Self.storeURL(), options: .atomic)
        return Date()
    }

    func writeBackup(_ store: TrainStore, meta: RideLibrary.Backup) throws {
        try createDirectory()
        try Data(MergedStore.export(store).utf8).write(to: Self.backupURL(), options: .atomic)
        try metaEncoder.encode(meta).write(to: Self.backupMetaURL(), options: .atomic)
    }

    /// Copies the recovery bytes over the saved store, then consumes them.
    ///
    /// Decoded before it is copied, and the copy is of the bytes that decoded:
    /// a backup that is not a store must not be written over the one that is,
    /// and re-exporting a decoded store here would put a second spelling of
    /// the same rides on disk under the name of the first.
    func restoreBackup() throws {
        let bytes = try Data(contentsOf: Self.backupURL())
        _ = try JSONDecoder().decode(TrainStore.self, from: bytes)
        try createDirectory()
        try bytes.write(to: Self.storeURL(), options: .atomic)
        discardBackup()
    }

    func discardBackup() {
        try? FileManager.default.removeItem(at: Self.backupURL())
        try? FileManager.default.removeItem(at: Self.backupMetaURL())
    }

    func removeStore() {
        try? FileManager.default.removeItem(at: Self.storeURL())
    }

    /// Folds the per-region stores an earlier version wrote into the merged
    /// one, and reports when the merged file was written — or nothing at all,
    /// which is what every launch after the first one gets.
    func foldLegacyStores() throws -> Date? {
        guard !FileManager.default.fileExists(atPath: Self.storeURL().path) else { return nil }
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
                if seen.contains(copy.id) { copy.id = "\(copy.id)-\(region.code)" }
                seen.insert(copy.id)
                trains.append(copy)
            }
        }
        guard !trains.isEmpty else { return nil }
        return try writeStore(
            TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: trains))
    }

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
