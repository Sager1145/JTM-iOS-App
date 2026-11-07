import Foundation
import RailCore

/// Textual edits of `physical-rail-junctions.json`: a row is located by its
/// `id` among the `junctions` array elements and only that row's bytes (and
/// one separator) change, so the rest of the 3,900-row file stays
/// byte-identical. Rows are written in the file's own style (Python
/// `json.dumps(indent=2, ensure_ascii=False)`).
public enum JunctionFileEditor {
    /// Key order for new rows; keys not listed keep their relative order after.
    public static let canonicalKeyOrder = [
        "id", "kind", "linkMeters", "path", "source", "attachMeters", "terminus",
        "region", "station", "stationCode", "lineIDs", "from", "to", "endJunction", "sourceTopology",
        "evidence", "geometryEvidence", "reviewedAt", "validFrom", "validTo", "temporalEvidence",
    ]

    struct Element { var start: Int; var end: Int; var id: String?; var value: AreaJSON }
    struct Layout { var bytes: [UInt8]; var open: Int; var close: Int; var elements: [Element] }

    static func layout(_ data: Data) throws -> Layout {
        var parser = AreaJSON.Parser(bytes: Array(data))
        try parser.expect(UInt8(ascii: "{"))
        var found: Layout?
        while true {
            parser.skipWhitespace()
            let key = try parser.parseString()
            try parser.expect(UInt8(ascii: ":"))
            if key == "junctions" {
                try parser.expect(UInt8(ascii: "["))
                let open = parser.position - 1
                var elements: [Element] = []
                if parser.peek() == UInt8(ascii: "]") {
                    parser.position += 1
                } else {
                    while true {
                        parser.skipWhitespace()
                        let start = parser.position
                        let value = try parser.parseValue()
                        elements.append(.init(start: start, end: parser.position, id: value["id"]?.stringValue, value: value))
                        guard let next = parser.peek() else { throw parser.error("unterminated junctions") }
                        parser.position += 1
                        if next == UInt8(ascii: "]") { break }
                        guard next == UInt8(ascii: ",") else { throw parser.error("expected , or ]") }
                    }
                }
                found = Layout(bytes: parser.bytes, open: open, close: parser.position - 1, elements: elements)
            } else {
                _ = try parser.parseValue()
            }
            guard let next = parser.peek() else { throw parser.error("unterminated document") }
            parser.position += 1
            if next == UInt8(ascii: "}") { break }
            guard next == UInt8(ascii: ",") else { throw parser.error("expected , or }") }
        }
        guard let found else { throw AreaRepairError.invalidJSON("no junctions array") }
        return found
    }

    /// All rows, verbatim, in file order.
    public static func rows(in data: Data) throws -> [AreaJSON] { try layout(data).elements.map(\.value) }

    /// The row with `id`, if present.
    public static func row(id: String, in data: Data) throws -> AreaJSON? {
        try layout(data).elements.first { $0.id == id }?.value
    }

