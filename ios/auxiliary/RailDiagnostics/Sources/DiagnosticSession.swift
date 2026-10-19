import CryptoKit
import Foundation
import Observation
import RailCore
import RailInspection
import WorkbenchCore

/// One request owns one session; workspaces retain their existing evidence formats.
@MainActor @Observable
final class DiagnosticSession {
    let identity = UUID()
    let alignment: InspectorModel
    let route = RouteWorkbenchModel()
    let through: WorkbenchStore
    private(set) var request: DiagnosticRequest?
    private(set) var state = "interactive"
    private(set) var message = "Select a workspace, or launch with --diagnostic-request /absolute/request.json."
    private(set) var candidates: [DiagnosticCandidate] = []
    private(set) var evidence: [String] = []
    private(set) var selectedItemIDs: [String] = []
    private(set) var dependencies: [String: String] = ["diagnosticContract": "rail-diagnostics-v1"]
    private(set) var reviewNotes: [String: DiagnosticReviewNote] = [:]
    private(set) var reviewMessage = ""
    private(set) var running = false
    private(set) var evidenceRevision = 0
    private var launchError: String?
    private var launchErrorDirectory: String?
    private let invocationID = UUID().uuidString
    private var opened = false
    private var admitted = false
    private var retainedResult: [String: Any]?
    private var dependenciesVerified = false
    private var stopRequested = false
    private var captureScope = Set<String>()
    private var captureViewpointIDs: Set<String>?
    var alignmentSummary: BatchCaptureController.ScopeSummary {
        alignment.batch.scopedSummary(scope: captureScope, viewpointIDs: captureViewpointIDs)
    }
    private var publishedCaptureRevision: Int?
    private var publishedCandidates = false

    var workspaceBusy: Bool {
        alignment.captureAdmission.isBusy || alignment.analysisBusy || route.isRunning || route.isReading || route.isInspecting || through.isBusy || through.isInspecting
    }
    var canPause: Bool {
        running || alignment.batch.isRunning || alignment.analysisBusy || route.isRunning || route.isInspecting
    }
    var outputPath: String { request.map { $0.sessionDirectory + "/result.json" } ?? "No request session" }

    init(request suppliedRequest: DiagnosticRequest? = nil) {
        var parsed = suppliedRequest
        let args = suppliedRequest == nil ? ProcessInfo.processInfo.arguments : []
        if let index = args.firstIndex(of: "--diagnostic-request") {
            do {
                guard args.indices.contains(index + 1), (args[index + 1] as NSString).isAbsolutePath else {
                    throw DiagnosticError.invalidRequest("--diagnostic-request requires an absolute JSON path.")
                }
                let data = try Data(contentsOf: URL(fileURLWithPath: args[index + 1]))
                if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = raw["sessionDirectory"] as? String, (path as NSString).isAbsolutePath {
                    launchErrorDirectory = path
                }
                parsed = try JSONDecoder().decode(DiagnosticRequest.self, from: data)
                try parsed?.validate()
            } catch { launchError = Self.explain(error); parsed = nil }
        }
        if let path = suppliedRequest?.sessionDirectory, (path as NSString).isAbsolutePath { launchErrorDirectory = path }
        do { try parsed?.validate() } catch { launchError = Self.explain(error); parsed = nil }
        request = parsed
        let root = parsed.map { URL(fileURLWithPath: $0.sessionDirectory, isDirectory: true) }
        let alignmentRoot = parsed?.alignmentEvidenceDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? root?.appendingPathComponent("alignment", isDirectory: true)
        alignment = InspectorModel(outputURL: alignmentRoot, diagnosticRequest: parsed?.workspace == .alignment ? parsed : nil)
        through = WorkbenchStore(saveURL: root?.appendingPathComponent("through-working-document.json"), automaticInspection: false)
    }

