import Foundation
import RailCore

/// The dry run: everything the import would do, computed without doing it.
///
/// The web app's 驗證匯入 JSON button (`validateTextareaJson`) answers one
/// question — "would this parse?" — and answers it with a single sentence.
/// The spec asks for more before a commit: which region, how many journeys,
/// whether they replace or join what is already here, and how many problems
/// there are (§5.8, §8.7). All four are computable, and none of them needs to
/// touch the live store, because ``ImportEngine/Session`` is a value: a scratch
/// copy seeded with the current trains answers "what would happen" exactly,
/// and is then thrown away.
///
/// This deliberately runs the SAME two front doors the commit runs —
/// `appendImportedTrain` normalises and validates in the one composed order
/// documented in `Import.swift` — rather than a second, looser check of its
/// own. A preflight that accepted what the commit rejects would be worse than
/// no preflight.
public enum ImportPreflight {

    /// The two import shapes the ported engine actually has.
    ///
    /// `replaceAll` is `replaceTrainStoreFromJsonText` — the web app's 打開本地
    /// JSON path. `append` is `importCanonicalStoreAppendProgressive` — the
    /// web app's 開始載入／逐條匯入 button.
    ///
    /// There is no "update by id" mode, and this enum does not invent one:
    /// `makeUniqueTrainId` RENAMES an incoming id that collides, so an
    /// appended journey never overwrites an existing one. Calling the mode
    /// "merge by id" in the interface would be a promise the engine does not
    /// keep.
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case replaceAll
        case append

