import Foundation
import RailCore

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
private final class StorageBox {
    weak var storage: RideStorage?
    init(_ storage: RideStorage) { self.storage = storage }
}

actor RideStorage {

    static let shared = RideStorage()
    private var exportCache = MergedStore.ExportCache()
    private let rootDirectory: URL?
    private let writeData: @Sendable (Data, URL) throws -> Void

    /// The composition root may provide an isolated store. Production keeps
    /// the historical Application Support location.
    init(
        directory: URL? = nil,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        }
    ) {
        rootDirectory = directory
        self.writeData = writeData
        BundledRegistry.install()
    }

    /// What the data screen says about the copy on this device, read in one
    /// pass so the screen does not pay for four separate trips to the disk.
    struct SavedState: Sendable {
        var hasStore = false
        var storeDate: Date?
        var backup: RideLibrary.Backup?
    }

    // MARK: - reading

    func savedState() -> SavedState {
        let url = storeURL()
        let mainExists = FileManager.default.fileExists(atPath: url.path)
        return SavedState(
            hasStore: mainExists,
            storeDate: mainExists
                ? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate : nil,
            backup: recoverableBackup())
    }

    /// Reads the sidecar rather than the backup itself: what the screen shows
    /// is a date and a count, and decoding a 201-journey store to learn them
    /// would be a megabyte of work every time the tab is opened.
    func recoverableBackup() -> RideLibrary.Backup? {
        guard let files = try? currentBackupFiles(),
            FileManager.default.fileExists(atPath: files.store.path),
            let data = try? Data(contentsOf: files.metadata),
            let decoded = try? metaDecoder.decode(RideLibrary.Backup.self, from: data)
        else { return nil }
        return decoded
    }

    /// One of the seven read-only itineraries the app ships with.
    func decodeSample(_ resource: String) throws -> TrainStore {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw RideLibrary.LibraryError.missingSample(resource)
        }
        let store = try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        return store
    }

    /// The one supported-region store. Legacy regional files are not read here.
    func decodeStore() throws -> TrainStore {
        try decodeStoreFile(storeURL())
    }

    private func decodeStoreFile(_ url: URL) throws -> TrainStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [])
        }
        let store = try JSONDecoder().decode(TrainStore.self, from: Data(contentsOf: url))
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        return upgraded(store)
    }

    /// Fills `station_id` / `operator_id` when that region's registry is already
    /// ready. A pending or unavailable region keeps the stored fields and is
    /// upgraded again when the preload settles.
    private func upgraded(_ store: TrainStore) -> TrainStore {
        var store = store
        BundledRegistry.preload(regions: MergedStore.regions(of: store.trains).map(\.code))
        Self.installSettleUpgrade()
        rememberForSettle()
        store.trains = store.trains.map(BundledRegistry.upgradeIfReady)
        return store
    }

    private static let settleLock = NSLock()
    nonisolated(unsafe) private static var settleStorages: [StorageBox] = []
    private static let settleUpgrade: Void = {
        BundledRegistry.addSettledHandler {
            let storages: [RideStorage]
            settleLock.lock()
            settleStorages = settleStorages.filter { $0.storage != nil }
            storages = settleStorages.compactMap(\.storage)
            settleLock.unlock()
            for storage in storages {
                Task { await storage.upgradeSettledFile() }
            }
        }
    }()

    private static func installSettleUpgrade() {
        _ = settleUpgrade
        // The caller is this actor. The handler list only needs the instance.
    }

    private func rememberForSettle() {
        Self.settleLock.lock()
        if !Self.settleStorages.contains(where: { $0.storage === self }) {
            Self.settleStorages.append(StorageBox(self))
        }
        Self.settleLock.unlock()
    }

    /// Rewrites the saved store once a pending region can fill registry ids.
    func upgradeSettledFile() {
        guard FileManager.default.fileExists(atPath: storeURL().path),
              let data = try? Data(contentsOf: storeURL()),
              let store = try? JSONDecoder().decode(TrainStore.self, from: data)
        else { return }
        let trains = store.trains.map(BundledRegistry.upgradeIfReady)
        guard zip(store.trains, trains).contains(where: identityFieldsChanged) else { return }
        try? writeStore(TrainStore(schemaVersion: store.schemaVersion, trains: trains))
    }

    private func identityFieldsChanged(_ before: Train, _ after: Train) -> Bool {
        if before.operatorID != after.operatorID || before.operatorIDs != after.operatorIDs { return true }
        guard before.stops.count == after.stops.count else { return true }
        return zip(before.stops, after.stops).contains { lhs, rhs in
            lhs.stationID != rhs.stationID || lhs.name != rhs.name || lhs.n02StationCode != rhs.n02StationCode
        }
    }

    // MARK: - writing

    /// Validate before touching the previous snapshot, then replace it atomically.
    func writeStore(_ store: TrainStore) throws -> Date {
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        try createDirectory()
        try writeExport(store, to: storeURL())
        return Date()
    }

    /// The canonical bytes, atomically, to an arbitrary location.
    ///
    /// Centralizes canonical export through the shared write cache. Backups use
    /// the same exporter; writes remain atomic at both destinations.
    private func writeExport(_ store: TrainStore, to url: URL) throws {
        try writeData(Data(MergedStore.export(store, cache: &exportCache).utf8), url)
    }

    func writeBackup(_ store: TrainStore, meta: RideLibrary.Backup) throws {
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        try createDirectory()
        let previous = try currentBackupGeneration()
        let generation = BackupGeneration(id: UUID())
        let directory = backupGenerationURL(generation)
        let files = backupFiles(in: directory)
        // Both files belong to one immutable generation. The canonical store
        // stays directly exportable; only the small pointer is replaced, once
        // every byte of its data and metadata has landed. Until then readers
        // keep the previous generation (or the legacy pair).
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeExport(store, to: files.store)
            try writeData(metaEncoder.encode(meta), files.metadata)
            try writeData(metaEncoder.encode(generation), backupGenerationPointerURL())
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        // Publication succeeded. A crash during retirement can leave old
        // bytes behind, but can never make readers combine two generations.
        if let previous {
            try? FileManager.default.removeItem(at: backupGenerationURL(previous))
        }
        try? FileManager.default.removeItem(at: backupURL())
        try? FileManager.default.removeItem(at: backupMetaURL())
    }

    /// Restore through the same validation and atomic writer, consuming the
    /// recovery generation only after the supported snapshot lands successfully.
    func restoreBackup() throws {
        let files = try currentBackupFiles()
        let bytes = try Data(contentsOf: files.store)
        let store = try JSONDecoder().decode(TrainStore.self, from: bytes)
        _ = try writeStore(upgraded(store))
        discardBackup()
    }

    func discardBackup() {
        try? FileManager.default.removeItem(at: backupGenerationPointerURL())
        try? FileManager.default.removeItem(at: backupGenerationsURL())
        try? FileManager.default.removeItem(at: backupURL())
        try? FileManager.default.removeItem(at: backupMetaURL())
    }

    func removeStore() throws {
        do { try FileManager.default.removeItem(at: storeURL()) }
        catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Deleting an already absent saved copy is complete.
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
        let marker = legacyFoldMarkerURL()
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        guard !FileManager.default.fileExists(atPath: storeURL().path) else {
            try createDirectory()
            FileManager.default.createFile(atPath: marker.path, contents: nil)
            return nil
        }
        var trains: [Train] = []
        var seen = Set<String>()
        for (region, name) in Self.legacyStoreURLs {
            let url = directory().appending(path: name)
            guard let data = try? Data(contentsOf: url),
                  let store = try? JSONDecoder().decode(TrainStore.self, from: data)
            else { continue }
            for train in store.trains {
                try TrainValidation.validateSupportedRegions(train)
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
        let store = TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: trains)
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
        try writeExport(store, to: storeURL())
        FileManager.default.createFile(atPath: marker.path, contents: nil)
        return Date()
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory(), withIntermediateDirectories: true)
    }

    // MARK: - locations

    /// One file, holding every region.
    ///
    /// It used to be one file per region, because the app had a region switch
    /// and "load the Taiwan sample" had to be unambiguous about what it
    /// replaced. With every region drawn at once there is one working set, so
    /// there is one file — and each ride says which region it belongs to
    /// (`Train.region`) rather than being told by which file it was in.
    private func storeURL() -> URL {
        directory().appending(path: "train-store.json")
    }

    /// The per-region files this app wrote before the merge, in the order they
    /// are folded into the merged store.
    private static let legacyStoreURLs: [(Region, String)] = Region.ordered.map {
        ($0, "train-store-\($0.rawValue).json")
    }

    /// The legacy recovery pair, read for installed snapshots until a new
    /// generation has published. Stores remain canonical JSON in both layouts.
    private func backupURL() -> URL {
        directory().appending(path: "train-store.backup.json")
    }

    private func backupMetaURL() -> URL {
        directory().appending(path: "train-store.backup-meta.json")
    }

    private struct BackupGeneration: Codable {
        let id: UUID
    }

    private struct BackupFiles {
        let store: URL
        let metadata: URL
    }

    private func backupGenerationPointerURL() -> URL {
        directory().appending(path: "train-store.backup-current.json")
    }

    private func backupGenerationsURL() -> URL {
        directory().appending(path: "backup-generations", directoryHint: .isDirectory)
    }

    private func backupGenerationURL(_ generation: BackupGeneration) -> URL {
        backupGenerationsURL().appending(path: generation.id.uuidString, directoryHint: .isDirectory)
    }

    private func backupFiles(in directory: URL) -> BackupFiles {
        BackupFiles(store: directory.appending(path: "train-store.json"),
            metadata: directory.appending(path: "metadata.json"))
    }

    private func currentBackupGeneration() throws -> BackupGeneration? {
        let pointer = backupGenerationPointerURL()
        guard FileManager.default.fileExists(atPath: pointer.path) else { return nil }
        return try metaDecoder.decode(BackupGeneration.self, from: Data(contentsOf: pointer))
    }

    private func currentBackupFiles() throws -> BackupFiles {
        if let generation = try currentBackupGeneration() {
            return backupFiles(in: backupGenerationURL(generation))
        }
        // Older installed versions saved this canonical pair. Keep it
        // readable until a new generation is successfully published.
        return BackupFiles(store: backupURL(), metadata: backupMetaURL())
    }

    /// Set once ``foldLegacyStores()`` has run to completion — including the
    /// backfill case where a merged store already existed and there was
    /// nothing to fold — so that deleting the merged store afterwards
    /// (``removeStore()``) can never make a later launch
    /// re-fold the same legacy files back in.
    private func legacyFoldMarkerURL() -> URL {
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

    private func directory() -> URL {
        if let rootDirectory { return rootDirectory }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        return base.appending(path: "Rides", directoryHint: .isDirectory)
    }
}
