import Foundation
import RailCore

enum Region: String, CaseIterable, Sendable {
    case jp, tw, hk, mo, kr

    var code: String { rawValue }
    static let ordered: [Region] = [.mo, .hk, .tw, .kr, .jp]

    static func resolved(_ train: Train) -> Region {
        Region(rawValue: train.region ?? "jp") ?? .jp
    }


}

extension Train {
    func taggingRegion() -> Train {
        var next = self
        next.region = Region.resolved(self).code
        return next
    }
}

/// A controllable collaborator for the production RideLibrary queue.
///
/// This deliberately has the same surface as RideStorage. The Python driver
/// compiles the unmodified RideLibrary definition above it, then substitutes
/// this actor for the filesystem implementation below it.
actor RideStorage {
    static let shared = RideStorage()

    struct SavedState: Sendable {
        var hasStore: Bool
        var storeDate: Date?
        var backup: RideLibrary.Backup?
    }

    private var events: [String] = []
    private var store: TrainStore?
    private var recovery: TrainStore?
    private var meta: RideLibrary.Backup?
    private var failing = false
    private var hold = false
    private var entered = false
    private var release: CheckedContinuation<Void, Never>?

    func reset() {
        events = []
        store = nil
        recovery = nil
        meta = nil
        failing = false
        hold = false
        entered = false
        release = nil
    }

    func failNext() { failing = true }
    func holdNext() { hold = true; entered = false }
    func unblock() { release?.resume(); release = nil }
    func isEntered() -> Bool { entered }
    func recorded() -> [String] { events }

    func decodeSample(_ name: String) throws -> TrainStore { TrainStore() }

    func decodeStore() throws -> TrainStore {
        events.append("read")
        return store ?? TrainStore()
    }

    func savedState() -> SavedState {
        .init(hasStore: store != nil, storeDate: nil, backup: meta)
    }

    func recoverableBackup() -> RideLibrary.Backup? { meta }

    func writeStore(_ next: TrainStore) async throws -> Date {
        events.append("save:\(next.trains.first?.id ?? "empty")")
        if hold {
            hold = false
            entered = true
            await withCheckedContinuation { release = $0 }
        }
        if failing {
            failing = false
            throw CocoaError(.fileWriteUnknown)
        }
        store = next
        return Date()
    }

    func writeBackup(_ next: TrainStore, meta: RideLibrary.Backup) throws {
        events.append("backup:\(next.trains.first?.id ?? "empty")")
        recovery = next
        self.meta = meta
    }

    func restoreBackup() throws {
        events.append("restore")
        store = recovery
        recovery = nil
        meta = nil
    }

    func discardBackup() {
        events.append("discard")
        recovery = nil
        meta = nil
    }

    func removeStore() {
        events.append("delete")
        store = nil
    }

    func foldLegacyStores() throws -> Date? { nil }
}

