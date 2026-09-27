import Foundation
import Testing

@testable import RailCore

/// Acceptance ledger for service-pattern reports.
///
/// `runComplete` means every expected case has a result. It does not mean
/// every dimension passed. Historical via stays unverified unless a separate
/// evidence comparison says otherwise. These tests plant faults directly and
/// do not run the catalog solver.
@Suite struct TrainServicePatternReportContractTests {
    private let forward = "p|2019-03-16|forward|default"
    private let reverse = "p|2019-03-16|reverse|default"

    @Test func sameNameDifferentCodeFailsReference() {
        #expect(TrainServicePatternAcceptance.referenceIntegrity(
            expectedCode: "001632", actualCode: "001632") == "passed")
        #expect(TrainServicePatternAcceptance.referenceIntegrity(
            expectedCode: "001632", actualCode: "nearby-platform") == "failed")
        #expect(TrainServicePatternAcceptance.referenceIntegrity(
            expectedCode: "001632", actualCode: nil) == "failed")
        #expect(TrainServicePatternAcceptance.referenceIntegrity(
            expectedCode: "", actualCode: "") == "failed")
    }

    @Test func emptyNonExemptSolveIsARouteFailure() {
        #expect(TrainServicePatternAcceptance.routeConnectivity(
            hasRideDate: true, failedLegCount: 1, unsolvableLegCount: 0) == "failed")
        #expect(TrainServicePatternAcceptance.routeConnectivity(
            hasRideDate: true, failedLegCount: 0, unsolvableLegCount: 1) == "incomplete")
        #expect(TrainServicePatternAcceptance.routeConnectivity(
            hasRideDate: false, failedLegCount: 0, unsolvableLegCount: 0) == "unverified")
    }

    @Test func connectivityDoesNotVerifyHistoricalVia() {
        #expect(TrainServicePatternAcceptance.routeConnectivity(
            hasRideDate: true, failedLegCount: 0, unsolvableLegCount: 0) == "passed")
        let historical = TrainServicePatternAcceptance.historicalCorrectness(
            independentEvidenceMatches: false)
        #expect(historical != "passed")
        #expect(historical.hasPrefix("unverified"))
    }

    @Test func directionCasesDoNotOverwrite() {
        var ledger = TrainServicePatternAcceptance.Ledger()
        ledger.record(storageKey: forward, result: ["routeConnectivity": "passed"])
        ledger.record(storageKey: reverse, result: ["routeConnectivity": "passed"])
        ledger.record(storageKey: forward, result: ["routeConnectivity": "failed"])
        #expect(ledger.cases[forward]?["routeConnectivity"] as? String == "failed")
        #expect(ledger.cases[reverse]?["routeConnectivity"] as? String == "passed")
        #expect(ledger.cases.count == 2)
    }

    @Test func missingExpectedCaseIsNotACompleteRun() {
        let expected: Set = [forward, reverse]
        var ledger = TrainServicePatternAcceptance.Ledger()
        ledger.record(storageKey: forward, result: result(connectivity: "passed"))
        let partial = document(ledger: ledger, runId: "run-1", expected: expected)
        #expect((partial["_metadata"] as? [String: Any])?["runComplete"] as? Bool == false)
        #expect(TrainServicePatternAcceptance.accepts(
            document: partial, runId: "run-1", expectedCaseKeys: expected) == false)

        ledger.record(storageKey: reverse, result: result(connectivity: "passed"))
        let complete = document(ledger: ledger, runId: "run-1", expected: expected)
        #expect(TrainServicePatternAcceptance.accepts(
            document: complete, runId: "run-1", expectedCaseKeys: expected))
    }

    @Test func unwritableReportDoesNotAcceptThePreviousFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pattern-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let url = root.appendingPathComponent("report.json")
        let expected: Set = [forward, reverse]
        var old = TrainServicePatternAcceptance.Ledger()
        old.record(storageKey: forward, result: result(connectivity: "passed"))
        old.record(storageKey: reverse, result: result(connectivity: "passed"))
        try TrainServicePatternAcceptance.write(
            document: document(ledger: old, runId: "old-run", expected: expected), to: url)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        var replacement = TrainServicePatternAcceptance.Ledger()
        replacement.record(storageKey: forward, result: result(connectivity: "passed"))
        replacement.record(storageKey: reverse, result: result(connectivity: "passed"))
        #expect(throws: Error.self) {
            try TrainServicePatternAcceptance.write(
                document: document(ledger: replacement, runId: "new-run", expected: expected), to: url)
        }

        let preserved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let metadata = preserved?["_metadata"] as? [String: Any]
        #expect(metadata?["runId"] as? String == "old-run")
        #expect(TrainServicePatternAcceptance.accepts(
            document: preserved ?? [:], runId: "new-run", expectedCaseKeys: expected) == false)
    }

    private func result(connectivity: String) -> [String: Any] {
        [
            "routeConnectivity": connectivity,
            "historicalCorrectness": TrainServicePatternAcceptance.historicalCorrectness(
                independentEvidenceMatches: false),
            "referenceIntegrity": "passed",
        ]
    }

    private func document(
        ledger: TrainServicePatternAcceptance.Ledger, runId: String, expected: Set<String>
    ) -> [String: Any] {
        [
            "_cases": TrainServicePatternAcceptance.caseObject(ledger.cases),
            "_metadata": [
                "runId": runId,
                "runComplete": ledger.runComplete(expected: expected),
                "expectedCaseCount": expected.count,
                "completedCaseCount": ledger.cases.count,
            ],
        ]
    }
}
