import CryptoKit
import Foundation
import WorkbenchCore

enum ImportKind: String, CaseIterable, Identifiable, Sendable {
    case workdoc = "Working document"
    case catalog = "Through-service catalog"
    case package = "Physical railway package"
    case history = "Railway history"
    case physicalJunctions = "Reviewed physical junctions"
    var id: String { rawValue }
}

enum ExportKind: Equatable, Sendable { case workdoc, catalog, inspectionPlan }

struct WorkbenchSnapshot: Sendable {
    var patterns: [PatternSummary]
    var issues: [ReviewIssue]
    var differences: [PatternDifference]
    var patches: [TemporalPatch]
    var targetFrom: String
}

enum SessionError: LocalizedError {
    case missingResource(String), notLoaded, invalidEditor(String)
    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Missing bundled resource: \(name). Rebuild the auxiliary app."
        case .notLoaded: "Open a working document or load the bundled catalog first."
        case .invalidEditor(let message): message
        }
    }
}

/// Owns the mutable document and serializes all disk and core work off the UI actor.
actor WorkbenchSession {
    private var document: WorkbenchDocument?
    private var retainedInspectionPlan: InspectionPlan?
    private let saveURL: URL

    init(saveURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.saveURL = saveURL ?? support.appendingPathComponent("ThroughWorkbench", isDirectory: true)
            .appendingPathComponent("working-document.json")
    }

    func load() throws {
        if FileManager.default.fileExists(atPath: saveURL.path) {
            document = try JSONDecoder().decode(WorkbenchDocument.self, from: Data(contentsOf: saveURL))
        } else {
            let bundled = try bundledDocument()
            try persist(bundled)
            document = bundled
        }
        retainedInspectionPlan = nil
    }

    private func bundledDocument() throws -> WorkbenchDocument {
        func read(_ name: String, required: Bool = true) throws -> JSONValue? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                if required { throw SessionError.missingResource(name) }
                return nil
            }
            return try JSONValue(data: Data(contentsOf: url))
        }
        guard let catalog = try read("japan-through-services") else { throw SessionError.notLoaded }
        var bundled = WorkbenchDocument(catalog: catalog, package: try read("jp-2025"), history: try read("rail-history", required: false), physicalJunctions: try read("physical-rail-junctions", required: false))
        for patch in try WorkbenchDocument.reviewedOnsetPatches() { try bundled.add(patch) }
        return bundled
    }

    func dependencyDigests() throws -> [String: String] {
        guard let document else { throw SessionError.notLoaded }
        func digest<T: Encodable>(_ value: T) throws -> String {
            SHA256.hash(data: try encode(value)).map { String(format: "%02x", $0) }.joined()
        }
        return ["catalog": try digest(document.catalog), "physicalPackage": try digest(document.package),
                "history": try digest(document.history), "physicalJunctions": try digest(document.physicalJunctions)]
    }

    func snapshot(day: String, comparison: String) throws -> WorkbenchSnapshot {
        guard let document else { throw SessionError.notLoaded }
        return WorkbenchSnapshot(patterns: try document.patterns(on: day), issues: try document.audit(on: day),
                                 differences: try document.differences(from: comparison, to: day),
                                 patches: document.patches, targetFrom: document.targetFrom)
    }

    func importFile(_ url: URL, kind: ImportKind) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        var candidate: WorkbenchDocument
        if kind == .workdoc {
            candidate = try JSONDecoder().decode(WorkbenchDocument.self, from: data)
        } else {
            candidate = try document ?? bundledDocument()
            let value = try JSONValue(data: data)
            switch kind {
            case .catalog: candidate = WorkbenchDocument(catalog: value, package: candidate.package, history: candidate.history, physicalJunctions: candidate.physicalJunctions)
            case .package: candidate.package = value
            case .history: candidate.history = value
            case .physicalJunctions: candidate.physicalJunctions = value
            case .workdoc: break
            }
        }
        // Ensure the imported catalog is usable before replacing the working document.
        _ = try candidate.patterns(on: candidate.targetFrom)
        try persist(candidate)
        document = candidate
        retainedInspectionPlan = nil
    }

    func addPatch(patternID: String, from: String, to: String, source: String, note: String,
                  editor: String, newPattern: Bool, remove: Bool) throws {
        guard var candidate = document else { throw SessionError.notLoaded }
        let value = try JSONValue(data: Data(editor.utf8))
        guard let object = value.objectValue else { throw SessionError.invalidEditor("The editor must contain a JSON object.") }
        let changes: [String: JSONValue]
        var legChanges: [LegPatch] = []
        if newPattern {
            changes = object
            guard object["id"]?.stringValue == patternID else {
                throw SessionError.invalidEditor("The pattern JSON id must match the Pattern ID field.")
            }
        } else {
            guard let fields = object["changes"]?.objectValue else {
                throw SessionError.invalidEditor("Use an object with changes and optional legChanges arrays.")
            }
            changes = fields
            if let legs = object["legChanges"] {
                guard let array = legs.arrayValue else { throw SessionError.invalidEditor("legChanges must be an array.") }
                for leg in array {
                    guard let indexValue = leg["index"], case .number(let number) = indexValue, number.isFinite,
                          number >= 0, number.rounded() == number, number < Double(Int.max),
                          let fields = leg["changes"]?.objectValue else {
                        throw SessionError.invalidEditor("Each leg change needs a nonnegative integer index and a changes object.")
                    }
                    legChanges.append(LegPatch(index: Int(number), changes: fields))
                }
            }
        }
        try candidate.add(TemporalPatch(patternID: patternID, effectiveFrom: from,
                                        effectiveTo: to.isEmpty ? nil : to, changes: changes,
                                        legChanges: legChanges, sourceURL: source, note: note, removePattern: remove))
        try persist(candidate)
        document = candidate
        retainedInspectionPlan = nil
    }

    func inspectionPlan(through endDay: String) throws -> InspectionPlan {
        guard let document else { throw SessionError.notLoaded }
        let plan = try document.inspectionPlan(through: endDay)
        retainedInspectionPlan = plan
        return plan
    }

    func export(_ kind: ExportKind, day: String) throws -> Data {
        guard let document else { throw SessionError.notLoaded }
        switch kind {
        case .workdoc: return try encode(document)
        case .catalog: return try document.catalog(on: day).data(pretty: true)
        case .inspectionPlan:
            let plan: InspectionPlan
            if let retainedInspectionPlan, retainedInspectionPlan.endDay == day {
                plan = retainedInspectionPlan
            } else {
                plan = try inspectionPlan(through: day)
            }
            return try encode(plan)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func persist(_ candidate: WorkbenchDocument) throws {
        try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(candidate).write(to: saveURL, options: .atomic)
    }
}
