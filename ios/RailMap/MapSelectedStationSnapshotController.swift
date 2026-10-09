import Foundation

@concurrent
private func loadSelectedStationSnapshot(_ country: String) async -> MapRideStationImportance.Snapshot {
    await MapRideStationImportance.shared.snapshot(for: country)
}

/// Owns selected-journey station lookup work and its map-lifetime snapshots.
/// Selection, camera intents and annotation refresh remain with the map owner.
@MainActor
final class MapSelectedStationSnapshotController {
    typealias Loader = @Sendable (String) async -> MapRideStationImportance.Snapshot

    private let load: Loader
    private var snapshots: [String: MapRideStationImportance.Snapshot] = [:]
    private var task: Task<Void, Never>?
    private var countryInFlight: String?
    private var ticket = UUID()

    init(load: @escaping Loader = loadSelectedStationSnapshot) {
        self.load = load
    }

    func snapshot(for country: String) -> MapRideStationImportance.Snapshot? {
        snapshots[country]
    }

    func prepare(
        country: String?,
        isCurrentMount: @escaping @MainActor () -> Bool,
        didLoad: @escaping @MainActor () -> Void
    ) {
        guard let country else {
            cancel()
            return
        }
        // Preserve cached-country behavior even if a different lookup is
        // already in flight. Its completion refreshes the live selection.
        guard snapshots[country] == nil, countryInFlight != country else { return }
        cancel()
        countryInFlight = country
        let requestTicket = ticket
        let load = self.load
        task = Task { @MainActor [weak self] in
            let snapshot = await load(country)
            guard !Task.isCancelled, let self, self.ticket == requestTicket,
                  isCurrentMount() else { return }
            self.task = nil
            self.countryInFlight = nil
            self.snapshots[country] = snapshot
            didLoad()
        }
    }

    private func cancel() {
        ticket = UUID()
        task?.cancel()
        task = nil
        countryInFlight = nil
    }

    func tearDown() {
        cancel()
        snapshots.removeAll()
    }
}
