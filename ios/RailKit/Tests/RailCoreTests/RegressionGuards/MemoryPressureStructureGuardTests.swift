import Foundation
import RailTestSupport
import Testing

/// The memory-warning path: one relief, after the app's own frees.
@Suite("RegressionGuardMemoryPressure")
struct RegressionGuardMemoryPressure {
    @Test func warningHandlerSchedulesTheReliefInsteadOfCallingIt() throws {
        let c = SourceFiles.textRecording("RailMap/Map/RailMapCoordinator.swift")
        let start = try #require(c.range(of: "func observeMemoryWarnings()"))
        let rest = c[start.upperBound...]
        let end = try #require(rest.range(of: "private var neighbourPrebuildTarget"))
        let handler = String(rest[..<end.lowerBound])
        #expect(handler.contains("scheduleMemoryRelief(firstDelay: .milliseconds(500))"))
        #expect(!handler.contains("malloc_zone_pressure_relief"))
    }

    @Test func appShellTrimsTheNetworkBeforeItsDetachedReleases() throws {
        let s = SourceFiles.textRecording("RailMap/App/AppShell.swift")
        let trim = try #require(s.range(of: "network.trimForMemoryPressure()"))
        let detached = try #require(s.range(of: "await RiddenRouteStore.releaseCachesForMemoryPressure()"))
        #expect(trim.lowerBound < detached.lowerBound)
    }

    @Test func trimIsOneEvictionPassWithABudgetOfZero() {
        let n = SourceFiles.textRecording("RailMap/Infrastructure/Network/RailNetworkStore.swift")
        #expect(n.contains("func trimForMemoryPressure()"))
        #expect(n.contains("evictIfNeeded(index: index, budget: 0, visibleRect: visibleRectProvider?())"))
    }

    @Test func trimSuspendsThePrefetchRingAndProtectsTheVisibleRect() throws {
        let n = SourceFiles.textRecording("RailMap/Infrastructure/Network/RailNetworkStore.swift")
        let trim = try #require(n.range(of: "func trimForMemoryPressure()"))
        let body = String(n[trim.upperBound...].prefix(900))
        #expect(body.contains("prefetchGate.suspend("))
        #expect(body.contains("visibleRect: visibleRectProvider?()"))
        #expect(n.contains("prefetchGate.noteRequest("))
        #expect(n.contains("guard !prefetchGate.isPrefetchSuspended else { return }"))
        #expect(n.contains("MemoryTrimProtection.protectedRects("))
        let w = SourceFiles.textRecording("RailMap/Workspace/RailWorkspaceView.swift")
        #expect(w.contains("store.visibleRectProvider ="))
    }
}
