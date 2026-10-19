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
            guard let bundle = bundle(for: region) else { return nil }
            return RegistryIdentity(bundle: bundle)
        }
    }

    /// Registry identity for one region. Nil when that file is missing or failed to decode.
    static func identity(for region: String) -> RegistryIdentity? {
        guard let bundle = bundle(for: region) else { return nil }
        return RegistryIdentity(bundle: bundle)
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
        let decoded = decodeCache.lookup(region: cc) {
            guard let url = Bundle.main.url(forResource: "registry-\(cc)", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return data
        }
        if decodeCache.logCount > before {
            log.error("registry-\(cc, privacy: .public).json failed to decode")
        }
        return decoded
    }
}
