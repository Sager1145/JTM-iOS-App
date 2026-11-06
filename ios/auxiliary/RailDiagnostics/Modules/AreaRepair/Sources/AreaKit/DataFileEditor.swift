import Foundation

/// Applies patch ops to file bytes. Junction ops splice text (see
/// ``JunctionFileEditor``); history and package ops edit an order-preserving
/// tree and re-serialise in the file's own style (both files are compact,
/// so unchanged entries keep their bytes).
public enum DataFileEditor {
    /// Package pairing fields an `alignmentPair.set` value may carry.
    public static let pairingFields = ["alignmentOf", "alignmentDirection", "alignmentPairs", "stationOrderDirection", "permittedTraversal"]

    /// Applies `ops` (all for `file`) in order.
    public static func apply(_ ops: [PatchOp], file: DataFile, to data: Data) throws -> Data {
        guard ops.allSatisfy({ $0.op.file == file }) else { throw AreaRepairError.invalidPatch("ops do not all target \(file.relativePath).") }
        if file == .junctions { return try ops.reduce(data) { try JunctionFileEditor.apply($1, to: $0) } }
        guard !ops.isEmpty else { return data }
        var tree = try AreaJSON.parse(data)
        for op in ops {
            switch file {
            case .history: try applyHistory(op, to: &tree)
            case .package: try applyPackage(op, to: &tree)
            default: throw AreaRepairError.invalidPatch("\(file.relativePath) is not patchable.")
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        let pretty = text.hasPrefix("{\n")
        var out = tree.serialized(style: pretty ? .pretty(indent: 2) : .compact)
        if text.hasSuffix("\n") { out += "\n" }
        return Data(out.utf8)
    }

    static func applyHistory(_ op: PatchOp, to tree: inout AreaJSON) throws {
        let collection: String = switch op.op {
        case .historyRetirementAdd, .historyRetirementUpdate, .historyRetirementRemove: "retirements"
        default: "identity_periods"
        }
        var rows = tree[collection]?.arrayValue ?? []
        let index = rows.firstIndex { $0["history_id"]?.stringValue == op.key }
        if let after = op.after, after["history_id"]?.stringValue != op.key {
            throw AreaRepairError.invalidPatch("\(op.op.rawValue): history_id must equal the key \(op.key).")
        }
        switch (op.before, op.after, index) {
        case (nil, let after?, nil): rows.append(after)
        case (let before?, nil, let i?) where rows[i] == before: rows.remove(at: i)
        case (let before?, let after?, let i?) where rows[i] == before: rows[i] = after
        default:
            throw AreaRepairError.invalidPatch("\(op.op.rawValue) \(op.key) does not match \(collection) in rail-history.json.")
        }
        tree[collection] = .array(rows)
    }

    static func applyPackage(_ op: PatchOp, to tree: inout AreaJSON) throws {
        guard var lines = tree["lines"]?.arrayValue else { throw AreaRepairError.invalidJSON("package has no lines") }
        switch op.op {
        case .packageAlignmentPairSet:
            guard let i = lines.firstIndex(where: { $0["id"]?.stringValue == op.key }) else {
                throw AreaRepairError.invalidPatch("package line \(op.key) does not exist.")
            }
            guard let after = op.after, case .object(let changes) = after,
                  Set(after.objectKeys).isSubset(of: pairingFields) else {
                throw AreaRepairError.invalidPatch("alignmentPair.set value must be an object of \(pairingFields).")
            }
            if let before = op.before {
                guard case .object = before, Set(before.objectKeys) == Set(after.objectKeys),
                      before.objectKeys.allSatisfy({ (lines[i][$0] ?? .null) == before[$0] }) else {
                    throw AreaRepairError.invalidPatch("package line \(op.key) pairing differs from the patch's before value.")
                }
            }
            for (field, value) in changes { lines[i][field] = value == .null ? nil : value }
        case .packageStationAnchorSet:
            let parts = op.key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let i = lines.firstIndex(where: { $0["id"]?.stringValue == parts[0] }) else {
                throw AreaRepairError.invalidPatch("station anchor key must be LINE/STATION on an existing line.")
            }
            guard let after = op.after?.arrayValue, after.count == 2, after.allSatisfy({ $0.doubleValue != nil }) else {
                throw AreaRepairError.invalidPatch("station anchor value must be [lon, lat].")
            }
            if case .object(var aliases)? = lines[i]["displayStationCoordinates"],
               let a = aliases.firstIndex(where: { $0.0 == parts[1] }) {
                if let before = op.before, before != aliases[a].1 {
                    throw AreaRepairError.invalidPatch("station anchor \(op.key) differs from the patch's before value.")
                }
                aliases[a].1 = .array(after)
                lines[i]["displayStationCoordinates"] = .object(aliases)
            } else {
                guard var stations = lines[i]["stations"]?.arrayValue,
                      let s = stations.firstIndex(where: { $0.arrayValue?.first?.stringValue == parts[1] }),
                      var row = stations[s].arrayValue, row.count >= 4 else {
                    throw AreaRepairError.invalidPatch("station \(parts[1]) is not on \(parts[0]).")
                }
                if let before = op.before, before != .array([row[2], row[3]]) {
                    throw AreaRepairError.invalidPatch("station anchor \(op.key) differs from the patch's before value.")
                }
                row[2] = after[0]; row[3] = after[1]
                stations[s] = .array(row)
                lines[i]["stations"] = .array(stations)
            }
        default:
            throw AreaRepairError.invalidPatch("\(op.op.rawValue) is not a package op.")
        }
        tree["lines"] = .array(lines)
    }

    /// The pairing-field subset of a package line row.
    public static func pairing(of line: AreaJSON) -> AreaJSON {
        .object(pairingFields.compactMap { field in line[field].map { (field, $0) } })
    }
}
