import Foundation
import RailCore

enum EditorCatalogLoadError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let country):
            return """
                \(country)-2025.json is not in the app bundle. \
                Run ios/copy-rail-packages.sh — the packages are copied from \
                app/public/rail rather than committed twice.
                """
        }
    }
}

private enum EditorCatalogCache {
    final class Store: @unchecked Sendable {
        static let shared = Store()
        private let lock = NSLock()
        private var catalogs: [String: EditorCatalog] = [:]

        func existing(_ code: String) -> EditorCatalog? {
            lock.lock()
            defer { lock.unlock() }
            return catalogs[code]
        }

        func store(_ catalog: EditorCatalog, code: String) -> EditorCatalog {
            lock.lock()
            defer { lock.unlock() }
            if let cached = catalogs[code] { return cached }
            catalogs[code] = catalog
            return catalog
        }
    }
}

/// Read-only catalog for one region. Parsed once per process; not editor session state.
nonisolated func loadCatalog(for region: Region) throws -> EditorCatalog {
    if let cached = EditorCatalogCache.Store.shared.existing(region.code) { return cached }
    guard let url = Bundle.main.url(forResource: region.packageResource, withExtension: "json")
    else { throw EditorCatalogLoadError.missingResource(region.code) }
    let directory = try JSONDecoder().decode(
        CompactPackage.StationDirectory.self, from: Data(contentsOf: url))
    let catalog = EditorCatalogBuilder.build(directory.lineSources(regionCode: region.code))
    return EditorCatalogCache.Store.shared.store(catalog, code: region.code)
}

/// Official station identity is shared by route searches and cached per region.
private enum JourneyStationIdentity {
    static let lock = NSLock()
    nonisolated(unsafe) static var groups: [String: [String: String]] = [:]

    nonisolated static func load(country: String) -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = groups[country] { return cached }
        guard let url = Bundle.main.url(
            forResource: Region.countrySuffixed("stations", country: country), withExtension: "json"),
              let collection = try? Stations.FeatureCollection.load(contentsOf: url) else { return [:] }
        var result: [String: String] = [:]
        for feature in collection.features {
            if let code = Stations.stationCode(feature), let group = Stations.stationGroupCode(feature) {
                result[code] = group
            }
        }
        groups[country] = result
        return result
    }
}

/// Call from the detached search worker, keeping cold JSON decoding off the main actor.
nonisolated func loadJourneyStationAliases(for codes: [String], package: CompactPackage) -> [String: String] {
    let groups = JourneyStationIdentity.load(country: package.country)
    return LocalJourneySearch.stationAliases(for: codes, package: package) { groups[$0] }
}
