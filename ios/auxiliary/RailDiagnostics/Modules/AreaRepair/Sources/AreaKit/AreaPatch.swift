import Foundation
import RailInspection

/// One keyed change to one repository data file: the entry `key` goes from
/// `before` to `after` (`nil` = absent). Every op carries a reason and at
/// least one source. Ops on generated files are report-only unless the
/// writer explicitly allows generated files; package ops are never written.
public struct PatchOp: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case junctionAdd = "junction.add"
        case junctionUpdate = "junction.update"
        case junctionRemove = "junction.remove"
        case historyRetirementAdd = "history.retirement.add"
        case historyRetirementUpdate = "history.retirement.update"
        case historyRetirementRemove = "history.retirement.remove"
        case historyIdentityPeriodAdd = "history.identityPeriod.add"
        case historyIdentityPeriodUpdate = "history.identityPeriod.update"
        case historyIdentityPeriodRemove = "history.identityPeriod.remove"
        /// key = line ID; value = object of pairing fields to change
        /// (alignmentOf, alignmentDirection, alignmentPairs, stationOrderDirection,
        /// permittedTraversal); `null` removes a field, absent fields are kept.
        /// `before` lists the same fields' current values (`null` = absent).
        case packageAlignmentPairSet = "package.alignmentPair.set"
        /// key = "lineID/stationID"; value = [lon, lat].
        case packageStationAnchorSet = "package.stationAnchor.set"

        public var file: DataFile {
            switch self {
            case .junctionAdd, .junctionUpdate, .junctionRemove: .junctions
            case .historyRetirementAdd, .historyRetirementUpdate, .historyRetirementRemove,
                 .historyIdentityPeriodAdd, .historyIdentityPeriodUpdate, .historyIdentityPeriodRemove: .history
            case .packageAlignmentPairSet, .packageStationAnchorSet: .package
            }
        }

        /// Repository source of truth to mirror a generated-file change into.
        public var mirror: String? {
            switch file {
            case .history: "app/scripts/railway/jp-rail-history-events.json"
            case .package: self == .packageAlignmentPairSet
                ? "app/scripts/railway/jp-directional-alignment-overrides.json"
                : "app/scripts/railway (compact package builder station anchors)"
            default: nil
            }
        }

        /// Hand-reviewed files are writable; generated files are not by default.
        public var defaultWritable: Bool { file == .junctions }

        var isRemove: Bool { [.junctionRemove, .historyRetirementRemove, .historyIdentityPeriodRemove].contains(self) }
        var isAdd: Bool { [.junctionAdd, .historyRetirementAdd, .historyIdentityPeriodAdd].contains(self) }

        /// The kind that undoes this one.
        public var inverse: Kind {
            switch self {
            case .junctionAdd: .junctionRemove
            case .junctionRemove: .junctionAdd
            case .historyRetirementAdd: .historyRetirementRemove
            case .historyRetirementRemove: .historyRetirementAdd
            case .historyIdentityPeriodAdd: .historyIdentityPeriodRemove
            case .historyIdentityPeriodRemove: .historyIdentityPeriodAdd
            default: self
            }
        }
    }

    public var op: Kind
    /// Repository-relative path; must equal `op.file.relativePath`.
    public var file: String
    public var key: String
    public var before: AreaJSON?
    public var after: AreaJSON?
    public var reason: String
    public var source: [String]
    public var writable: Bool
    public var mirror: String?

    public init(op: Kind, key: String, before: AreaJSON?, after: AreaJSON?, reason: String = "", source: [String] = []) {
        self.op = op; self.file = op.file.relativePath; self.key = key
        self.before = before; self.after = after; self.reason = reason; self.source = source
        self.writable = op.defaultWritable; self.mirror = op.mirror
    }

    /// The op that restores the state before this one. A junction add
    /// writes its row in canonical key order, so the inverse remove expects
    /// that order.
    public var inverse: PatchOp {
        var op = self
        op.op = self.op.inverse
        op.before = self.op == .junctionAdd ? after.map(JunctionFileEditor.canonicalised) : after
        op.after = before
        return op
    }

    /// Structural checks; `requireProvenance` also demands reason and ≥1 source.
    public func validate(requireProvenance: Bool = true) throws {
        func fail(_ reason: String) -> AreaRepairError { .invalidPatch("\(op.rawValue) \(key): \(reason)") }
        guard file == op.file.relativePath else { throw fail("file must be \(op.file.relativePath).") }
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { throw fail("key is required.") }
        if op.isAdd, before != nil || after == nil { throw fail("an add has no before and a value after.") }
        if op.isRemove, before == nil || after != nil { throw fail("a remove has a before and no after.") }
        if !op.isAdd, !op.isRemove, before == nil || after == nil {
            throw fail("an update or set needs before and after.")
        }
        if requireProvenance {
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail("a reason is required.") }
            guard !source.isEmpty, source.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                throw fail("at least one source is required.")
            }
        }
    }
}

/// Which regression guards a patch must pass after a write.
public enum GuardClass: String, Codable, CaseIterable, Sendable {
    case junction, history, paired, station, rounding
}

/// `jtm-area-patch-v1`: an ordered list of ops for one area. Encoded with an
/// order-preserving writer so row payloads keep their file key order.
public struct AreaPatch: Equatable, Sendable {
    public static let format = "jtm-area-patch-v1"
    public var id: String
    public var createdAt: String
    public var area: AreaSelection
    public var ops: [PatchOp]
    public var guards: [GuardClass]

