import Foundation
import RailCore

/// What the pack takes from a region's topology file (`{region}.topology.bin`): the line index
/// order, the global node index of each line's ordinal 0, and where every node sits (chain number
/// and metres on that chain's ruler). The pack and the topology of one build are a pair, so the
/// pack header repeats this file's `displaySHA256`.
///
/// Read straight from the file's bytes with `RailTopologyFormat`'s constants; the topology reader
/// itself is not touched.
public struct PackTopology: Sendable, Equatable {

    public struct Line: Sendable, Equatable {
        /// The package line id (`DisplayInput.LineInfo.id`).
        public var id: String
        public var firstNode: Int
        public var nodeCount: Int
        public init(id: String, firstNode: Int, nodeCount: Int) {
            self.id = id
            self.firstNode = firstNode
            self.nodeCount = nodeCount
        }
    }

    public struct Node: Sendable, Equatable {
        /// `Node.chain`: the chain number of a continuous line, the flat part number otherwise.
        public var chain: Int
        /// Metres on the chain's full ruler; nil for a node with no chain slot.
        public var metres: Double?
        public init(chain: Int, metres: Double?) {
            self.chain = chain
            self.metres = metres
        }
    }

    public var region: String
    public var displaySHA256: [UInt8]
    /// In line-index order.
    public var lines: [Line]
    /// By global node index.
    public var nodes: [Node]

    public init(region: String, displaySHA256: [UInt8], lines: [Line], nodes: [Node]) {
        self.region = region
        self.displaySHA256 = displaySHA256
        self.lines = lines
        self.nodes = nodes
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case unreadable(String)

        public var description: String {
            switch self {
            case .unreadable(let why): "topology file unreadable: \(why)"
            }
        }
    }

    public static func read(from url: URL) throws -> PackTopology {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let header: RailTopologyFormat.ParsedHeader
        do { header = try RailTopologyFormat.parseHeader(data) } catch { throw Failure.unreadable("\(error)") }
        func u16(_ offset: Int) -> Int {
            Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
        }
        let strings = header.offset(.strings), stringBytes = header.count(.strings)
        func string(_ reference: UInt32) throws -> String {
            let at = Int(reference)
            guard reference != RailTopologyFormat.noString, at + 2 <= stringBytes else {
                throw Failure.unreadable("string reference \(reference)")
            }
            let length = u16(strings + at)
            guard at + 2 + length <= stringBytes else { throw Failure.unreadable("string length at \(reference)") }
            let start = data.startIndex + strings + at + 2
            return String(decoding: data[start..<(start + length)], as: UTF8.self)
        }
        var lines: [Line] = []
        for index in 0..<header.count(.lines) {
            let base = header.offset(.lines) + index * RailTopologyFormat.Line.size
            lines.append(Line(
                id: try string(u32(base + RailTopologyFormat.Line.id)),
                firstNode: Int(u32(base + RailTopologyFormat.Line.firstNode)),
                nodeCount: Int(u32(base + RailTopologyFormat.Line.nodeCount))))
        }
        var nodes: [Node] = []
        nodes.reserveCapacity(header.count(.nodes))
        for index in 0..<header.count(.nodes) {
            let base = header.offset(.nodes) + index * RailTopologyFormat.Node.size
            let centimetres = u32(base + RailTopologyFormat.Node.fullMetres)
            nodes.append(Node(
                chain: u16(base + RailTopologyFormat.Node.chain),
                metres: centimetres == RailTopologyFormat.unsetMetres ? nil : Double(centimetres) / 100))
        }
        return PackTopology(region: header.region, displaySHA256: header.displaySHA256, lines: lines, nodes: nodes)
    }
}
