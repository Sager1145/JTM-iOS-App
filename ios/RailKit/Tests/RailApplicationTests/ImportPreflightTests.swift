import Foundation
import RailApplication
import RailCore
import Testing

struct ImportPreflightTests {
    @Test func appendPlansRenamesWithoutChangingSnapshot() throws {
        let current = try trains([row("ride"), row("ride-2")])
        let snapshot = current
        let progress = ProgressRecorder()
        let report = try ImportPreflight.inspect(
            text: document([row("ride"), row("ride")]),
            currentTrains: current, country: "jp", mode: .append
        ) { completed, total in
            progress.record(completed, total)
        }

        #expect(current == snapshot)
        #expect(report.mode == .append)
        #expect(report.country == "jp")
        #expect(report.schemaVersion == TrainValidation.schemaVersion)
        #expect(report.documentCount == 2)
        #expect(report.added == 2)
        #expect(report.kept == 2)
        #expect(report.replaced == 0)
        #expect(report.renames.map(\.from) == ["ride", "ride"])
        #expect(report.renames.map(\.to) == ["ride-3", "ride-4"])
        #expect(report.isCommittable)
        #expect(progress.completed == [1, 2])
        #expect(progress.totals == [2, 2])
    }

    @Test func replaceUsesEmptyScratchStoreAndRenamesDocumentDuplicates() throws {
        let current = try trains([row("ride"), row("old")])
        let report = try ImportPreflight.inspect(
            text: document([row("ride"), row("ride")]),
            currentTrains: current, country: "tw", mode: .replaceAll)

        #expect(report.country == "tw")
        #expect(report.added == 2)
        #expect(report.replaced == 2)
        #expect(report.kept == 0)
        #expect(report.renames.map(\.from) == ["ride"])
        #expect(report.renames.map(\.to) == ["ride-2"])
        #expect(report.issues.isEmpty)
        #expect(report.isCommittable)
        #expect(current.map(\.id) == ["ride", "old"])
    }

    @Test func issuesLocateDocumentRowsDespiteExistingStoreOffset() throws {
        let current = try trains([row("existing"), row("other")])
        let badStop = row("bad-stop").replacingOccurrences(
            of: "\"n02_station_code\":\"123456\"", with: "\"n02_station_code\":\"bad\"")
        let badTrain = row("bad-row").replacingOccurrences(
            of: "\"number\":\"Local\"", with: "\"number\":\"Local\",\"unknown\":true")
        let progress = ProgressRecorder()
        let report = try ImportPreflight.inspect(
            text: document([row("good"), badStop, badTrain, row("last")]),
            currentTrains: current, country: "jp", mode: .append
        ) { done, total in progress.record(done, total) }

        #expect(report.documentCount == 4)
        #expect(report.added == 2)
        #expect(report.kept == 2)
        #expect(!report.isCommittable)
        #expect(report.issues.count == 2)
        let stopIssue = try #require(report.issues.first)
        #expect(stopIssue.row == 1)
        #expect(stopIssue.stop == 1)
        #expect(stopIssue.path == "trains[1].stops[0]")
        #expect(stopIssue.trainID == "bad-stop")
        #expect(stopIssue.detail == "n02_station_code must be a six-digit N02_005c, a TDX StationUID, or null.")
        let rowIssue = report.issues[1]
        #expect(rowIssue.row == 2)
        #expect(rowIssue.stop == nil)
        #expect(rowIssue.path == "trains[2]")
        #expect(rowIssue.trainID == "bad-row")
        #expect(rowIssue.detail == "Train contains unsupported field: unknown.")
        #expect(progress.completed == [1, 2, 3, 4])
        #expect(current.map(\.id) == ["existing", "other"])
    }

    @Test func malformedDocumentIsReportedAtRootAndKeepsCurrentCount() throws {
        let current = try trains([row("existing")])
        for mode in ImportPreflight.Mode.allCases {
            let report = try ImportPreflight.inspect(
                text: "{", currentTrains: current, country: "jp", mode: mode)
            #expect(report.documentCount == 0)
            #expect(report.added == 0)
            #expect(report.replaced == 0)
            #expect(report.kept == 1)
            #expect(report.schemaVersion == nil)
            #expect(!report.isCommittable)
            let issue = try #require(report.issues.first)
            #expect(issue.row == nil)
            #expect(issue.stop == nil)
            #expect(issue.path == nil)
            #expect(issue.trainID == nil)
            #expect(!issue.detail.isEmpty)
        }
    }

