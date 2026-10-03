import Foundation
import Testing

@testable import RailCore

/// Generated workloads use shipped station identities, route sections and dates.
/// Increase JTM_STRESS_TRAIN_COUNT for local load runs; timing is reported, never
/// asserted against a machine-dependent deadline.
@Suite("Large generated journey stores", .serialized)
struct RouteStoreStressTests {
    private static var count: Int {
        max(2_100, Int(ProcessInfo.processInfo.environment["JTM_STRESS_TRAIN_COUNT"] ?? "") ?? 2_100)
    }

    private static func generatedTrains(count: Int) throws -> [Train] {
        let root = try PortFixtures.repositoryRoot()
        let seeds = try PortFixtures.countries.map { country in
            let suffix = country == "jp" ? "" : "-\(country)"
            let data = try Data(contentsOf: root.appending(path: "app/data/train-store\(suffix).json"))
            let trains = try JSONDecoder().decode(TrainStore.self, from: data).trains
            try #require(!trains.isEmpty)
            return (country, trains)
        }
        return (0..<count).map { index in
            let (country, rows) = seeds[index % seeds.count]
            var train = rows[(index / seeds.count) % rows.count]
            train.id = "stress_\(country)_\(index)"
            train.region = country
            return train
        }
    }

    private static func document(_ trains: [Train]) -> TrainValidation.JSON {
        StoreOperations.json(TrainStore(trains: trains))
    }

    private static func report(_ label: String, count: Int, since start: Date) {
        print("STRESS \(label): \(count) journeys, \(String(format: "%.3f", Date().timeIntervalSince(start))) s")
    }

    @Test("Thousands of mixed-region journeys import, export, and reopen without data loss")
    func largeMixedRegionJSONRoundTrip() throws {
        let generated: [Train]
        if let path = ProcessInfo.processInfo.environment["JTM_STRESS_STORE_PATH"] {
            generated = try JSONDecoder().decode(
                TrainStore.self, from: Data(contentsOf: URL(filePath: path))).trains
            try #require(generated.count >= 2_100)
        } else {
            generated = try Self.generatedTrains(count: Self.count)
        }
        let text = StoreOperations.stringify(Self.document(generated))
        var warmIDs: [String] = []
        var drawIDs: [String] = []
        var listIDs: [String] = []
        var renders = 0
        var persists = 0
        var finishes = 0
        var latestProgress = 0
        var progressIsMonotonic = true
        var session = ImportEngine.Session(country: "jp") { event in
            switch event {
            case .warmRoute(let id): warmIDs.append(id)
            case .drawTrain(let id): drawIDs.append(id)
            case .appendListItem(let id): listIDs.append(id)
            case .render: renders += 1
            case .persist: persists += 1
            case .finished: finishes += 1
            case .progressBar(let count, let total, _):
                progressIsMonotonic = progressIsMonotonic && count >= latestProgress && total == generated.count
                latestProgress = count
            case .status: break
            }
        }
        let start = Date()
        try session.replaceTrainStoreFromJSONText(text)
        Self.report("mixed-region JSON import", count: generated.count, since: start)

        let ids = generated.map(\.id)
        #expect(session.trains.count == generated.count)
        #expect(session.trains.map(\.id) == ids)
        #expect(Set(session.trains.compactMap(\.region)) == Set(PortFixtures.countries))
        #expect(Set(session.trains.compactMap(\.date)).count > 20)
        #expect(Set(session.trains.map { "\($0.region ?? ""):\($0.origin):\($0.destination)" }).count > 100)
        #expect(warmIDs == ids)
        #expect(drawIDs == ids)
        #expect(listIDs == ids)
        #expect(renders == 2)
        #expect(persists == 2)
        #expect(finishes == 1)
        #expect(progressIsMonotonic && latestProgress == generated.count)
        #expect(!session.importInProgress)
        #expect(session.selectedTrainID == ids.first)

        let workspace = StoreOperations.Workspace(store: TrainStore(trains: session.trains))
        let exportStart = Date()
        let exported = StoreOperations.exportTrainStore(workspace)
        #expect(try TrainValidation.validateTrainStore(TrainValidation.JSON.parse(exported)))
        var restored = ImportEngine.Session(country: "jp")
        try restored.replaceTrainStoreFromJSONText(exported)
        let reexported = StoreOperations.exportTrainStore(
            .init(store: TrainStore(trains: restored.trains)))
        #expect(reexported == exported, "The canonical archive must reach a stable round trip")
        #expect(restored.trains.map(\.region) == session.trains.map(\.region))
        #expect(restored.trains.map(\.date) == session.trains.map(\.date))
        let native = try JSONEncoder().encode(TrainStore(trains: restored.trains))
        #expect(try JSONDecoder().decode(TrainStore.self, from: native).trains == restored.trains)
        Self.report("canonical export, validate and reopen", count: generated.count, since: exportStart)
    }

