import Foundation
import Testing

/// The memory-warning path: one relief, after the app's own frees.
@Suite("RegressionGuardMemoryPressure")
struct RegressionGuardMemoryPressure {
    private static let ios: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RegressionGuards
            .deletingLastPathComponent() // RailCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RailKit
            .deletingLastPathComponent() // ios
    }()

    private static func read(_ path: String) -> String {
        (try? String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    @Test func warningHandlerSchedulesTheReliefInsteadOfCallingIt() throws {
        let c = Self.read("RailMap/Map/RailMapCoordinator.swift")
        let start = try #require(c.range(of: "func observeMemoryWarnings()"))
        let rest = c[start.upperBound...]
        let end = try #require(rest.range(of: "private var neighbourPrebuildTarget"))
        let handler = String(rest[..<end.lowerBound])
        #expect(handler.contains("scheduleMemoryRelief(firstDelay: .milliseconds(500))"))
        #expect(!handler.contains("malloc_zone_pressure_relief"))
    }

    @Test func appShellTrimsTheNetworkBeforeItsDetachedReleases() throws {
        let s = Self.read("RailMap/App/AppShell.swift")
        let trim = try #require(s.range(of: "network.trimForMemoryPressure()"))
        let detached = try #require(s.range(of: "await RiddenRouteStore.releaseCachesForMemoryPressure()"))
        #expect(trim.lowerBound < detached.lowerBound)
    }

    @Test func trimIsOneEvictionPassWithABudgetOfZero() {
        let n = Self.read("RailMap/Infrastructure/Network/RailNetworkStore.swift")
        #expect(n.contains("func trimForMemoryPressure()"))
        #expect(n.contains("evictIfNeeded(index: index, budget: 0, visibleRect: visibleRectProvider?())"))
    }

    @Test func trimSuspendsThePrefetchRingAndProtectsTheVisibleRect() throws {
        let n = Self.read("RailMap/Infrastructure/Network/RailNetworkStore.swift")
        let trim = try #require(n.range(of: "func trimForMemoryPressure()"))
        let body = String(n[trim.upperBound...].prefix(900))
        #expect(body.contains("prefetchGate.suspend("))
        #expect(body.contains("visibleRect: visibleRectProvider?()"))
        #expect(n.contains("prefetchGate.noteRequest("))
        #expect(n.contains("guard !prefetchGate.isPrefetchSuspended else { return }"))
        #expect(n.contains("MemoryTrimProtection.protectedRects("))
        let w = Self.read("RailMap/Workspace/RailWorkspaceView.swift")
        #expect(w.contains("store.visibleRectProvider ="))
    }
}
