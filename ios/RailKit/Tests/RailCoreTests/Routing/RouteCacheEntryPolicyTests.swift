import Foundation
import Testing
@testable import RailCore

@Suite("RouteCacheEntryPolicy")
struct RouteCacheEntryPolicyTests {
    @Test func failedTripIsNotSolvedAgainOnReload() {
        #expect(RouteCacheEntryPolicy.decide(
            hasDrawableSegments: false, storedFailure: "no route", retryFailures: false) == .reuseFailure)
    }

    @Test func repairSolvesAFailedTripOnce() {
        #expect(RouteCacheEntryPolicy.decide(
            hasDrawableSegments: false, storedFailure: "no route", retryFailures: true) == .solve)
        // The retry writes its new answer under the same key, so the next
        // plain reload reuses it again instead of solving a second time.
        #expect(RouteCacheEntryPolicy.decide(
            hasDrawableSegments: false, storedFailure: "no route", retryFailures: false) == .reuseFailure)
    }

    @Test func goodEntrySurvivesRepair() {
        for retry in [false, true] {
            #expect(RouteCacheEntryPolicy.decide(
                hasDrawableSegments: true, storedFailure: nil, retryFailures: retry) == .reuseSolved)
        }
    }

    @Test func entryWithNeitherGeometryNorFailureIsSolved() {
        #expect(RouteCacheEntryPolicy.decide(
            hasDrawableSegments: false, storedFailure: nil, retryFailures: false) == .solve)
    }

    @Test func onlyDefiniteFailuresAreStored() {
        #expect(RouteCacheEntryPolicy.shouldStoreFailure(drawnSegments: 0, hasResourceWarnings: false))
        #expect(!RouteCacheEntryPolicy.shouldStoreFailure(drawnSegments: 0, hasResourceWarnings: true))
        #expect(!RouteCacheEntryPolicy.shouldStoreFailure(drawnSegments: 2, hasResourceWarnings: false))
        #expect(RouteCacheEntryPolicy.failureReason(expectedSections: 3, physicalGapCount: 0).hasPrefix("no route"))
    }

    // The store lives in the app target, which host tests cannot import, so
    // these read its source the way the other structure guards do.
    private static let store: String = {
        let ios = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return (try? String(
            contentsOf: ios.appendingPathComponent("RailMap/Infrastructure/Persistence/RiddenRouteStore.swift"),
            encoding: .utf8)) ?? ""
    }()

    @Test func publicationIntervalIsFiveSeconds() {
        #expect(Self.store.contains("static let interval: Duration = .seconds(5)"))
        #expect(!Self.store.contains("static let interval: Duration = .milliseconds(750)"))
    }

    @Test func storeUsesThePolicyAndOnlyRepairAndResolveAgainRetryFailures() {
        #expect(Self.store.contains("RouteCacheEntryPolicy.decide("))
        #expect(Self.store.contains("load(trains: trains, priority: .utility, keepDrawn: true, retryFailures: true)"))
        #expect(Self.store.contains("resolveOne(train, scope: scope)"))
        #expect(Self.store.contains("loadCached([train], country: scope.code, retryFailures: true)"))
    }
}
