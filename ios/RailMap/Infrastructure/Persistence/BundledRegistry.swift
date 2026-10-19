import Foundation
import os
import RailCore

/// Loads `registry-<cc>.json` from the app bundle the same way
/// `Stations.bundledIdentityIndex` loads a station file: one success cache.
/// A missing or unreadable file is a miss that is not remembered. A file that
/// decodes, or that decodes for a different region, is remembered as a failure
/// so a later train does not parse it again. The failure is logged once.
enum BundledRegistry {
    private static let lock = NSLock()
    private static let log = Logger(subsystem: "com.JRM.RailMap", category: "registry")
    nonisolated(unsafe) private static var decodeCache = DecodeCache()

    struct DecodeCache {
        private var bundles: [String: RegistryBundle] = [:]
        private var identities: [String: RegistryIdentity] = [:]
        private var failed: Set<String> = []
        private(set) var logCount = 0

        mutating func lookup(region: String, load: () -> Data?) -> RegistryBundle? {
            let cc = region.lowercased()
            guard !cc.isEmpty else { return nil }
            if let cached = bundles[cc] { return cached }
            if failed.contains(cc) { return nil }
            guard let data = load() else { return nil }
            guard let decoded = try? JSONDecoder().decode(RegistryBundle.self, from: data),
                  decoded.region.lowercased() == cc
            else {
                failed.insert(cc)
                logCount += 1
                return nil
            }
            bundles[cc] = decoded
            return decoded
        }

        mutating func identity(region: String, load: () -> Data?) -> RegistryIdentity? {
            let cc = region.lowercased()
            guard !cc.isEmpty else { return nil }
            if let cached = identities[cc] { return cached }
            guard let bundle = lookup(region: cc, load: load) else { return nil }
            let built = RegistryIdentity(bundle: bundle)
            identities[cc] = built
            return built
        }
    }

    static func install() {
        RegistryIdentityUpgrade.installBundleProvider { region in
            bundle(for: region)
        }
        StationNameLookup.install { region in
            guard let bundle = bundle(for: region) else { return nil }
            return StationNameDirectory(bundle: bundle)
        }
        RegistryIdentityLookup.install { region in
            identity(for: region)
        }
    }

    /// Registry identity for one region. The decoded bundle and its maps are cached together.
    static func identity(for region: String) -> RegistryIdentity? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let before = decodeCache.logCount
        let built = decodeCache.identity(region: cc) { loadData(region: cc) }
        if decodeCache.logCount > before {
            log.error("registry-\(cc, privacy: .public).json failed to decode")
        }
        return built
    }

    /// Decode path: the ride's own region, never the session country.
    static func upgrade(_ train: Train) -> Train {
        RegistryIdentityUpgrade.applyLoaded(train, regionFallback: nil)
    }

    private static func bundle(for region: String) -> RegistryBundle? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let before = decodeCache.logCount
        let decoded = decodeCache.lookup(region: cc) { loadData(region: cc) }
        if decodeCache.logCount > before {
            log.error("registry-\(cc, privacy: .public).json failed to decode")
        }
        return decoded
    }

    private static func loadData(region: String) -> Data? {
        guard let url = Bundle.main.url(forResource: "registry-\(region)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }
}
