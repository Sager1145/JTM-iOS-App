import Foundation
import RailCore

/// The app's one `SearchEngine`: a region's search index is built once and
/// reused by the station picker and the line search, instead of per open.
/// Ranking, folding and keyword parsing all live in RailCore.
final class SharedSearchEngine: @unchecked Sendable {
    static let shared = SharedSearchEngine()

    let engine: SearchEngine
    private let state: State

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var readings: [String: [String: [String]]] = [:]
        private var stationIndexes: [String: CachedStationIndex] = [:]

        struct CachedStationIndex {
            var engine: SearchIndex
            var index: StationSearchIndex
            var generation: UInt64
            var hadIdentity: Bool
        }

        func readings(_ regionCode: String) -> [String: [String]] {
            lock.withLock { readings[regionCode] ?? [:] }
        }

        /// True when the readings changed and the region's index is stale.
        func setReadings(_ new: [String: [String]], regionCode: String) -> Bool {
            lock.withLock {
                guard readings[regionCode] != new else { return false }
                readings[regionCode] = new
                stationIndexes[regionCode] = nil
                return true
            }
        }

        func cached(regionCode: String) -> CachedStationIndex? {
            lock.withLock { stationIndexes[regionCode] }
        }

        func store(_ entry: CachedStationIndex, regionCode: String) {
            lock.withLock { stationIndexes[regionCode] = entry }
        }
    }

    private init() {
        let state = State()
        self.state = state
        engine = SearchEngine { regionCode in
            guard let region = Region(rawValue: regionCode) else {
                throw EditorCatalogLoadError.missingResource(regionCode)
            }
            let catalog = try loadCatalog(for: region)
            return SearchIndexBuilder.catalog(
                catalog, regionCode: regionCode, extraNames: state.readings(regionCode))
        }
    }

    /// Hand over the language's station readings. A change drops that region's
    /// index; the next query rebuilds it. Call before asking for the index.
    func prepare(regionCode: String, readings: [String: [String]]) {
        if state.setReadings(readings, regionCode: regionCode) {
            engine.invalidate(regionCode: regionCode)
        }
    }

    /// The picker's index for a region, over the shared engine index.
    func stationIndex(regionCode: String, catalog: EditorCatalog) async throws -> StationSearchIndex {
        // The registry may become ready (or its provider change) after an index
        // was built without identity: rebuild both layers then.
        var generation = RegistryIdentityLookup.providerGeneration
        var hasIdentity = Self.hasIdentity(regionCode)
        if let cached = state.cached(regionCode: regionCode),
           cached.generation != generation || (!cached.hadIdentity && hasIdentity) {
            engine.invalidate(regionCode: regionCode)
        }
        let shared = try await engine.index(regionCode: regionCode)
        generation = RegistryIdentityLookup.providerGeneration
        hasIdentity = Self.hasIdentity(regionCode)
        if let cached = state.cached(regionCode: regionCode), cached.engine === shared,
           cached.generation == generation, cached.hadIdentity || !hasIdentity {
            return cached.index
        }
        let built = catalog.stationSearchIndex(regionCode: regionCode, engine: shared)
        state.store(.init(engine: shared, index: built, generation: generation, hadIdentity: hasIdentity),
                    regionCode: regionCode)
        return built
    }

    private static func hasIdentity(_ regionCode: String) -> Bool {
        RegistryIdentityCache.identity(forRegion: regionCode).map { !$0.bundle.stations.isEmpty } ?? false
    }
}

/// The last stations a reader picked in each region, most recent first.
enum StationPickerRecents {
    static let limit = 20

    static func key(_ regionCode: String) -> String { "stationPicker.recent.\(regionCode)" }

    static func load(regionCode: String, defaults: UserDefaults = .standard) -> [SearchEntityID] {
        guard let data = defaults.data(forKey: key(regionCode)),
              let list = try? JSONDecoder().decode([SearchEntityID].self, from: data) else { return [] }
        return Array(list.filter { $0.kind == .station && !$0.id.isEmpty }.prefix(limit))
    }

    @discardableResult
    static func record(
        stationCode: String, regionCode: String, defaults: UserDefaults = .standard
    ) -> [SearchEntityID] {
        let pick = SearchEntityID.station(stationCode)
        var list = load(regionCode: regionCode, defaults: defaults).filter { $0 != pick }
        list.insert(pick, at: 0)
        list = Array(list.prefix(limit))
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key(regionCode)) }
        return list
    }

    /// Saved rides of this region, per line and per boarding/alighting station.
    static func rideCounts(trains: [Train], regionCode: String) -> [SearchEntityID: Int] {
        var counts: [SearchEntityID: Int] = [:]
        for train in trains where (train.region ?? regionCode) == regionCode {
            var lines = Set<String>()
            var stations = Set<String>()
            for section in train.routeSections ?? [] {
                lines.formUnion(section.lineIDs ?? [])
                for code in [section.fromN02StationCode, section.toN02StationCode] {
                    if let code, !code.isEmpty { stations.insert(code) }
                }
            }
            for id in lines { counts[.line(id), default: 0] += 1 }
            for code in stations { counts[.station(code), default: 0] += 1 }
        }
        return counts
    }
}
