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

    /// The file at `path` relative to `ios/`, or throws when it cannot be read or
    /// holds no text (an empty file would also be scanned as "nothing found").
    public static func text(_ path: String, relativeTo base: URL = ios) throws -> String {
        let url = base.appendingPathComponent(path)
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SourceFileError(path: url.path, underlying: error)
        }
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw SourceFileError(path: url.path, underlying: EmptySourceFile())
        }
        return text
    }

    /// For call sites that cannot throw (computed properties, plain functions): an
    /// unreadable or empty file records a test failure in the CALLING test, so the
    /// test cannot pass on empty text.
    ///
    /// Call it from a computed property (`static var x: String { ... }`) or inside
    /// the test, never from a stored `static let`: a stored property runs once, so
    /// only the first test to touch it would get the failure and every later test
    /// in the suite would scan "" and pass. `RegressionGuardSourceFiles` enforces
    /// this.
    public static func textRecording(
        _ path: String, relativeTo base: URL = ios, sourceLocation: SourceLocation = #_sourceLocation
    ) -> String {
        do {
            return try text(path, relativeTo: base)
        } catch {
            Issue.record("\(error)", sourceLocation: sourceLocation)
            return ""
        }
    }
}

struct EmptySourceFile: Error, CustomStringConvertible {
    var description: String { "the file is empty" }
}

public struct SourceFileError: Error, CustomStringConvertible {
    public let path: String
    public let underlying: Error
    public var description: String {
        "cannot read source file \(path) (\(underlying)); the guard would scan nothing"
    }
}
