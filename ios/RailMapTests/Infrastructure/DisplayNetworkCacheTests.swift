import Foundation
import RailCore
import Testing
@testable import RailMap

/// The shared package loader. These call the real bundle decode, not a stand-in.
@Suite(.serialized)
struct DisplayNetworkCacheTests {
    private let cache = DisplayNetworkCache.shared

    @Test func concurrentRequestsDecodeOnce() async throws {
        try await reset()
        async let first = cache.package(country: "mo")
        async let second = cache.package(country: "mo")
        let (left, right) = try await (first, second)
        #expect(await cache.testingFullDecodeCount() == 1)
        #expect(!left.package.lines.isEmpty)
        #expect(left.package.lines.count == right.package.lines.count)
    }

    @Test func failedLoadIsNotCachedAndTheNextRequestSucceeds() async throws {
        try await reset()
        await cache.testingFailNextPackageLoad()
        do {
            _ = try await cache.package(country: "mo")
            Issue.record("a forced failure was stored as a package")
        } catch {
            #expect(await cache.testingFullDecodeCount() == 0)
        }
        let loaded = try await cache.package(country: "mo")
        #expect(!loaded.package.lines.isEmpty)
        #expect(await cache.testingFullDecodeCount() == 1)
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 1)
    }

    @Test func revisionChangeDecodesAgain() async throws {
        try await reset()
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 1)
        await cache.testingSetRevisions(RailResourceRevisions(
            regions: ["mo": "changed-revision"], timetableRevision: "timetable"))
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 2)
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 2)
    }

    @Test func evictingTheResidentRegionDecodesAgainOnReload() async throws {
        try await reset()
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 1)
        _ = try await cache.package(country: "hk")
        #expect(await cache.testingFullDecodeCount() == 2)
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 3)
    }

    @Test func layoutAndNetworkReuseTheSameDecode() async throws {
        try await reset()
        let (loaded, parts) = try await cache.generation(country: "mo")
        _ = try await cache.lineParts(country: "mo")
        let network = try await cache.network(country: "mo")
        _ = try await cache.network(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 1)
        #expect(await cache.testingLayoutCount() == 1)
        #expect(parts.count == loaded.package.lines.count)
        #expect(network.lines.count == loaded.package.lines.count)
        #expect(network.lines.map(\.lineId) == loaded.package.lines.map(\.id))
    }

    @Test func cancellingOneSubscriberKeepsTheSharedDecode() async throws {
        try await reset()
        await cache.testingBlockNextLoad()
        let first = Task { try await cache.package(country: "mo") }
        let second = Task { try await cache.package(country: "mo") }
        await cache.testingWaitUntilLoadBlocked()
        first.cancel()
        await cache.testingUnblockLoad()
        let loaded = try await second.value
        #expect(await cache.testingFullDecodeCount() == 1)
        #expect(!loaded.package.lines.isEmpty)
        _ = try await cache.package(country: "mo")
        #expect(await cache.testingFullDecodeCount() == 1)
        _ = await first.result
    }

    @Test func damagedStationReadingsAreReportedAndTheNextLoadRecovers() async {
        let store = StationReadingsStore()
        await store.testingReplaceResource(Data("{".utf8), for: "mo")
        let failed = await store.availability(for: "mo")
        guard case .unavailable(let message) = failed else {
            Issue.record("damaged station readings were stored as a table")
            return
        }
        #expect(!message.isEmpty)
        #expect(await store.testingHasCachedTable(for: "mo") == false)
        await store.testingReplaceResource(nil, for: "mo")
        let recovered = await store.availability(for: "mo")
        guard case .ready(let table) = recovered else {
            Issue.record("station readings did not recover after the damaged file was removed")
            return
        }
        #expect(table.country == "MO")
        #expect(await store.testingHasCachedTable(for: "mo"))
    }

    @Test func catalogDoesNotTriggerAFullDecode() async throws {
        try await reset()
        testingResetEditorCatalogCache()
        let cold = try loadCatalog(for: .mo)
        #expect(await cache.testingFullDecodeCount() == 0)
        #expect(!cold.lines(in: "mo").isEmpty)

        testingResetEditorCatalogCache()
        _ = try await cache.package(country: "mo")
        let decodes = await cache.testingFullDecodeCount()
        let warm = try loadCatalog(for: .mo)
        #expect(await cache.testingFullDecodeCount() == decodes)
        #expect(warm.lines(in: "mo").count == cold.lines(in: "mo").count)
    }

    private func reset() async throws {
        await cache.testingReset()
    }
}
