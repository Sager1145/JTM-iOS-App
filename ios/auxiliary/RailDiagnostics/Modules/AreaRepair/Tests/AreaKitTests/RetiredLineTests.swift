import Foundation
import Testing
@testable import AreaKit

/// User decision 2026-11-06 ("Allow if in history"): a junction row may name
/// a line absent from the package only when rail-history.json knows the line
/// and the row's era overlaps one of its open periods; unknown lines stay refused.
struct RetiredLineTests {
    private func files() throws -> (package: URL, history: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "retired-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let package = dir.appending(path: "jp-2025.json"), history = dir.appending(path: "rail-history.json")
        try #"{"lines":[{"id":"jp-テスト鉄道-本線"}]}"#.write(to: package, atomically: true, encoding: .utf8)
        try #"""
        {"sections":[{"type":"Feature","properties":{"N02_003":"旧線","N02_004":"テスト鉄道","valid_to":"2014-05-12"},"geometry":null}],
         "stations":[],
         "identity_periods":[{"history_id":"x","match":{},"valid_from":"1990-01-01","valid_to":"2016-03-26","as":{"N02_003":"移管線","N02_004":"テスト鉄道"}}]}
        """#.write(to: history, atomically: true, encoding: .utf8)
        return (package, history)
    }

    private func op(_ lines: [String], from: String?, to: String?) -> PatchOp {
        let row = AreaJSON.object([("id", .string("r")), ("region", .string("jp")),
                                   ("lineIDs", .array(lines.map(AreaJSON.string))),
                                   ("validFrom", from.map(AreaJSON.string) ?? .null),
                                   ("validTo", to.map(AreaJSON.string) ?? .null)])
        return PatchOp(op: .junctionAdd, key: "r", before: nil, after: row)
    }

    @Test func retiredLineKnownToHistoryWithOverlappingEraIsAccepted() throws {
        let (package, history) = try files()
        try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-本線", "jp-テスト鉄道-旧線"], from: "1936-11-10", to: "2014-05-12")],
                                             packageURL: package, historyURL: history)
        // An identity period (the name the line had before a transfer) counts too.
        try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-移管線"], from: "2000-01-01", to: nil)],
                                             packageURL: package, historyURL: history)
    }

    @Test func retiredLineWithEraOutsideItsOpenYearsIsRefused() throws {
        let (package, history) = try files()
        #expect(throws: AreaRepairError.self) {
            try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-旧線"], from: "2014-05-12", to: nil)],
                                                 packageURL: package, historyURL: history)
        }
        #expect(throws: AreaRepairError.self) {
            try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-移管線"], from: "1950-01-01", to: "1990-01-01")],
                                                 packageURL: package, historyURL: history)
        }
    }

    @Test func lineUnknownToPackageAndHistoryIsRefused() throws {
        let (package, history) = try files()
        #expect(throws: AreaRepairError.self) {
            try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-幻線"], from: nil, to: nil)],
                                                 packageURL: package, historyURL: history)
        }
        // Without a history file every absent line stays refused.
        #expect(throws: AreaRepairError.self) {
            try JunctionRowRules.validateLineIDs([op(["jp-テスト鉄道-旧線"], from: "1936-11-10", to: "2014-05-12")],
                                                 packageURL: package)
        }
    }

    @Test func periodOverlapIsHalfOpen() {
        typealias P = JunctionRowRules.HistoryPeriod
        #expect(P(from: nil, to: "2014-05-12").overlaps(P(from: "2014-05-11", to: nil)))
        #expect(!P(from: nil, to: "2014-05-12").overlaps(P(from: "2014-05-12", to: nil)))
        #expect(P(from: nil, to: nil).overlaps(P(from: "2000-01-01", to: "2000-01-02")))
    }

    /// The bundled data: 江差線 (in history) is accepted for its 1936–2016
    /// row; 海峡線 (absent from history) stays refused.
    @Test func bundledRetiredLineRows() throws {
        let repo = try DataRoot.discoverRepo(from: URL(fileURLWithPath: #filePath))
        let package = repo.appending(path: DataFile.package.relativePath), history = repo.appending(path: DataFile.history.relativePath)
        let rows = try JunctionFileEditor.rows(in: Data(contentsOf: repo.appending(path: DataFile.junctions.relativePath)))
        func check(_ id: String) throws {
            let row = try #require(rows.first { $0["id"]?.stringValue == id })
            try JunctionRowRules.validateLineIDs([PatchOp(op: .junctionAdd, key: id, before: nil, after: row)],
                                                 packageURL: package, historyURL: history)
        }
        try check("goryokaku-hakodate-esashi")
        #expect(throws: AreaRepairError.self) { try check("kikonai-esashi-kaikyo") }
    }
}