    /// Orders a new row's keys canonically.
    public static func canonicalised(_ row: AreaJSON) -> AreaJSON {
        guard case .object(let pairs) = row else { return row }
        let rank = Dictionary(uniqueKeysWithValues: canonicalKeyOrder.enumerated().map { ($1, $0) })
        let sorted = pairs.enumerated().sorted { a, b in
            let ra = rank[a.element.0] ?? Int.max, rb = rank[b.element.0] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return .object(sorted)
    }

    /// Applies one junction op and returns the edited file.
    public static func apply(_ op: PatchOp, to data: Data) throws -> Data {
        let layout = try layout(data)
        var bytes = layout.bytes
        let index = layout.elements.firstIndex { $0.id == op.key }
        if let after = op.after, after["id"]?.stringValue != op.key {
            throw AreaRepairError.invalidPatch("\(op.op.rawValue): the row id must equal the key \(op.key).")
        }
        if let after = op.after { try JunctionRowRules.validate(after, op: op) }
        // Element indentation: the whitespace before the first row (or 2 deeper than the array's line).
        let indent: Int = {
            if let first = layout.elements.first {
                var i = first.start
                while i > 0, bytes[i - 1] == 0x20 { i -= 1 }
                return first.start - i
            }
            return 4
        }()
        let depth = indent / 2
        func text(_ row: AreaJSON) -> [UInt8] { Array(row.serialized(style: .pretty(indent: 2), depth: depth).utf8) }

        switch (op.before, op.after) {
        case (nil, let after?):
            guard index == nil else { throw AreaRepairError.invalidPatch("junction \(op.key) already exists.") }
            // New rows are appended in canonical key order. (Re-adding a removed
            // row lands at the end; byte-exact restores use write backups.)
            let row = text(canonicalised(after))
            if let last = layout.elements.last {
                bytes.replaceSubrange(last.end..<last.end,
                                      with: Array(",\n".utf8) + Array(repeating: 0x20, count: indent) + row)
            } else {
                let closeIndent = Array(repeating: UInt8(0x20), count: max(0, indent - 2))
                bytes.replaceSubrange(layout.open...layout.close,
                                      with: Array("[\n".utf8) + Array(repeating: 0x20, count: indent) + row
                                        + Array("\n".utf8) + closeIndent + Array("]".utf8))
            }
        case (let before?, nil):
            guard let index else { throw AreaRepairError.invalidPatch("junction \(op.key) does not exist.") }
            guard layout.elements[index].value == before else {
                throw AreaRepairError.invalidPatch("junction \(op.key) differs from the patch's before value.")
            }
            let elements = layout.elements
            if elements.count == 1 {
                bytes.replaceSubrange(layout.open...layout.close, with: Array("[]".utf8))
            } else if index + 1 < elements.count {
                bytes.removeSubrange(elements[index].start..<elements[index + 1].start)
            } else {
                bytes.removeSubrange(elements[index - 1].end..<elements[index].end)
            }
        case (let before?, let after?):
            guard let index else { throw AreaRepairError.invalidPatch("junction \(op.key) does not exist.") }
            guard layout.elements[index].value == before else {
                throw AreaRepairError.invalidPatch("junction \(op.key) differs from the patch's before value.")
            }
            bytes.replaceSubrange(layout.elements[index].start..<layout.elements[index].end, with: text(after))
        case (nil, nil):
            throw AreaRepairError.invalidPatch("\(op.op.rawValue) \(op.key) has neither before nor after.")
        }
        return Data(bytes)
    }
}

/// The registry policy's static rules for one row
/// (`physical-rail-junctions.json` `policy`, PhysicalRailJunctionRegistry
/// decoding and RouteGraph's loader limits). Checked on every add or update
/// a scratch preview or a write applies, so a row the app's loader would
/// reject never previews as a repair. Endpoint vertices are not checked
/// here: that needs the physical graph (the loader rejects them).
public enum JunctionRowRules {
    static let kinds = ["zeroLength", "shortLink", "osmConnector", "osmTrack"]

