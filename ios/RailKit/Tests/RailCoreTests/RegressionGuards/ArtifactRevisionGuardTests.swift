import Foundation
import Testing

@testable import RailCore

/// Regression guard: generated artifacts must be stamped with, and still match,
/// the inputs they were generated from.
///
/// Bug class: port fixtures, sample parts and Swift-generated expectations go
/// stale after a data or solver change and then fail much later with an opaque
/// diff. Every artifact kind carries (or has recorded in its manifest) the
/// inputs' content hashes plus the solver and history revisions; this guard
/// re-hashes the inputs (about 70 MB, ~0.05 s; part files are not read) and
/// reports `key old → new` with the command that regenerates the artifact.
///
/// Dependency propagation: an artifact whose inputs include another stale
/// artifact's path is stale too (regenerating it first would change nothing).
/// Entries are listed dependencies first.
///
/// Each test reports one combined Issue for its artifact kind; propagation is
/// computed across all kinds.
@Suite("RegressionGuardArtifactRevisions")
struct RegressionGuardArtifactRevisions {
    /// Port fixtures that predate stamping. Shrink-only: stamp a fixture by
    /// giving its module `provenanceInputs`, regenerate it, then delete it here.
    static let legacyUnstampedFixtures: Set<String> = [
        "continuous-stroke.json",
        "coords.json",
        "dates.json",
        "distance.json",
        "family-windows.json",
        "grooming.json",
        "i18n.json",
        "import.json",
        "intervals.json",
        "operator-branding.json",
        "overlap-lanes.json",
        "route-feature.json",
        "route-graph.json",
        "route-hints.json",
        "route-section-solve.json",
        "route-solver-core.json",
        "route-station-candidates.json",
        "simplify.json",
        "station-join-smoothing.json",
        "station-visibility.json",
        "stations.json",
        "store-ops.json",
        "validation.json",
        "visibility.json",
    ]

    /// Swift-written expectation files (repo-relative) outside
    /// `DataCountExpectations.directory`. Each must carry a top-level
    /// `provenance` object.
    static let stampedGenerated: [String] = [
        "app/data/registry/jp/history-registry-differences.json"
    ]

    struct Dataset {
        let directory: String
        let country: String
        let store: String
        let command: String
    }

    static let datasets: [Dataset] = [
        Dataset(
            directory: "sample-data", country: "jp", store: "app/data/train-store.json",
            command: "(cd app && npm run precompute)"),
        Dataset(
            directory: "sample-data-tw", country: "tw", store: "app/data/train-store-tw.json",
            command: "(cd app && npm run precompute:tw)"),
        Dataset(
            directory: "sample-data-hk", country: "hk", store: "app/data/train-store-hk.json",
            command: "(cd app && npm run precompute:hk)"),
        Dataset(
            directory: "sample-data-kr", country: "kr", store: "app/data/train-store-kr.json",
            command: "(cd app && npm run precompute:kr)"),
        Dataset(
            directory: "sample-data-mo", country: "mo", store: "app/data/train-store-mo.json",
            command: "(cd app && npm run precompute:mo)"),
        Dataset(
            directory: "new-year-grand-loop-data", country: "jp",
            store: "app/data/special-samples/new-year-grand-loop.json",
            command: "(cd app && npm run precompute:new-year-grand-loop)"),
        Dataset(
            directory: "tokyo-limited-express-loop-data", country: "jp",
            store: "app/data/special-samples/tokyo-limited-express-loop.json",
            command: "(cd app && npm run precompute:tokyo-limited-express-loop)"),
    ]

    // MARK: - model

    enum Kind: Int { case sample, fixture, expectation }

    struct Artifact {
        let kind: Kind
        let path: String
        let inputs: [String]
        var differences: [String]
        let command: String
    }

    /// Every artifact with its own differences; computed once per process.
    private static let analysis: [Artifact] = {
        do {
            let root = try PortFixtures.repositoryRoot()
            return samples(root) + fixtures(root) + expectations(root)
        } catch {
            return [
                Artifact(
                    kind: .sample, path: "repository root", inputs: [],
                    differences: ["\(error)"], command: "")
            ]
        }
    }()

