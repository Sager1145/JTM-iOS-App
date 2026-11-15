import Foundation
import RailCore
import Testing

@testable import RailBakeKit

/// `PackTopology` reads the file the router branch writes (`RailTopologyFormat` v2) through the
/// same reader the app uses (`RailTopology`); there is no second format reader in the bake.
struct PackTopologyTests {

    /// The v2 file checked in with RailCore's own tests.
    static let fixture: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "RailKit/Tests/RailCoreTests/Topology/Fixtures/topology-mini.bin")

    @Test func readsTheV2FileTheRouterReads() throws {
        let reader = try RailTopology(contentsOf: Self.fixture)
        let topology = try PackTopology.read(from: Self.fixture)
        #expect(RailTopologyFormat.formatVersion == 2 && reader.header.version == 2)
        #expect(topology.region == reader.header.region)
        #expect(topology.displaySHA256 == reader.header.displaySHA256)
        #expect(topology.lines.count == reader.lineCount && topology.lines.count > 0)
        #expect(topology.nodes.count == reader.nodeTotal)
        var next = 0
        for (index, line) in topology.lines.enumerated() {
            #expect(line.id == reader.lineID(UInt16(index)))
            #expect(line.nodeCount == reader.nodeCount(ofLine: UInt16(index)))
            #expect(line.firstNode == next)
            next += line.nodeCount
        }
    }

    @Test func refusesWhatTheAppReaderRefuses() throws {
        var v1 = try Data(contentsOf: Self.fixture)
        v1[RailTopologyFormat.Header.versionOffset] = 1
        var truncated = try Data(contentsOf: Self.fixture)
        truncated.removeLast(4)
        let directory = FileManager.default.temporaryDirectory.appending(path: "pack-topology-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, bytes) in [("v1.bin", v1), ("short.bin", truncated)] {
            let url = directory.appending(path: name)
            try bytes.write(to: url)
            #expect(throws: PackTopology.Failure.self) { try PackTopology.read(from: url) }
            #expect(throws: (any Error).self) { try RailTopology(contentsOf: url) }
        }
    }
}
