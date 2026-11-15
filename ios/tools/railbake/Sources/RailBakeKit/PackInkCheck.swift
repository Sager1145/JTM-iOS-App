import Foundation
import RailCore

/// Every line that should be visible at a level has ink at that level.
///
/// A line is visible at a visibility zoom when its tier (`DisplayInput.LineInfo.tierQuarterZoom`,
/// `lodMinZoom` x 4) is at most four times that zoom. A level serves visibility zooms around its own
/// app zoom (the ladder zoom plus one), so every quarter-zoom step in `offsets` around it is
/// checked, the tier's own granularity. Ink is a piece
/// of one of the line's chains whose group draws at that zoom (`RailPackGroup.isDrawn`). A line can
/// lose its ink where its own pieces have become a tenant fallback that a landlord's group has
/// already given up, or where the landlord's pieces have not yet appeared; this finds it.
public enum PackInkCheck {

    public struct Missing: Equatable, Sendable, CustomStringConvertible {
        public var level: Int
        public var zoom: Double
        /// The visibility zoom (app convention) the line has no ink at.
        public var visibilityZoom: Double
        public var line: String
        public var description: String {
            "z\(zoom) (visibility zoom \(visibilityZoom)): line \(line) is visible but has no ink"
        }
    }

    /// The camera holds a level for 0.45 zoom each way and the device's visibility policy shifts the
    /// visibility zoom by between -1.5 and +0.5 (`NetworkVisibilityPolicy`), so the zooms a level serves
    /// lie between -1.95 and +0.95 around its app zoom; the tier steps in quarter zooms.
    public static let defaultOffsets: [Double] = Array(stride(from: -2.0, through: 1.0, by: 0.25))

    /// `lines` is the pack's line order (the topology's) with each line's tier.
    public static func missing(
        reader: RailPackReader, lines: [(id: String, tier: Int16)], offsets: [Double] = defaultOffsets
    ) throws -> [Missing] {
        var found: [Missing] = []
        let groupRows = try (0..<reader.header.groupCount).map { try reader.group($0) }
        for level in 0..<reader.header.levelCount {
            let zoom = reader.ladder.zooms[level]
            let opened = try reader.level(level)
            // The groups each line's pieces use at this level.
            var groupsOfLine: [[Int]] = []
            for line in 0..<reader.header.lineCount {
                let row = try reader.line(line)
                var groups = Set<Int>()
                for chain in Int(row.firstChain)..<(Int(row.firstChain) + Int(row.chainCount)) {
                    for piece in try opened.pieceRange(chain: chain) {
                        groups.insert(Int(try opened.piece(piece).group))
                    }
                }
                groupsOfLine.append(groups.sorted())
            }
            for offset in offsets {
                let visibility = zoom + RailPackLadder.appZoomOffset + offset
                for (index, line) in lines.enumerated() where Double(line.tier) <= visibility * 4 {
                    if !groupsOfLine[index].contains(where: { groupRows[$0].isDrawn(visibilityZoom: visibility) }) {
                        found.append(Missing(level: level, zoom: zoom, visibilityZoom: visibility, line: line.id))
                    }
                }
            }
        }
        return found
    }
}
