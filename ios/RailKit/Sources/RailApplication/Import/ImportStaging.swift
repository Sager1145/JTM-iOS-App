import Foundation
import RailCore

/// Runs an import against a value snapshot and returns a candidate working
/// set. The caller owns when the candidate may replace its live store.
public enum ImportStaging {
    public struct Progress: Equatable, Sendable {
        public let completed: Int
        public let total: Int
        /// Replace reports only counts. Append's preparation tick also has
        /// no train ID; its engine label is a localization key.
        public let trainID: String?
    }

    public struct Snapshot: Sendable {
        public let trains: [Train]
        public let selectedTrainID: String?
        /// Imported IDs only, excluding the baseline in append mode.
        public let ids: [String]
    }

    /// Drives the existing engine door without changing its event order or
    /// validation rules. Progress is synchronous on the caller's executor.
    ///
    /// The engine runs to completion even if its task is cancelled. The
    /// caller must check cancellation before accepting the returned snapshot,
    /// so cancellation cannot publish a partially imported store.
    public static func stage(
        text: String,
        currentTrains: [Train],
        country: String,
        mode: ImportPreflight.Mode,
        sourceLabel: String = "JSON",
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) throws -> Snapshot {
        var session = ImportEngine.Session(
            trains: mode == .append ? currentTrains : [],
            selectedTrainID: nil,
            focusedTrainID: nil,
            selectedDate: Dates.allDates,
            country: country)

        switch mode {
        case .replaceAll:
            // Only loading carries per-journey progress. The prepare/done
            // bookends must not reset or duplicate the caller's progress.
            session.onEvent = { event in
                guard case .progressBar(let count, let total, let label) = event,
                    label == ImportEngine.MessageKey.loading
                else { return }
                onProgress(Progress(completed: count, total: total, trainID: nil))
            }
            try session.replaceTrainStoreFromJSONText(text, sourceLabel: sourceLabel)
            return Snapshot(
                trains: session.trains,
                selectedTrainID: session.selectedTrainID,
                ids: session.trains.map(\.id))
        case .append:
            let document = try TrainValidation.parseImportedCanonicalStore(text: text)
            let result = try session.importCanonicalStoreAppendProgressive(document) { progress in
                onProgress(
                    Progress(
                        completed: progress.count, total: progress.total,
                        trainID: progress.count == 0 ? nil : progress.id))
            }
            return Snapshot(
                trains: session.trains,
                selectedTrainID: session.selectedTrainID,
                ids: result.ids)
        }
    }
}