    public init(id: String, createdAt: String = ISO8601DateFormatter().string(from: Date()),
                area: AreaSelection, ops: [PatchOp], guards: [GuardClass]? = nil) {
        self.id = id; self.createdAt = createdAt; self.area = area; self.ops = ops
        self.guards = guards ?? Self.guards(for: ops)
    }

    /// Guards implied by the files the ops touch.
    public static func guards(for ops: [PatchOp]) -> [GuardClass] {
        var classes: [GuardClass] = []
        for op in ops {
            let implied: [GuardClass] = switch op.op {
            case .junctionAdd, .junctionUpdate, .junctionRemove: [.junction]
            case .packageAlignmentPairSet: [.paired]
            case .packageStationAnchorSet: [.station]
            default: [.history]
            }
            for guardClass in implied where !classes.contains(guardClass) { classes.append(guardClass) }
        }
        return classes
    }

    /// The patch that undoes this one (reversed, inverted ops).
    public var inverse: AreaPatch {
        AreaPatch(id: id + ".inverse", createdAt: createdAt, area: area, ops: ops.reversed().map(\.inverse), guards: guards)
    }

    /// Files touched, in first-touch order.
    public var files: [DataFile] {
        var out: [DataFile] = []
        for op in ops where !out.contains(op.op.file) { out.append(op.op.file) }
        return out
    }

    public func validate(requireProvenance: Bool = true) throws {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else { throw AreaRepairError.invalidPatch("id is required.") }
        guard !ops.isEmpty else { throw AreaRepairError.invalidPatch("a patch needs at least one op.") }
        for op in ops { try op.validate(requireProvenance: requireProvenance) }
    }

    // MARK: encode / decode

    public func json() throws -> AreaJSON {
        func opJSON(_ op: PatchOp) -> AreaJSON {
            var pairs: [(String, AreaJSON)] = [
                ("op", .string(op.op.rawValue)), ("file", .string(op.file)), ("key", .string(op.key)),
                ("before", op.before ?? .null), ("after", op.after ?? .null),
                ("reason", .string(op.reason)), ("source", .array(op.source.map(AreaJSON.string))),
                ("writable", .bool(op.writable)),
            ]
            if let mirror = op.mirror { pairs.append(("mirror", .string(mirror))) }
            return .object(pairs)
        }
        return .object([
            ("format", .string(Self.format)), ("id", .string(id)), ("createdAt", .string(createdAt)),
            ("area", try AreaJSON.from(area)), ("ops", .array(ops.map(opJSON))),
            ("guards", .array(guards.map { .string($0.rawValue) })),
        ])
    }

    /// Pretty JSON (2-space indent, trailing newline).
    public func encoded() throws -> Data { Data((try json().serialized() + "\n").utf8) }

    public static func decode(_ data: Data) throws -> AreaPatch {
        let root = try AreaJSON.parse(data)
        let allowed: Set<String> = ["format", "id", "createdAt", "area", "ops", "guards"]
        guard case .object = root, Set(root.objectKeys).isSubset(of: allowed) else {
            throw AreaRepairError.invalidPatch("unknown top-level fields \(Set(root.objectKeys).subtracting(allowed).sorted()).")
        }
        guard root["format"]?.stringValue == format else { throw AreaRepairError.invalidPatch("format must be \(format).") }
        guard let id = root["id"]?.stringValue, let createdAt = root["createdAt"]?.stringValue,
              let areaJSON = root["area"], let opsJSON = root["ops"]?.arrayValue else {
            throw AreaRepairError.invalidPatch("id, createdAt, area and ops are required.")
        }
        let area = try areaJSON.decode(AreaSelection.self)
        let opKeys: Set<String> = ["op", "file", "key", "before", "after", "reason", "source", "writable", "mirror"]
        let ops = try opsJSON.map { item -> PatchOp in
            guard case .object = item, Set(item.objectKeys).isSubset(of: opKeys) else {
                throw AreaRepairError.invalidPatch("unknown op fields \(Set(item.objectKeys).subtracting(opKeys).sorted()).")
            }
            guard let raw = item["op"]?.stringValue, let kind = PatchOp.Kind(rawValue: raw) else {
                throw AreaRepairError.invalidPatch("unknown op \(item["op"]?.stringValue ?? "?").")
            }
            guard let key = item["key"]?.stringValue else { throw AreaRepairError.invalidPatch("op key is required.") }
            func value(_ name: String) -> AreaJSON? { item[name].flatMap { $0 == .null ? nil : $0 } }
            var op = PatchOp(op: kind, key: key, before: value("before"), after: value("after"),
                             reason: item["reason"]?.stringValue ?? "",
                             source: (item["source"]?.arrayValue ?? []).compactMap(\.stringValue))
            if let file = item["file"]?.stringValue { op.file = file }
            if case .bool(let writable)? = item["writable"] { op.writable = writable }
            if let mirror = item["mirror"]?.stringValue { op.mirror = mirror }
            return op
        }
        let guards = try (root["guards"]?.arrayValue).map { values in
            try values.map { value -> GuardClass in
                guard let raw = value.stringValue, let guardClass = GuardClass(rawValue: raw) else {
                    throw AreaRepairError.invalidPatch("unknown guard \(value.serialized(style: .compact)).")
                }
                return guardClass
            }
        }
        return AreaPatch(id: id, createdAt: createdAt, area: area, ops: ops, guards: guards)
    }
}
