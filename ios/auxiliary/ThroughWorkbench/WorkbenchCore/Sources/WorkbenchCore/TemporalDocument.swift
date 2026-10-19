import Foundation

public struct LegPatch: Codable, Hashable, Sendable {
    public let index: Int
    public let changes: [String: JSONValue]
    public let expectedIdentity: [String: JSONValue]?
    public init(index: Int, changes: [String: JSONValue], expectedIdentity: [String: JSONValue]? = nil) {
        self.index = index; self.changes = changes; self.expectedIdentity = expectedIdentity
    }
}

/// Sparse source-attributed edits, applied in chronological order, stable file order on ties.
/// A null value removes a key. Temporary changes stop applying at the exclusive end.
public struct TemporalPatch: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let patternID: String
    public let effectiveFrom: String
    public let effectiveTo: String?
    public let changes: [String: JSONValue]
    public let legChanges: [LegPatch]
    public let sourceURL: String
    public let note: String
    public let removePattern: Bool
    public init(id: String = UUID().uuidString, patternID: String, effectiveFrom: String, effectiveTo: String? = nil,
                changes: [String: JSONValue] = [:], legChanges: [LegPatch] = [],
                sourceURL: String, note: String, removePattern: Bool = false) {
        self.id = id; self.patternID = patternID; self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo; self.changes = changes; self.legChanges = legChanges
        self.sourceURL = sourceURL; self.note = note; self.removePattern = removePattern
    }
    func validate() throws {
        try ISODay.validate(effectiveFrom)
        if let effectiveTo { try ISODay.validate(effectiveTo)
            guard effectiveFrom < effectiveTo else { throw WorkbenchError.invalid("结束日期必须晚于开始日期（结束日不包含在内）。") }
        }
        guard !patternID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: sourceURL), ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host, !host.isEmpty else { throw WorkbenchError.invalid("修复需要线路 ID、来源网页和说明。") }
        if let changedID = changes["id"], changedID != .string(patternID) {
            throw WorkbenchError.invalid("修复不能改变线路 ID；请以新 ID 新增一条记录。")
        }
        if removePattern && (!changes.isEmpty || !legChanges.isEmpty) { throw WorkbenchError.invalid("移除记录不能同时修改字段。") }
        for leg in legChanges where leg.index < 0 { throw WorkbenchError.invalid("区段序号不能为负数。") }
    }
}

public struct WorkbenchDocument: Codable, Sendable {
    public var schemaVersion = 1
    public var catalog: JSONValue
    /// One physical base, independent of service revisions. Never copied for each date.
    public var package: JSONValue?
    /// Existing geometry overlay and identity periods, preserved unchanged for review.
    public var history: JSONValue?
    /// Reviewed physical junction catalog, separate from service/display connectors.
    /// Optional so previously saved work files decode without migration.
    public var physicalJunctions: JSONValue?
    public var patches: [TemporalPatch] = []
    public let targetFrom: String
    public init(catalog: JSONValue, package: JSONValue? = nil, history: JSONValue? = nil, physicalJunctions: JSONValue? = nil) {
        self.catalog = catalog; self.package = package; self.history = history
        self.physicalJunctions = physicalJunctions; targetFrom = "1996-12-31"
    }

