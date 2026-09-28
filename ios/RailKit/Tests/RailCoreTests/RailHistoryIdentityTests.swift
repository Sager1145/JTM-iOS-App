import Foundation
import Testing

@testable import RailCore

struct RailHistoryIdentityTests {
    private func context(
        rideDate: String? = "2026-09-27",
        historyHashes: String? = nil
    ) throws -> RailPrecomputedSolverContext {
        let hashesField = historyHashes.map { ", \"history_hashes\": \($0)" } ?? ""
        let rideDateValue = rideDate.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "solver_version": "22",
          "route_cache_digest": "route-a",
          "ride_date": \(rideDateValue),
          "history_revisions": {"jp": "2026-09-27.2"}\(hashesField)
        }
        """
        return try JSONDecoder().decode(
            RailPrecomputedSolverContext.self,
            from: Data(json.utf8))
    }

    @Test func sameRevisionWithDifferentContentHashHasDifferentCanonicalIdentity() {
        let first = RailHistoryRevisionSet(
            ["jp": "2026-09-27.2"], contentHashes: ["jp": "hash-a"])
        let second = RailHistoryRevisionSet(
            ["jp": "2026-09-27.2"], contentHashes: ["jp": "hash-b"])
        #expect(first.canonical != second.canonical)
        #expect(RailHistoryRevisionSet(["jp": "2026-09-27.2"]).canonical == "jp:2026-09-27.2")
    }

    @Test func matchingExpectedHistoryHashIsAccepted() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-27.2"])
        let solverContext = try context(historyHashes: "{\"jp\": \"hash-a\"}")
        #expect(RailPrecomputedRouteGate.accepts(
            solverContext,
            expectedDigest: "route-a",
            solverVersion: "22",
            rideDate: "2026-09-27",
            revisions: revisions,
            expectedHashes: ["jp": "hash-a"]
        ))
    }

    @Test func missingOrDifferentHistoryHashIsRejectedWhenExpected() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-27.2"])
        let missing = try context()
        let different = try context(historyHashes: "{\"jp\": \"hash-b\"}")
        for solverContext in [missing, different] {
            #expect(!RailPrecomputedRouteGate.accepts(
                solverContext,
                expectedDigest: "route-a",
                solverVersion: "22",
                rideDate: "2026-09-27",
                revisions: revisions,
                expectedHashes: ["jp": "hash-a"]
            ))
        }
    }

    @Test func oldGateCallRemainsCompatibleWithoutExpectedHashes() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-27.2"])
        #expect(RailPrecomputedRouteGate.accepts(
            try context(),
            expectedDigest: "route-a",
            solverVersion: "22",
            rideDate: "2026-09-27",
            revisions: revisions
        ))
    }

    @Test func hashAttestationFailsClosedForUndatedOrMissingContext() throws {
        let revisions = RailHistoryRevisionSet(["jp": "2026-09-27.2"])
        let undatedWrongHash = try context(
            rideDate: nil, historyHashes: "{\"jp\": \"hash-b\"}")
        #expect(!RailPrecomputedRouteGate.accepts(
            undatedWrongHash,
            expectedDigest: "route-a",
            solverVersion: "22",
            rideDate: nil,
            revisions: revisions,
            expectedHashes: ["jp": "hash-a"]
        ))
        #expect(!RailPrecomputedRouteGate.accepts(
            nil,
            expectedDigest: "route-a",
            solverVersion: "22",
            rideDate: nil,
            revisions: revisions,
            expectedHashes: ["jp": "hash-a"]
        ))
    }
}
