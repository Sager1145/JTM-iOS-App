import Foundation
import RailCore

enum Region: String, Sendable {
    case jp, tw, hk, mo, kr, us, ca

    var code: String { rawValue }
    nonisolated static var northAmericaEnabled: Bool { false }

    static func resolved(_ train: Train) -> Region {
        Region(rawValue: train.region ?? "jp") ?? .jp
    }

    static func isNorthAmerica(_ train: Train) -> Bool {
        resolved(train) == .us || resolved(train) == .ca
    }
}

extension Train {
    func taggingRegion() -> Train {
        var next = self
        next.region = Region.resolved(self).code
        return next
    }
}

struct JourneyDay: Sendable {
    var date = ""
    var trains: [Train] = []
}

enum MergedStore {
    static func tagged(_ store: TrainStore) -> TrainStore {
        var next = store
        next.trains = next.trains.map { $0.taggingRegion() }
        return next
    }
}

@MainActor
final class RideStatusCenter {
    static let shared = RideStatusCenter()
    func publish(trainIDs: Set<String>) {}
    func resolveAgain(_ train: Train) -> Bool { false }
}

@MainActor
final class RideLibrary {
    private(set) var snapshots: [TrainStore] = []
    private(set) var lastSaveError: String? = "prior write failed"

    @discardableResult
    func save(_ store: TrainStore) -> Task<Bool, Never> {
        snapshots.append(store)
        lastSaveError = nil
        return Task { true }
    }

    func recordPriorError() {
        lastSaveError = "prior write failed"
    }
}

@main
struct EditorChecks {
    @MainActor
    static func main() async throws {
        func train(_ id: String, number: String, vehicle: String? = nil) -> Train {
            var value = Train(
                id: id, date: "2026-09-22", number: number,
                origin: "Alpha", destination: "Beta", stops: [], region: "jp")
            value.vehicleType = vehicle
            return value
        }

        let library = RideLibrary()
        let itineraries = ItineraryStore(testStore: TrainStore())
        let editing = JourneyEditing(itineraries: itineraries, library: library)

        let created = train("created", number: "Create", vehicle: "EMU-A")
        precondition(editing.add(created) == "created")
        precondition(itineraries.selectedTrainID == "created")
        precondition(library.snapshots.last?.trains == [created.taggingRegion()])

        var replacement = created
        replacement.number = "Edited"
        replacement.vehicleType = "EMU-B"
        precondition(editing.replace(replacement, replacing: "created") == .saved)
        precondition(library.snapshots.last?.trains.first?.id == "created")
        precondition(library.snapshots.last?.trains.first?.vehicleType == "EMU-B")
        print("PASS JourneyEditing saves complete add and replace snapshots with stable identity")

        let other = train("other", number: "Other")
        precondition(editing.add(other) == "other")
        var colliding = replacement
        colliding.id = "other"
        let collision = editing.replace(colliding, replacing: "created")
        precondition(collision == .savedKeepingID(keptID: "created", requestedID: "other"))
        precondition(Set(library.snapshots.last?.trains.map(\.id) ?? []) == ["created", "other"])
        print("PASS an edited ID collision preserves both journey identities on save")

        let beforeRefusals = library.snapshots.count
        library.recordPriorError()
        let missing = editing.replace(train("missing", number: "Missing"), replacing: "absent")
        precondition(missing == .notFound)
        precondition(library.snapshots.count == beforeRefusals)

        itineraries.setImportingForTest(true)
        let refused = editing.replace(replacement, replacing: "created")
        precondition(refused == .refusedImportRunning)
        precondition(library.snapshots.count == beforeRefusals)
        precondition(library.lastSaveError == "prior write failed")
        print("PASS not-found and import-owned replacements do not enqueue an unchanged save or clear an error")
    }
}
