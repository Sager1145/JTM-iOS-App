import Foundation
import Observation
import RailCore

struct CatalogStationRow: Identifiable, Hashable, Sendable {
    var station: CatalogStation
    var subtitle: String
    /// Line or operator text the round-trip qualifier does not already contain.
    var detail: String = ""
    /// `name (CC, lineLabel)` for copy and share. Empty falls back to the subtitle.
    var copyText: String = ""
    var id: String { station.key.sourceCode }
}

/// Owns one station picker's search snapshots and request lifetime. Ranking
/// stays in ``StationSearchIndex``; this controller only debounces and drops
/// a result whose load or query is no longer current.
@MainActor
@Observable
final class StationPickerSearchController {
    struct Request: Hashable, Sendable {
        var regionCode: String
        var rideDate: String?
        var lineIDs: Set<String>
        var includesRetired: Bool
        var companyName: String? = nil
    }

    private(set) var output = StationSearchResult()

    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var index: StationSearchIndex?
    @ObservationIgnored private var retired: [RetiredStation] = []
    @ObservationIgnored private var request = Request(
        regionCode: "", rideDate: nil, lineIDs: [], includesRetired: false)
    @ObservationIgnored private let debounce: @Sendable () async throws -> Void

    init(debounce: @escaping @Sendable () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(120))
    }) {
        self.debounce = debounce
    }

    func beginLoad() -> UUID {
        cancel()
        let id = UUID()
        loadID = id
        index = nil
        retired = []
        output = StationSearchResult()
        return id
    }

    func acceptsLoad(_ id: UUID) -> Bool { loadID == id }

    @discardableResult
    func install(
        index: StationSearchIndex,
        retired: [RetiredStation],
        request: Request,
        output: StationSearchResult,
        loadID: UUID
    ) -> Bool {
        guard acceptsLoad(loadID) else { return false }
        self.index = index
        self.retired = retired
        self.request = request
        self.output = output
        return true
    }

    func apply(query: String, companyName: String? = nil) {
        request.companyName = companyName
        filterTask?.cancel()
        let id = UUID()
        requestID = id
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index else { return }
        let retired = retired
        let query = storedQuery(needle: needle)
        let debounce = debounce
        filterTask = Task { @MainActor [weak self] in
            if !needle.isEmpty {
                do { try await debounce() } catch { return }
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                index.search(query, retired: retired)
            }.value
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.output = result
            self.filterTask = nil
        }
    }

    func cancel() {
        filterTask?.cancel()
        filterTask = nil
        requestID = UUID()
        loadID = nil
    }

    private func storedQuery(needle: String) -> StationSearchQuery {
        StationSearchQuery(
            regionCode: request.regionCode,
            needle: needle,
            rideDate: request.rideDate,
            eligibility: request.includesRetired ? [.current, .retired] : .current,
            lineIDs: request.lineIDs, companyName: request.companyName)
    }
}
