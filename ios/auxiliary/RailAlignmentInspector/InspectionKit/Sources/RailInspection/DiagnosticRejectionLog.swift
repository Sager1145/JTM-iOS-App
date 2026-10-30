import Foundation

/// Durable record of requests refused before admission, which write no run-status or result.
/// Agents read `<evidenceRoot>/diagnostics/inbox/rejections.jsonl` and `<session>/last-rejection.json`.
public enum DiagnosticRejectionLog {
    /// Leniently reads only the identity fields, so a request that fails full decoding is still attributable.
    public static func identity(in data: Data?) -> (requestID: String?, sessionDirectory: String?) {
        guard let data, let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        let path = raw["sessionDirectory"] as? String
        return (raw["requestID"] as? String, path.flatMap { ($0 as NSString).isAbsolutePath ? $0 : nil })
    }

    /// Never throws: a logging failure must not change how the rejection is shown.
    public static func record(requestPath: String?, requestData: Data? = nil, requestID: String? = nil, sessionDirectory: String? = nil,
                              reason: String, root: URL = RailwayEvidenceRoot.resolve()) {
        let found = identity(in: requestData)
        var entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "reason": reason,
            "processID": Int(ProcessInfo.processInfo.processIdentifier)
        ]
        if let requestPath { entry["requestPath"] = requestPath }
        if let id = requestID ?? found.requestID { entry["requestID"] = id }
        let session = sessionDirectory ?? found.sessionDirectory
        if let session { entry["sessionDirectory"] = session }
        guard let line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let manager = FileManager.default
        do {
            let log = try RailwayEvidenceRoot.validatedWriteURL(root.appendingPathComponent("diagnostics/inbox/rejections.jsonl"))
            try manager.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: log.path) { manager.createFile(atPath: log.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: line + Data("\n".utf8))
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data(("Diagnostic rejection log unavailable: " + error.localizedDescription + "\n").utf8))
        }
        if let session {
            do {
                let destination = try RailwayEvidenceRoot.validatedWriteURL(URL(fileURLWithPath: session, isDirectory: true).appendingPathComponent("last-rejection.json"))
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let pretty = try JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys])
                try pretty.write(to: destination, options: .atomic)
            } catch {
                try? FileHandle.standardError.write(contentsOf: Data(("Diagnostic rejection session report unavailable: " + error.localizedDescription + "\n").utf8))
            }
        }
    }
}