    @Test func emptyDocumentCannotReplaceOrAppend() throws {
        let current = try trains([row("existing")])
        for mode in ImportPreflight.Mode.allCases {
            let report = try ImportPreflight.inspect(
                text: "[]", currentTrains: current, country: "jp", mode: mode)
            #expect(report.documentCount == 0)
            #expect(report.added == 0)
            #expect(report.replaced == (mode == .replaceAll ? 1 : 0))
            #expect(report.kept == (mode == .append ? 1 : 0))
            #expect(!report.isCommittable)
            #expect(report.issues.map(\.detail) == ["The document contains no trains."])
            #expect(report.issues.first?.path == nil)
        }
    }

    @Test func normalizedSingleTrainUsesSameFrontDoorsAsCommit() throws {
        // Numeric train_type is normalized before validation; the raw
        // validator alone rejects it. Trimmed IDs use the engine's rule.
        let text = row("  ride  ").replacingOccurrences(
            of: "\"number\":\"Local\"", with: "\"number\":\"Local\",\"train_type\":7")
        let report = try ImportPreflight.inspect(
            text: text, currentTrains: [], country: "jp", mode: .replaceAll)
        #expect(report.documentCount == 1)
        #expect(report.added == 1)
        #expect(report.renames.map(\.from) == ["  ride  "])
        #expect(report.renames.map(\.to) == ["ride"])
        #expect(report.isCommittable)
    }

    @Test func cancelledTaskStopsBeforeFirstRow() async {
        let progress = ProgressRecorder()
        let input = document([row("first"), row("second")])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImportPreflight.inspect(
                text: input, currentTrains: [], country: "jp", mode: .append
            ) { done, total in progress.record(done, total) }
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled preflight unexpectedly produced a report")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(progress.completed.isEmpty)
    }

    @Test func cancellationBetweenRowsStopsProgressAndPreservesSnapshot() async throws {
        let current = try trains([row("existing")])
        let input = document([row("first"), row("second"), row("third")])
        let progress = ProgressRecorder()
        let task = Task {
            try ImportPreflight.inspect(
                text: input, currentTrains: current, country: "jp", mode: .replaceAll
            ) { done, total in
                progress.record(done, total)
                if done == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled preflight unexpectedly produced a report")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(progress.completed == [1])
        #expect(progress.totals == [3])
        #expect(current.map(\.id) == ["existing"])
    }

    @Test func retiredRegionsAndUntaggedIdentitiesCannotBeImported() throws {
        let current = try trains([row("existing")])
        let retired = [
            row("us-ride").replacingOccurrences(of: "\"number\":", with: "\"region\":\"us\",\"number\":"),
            row("ca-ride").replacingOccurrences(of: "\"number\":", with: "\"region\":\"ca\",\"number\":"),
            row("station").replacingOccurrences(of: "123456", with: "US-OFFICIAL-RETIRED"),
            row("section").replacingOccurrences(
                of: "\"number\":", with: "\"route_sections\":[{\"line_ids\":[\"ca-retired-line\"]}],\"number\":")
        ]
        for mode in ImportPreflight.Mode.allCases {
            let report = try ImportPreflight.inspect(
                text: document(retired), currentTrains: current, country: "jp", mode: mode)
            #expect(!report.isCommittable)
            #expect(report.added == 0)
            #expect(report.issues.count == retired.count)
            #expect(report.issues.allSatisfy { $0.detail.contains("Unsupported") })
            #expect(current.map(\.id) == ["existing"])
        }
    }

    @Test func validationErrorUsesItsDiagnosticMessage() {
        let error = TrainValidation.ValidationError(message: "Train 2: number is required.")
        #expect(ImportPreflight.message(of: error) == "Train 2: number is required.")
    }

    private func row(_ id: String) -> String {
        """
        {"id":"\(id)","number":"Local","origin":"A","destination":"B","stops":[
        {"name":"A","n02_station_code":"123456","departure":"08:00","ride_segment":true},
        {"name":"B","n02_station_code":"123457","arrival":"09:00"}]}
        """
    }

    private func document(_ rows: [String]) -> String {
        "{\"schema_version\":\"\(TrainValidation.schemaVersion)\",\"trains\":[\(rows.joined(separator: ","))]}"
    }

    private func trains(_ rows: [String]) throws -> [Train] {
        var session = ImportEngine.Session(country: "jp")
        for row in rows { try session.appendImportedTrain(TrainValidation.JSON.parse(row)) }
        return session.trains
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [(Int, Int)] = []

    func record(_ completed: Int, _ total: Int) {
        lock.withLock { ticks.append((completed, total)) }
    }

    var completed: [Int] { lock.withLock { ticks.map(\.0) } }
    var totals: [Int] { lock.withLock { ticks.map(\.1) } }
}
