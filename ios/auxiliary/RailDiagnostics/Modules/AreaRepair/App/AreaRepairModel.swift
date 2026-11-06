import AreaKit
import CoreLocation
import Foundation
import Observation
import RailInspection
import SwiftUI

// MARK: - App-local value types (the view never touches AreaKit)

struct AreaProblemRow: Identifiable, Equatable {
    var id: String
    var kind: String
    var severity: String
    var message: String
    var lineIDs: [String]
    var coordinate: CLLocationCoordinate2D?
    var hasProposal: Bool
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.message == b.message }
}

struct AreaOpRow: Identifiable, Equatable {
    var id: String
    var title: String
    var file: String
    var writable: Bool
    var reason: String
    var source: [String]
}

struct AreaRideRow: Identifiable, Equatable {
    var id: String
    var before: Bool
    var after: Bool
}

struct AreaPreviewData {
    var baseline: [[CLLocationCoordinate2D]] = []
    var patched: [[CLLocationCoordinate2D]] = []
    var stations: [(name: String, coordinate: CLLocationCoordinate2D)] = []
    var junctions: [CLLocationCoordinate2D] = []
    var rides: [AreaRideRow] = []
    var problemsBefore = 0
    var problemsAfter = 0
}

/// Focused-value bridge for the Diagnostics menu while this workspace is active.
@MainActor @Observable
final class AreaRepairCommandBridge {
    var canResolve = false, canPreview = false, canUndo = false, canWrite = false
    @ObservationIgnored var resolve: (() -> Void)?
    @ObservationIgnored var preview: (() -> Void)?
    @ObservationIgnored var undo: (() -> Void)?
    @ObservationIgnored var write: (() -> Void)?
}
private struct AreaRepairCommandKey: FocusedValueKey { typealias Value = AreaRepairCommandBridge }
extension FocusedValues {
    var areaRepairCommands: AreaRepairCommandBridge? {
        get { self[AreaRepairCommandKey.self] }
        set { self[AreaRepairCommandKey.self] = newValue }
    }
}

// MARK: - Model

@MainActor @Observable
final class AreaRepairModel {
    enum Kind: String, CaseIterable, Identifiable {
        case rect = "Rectangle", stationPair = "Station pair", lineSection = "Line section", centre = "Centre + radius"
        var id: String { rawValue }
    }
    // Selection form
    var kind = Kind.centre
    var minLon = "", minLat = "", maxLon = "", maxLat = ""
    var lineID = "", fromStation = "", toStation = ""
    var firstInterval = "", lastInterval = ""
    var centreLon = "", centreLat = "", radius = "800"
    var margin = "500"
    // Results
    private(set) var busy = false
    private(set) var message = "Choose an area and Resolve."
    private(set) var errorText: String?
    private(set) var problems: [AreaProblemRow] = []
    private(set) var ops: [AreaOpRow] = []
    private(set) var preview: AreaPreviewData?
    private(set) var guardLog: [String] = []
    private(set) var lastReceiptDescription: String?
    var selectedProblemID: String?
    // Proposal form (op prefilled from the problem; reason and source required)
    var proposalSummary = ""
    var proposalReason = ""
    var proposalSource = ""
    var confirmingWrite = false

