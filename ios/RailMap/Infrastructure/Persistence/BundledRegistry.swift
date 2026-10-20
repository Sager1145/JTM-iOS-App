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

        mutating func lookup(region: String, fileExists: Bool = false, load: () -> Data?) -> RegistryBundle? {
            let cc = region.lowercased()
            guard !cc.isEmpty else { return nil }
            if let cached = bundles[cc] { return cached }
            if failed.contains(cc) { return nil }
            guard let data = load() else {
                if fileExists { noteFailure(cc) }
                return nil
            }
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

        func cachedIdentity(_ region: String) -> RegistryIdentity? {
            identities[region]
        }

        func cachedBundle(_ region: String) -> RegistryBundle? {
            bundles[region]
        }

        func hasFailed(_ region: String) -> Bool {
            failed.contains(region)
        }

        mutating func noteFailure(_ region: String) {
            let cc = region.lowercased()
            guard !cc.isEmpty, !failed.contains(cc) else { return }
            failed.insert(cc)
            logCount += 1
        }

        mutating func store(_ bundle: RegistryBundle, _ identity: RegistryIdentity) {
            let cc = bundle.region.lowercased()
            guard !cc.isEmpty, !failed.contains(cc), identities[cc] == nil else { return }
            bundles[cc] = bundle
            identities[cc] = identity
        }
    }

    /// Handlers run after a background decode settles, outside the decode lock.
    /// The argument is the region code that settled.
    private static let handlerLock = NSLock()
    nonisolated(unsafe) private static var settledHandlers: [Int: @Sendable (String) -> Void] = [:]
    nonisolated(unsafe) private static var nextHandlerToken = 0
    nonisolated(unsafe) private static var decoding = Set<String>()

    @discardableResult
    static func addSettledHandler(_ handler: @escaping @Sendable (String) -> Void) -> Int {
        handlerLock.lock()
        defer { handlerLock.unlock() }
        nextHandlerToken += 1
        settledHandlers[nextHandlerToken] = handler
        return nextHandlerToken
    }

    static func removeSettledHandler(_ token: Int) {
        handlerLock.lock()
        settledHandlers.removeValue(forKey: token)
        handlerLock.unlock()
    }

    static var settledHandlerCount: Int {
        handlerLock.lock()
        defer { handlerLock.unlock() }
        return settledHandlers.count
    }

    /// Removes its handler when released, so a per-instance registration cannot outlive its owner.
    final class SettledRegistration: Sendable {
        private let token: Int
        init(_ handler: @escaping @Sendable (String) -> Void) {
            token = BundledRegistry.addSettledHandler(handler)
        }
        deinit { BundledRegistry.removeSettledHandler(token) }
    }

    private static func notifySettledHandlers(_ region: String) {
        handlerLock.lock()
        let handlers = Array(settledHandlers.values)
        handlerLock.unlock()
        for handler in handlers { handler(region) }
    }

    static func install() {
        RegistryIdentityUpgrade.installBundleProvider { region in
            bundle(for: region)
        }
        StationNameLookup.install { region in
            directoryFromCache(region)
        }
        RegistryIdentityLookup.installPhase { region in
            phase(for: region)
        }
    }

    /// Starts a background decode for each region the store actually contains.
    static func preload(regions: [String]) {
        for region in regions {
            let cc = region.lowercased()
            guard !cc.isEmpty, fileExists(cc) else { continue }
            startDecode(cc)
        }
    }

    /// Ready when decoded, unavailable when there is no file or the decode failed,
    /// pending while a background decode is in flight. Never decodes on the caller.
    private static func phase(for region: String) -> RegistryPhase {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return .unavailable }
        lock.lock()
        if let identity = decodeCache.cachedIdentity(cc) {
            lock.unlock()
            return .ready(identity)
        }
        let failed = decodeCache.hasFailed(cc)
        lock.unlock()
        if failed { return .unavailable }
        guard fileExists(cc) else { return .unavailable }
        startDecode(cc)
        return .pending
    }

    /// A directory only when the bundle is already decoded. A miss starts the preload.
    private static func directoryFromCache(_ region: String) -> StationNameDirectory? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        let bundle = decodeCache.cachedBundle(cc)
        lock.unlock()
        if let bundle { return StationNameDirectory(bundle: bundle) }
        guard fileExists(cc) else { return nil }
        startDecode(cc)
        return nil
    }

    private static func startDecode(_ cc: String) {
        lock.lock()
        if decodeCache.cachedIdentity(cc) != nil || decodeCache.hasFailed(cc) || decoding.contains(cc) {
            lock.unlock()
            return
        }
        decoding.insert(cc)
        lock.unlock()
        Task.detached(priority: .utility) {
            _ = identity(for: cc)
            finishDecode(cc)
            RegistryIdentityLookup.notifySettled(region: cc)
            notifySettledHandlers(cc)
        }
    }

    /// Synchronous so the lock stays out of the detached task.
    private static func finishDecode(_ cc: String) {
        lock.lock()
        decoding.remove(cc)
        lock.unlock()
    }

    private static func fileExists(_ cc: String) -> Bool {
        Bundle.main.url(forResource: "registry-\(cc)", withExtension: "json") != nil
    }

    /// Registry identity for one region. Decode and map build stay outside the lock.
    static func identity(for region: String) -> RegistryIdentity? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        lock.lock()
        if let cached = decodeCache.cachedIdentity(cc) {
            lock.unlock()
            return cached
        }
        let failed = decodeCache.hasFailed(cc)
        lock.unlock()
        if failed { return nil }
        let exists = fileExists(cc)
        guard let data = loadData(region: cc) else {
            if exists { recordFailure(cc) }
            return nil
        }
        guard let bundle = try? JSONDecoder().decode(RegistryBundle.self, from: data),
              bundle.region.lowercased() == cc
        else {
            recordFailure(cc)
            return nil
        }
        let built = RegistryIdentity(bundle: bundle)
        lock.lock()
        if let cached = decodeCache.cachedIdentity(cc) {
            lock.unlock()
            return cached
        }
        if decodeCache.hasFailed(cc) {
            lock.unlock()
            return nil
        }
        decodeCache.store(bundle, built)
        lock.unlock()
        return built
    }

    /// Decode path: the ride's own region, never the session country.
    static func upgrade(_ train: Train) -> Train {
        RegistryIdentityUpgrade.applyLoaded(train, regionFallback: nil)
    }

    /// Leaves stored fields in place until this train's region is ready.
    /// Phase comes from the installed lookup so a test phase override is honored.
    /// Production install points that lookup at ``phase(for:)``.
    static func upgradeIfReady(_ train: Train) -> Train {
        let region = train.region?.lowercased() ?? ""
        guard !region.isEmpty else { return train }
        guard case .ready = RegistryIdentityLookup.phase(forRegion: region) else { return train }
        return upgrade(train)
    }

    private static func recordFailure(_ cc: String) {
        lock.lock()
        let before = decodeCache.logCount
        decodeCache.noteFailure(cc)
        let shouldLog = decodeCache.logCount > before
        lock.unlock()
        if shouldLog {
            log.error("registry-\(cc, privacy: .public).json failed to decode")
        }
    }

    private static func bundle(for region: String) -> RegistryBundle? {
        let cc = region.lowercased()
        guard !cc.isEmpty else { return nil }
        _ = identity(for: cc)
        lock.lock()
        defer { lock.unlock() }
        return decodeCache.cachedBundle(cc)
    }

    private static func loadData(region: String) -> Data? {
        guard let url = Bundle.main.url(forResource: "registry-\(region)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }
}
