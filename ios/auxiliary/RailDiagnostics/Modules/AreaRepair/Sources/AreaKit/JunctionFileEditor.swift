import Foundation

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
