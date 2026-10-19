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

        func reset() {
            lock.lock()
            catalogs.removeAll()
            lock.unlock()
        }
    }
}

func testingResetEditorCatalogCache() {
    EditorCatalogCache.Store.shared.reset()
}

/// Read-only catalog for one region. Parsed once per process; not editor session state.
nonisolated func loadCatalog(for region: Region) throws -> EditorCatalog {
    if let cached = EditorCatalogCache.Store.shared.existing(region.code) { return cached }
    // A resident full package already has the station rows. Reading it here
    // must not be what causes that decode.
    if let loaded = DisplayNetworkCache.shared.residentPackage(country: region.code) {
        let catalog = EditorCatalogBuilder.build(
            EditorCatalogBuilder.sources(regionCode: region.code, package: loaded.package))
        return EditorCatalogCache.Store.shared.store(catalog, code: region.code)
    }
    guard let url = Bundle.main.url(forResource: region.packageResource, withExtension: "json")
    else { throw EditorCatalogLoadError.missingResource(region.code) }
    let directory = try JSONDecoder().decode(
        CompactPackage.StationDirectory.self, from: Data(contentsOf: url))
    let catalog = EditorCatalogBuilder.build(directory.lineSources(regionCode: region.code))
    return EditorCatalogCache.Store.shared.store(catalog, code: region.code)
}