    @ObservationIgnored private var session: Session?
    var hasResolved: Bool { session?.scope != nil }
    var canAddProposal: Bool {
        selectedProblemID != nil && session?.hasProposal(selectedProblemID!) == true
            && !proposalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceList.isEmpty
    }
    var sourceList: [String] {
        proposalSource.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var writableCount: Int { ops.filter(\.writable).count }
    var canWrite: Bool { !busy && writableCount > 0 }

    // MARK: Selection

    static func describe(_ area: AreaSelection) -> String {
        switch area.mode {
        case .rect(let a, let b, let c, let d): "rect \(a),\(b) – \(c),\(d)"
        case .stationPair(let l, let f, let t): "\(l) \(f)–\(t)"
        case .lineSection(let l, let f, let t): "\(l) intervals \(f)–\(t)"
        case .centre(let lon, let lat, let r): "centre \(lon),\(lat) r\(Int(r)) m"
        }
    }

    func selection() throws -> AreaSelection {
        func number(_ t: String, _ n: String) throws -> Double {
            guard let v = Double(t.trimmingCharacters(in: .whitespaces)) else { throw DiagnosticError.invalidRequest("\(n) must be a number.") }
            return v
        }
        func integer(_ t: String, _ n: String) throws -> Int {
            guard let v = Int(t.trimmingCharacters(in: .whitespaces)) else { throw DiagnosticError.invalidRequest("\(n) must be an integer.") }
            return v
        }
        let line = lineID.trimmingCharacters(in: .whitespaces)
        let mode: AreaSelection.Mode
        switch kind {
        case .rect: mode = .rect(minLon: try number(minLon, "Min longitude"), minLat: try number(minLat, "Min latitude"),
                                 maxLon: try number(maxLon, "Max longitude"), maxLat: try number(maxLat, "Max latitude"))
        case .stationPair: mode = .stationPair(lineID: line, fromStationID: fromStation.trimmingCharacters(in: .whitespaces),
                                               toStationID: toStation.trimmingCharacters(in: .whitespaces))
        case .lineSection: mode = .lineSection(lineID: line, firstInterval: try integer(firstInterval, "First interval"),
                                               lastInterval: try integer(lastInterval, "Last interval"))
        case .centre: mode = .centre(lon: try number(centreLon, "Longitude"), lat: try number(centreLat, "Latitude"),
                                     radiusMetres: try number(radius, "Radius"))
        }
        let selection = AreaSelection(mode: mode, marginMetres: try number(margin, "Margin"))
        try selection.validate()
        return selection
    }

    // MARK: Actions

    func resolve() {
        guard !busy else { return }
        let selection: AreaSelection
        do { selection = try self.selection() } catch { fail(error); return }
        begin("Loading railway data and resolving the area…")
        let previous = session
        Task {
            do {
                let repo = try Session.discoverRepo()
                let patchDir = Session.patchDirectory(name: "area-" + String(UUID().uuidString.prefix(8)).lowercased())
                let session = try await Task.detached {
                    try Session.resolve(selection: selection, repo: repo, patchDir: patchDir, reuse: previous)
                }.value
                self.session = session
                problems = session.problemRows
                ops = []; preview = nil; guardLog = []; lastReceiptDescription = nil; selectedProblemID = nil
                message = "\(problems.count) problem(s) in \(Self.describe(selection))."
            } catch { fail(error) }
            busy = false
        }
    }

    func selectProblem(_ id: String?) {
        selectedProblemID = id
        guard let id, let session else { proposalSummary = ""; return }
        proposalSummary = session.proposalSummary(id) ?? "No automatic fix: this needs a survey or belongs to another owner."
        proposalReason = ""; proposalSource = ""
    }

    func addProposal() {
        guard canAddProposal, let id = selectedProblemID, let session else { return }
        do {
            try session.addProposal(problemID: id, reason: proposalReason.trimmingCharacters(in: .whitespacesAndNewlines), source: sourceList)
            ops = session.opRows
            preview = nil
            message = "Fix added to the patch stack (\(ops.count))."
        } catch { fail(error) }
    }

    func undoLast() {
        guard !busy, let session, session.popLast() else { return }
        ops = session.opRows; preview = nil
        message = "Removed the last fix; overlay rematerialises on the next Preview."
    }

    func runPreview() {
        guard !busy, let session, !ops.isEmpty else { return }
        begin("Re-solving the area with the patch stack…")
        Task {
            do {
                let data = try await Task.detached { try session.preview() }.value
                preview = data
                message = "Preview: \(data.problemsBefore) → \(data.problemsAfter) problem(s)."
            } catch { fail(error) }
            busy = false
        }
    }

    func write() {
        confirmingWrite = false
        guard canWrite, let session else { return }
        begin("Writing confirmed patch; guards run and failures auto-revert…")
        Task {
            do {
                let lines = try await Task.detached { try session.write(confirm: true) }.value
                guardLog = lines
                lastReceiptDescription = session.lastReceiptDescription
                message = "Write finished; see the guard log."
            } catch { fail(error) }
            busy = false
        }
    }

    func undoWrite() {
        guard !busy, let session, lastReceiptDescription != nil else { return }
        begin("Restoring the pre-write bytes and re-running guards…")
        Task {
            do {
                guardLog = try await Task.detached { try session.undoWrite(confirm: true) }.value
                lastReceiptDescription = nil
                message = "Write undone."
            } catch { fail(error) }
            busy = false
        }
    }

    private func begin(_ text: String) { busy = true; errorText = nil; message = text }
    private func fail(_ error: Error) { busy = false; errorText = DiagnosticSession.explain(error); message = "Failed." }
}

// MARK: - AreaKit isolation: every AreaKit call lives below this line.

extension AreaRepairModel {
    /// Holds AreaKit state; used serially (one operation at a time, guarded by `busy`).
    final class Session: @unchecked Sendable {
        let selection: AreaSelection
        let repo: URL
        let patchDir: URL
        let data: AreaData
        var scope: AreaScope?
        var problems: [Problem] = []
        var trains: [Train] = []          // AREAKIT-API: Train comes from RailCore via AreaKit's RideSelection
        var patches: [AreaPatch] = []
        var receipt: WriteReceipt?        // AREAKIT-API: WriteTransaction.write return type

