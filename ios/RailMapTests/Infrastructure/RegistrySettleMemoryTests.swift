import Foundation
@_spi(Testing) import RailCore
import Testing

@testable import RailMap

/// A stored ride has no station ids until its region settles. The in-memory
/// working set and a save of a stale snapshot both keep the ids after that.
@MainActor
struct RegistrySettleMemoryTests {
    private func bundle() -> RegistryBundle {
        RegistryBundle(
            region: "jp", run: 1,
            stationCodes: ["003700": "st:jp:1"],
            operators: ["op:jp:1": ["JR East", "JR東日本"]])
    }

    private func ride() -> Train {
        Train(
            id: "ride1", number: "1", company: "JR東日本",
            origin: "東京", destination: "品川",
            routeSections: [
                RouteSection(
                    from: "東京", to: "品川",
                    fromN02StationCode: "003700", toN02StationCode: "116021"),
            ],
            stops: [
                Stop(
                    name: "東京", n02StationCode: "003700", departure: "06:00",
                    stopType: "origin", rideSegment: true),
                Stop(name: "品川", arrival: "07:00", stopType: "destination", rideSegment: true),
            ],
            region: "jp")
    }

    @MainActor @Test func settleFillsMemoryAndSaveKeepsStationIDs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "registry-settle-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "registry-settle-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            RegistryIdentityUpgrade.installBundleProvider(nil)
            BundledRegistry.install()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let storage = RideStorage(directory: root)
        let decoded = bundle()
        let identity = RegistryIdentity(bundle: decoded)
        RegistryIdentityUpgrade.installBundleProvider { region in
            region.lowercased() == "jp" ? decoded : nil
        }
        final class PhaseBox: @unchecked Sendable {
            var phase: RegistryPhase = .pending
        }
        let box = PhaseBox()
        let original = ride()
        try await RegistryIdentityLookup.withTestPhase({ _ in box.phase }) {
            _ = try await storage.writeStore(
                TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [original]))
            let before = try await storage.decodeStore()
            #expect(before.trains[0].stops[0].stationID == nil)
            #expect(before.trains[0].operatorID == nil)

            let library = RideLibrary(storage: storage, preferences: defaults)
            let itineraries = ItineraryStore(preferences: defaults)
            itineraries.attach(library)
            itineraries.load(from: library)
            for _ in 0..<100 {
                if case .loaded = itineraries.state { break }
                if case .failed = itineraries.state { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard case .loaded = itineraries.state else {
                Issue.record("load did not finish: \(String(describing: itineraries.state))")
                return
            }
            #expect(itineraries.store?.trains.first?.stops.first?.stationID == nil)

            box.phase = .ready(identity)
            itineraries.applySettledIdentity(region: "jp")
            let memory = try #require(itineraries.store?.trains.first)
            #expect(memory.stops[0].stationID == "st:jp:1")
            #expect(memory.operatorID == "op:jp:1")
            #expect(memory.routeSections?.first?.fromStationID == "st:jp:1")

            let solved = RiddenRouteStore.upgradedSolveTrain(original)
            #expect(solved.stops[0].stationID == "st:jp:1")
            #expect(solved.routeSections?.first?.fromStationID == "st:jp:1")

            _ = try await storage.writeStore(
                TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [original]))
            let after = try await storage.decodeStore()
            #expect(after.trains[0].stops[0].stationID == "st:jp:1")
            #expect(after.trains[0].operatorID == "op:jp:1")
            #expect(after.trains[0].routeSections?.first?.fromStationID == "st:jp:1")
        }
    }

    @Test func replayNeverClaimsAWaitingSolveAndReplaysCompletedOnesOnce() {
        let owner = PendingSolveOwner()
        // Cold launch: the preferred ride's solve waits; another ride already
        // solved without the registry.
        owner.noteAwaiting(id: "preferred", regions: ["jp"])
        owner.noteSolvedUnavailable(id: "batched", regions: ["jp"])
        owner.noteSolvedUnavailable(id: "tw-ride", regions: ["tw"])

        // Settle fires before the waiting solver resumes: it must not be claimed.
        #expect(owner.claimForReplay(region: "jp") == ["batched"])
        #expect(owner.claimForReplay(region: "jp").isEmpty)
        #expect(owner.isAwaiting(id: "preferred"))

        // The solver resumes, solves itself, and leaves nothing to replay.
        owner.finishAwaiting(id: "preferred")
        #expect(!owner.isAwaiting(id: "preferred"))
        #expect(owner.claimForReplay(region: "jp").isEmpty)
        #expect(owner.claimForReplay(region: "tw") == ["tw-ride"])
    }

    @Test func settledRegistrationRemovesItsHandlerWhenReleased() {
        let before = BundledRegistry.settledHandlerCount
        var registration: BundledRegistry.SettledRegistration? = BundledRegistry.SettledRegistration { _ in }
        #expect(BundledRegistry.settledHandlerCount == before + 1)
        registration = nil
        #expect(registration == nil)
        #expect(BundledRegistry.settledHandlerCount == before)
    }

    @Test func saveDoesNotUpgradeAnUnchangedTrainTwice() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("save-upgrade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = RideStorage(directory: root)
        let decoded = bundle()
        let identity = RegistryIdentity(bundle: decoded)
        RegistryIdentityUpgrade.installBundleProvider { region in
            region.lowercased() == "jp" ? decoded : nil
        }
        try await RegistryIdentityLookup.withTestPhase({ _ in .ready(identity) }) {
            let upgraded = await storage.upgradeOnce(ride())
            #expect(upgraded.stops[0].stationID == "st:jp:1")
            let again = await storage.upgradeOnce(upgraded)
            #expect(again == upgraded)
            let url = await storage.storeURL()
            _ = try await storage.writeStore(
                TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [upgraded]))
            let first = try Data(contentsOf: url)
            _ = try await storage.writeStore(
                TrainStore(schemaVersion: TrainValidation.schemaVersion, trains: [upgraded]))
            #expect(try Data(contentsOf: url) == first)
        }
    }
}
