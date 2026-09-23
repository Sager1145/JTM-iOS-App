import Foundation
import RailCore

enum Region: String, CaseIterable, Sendable {
    case jp, tw, hk, mo, kr, us, ca

    var code: String { rawValue }
    var isNorthAmerica: Bool { self == .us || self == .ca }
    static let ordered: [Region] = [.mo, .hk, .tw, .kr, .ca, .jp, .us]
    static let northAmericaDefaultsKey = "feature-north-america-enabled"
    nonisolated static var northAmericaEnabled: Bool {
        UserDefaults.standard.bool(forKey: northAmericaDefaultsKey)
    }

    static func resolved(_ train: Train) -> Region {
        Region(rawValue: train.region ?? "jp") ?? .jp
    }

    static func isNorthAmerica(_ train: Train) -> Bool {
        resolved(train).isNorthAmerica
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

        let library = RideLibrary()
        var added = train("journey-1", number: "First", vehicle: "EMU-1")
        let addSaved = await library.save(TrainStore(trains: [added])).value
        precondition(addSaved)
        var read = try await RideLibrary().savedStore().store
        precondition(read.trains.map(\.id) == ["journey-1"])
        precondition(read.trains[0].number == "First")
        precondition(read.trains[0].vehicleType == "EMU-1")

        added.number = "Replaced"
        added.vehicleType = "EMU-2"
        let replacementSaved = await library.save(TrainStore(trains: [added])).value
        precondition(replacementSaved)
        read = try await RideLibrary().savedStore().store
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
        read = try await RideLibrary().savedStore().store
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
        let recoveredRead = try await RideLibrary().savedStore().store
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
        let restoredRead = try await RideLibrary().savedStore().store
        precondition(restoredRead.trains.map(\.id) == ["backup"])
        precondition(restoredRead.trains.first?.number == "Before")
        precondition(library.backup == nil)
        print("PASS backup restore returns the exact prior snapshot and consumes recovery metadata")

        UserDefaults.standard.set(true, forKey: Region.northAmericaDefaultsKey)
        library.northAmericaInWorkingSet = true
        let japan = train("jp-identity", number: "JP", region: "jp")
        let america = train("us-identity", number: "US", region: "us")
        let partitionSaved = await library.save(TrainStore(trains: [japan, america])).value
        precondition(partitionSaved)
        read = try await library.savedStore().store
        precondition(read.trains.map(\.id) == ["jp-identity", "us-identity"])

        UserDefaults.standard.set(false, forKey: Region.northAmericaDefaultsKey)
        let mainOnly = try await library.savedStore()
        precondition(mainOnly.store.trains.map(\.id) == ["jp-identity"])
        precondition(mainOnly.includedNorthAmerica == false)
        let northAmerica = try await library.northAmericaStore()
        precondition(northAmerica.trains.map(\.id) == ["us-identity"])
        print("PASS regional partitioning preserves identities while North America is hidden")

        UserDefaults.standard.removeObject(forKey: Region.northAmericaDefaultsKey)
    }
}

private func requireURL(_ value: URL?) throws -> URL {
    guard let value else { throw CocoaError(.fileNoSuchFile) }
    return value
}
