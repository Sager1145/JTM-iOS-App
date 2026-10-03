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
actor RideStorage {

    static let shared = RideStorage()
    private var exportCache = MergedStore.ExportCache()
    private let rootDirectory: URL?

    /// The composition root may provide an isolated store. Production keeps
    /// the historical Application Support location.
    init(directory: URL? = nil) {
        rootDirectory = directory
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
        guard FileManager.default.fileExists(atPath: backupURL().path),
            let data = try? Data(contentsOf: backupMetaURL()),
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
        return store
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
    /// Kept as its own function — rather than folded into every call site —
    /// so that ``writeBackup(_:meta:)`` and this one are the only two places
    /// that call the exporter with the write cache. A verify.sh contract
    /// counts that call's exact spelling; a third writer that lost it
    /// somewhere else is the failure it exists to catch.
    private func writeExport(_ store: TrainStore, to url: URL) throws {
        try Data(MergedStore.export(store, cache: &exportCache).utf8).write(to: url, options: .atomic)
    }

    func writeBackup(_ store: TrainStore, meta: RideLibrary.Backup) throws {
        for train in store.trains { try TrainValidation.validateSupportedRegions(train) }
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
        let staging = backupStagingURL()
        try? FileManager.default.removeItem(at: staging)
        do {
            try Data(MergedStore.export(store, cache: &exportCache).utf8).write(to: staging, options: .atomic)
            if FileManager.default.fileExists(atPath: backupURL().path) {
                _ = try FileManager.default.replaceItemAt(backupURL(), withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: backupURL())
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        try metaEncoder.encode(meta).write(to: backupMetaURL(), options: .atomic)
    }

    /// Restore through the same validation and atomic writer, consuming the
    /// recovery pair only after the supported snapshot lands successfully.
    func restoreBackup() throws {
        let bytes = try Data(contentsOf: backupURL())
        let store = try JSONDecoder().decode(TrainStore.self, from: bytes)
        _ = try writeStore(store)
        discardBackup()
    }

    func discardBackup() {
        try? FileManager.default.removeItem(at: backupURL())
        try? FileManager.default.removeItem(at: backupMetaURL())
    }

    func removeStore() {
        try? FileManager.default.removeItem(at: storeURL())
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

    /// The recovery copy and its sidecar. The sidecar is separate so that the
    /// backup file itself stays byte-identical to an export — a date stamped
    /// inside it would make it a different document from the one it copies.
    private func backupURL() -> URL {
        directory().appending(path: "train-store.backup.json")
    }

    private func backupMetaURL() -> URL {
        directory().appending(path: "train-store.backup-meta.json")
    }

    /// Where ``writeBackup(_:meta:)`` lands the new bytes before swapping
    /// them in for ``backupURL()`` — never read from directly.
    private func backupStagingURL() -> URL {
        directory().appending(path: "train-store.backup.json.staging")
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
