import Foundation
import Testing

/// Counts that depend on shipped data (marker totals, train counts) live in a
/// committed, provenance-stamped file instead of as literals in `#expect`.
///
/// When a count moves the file tells the two causes apart:
/// - the stamped inputs changed: data changed, review the diff and regenerate;
/// - the inputs are identical: the code regressed, do not regenerate.
///
/// Files: `RegressionGuards/Resources/expectations/<group>.json`, located from
/// the repository root (not an SPM resource, so no package change).
enum DataCountExpectations {
    static let format = "jtm-data-count-expectations/1"
    static let directory = "ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/expectations"

    struct File: Codable, Equatable {
        var format: String
        var provenance: ArtifactProvenance
        var counts: [String: Int]
    }

    static func path(_ group: String) -> String { "\(directory)/\(group).json" }

    static func regenerateCommand(filter: String) -> String {
        "JTM_REGENERATE_EXPECTATIONS=1 swift test --package-path ios/RailKit --filter \(filter)"
    }

    static func check(
        _ group: String, inputs: [String], counts: [String: Int], filter: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let root = try PortFixtures.repositoryRoot()
        let url = root.appending(path: path(group))
        let command = regenerateCommand(filter: filter)
        let provenance = ArtifactProvenance.current(
            root: root, generator: "ios/RailKit/Tests/RailCoreTests/Support/DataCountExpectations.swift",
            regenerate: command, inputs: inputs, solverDependent: false)

        if ProcessInfo.processInfo.environment["JTM_REGENERATE_EXPECTATIONS"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(File(format: format, provenance: provenance, counts: counts))
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            Issue.record(
                "\(path(group)) is missing. Generate it with:\n  \(command)",
                sourceLocation: sourceLocation)
            return
        }
        let recorded = try JSONDecoder().decode(File.self, from: data)
        if recorded.counts == counts { return }

        let countDiffs = ArtifactProvenance.compare(
            "counts", recorded.counts.mapValues(String.init), counts.mapValues(String.init), short: false)
        let inputDiffs = recorded.provenance.differences(root: root)
        if inputDiffs.isEmpty {
            Issue.record(
                """
                code regression; do not regenerate. \(group) inputs are unchanged but counts moved:
                  \(countDiffs.joined(separator: "\n  "))
                """,
                sourceLocation: sourceLocation)
        } else {
            Issue.record(
                """
                data changed: review key old→new and run \(command); commit the diff.
                  \(countDiffs.joined(separator: "\n  "))
                  inputs:
                  \(inputDiffs.joined(separator: "\n  "))
                """,
                sourceLocation: sourceLocation)
        }
    }
}