    func open() async {
        guard !opened else { return }
        opened = true
        if let launchError {
            state = "failed"; message = launchError
            if let launchErrorDirectory {
                let root = URL(fileURLWithPath: launchErrorDirectory, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let failure: [String: Any] = ["state": "failed", "message": launchError,
                        "dependenciesVerified": false, "updatedAt": ISO8601DateFormatter().string(from: Date())]
                    try JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys])
                        .write(to: root.appendingPathComponent("last-error.json"), options: .atomic)
                } catch { message += " Error report could not be saved: " + error.localizedDescription }
            }
            return
        }
        guard let request else { return }
        running = true
        defer { running = false }
        do {
            let root = URL(fileURLWithPath: request.sessionDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let retained = root.appendingPathComponent("request.json")
            if FileManager.default.fileExists(atPath: retained.path) {
                guard try JSONDecoder().decode(DiagnosticRequest.self, from: Data(contentsOf: retained)) == request else { throw DiagnosticError.changedRequest }
            } else {
                try Self.encoder.encode(request).write(to: retained, options: .atomic)
            }
            let prior = root.appendingPathComponent("result.json")
            if FileManager.default.fileExists(atPath: prior.path) {
                retainedResult = try JSONSerialization.jsonObject(with: Data(contentsOf: prior)) as? [String: Any]
            }
            admitted = true
            state = "preparing"
            message = "Preparing exact \(request.workspace.rawValue) request scope…"
            try persistRunStatus()
            evidence = request.evidencePaths ?? []
            for path in evidence where !FileManager.default.fileExists(atPath: path) {
                throw DiagnosticError.invalidRequest("Linked evidence is missing: \(path)")
            }
            switch request.workspace {
            case .alignment: try await runAlignment(request)
            case .route: try await runRoute(request)
            case .through: try await runThrough(request)
            }
            try persist()
        } catch {
            state = "failed"; message = error.localizedDescription
            try? persistRunStatus()
            if admitted {
                if retainedResult != nil && !dependenciesVerified {
                    let errorURL = URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("last-error.json")
                    try? JSONSerialization.data(withJSONObject: ["state": state, "message": message], options: [.sortedKeys]).write(to: errorURL, options: .atomic)
                } else { try? persist() }
            }
        }
    }

    func pause() {
        stopRequested = true
        alignment.batch.pause()
        if alignment.analysisBusy { alignment.invalidateAnalysis() }
        route.cancel()
        message = "Pause requested; current native operation must settle before another workspace starts."
    }

    /// Existing workspace controls can collect more evidence for the same
    /// exact task. Their receipts must remain visible to the agent interface.
    func refreshWorkspaceCaptureResult() {
        guard !running, request?.workspace == .alignment, dependenciesVerified else { return }
        updateAlignmentState()
        do { try persist() } catch { state = "failed"; message = error.localizedDescription }
    }

    private var captureProgressMessage: String {
        guard captureViewpointIDs != nil else { return alignment.batch.status }
        let summary = alignmentSummary
        return "\(summary.capturedCount)/\(summary.totalCount) selected captures; \(summary.pendingCount) pending; \(summary.failedCount) failed."
    }

    private func updateAlignmentState() {
        let summary = alignmentSummary
        if alignment.batch.isRunning {
            state = "running"; message = captureProgressMessage
        } else {
            state = request?.action == .prepare ? "prepared" : summary.incomplete ? "partial" : "evidenceReady"
            message = "\(summary.capturedCount)/\(summary.totalCount) scoped captures; \(summary.failedCount) failed. All alignment and connectivity verdicts require review."
            if let error = alignment.batch.lastError { message += " " + error }
        }
    }

    private func runAlignment(_ request: DiagnosticRequest) async throws {
        await alignment.load()
        if let error = alignment.error { throw DiagnosticError.invalidRequest(error) }
        let all = Array(alignment.inputsByID.values)
        guard let plan = alignment.batch.plan else { throw DiagnosticError.invalidRequest("No scoped capture plan is available.") }
        captureViewpointIDs = try request.alignmentViewpointIDs(in: plan, inputs: all)
        let owners = captureViewpointIDs.map { ids in Set(plan.viewpoints.filter { ids.contains($0.id) }.map(\.itemID)) }
        let selected = alignment.admittedCaptureInputs.filter { owners == nil || owners!.contains($0.id) }
        selectedItemIDs = selected.map(\.id)
        captureScope = Set(selectedItemIDs)
        candidates = DiagnosticCandidate.tasks(selected: selected, context: all)
        alignment.select(request.lineID)
        alignment.stationIndex = selected[0].intervalIndex
        alignment.focusInterval()
        if let line = alignment.line {
            dependencies["lineRender"] = BatchCaptureGeometry.dependency(line: line, display: alignment.display, settings: request.normalizedCaptureSettings)
        }
        dependencies["packageVersion"] = alignment.version
        try verifyDependencies()
        evidence.append(alignment.batch.outputURL.path)
        let geometryURL = URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("alignment-geometry.json")
        let selectedData = try Self.encoder.encode(selected)
        let object: [String: Any] = [
            "lineID": request.lineID!, "dependency": dependencies["lineRender"] ?? "",
            "packageInputPath": alignment.packageURL?.path as Any? ?? NSNull(),
            "packageInputSource": request.inputPath == nil ? "bundle" : "request",
            "selectedIntervals": try JSONSerialization.jsonObject(with: selectedData),
            "completeLineDisplayParts": alignment.display.map { $0.map { [$0.lon, $0.lat] } },
            "scope": "DisplayParts geometry, before smoothing and viewport clipping; source/display endpoints and parts support breakpoint review but do not establish physical topology."
        ]
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: geometryURL, options: .atomic)
        evidence.append(geometryURL.path)
        guard !stopRequested && !Task.isCancelled else { state = "paused"; message = "Paused before capture."; return }
        if request.action != .prepare {
            state = "running"; try persist()
            if request.action == .retryFailures {
                // Retrying stays confined to the exact scope; receipts retain failed attempts.
                alignment.batch.retryFailed(scope: captureScope, limit: request.captureLimit, viewpointIDs: captureViewpointIDs)
            } else { alignment.batch.start(scope: captureScope, limit: request.captureLimit, viewpointIDs: captureViewpointIDs) }
            while alignment.batch.isRunning {
                if Task.isCancelled || stopRequested { alignment.batch.pause() }
                message = captureProgressMessage
                if publishedCaptureRevision != alignment.batch.evidenceRevision { try persist() }
                else { try persistRunStatus() }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        updateAlignmentState()
    }

    private func runRoute(_ request: DiagnosticRequest) async throws {
        #if RAIL_DIAGNOSTICS
        let graphCache = try RiddenRouteStore.diagnosticGraphCacheConfiguration()
        dependencies["fallbackGraphCacheMode"] = graphCache.mode
        dependencies["fallbackGraphCacheMaximumNodes"] = graphCache.maximumNodesDescription
        #endif
        let input = URL(fileURLWithPath: request.inputPath!)
        let report = URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("route-report.json")
        try RouteWorkbenchModel.validateReportDestination(report, input: input)
        dependencies["journeyInputSHA256"] = try Self.digest(input)
        await route.read(input)
        if let error = route.error { throw DiagnosticError.invalidRequest(error) }
        let revisions = try RailResourceRevisions.bundled()
        for country in Set(route.trains.flatMap { Region.regionsTouched($0).map(\.code) }) {
            dependencies["rail/" + country] = try revisions.requiredRevision(for: country)
            if country == "jp" { dependencies["timetable"] = revisions.timetableRevision }
        }
        try verifyDependencies()
        selectedItemIDs = route.trains.map(\.id)
        guard !stopRequested && !Task.isCancelled else { state = "paused"; message = "Paused before solve."; return }
        if request.action == .solve {
            state = "running"; try persist(); route.start()
            while route.isRunning || route.isInspecting {
                if Task.isCancelled || stopRequested { route.cancel() }
                route.refresh()
                message = route.message
                try persistRunStatus()
                try await Task.sleep(for: .milliseconds(500))
            }
            try await route.export(reportOnly: true).write(to: report, options: .atomic)
            evidence.append(report.path)
        }
        if let error = route.error { throw DiagnosticError.invalidRequest(error) }
        state = request.action == .prepare ? "prepared" : route.batchPhase == "completed" ? "evidenceReady" : "partial"
        message = route.message + " " + route.inspectionMessage
    }

    private func runThrough(_ request: DiagnosticRequest) async throws {
        guard !stopRequested && !Task.isCancelled else { state = "paused"; message = "Paused before through review."; return }
        through.day = ISODay.date(request.reviewDay!)!
        await through.refresh()
        if let error = through.errorMessage { throw DiagnosticError.invalidRequest(error) }
        guard let pattern = through.snapshot?.patterns.first(where: { $0.id == request.patternID }) else {
            throw DiagnosticError.invalidRequest("Unknown pattern ID on the requested date.")
        }
        through.selectedID = pattern.id
        selectedItemIDs = [pattern.id]
        let root = URL(fileURLWithPath: request.sessionDirectory)
        let patternFile = root.appendingPathComponent("through-pattern.json")
        let patternData = try Self.encoder.encode(pattern.raw)
        dependencies["patternSHA256"] = Self.digest(patternData)
        dependencies["reviewDay"] = request.reviewDay!
        for (name, digest) in try await through.dependencyDigests() { dependencies[name] = digest }
        try verifyDependencies()
        guard !stopRequested && !Task.isCancelled else { state = "paused"; message = "Paused before through export."; return }
        try patternData.write(to: patternFile, options: .atomic)
        evidence.append(patternFile.path)
        if request.action == .inspect {
            let issues = through.snapshot?.issues.filter { $0.patternID == pattern.id || $0.patternID.isEmpty } ?? []
            let rows: [[String: String]] = issues.map { ["id": $0.id, "severity": $0.severity.rawValue, "message": $0.message] }
            let report = root.appendingPathComponent("through-report.json")
            try JSONSerialization.data(withJSONObject: ["patternID": pattern.id, "reviewDay": request.reviewDay!, "scope": "Selected date and pattern; historical range plan and physical routing remain separate.", "issues": rows], options: [.sortedKeys, .prettyPrinted]).write(to: report, options: .atomic)
            evidence.append(report.path)
        }
        state = request.action == .prepare ? "prepared" : "evidenceReady"
        message = "Selected pattern/date evidence exported. Through-service display does not prove physical connectivity."
    }

    func saveReview(candidateID: String, conclusion: String, note: String, paths: String) {
        do {
            guard let request, dependenciesVerified, candidates.contains(where: { $0.id == candidateID }),
                  ["needsRepair", "noIssueObserved", "insufficientEvidence"].contains(conclusion),
                  !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DiagnosticError.invalidRequest("Choose a current candidate and record a concrete observation.")
            }
            var hashes: [String: String] = [:]
            for path in paths.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
                guard (path as NSString).isAbsolutePath else { throw DiagnosticError.invalidRequest("Review evidence paths must be absolute files.") }
                hashes[path] = try Self.digest(URL(fileURLWithPath: path))
            }
            guard !hashes.isEmpty else { throw DiagnosticError.invalidRequest("At least one retained evidence file is required.") }
            var updated = reviewNotes
            updated[candidateID] = .init(id: candidateID, conclusion: conclusion, note: note, evidenceSHA256: hashes)
            let ledger = DiagnosticReviewLedger(requestID: request.requestID, dependencies: dependencies, notes: updated.values.sorted { $0.id < $1.id })
            let ledgerURL = URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("review-notes.json")
            if FileManager.default.fileExists(atPath: ledgerURL.path) {
                let archive = ledgerURL.deletingLastPathComponent().appendingPathComponent("review-note-history", isDirectory: true)
                try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: ledgerURL, to: archive.appendingPathComponent(UUID().uuidString + ".json"))
            }
            try Self.encoder.encode(ledger).write(to: ledgerURL, options: .atomic)
            reviewNotes = updated
            reviewMessage = "Saved reviewer observation; Main final check remains separate."
            try persist()
        } catch { reviewMessage = error.localizedDescription }
    }

    private func loadReviewNotes() throws {
        guard let request else { return }
        let file = URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("review-notes.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let ledger = try JSONDecoder().decode(DiagnosticReviewLedger.self, from: Data(contentsOf: file))
        guard ledger.schemaVersion == 1, ledger.requestID == request.requestID, ledger.dependencies == dependencies else {
            reviewMessage = "Retained review notes have stale dependencies; original notes preserved."
            return
        }
        for note in ledger.notes {
            let valid = !note.evidenceSHA256.isEmpty && note.evidenceSHA256.allSatisfy { path, hash in
                (try? Self.digest(URL(fileURLWithPath: path))) == hash
            }
            if valid { reviewNotes[note.id] = note }
            else { reviewMessage = "Some retained review evidence changed or is missing; those notes remain stale." }
        }
    }

    private func verifyDependencies() throws {
        if retainedResult?["dependenciesVerified"] as? Bool == true,
           let prior = retainedResult?["dependencies"] as? [String: String], prior != dependencies {
            throw DiagnosticError.invalidRequest("Relevant inputs changed. Prior reports are retained; use a new session directory.")
        }
        if let request, retainedResult != nil {
            // Retain a prior partial/failed report before the resumed attempt updates it.
            let root = URL(fileURLWithPath: request.sessionDirectory)
            let archive = root.appendingPathComponent("attempts/" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            for name in ["result.json", "candidate-tasks.json", "route-report.json", "through-report.json", "capture-index.json"] {
                let file = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.copyItem(at: file, to: archive.appendingPathComponent(name)) }
            }
        }
        dependenciesVerified = true
        try loadReviewNotes()
    }

    private func persistRunStatus() throws {
        guard admitted, let request else { return }
        let object: [String: Any] = ["schemaVersion": 1, "requestID": request.requestID,
            "invocationID": invocationID, "state": state, "message": message,
            "processID": Int(ProcessInfo.processInfo.processIdentifier),
            "executablePath": Bundle.main.executablePath as Any? ?? NSNull(),
            "active": ["preparing", "running"].contains(state), "dependenciesVerified": dependenciesVerified,
            "updatedAt": ISO8601DateFormatter().string(from: Date()), "resultPath": outputPath]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(
            to: URL(fileURLWithPath: request.sessionDirectory).appendingPathComponent("run-status.json"), options: .atomic)
    }

    private func persist() throws {
        try persistRunStatus()
        guard admitted, let request else { return }
        let root = URL(fileURLWithPath: request.sessionDirectory)
        if request.workspace == .alignment && !captureScope.isEmpty,
           publishedCaptureRevision != alignment.batch.evidenceRevision {
            try alignment.batch.scopedEvidenceIndex(scope: captureScope, viewpointIDs: captureViewpointIDs).write(to: root.appendingPathComponent("capture-index.json"), options: .atomic)
            publishedCaptureRevision = alignment.batch.evidenceRevision
            evidenceRevision &+= 1
        }
        let candidatesURL = root.appendingPathComponent("candidate-tasks.json")
        if !publishedCandidates {
            try Self.encoder.encode(candidates).write(to: candidatesURL, options: .atomic)
            publishedCandidates = true
        }
        let summary = alignmentSummary
        let object: [String: Any] = [
            "schemaVersion": 1, "requestID": request.requestID, "workspace": request.workspace.rawValue,
            "invocationID": invocationID, "processID": Int(ProcessInfo.processInfo.processIdentifier),
            "executablePath": Bundle.main.executablePath as Any? ?? NSNull(),
            "action": request.action.rawValue, "state": state, "message": message,
            "requestPath": root.appendingPathComponent("request.json").path,
            "runStatusPath": root.appendingPathComponent("run-status.json").path,
            "captureIndexPath": request.workspace == .alignment ? root.appendingPathComponent("capture-index.json").path : NSNull(),
            "packageInputPath": request.workspace == .alignment ? (alignment.packageURL?.path as Any? ?? NSNull()) : NSNull(),
            "packageInputSource": request.workspace == .alignment ? (request.inputPath == nil ? "bundle" : "request") : NSNull(),
            "captureSettings": request.workspace == .alignment ? try JSONSerialization.jsonObject(with: Self.encoder.encode(request.normalizedCaptureSettings)) : NSNull(),
            "updatedAt": ISO8601DateFormatter().string(from: Date()), "itemIDs": selectedItemIDs,
            "dependencies": dependencies, "dependenciesVerified": dependenciesVerified, "evidencePaths": evidence, "candidateTasksPath": candidatesURL.path,
            "reviewNotesPath": root.appendingPathComponent("review-notes.json").path,
            "currentReviewerObservationCount": reviewNotes.count, "reviewMessage": reviewMessage,
            "selectedViewpointIDs": captureViewpointIDs.map { $0.sorted() } as Any? ?? NSNull(),
            "capturedCount": summary.capturedCount,
            "failedCount": summary.failedCount,
            "pendingCount": summary.pendingCount,
            "mainFinalCheck": "pending — separate production composition evidence required",
            "verdict": "pendingReview"
        ]
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("result.json"), options: .atomic)
    }

    static func explain(_ error: Error) -> String {
        let context: DecodingError.Context
        switch error {
        case DecodingError.dataCorrupted(let value): context = value
        case DecodingError.keyNotFound(let key, let value):
            return "Missing request field \(key.stringValue): \(value.debugDescription)"
        case DecodingError.typeMismatch(_, let value), DecodingError.valueNotFound(_, let value): context = value
        default: return error.localizedDescription
        }
        let field = context.codingPath.map(\.stringValue).joined(separator: ".")
        return "Invalid request" + (field.isEmpty ? "" : " at " + field) + ": " + context.debugDescription
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]; return encoder
    }
    private static func digest(_ url: URL) throws -> String {
        digest(try Data(contentsOf: url))
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
