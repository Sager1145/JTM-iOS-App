import Foundation

@concurrent
private func loadSelectedStationSnapshot(_ country: String) async throws -> MapRideStationImportance.Snapshot {
    try await MapRideStationImportance.shared.snapshot(for: country)
}

/// Owns selected-journey station lookup work and its map-lifetime snapshots.
/// Selection, camera intents and annotation refresh remain with the map owner.
@MainActor
final class MapSelectedStationSnapshotController {
    private var snapshots: [String: MapRideStationImportance.Snapshot] = [:]
    private var task: Task<Void, Never>?
    private var countryInFlight: String?
    private var ticket = UUID()
    private var selectedCountry: String?
    private var hasPrepared = false
    private(set) var failureMessage: String?

    func snapshot(for country: String) -> MapRideStationImportance.Snapshot? {
        snapshots[country]
    }

    func prepare(
        country: String?,
        isCurrentMount: @escaping @MainActor () -> Bool,
        onFailureChange: @escaping @MainActor (String?) -> Void,
        didLoad: @escaping @MainActor () -> Void
    ) {
        if !hasPrepared || selectedCountry != country {
            cancel()
            hasPrepared = true
            selectedCountry = country
            failureMessage = nil
            onFailureChange(nil)
        }
        guard let country else {
            cancel()
            return
        }
        // Preserve cached-country behavior even if a different lookup is
        // already in flight. Its completion refreshes the live selection.
        // A failed selection is reported once. Selecting another country and
        // returning may try again; map frames do not retry the same bad file.
        guard snapshots[country] == nil, countryInFlight != country, failureMessage == nil else { return }
        cancel()
        countryInFlight = country
        let requestTicket = ticket
        task = Task { @MainActor [weak self] in
            do {
                let snapshot = try await loadSelectedStationSnapshot(country)
                guard !Task.isCancelled, let self, self.ticket == requestTicket,
                      isCurrentMount() else { return }
                self.task = nil
                self.countryInFlight = nil
                self.snapshots[country] = snapshot
                didLoad()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.ticket == requestTicket,
                      isCurrentMount() else { return }
                self.task = nil
                self.countryInFlight = nil
                let message = "\(country): \(error.localizedDescription)"
                self.failureMessage = message
                onFailureChange(message)
            }
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
        selectedCountry = nil
        hasPrepared = false
        failureMessage = nil
    }
}