        init(selection: AreaSelection, repo: URL, patchDir: URL, data: AreaData) {
            self.selection = selection; self.repo = repo; self.patchDir = patchDir; self.data = data
        }

        static func discoverRepo() throws -> URL {
            // AREAKIT-API: DataRoot.discoverRepo(from:) -> URL (optional or throwing both tolerated)
            for start in [URL(fileURLWithPath: Bundle.main.bundlePath), URL(fileURLWithPath: FileManager.default.currentDirectoryPath)] {
                if let url = try? DataRoot.discoverRepo(from: start) { return url }
            }
            throw DiagnosticError.invalidRequest("Could not find the repository (a directory containing port-fixtures).")
        }

        static func patchDirectory(name: String) -> URL {
            RailwayEvidenceRoot.resolve().appendingPathComponent("area-repairs", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }

        static func resolve(selection: AreaSelection, repo: URL, patchDir: URL, reuse: Session?) throws -> Session {
            // AREAKIT-API: AreaData(root:) loads the five data files once; reuse when the repo is unchanged.
            let data = try reuse.flatMap { $0.repo == repo ? $0.data : nil } ?? AreaData(root: DataRoot(repo: repo, overlay: nil))
            let session = Session(selection: selection, repo: repo, patchDir: patchDir, data: data)
            let scope = try AreaScope.resolve(selection, data: data)   // AREAKIT-API
            session.scope = scope
            // AREAKIT-API: default trains crossing the scope (RideSelection), then all detectors.
            session.trains = try RideSelection.ridesCrossing(scope, trains: RideSelection.defaultTrains(data: data))
            session.problems = try Detectors.run(scope: scope, data: data, trains: session.trains)
            return session
        }

        var problemRows: [AreaProblemRow] {
            problems.map { p in
                // AREAKIT-API: Problem { id, kind, severity, lineIDs, coordinate, message, proposal }
                AreaProblemRow(id: p.id, kind: "\(p.kind)", severity: "\(p.severity)", message: p.message, lineIDs: p.lineIDs,
                               coordinate: CLLocationCoordinate2D(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude),
                               hasProposal: p.proposal != nil)
            }
        }

        func hasProposal(_ id: String) -> Bool { problems.first { $0.id == id }?.proposal != nil }
        func proposalSummary(_ id: String) -> String? {
            guard let op = problems.first(where: { $0.id == id })?.proposal else { return nil }
            return "\(op.op) → \(op.file) [\(op.key)]" + (op.writable ? "" : "  (report-only: not written to repo data)")
        }

        func addProposal(problemID: String, reason: String, source: [String]) throws {
            guard var op = problems.first(where: { $0.id == problemID })?.proposal else {
                throw DiagnosticError.invalidRequest("This problem has no automatic proposal.")
            }
            op.reason = reason; op.source = source     // AREAKIT-API: PatchOp.reason/.source are mutable
            // AREAKIT-API: AreaPatch(id:createdAt:area:ops:guards:) — one patch per fix so Undo pops one entry.
            let patch = try AreaPatch(id: "fix-\(patches.count + 1)", createdAt: Date(), area: selection, ops: [op], guards: [])
            try patch.validate()
            patches.append(patch)
        }

        func popLast() -> Bool { patches.popLast() != nil }

        var opRows: [AreaOpRow] {
            patches.flatMap { patch in
                patch.ops.enumerated().map { index, op in
                    AreaOpRow(id: "\(patch.id)/\(index)", title: op.op, file: op.file, writable: op.writable,
                              reason: op.reason, source: op.source)
                }
            }
        }

        var lastReceiptDescription: String? { receipt.map { "\($0.directory.path)" } }   // AREAKIT-API: receipt.directory

        func preview() throws -> AreaPreviewData {
            guard let scope else { throw DiagnosticError.invalidRequest("Resolve the area first.") }
            let scratch = patchDir.appendingPathComponent("scratch", isDirectory: true)
            // AREAKIT-API: ScratchOverlay.materialize(repo:patches:into:) -> DataRoot; overlay = f(repo, patch stack)
            let overlay = try ScratchOverlay.materialize(repo: repo, patches: patches, into: scratch)
            let patched = try AreaData(root: overlay)
            let patchedScope = try AreaScope.resolve(selection, data: patched)
            // AREAKIT-API: Preview.run(baseline:patched:scope:trains:) -> PreviewResult
            let result = try Preview.run(baseline: data, patched: patched, scope: patchedScope, trains: trains)
            var out = AreaPreviewData()
            // AREAKIT-API: PreviewResult.geometry.{baseline,patched}: [[(lat, lon)]]; .stations, .junctions; .rides
            out.baseline = result.baselineGeometry.display.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
            out.patched = result.patchedGeometry.display.map { $0.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
            out.stations = result.patchedGeometry.stations.map { ($0.name, CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            out.junctions = result.patchedGeometry.junctions.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            out.rides = result.rides.map { AreaRideRow(id: $0.trainID, before: $0.certifiedBefore, after: $0.certifiedAfter) }
            out.problemsBefore = result.problemsBefore.count
            out.problemsAfter = result.problemsAfter.count
            _ = scope
            return out
        }

        func write(confirm: Bool) throws -> [String] {
            // AREAKIT-API: WriteTransaction(repo:patchDir:).write(patch, confirm:) -> WriteReceipt with .guardLog: [String]
            let transaction = WriteTransaction(repo: repo, patchDir: patchDir)
            let merged = try AreaPatch(id: "write-\(Int(Date().timeIntervalSince1970))", createdAt: Date(), area: selection,
                                       ops: patches.flatMap(\.ops), guards: [])
            let result = try transaction.write(merged, confirm: confirm)
            receipt = result
            return result.guardLog
        }

        func undoWrite(confirm: Bool) throws -> [String] {
            guard let receipt else { throw DiagnosticError.invalidRequest("No write to undo.") }
            // AREAKIT-API: WriteTransaction.undo(receipt, confirm:) -> [String] guard log
            return try WriteTransaction(repo: repo, patchDir: patchDir).undo(receipt, confirm: confirm)
        }
    }
}
