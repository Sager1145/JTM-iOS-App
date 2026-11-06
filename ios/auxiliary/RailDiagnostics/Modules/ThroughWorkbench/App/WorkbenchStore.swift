import Foundation
import Observation
import WorkbenchCore

@MainActor @Observable
final class WorkbenchStore {
    var day = ISODay.date("2026-10-10") ?? .now {
        didSet {
            if ISODay.string(oldValue) != dayString { invalidateInspectionPlan() }
        }
    }
    var comparisonDay = ISODay.date("2005-01-01") ?? .now
    var snapshot: WorkbenchSnapshot?
    private(set) var snapshotKey: String?
    var inspectionPlan: InspectionPlan?
    var isInspecting = false
    var inspectionError: String?
    var selectedID: String?
    var search = ""
    var errorMessage: String?
    var status = "Loading working document…"
    var isBusy = false
    private let session: WorkbenchSession
    private let automaticInspection: Bool

    init(saveURL: URL? = nil, automaticInspection: Bool = true) {
        session = WorkbenchSession(saveURL: saveURL)
        self.automaticInspection = automaticInspection
    }
    private var loaded = false
    private var refreshGeneration = 0
    private var inspectionGeneration = 0

    var dayString: String { ISODay.string(day) }
    var comparisonString: String { ISODay.string(comparisonDay) }
    var selection: PatternSummary? { snapshot?.patterns.first { $0.id == selectedID } }
    var filteredPatterns: [PatternSummary] {
        let patterns = snapshot?.patterns ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return patterns }
        return patterns.filter { "\($0.id) \($0.name) \($0.serviceCode)".localizedCaseInsensitiveContains(query) }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let day = dayString, comparison = comparisonString
        isBusy = true
        defer { if generation == refreshGeneration { isBusy = false } }
        do {
            if !loaded {
                try await session.load()
                loaded = true
            }
            let result = try await session.snapshot(day: day, comparison: comparison)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            snapshot = result
            snapshotKey = "\(day)/\(comparison)"
            status = "\(result.patterns.count) patterns · \(result.issues.count) review issues · \(result.patches.count) patches"
            if automaticInspection && inspectionPlan == nil && !isInspecting && inspectionError == nil {
                await refreshInspectionPlan()
            }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            report(error)
        }
    }

    func importFile(_ url: URL, kind: ImportKind) async {
        isBusy = true
        invalidateInspectionPlan()
        do {
            try await session.importFile(url, kind: kind)
            loaded = true
            await refresh()
        } catch { isBusy = false; report(error); if loaded { await refreshInspectionPlan() } }
    }

    func apply(_ draft: PatchDraft) async -> Bool {
        isBusy = true
        invalidateInspectionPlan()
        do {
            try await session.addPatch(patternID: draft.patternID, from: draft.from, to: draft.to,
                                       source: draft.source, note: draft.note, editor: draft.editor,
                                       newPattern: draft.isNew, remove: draft.remove)
            selectedID = draft.patternID
            await refresh()
            return true
        } catch { isBusy = false; report(error); if loaded { await refreshInspectionPlan() }; return false }
    }

    func refreshInspectionPlan() async {
        guard loaded else { return }
        inspectionGeneration += 1
        let generation = inspectionGeneration
        let endDay = dayString
        isInspecting = true
        inspectionError = nil
        defer { if generation == inspectionGeneration { isInspecting = false } }
        do {
            let result = try await session.inspectionPlan(through: endDay)
            guard generation == inspectionGeneration, !Task.isCancelled else { return }
            inspectionPlan = result
        } catch {
            guard generation == inspectionGeneration, !Task.isCancelled else { return }
            inspectionError = error.localizedDescription
        }
    }

    private func invalidateInspectionPlan() {
        inspectionGeneration += 1
        inspectionPlan = nil
        inspectionError = nil
        isInspecting = false
    }

    func export(_ kind: ExportKind, on day: String) async -> Data? {
        do { return try await session.export(kind, day: day) }
        catch { report(error); return nil }
    }

    func dependencyDigests() async throws -> [String: String] { try await session.dependencyDigests() }

    func report(_ error: Error) { errorMessage = error.localizedDescription; status = "Needs attention" }
}

struct PatchDraft: Identifiable {
    let id = UUID()
    var patternID: String
    var from: String
    var to = ""
    var source = ""
    var note = ""
    var editor = "{\n  \"changes\": {},\n  \"legChanges\": []\n}"
    var isNew = false
    var remove = false

    static func new(on day: String) -> PatchDraft {
        PatchDraft(patternID: "new-pattern", from: day, editor: """
        {
          "id": "new-pattern",
          "name": "New through-service pattern",
          "serviceCode": "new-pattern",
          "aliases": [],
          "kind": "throughRunning",
          "validFrom": "\(day)",
          "legs": [
            { "lineID": "", "fromStationCode": "", "toStationCode": "" }
          ],
          "sourceURLs": [],
          "notes": ""
        }
        """, isNew: true)
    }
}
