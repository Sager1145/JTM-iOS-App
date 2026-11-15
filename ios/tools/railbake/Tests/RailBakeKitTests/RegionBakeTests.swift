import Foundation
import RailCore
import Testing
@testable import RailBakeKit

/// DisplayInput and RegionBake against a builder-output directory re-packed from the committed
/// RailKit stroke fixture (real hk, mo and a jp selection, plus synthetic chains).
@Suite("RegionBake")
struct RegionBakeTests {

    static let fixtureURL: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RailBakeKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // railbake
            .deletingLastPathComponent() // tools
            .deletingLastPathComponent() // ios
            .appending(path: "RailKit/Tests/RailCoreTests/StrokeBake/Fixtures/stroke-network.json")
    }()

    /// A directory in the layout `build-display-network.py` writes: `manifest.json` and one
    /// `{region}.display.bin` of concatenated chunk documents.
    static func makeBuilderDirectory() throws -> URL {
        let fixture = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let regions = try #require(fixture["regions"] as? [String: [String: Any]])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "railbake-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifestLines: [String: Any] = [:]
        var records: [[String: Any]] = []
        for region in regions.keys.sorted() {
            let entries = try #require(regions[region]?["lines"] as? [[String: Any]])
            var blob = Data()
            for entry in entries {
                let key = try #require(entry["lineKey"] as? String)
                var meta = try #require(entry["meta"] as? [String: Any])
                let chunk = try JSONSerialization.data(
                    withJSONObject: try #require(entry["chunk"]), options: [.sortedKeys])
                meta["chunk"] = ["offset": blob.count, "length": chunk.count]
                manifestLines[key] = meta
                blob.append(chunk)
            }
            let file = "\(region).display.bin"
            try blob.write(to: directory.appending(path: file))
            records.append([
                "region": region, "file": file, "bytes": blob.count,
                "families": regions[region]?["families"] ?? [:],
            ])
        }
        let manifest: [String: Any] = ["format": "test", "lines": manifestLines, "regions": records]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appending(path: "manifest.json"))
        return directory
    }

    @Test("a region's chains come out of the directory the way the fixture decodes")
    func loadsRegion() throws {
        let directory = try Self.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try DisplayInput.load(region: "hk", from: directory)
        let fixture = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: Self.fixtureURL))
        let expected = fixture.network(region: "hk")
        #expect(loaded.network.lines.map(\.id) == expected.lines.map(\.id))
        #expect(loaded.network.anchors == expected.anchors)
        #expect(loaded.network.lines.count > 20)
        for (a, b) in zip(loaded.network.lines, expected.lines) {
            #expect(a.intervals.count == b.intervals.count)
            #expect(a.laneRows == b.laneRows)
            #expect(a.lane == b.lane)
            for (p, q) in zip(a.intervals.joined(), b.intervals.joined()) {
                #expect(abs(p.lon - q.lon) < 1e-9 && abs(p.lat - q.lat) < 1e-9)
            }
        }
    }

    @Test("a baked level equals baking the same input directly, twice over")
    func bakesLevel() throws {
        let directory = try Self.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try RegionBake.bake(region: "jp", appZoom: 13, from: directory)
        let second = try RegionBake.bake(region: "jp", appZoom: 13, from: directory)
        #expect(first == second)
        let direct = try NetworkStrokeBake.bake(
            try DisplayInput.load(region: "jp", from: directory).network, level: .init(appZoom: 13, datumToken: "wgs84"))
        #expect(first == direct)
        #expect(first.chains.count > 40)
        #expect(first.chains.contains { !$0.withheld.isEmpty })
        #expect(first.chains.contains { !$0.landlord.isEmpty })
        #expect(first.chains.contains { !$0.tenantFallback.isEmpty })
        #expect(first.chains.contains { !$0.nodes.isEmpty })
    }

    @Test("several levels equal their single-level bakes")
    func bakesLevels() throws {
        let directory = try Self.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zooms: [Double] = [5, 10.5, 17]
        let together = try RegionBake.bake(region: "hk", appZooms: zooms, from: directory)
        #expect(together.count == zooms.count)
        for (zoom, baked) in zip(zooms, together) {
            #expect(baked == (try RegionBake.bake(region: "hk", appZoom: zoom, from: directory)))
        }
    }

    @Test("a missing manifest or region is reported, not baked as empty")
    func failures() throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "railbake-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: DisplayInput.Failure.missing("manifest.json")) {
            try DisplayInput.load(region: "hk", from: empty)
        }
        let directory = try Self.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: DisplayInput.Failure.regionNotInManifest("kr")) {
            try DisplayInput.load(region: "kr", from: directory)
        }
    }

    /// Opt-in: `RAILBAKE_BUILDER_DIR=/path/to/display-network RAILBAKE_REGIONS=mo,hk,jp swift test ...`.
    /// Bakes real regions at three levels, twice, and prints what it measured.
    @Test(
        "real builder output bakes deterministically",
        .enabled(if: ProcessInfo.processInfo.environment["RAILBAKE_BUILDER_DIR"] != nil))
    func realBuilderOutput() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: try #require(environment["RAILBAKE_BUILDER_DIR"]))
        let regions = (environment["RAILBAKE_REGIONS"] ?? "mo,hk").split(separator: ",").map(String.init)
        let clock = ContinuousClock()
        for region in regions {
            var network: NetworkStrokeBake.Network?
            let loadTime = try clock.measure { network = try DisplayInput.load(region: region, from: directory).network }
            let loaded = try #require(network)
            for zoom in [6.5, 10.5, 14.0] {
                var first: NetworkStrokeBake.Baked?
                let time = try clock.measure {
                    first = try NetworkStrokeBake.bake(loaded, level: .init(appZoom: zoom, datumToken: "wgs84"))
                }
                let baked = try #require(first)
                let again = try NetworkStrokeBake.bake(loaded, level: .init(appZoom: zoom, datumToken: "wgs84"))
                #expect(baked == again, "\(region) z\(zoom) differs between two bakes")
                let vertices = baked.chains.reduce(0) { $0 + $1.runs.reduce(0) { $0 + $1.vertices.count } }
                let nodes = baked.chains.reduce(0) { $0 + $1.nodes.count }
                print("RegionBake \(region) z\(zoom): \(loaded.lines.count) chains, \(vertices) vertices, \(nodes) nodes, load \(loadTime), bake \(time)")
                #expect(baked.chains.count == loaded.lines.count)
            }
        }
    }

    // The fixture decoded the way RailCore's own tests decode it.
    struct Fixture: Decodable {
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

        struct Region: Decodable {
            var families: [String: DisplayChunk.FamilyColor]
            var lines: [Entry]
        }

        var regions: [String: Region]

        func network(region: String) -> NetworkStrokeBake.Network {
            let data = regions[region]!
            let metadata = Dictionary(uniqueKeysWithValues: data.lines.map {
                ($0.lineKey, DisplayLineMetadata(
                    id: $0.meta.id, region: $0.meta.region, operatorName: $0.meta.operator,
                    color: $0.meta.color, colorDark: $0.meta.colorDark))
            })
            var lines: [StrokeLineInput] = []
            var anchors: [String: [Int]] = [:]
            for entry in data.lines.sorted(by: { $0.lineKey < $1.lineKey }) {
                for fragment in entry.chunk.lines {
                    if let line = StrokeLineInput.make(
                        fragment: fragment, metadata: metadata[entry.lineKey]!,
                        families: data.families, shiftToGCJ02: false) {
                        lines.append(line)
                    }
                }
                anchors.merge(
                    StrokeLineInput.anchors(stations: entry.chunk.stations, lineMetadata: { metadata[$0] }),
                    uniquingKeysWith: { first, _ in first })
            }
            return NetworkStrokeBake.Network(lines: lines, anchors: anchors)
        }
    }
}
