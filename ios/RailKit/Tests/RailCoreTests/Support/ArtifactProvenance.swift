import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Swift mirror of `app/scripts/build/artifact-provenance.mjs`: what a generated
/// artifact (port fixture, Swift-written expectation) was generated from.
///
/// Bug class: fixtures and counts going stale after a data or solver change and
/// failing much later with an opaque diff. A stamp turns that into
/// "input X changed" with the command that regenerates it.
struct ArtifactProvenance: Codable, Equatable {
    static let format = "jtm-artifact-provenance/1"

    struct Engine: Codable, Equatable {
        var jsRouteSolverCacheVersion: String
        enum CodingKeys: String, CodingKey { case jsRouteSolverCacheVersion = "js_route_solver_cache_version" }
    }

    var format: String
    var generator: String
    var regenerate: String
    var engine: Engine?
    var historyRevisions: [String: String]
    var inputs: [String: String]

    enum CodingKeys: String, CodingKey {
        case format, generator, regenerate, engine
        case historyRevisions = "history_revisions"
        case inputs
    }

    /// Provenance of `inputs` as they are on disk now. Missing files read as "none".
    static func current(
        root: URL, generator: String, regenerate: String, inputs: [String], solverDependent: Bool
    ) -> ArtifactProvenance {
        var hashes: [String: String] = [:]
        var revisions: [String: String] = [:]
        for path in Set(inputs) {
            hashes[path] = sha256(root: root, path: path)
            if let code = historyCountry(path) { revisions[code] = historyRevision(root: root, path: path) }
        }
        return ArtifactProvenance(
            format: format, generator: generator, regenerate: regenerate,
            engine: solverDependent ? Engine(jsRouteSolverCacheVersion: jsRouteSolverCacheVersion(root: root)) : nil,
            historyRevisions: revisions, inputs: hashes)
    }

    /// Differences between this recorded stamp and the same inputs read now, as
    /// `key old → new` lines. Empty means current.
    func differences(root: URL) -> [String] {
        let now = Self.current(
            root: root, generator: generator, regenerate: regenerate,
            inputs: Array(inputs.keys), solverDependent: engine != nil)
        var out: [String] = []
        if format != Self.format { out.append("format \(format) → \(Self.format)") }
        if let engine, let nowEngine = now.engine, engine != nowEngine {
            out.append(
                "engine.js_route_solver_cache_version \(engine.jsRouteSolverCacheVersion) → \(nowEngine.jsRouteSolverCacheVersion)"
            )
        }
        out += Self.compare("history_revisions", historyRevisions, now.historyRevisions, short: false)
        out += Self.compare("inputs", inputs, now.inputs, short: true)
        return out
    }

    /// `key old → new` for every key whose value differs, in key order.
    static func compare(
        _ label: String, _ old: [String: String], _ new: [String: String], short: Bool
    ) -> [String] {
        func show(_ value: String?) -> String {
            guard let value else { return "none" }
            return short ? String(value.prefix(8)) : value
        }
        return Set(old.keys).union(new.keys).sorted().compactMap { key in
            old[key] == new[key] ? nil : "\(label)[\(key)] \(show(old[key])) → \(show(new[key]))"
        }
    }

    // MARK: - readers

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var hashes: [String: String] = [:]
        private var revisions: [String: String] = [:]

        func hash(_ url: URL, compute: () -> String) -> String {
            lock.lock(); defer { lock.unlock() }
            if let hit = hashes[url.path] { return hit }
            let value = compute()
            hashes[url.path] = value
            return value
        }

        func revision(_ url: URL, compute: () -> String) -> String {
            lock.lock(); defer { lock.unlock() }
            if let hit = revisions[url.path] { return hit }
            let value = compute()
            revisions[url.path] = value
            return value
        }
    }

    private static let cache = Cache()

    static func sha256(root: URL, path: String) -> String {
        sha256(of: root.appending(path: path))
    }

    /// Lowercase hex SHA-256 of the file's bytes, cached per path; "none" when absent.
    static func sha256(of url: URL) -> String {
        cache.hash(url) {
            guard let data = try? Data(contentsOf: url) else { return "none" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// `ROUTE_SOLVER_CACHE_VERSION` from `app/public/app-config.js`, same pattern as the precompute.
    static func jsRouteSolverCacheVersion(root: URL) -> String {
        guard
            let source = try? String(
                contentsOf: root.appending(path: "app/public/app-config.js"), encoding: .utf8),
            let match = source.firstMatch(
                of: /const\s+ROUTE_SOLVER_CACHE_VERSION\s*=\s*["']([^"']+)["']/)
        else { return "none" }
        return String(match.1)
    }

    /// `app/data/rail-history[-cc].json` -> cc ("jp" for the unsuffixed file).
    static func historyCountry(_ path: String) -> String? {
        guard let match = path.firstMatch(of: /^app\/data\/rail-history(?:-([a-z]{2}))?\.json$/) else {
            return nil
        }
        return match.1.map(String.init) ?? "jp"
    }

    /// Top-level `revision` of a history package; "none" when the file is absent.
    static func historyRevision(root: URL, path: String) -> String {
        let url = root.appending(path: path)
        return cache.revision(url) {
            guard let data = try? Data(contentsOf: url) else { return "none" }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (object?["revision"] as? String) ?? "none"
        }
    }
}
