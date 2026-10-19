import Foundation
import Testing
@testable import RailCore

struct RailResourceRevisionsTests {
    @Test func bundledAttestationRejectsInvalidDataAndSharesSuccessfulSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "resource-revisions-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "rail-resource-revisions.json")
        let invalid = RailResourceRevisions(schemaVersion: 2, regions: ["jp": "first"], timetableRevision: "tt")
        try JSONEncoder().encode(invalid).write(to: url)
        let bundle = try #require(Bundle(url: directory))
        #expect(throws: RailResourceRevisions.ResourceError.self) {
            try RailResourceRevisions.bundled(bundle: bundle)
        }
        let valid = RailResourceRevisions(regions: ["jp": "first"], timetableRevision: "tt")
        try JSONEncoder().encode(valid).write(to: url)
        #expect(try RailResourceRevisions.bundled(bundle: bundle) == valid)
        try Data("broken after snapshot load".utf8).write(to: url)
        #expect(try RailResourceRevisions.bundled(bundle: bundle) == valid)
        #expect(throws: RailResourceRevisions.ResourceError.missingRegion("tw")) {
            try valid.requiredRevision(for: "tw")
        }
    }

    @Test func missingAttestationIsAnExplicitFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "resource-revisions-missing-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try #require(Bundle(url: directory))
        #expect(throws: RailResourceRevisions.ResourceError.missingResource) {
            try RailResourceRevisions.bundled(bundle: bundle)
        }
    }

    @Test func everyCountryAndCombinedScopeUseContentRevisions() {
        let codes = ["jp", "tw", "hk", "mo", "kr"]
        let snapshot = RailResourceRevisions(regions: Dictionary(uniqueKeysWithValues:
            codes.map { ($0, "revision-\($0)") }), timetableRevision: "timetable")
        for code in codes { #expect(snapshot.revision(for: code) == "\(code):revision-\(code)") }
        #expect(snapshot.revision(for: "hk+mo") == snapshot.revision(for: "mo+hk"))
        let changed = RailResourceRevisions(regions: ["hk": "revision-hk", "mo": "changed"],
                                            timetableRevision: "timetable")
        #expect(changed.revision(for: "hk") == snapshot.revision(for: "hk"))
        #expect(changed.revision(for: "hk+mo") != snapshot.revision(for: "hk+mo"))
        #expect(snapshot.revision(for: "unknown") == nil)
        #expect(snapshot.revision(for: "hk+unknown") == nil)
        #expect(RailResourceRevisions(schemaVersion: 2, regions: snapshot.regions,
                                      timetableRevision: "timetable").revision(for: "jp") == nil)
    }

    @Test func staleOrUnattestedPrecomputesCannotSeedFreshCache() {
        for country in ["jp", "tw", "hk", "mo", "kr"] {
            let suffix = country == "jp" ? "" : "-\(country)"
            let names = ["\(country)-2025.json", "rail-sections\(suffix).json", "stations\(suffix).json",
                         "matched-routes.json", "matched-stops.json", "rail-history\(suffix).json"]
            let hashes = Dictionary(uniqueKeysWithValues: names.map { ($0, "hash-\($0)") })
            let snapshot = RailResourceRevisions(regions: [country: "revision"],
                                                timetableRevision: "timetable", sourceHashes: hashes)
            #expect(snapshot.acceptsPrecomputed(sourceHashes: hashes, country: country))
            #expect(!snapshot.acceptsPrecomputed(sourceHashes: nil, country: country))
            #expect(snapshot.acceptsPrecomputed(
                manifestSourceHashes: hashes, partSourceHashes: hashes, country: country))
            #expect(!snapshot.acceptsPrecomputed(
                manifestSourceHashes: hashes, partSourceHashes: nil, country: country))
            for filename in names {
                var stale = hashes
                stale[filename] = "old"
                #expect(!snapshot.acceptsPrecomputed(sourceHashes: stale, country: country))
                #expect(!snapshot.acceptsPrecomputed(
                    manifestSourceHashes: hashes, partSourceHashes: stale, country: country))
                #expect(!snapshot.acceptsPrecomputed(
                    manifestSourceHashes: stale, partSourceHashes: hashes, country: country))
                stale[filename] = nil
                #expect(!snapshot.acceptsPrecomputed(sourceHashes: stale, country: country))
            }
        }
    }

    @Test func packageVersionUpdateRetiresOldPrecomputedGeometry() {
        let names = ["jp-2025.json", "rail-sections.json", "stations.json",
                     "matched-routes.json", "matched-stops.json"]
        let oldHashes = Dictionary(uniqueKeysWithValues: names.map { ($0, "old-\($0)") })
        var newHashes = oldHashes
        newHashes["jp-2025.json"] = "new-map-version"
        let snapshot = RailResourceRevisions(regions: ["jp": "new-revision"],
                                            timetableRevision: "timetable", sourceHashes: newHashes)
        #expect(!snapshot.acceptsPrecomputed(
            manifestSourceHashes: oldHashes, partSourceHashes: oldHashes, country: "jp"))
        #expect(!snapshot.acceptsPrecomputed(
            manifestSourceHashes: newHashes, partSourceHashes: oldHashes, country: "jp"))
        #expect(snapshot.acceptsPrecomputed(
            manifestSourceHashes: newHashes, partSourceHashes: newHashes, country: "jp"))
    }
}