    /// Stale artifacts of `kind` as one report, dependencies first; nil when current.
    private static func report(_ kind: Kind) -> String? {
        let all = analysis
        let byPath = Dictionary(all.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var staleOwn = Set(all.filter { !$0.differences.isEmpty }.map(\.path))
        // Propagate until nothing new turns stale.
        var changed = true
        var because: [String: [String]] = [:]
        while changed {
            changed = false
            for artifact in all where !staleOwn.contains(artifact.path) {
                let stale = artifact.inputs.filter { input in
                    staleOwn.contains { input == $0 || input.hasPrefix($0 + "/") }
                }
                if !stale.isEmpty {
                    staleOwn.insert(artifact.path)
                    because[artifact.path] = stale
                    changed = true
                }
            }
        }
        var ordered: [String] = []
        var visited = Set<String>()
        func visit(_ path: String) {
            guard visited.insert(path).inserted, let artifact = byPath[path] else { return }
            for input in artifact.inputs.sorted() {
                for candidate in staleOwn where input == candidate || input.hasPrefix(candidate + "/") {
                    visit(candidate)
                }
            }
            ordered.append(path)
        }
        for artifact in all.sorted(by: { ($0.kind.rawValue, $0.path) < ($1.kind.rawValue, $1.path) })
        where staleOwn.contains(artifact.path) {
            visit(artifact.path)
        }
        let entries = ordered.compactMap { path -> String? in
            guard let artifact = byPath[path], artifact.kind == kind, staleOwn.contains(path) else {
                return nil
            }
            var lines = [path]
            lines += artifact.differences.map { "    \($0)" }
            lines += (because[path] ?? []).map { "    stale because input \($0) is stale" }
            if !artifact.command.isEmpty { lines.append("    $ \(artifact.command)") }
            return lines.joined(separator: "\n")
        }
        return entries.isEmpty ? nil : entries.joined(separator: "\n\n")
    }

    private static func fail(_ title: String, _ kind: Kind) {
        guard let report = report(kind) else { return }
        Issue.record(Comment(rawValue: "\(title), dependencies first:\n\n\(report)"))
    }

    // MARK: - samples

    private static func jsonObject(_ url: URL) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any]
    }

    private static func historyPath(_ cc: String) -> String {
        cc == "jp" ? "app/data/rail-history.json" : "app/data/rail-history-\(cc).json"
    }

    private static func samples(_ root: URL) -> [Artifact] {
        let swiftVersion = RouteGraph.routeSolverCacheVersion
        let jsVersion = ArtifactProvenance.jsRouteSolverCacheVersion(root: root)
        return datasets.map { dataset in
            let directory = "app/data/\(dataset.directory)"
            guard let manifest = jsonObject(root.appending(path: "\(directory)/manifest.json")) else {
                return Artifact(
                    kind: .sample, path: directory, inputs: [],
                    differences: ["manifest.json is missing or unreadable"], command: dataset.command)
            }
            var diffs: [String] = []
            let context = manifest["solver_context"] as? [String: Any] ?? [:]
            let version = context["solver_version"] as? String ?? "none"
            if version != swiftVersion {
                diffs.append("solver_version (RouteGraph.routeSolverCacheVersion) \(version) → \(swiftVersion)")
            }
            if version != jsVersion {
                diffs.append("solver_version (ROUTE_SOLVER_CACHE_VERSION in app-config.js) \(version) → \(jsVersion)")
            }

            let revisions = context["history_revisions"] as? [String: String] ?? [:]
            let recordedHashes = context["history_hashes"] as? [String: String] ?? [:]
            let scope = revisions.keys.sorted()
            var currentRevisions: [String: String] = [:]
            var currentHashes: [String: String] = [:]
            for cc in scope {
                let path = historyPath(cc)
                currentRevisions[cc] = ArtifactProvenance.historyRevision(root: root, path: path)
                let hash = ArtifactProvenance.sha256(root: root, path: path)
                if hash != "none" { currentHashes[cc] = hash }
            }
            diffs += ArtifactProvenance.compare("history_revisions", revisions, currentRevisions, short: false)
            diffs += ArtifactProvenance.compare("history_hashes", recordedHashes, currentHashes, short: true)

            // The key set is the precompute's `currentPrecomputeSourceHashes`.
            var sources: [String: String] = [:]
            for name in ["matched-routes.json", "matched-stops.json", "physical-rail-junctions.json"] {
                sources[name] = "app/data/\(name)"
            }
            for cc in scope {
                let suffix = cc == "jp" ? "" : "-\(cc)"
                sources["\(cc)-2025.json"] = "app/public/rail/\(cc)-2025.json"
                sources["rail-sections\(suffix).json"] = "app/data/rail-sections\(suffix).json"
                sources["stations\(suffix).json"] = "app/data/stations\(suffix).json"
                if currentHashes[cc] != nil {
                    sources["rail-history\(suffix).json"] = historyPath(cc)
                }
            }
            let recordedSources = manifest["source_hashes"] as? [String: String] ?? [:]
            var currentSources: [String: String] = [:]
            for (name, path) in sources { currentSources[name] = ArtifactProvenance.sha256(root: root, path: path) }
            diffs += ArtifactProvenance.compare("source_hashes", recordedSources, currentSources, short: true)

            let full = ArtifactProvenance.sha256(root: root, path: "\(directory)/sample-full.json")
            let store = ArtifactProvenance.sha256(root: root, path: dataset.store)
            diffs += ArtifactProvenance.compare(
                "sample-full.json vs \(dataset.store)", ["sha256": full], ["sha256": store], short: true)

            // Required: every generator writes it, and the registry names the
            // operators in the route key, so a solve without it is unattested.
            let registry = manifest["registry_hashes"] as? [String: String]
            let registryPath = "app/data/registry-bundle/\(dataset.country).json"
            diffs += ArtifactProvenance.compare(
                "registry_hashes", registry ?? [:],
                [dataset.country: ArtifactProvenance.sha256(root: root, path: registryPath)], short: true)
            let inputs = sources.values.sorted() + [dataset.store, registryPath]
            return Artifact(
                kind: .sample, path: directory, inputs: inputs, differences: diffs, command: dataset.command)
        }
    }

    // MARK: - port fixtures

    private enum Stamp {
        case unstamped
        case stamped(ArtifactProvenance)
        case malformed(String)
    }

    /// `serialize()` writes `provenance` right after `fixture`, so the block is
    /// in the first bytes; reading only a prefix avoids parsing megabytes.
    private static func stamp(of url: URL) -> Stamp {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .malformed("unreadable") }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 65_536)) ?? Data()
        let text = String(decoding: prefix, as: UTF8.self)
        guard let marker = text.range(of: "\n  \"provenance\": {") else { return .unstamped }
        var depth = 0
        var end: String.Index?
        var index = text.index(before: marker.upperBound)  // the opening brace
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { end = index; break }
            }
            index = text.index(after: index)
        }
        guard let end else { return .malformed("provenance block is not closed in the first 64 KB") }
        let block = text[text.index(before: marker.upperBound)...end]
        do {
            return .stamped(try JSONDecoder().decode(ArtifactProvenance.self, from: Data(block.utf8)))
        } catch {
            return .malformed("provenance does not decode: \(error)")
        }
    }

    private static func fixtureCommand(_ name: String) -> String {
        "node app/scripts/build/build-port-fixtures.mjs --only=\(name)"
    }

    private static func fixtures(_ root: URL) -> [Artifact] {
        let directory = root.appending(path: "port-fixtures")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.contains(" ") }
            .sorted()
        var out: [Artifact] = []
        for name in names {
            let path = "port-fixtures/\(name)"
            let command = fixtureCommand(name)
            switch stamp(of: directory.appending(path: name)) {
            case .malformed(let reason):
                out.append(Artifact(kind: .fixture, path: path, inputs: [], differences: [reason], command: command))
            case .unstamped:
                var diffs: [String] = []
                if !legacyUnstampedFixtures.contains(name) {
                    diffs.append("no provenance block (stamp it: export provenanceInputs from its module)")
                }
                out.append(Artifact(kind: .fixture, path: path, inputs: [], differences: diffs, command: command))
            case .stamped(let provenance):
                var diffs: [String] = []
                if legacyUnstampedFixtures.contains(name) {
                    diffs.append("remove \(name) from legacyUnstampedFixtures")
                }
                if !FileManager.default.fileExists(atPath: root.appending(path: provenance.generator).path) {
                    diffs.append("generator \(provenance.generator) does not exist")
                }
                if provenance.regenerate != command {
                    diffs.append("regenerate \(provenance.regenerate) → \(command)")
                }
                diffs += provenance.differences(root: root)
                out.append(
                    Artifact(
                        kind: .fixture, path: path, inputs: provenance.inputs.keys.sorted(),
                        differences: diffs, command: command))
            }
        }
        for name in legacyUnstampedFixtures.sorted() where !names.contains(name) {
            out.append(
                Artifact(
                    kind: .fixture, path: "port-fixtures/\(name)", inputs: [],
                    differences: ["remove \(name) from legacyUnstampedFixtures (file is gone)"], command: ""))
        }
        return out
    }

    // MARK: - Swift-generated expectations

    private static func expectations(_ root: URL) -> [Artifact] {
        var out: [Artifact] = []
        let directoryPath = DataCountExpectations.directory
        let directory = root.appending(path: directoryPath)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .sorted()
        for name in names {
            let path = "\(directoryPath)/\(name)"
            guard
                let file = try? JSONDecoder().decode(
                    DataCountExpectations.File.self, from: Data(contentsOf: root.appending(path: path)))
            else {
                out.append(Artifact(kind: .expectation, path: path, inputs: [], differences: ["does not decode"], command: ""))
                continue
            }
            var diffs: [String] = []
            if file.format != DataCountExpectations.format {
                diffs.append("format \(file.format) → \(DataCountExpectations.format)")
            }
            diffs += file.provenance.differences(root: root)
            out.append(
                Artifact(
                    kind: .expectation, path: path, inputs: file.provenance.inputs.keys.sorted(),
                    differences: diffs, command: file.provenance.regenerate))
        }
        for path in stampedGenerated {
            guard let object = jsonObject(root.appending(path: path)) else {
                out.append(
                    Artifact(
                        kind: .expectation, path: path, inputs: [],
                        differences: ["\(path) is missing or does not parse"], command: ""))
                continue
            }
            guard let raw = object["provenance"],
                let data = try? JSONSerialization.data(withJSONObject: raw),
                let provenance = try? JSONDecoder().decode(ArtifactProvenance.self, from: data)
            else {
                out.append(
                    Artifact(
                        kind: .expectation, path: path, inputs: [],
                        differences: ["\(path) has no decodable provenance"], command: ""))
                continue
            }
            out.append(
                Artifact(
                    kind: .expectation, path: path, inputs: provenance.inputs.keys.sorted(),
                    differences: provenance.differences(root: root), command: provenance.regenerate))
        }
        return out
    }

    // MARK: - tests

    @Test func jsAndSwiftSolverVersionsAgree() throws {
        let root = try PortFixtures.repositoryRoot()
        let js = ArtifactProvenance.jsRouteSolverCacheVersion(root: root)
        #expect(
            js == RouteGraph.routeSolverCacheVersion,
            """
            app/public/app-config.js ROUTE_SOLVER_CACHE_VERSION is \(js) but \
            RouteGraph.routeSolverCacheVersion is \(RouteGraph.routeSolverCacheVersion); \
            bump both together (routeDrawnCacheVersion is native-only).
            """)
    }

    @Test func bundledSampleDatasetsMatchTheirInputs() {
        Self.fail("Bundled sample datasets are stale", .sample)
    }

    @Test func portFixturesCarryCurrentProvenance() {
        Self.fail("Port fixtures are stale or unstamped", .fixture)
    }

    @Test func swiftGeneratedExpectationsCarryCurrentProvenance() {
        Self.fail("Swift-generated expectations are stale", .expectation)
    }
}