    /// Throws `invalidPatch` naming the first broken rule.
    public static func validate(_ row: AreaJSON, op: PatchOp) throws {
        func fail(_ reason: String) -> AreaRepairError { .invalidPatch("\(op.op.rawValue) \(op.key): \(reason)") }
        func text(_ key: String) -> String? {
            row[key]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }
        guard text("id") != nil else { throw fail("id is required.") }
        guard let region = text("region") else { throw fail("region is required.") }
        guard Localization.supportedCountries.contains(region) else {
            throw fail("region \(region) is not one of \(Localization.supportedCountries).")
        }
        let kind = row["kind"].map { $0.stringValue ?? "" } ?? "zeroLength"
        guard kinds.contains(kind) else { throw fail("kind \(kind) is not one of \(kinds).") }
        func endpoint(_ key: String) throws -> Coordinate {
            guard let end = row[key], let identity = end["identity"],
                  ["operatorName", "lineName", "railwayClassCode"].allSatisfy({ identity[$0]?.stringValue?.isEmpty == false }) else {
                throw fail("\(key).identity needs operatorName, lineName and railwayClassCode.")
            }
            guard let point = coordinate(end["coordinate"]) else { throw fail("\(key).coordinate must be a valid [lon, lat].") }
            return point
        }
        let from = try endpoint("from"), to = try endpoint("to")
        guard let evidence = row["evidence"]?.arrayValue, !evidence.isEmpty,
              evidence.allSatisfy({ $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
            throw fail("evidence must list at least one non-empty source (the loader rejects a row without evidence).")
        }
        guard text("geometryEvidence") != nil else { throw fail("geometryEvidence is required.") }
        let lineIDs = row["lineIDs"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if kind != "osmTrack", lineIDs.isEmpty { throw fail("lineIDs must name the joined package lines.") }
        guard Set(lineIDs).count == lineIDs.count else { throw fail("lineIDs repeats a line.") }
        let bounds = ["validFrom", "validTo"].map { row[$0].flatMap { $0 == .null ? nil : $0 } }
        for (name, value) in zip(["validFrom", "validTo"], bounds) where value != nil {
            guard let day = value?.stringValue, isPlainISODay(day) else { throw fail("\(name) must be null or YYYY-MM-DD.") }
        }
        if let a = bounds[0]?.stringValue, let b = bounds[1]?.stringValue, a >= b { throw fail("validFrom must precede validTo.") }

        let metres = Geometry.distanceMeters(from, to)
        let maxLink = RouteGraph.PhysicalJunction.maximumReviewedLinkMeters
        let maxAttach = RouteGraph.PhysicalJunction.maximumOSMAttachMeters
        switch kind {
        case "zeroLength":
            guard from == to else {
                throw fail("a zeroLength row joins identical vertices; its endpoints are \(format(metres)) apart (use shortLink up to \(format(maxLink))).")
            }
        case "shortLink":
            guard from != to else { throw fail("a shortLink row joins two different vertices; use zeroLength.") }
            guard metres <= maxLink else {
                throw fail("a shortLink row may join vertices at most \(format(maxLink)) apart; its endpoints are \(format(metres)) apart.")
            }
            if let link = row["linkMeters"]?.doubleValue, link > maxLink {
                throw fail("linkMeters \(format(link)) exceeds the \(format(maxLink)) shortLink limit.")
            }
        default:
            guard let path = row["path"]?.arrayValue?.map(coordinate), path.count >= 2, path.allSatisfy({ $0 != nil }) else {
                throw fail("an \(kind) row needs a path of at least two valid [lon, lat] points.")
            }
            guard let source = row["source"], field(in: source, "provider") != nil, field(in: source, "license") != nil,
                  source["ways"]?.arrayValue?.isEmpty == false else {
                throw fail("an \(kind) row needs source.provider, source.license and source.ways.")
            }
            let deadEnd = row["terminus"]?["end"]?.stringValue == "to"
            if kind == "osmConnector", row["terminus"] != nil { throw fail("a terminus requires kind osmTrack.") }
            guard let attachFrom = row["attachMeters"]?["from"]?.doubleValue,
                  let attachTo = row["attachMeters"]?["to"]?.doubleValue else {
                throw fail("an \(kind) row needs attachMeters.from and attachMeters.to.")
            }
            guard attachFrom <= maxAttach, deadEnd || attachTo <= maxAttach else {
                throw fail("attach stubs may be at most \(format(maxAttach)); they are \(format(attachFrom)) / \(format(attachTo)).")
            }
            if kind == "osmConnector" {
                let points = path.compactMap { $0 }
                let total = zip(points, points.dropFirst()).reduce(attachFrom + attachTo) { $0 + Geometry.distanceMeters($1.0, $1.1) }
                let maxTotal = RouteGraph.PhysicalJunction.maximumOSMTotalMeters
                guard total <= maxTotal else {
                    throw fail("an osmConnector may be at most \(format(maxTotal)) long with its stubs; it is \(format(total)).")
                }
            }
        }
    }

    /// Every jp add/update row's lineIDs exist in the jp package at
    /// `packageURL` (rows of other regions name lines of their own packages).
    /// A line absent from the package (a retired line) is accepted only when
    /// `rail-history.json` at `historyURL` knows it (`jp-<operator>-<line>`
    /// from a section, station or identity period) and the row's
    /// [validFrom, validTo) overlaps one of that line's known periods.
    public static func validateLineIDs(_ ops: [PatchOp], packageURL: URL, historyURL: URL? = nil) throws {
        let rows = ops.filter { $0.op.file == .junctions }.compactMap { op in op.after.map { (op, $0) } }
            .filter { $0.1["region"]?.stringValue == "jp" }
        guard !rows.isEmpty else { return }
        struct Package: Decodable { struct Line: Decodable { let id: String }; let lines: [Line] }
        let known = Set(try JSONDecoder().decode(Package.self, from: Data(contentsOf: packageURL)).lines.map(\.id))
        var history: [String: [HistoryPeriod]]?
        for (op, row) in rows {
            let missing = (row["lineIDs"]?.arrayValue ?? []).compactMap(\.stringValue).filter { !known.contains($0) }
            guard !missing.isEmpty else { continue }
            if history == nil { history = try historyURL.map(retiredLinePeriods(historyURL:)) ?? [:] }
            let era = HistoryPeriod(from: row["validFrom"]?.stringValue, to: row["validTo"]?.stringValue)
            let unknown = missing.filter { history?[$0] == nil }
            guard unknown.isEmpty else {
                throw AreaRepairError.invalidPatch("\(op.op.rawValue) \(op.key): lineIDs \(unknown) are not lines of \(DataFile.package.relativePath) and not retired lines known to \(DataFile.history.relativePath).")
            }
            let outside = missing.filter { line in !(history?[line] ?? []).contains { $0.overlaps(era) } }
            guard outside.isEmpty else {
                throw AreaRepairError.invalidPatch("\(op.op.rawValue) \(op.key): the row's era \(era) does not overlap the open years \(DataFile.history.relativePath) gives retired lines \(outside.map { "\($0) \(history?[$0] ?? [])" }).")
            }
        }
    }

    /// A half-open [from, to) day interval; nil bounds are open-ended.
    public struct HistoryPeriod: Equatable, Sendable, CustomStringConvertible {
        public var from: String?
        public var to: String?
        public init(from: String?, to: String?) { self.from = from; self.to = to }
        public func overlaps(_ other: HistoryPeriod) -> Bool {
            (from == nil || other.to == nil || from! < other.to!) && (other.from == nil || to == nil || other.from! < to!)
        }
        public var description: String { "[\(from ?? "…"), \(to ?? "…"))" }
    }

    /// Line id → the periods `rail-history.json` records for it: sections and
    /// stations (by `N02_004`/`N02_003` or operator/line_name) and identity
    /// periods (the identity a line had, `as`).
    public static func retiredLinePeriods(historyURL: URL) throws -> [String: [HistoryPeriod]] {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: historyURL)) as? [String: Any] else {
            throw AreaRepairError.invalidJSON("\(DataFile.history.relativePath) is not an object")
        }
        var periods: [String: [HistoryPeriod]] = [:]
        func add(_ operatorName: Any?, _ lineName: Any?, _ entry: [String: Any]) {
            guard let op = operatorName as? String, let line = lineName as? String, !op.isEmpty, !line.isEmpty else { return }
            let period = HistoryPeriod(from: entry["valid_from"] as? String, to: entry["valid_to"] as? String)
            let id = "jp-\(op)-\(line)"
            if periods[id]?.contains(period) != true { periods[id, default: []].append(period) }
        }
        for key in ["sections", "stations"] {
            for feature in root[key] as? [[String: Any]] ?? [] {
                guard let p = feature["properties"] as? [String: Any] else { continue }
                add(p["N02_004"] ?? p["operator"], p["N02_003"] ?? p["line_name"], p)
            }
        }
        for entry in root["identity_periods"] as? [[String: Any]] ?? [] {
            guard let identity = entry["as"] as? [String: Any] else { continue }
            add(identity["N02_004"], identity["N02_003"], entry)
        }
        return periods
    }

    static func coordinate(_ value: AreaJSON?) -> Coordinate? {
        guard let pair = value?.arrayValue?.compactMap(\.doubleValue), pair.count == 2,
              let point = Coordinate(pair: pair), point.lon.isFinite, point.lat.isFinite,
              (-180...180).contains(point.lon), (-90...90).contains(point.lat) else { return nil }
        return point
    }

    static func field(in object: AreaJSON, _ key: String) -> String? {
        object[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isPlainISODay(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else { return false }
        return [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy { (48...57).contains(scalars[$0].value) }
    }

    static func format(_ metres: Double) -> String { String(format: "%.1f m", metres) }
}
