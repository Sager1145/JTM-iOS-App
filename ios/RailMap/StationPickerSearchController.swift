import Foundation
import Observation
import RailCore

struct CatalogStationRow: Identifiable, Hashable, Sendable {
    var station: CatalogStation
    var subtitle: String
    var id: String { station.key.sourceCode }
}

/// Owns one station picker's search snapshots and request lifetime. Catalog
/// loading stays with the view; a load token prevents its suspended preparation
/// from installing into a replacement load or a dismissed picker.
@MainActor
@Observable
final class StationPickerSearchController {
    struct LoadIdentity: Hashable, Sendable {
        let regionCode: String
        let selectedLineIDs: Set<String>
        let rideDate: String?
        let includesRetired: Bool
    }

    struct Input: Sendable {
        let rows: [CatalogStationRow]
        let retired: [RetiredStation]
        let needle: String
    }

    struct Result: Sendable {
        let rows: [CatalogStationRow]
        let retired: [RetiredStation]
    }

    typealias Search = @Sendable (Input) async -> Result
    typealias Debounce = @Sendable () async throws -> Void

    private(set) var prepared: [CatalogStationRow] = []
    private(set) var retired: [RetiredStation] = []
    private(set) var matches: [CatalogStationRow] = []
    private(set) var matchedRetired: [RetiredStation] = []

    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private let search: Search
    @ObservationIgnored private let debounce: Debounce

    init(
        search: @escaping Search = StationPickerSearchController.search,
        debounce: @escaping Debounce = { try await Task.sleep(for: .milliseconds(120)) }
    ) {
        self.search = search
        self.debounce = debounce
    }

    func beginLoad() -> UUID {
        cancel()
        let id = UUID()
        loadID = id
        prepared = []
        retired = []
        matches = []
        matchedRetired = []
        return id
    }

    func acceptsLoad(_ id: UUID) -> Bool { loadID == id }

    @discardableResult
    func install(rows: [CatalogStationRow], retired: [RetiredStation], loadID: UUID, query: String) -> Bool {
        guard acceptsLoad(loadID) else { return false }
        prepared = rows
        self.retired = retired
        apply(query: query)
        return true
    }

    func apply(query: String) {
        filterTask?.cancel()
        let id = UUID()
        requestID = id
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            filterTask = nil
            matches = prepared
            matchedRetired = retired
            return
        }
        let input = Input(rows: prepared, retired: retired, needle: needle)
        let search = search
        let debounce = debounce
        filterTask = Task { @MainActor [weak self] in
            do { try await debounce() } catch { return }
            guard !Task.isCancelled else { return }
            let result = await search(input)
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.matches = result.rows
            self.matchedRetired = result.retired
            self.filterTask = nil
        }
    }

    func cancel() {
        filterTask?.cancel()
        filterTask = nil
        requestID = UUID()
        loadID = nil
    }

    nonisolated static func search(_ input: Input) async -> Result {
        await Task.detached(priority: .userInitiated) { filter(input) }.value
    }

    /// Preserve catalog ordering and the existing localized matching rules.
    /// Historical stations match names only, not their codes or line names.
    nonisolated static func filter(_ input: Input) -> Result {
        Result(rows: input.rows.filter {
            $0.station.name.localizedStandardContains(input.needle)
                || $0.station.aliases.contains { $0.localizedStandardContains(input.needle) }
                || $0.station.key.sourceCode.localizedStandardContains(input.needle)
        }, retired: input.retired.filter { $0.name.localizedStandardContains(input.needle) })
    }
}
