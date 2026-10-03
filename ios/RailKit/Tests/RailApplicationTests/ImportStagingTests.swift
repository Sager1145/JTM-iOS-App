import Foundation
import RailApplication
import RailCore
import Testing

struct ImportStagingTests {
    @Test func appendReturnsCompleteSnapshotAndImportedIDsOnly() throws {
        let current = try baseline()
        let progress = StagingProgressRecorder()
        let snapshot = try ImportStaging.stage(
            text: document([row("existing"), row("new")]), currentTrains: current,
            country: "jp", mode: .append, onProgress: progress.record)

        #expect(current.map(\.id) == ["existing"])
        #expect(snapshot.trains.map(\.id) == ["existing", "existing-2", "new"])
        #expect(snapshot.trains.first == current.first)
        #expect(snapshot.ids == ["existing-2", "new"])
        #expect(snapshot.selectedTrainID == nil)
        #expect(progress.completed == [0, 1, 2])
        #expect(progress.totals == [2, 2, 2])
        #expect(progress.trainIDs == [nil, "existing-2", "new"])
    }

    @Test func replaceReturnsOnlyImportedRowsAndEngineSelection() throws {
        let current = try baseline()
        let progress = StagingProgressRecorder()
        let snapshot = try ImportStaging.stage(
            text: document([row("existing"), row("existing")]), currentTrains: current,
            country: "jp", mode: .replaceAll, onProgress: progress.record)

        #expect(current.map(\.id) == ["existing"])
        #expect(snapshot.trains.map(\.id) == ["existing", "existing-2"])
        #expect(snapshot.ids == ["existing", "existing-2"])
        #expect(snapshot.selectedTrainID == "existing")
        // The engine's prepare and done events are filtered out.
        #expect(progress.completed == [1, 2])
        #expect(progress.totals == [2, 2])
        #expect(progress.trainIDs == [nil, nil])
    }

    @Test(arguments: ImportPreflight.Mode.allCases)
    func failedImportNeverReturnsPartialCandidate(mode: ImportPreflight.Mode) throws {
        let current = try baseline()
        let progress = StagingProgressRecorder()
        let bad = row("bad").replacingOccurrences(
            of: "\"n02_station_code\":\"123456\"", with: "\"n02_station_code\":\"bad\"")
        #expect(throws: TrainValidation.ValidationError.self) {
            try ImportStaging.stage(
                text: document([row("good"), bad, row("last")]), currentTrains: current,
                country: "jp", mode: mode, onProgress: progress.record)
        }
        #expect(current.map(\.id) == ["existing"])
        #expect(progress.completed == (mode == .append ? [0, 1] : [1]))
        #expect(progress.trainIDs == (mode == .append ? [nil, "good"] : [nil]))
    }

    @Test func regionNormalizationRunsWithoutAppRegionStamping() throws {
        let input = row("taiwan").replacingOccurrences(
            of: "\"number\":\"Local\"",
            with: "\"number\":\"Local\",\"company\":\"臺灣鐵路管理局\"")
        let snapshot = try ImportStaging.stage(
            text: input, currentTrains: [], country: "tw", mode: .append)
        let train = try #require(snapshot.trains.first)
        #expect(train.company == "台鐵")
        #expect(train.region == nil)
        #expect(train.date == TrainValidation.undated)
    }

    @Test func replacementEmptyErrorNamesChosenSource() throws {
        do {
            _ = try ImportStaging.stage(
                text: "[]", currentTrains: try baseline(), country: "jp",
                mode: .replaceAll, sourceLabel: "backup.json")
            Issue.record("Empty replacement unexpectedly returned a candidate")
        } catch {
            #expect(ImportPreflight.message(of: error) == "backup.json contains no trains.")
        }
    }

    @Test(arguments: ImportPreflight.Mode.allCases)
    func stagingLeavesCancellationAcceptanceToCaller(mode: ImportPreflight.Mode) async throws {
        let current = try baseline()
        let text = document([row("first"), row("second")])
        let progress = StagingProgressRecorder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let snapshot = try ImportStaging.stage(
                text: text, currentTrains: current, country: "jp", mode: mode,
                onProgress: progress.record)
            // The real store retains this check immediately before accepting
            // the candidate. The scratch engine itself keeps running.
            #expect(snapshot.ids == ["first", "second"])
            try Task.checkCancellation()
            return snapshot
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled caller unexpectedly accepted the candidate")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(progress.completed == (mode == .append ? [0, 1, 2] : [1, 2]))
        #expect(current.map(\.id) == ["existing"])
    }

    private func baseline() throws -> [Train] {
        var session = ImportEngine.Session(country: "jp")
        try session.appendImportedTrain(TrainValidation.JSON.parse(row("existing")))
        return session.trains
    }

    private func row(_ id: String) -> String {
        """
        {"id":"\(id)","number":"Local","origin":"A","destination":"B","stops":[
        {"name":"A","n02_station_code":"123456","departure":"08:00","ride_segment":true},
        {"name":"B","n02_station_code":"123457","arrival":"09:00"}]}
        """
    }

    private func document(_ rows: [String]) -> String {
        "[\(rows.joined(separator: ","))]"
    }
}

private final class StagingProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [ImportStaging.Progress] = []

    func record(_ progress: ImportStaging.Progress) {
        lock.withLock { ticks.append(progress) }
    }

    var completed: [Int] { lock.withLock { ticks.map(\.completed) } }
    var totals: [Int] { lock.withLock { ticks.map(\.total) } }
    var trainIDs: [String?] { lock.withLock { ticks.map(\.trainID) } }
}
