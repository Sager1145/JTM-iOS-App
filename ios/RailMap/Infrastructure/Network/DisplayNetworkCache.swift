import Foundation
import RailCore

/// One resident region’s railway package, shared by the map, the route network,
/// and the editor.
///
/// A full `<country>-2025.json` decode is the expensive read. Callers that need
/// that file — map geometry, ``RouteNetwork``, and the editor’s route package —
/// share one in-flight task per region and resource revision. ``EditorCatalog``
/// does not: it keeps its header-weight station read unless a package is already
/// resident. Layout (``DisplayParts``) runs once for that same generation and is
/// what both the map and ``RouteNetwork`` consume.
///
/// Residency stays one package, one layout, and one network. A newer region or
/// revision drops the previous slot; the next ask reads the file again. Failure
/// is not stored. A subscriber’s cancellation resumes only that subscriber.
///
/// The build permit is this cache’s own limiter, not ``RouteSolveLimiter/shared``
/// and not ``EdgeIndexCache``’s. Edge construction awaits this cache while
/// holding its limiter; folding the two into one non-reentrant permit deadlocks.
/// Admission order inside the permit is release the retained network, then
/// allocate the replacement, then publish before the permit is released.
actor DisplayNetworkCache {
    static let shared = DisplayNetworkCache()

    private struct PackageIdentity: Hashable, Sendable {
        var country: String
        var revision: String
    }

    private struct LineLayout: Sendable {
        var lineIDs: [String]
        var parts: [[[Coordinate]]]
    }

    private struct ResidentPackage {
        var identity: PackageIdentity
        var package: DisplayParts.LoadedPackage
    }

    private struct ResidentParts {
        var identity: PackageIdentity
        var layout: LineLayout
    }

    private var residentPackage: ResidentPackage?
    private var residentParts: ResidentParts?
    private var networks: [String: RouteNetwork] = [:]
    private var networkIdentity: [String: PackageIdentity] = [:]

    private var packageLoads: [PackageIdentity: Task<DisplayParts.LoadedPackage, Error>] = [:]
    private var partLoads: [PackageIdentity: Task<LineLayout, Error>] = [:]
    private var networkLoads: [PackageIdentity: Task<RouteNetwork, Error>] = [:]

    /// Bumped when a different package generation is admitted, so a late task
    /// cannot publish over the generation that replaced it.
    private var packageTicket = 0
    private var partsTicket = 0
    private var packageAdmitted: PackageIdentity?
    private var partsAdmitted: PackageIdentity?
    private var networkAdmitted: PackageIdentity?

    private var fullDecodeCount = 0
    private var layoutCount = 0
    private var forcedFailures = 0
    private var blockNextLoad = false
    private var loadMayProceed = true
    private var loadDidEnter = false
    private var loadEntered: CheckedContinuation<Void, Never>?
    private var unblock: CheckedContinuation<Void, Never>?

    private let buildLimiter = RouteSolveLimiter(limit: 1)
    private nonisolated let revisionSource = RevisionSource()
    private nonisolated let publication = ResidentPublication()

    /// The immutable full decode for one region at the current resource revision.
    func package(country: String) async throws -> DisplayParts.LoadedPackage {
        try await loadPackage(identity(for: country))
    }

    /// Display layout for the same generation ``package(country:)`` just decoded.
    /// A second caller joins the in-flight layout instead of running ``DisplayParts`` again.
    func lineParts(country: String) async throws -> (lineIDs: [String], parts: [[[Coordinate]]]) {
        let identity = identity(for: country)
        let loaded = try await loadPackage(identity)
        let layout = try await loadParts(identity, loaded: loaded)
        return (layout.lineIDs, layout.parts)
    }

    /// Package and layout captured for one identity, so a map decode cannot
    /// apply another generation’s parts to this package.
    func generation(country: String) async throws -> (
        package: DisplayParts.LoadedPackage, parts: [[[Coordinate]]]
    ) {
        let identity = identity(for: country)
        let loaded = try await loadPackage(identity)
        let layout = try await loadParts(identity, loaded: loaded)
        precondition(
            layout.lineIDs == loaded.package.lines.map(\.id),
            "layout generation drifted from its package")
        return (loaded, layout.parts)
    }

    /// A failed optional attestation remains visible without making the physical package unavailable.
    nonisolated func resourceRevisionFailure(for country: String) -> String? {
        revisionSource.failure(for: country)
    }

    /// Already-resident package for this country and revision. Does not read the file.
    nonisolated func residentPackage(country: String) -> DisplayParts.LoadedPackage? {
        publication.package(country: country, revision: revisionSource.revision(for: country))
    }

    func network(scope: RouteScope) async throws -> RouteNetwork {
        guard scope.crossesBorder else { return try await network(country: scope.code) }
        let identity = scopeIdentity(scope)
        if let ready = networks[scope.key], networkIdentity[scope.key] == identity { return ready }
        // Catalog order, not request order and not the statistics merge key.
        var lines: [RouteNetwork.Line] = []
        for region in scope.graphRegions {
            lines += try await network(country: region.code).lines
        }
        let merged = RouteNetwork(lines: lines)
        retain(merged, key: scope.key, identity: identity)
        return merged
    }

    func network(country: String) async throws -> RouteNetwork {
        let identity = identity(for: country)
        if let ready = networks[country], networkIdentity[country] == identity { return ready }
        if let running = networkLoads[identity] { return try await joinShared(running) }
        let limiter = buildLimiter
        let task = Task.detached(priority: .userInitiated) { () throws -> RouteNetwork in
            do {
                return try await limiter.withPermit {
                    await self.beginNetwork(identity)
                    let interval = RailSignpost.data.begin("data.displayNetwork.build")
                    defer { RailSignpost.data.end("data.displayNetwork.build", interval) }
                    let loaded = try await self.loadPackage(identity)
                    let layout = try await self.loadParts(identity, loaded: loaded)
                    let built = Self.assemble(loaded: loaded, layout: layout)
                    await self.completeNetwork(identity, built, key: country)
                    return built
                }
            } catch {
                await self.failNetwork(identity)
                throw error
            }
        }
        networkLoads[identity] = task
        return try await joinShared(task)
    }

    func testingReset() {
        packageTicket += 1
        partsTicket += 1
        residentPackage = nil
        residentParts = nil
        networks.removeAll()
        networkIdentity.removeAll()
        packageLoads.removeAll()
        partLoads.removeAll()
        networkLoads.removeAll()
        packageAdmitted = nil
        partsAdmitted = nil
        networkAdmitted = nil
        fullDecodeCount = 0
        layoutCount = 0
        forcedFailures = 0
        blockNextLoad = false
        loadMayProceed = true
        loadDidEnter = false
        loadEntered?.resume()
        loadEntered = nil
        unblock?.resume()
        unblock = nil
        revisionSource.setOverride(nil)
        publication.clear()
    }

    func testingFailNextPackageLoad() {
        forcedFailures += 1
    }

    func testingSetRevisions(_ revisions: RailResourceRevisions?) {
        revisionSource.setOverride(revisions)
    }

    func testingFullDecodeCount() -> Int { fullDecodeCount }

    func testingLayoutCount() -> Int { layoutCount }

    func testingBlockNextLoad() {
        blockNextLoad = true
        loadMayProceed = true
        loadDidEnter = false
    }

    func testingWaitUntilLoadBlocked() async {
        if loadDidEnter { return }
        await withCheckedContinuation { continuation in
            if loadDidEnter {
                continuation.resume()
            } else {
                loadEntered = continuation
            }
        }
    }

    func testingUnblockLoad() {
        loadMayProceed = true
        unblock?.resume()
        unblock = nil
    }

    private func identity(for country: String) -> PackageIdentity {
        PackageIdentity(country: country, revision: revisionSource.revision(for: country))
    }

    private func scopeIdentity(_ scope: RouteScope) -> PackageIdentity {
        let joined = scope.graphRegions.map(\.code).joined(separator: "+")
        return PackageIdentity(country: scope.key, revision: revisionSource.revision(for: joined))
    }

    private func loadPackage(_ identity: PackageIdentity) async throws -> DisplayParts.LoadedPackage {
        if let resident = residentPackage, resident.identity == identity { return resident.package }
        if let running = packageLoads[identity] { return try await joinShared(running) }
        let ticket = beginPackage(identity)
        let country = identity.country
        let task = Task.detached(priority: .userInitiated) { () throws -> DisplayParts.LoadedPackage in
            do {
                if await self.consumeFailure() { throw MissingPackage(country: country) }
                await self.blockLoadIfRequested()
                let loaded = try Self.load(country: country)
                await self.noteDecode()
                await self.completePackage(identity, loaded, ticket: ticket)
                return loaded
            } catch {
                await self.failPackage(identity)
                throw error
            }
        }
        packageLoads[identity] = task
        return try await joinShared(task)
    }

    private func loadParts(
        _ identity: PackageIdentity, loaded: DisplayParts.LoadedPackage
    ) async throws -> LineLayout {
        if let resident = residentParts, resident.identity == identity { return resident.layout }
        if let running = partLoads[identity] { return try await joinShared(running) }
        let ticket = beginParts(identity)
        let task = Task.detached(priority: .userInitiated) { () throws -> LineLayout in
            let layout = Self.layout(loaded)
            await self.noteLayout()
            await self.completeParts(identity, layout, ticket: ticket)
            return layout
        }
        partLoads[identity] = task
        return try await joinShared(task)
    }

    private func beginPackage(_ identity: PackageIdentity) -> Int {
        if packageAdmitted != identity {
            packageTicket += 1
            packageAdmitted = identity
            if residentPackage?.identity != identity {
                residentPackage = nil
                publication.clear()
            }
            if residentParts?.identity != identity {
                partsTicket += 1
                partsAdmitted = nil
                residentParts = nil
            }
        }
        return packageTicket
    }

    private func beginParts(_ identity: PackageIdentity) -> Int {
        if partsAdmitted != identity {
            partsTicket += 1
            partsAdmitted = identity
            if residentParts?.identity != identity { residentParts = nil }
        }
        return partsTicket
    }

    /// Release the previous network before the caller allocates its replacement.
    private func beginNetwork(_ identity: PackageIdentity) {
        releaseCachedNetwork()
        networkAdmitted = identity
        if packageAdmitted != identity {
            packageTicket += 1
            packageAdmitted = identity
            residentPackage = nil
            publication.clear()
        }
        if partsAdmitted != identity {
            partsTicket += 1
            partsAdmitted = identity
            residentParts = nil
        }
    }

    private func completePackage(
        _ identity: PackageIdentity, _ loaded: DisplayParts.LoadedPackage, ticket: Int
    ) {
        packageLoads[identity] = nil
        guard ticket == packageTicket, packageAdmitted == identity else { return }
        residentPackage = ResidentPackage(identity: identity, package: loaded)
        publication.store(country: identity.country, revision: identity.revision, package: loaded)
    }

    private func failPackage(_ identity: PackageIdentity) {
        packageLoads[identity] = nil
    }

    private func completeParts(_ identity: PackageIdentity, _ layout: LineLayout, ticket: Int) {
        partLoads[identity] = nil
        guard ticket == partsTicket, partsAdmitted == identity else { return }
        residentParts = ResidentParts(identity: identity, layout: layout)
    }

    private func completeNetwork(_ identity: PackageIdentity, _ network: RouteNetwork, key: String) {
        networkLoads[identity] = nil
        guard networkAdmitted == identity else { return }
        retain(network, key: key, identity: identity)
    }

    private func failNetwork(_ identity: PackageIdentity) {
        networkLoads[identity] = nil
    }

    private func retain(_ network: RouteNetwork, key: String, identity: PackageIdentity) {
        networks = [key: network]
        networkIdentity = [key: identity]
    }

    private func releaseCachedNetwork() {
        networks.removeAll()
        networkIdentity.removeAll()
    }

    private func consumeFailure() -> Bool {
        guard forcedFailures > 0 else { return false }
        forcedFailures -= 1
        return true
    }

    private func noteDecode() { fullDecodeCount += 1 }

    private func noteLayout() { layoutCount += 1 }

    private func blockLoadIfRequested() async {
        guard blockNextLoad else { return }
        blockNextLoad = false
        loadMayProceed = false
        loadDidEnter = true
        loadEntered?.resume()
        loadEntered = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if loadMayProceed {
                continuation.resume()
            } else {
                unblock = continuation
            }
        }
    }

    private nonisolated static func load(country: String) throws -> DisplayParts.LoadedPackage {
        guard let url = Bundle.main.url(
            forResource: Region.packageResource(country: country), withExtension: "json")
        else { throw MissingPackage(country: country) }
        return try DisplayParts.LoadedPackage.load(contentsOf: url)
    }

    private nonisolated static func layout(_ loaded: DisplayParts.LoadedPackage) -> LineLayout {
        let lines = loaded.package.lines
        return LineLayout(
            lineIDs: lines.map(\.id),
            parts: lines.map { line in
                DisplayParts.parts(for: line, topology: loaded.topologyByLineID[line.id] ?? .init())
            })
    }

    private nonisolated static func assemble(
        loaded: DisplayParts.LoadedPackage, layout: LineLayout
    ) -> RouteNetwork {
        let lines = loaded.package.lines
        precondition(
            layout.lineIDs == lines.map(\.id),
            "layout generation drifted from its package")
        return RouteNetwork(lines: lines.enumerated().map { index, line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: layout.parts[index],
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
    }

    struct MissingPackage: LocalizedError {
        let country: String
        var errorDescription: String? {
            """
            \(country)-2025.json is not in the app bundle. \
            Run ios/copy-rail-packages.sh — the packages are copied from \
            app/public/rail rather than committed twice.
            """
        }
    }
}

/// Bundled ``RailResourceRevisions``, plus a test override of that same value.
private final class RevisionSource: @unchecked Sendable {
    private let lock = NSLock()
    private var override: RailResourceRevisions?

    func setOverride(_ revisions: RailResourceRevisions?) {
        lock.lock()
        override = revisions
        lock.unlock()
    }

    private func currentRevision(for country: String) -> Result<String, Error> {
        lock.lock()
        let override = override
        lock.unlock()
        return Result {
            let current = try override ?? RailResourceRevisions.bundled()
            return try current.requiredRevision(for: country)
        }
    }

    func failure(for country: String) -> String? {
        if case .failure(let error) = currentRevision(for: country) { return error.localizedDescription }
        return nil
    }

    func revision(for country: String) -> String {
        if case .success(let revision) = currentRevision(for: country) { return revision }
        // This cache only retains immutable data in memory. The current
        // record's diagnostic is read separately; disk caches require attestation.
        return ""
    }
}

/// Synchronous peek for the editor catalog. Publishing happens on the actor;
/// reading it must not start a decode.
private final class ResidentPublication: @unchecked Sendable {
    private let lock = NSLock()
    private var country: String?
    private var revision: String?
    private var package: DisplayParts.LoadedPackage?

    func store(country: String, revision: String, package: DisplayParts.LoadedPackage) {
        lock.lock()
        self.country = country
        self.revision = revision
        self.package = package
        lock.unlock()
    }

    func clear() {
        lock.lock()
        country = nil
        revision = nil
        package = nil
        lock.unlock()
    }

    func package(country: String, revision: String) -> DisplayParts.LoadedPackage? {
        lock.lock()
        defer { lock.unlock() }
        guard self.country == country, self.revision == revision else { return nil }
        return package
    }
}

/// Waits for a shared load. Cancelling this waiter resumes only this waiter.
private func joinShared<T: Sendable>(_ task: Task<T, Error>) async throws -> T {
    let holder = JoinHolder<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let once = OnceResume(continuation)
            holder.store(once)
            Task {
                do { once.resume(returning: try await task.value) }
                catch { once.resume(throwing: error) }
            }
        }
    } onCancel: {
        holder.cancel()
    }
}

private final class JoinHolder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var once: OnceResume<T>?
    private var cancelled = false

    func store(_ once: OnceResume<T>) {
        lock.lock()
        self.once = once
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled { once.resume(throwing: CancellationError()) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let once = self.once
        lock.unlock()
        once?.resume(throwing: CancellationError())
    }
}

private final class OnceResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        resume(with: .success(value))
    }

    func resume(throwing error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<T, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
