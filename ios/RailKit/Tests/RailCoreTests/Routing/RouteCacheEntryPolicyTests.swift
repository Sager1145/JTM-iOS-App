import Foundation
import Testing
@testable import RailCore

@Suite("RouteCacheEntryPolicy")
struct RouteCacheEntryPolicyTests {
    /// The cache file of one trip, as the store reads and writes it.
    private struct Entry: Equatable { var segments: Int; var failure: String? }

    /// One load of one trip against `entry`; returns the entry afterwards and
    /// whether the solver ran. `solve` is the solver's answer when it runs.
    private func load(
        _ entry: Entry?, retry: Bool, solve: (segments: Int, warnings: Bool)
    ) -> (entry: Entry?, solved: Bool) {
        if let entry,
           RouteCacheEntryPolicy.decide(
            hasDrawableSegments: entry.segments > 0, storedFailure: entry.failure,
            retryFailures: retry) != .solve {
            return (entry, false)
        }
        switch RouteCacheEntryPolicy.storeOutcome(
            drawnSegments: solve.segments, hasResourceWarnings: solve.warnings,
            expectedSections: 3, physicalGapCount: 0) {
        case .solved: return (Entry(segments: solve.segments, failure: nil), true)
        case .failure(let reason): return (Entry(segments: 0, failure: reason), true)
        case .skip: return (entry, true)
        }
    }

    @Test func failedTripIsNotSolvedAgainOnReload() {
        let first = load(nil, retry: false, solve: (0, false))
        #expect(first.solved && first.entry?.failure?.hasPrefix("no route") == true)
        let reload = load(first.entry, retry: false, solve: (2, false))
        #expect(!reload.solved)
        #expect(reload.entry?.failure != nil)
    }

    @Test func repairSolvesAFailedTripOnceAndItsAnswerReplacesTheFailure() {
        let failed = load(nil, retry: false, solve: (0, false)).entry
        let repaired = load(failed, retry: true, solve: (2, false))
        #expect(repaired.solved)
        #expect(repaired.entry == Entry(segments: 2, failure: nil))
        // A second Repair, or a plain reload, finds a good entry and does nothing.
        #expect(!load(repaired.entry, retry: true, solve: (0, false)).solved)
        #expect(!load(repaired.entry, retry: false, solve: (0, false)).solved)
    }

    @Test func repairThatFailsAgainKeepsAFailureAndReloadDoesNotRetryIt() {
        let failed = load(nil, retry: false, solve: (0, false)).entry
        let again = load(failed, retry: true, solve: (0, false))
        #expect(again.solved && again.entry?.failure != nil)
        #expect(!load(again.entry, retry: false, solve: (2, false)).solved)
    }

    @Test func goodEntrySurvivesRepair() {
        let good = Entry(segments: 2, failure: nil)
        for retry in [false, true] {
            let r = load(good, retry: retry, solve: (0, false))
            #expect(!r.solved && r.entry == good)
        }
    }

    @Test func entryWithNeitherGeometryNorFailureIsSolved() {
        #expect(RouteCacheEntryPolicy.decide(
            hasDrawableSegments: false, storedFailure: nil, retryFailures: false) == .solve)
    }

    @Test func onlyDefiniteFailuresAreStored() {
        // A warning (timetable, revision, an input that did not load) means
        // the empty answer may be transient: nothing is written.
        #expect(RouteCacheEntryPolicy.storeOutcome(
            drawnSegments: 0, hasResourceWarnings: true, expectedSections: 3, physicalGapCount: 0) == .skip)
        #expect(RouteCacheEntryPolicy.storeOutcome(
            drawnSegments: 2, hasResourceWarnings: true, expectedSections: 3, physicalGapCount: 0) == .solved)
        #expect(RouteCacheEntryPolicy.storeOutcome(
            drawnSegments: 0, hasResourceWarnings: false, expectedSections: 3, physicalGapCount: 1)
            == .failure(reason: "no route: 1 of 3 sections unproven"))
        #expect(RouteCacheEntryPolicy.failureReason(expectedSections: 3, physicalGapCount: 0).hasPrefix("no route"))
    }

    @Test func throttleAppliesFirstNonEmptyAtOnceAndNotAnEmptyOne() {
        var t = PartialPublicationThrottle()
        #expect(t.offer(isEmpty: true, immediate: false, now: .zero) == .skip)
        // The empty offer did not use up the slot.
        #expect(t.offer(isEmpty: false, immediate: false, now: .milliseconds(10)) == .applyNow)
        #expect(t.offer(isEmpty: false, immediate: false, now: .seconds(1)) == .scheduleFlush(after: .milliseconds(4010)))
        #expect(t.offer(isEmpty: false, immediate: false, now: .seconds(2)) == .replacePending)
        t.appliedPending(now: .milliseconds(5010))
        #expect(t.offer(isEmpty: false, immediate: false, now: .seconds(6)) == .scheduleFlush(after: .milliseconds(4010)))
    }

    @Test func throttleLetsTheSelectedTripBypassTheInterval() {
        var t = PartialPublicationThrottle()
        #expect(t.offer(isEmpty: false, immediate: false, now: .zero) == .applyNow)
        #expect(t.offer(isEmpty: false, immediate: false, now: .seconds(1)) == .scheduleFlush(after: .seconds(4)))
        #expect(t.offer(isEmpty: false, immediate: true, now: .seconds(2)) == .applyNow)
        // The immediate apply restarted the interval and cleared the held flush.
        #expect(t.offer(isEmpty: false, immediate: false, now: .seconds(3)) == .scheduleFlush(after: .seconds(4)))
    }

    @Test func publicationIntervalIsFiveSeconds() {
        #expect(PartialPublicationThrottle.interval == .seconds(5))
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

    @Test func storeUsesThePolicyAndThrottle() {
        #expect(Self.store.contains("RouteCacheEntryPolicy.decide("))
        #expect(Self.store.contains("RouteCacheEntryPolicy.storeOutcome("))
        #expect(Self.store.contains("PartialPublicationThrottle()"))
        #expect(!Self.store.contains("static let interval: Duration"))
    }

    @Test func onlyRepairAndResolveAgainRetryFailures() {
        #expect(Self.store.contains("load(trains: trains, priority: .utility, keepDrawn: true, retryFailures: true)"))
        #expect(Self.store.contains("resolveOne(train, scope: scope)"))
        #expect(Self.store.contains("loadCached([train], country: scope.code, retryFailures: true)"))
    }

    @Test func repairNeverAttachesToALoadThatReusesFailures() {
        let body = Self.store.components(separatedBy: "private func repairAll() {").last?
            .components(separatedBy: "private func rebuildAll()").first ?? ""
        #expect(body.contains("loadingRetriesFailures"))
        // Attaching is allowed only when the running load already retries.
        #expect(body.contains("loadingInputs == lastRequestedInputs, loadingRetriesFailures"))
        // A repair in progress makes a superseding load retry too.
        #expect(Self.store.contains("let retryFailures = retryFailures || (loadingInputs != nil && loadingRetriesFailures)"))
    }

    @Test func aMissingDisplayNetworkIsAWarningSoItIsNeverStoredAsAFailure() {
        #expect(Self.store.contains("degradedInputWarning"))
    }
}