    public mutating func add(_ patch: TemporalPatch) throws {
        try patch.validate()
        guard !patches.contains(where: { $0.id == patch.id }) else { throw WorkbenchError.invalid("修复记录 ID 重复。") }
        // Validate the proposed document before committing; failure preserves the working copy.
        var boundEdits: [LegPatch] = []
        if !patch.legChanges.isEmpty {
            let before = try catalog(on: patch.effectiveFrom)
            var fields = before["patterns"]?.arrayValue?.first { $0["id"]?.stringValue == patch.patternID }?.objectValue ?? [:]
            Self.apply(patch.changes, to: &fields)
            guard var legs = fields["legs"]?.arrayValue else { throw WorkbenchError.invalid("记录没有有序区段。") }
            for edit in patch.legChanges {
                guard legs.indices.contains(edit.index), var leg = legs[edit.index].objectValue else { throw WorkbenchError.invalid("区段序号已失效。") }
                let identity = Dictionary(uniqueKeysWithValues: ["lineID", "fromStationCode", "toStationCode", "reverseLineID"].map { ($0, leg[$0] ?? .null) })
                if let expected = edit.expectedIdentity, expected != identity { throw WorkbenchError.invalid("区段身份已经改变，必须重新选择修复对象。") }
                boundEdits.append(LegPatch(index: edit.index, changes: edit.changes, expectedIdentity: identity))
                Self.apply(edit.changes, to: &leg); legs[edit.index] = .object(leg)
            }
        }
        let bound = TemporalPatch(id: patch.id, patternID: patch.patternID, effectiveFrom: patch.effectiveFrom,
            effectiveTo: patch.effectiveTo, changes: patch.changes, legChanges: boundEdits,
            sourceURL: patch.sourceURL, note: patch.note, removePattern: patch.removePattern)
        var proposed = self; proposed.patches.append(bound)
        _ = try proposed.catalog(on: patch.effectiveFrom)
        // An older edit can invalidate later indexed edits. Check every patch start and end boundary.
        for day in Set(proposed.patches.map(\.effectiveFrom) + proposed.patches.compactMap(\.effectiveTo)) {
            _ = try proposed.catalog(on: day)
        }
        self = proposed
    }

    public func catalog(on day: String) throws -> JSONValue {
        try ISODay.validate(day)
        guard schemaVersion == 1, var root = catalog.objectValue,
              var patterns = root["patterns"]?.arrayValue else { throw WorkbenchError.invalid("不是支持的直通目录或工作文件。") }
        var ids = Set<String>()
        for pattern in patterns {
            guard let id = pattern["id"]?.stringValue, !id.isEmpty, ids.insert(id).inserted,
                  pattern["legs"]?.arrayValue != nil else { throw WorkbenchError.invalid("直通记录需要唯一 ID 和有序 legs。") }
        }
        let ordered = patches.enumerated().sorted {
            $0.element.effectiveFrom == $1.element.effectiveFrom ? $0.offset < $1.offset : $0.element.effectiveFrom < $1.element.effectiveFrom
        }
        for (_, patch) in ordered {
            try patch.validate()
            guard patch.effectiveFrom <= day, patch.effectiveTo == nil || day < patch.effectiveTo! else { continue }
            let index = patterns.firstIndex { $0["id"]?.stringValue == patch.patternID }
            if patch.removePattern {
                guard let index else { throw WorkbenchError.invalid("无法移除不存在的记录：\(patch.patternID)") }
                patterns.remove(at: index); continue
            }
            var fields = index.flatMap { patterns[$0].objectValue } ?? ["id": .string(patch.patternID)]
            if patch.changes["legs"] != nil, fields["legVariants"]?.arrayValue != nil,
               patch.changes["legVariants"] == nil {
                throw WorkbenchError.invalid("替换共享 legs 时必须同时明确 legVariants，避免历史索引指向错误区段。")
            }
            Self.apply(patch.changes, to: &fields)
            if !patch.legChanges.isEmpty {
                guard var legs = fields["legs"]?.arrayValue else { throw WorkbenchError.invalid("记录没有 legs：\(patch.patternID)") }
                for edit in patch.legChanges {
                    guard legs.indices.contains(edit.index), var leg = legs[edit.index].objectValue else {
                        throw WorkbenchError.invalid("区段序号已失效：\(patch.patternID) #\(edit.index + 1)")
                    }
                    guard let expected = edit.expectedIdentity,
                          expected.allSatisfy({ (leg[$0.key] ?? .null) == $0.value }) else {
                        throw WorkbenchError.invalid("区段身份已改变或索引修复没有身份依据：\(patch.patternID) #\(edit.index + 1)")
                    }
                    Self.apply(edit.changes, to: &leg); legs[edit.index] = .object(leg)
                }
                fields["legs"] = .array(legs)
            }
            guard fields["id"] == .string(patch.patternID), fields["legs"]?.arrayValue != nil,
                  fields["name"]?.stringValue != nil, fields["serviceCode"]?.stringValue != nil else {
                throw WorkbenchError.invalid("新增或修改记录必须保留 id、name、serviceCode 和 legs。")
            }
            try Self.validateWindows(.object(fields), label: patch.patternID)
            for leg in fields["legs"]?.arrayValue ?? [] { try Self.validateWindows(leg, label: patch.patternID) }
            if let index { patterns[index] = .object(fields) } else { patterns.append(.object(fields)) }
        }
        for pattern in patterns { try Self.validateLegVariants(pattern) }
        root["patterns"] = .array(patterns)
        root["workbenchSnapshotDay"] = .string(day)
        root["workbenchAppliedPatches"] = .array(try ordered.compactMap { _, patch in
            guard patch.effectiveFrom <= day, patch.effectiveTo == nil || day < patch.effectiveTo! else { return nil }
            return try JSONValue(data: JSONEncoder().encode(patch))
        })
        return .object(root)
    }
    static func apply(_ changes: [String: JSONValue], to fields: inout [String: JSONValue]) {
        for (key, value) in changes { if value == .null { fields.removeValue(forKey: key) } else { fields[key] = value } }
    }
    static func validateLegVariants(_ pattern: JSONValue) throws {
        guard let value = pattern["legVariants"], value != .null else { return }
        guard let variants = value.arrayValue, !variants.isEmpty else { throw WorkbenchError.invalid("legVariants 必须是非空路径列表。") }
        let count = pattern["legs"]?.arrayValue?.count ?? 0
        for (i, variant) in variants.enumerated() {
            try validateWindows(variant, label: "历史路径 #\(i)")
            guard let rows = variant["legIndices"]?.arrayValue,
                  let sources = variant["sourceURLs"]?.arrayValue, !sources.isEmpty,
                  sources.allSatisfy({ value in
                      guard let text = value.stringValue, let url = URL(string: text) else { return false }
                      return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
                  }), variant["notes"]?.stringValue?.isEmpty == false else {
                throw WorkbenchError.invalid("历史路径需要有序 legIndices、来源和说明。")
            }
            let suspended = variant["suspended"] == .bool(true)
            if let suspension = variant["suspended"], suspension != .null, suspension != .bool(true), suspension != .bool(false) {
                throw WorkbenchError.invalid("suspended 必须是布尔值。")
            }
            if suspended {
                guard rows.isEmpty, variant["validFrom"]?.stringValue != nil, variant["validTo"]?.stringValue != nil else {
                    throw WorkbenchError.invalid("停驶期间必须明确起止日期并使用空 legIndices。")
                }
            } else if rows.isEmpty { throw WorkbenchError.invalid("空历史路径必须明确声明 suspended。") }
            var seen = Set<Int>()
            for row in rows {
                guard let number = row.numberValue, number >= 0, number < Double(count), number.rounded() == number,
                      seen.insert(Int(number)).inserted else { throw WorkbenchError.invalid("历史路径区段索引无效或重复。") }
            }
            for previous in variants.prefix(i) {
                let start = max(variant["validFrom"]?.stringValue ?? "", previous["validFrom"]?.stringValue ?? "")
                let end = min(variant["validTo"]?.stringValue ?? "9999-12-31", previous["validTo"]?.stringValue ?? "9999-12-31")
                if start < end { throw WorkbenchError.invalid("历史路径有效期重叠，无法唯一选择路径。") }
            }
        }
    }

