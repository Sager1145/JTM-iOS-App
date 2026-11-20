import Foundation
import RailTestSupport
import Testing

/// The source-scanning guards read app and package sources as text. A guard that
/// reads nothing passes every `!contains(...)` check, so a missing or empty file
/// must fail EVERY test that uses it, not only the first one in the suite.
@Suite("RegressionGuardSourceFiles")
struct RegressionGuardSourceFiles {
    private static let missing = "RailMap/NoSuchDirectory/NoSuchFile.swift"

    @Test func aMissingFileThrows() {
        #expect(throws: SourceFileError.self) { try SourceFiles.text(Self.missing) }
    }

    /// Two calls, two recorded failures: the failure is not used up by the first caller.
    @Test func aMissingFileRecordsAFailureOnEveryCall() {
        for _ in 0..<2 {
            var text = "unset"
            withKnownIssue { text = SourceFiles.textRecording(Self.missing) }
            #expect(text.isEmpty)
        }
    }

    @Test func anEmptyFileIsAFailureToo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-files-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent("empty.swift"))
        try Data(" \n\t\n".utf8).write(to: dir.appendingPathComponent("blank.swift"))
        try Data("let a = 1\n".utf8).write(to: dir.appendingPathComponent("real.swift"))
        for name in ["empty.swift", "blank.swift"] {
            #expect(throws: SourceFileError.self) { try SourceFiles.text(name, relativeTo: dir) }
            withKnownIssue { _ = SourceFiles.textRecording(name, relativeTo: dir) }
        }
        #expect(try SourceFiles.text("real.swift", relativeTo: dir) == "let a = 1\n")
        #expect(SourceFiles.textRecording("real.swift", relativeTo: dir) == "let a = 1\n")
    }

    /// A stored `static let` holding the text a `SourceFiles` reader returned (or a
    /// file-level `let`) is initialised once, inside whichever test touches it first. Only
    /// that test gets the missing-file failure; the others see "" and pass. So
    /// source text is read through a computed property or inside the test.
    @Test func noTestKeepsSourceTextInAStoredStaticOrGlobal() throws {
        let tests = SourceFiles.ios.appendingPathComponent("RailKit/Tests")
        let files = try #require(FileManager.default.enumerator(atPath: tests.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".swift") }
        #expect(files.count > 100, "test sources not found")
        let reader = "SourceFiles" + ".text"
        var readers = 0
        for file in files {
            let text = try SourceFiles.text(file, relativeTo: tests)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(reader) {
                readers += 1
                let declaration = line.components(separatedBy: reader)[0]
                let storedStatic = declaration.contains("static let ")
                    || (declaration.contains("static var ") && declaration.contains("=") && !declaration.contains("{"))
                let global = (declaration.hasPrefix("let ") || declaration.hasPrefix("var ")
                    || declaration.hasPrefix("private let ") || declaration.hasPrefix("private var ")
                    || declaration.hasPrefix("fileprivate let ") || declaration.hasPrefix("fileprivate var "))
                    && !declaration.contains("{")
                #expect(!storedStatic && !global,
                        "\(file):\(index + 1) stores source text once for the whole suite; use `static var name: String { ... }`")
            }
        }
        #expect(readers > 60, "the scan found too few source reads (\(readers)) to be looking at the guards")
    }
}

/// The golden-capture package is kept as `.txt` sources. It was once committed
/// with the absolute path of the worktree it was captured in.
@Suite("RegressionGuardFixturePaths")
struct RegressionGuardFixturePaths {
    @Test func captureFixtureSourcesCarryNoMachinePath() throws {
        let base = "RailKit/Tests/RailCoreTests/StrokeBake/Fixtures"
        let dir = SourceFiles.ios.appendingPathComponent(base + "/golden-capture")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".txt") }
        #expect(names.count >= 5, "golden-capture sources not found")
        for name in names {
            let text = try SourceFiles.text(base + "/golden-capture/" + name)
            for marker in ["/Users/", "/home/", ".claude/worktrees", "/private/tmp"] {
                #expect(!text.contains(marker), "\(name) carries a machine path (\(marker))")
            }
        }
        let package = try SourceFiles.text(base + "/golden-capture/Package.swift.txt")
        #expect(package.contains(#".package(path: "RAILKIT_CHECKOUT_PATH")"#))
        let readme = try SourceFiles.text(base + "/README.md")
        #expect(readme.contains("RAILKIT_CHECKOUT_PATH"), "the README must say which placeholder to set")
    }
}
