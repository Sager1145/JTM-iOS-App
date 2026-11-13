import Foundation
import RailCore
import Testing
@testable import RailBakeKit

/// The command line's argument handling, the report and the compare, on a small written pack.
@Suite("RailBakeCommand")
struct RailBakeCommandTests {

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func add(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    @Test("--levels reads ranges and lists, ascending only")
    func levels() throws {
        #expect(try PackBake.parseLevels("8...34") == Array(8...34))
        #expect(try PackBake.parseLevels("8-10") == [8, 9, 10])
        #expect(try PackBake.parseLevels("8,12,34") == [8, 12, 34])
        #expect(PackBake.defaultLevels == Array(8...34))
        #expect(try PackBake.ladder(levels: PackBake.defaultLevels) == RailPackLadder.default)
        for bad in ["", "34,8", "8,8", "a", "10...8", "-3"] {
            #expect(throws: PackBake.Failure.self) { try PackBake.parseLevels(bad) }
        }
    }

    @Test("a hash is 64 hex digits")
    func hashes() {
        #expect(PackBake.hex(String(repeating: "ab", count: 32)) == [UInt8](repeating: 0xAB, count: 32))
        #expect(PackBake.hex("abc") == nil)
        #expect(PackBake.hex(String(repeating: "zz", count: 32)) == nil)
    }

    @Test("arguments that make no sense are refused with the usage, not guessed at")
    func refusals() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zero = String(repeating: "00", count: 32)
        func status(_ arguments: [String]) -> (Int32, [String]) {
            let out = Lines()
            let code = RailBakeCommand.run(arguments: arguments) { out.add($0) }
            return (code, out.all)
        }
        #expect(status([]).0 != 0)
        #expect(status(["--nonsense"]).0 != 0)
        #expect(status(["--region"]).0 != 0)
        let base = ["--builder-dir", directory.path, "--region", "hk", "--inputs-sha256", zero, "--output", "/dev/null"]
        // The fixture directory has no topology.bin: the bake must not invent one.
        let missing = status(base)
        #expect(missing.0 != 0 && missing.1.contains { $0.contains("hk.topology.bin") })
        #expect(status(base + ["--datum", "mercator"]).0 != 0)
        #expect(status(base + ["--levels", "34,8"]).0 != 0)
        #expect(status(Array(base.prefix(6)) + ["--inputs-sha256", "xyz", "--output", "/dev/null"]).0 != 0)
        #expect(throws: PackBake.Failure.datumNotForRegion("jp")) {
            try PackBake.bake(
                region: "jp", directory: directory, datum: .gcj02, levels: [26],
                inputsSHA256: [UInt8](repeating: 0, count: 32))
        }
    }

    @Test("--report-of and --compare work on written packs, and compare notices a difference")
    func reportAndCompare() throws {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try PackAssemblerTests.fixtureRegion("hk", directory: directory, referenceLevel: 26)
        let a = try RailPackWriter.write(try PackAssemblerTests.assemble(display, topology, levels: [20, 26]))
        let b = try RailPackWriter.write(try PackAssemblerTests.assemble(display, topology, levels: [20, 26, 30]))
        let fileA = FileManager.default.temporaryDirectory.appending(path: "rb-a-\(UUID().uuidString).railpack")
        let fileA2 = FileManager.default.temporaryDirectory.appending(path: "rb-a2-\(UUID().uuidString).railpack")
        let fileB = FileManager.default.temporaryDirectory.appending(path: "rb-b-\(UUID().uuidString).railpack")
        defer { for url in [fileA, fileA2, fileB] { try? FileManager.default.removeItem(at: url) } }
        try a.write(to: fileA)
        try a.write(to: fileA2)
        try b.write(to: fileB)

        let report = Lines()
        #expect(RailBakeCommand.run(arguments: ["--report-of", fileA.path]) { report.add($0) } == 0)
        let text = report.all.joined(separator: "\n")
        #expect(text.contains("total:") && text.contains("maxTilePieces"))
        #expect(text.split(separator: "\n").count == 4, "header, two levels, total")

        let same = Lines()
        #expect(RailBakeCommand.run(arguments: ["--compare", fileA.path, fileA2.path]) { same.add($0) } == 0)
        let different = Lines()
        #expect(RailBakeCommand.run(arguments: ["--compare", fileA.path, fileB.path]) { different.add($0) } != 0)
        #expect(different.all.contains { $0.contains("level count") })
    }
}
