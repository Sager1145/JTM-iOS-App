import Foundation

/// Owns one lazily built `SearchIndex` per region. Builds run once, off the
/// caller's thread, and concurrent callers share the same build. Hold one
/// engine for the app (the loader knows how to read a region's catalog).
///
/// Cancellation: `query` runs on a detached task and propagates the caller's
/// cancellation, so a controller that cancels its previous task per keystroke
/// stops the stale scan early.
public final class SearchEngine: @unchecked Sendable {
    public typealias Loader = @Sendable (_ regionCode: String) throws -> SearchIndex

    private let loader: Loader
    private let lock = NSLock()
    private var built: [String: SearchIndex] = [:]
    private var building: [String: (task: Task<SearchIndex, Error>, generation: UInt64)] = [:]
    /// Bumped by `invalidate`; a build only caches its result if no invalidation
    /// happened since it started (the loader itself can't be interrupted).
    private var generation: [String: UInt64] = [:]

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    /// The region's index, building it on first use.
    public func index(regionCode: String) async throws -> SearchIndex {
        let (task, startedAt): (Task<SearchIndex, Error>, UInt64) = lock.withLock {
            let current = generation[regionCode, default: 0]
            if let ready = built[regionCode] { return (Task { ready }, current) }
            if let running = building[regionCode] { return running }
            let loader = loader
            let running = Task.detached(priority: .userInitiated) { try loader(regionCode) }
            building[regionCode] = (running, current)
            return (running, current)
        }
        do {
            let index = try await task.value
            let stale: Bool = lock.withLock {
                guard generation[regionCode, default: 0] == startedAt else { return true }
                built[regionCode] = index
                if building[regionCode]?.generation == startedAt { building[regionCode] = nil }
                return false
            }
            // Invalidated mid-build: the result may reflect old names; build afresh.
            if stale { return try await self.index(regionCode: regionCode) }
            return index
        } catch {
            let stale: Bool = lock.withLock {
                if building[regionCode]?.generation == startedAt { building[regionCode] = nil }
                return generation[regionCode, default: 0] != startedAt
            }
            // A build cancelled or failed by `invalidate` is retried, like a stale success.
            if stale, !Task.isCancelled { return try await self.index(regionCode: regionCode) }
            throw error
        }
    }

    /// The index when already built; never builds.
    public func cachedIndex(regionCode: String) -> SearchIndex? {
        lock.withLock { built[regionCode] }
    }

    /// Start building a region's index in the background (e.g. when the editor opens).
    public func prewarm(regionCode: String) {
        Task.detached(priority: .utility) { [self] in _ = try? await index(regionCode: regionCode) }
    }

    /// Drop a region's index (its catalog or readings changed). The next query rebuilds.
    public func invalidate(regionCode: String) {
        lock.withLock {
            generation[regionCode, default: 0] &+= 1
            built[regionCode] = nil
            building[regionCode]?.task.cancel()
            building[regionCode] = nil
        }
    }

    /// Query the context's region. Runs off the caller's thread; honours cancellation.
    public func query(_ text: String, scope: SearchScope = .all, context: SearchContext) async throws -> SearchResponse {
        let index = try await index(regionCode: context.regionCode)
        let worker = Task.detached(priority: .userInitiated) {
            index.query(text, scope: scope, context: context)
        }
        let response = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return response
    }
}
