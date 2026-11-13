import Foundation
import RailCore

/// The committed stroke-bake fixture (`Fixtures/stroke-network.json`) decoded into engine input
/// the way the app and `RailBakeKit` decode a builder directory: `DisplayChunk` then
/// `StrokeLineInput.make`.
enum StrokeBakeFixtures {
    struct Meta: Decodable {
        var id: String
        var region: String
        var `operator`: String?
        var color: String
        var colorDark: String
    }

    struct Entry: Decodable {
        var lineKey: String
        var meta: Meta
        var chunk: DisplayChunk
    }

    struct FixtureRegion: Decodable {
        var families: [String: DisplayChunk.FamilyColor]
        var lines: [Entry]
    }

    struct Fixture: Decodable {
        var regions: [String: FixtureRegion]
    }

    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")
    }

    static func load() throws -> Fixture {
        try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: directory.appending(path: "stroke-network.json")))
    }

    /// All regions in region-name order, each region's chains in file order.
    static func network(
        _ fixture: Fixture, shiftToGCJ02: Set<String> = []
    ) -> NetworkStrokeBake.Network {
        var lines: [StrokeLineInput] = []
        var anchors: [String: [Int]] = [:]
        for region in fixture.regions.keys.sorted() {
            let data = fixture.regions[region]!
            let metadata = Dictionary(uniqueKeysWithValues: data.lines.map {
                ($0.lineKey, DisplayLineMetadata(
                    id: $0.meta.id, region: $0.meta.region, operatorName: $0.meta.operator,
                    color: $0.meta.color, colorDark: $0.meta.colorDark))
            })
            for entry in data.lines {
                for fragment in entry.chunk.lines {
                    if let line = StrokeLineInput.make(
                        fragment: fragment, metadata: metadata[entry.lineKey]!,
                        families: data.families, shiftToGCJ02: shiftToGCJ02.contains(region)) {
                        lines.append(line)
                    }
                }
                anchors.merge(
                    StrokeLineInput.anchors(stations: entry.chunk.stations, lineMetadata: { metadata[$0] }),
                    uniquingKeysWith: { first, _ in first })
            }
        }
        return NetworkStrokeBake.Network(lines: lines, anchors: anchors)
    }

    /// The part style the golden's "dated" passes were captured with: part % 3 is 0 solid,
    /// 1 historical, 2 hidden; a continuous chain is judged by its chain index.
    static func datedStyle(_ line: StrokeLineInput, _ part: Int) -> StrokeBake.PartStyle {
        let index: Int
        if line.continuous {
            index = Int(line.id.split(separator: "#").last ?? "0") ?? 0
        } else {
            index = part
        }
        switch index % 3 {
        case 1: return .historical
        case 2: return .hidden
        default: return .solid
        }
    }
}
