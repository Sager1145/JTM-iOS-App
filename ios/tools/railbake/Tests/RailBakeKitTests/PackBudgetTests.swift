import Foundation
import RailCore
import Testing
@testable import RailBakeKit

/// The size guards: the committed budgets, the window count against a brute force, and the
/// fixture regions against the real ceilings.
@Suite("PackBudget")
struct PackBudgetTests {

    static var budgetsURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "pack-budgets.json")
    }

    static func committed() throws -> PackBudget { try PackBudget.load(from: budgetsURL) }

    /// A small pack of the hk fixture at three levels and its report.
    static func pack(_ name: String = "hk", levels: [Int] = [10, 18, 26]) throws -> (RailPackReader, PackReport) {
        let directory = try RegionBakeTests.makeBuilderDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (display, topology) = try PackAssemblerTests.fixtureRegion(name, directory: directory, referenceLevel: 26)
        let reader = try PackAssemblerTests.reader(try PackAssemblerTests.assemble(display, topology, levels: levels))
        return (reader, try PackReport(reader: reader))
    }

    @Test("the committed budgets are the limits record's: 30 MB bundle, Japan 22 MB, 100k phone view, every region and level present")
    func committedBudgets() throws {
        let budget = try Self.committed()
        #expect(budget.bundleBytes == 30_000_000)
        #expect(budget.packs["jp"]?.bytes == 22_000_000)
        #expect(budget.phoneWindowVertices == 100_000 && budget.padWindowVertices == 200_000)
        #expect(Set(budget.packs.keys) == ["jp", "tw", "hk", "mo", "kr"])
        for (region, pack) in budget.packs {
            #expect(Set(pack.levelVertices.keys) == Set(PackBake.defaultLevels.map(String.init)), "\(region) levels")
            #expect(pack.levelVertices.values.allSatisfy { $0 > 0 }, "\(region)")
            let values = PackBake.defaultLevels.map { pack.levelVertices[String($0)]! }
            #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 * 2 }, "\(region): ceilings are not wildly out of order")
        }
        // One file per region (the GCJ-02 shift is the reader's): every file at its budget stays in the bundle.
        let files = budget.packs.reduce(0) { $0 + $1.value.bytes }
        #expect(files <= budget.bundleBytes, "\(files) bytes of per-pack budgets exceed the bundle")
    }

    /// Bytes of the fixture regions baked at the default ladder in format v2 at the 4-quantum tolerance, measured
    /// (685,276, 28,992 and 848,708), rounded up by 10%. The
    /// fixture is a selection of lines with synthetic station nodes, so these are its own ceilings,
    /// not the real regions'; the real packs are held to `pack-budgets.json` by `RailBake --budgets`.
    static let fixtureBytes: [String: Int] = ["hk": 753_900, "mo": 31_900, "jp": 933_600]

    @Test("the fixture regions stay under their recorded size and the real window caps")
    func fixturesFit() throws {
        let budget = try Self.committed()
        for name in ["hk", "mo", "jp"] {
            let (_, report) = try Self.pack(name, levels: PackBake.defaultLevels)
            #expect(report.fileBytes <= Self.fixtureBytes[name]!, "\(name): \(report.fileBytes) bytes")
            #expect(report.totalVertices > 1_000)
            for level in report.levels {
                #expect(level.phoneWindowVertices <= budget.phoneWindowVertices, "\(name) z\(level.zoom)")
                #expect(level.padWindowVertices <= budget.padWindowVertices, "\(name) z\(level.zoom)")
            }
        }
    }

    @Test("the committed budgets fail a bake over 22,000,000 bytes for Japan or 100,000 vertices in a phone view")
    func committedLimitsBite() throws {
        let budget = try Self.committed()
        let (_, report) = try Self.pack()
        #expect(budget.violations(region: "jp", report: report).isEmpty, "a small pack is within the jp budgets")
        var big = report
        big.fileBytes = 22_000_001
        #expect(budget.violations(region: "jp", report: big).contains { $0.contains("exceeds the pack budget of 22000000") })
        big.fileBytes = 22_000_000
        #expect(budget.violations(region: "jp", report: big).isEmpty, "exactly at the ceiling passes")
        var dense = report
        dense.levels[0].phoneWindowVertices = 100_001
        #expect(budget.violations(region: "jp", report: dense).contains { $0.contains("phone view") && $0.contains("over 100000") })
        dense.levels[0].phoneWindowVertices = 100_000
        #expect(budget.violations(region: "jp", report: dense).isEmpty)
    }

    @Test("each limit is enforced and named")
    func limitsAreEnforced() throws {
        let (_, report) = try Self.pack()
        let roomy = PackBudget(
            bundleBytes: 30_000_000, phoneWindowVertices: 1_000_000, padWindowVertices: 1_000_000,
            packs: ["hk": .init(bytes: 10_000_000, levelVertices: ["10": 1_000_000, "18": 1_000_000, "26": 1_000_000])])
        try roomy.check(region: "hk", report: report)
        #expect(throws: Never.self) { try roomy.check(region: "hk", report: report) }

        func message(_ budget: PackBudget, region: String = "hk") -> String {
            do { try budget.check(region: region, report: report); return "" } catch { return "\(error)" }
        }
        var bytes = roomy
        bytes.packs["hk"]!.bytes = report.fileBytes - 1
        #expect(message(bytes).contains("bytes exceeds the pack budget"))
        var level = roomy
        level.packs["hk"]!.levelVertices["18"] = report.levels[1].vertices - 1
        #expect(message(level).contains("z9.0") && message(level).contains("vertices exceeds"))
        var phone = roomy
        phone.phoneWindowVertices = report.levels.map(\.phoneWindowVertices).max()! - 1
        #expect(message(phone).contains("phone view"))
        var pad = roomy
        pad.padWindowVertices = report.levels.map(\.padWindowVertices).max()! - 1
        #expect(message(pad).contains("pad view"))
        #expect(message(roomy, region: "zz").contains("no budget for region zz"))
        // Exactly at the limit passes.
        var exact = roomy
        exact.packs["hk"]!.bytes = report.fileBytes
        exact.phoneWindowVertices = report.levels.map(\.phoneWindowVertices).max()!
        try exact.check(region: "hk", report: report)
    }

    /// Brute force: every window position over the occupied bounding box, counted from the pieces.
    static func bruteForce(_ reader: RailPackReader, level: Int, columns: Int, rows: Int) throws -> Int {
        let opened = try reader.level(level)
        let info = reader.levels[level]
        let side = RailPackFormat.tileSide(mapPointsPerPoint: info.mapPointsPerPoint)
        let quantum = RailPackFormat.quantum(mapPointsPerPoint: info.mapPointsPerPoint)
        var normal: [[Int]: Int] = [:]
        for index in 0..<opened.pieceCount {
            let row = try opened.piece(index)
            if row.isLong { continue }
            normal[[Int(row.tileX), Int(row.tileY)], default: 0] += Int(row.vertexCount)
        }
        var longs: [(Int, Int, Int, Int, Int)] = []
        for index in 0..<opened.count(.longPieces) {
            let long = try opened.longPieceRow(index)
            func tile(_ q: Int32) -> Int { Int((Double(q) * quantum / side).rounded(.down)) }
            longs.append((tile(long.minX), tile(long.maxX), tile(long.minY), tile(long.maxY),
                          Int(try opened.piece(Int(long.piece)).vertexCount)))
        }
        let xs = normal.keys.map { $0[0] } + longs.flatMap { [$0.0, $0.1] }
        let ys = normal.keys.map { $0[1] } + longs.flatMap { [$0.2, $0.3] }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return 0 }
        var best = 0
        for ax in (x0 - columns + 1)...x1 {
            for ay in (y0 - rows + 1)...y1 {
                var total = 0
                for (tile, count) in normal where tile[0] >= ax && tile[0] < ax + columns && tile[1] >= ay && tile[1] < ay + rows {
                    total += count
                }
                for long in longs where long.0 <= ax + columns - 1 && long.1 >= ax && long.2 <= ay + rows - 1 && long.3 >= ay {
                    total += long.4
                }
                best = max(best, total)
            }
        }
        return best
    }

    @Test("the window maxima equal a brute-force count at every level")
    func windowsMatchBruteForce() throws {
        for name in ["hk", "jp"] {
            let (reader, report) = try Self.pack(name, levels: [8, 14, 20, 26])
            for level in 0..<reader.header.levelCount {
                let phone = try PackWindows.phoneShapes.map { try Self.bruteForce(reader, level: level, columns: $0.columns, rows: $0.rows) }.max()!
                let pad = try PackWindows.padShapes.map { try Self.bruteForce(reader, level: level, columns: $0.columns, rows: $0.rows) }.max()!
                #expect(report.levels[level].phoneWindowVertices == phone, "\(name) level \(level) phone")
                #expect(report.levels[level].padWindowVertices == pad, "\(name) level \(level) pad")
                #expect(phone <= pad && phone > 0)
            }
        }
    }

    @Test("a dense view is where the guard bites: fewer than 100k vertices at the densest level of the fixtures")
    func windowsAreCountedAtEveryLevel() throws {
        let (_, report) = try Self.pack("jp", levels: PackBake.defaultLevels)
        #expect(report.levels.count == 27)
        // The densest phone window grows with zoom until the tiles thin out; it is the largest somewhere in the middle.
        #expect(report.levels.map(\.phoneWindowVertices).max()! > report.levels[0].phoneWindowVertices)
        #expect(report.levels.allSatisfy { $0.phoneWindowVertices <= 100_000 })
    }
}