    static func activeLegIndices(_ pattern: JSONValue, on day: String) -> [Int] {
        guard ISODay.active(pattern, on: day), let legs = pattern["legs"]?.arrayValue else { return [] }
        let ordered: [Int]
        if let variants = pattern["legVariants"]?.arrayValue {
            guard let selected = variants.first(where: { ISODay.active($0, on: day) }) else { return [] }
            ordered = selected["legIndices"]?.arrayValue?.compactMap { $0.numberValue.map(Int.init) } ?? []
        } else { ordered = Array(legs.indices) }
        let positions = ordered.indices.filter { ISODay.active(legs[ordered[$0]], on: day) }
        guard !zip(positions, positions.dropFirst()).contains(where: { $1 != $0 + 1 }) else { return [] }
        return positions.map { ordered[$0] }
    }
    static func validateWindows(_ value: JSONValue, label: String) throws {
        for key in ["validFrom", "validTo"] {
            if let v = value[key], v != .null {
                guard let day = v.stringValue else { throw WorkbenchError.invalid("\(label)：\(key) 必须是日期字符串。") }
                try ISODay.validate(day)
            }
        }
        if let start = value["validFrom"]?.stringValue, let end = value["validTo"]?.stringValue, start >= end {
            throw WorkbenchError.invalid("\(label)：有效期顺序错误。")
        }
    }
}
