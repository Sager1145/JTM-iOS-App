#!/usr/bin/env python3
"""Exercise the actual RideLibrary queue against a recording storage actor.

Usage: DEVELOPER_DIR=... python3 ios/tools/verify-store-ordering.py <SPM scratch>
The storage double records ordering and failures without touching user files.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
scratch = Path(sys.argv[1])
libs = list(scratch.rglob('libRailCore.a'))
if not libs:
    raise SystemExit('Build RailKit in the supplied scratch directory first.')
products = libs[0].parent
source = (root / 'ios/RailMap/RideLibrary.swift').read_text().split('actor RideStorage {')[0]
exporter = (root / 'ios/RailMap/MergedStore.swift').read_text().split('    /// Every train with its region')[0] + '}\n'
source += exporter
# Compile the production queue unchanged. Only its filesystem collaborator and
# the region catalog used by sample labels are replaced in this host harness.
harness = r'''
import Foundation
import RailCore

enum Region: String, Sendable {
    case jp, tw, hk, mo, kr, us, ca
    var code: String { rawValue }
    static func resolved(_ train: Train) -> Region { Region(rawValue: train.region ?? "jp") ?? .jp }
}
extension Train {
    func taggingRegion() -> Train { var next = self; next.region = Region.resolved(self).code; return next }
}
actor RideStorage {
    static let shared = RideStorage()
    struct SavedState: Sendable {
        var hasStore: Bool
        var storeDate: Date?
        var backup: RideLibrary.Backup?
    }
    var events: [String] = []
    var store: TrainStore?
    var recovery: TrainStore?
    var meta: RideLibrary.Backup?
    var failing = false
    var hold = false
    var entered = false
    var release: CheckedContinuation<Void, Never>?
    func reset() { events = []; store = nil; recovery = nil; meta = nil; failing = false; entered = false }
    func failNext() { failing = true }
    func holdNext() { hold = true; entered = false }
    func unblock() { release?.resume(); release = nil }
    func isEntered() -> Bool { entered }
    func recorded() -> [String] { events }
    func decodeSample(_ name: String) throws -> TrainStore { TrainStore() }
    func decodeStore() throws -> TrainStore { events.append("read"); return store ?? TrainStore() }
    func savedState() -> SavedState { .init(hasStore: store != nil, storeDate: nil, backup: meta) }
    func writeStore(_ next: TrainStore) async throws -> Date {
        events.append("save:" + next.trains[0].id)
        if hold { hold = false; entered = true; await withCheckedContinuation { release = $0 } }
        if failing { failing = false; throw CocoaError(.fileWriteUnknown) }
        store = next
        return Date()
    }
    func writeBackup(_ next: TrainStore, meta: RideLibrary.Backup) throws {
        events.append("backup:" + next.trains[0].id); recovery = next; self.meta = meta
    }
    func restoreBackup() throws { events.append("restore"); store = recovery; recovery = nil; meta = nil }
    func discardBackup() { events.append("discard"); recovery = nil; meta = nil }
    func removeStore() { events.append("delete"); store = nil }
    func foldLegacyStores() throws -> Date? { nil }
}

@main struct Checks {
    @MainActor static func main() async throws {
        func store(_ id: String) -> TrainStore {
            TrainStore(trains: [Train(id: id, number: id, origin: "A", destination: "B", stops: [])])
        }
        let storage = RideStorage.shared
        let library = RideLibrary()
        let a = store("A"), b = store("B"), c = store("C")
        let first = library.save(a)
        let second = library.save(b)
        precondition(first == second, "queued callers must await the same durable write")
        await second.value
        precondition(await storage.recorded() == ["save:B"])
        print("PASS consecutive unstarted saves serialize only their latest snapshot")

        await storage.reset()
        library.save(a)
        library.snapshotBackup(a, reason: .beforeImport)
        let committed = library.save(b)
        await committed.value
        precondition(await storage.recorded() == ["save:A", "backup:A", "save:B"])
        _ = try await library.restoreBackup()
        let restored = try await library.savedStore()
        precondition(restored == a && library.backup == nil)
        print("PASS backup/import/restore preserve the pre-import snapshot and operation order")

        await storage.reset()
        let beforeDelete = library.save(a)
        library.deleteSavedStore()
        await beforeDelete.value
        precondition(!library.hasSavedStore, "late save completion cannot undo deletion UI")
        let afterDelete = library.save(c)
        await afterDelete.value
        precondition(await storage.recorded() == ["save:A", "delete", "save:C"])
        precondition(try await library.savedStore() == c)
        print("PASS delete is a barrier and older save completion cannot resurrect saved state")

        await storage.reset()
        await storage.holdNext()
        let started = library.save(a)
        while !(await storage.isEntered()) { await Task.yield() }
        let next = library.save(b)
        let latest = library.save(c)
        precondition(started != next && next == latest)
        await storage.unblock()
        await latest.value
        precondition(await storage.recorded() == ["save:A", "save:C"])
        print("PASS a write already in progress retains its immutable snapshot")

        await storage.reset()
        await storage.failNext()
        library.save(a)
        library.snapshotBackup(a, reason: .beforeReplace)
        await library.save(b).value
        precondition(try await library.savedStore() == b)
        print("PASS write failure does not cancel queued backup or subsequent save")

        var exportCache = MergedStore.ExportCache()
        func sameBytes(_ left: String, _ right: String) -> Bool { left.utf8.elementsEqual(right.utf8) }
        let repository = URL(filePath: CommandLine.arguments[1])
        for country in ["jp", "tw", "hk", "mo", "kr"] {
            let suffix = country == "jp" ? "" : "-" + country
            let bytes = try Data(contentsOf: repository.appending(path: "app/data/train-store" + suffix + ".json"))
            var sample = try JSONDecoder().decode(TrainStore.self, from: bytes)
            for i in sample.trains.indices { sample.trains[i].region = country }
            precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
            precondition(sameBytes(exportCache.export(sample), MergedStore.export(sample)))
            precondition(exportCache.encodedTrainCount == 0)
            if !sample.trains.isEmpty {
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
        print("PASS cached export is byte-identical for five real samples, edits, escapes, reordering, deletion, restoration and empty stores")
    }
}
'''
# Swift precondition uses synchronous autoclosures; await outside each assertion.
counter = 0
lines = []
for line in harness.splitlines():
    if 'precondition(await ' in line or 'precondition(try await ' in line:
        counter += 1
        indent = line[:len(line) - len(line.lstrip())]
        expression = line.strip()[len('precondition('):-1]
        lines += [f'{indent}let assertion{counter} = {expression}', f'{indent}precondition(assertion{counter})']
    else:
        lines.append(line)
with tempfile.TemporaryDirectory(prefix='jtm-store-ordering-') as temporary:
    folder = Path(temporary)
    queue = folder / 'RideLibrary.swift'
    checks = folder / 'Checks.swift'
    queue.write_text(source)
    checks.write_text('\n'.join(lines))
    executable = folder / 'checks'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-sdk', sdk, '-I', str(products), str(queue), str(checks),
                    str(libs[0]), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(root)], check=True)