        public var id: String { rawValue }
    }

    /// One problem, and where in the document it is.
    ///
    /// §8.7 requires a JSON path, a journey id or a stop number — not a
    /// message on its own. The engine's own message names a position in the
    /// *resulting store* (`Train 47`), which in append mode is not the row the
    /// reader has to go and fix; the row index is recovered here from the loop
    /// and the engine's prefix is replaced with a document-relative path.
    public struct Issue: Identifiable, Hashable, Sendable {
        /// The row in `trains`, or nil for a problem with the document itself.
        public var row: Int?
        public var stop: Int?
        /// The id the document gave this journey, before any renaming.
        public var trainID: String?
        public var detail: String

        public var id: String { "\(row.map(String.init) ?? "root")|\(stop.map(String.init) ?? "-")|\(detail)" }

        /// `trains[12].stops[3]` — the path into the document as written.
        public var path: String? {
            guard let row else { return nil }
            guard let stop else { return "trains[\(row)]" }
            return "trains[\(row)].stops[\(stop - 1)]"
        }
    }

    public struct Rename: Identifiable, Hashable, Sendable {
        public var from: String
        public var to: String
        public var id: String { "\(from)->\(to)" }
    }

    /// What the commit would do, in the numbers §8.7 asks to see first.
    public struct Report: Sendable {
        public var mode: Mode
        public var country: String
        public var schemaVersion: String?
        /// Rows the document offered.
        public var documentCount: Int
        /// Rows that passed both doors.
        public var added: Int
        /// Journeys the commit would remove — every current one, in replace
        /// mode, and none in append mode.
        public var replaced: Int
        /// Journeys the commit would leave exactly as they are.
        public var kept: Int
        public var renames: [Rename]
        public var issues: [Issue]

        /// A commit is offered only when nothing is wrong.
        ///
        /// The engine stops at the FIRST bad row (append mode also rolls back
        /// what it had already added), so importing a document with known
        /// problems could only ever half-work. The web app lets it be tried
        /// and reports the failure; here the failure is reported before it
        /// happens instead, which changes no import semantics — the same
        /// documents commit, and the same documents do not.
        public var isCommittable: Bool { issues.isEmpty && added > 0 }
    }

    // MARK: - the dry run

    /// Parses, then walks the rows through the real front doors on a scratch
    /// session. Never touches, and cannot touch, the live store.
    ///
    /// - Parameter onProgress: called with `(completed, total)` after every
    ///   row, so the caller can show "驗證 12/201" rather than a spinner.
    public static func inspect(
        text: String,
        currentTrains: [Train],
        country: String,
        mode: Mode,
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) throws -> Report {
        let document: TrainValidation.JSON
        do {
            document = try TrainValidation.parseImportedCanonicalStore(text: text)
        } catch {
            // A document that will not parse has no rows to point at, so the
            // issue is filed against the root rather than invented onto one.
            return documentFailure(
                mode: mode, country: country, kept: currentTrains.count, detail: message(of: error))
        }

        let schema: String? =
            if case .string(let version)? = document["schema_version"] { version } else { nil }
        guard case .array(let rows)? = document["trains"] else {
            return documentFailure(
                mode: mode, country: country, kept: currentTrains.count,
                schemaVersion: schema, detail: "trains must be an array.")
        }

        var session = ImportEngine.Session(
            trains: mode == .append ? currentTrains : [],
            selectedTrainID: nil,
            focusedTrainID: nil,
            selectedDate: Dates.allDates,
            country: country)

        var issues: [Issue] = []
        var renames: [Rename] = []
        var added = 0

        try inspectRows(
            rows, session: &session, issues: &issues, renames: &renames,
            added: &added, onProgress: onProgress)

        // The replace door ends in `finalizeProgressiveLoad`, which runs the
        // ONE authoritative `validateTrainStore` over the rebuilt canonical
        // store. Skipping it here would leave a document that passes every row
        // and still fails the commit — the one outcome a preflight exists to
        // rule out. The append door has no finalize step and therefore no
        // store-level check to mirror.
        appendStoreIssues(
            trains: session.trains, country: country, mode: mode,
            rowsAreEmpty: rows.isEmpty, issues: &issues)

        return Report(
            mode: mode,
            country: country,
            schemaVersion: schema,
            documentCount: rows.count,
            added: added,
            replaced: mode == .replaceAll ? currentTrains.count : 0,
            kept: mode == .replaceAll ? 0 : currentTrains.count,
            renames: renames,
            issues: issues)
    }

    private static func documentFailure(
        mode: Mode, country: String, kept: Int, schemaVersion: String? = nil, detail: String
    ) -> Report {
        return Report(
            mode: mode,
            country: country,
            schemaVersion: schemaVersion,
            documentCount: 0,
            added: 0,
            replaced: 0,
            kept: kept,
            renames: [],
            issues: [Issue(row: nil, stop: nil, trainID: nil, detail: detail)])
    }

    /// Walks the authoritative append door once per row, preserving progress
    /// after diagnostics and the evolving scratch-store index in each message.
    private static func inspectRows(
        _ rows: [TrainValidation.JSON], session: inout ImportEngine.Session,
        issues: inout [Issue], renames: inout [Rename], added: inout Int,
        onProgress: @Sendable (Int, Int) -> Void
    ) throws {
        for (row, raw) in rows.enumerated() {
            try Task.checkCancellation()
            let documentID: String? =
                if case .string(let value)? = raw["id"] { value } else { nil }
            // The index the engine will name in its message, so the prefix can
            // be recognised and replaced with a document-relative one.
            let storeIndex = session.trains.count
            do {
                let finalID = try session.appendImportedTrain(raw, fallbackDate: nil)
                added += 1
                if let documentID, documentID != finalID {
                    renames.append(Rename(from: documentID, to: finalID))
                }
            } catch {
                let located = locate(message(of: error), storeIndex: storeIndex)
                issues.append(
                    Issue(
                        row: row, stop: located.stop, trainID: documentID,
                        detail: located.detail))
            }
            onProgress(row + 1, rows.count)
        }
    }

    private static func appendStoreIssues(
        trains: [Train], country: String, mode: Mode, rowsAreEmpty: Bool,
        issues: inout [Issue]
    ) {
        if mode == .replaceAll, issues.isEmpty, !rowsAreEmpty {
            validateReplacement(trains, country: country, issues: &issues)
        }

        if rowsAreEmpty {
            // Both the JSON-text door and the append door treat an empty
            // document as an error rather than as "replace with nothing".
            issues.append(
                Issue(
                    row: nil, stop: nil, trainID: nil,
                    detail: "The document contains no trains."))
        }
    }

    private static func validateReplacement(
        _ trains: [Train], country: String, issues: inout [Issue]
    ) {
        do {
            let canonical = TrainValidation.buildCanonicalTrainStore(
                trains, country: country, stations: .empty)
            let encoded = try JSONEncoder().encode(canonical)
            try TrainValidation.validateTrainStore(
                TrainValidation.JSON.parse(String(decoding: encoded, as: UTF8.self)))
        } catch {
            issues.append(
                Issue(row: nil, stop: nil, trainID: nil, detail: message(of: error)))
        }
    }

    // MARK: - message shaping

    /// `ValidationError`'s message, and nothing else.
    ///
    /// `localizedDescription` on an `Error` that carries no
    /// `LocalizedError` conformance answers "The operation couldn't be
    /// completed. (RailCore.TrainValidation.ValidationError error 1.)" — a
    /// sentence with no content, which is exactly what §13.3 forbids.
    public static func message(of error: Error) -> String {
        if let validation = error as? TrainValidation.ValidationError { return validation.message }
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return String(describing: error)
    }

    /// Splits `Train 13 stop 4: stop_type is required.` into the stop number
    /// and the part that is actually about what is wrong.
    ///
    /// Built from the index the engine was given rather than by pattern
    /// matching any number, so a message that happens to start with a
    /// different train's position is left alone instead of mis-parsed.
    private static func locate(_ message: String, storeIndex: Int) -> (stop: Int?, detail: String) {
        let prefix = "Train \(storeIndex + 1)"
        guard message.hasPrefix(prefix) else { return (nil, message) }
        var rest = message.dropFirst(prefix.count)
        var stop: Int?
        if rest.hasPrefix(" stop ") {
            rest = rest.dropFirst(" stop ".count)
            let digits = rest.prefix { $0.isNumber }
            stop = Int(digits)
            rest = rest.dropFirst(digits.count)
        }
        if rest.hasPrefix(": ") { rest = rest.dropFirst(2) }
        return (stop, String(rest))
    }
}
