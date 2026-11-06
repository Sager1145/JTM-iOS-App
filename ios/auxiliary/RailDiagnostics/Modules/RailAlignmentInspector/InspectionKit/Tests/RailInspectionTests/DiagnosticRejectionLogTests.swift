import Foundation
import Testing
@testable import RailInspection

struct DiagnosticRejectionLogTests {
    @Test func lenientIdentityAndAppend() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rejection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session").path
        let data = Data("{\"requestID\":\"r1\",\"sessionDirectory\":\"\(session)\",\"workspace\":42}".utf8)
        #expect(DiagnosticRejectionLog.identity(in: data).requestID == "r1")
        #expect(DiagnosticRejectionLog.identity(in: Data("nope".utf8)).requestID == nil)
        DiagnosticRejectionLog.record(requestPath: "/a.json", requestData: data, reason: "bad", root: root)
        DiagnosticRejectionLog.record(requestPath: "/b.json", reason: "worse", root: root)
        let lines = try String(contentsOf: root.appendingPathComponent("diagnostics/inbox/rejections.jsonl"), encoding: .utf8)
            .split(separator: "\n").map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        #expect(lines.count == 2)
        #expect(lines[0]["requestID"] as? String == "r1")
        #expect(lines[1]["requestID"] == nil)
        let last = try Data(contentsOf: URL(fileURLWithPath: session).appendingPathComponent("last-rejection.json"))
        #expect((try JSONSerialization.jsonObject(with: last) as? [String: Any])?["reason"] as? String == "bad")
    }
}