@main
struct QueueChecks {
    @MainActor
    static func main() async throws {
        func store(_ id: String) -> TrainStore {
            TrainStore(trains: [
                Train(id: id, number: id, origin: "A", destination: "B", stops: [])
            ])
        }

        let storage = RideStorage()
        let library = RideLibrary(storage: storage)
        let a = store("A")
        let b = store("B")
        let c = store("C")

        let first = library.save(a)
        let second = library.save(b)
        precondition(first == second, "unstarted saves must share one durable write")
        let secondSaved = await second.value
        let coalescedEvents = await storage.recorded()
        precondition(secondSaved)
        precondition(coalescedEvents == ["save:B"])
        print("PASS queue coalesces consecutive unstarted saves to their latest snapshot")

        await storage.reset()
        _ = library.save(a)
        try await library.snapshotBackup(a, reason: .beforeImport)
        let laterSaved = await library.save(b).value
        let backupEvents = await storage.recorded()
        precondition(laterSaved)
        precondition(backupEvents == [
            "save:A", "backup:A", "save:B",
        ])
        _ = try await library.restoreBackup()
        let restored = try await library.savedStore()
        precondition(restored == a && library.backup == nil)
        print("PASS backup, later save, and restore preserve queue order and the prior snapshot")

        await storage.reset()
        let beforeDelete = library.save(a)
        library.deleteSavedStore()
        _ = await beforeDelete.value
        precondition(library.hasSavedStore == false, "late completion cannot undo deletion state")
        let afterDeleteSaved = await library.save(c).value
        let deletionEvents = await storage.recorded()
        precondition(afterDeleteSaved)
        precondition(deletionEvents == [
            "save:A", "delete", "save:C",
        ])
        let afterDeleteRead = try await library.savedStore()
        precondition(afterDeleteRead == c)
        print("PASS deletion is a queue barrier and stale completion cannot resurrect its state")

        await storage.reset()
        await storage.holdNext()
        let started = library.save(a)
        while await storage.isEntered() == false { await Task.yield() }
        let queued = library.save(b)
        let latest = library.save(c)
        precondition(started != queued && queued == latest)
        await storage.unblock()
        let latestSaved = await latest.value
        let inFlightEvents = await storage.recorded()
        precondition(latestSaved)
        precondition(inFlightEvents == ["save:A", "save:C"])
        print("PASS a started write keeps its snapshot while the following batch coalesces")

        await storage.reset()
        await storage.failNext()
        let failed = library.save(a)
        try await library.snapshotBackup(a, reason: .beforeReplace)
        let recovered = library.save(b)
        let failedResult = await failed.value
        let recoveredResult = await recovered.value
        let recoveredRead = try await library.savedStore()
        precondition(failedResult == false)
        precondition(recoveredResult)
        precondition(recoveredRead == b)
        precondition(library.lastSaveError == nil)
        print("PASS a failed write does not cancel queued recovery work or a later successful save")

        await storage.reset()
        let acceptedBefore = library.save(a)
        var retired = b
        retired.trains[0].region = "us"
        let rejected = library.save(retired)
        let acceptedAfter = library.save(c)
        let beforeResult = await acceptedBefore.value
        let rejectedResult = await rejected.value
        let afterResult = await acceptedAfter.value
        let rejectionEvents = await storage.recorded()
        precondition(beforeResult && !rejectedResult && afterResult)
        precondition(rejectionEvents == ["save:A", "save:C"])
        precondition(library.lastSaveError == nil)
        print("PASS unsupported saves are refused without poisoning either accepted snapshot or queue recovery")

        var exportCache = MergedStore.ExportCache()
        func sameBytes(_ left: String, _ right: String) -> Bool {
            left.utf8.elementsEqual(right.utf8)
        }
        let repository = URL(filePath: CommandLine.arguments[1])
        for country in ["jp", "tw", "hk", "mo", "kr"] {
            let suffix = country == "jp" ? "" : "-" + country
            let bytes = try Data(
                contentsOf: repository.appending(path: "app/data/train-store" + suffix + ".json"))
            var sample = try JSONDecoder().decode(TrainStore.self, from: bytes)
            for index in sample.trains.indices { sample.trains[index].region = country }
            precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
            precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
            precondition(exportCache.encodedTrainCount == 0)
            if sample.trains.isEmpty == false {
                sample.trains[0].number = "Unicode 駅 \"quoted\"\nservice"
                precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
                precondition(exportCache.encodedTrainCount == 1)
                sample.trains.reverse()
                precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
                precondition(exportCache.encodedTrainCount == 0)
                let removed = sample.trains.removeLast()
                precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
                precondition(exportCache.encodedTrainCount == 0)
                sample.trains.append(removed)
                precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
                precondition(exportCache.encodedTrainCount == 1)
            }
        }
        var unicode = a
        unicode.trains[0].number = "\u{00e9}"
        _ = exportCache.export(unicode)
        unicode.trains[0].number = "e\u{0301}"
        precondition(sameBytes(exportCache.export(unicode), MergedStore.export(unicode)))
        precondition(exportCache.encodedTrainCount == 1)
        precondition(sameBytes(exportCache.export(TrainStore()), MergedStore.export(TrainStore())))
        print("PASS cached export is byte-identical for five samples, Unicode, reorder, removal, restoration, and empty stores")
    }
}
