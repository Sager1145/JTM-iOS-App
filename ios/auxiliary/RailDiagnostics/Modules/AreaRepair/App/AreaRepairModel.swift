import AreaKit
import CoreLocation
import Foundation
import Observation
import RailCore
import RailInspection
import SwiftUI
import UIKit

// MARK: - App-local value types (the view never touches AreaKit)

struct AreaProblemRow: Identifiable, Equatable {
    var id: String
    var kind: String
    var severity: String
    var message: String
    var lineIDs: [String]
    var coordinate: CLLocationCoordinate2D
    var hasProposal: Bool
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.message == b.message }
}

struct AreaOpRow: Identifiable, Equatable {
    var id: String
    var title: String
    var file: String
    var key: String
    var writable: Bool
    /// Source of truth a report-only op must be mirrored into.
    var mirror: String?
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
    var cleared = 0
    var introduced = 0
}

/// A patch saved for the guarded CLI write. The app never writes repository data:
/// Foundation.Process is unavailable on Mac Catalyst, so it cannot run the guards.
struct AreaPatchExport: Equatable {
    var patchPath: String
    var reportOnlyPath: String?
    var command: String
    var repository: String
}

/// Locates the JTM repository the area workspace reads from. The app runs from a
/// build product, so it uses `--repo-root PATH` or `JTM_REPO_ROOT` when given, else
/// the source tree this file was compiled from.
enum AreaRepository {
    static func root(arguments: [String] = ProcessInfo.processInfo.arguments,
                     environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let index = arguments.firstIndex(of: "--repo-root") {
            guard arguments.indices.contains(index + 1), (arguments[index + 1] as NSString).isAbsolutePath else {
                throw DiagnosticError.invalidRequest("--repo-root requires an absolute repository path.")
            }
            return try DataRoot.discoverRepo(from: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        }
        if let path = environment["JTM_REPO_ROOT"], !path.isEmpty {
            return try DataRoot.discoverRepo(from: URL(fileURLWithPath: path, isDirectory: true))
        }
        return try DataRoot.discoverRepo(from: URL(fileURLWithPath: #filePath))
    }
}

/// Focused-value bridge for the Diagnostics menu while this workspace is active.
@MainActor @Observable
final class AreaRepairCommandBridge {
    var canResolve = false
    var canPreview = false
    var canUndo = false
    var canExport = false
    @ObservationIgnored var resolve: (() -> Void)?
    @ObservationIgnored var preview: (() -> Void)?
    @ObservationIgnored var undo: (() -> Void)?
    @ObservationIgnored var export: (() -> Void)?
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
    var minLon = ""
    var minLat = ""
    var maxLon = ""
    var maxLat = ""
    var lineID = ""
    var fromStation = ""
    var toStation = ""
    var firstInterval = ""
    var lastInterval = ""
    var centreLon = ""
    var centreLat = ""
    var radius = "800"
    var margin = "500"
    // Results
    private(set) var busy = false
    private(set) var message = "Choose an area and Resolve."
    private(set) var errorText: String?
    private(set) var problems: [AreaProblemRow] = []
    private(set) var ops: [AreaOpRow] = []
    private(set) var preview: AreaPreviewData?
    private(set) var export: AreaPatchExport?
    var selectedProblemID: String?
    // Proposal form (op prefilled from the problem; reason and source required)
    var proposalSummary = ""
    var proposalReason = ""
    var proposalSource = ""
    var confirmingExport = false

    @ObservationIgnored private var session: Session?
    var hasResolved: Bool { session != nil }
    var canAddProposal: Bool {
        selectedProblemID != nil && session?.hasProposal(selectedProblemID!) == true
            && !proposalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceList.isEmpty
    }
    var sourceList: [String] {
        proposalSource.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var writableCount: Int { ops.filter(\.writable).count }
    var canExport: Bool { !busy && writableCount > 0 }

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
                let repo = try AreaRepository.root()
                let patchID = "area-" + String(UUID().uuidString.prefix(8)).lowercased()
                let session = try await Task.detached(priority: .userInitiated) {
                    try Session.resolve(selection: selection, repo: repo, patchID: patchID, reuse: previous)
                }.value
                self.session = session
                problems = session.problemRows
                ops = []; preview = nil; export = nil; selectedProblemID = nil
                message = "\(problems.count) problem(s) in \(Self.describe(selection)); \(session.trains.count) ride(s) cross it."
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
            preview = nil; export = nil
            message = "Fix added to the patch stack (\(ops.count))."
        } catch { fail(error) }
    }

    func undoLast() {
        guard !busy, let session, session.popLast() else { return }
        ops = session.opRows; preview = nil; export = nil
        message = "Removed the last fix; the scratch overlay rematerialises on the next Preview."
    }

    func runPreview() {
        guard !busy, let session, !ops.isEmpty else { return }
        begin("Re-solving the area on the scratch overlay…")
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) { try session.preview() }.value
                preview = data
                message = "Preview: \(data.problemsBefore) → \(data.problemsAfter) problem(s); \(data.cleared) cleared, \(data.introduced) introduced."
            } catch { fail(error) }
            busy = false
        }
    }

    /// Saves the patch for the guarded CLI write and copies its command.
    func exportPatch() {
        confirmingExport = false
        guard canExport, let session else { return }
        do {
            let result = try session.export()
            export = result
            UIPasteboard.general.string = result.command
            message = "Patch saved. Run the copied command from \(result.repository) to write it with guards and auto-revert."
        } catch { fail(error) }
    }

    func copyCommand() {
        guard let export else { return }
        UIPasteboard.general.string = export.command
        message = "Command copied."
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
        let patchID: String
        let data: AreaData
        let scope: AreaScope
        let problems: [Problem]
        let trains: [Train]
        private(set) var patches: [AreaPatch] = []

        private init(selection: AreaSelection, repo: URL, patchID: String, data: AreaData,
                     scope: AreaScope, problems: [Problem], trains: [Train]) {
            self.selection = selection; self.repo = repo; self.patchID = patchID; self.data = data
            self.scope = scope; self.problems = problems; self.trains = trains
        }

        /// `<evidence root>/area-repairs/<patch id>/`, validated as an evidence write location.
        var patchDirectory: URL {
            get throws {
                try RailwayEvidenceRoot.validatedWriteURL(RailwayEvidenceRoot.resolve()
                    .appendingPathComponent("area-repairs", isDirectory: true)
                    .appendingPathComponent(patchID, isDirectory: true))
            }
        }

        static func resolve(selection: AreaSelection, repo: URL, patchID: String, reuse: Session?) throws -> Session {
            // The five data files load once per repository; a new selection reuses them.
            let data = try reuse.flatMap { $0.repo == repo ? $0.data : nil } ?? AreaData.load(DataRoot(repo: repo))
            let scope = try AreaScope.resolve(selection, data: data)
            let trains = RideSelection.ridesCrossing(scope, trains: try RideSelection.loadTrains(RideSource.defaults(data.root)), data: data)
            return Session(selection: selection, repo: repo, patchID: patchID, data: data, scope: scope,
                           problems: AreaProblems.detect(scope: scope, data: data, trains: trains), trains: trains)
        }

        var problemRows: [AreaProblemRow] {
            problems.map { p in
                AreaProblemRow(id: p.id, kind: p.kind.rawValue, severity: p.severity.rawValue, message: p.message, lineIDs: p.lineIDs,
                               coordinate: CLLocationCoordinate2D(latitude: p.coordinate.lat, longitude: p.coordinate.lon),
                               hasProposal: p.proposal != nil)
            }
        }

        func hasProposal(_ id: String) -> Bool { problems.first { $0.id == id }?.proposal != nil }
        func proposalSummary(_ id: String) -> String? {
            guard let op = problems.first(where: { $0.id == id })?.proposal else { return nil }
            return "\(op.op.rawValue) → \(op.file) [\(op.key)]"
                + (op.writable ? "" : "\nReport-only: never written from here" + (op.mirror.map { "; mirror into \($0)" } ?? "") + ".")
        }

        /// One patch per fix, so Undo pops exactly one entry.
        func addProposal(problemID: String, reason: String, source: [String]) throws {
            guard var op = problems.first(where: { $0.id == problemID })?.proposal else {
                throw DiagnosticError.invalidRequest("This problem has no automatic proposal.")
            }
            op.reason = reason; op.source = source
            let patch = AreaPatch(id: "\(patchID)-fix-\(patches.count + 1)", area: selection, ops: [op])
            try patch.validate()
            patches.append(patch)
        }

        func popLast() -> Bool { patches.popLast() != nil }

        var opRows: [AreaOpRow] {
            patches.flatMap { patch in
                patch.ops.enumerated().map { index, op in
                    AreaOpRow(id: "\(patch.id)/\(index)", title: op.op.rawValue, file: op.file, key: op.key, writable: op.writable,
                              mirror: op.mirror, reason: op.reason, source: op.source)
                }
            }
        }

        /// Materialises the whole patch stack (report-only ops included) into the
        /// patch directory's scratch/ overlay and compares it with the repository.
        func preview() throws -> AreaPreviewData {
            let overlay = try ScratchOverlay.materialize(repo: repo, patches: patches,
                                                         into: patchDirectory.appendingPathComponent("scratch", isDirectory: true))
            let patched = try AreaData.load(overlay)
            let result = try AreaKit.Preview.run(baseline: data, patched: patched, scope: scope, trains: trains)
            func native(_ p: AreaPoint) -> CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon) }
            func certified(_ ride: RideOutcome?) -> Bool {
                guard let ride else { return false }
                return ride.disposition != "error" && ride.sections.filter(\.inArea).allSatisfy(\.certified)
            }
            var out = AreaPreviewData()
            out.baseline = result.geometryBefore.lines.flatMap(\.display).map { $0.map(native) }
            out.patched = result.geometryAfter.lines.flatMap(\.display).map { $0.map(native) }
            out.stations = result.geometryAfter.stations.map { ($0.name, native($0.anchor)) }
            out.junctions = result.geometryAfter.junctions.flatMap { [native($0.from), native($0.to)] }
            let after = Dictionary(result.ridesAfter.map { ($0.trainID, $0) }, uniquingKeysWith: { a, _ in a })
            out.rides = result.ridesBefore.map { AreaRideRow(id: $0.trainID, before: certified($0), after: certified(after[$0.trainID])) }
            out.problemsBefore = result.problemsBefore.count
            out.problemsAfter = result.problemsAfter.count
            out.cleared = result.cleared.count
            out.introduced = result.introduced.count
            return out
        }

        /// Saves `patch.json` (writable ops) and, when present, `report-only.json`
        /// (ops that must be mirrored into their source of truth) into the patch directory.
        func export() throws -> AreaPatchExport {
            let ops = patches.flatMap(\.ops)
            let writable = ops.filter(\.writable), reportOnly = ops.filter { !$0.writable }
            let patch = AreaPatch(id: patchID, area: selection, ops: writable)
            try patch.validate()
            let directory = try patchDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let patchURL = try RailwayEvidenceRoot.validatedWriteURL(directory.appendingPathComponent("patch.json"))
            try patch.encoded().write(to: patchURL, options: .atomic)
            var reportOnlyPath: String?
            if !reportOnly.isEmpty {
                let url = try RailwayEvidenceRoot.validatedWriteURL(directory.appendingPathComponent("report-only.json"))
                try AreaPatch(id: patchID + "-report-only", area: selection, ops: reportOnly).encoded().write(to: url, options: .atomic)
                reportOnlyPath = url.path
            }
            let quoted = "'" + patchURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            return AreaPatchExport(patchPath: patchURL.path, reportOnlyPath: reportOnlyPath,
                                   command: "bash ios/verify.sh area write --patch \(quoted) --confirm", repository: repo.path)
        }
    }
}
