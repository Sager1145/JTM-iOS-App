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
    /// Registry company station this row writes. Nil when the row is a complex
    /// with more than one station, or when no registry is installed.
    var stationID: String? = nil
    /// How the shared engine matched this row, for highlights and the "matched via" line.
    var match: SearchMatch? = nil
    var id: String { station.key.sourceCode }
}

/// Owns one station picker's search snapshots and request lifetime. Ranking
/// stays in the shared RailCore engine (via ``StationSearchIndex``, whose index
/// comes from ``SharedSearchEngine``); this controller only debounces and drops
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
    /// Best engine match per station source code, from the same response as `output`.
    private(set) var matches: [String: SearchMatch] = [:]

    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var emptyBoxTask: Task<Void, Never>?
    @ObservationIgnored private var lastNeedle = ""
    @ObservationIgnored private var index: StationSearchIndex?
    @ObservationIgnored private var retired: [RetiredStation] = []
    @ObservationIgnored private var recentPicks: [SearchEntityID] = []
    @ObservationIgnored private var rideCounts: [SearchEntityID: Int] = [:]
    @ObservationIgnored private var visibleRegion: SearchMapRect?
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
        matches = [:]
        visibleRegion = nil
        lastNeedle = ""
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
        self.matches = Self.matches(of: output)
        return true
    }

    /// Ranking signals for the engine's `SearchContext`. The visible region
    /// arrives on camera idle and is read by the next search.
    func setSignals(
        recentPicks: [SearchEntityID]? = nil, rideCounts: [SearchEntityID: Int]? = nil,
        visibleRegion: SearchMapRect? = nil
    ) {
        if let recentPicks { self.recentPicks = recentPicks }
        if let rideCounts { self.rideCounts = rideCounts }
        if let visibleRegion {
            self.visibleRegion = visibleRegion
            refreshEmptyBox()
        }
    }

    nonisolated private static func matches(of output: StationSearchResult) -> [String: SearchMatch] {
        var best: [String: SearchMatch] = [:]
        for result in output.response?.results ?? [] where result.entity.kind == .station {
            // Results are ranked best first: keep the first match per station.
            if best[result.entity.id] == nil { best[result.entity.id] = result.match }
        }
        return best
    }

    /// The map settled somewhere new while the box is empty: re-rank the empty-box
    /// suggestions by what is visible. Debounced; the map reports on camera idle.
    private func refreshEmptyBox() {
        guard index != nil, lastNeedle.isEmpty else { return }
        emptyBoxTask?.cancel()
        let debounce = debounce
        emptyBoxTask = Task { @MainActor [weak self] in
            do { try await debounce() } catch { return }
            guard let self, self.lastNeedle.isEmpty else { return }
            self.apply(query: "", companyName: self.request.companyName)
        }
    }

    func apply(query: String, companyName: String? = nil) {
        request.companyName = companyName
        emptyBoxTask?.cancel()
        lastNeedle = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let (result, matches) = await Task.detached(priority: .userInitiated) {
                let result = index.search(query, retired: retired)
                return (result, Self.matches(of: result))
            }.value
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.output = result
            self.matches = matches
            self.filterTask = nil
        }
    }

    /// The picker's one Clear: forget this region's recent queries and recent
    /// picks (no other region's), then re-rank the empty box without them.
    func clearRecents(regionCode: String, defaults: UserDefaults = .standard) {
        RecentSearchStore.clear(.stationPicker, regionCode: regionCode, defaults: defaults)
        defaults.removeObject(forKey: StationPickerRecents.key(regionCode))
        recentPicks = []
        refreshEmptyBoxNow()
    }

    /// Long-press "Remove" on one recent query chip. Returns the remaining queries.
    @discardableResult
    func removeRecentQuery(_ query: String, regionCode: String, defaults: UserDefaults = .standard) -> [String] {
        RecentSearchStore.remove(query, box: .stationPicker, regionCode: regionCode, defaults: defaults)
    }

    private func refreshEmptyBoxNow() {
        guard index != nil, lastNeedle.isEmpty else { return }
        apply(query: "", companyName: request.companyName)
    }

    func cancel() {
        filterTask?.cancel()
        emptyBoxTask?.cancel()
        filterTask = nil
        requestID = UUID()
        loadID = nil
    }

    private func storedQuery(needle: String) -> StationSearchQuery {
        var query = StationSearchQuery(
            regionCode: request.regionCode,
            needle: needle,
            rideDate: request.rideDate,
            eligibility: request.includesRetired ? [.current, .retired] : .current,
            lineIDs: request.lineIDs, companyName: request.companyName)
        query.recentPicks = recentPicks
        query.rideCounts = rideCounts
        query.visibleRegion = visibleRegion
        return query
    }
}
