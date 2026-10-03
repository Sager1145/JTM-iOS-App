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

actor RegionCodeIndex {
    static let shared = RegionCodeIndex()
    func tagging(_ trains: [Train]) -> [Train] { trains.map { $0.taggingRegion() } }
}

@main
struct DiskChecks {
    @MainActor
    static func main() async throws {
        let expectedHome = URL(filePath: CommandLine.arguments[1]).standardizedFileURL
        let support = try requireURL(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        precondition(
            support.standardizedFileURL.path.hasPrefix(expectedHome.path),
            "CFFIXED_USER_HOME did not isolate Application Support: \(support.path)")
        let rides = support.appending(path: "Rides", directoryHint: .isDirectory)

        func train(
            _ id: String,
            number: String,
            region: String = "jp",
            vehicle: String? = nil
        ) -> Train {
            var value = Train(
                id: id, date: "2026-09-22", number: number,
                trainType: "express", company: "Test Rail",
                origin: "Alpha", destination: "Beta", direction: "down", visible: true,
                stops: [
                    Stop(name: "Alpha", departure: "09:00", stopType: "origin", rideSegment: true),
                    Stop(name: "Beta", arrival: "10:00", stopType: "destination", rideSegment: true),
                ],
                region: region)
            value.vehicleType = vehicle
            return value
        }

        let isolated = RideStorage(directory: expectedHome.appending(path: "isolated"))
        let isolatedLibrary = RideLibrary(storage: isolated)
        let isolatedSaved = await isolatedLibrary.save(TrainStore(trains: [train("isolated", number: "Only here")])).value
        precondition(isolatedSaved)
        let separate = RideStorage(directory: expectedHome.appending(path: "separate"))
        let separateState = await separate.savedState()
        precondition(!separateState.hasStore)
        let reopened = RideStorage(directory: expectedHome.appending(path: "isolated"))
        let isolatedRead = try await reopened.decodeStore()
        precondition(isolatedRead.trains.map(\.id) == ["isolated"])
        print("PASS injected stores isolate writes and preserve their own relaunch snapshot")

        let legacyDirectory = expectedHome.appending(path: "supported-legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        var legacyTrain = train("shared-legacy-id", number: "Legacy")
        legacyTrain.region = nil
        let legacyBytes = try JSONEncoder().encode(TrainStore(trains: [legacyTrain]))
        for region in ["tw", "hk"] {
            try legacyBytes.write(to: legacyDirectory.appending(path: "train-store-" + region + ".json"))
        }
        let legacyStorage = RideStorage(directory: legacyDirectory)
        let foldedDate = try await legacyStorage.foldLegacyStores()
        precondition(foldedDate != nil)
        let folded = try await legacyStorage.decodeStore()
        precondition(folded.trains.map(\.region) == ["hk", "tw"])
        precondition(Set(folded.trains.map(\.id)).count == 2)
        for region in ["tw", "hk"] {
            try requireBytes(legacyDirectory.appending(path: "train-store-" + region + ".json"), equalTo: legacyBytes)
        }
        await legacyStorage.removeStore()
        let refoldedDate = try await legacyStorage.foldLegacyStores()
        precondition(refoldedDate == nil)
        let afterLegacyDelete = await legacyStorage.savedState()
        precondition(!afterLegacyDelete.hasStore)
        print("PASS supported legacy stores retain duplicate journeys and source bytes; deletion cannot resurrect them")

        let library = RideLibrary()
        var added = train("journey-1", number: "First", vehicle: "EMU-1")
        let addSaved = await library.save(TrainStore(trains: [added])).value
        precondition(addSaved)
        var read = try await RideLibrary().savedStore()
        precondition(read.trains.map(\.id) == ["journey-1"])
        precondition(read.trains[0].number == "First")
        precondition(read.trains[0].vehicleType == "EMU-1")

        added.number = "Replaced"
        added.vehicleType = "EMU-2"
        let replacementSaved = await library.save(TrainStore(trains: [added])).value
        precondition(replacementSaved)
        read = try await RideLibrary().savedStore()
        precondition(read.trains.map(\.id) == ["journey-1"])
        precondition(read.trains[0].number == "Replaced")
        precondition(read.trains[0].vehicleType == "EMU-2")
        print("PASS add and same-identity replace survive a canonical disk round trip")

        var lastTask: Task<Bool, Never>?
        for index in 0..<100 {
            let snapshot = TrainStore(trains: [train("journey-1", number: "Rapid \(index)")])
            lastTask = library.save(snapshot)
        }
        let lastSaved = await lastTask?.value
        precondition(lastSaved == true)
        read = try await RideLibrary().savedStore()
        precondition(read.trains.first?.number == "Rapid 99")
        print("PASS one hundred rapid queued saves leave the newest generation on disk")

        try FileManager.default.removeItem(at: rides)
        try Data("blocks-directory".utf8).write(to: rides)
        let failed = await library.save(TrainStore(trains: [train("failure", number: "Blocked")])).value
        precondition(failed == false)
        precondition(library.lastSaveError != nil)
        try FileManager.default.removeItem(at: rides)
        let recoveredStore = TrainStore(trains: [train("recovered", number: "Recovered")])
        let recoverySaved = await library.save(recoveredStore).value
        precondition(recoverySaved)
        precondition(library.lastSaveError == nil)
        let recoveredRead = try await RideLibrary().savedStore()
        precondition(recoveredRead.trains.map(\.id) == ["recovered"])
        precondition(recoveredRead.trains.first?.number == "Recovered")
        print("PASS a filesystem error is reported and the next valid save recovers")

        let beforeReplace = TrainStore(trains: [train("backup", number: "Before")])
        let beforeReplaceSaved = await library.save(beforeReplace).value
        precondition(beforeReplaceSaved)
        try await library.snapshotBackup(beforeReplace, reason: .beforeReplace)
        let afterReplace = TrainStore(trains: [train("backup", number: "After")])
        let afterReplaceSaved = await library.save(afterReplace).value
        precondition(afterReplaceSaved)
        _ = try await library.restoreBackup()
        let restoredRead = try await RideLibrary().savedStore()
        precondition(restoredRead.trains.map(\.id) == ["backup"])
        precondition(restoredRead.trains.first?.number == "Before")
        precondition(library.backup == nil)
        print("PASS backup restore returns the exact prior snapshot and consumes recovery metadata")

        let supported = TrainStore(trains: ["jp", "tw", "hk", "mo", "kr"].map {
            train("identity-" + $0, number: $0.uppercased(), region: $0)
        })
        let supportedSaved = await library.save(supported).value
        precondition(supportedSaved)
        let supportedRead = try await library.savedStore()
        precondition(supportedRead.trains.map(\.id) == supported.trains.map(\.id))
        precondition(supportedRead.trains.map(\.region) == supported.trains.map(\.region))
        precondition(MergedStore.export(supportedRead) == MergedStore.export(supported))
        let mainURL = rides.appending(path: "train-store.json")
        let beforeRejection = try Data(contentsOf: mainURL)
        try await library.snapshotBackup(supported, reason: .beforeImport)
        let recoveryURL = rides.appending(path: "train-store.backup.json")
        let recoveryMetaURL = rides.appending(path: "train-store.backup-meta.json")
        let beforeBackupRejection = try Data(contentsOf: recoveryURL)
        let beforeMetaRejection = try Data(contentsOf: recoveryMetaURL)
        let legacyNames = ["train-store-na.json", "train-store-us.json", "train-store-ca.json"]
        let oldBytes = Data("legacy bytes must remain untouched".utf8)
        for name in legacyNames { try oldBytes.write(to: rides.appending(path: name)) }
        for region in ["us", "ca"] {
            let rejected = TrainStore(trains: [train("unsupported", number: region, region: region)])
            let rejectedSaved = await library.save(rejected).value
            precondition(rejectedSaved == false)
            precondition(library.lastSaveError != nil)
            try requireBytes(mainURL, equalTo: beforeRejection)
            do {
                try await library.snapshotBackup(rejected, reason: .beforeReplace)
                preconditionFailure("unsupported-region backup must be refused")
            } catch {}
            try requireBytes(recoveryURL, equalTo: beforeBackupRejection)
            try requireBytes(recoveryMetaURL, equalTo: beforeMetaRejection)
        }
        var untagged = train("unsupported-code", number: "Prefix")
        untagged.region = nil
        untagged.stops[0].n02StationCode = "US-EXAMPLE"
        let untaggedSaved = await library.save(TrainStore(trains: [untagged])).value
        precondition(untaggedSaved == false)
        try requireBytes(mainURL, equalTo: beforeRejection)
        print("PASS five supported regions round-trip; unsupported regions and untagged identities cannot overwrite the store")

        // Old snapshots may contain retired regions. Refuse the read/restore
        // without migrating, rewriting or consuming those bytes.
        let retired = TrainStore(trains: [train("retired", number: "Old", region: "ca")])
        let retiredBytes = try JSONEncoder().encode(retired)
        try retiredBytes.write(to: mainURL)
        do {
            _ = try await library.savedStore()
            preconditionFailure("unsupported-region saved store must be refused")
        } catch {}
        try requireBytes(mainURL, equalTo: retiredBytes)
        try retiredBytes.write(to: recoveryURL)
        do {
            _ = try await library.restoreBackup()
            preconditionFailure("unsupported-region recovery must be refused")
        } catch {}
        try requireBytes(recoveryURL, equalTo: retiredBytes)
        try requireBytes(recoveryMetaURL, equalTo: beforeMetaRejection)
        precondition(library.backup != nil)
        try requireBytes(mainURL, equalTo: retiredBytes)
        library.deleteSavedStore()
        await library.migrateLegacyStores()
        await library.refreshSavedState()
        precondition(library.hasSavedStore == false)
        for name in legacyNames {
            try requireBytes(rides.appending(path: name), equalTo: oldBytes)
        }
        print("PASS retired disk snapshots are refused; save, restore, delete and legacy folding leave old separate files untouched")

    }
}

private func requireURL(_ value: URL?) throws -> URL {
    guard let value else { throw CocoaError(.fileNoSuchFile) }
    return value
}

private func requireBytes(_ url: URL, equalTo expected: Data) throws {
    let actual = try Data(contentsOf: url)
    precondition(actual == expected)
}