    @Test("Ten thousand rapid additions sharing a base ID keep contiguous collision suffixes")
    func rapidRepeatedIDAppend() throws {
        let count = max(10_000, Self.count)
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.id = "stress_collision"
        train.number = "Stress local"
        train.date = "2026-08-10"
        let raw = StoreOperations.json(train)
        var session = ImportEngine.Session(country: "jp")
        let start = Date()
        for index in 0..<count {
            let id = try session.appendImportedTrain(raw)
            let expected = index == 0 ? train.id : "\(train.id)-\(index + 1)"
            #expect(id == expected)
        }
        #expect(session.trains.count == count)
        #expect(Set(session.trains.map(\.id)).count == count)
        #expect(session.trains.allSatisfy { $0.stops == session.trains[0].stops })
        #expect(try TrainValidation.validateTrainStore(Self.document(session.trains)))
        Self.report("repeated-ID append", count: count, since: start)
    }

    @Test("An external same-count replacement invalidates cached identities at scale")
    func externalReplacementAndFailedRowDoNotPoisonIDs() throws {
        var session = ImportEngine.Session(trains: try Self.generatedTrains(count: Self.count))
        var incoming = session.trains[0]
        incoming.id = "external_collision"
        #expect(try session.appendImportedTrain(StoreOperations.json(incoming)) == incoming.id)

        // Keep the count fixed, remove the cached ID, and introduce another.
        var replacement = session.trains
        replacement[replacement.count - 1].id = "externally_replaced"
        session.trains = replacement
        #expect(try session.appendImportedTrain(StoreOperations.json(incoming)) == incoming.id)
        incoming.id = "externally_replaced"
        #expect(try session.appendImportedTrain(StoreOperations.json(incoming)) == "externally_replaced-2")

        var invalid = incoming
        invalid.id = "failed_candidate"
        invalid.stops[0].name = ""
        let baseline = session.trains
        #expect(throws: TrainValidation.ValidationError.self) {
            try session.appendImportedTrain(StoreOperations.json(invalid))
        }
        #expect(session.trains == baseline)
        incoming.id = invalid.id
        #expect(try session.appendImportedTrain(StoreOperations.json(incoming)) == invalid.id)
    }

    @Test("A late invalid row rolls back a large append, and retry reuses every original ID")
    func lateFailureRollsBackAndRetryIsClean() throws {
        let existing = try Self.generatedTrains(count: Self.count)
        var session = ImportEngine.Session(
            trains: existing, selectedTrainID: existing[0].id,
            focusedTrainID: existing.last?.id, selectedDate: Dates.allDates)
        var incoming = Array(existing.prefix(512))
        for index in incoming.indices { incoming[index].id = "rollback_\(index)" }
        var invalid = incoming[0]
        invalid.id = "late_invalid"
        invalid.stops[0].name = ""
        #expect(throws: TrainValidation.ValidationError.self) {
            try session.importCanonicalStoreAppendProgressive(Self.document(incoming + [invalid]))
        }
        #expect(session.trains == existing)
        #expect(session.selectedTrainID == existing[0].id)
        #expect(session.focusedTrainID == existing.last?.id)
        #expect(!session.importInProgress)
        let result = try session.importCanonicalStoreAppendProgressive(Self.document(incoming))
        #expect(result.ids == incoming.map(\.id))
        #expect(session.trains.count == existing.count + incoming.count)
        #expect(Set(session.trains.map(\.id)).count == session.trains.count)
    }

    @Test("Removing a suffix, rejecting a collision, and copying a session preserve allocation")
    func suffixHolesFailuresAndSessionCopies() throws {
        var train = StoreOperations.createBlankTrain(country: "jp")
        train.id = "suffix_hole"
        train.number = "Stress local"
        train.date = "2026-08-10"
        let raw = StoreOperations.json(train)
        var original = ImportEngine.Session()
        for _ in 0..<1_024 { try original.appendImportedTrain(raw) }

        original.trains.removeAll { $0.id == "suffix_hole-512" }
        #expect(try original.appendImportedTrain(raw) == "suffix_hole-512")
        var invalid = train
        invalid.stops[0].name = ""
        #expect(throws: TrainValidation.ValidationError.self) {
            try original.appendImportedTrain(StoreOperations.json(invalid))
        }
        #expect(try original.appendImportedTrain(raw) == "suffix_hole-1025")

        // Value-type copies must allocate independently even with warm caches.
        var copied = original
        #expect(try original.appendImportedTrain(raw) == "suffix_hole-1026")
        #expect(try copied.appendImportedTrain(raw) == "suffix_hole-1026")
        #expect(try original.appendImportedTrain(raw) == "suffix_hole-1027")
        #expect(copied.trains.count + 1 == original.trains.count)
        #expect(Set(original.trains.map(\.id)).count == original.trains.count)
        #expect(Set(copied.trains.map(\.id)).count == copied.trains.count)
    }
}
