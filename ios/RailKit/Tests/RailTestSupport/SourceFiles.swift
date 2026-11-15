import Foundation
import Testing

/// Shared reader for the source-scanning regression guards.
///
/// One place locates the `ios/` directory and reads a file under it (or under
/// `ios/RailKit/Sources/RailCore`) as text. A file that cannot be read is a
/// failure, never an empty string: a guard that scans nothing would pass every
/// `!contains(...)` assertion.
public enum SourceFiles {
    /// The `ios/` directory, located from this file's own path
    /// (`ios/RailKit/Tests/RailTestSupport/SourceFiles.swift`).
    public static let ios: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RailTestSupport
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // RailKit
        .deletingLastPathComponent() // ios

    /// `ios/RailKit/Sources/RailCore`.
    public static let railCoreSources: URL = ios.appendingPathComponent("RailKit/Sources/RailCore")

    /// The file at `path` relative to `ios/`, or throws when it cannot be read.
    public static func text(_ path: String, relativeTo base: URL = ios) throws -> String {
        let url = base.appendingPathComponent(path)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SourceFileError(path: url.path, underlying: error)
        }
    }

    /// For call sites that cannot throw (static lets, plain functions): an unreadable
    /// file records a test failure first, so the test cannot pass on empty text.
    public static func textRecording(_ path: String, relativeTo base: URL = ios) -> String {
        do {
            return try text(path, relativeTo: base)
        } catch {
            Issue.record("\(error)")
            return ""
        }
    }
}

public struct SourceFileError: Error, CustomStringConvertible {
    public let path: String
    public let underlying: Error
    public var description: String {
        "cannot read source file \(path) (\(underlying)); the guard would scan nothing"
    }
}
