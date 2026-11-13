import Foundation

/// The size ceilings of the pack bake (`ios/tools/railbake/pack-budgets.json`, design
/// docs/maintenance/2026-11-13-rail-pack-size-design.md, section 4.6).
///
/// `RailBake --budgets FILE` checks a finished pack against them before writing it and fails with
/// every limit it broke. The file is part of the pack's inputs hash, so changing a ceiling forces a
/// rebake and a recheck. Ceilings are data: real growth of the network is a deliberate edit here,
/// never a loosening to make a bake pass.
public struct PackBudget: Decodable, Equatable, Sendable {

    public struct Pack: Decodable, Equatable, Sendable {
        /// Largest file, in bytes (either datum).
        public var bytes: Int
        /// Vertex ceiling per level, keyed by the level's half-zoom index k (zoom x 2) as text.
        public var levelVertices: [String: Int]
    }

    /// All packs of the bundle together: 60,000,000 bytes (user requirement).
    public var bundleBytes: Int
    /// Most vertices a phone-sized view plus one ring may mount, at any level.
    public var phoneWindowVertices: Int
    /// The same for a pad-sized view.
    public var padWindowVertices: Int
    public var packs: [String: Pack]

    public struct Violation: Error, CustomStringConvertible {
        public var messages: [String]
        public var description: String { "over budget:\n  " + messages.joined(separator: "\n  ") }
    }

    public static func load(from url: URL) throws -> PackBudget {
        try JSONDecoder().decode(PackBudget.self, from: Data(contentsOf: url))
    }

    /// Every limit `report` (of a pack of `region`) breaks; empty when it is within budget.
    public func violations(region: String, report: PackReport) -> [String] {
        var found: [String] = []
        guard let limit = packs[region] else { return ["no budget for region \(region) in the budgets file"] }
        if report.fileBytes > limit.bytes {
            found.append("\(region): \(report.fileBytes) bytes exceeds the pack budget of \(limit.bytes)")
        }
        for level in report.levels {
            let k = Int((level.zoom * 2).rounded())
            if let ceiling = limit.levelVertices[String(k)], level.vertices > ceiling {
                found.append("\(region) z\(level.zoom): \(level.vertices) vertices exceeds \(ceiling)")
            }
            if level.phoneWindowVertices > phoneWindowVertices {
                found.append("\(region) z\(level.zoom): a phone view plus one ring mounts \(level.phoneWindowVertices) vertices, over \(phoneWindowVertices)")
            }
            if level.padWindowVertices > padWindowVertices {
                found.append("\(region) z\(level.zoom): a pad view plus one ring mounts \(level.padWindowVertices) vertices, over \(padWindowVertices)")
            }
        }
        return found
    }

    public func check(region: String, report: PackReport) throws {
        let found = violations(region: region, report: report)
        if !found.isEmpty { throw Violation(messages: found) }
    }
}
