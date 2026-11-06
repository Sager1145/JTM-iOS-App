import Foundation
import Testing
import RailCore

struct RouteDigestIndexTests {
    private func train(id: String = "t1", date: String? = "2026-01-02", notes: String? = nil) -> Train {
        Train(
            id: id, date: date, number: "1", origin: "東京", destination: "大阪",
            routeSections: [RouteSection(from: "東京", to: "大阪", lineNames: ["東海道新幹線"])],
            stops: [], notes: notes)
    }

    private func inputs(
        timetable: String = "rail:r1|timetable:t1", build: String = "b1", registry: String = "jp:ready:1@0"
    ) -> RouteDigestIndex.Inputs {
        RouteDigestIndex.Inputs(
            country: "jp", resourceRevision: "jp:r1|timetable:t1",
            timetableEvidenceRevision: timetable, solverCacheVersion: "28",
            drawnCacheVersion: "33", resolutionSemantics: "physical-section-evidence-v5",
            historyRevision: "h1", registry: registry, build: build)
    }

    @Test("The same train under the same inputs keys identically")
    func stableKey() throws {
        let first = try #require(RouteDigestIndex.key(train: train(), inputs: inputs()))
        let second = try #require(RouteDigestIndex.key(train: train(), inputs: inputs()))
        #expect(first == second)
    }

    @Test("Any train edit or any input change is a different key")
    func invalidation() throws {
        let base = try #require(RouteDigestIndex.key(train: train(), inputs: inputs()))
        let changed = [
            RouteDigestIndex.key(train: train(date: "2026-01-03"), inputs: inputs()),
            RouteDigestIndex.key(train: train(notes: "x"), inputs: inputs()),
            RouteDigestIndex.key(train: train(id: "t2"), inputs: inputs()),
            RouteDigestIndex.key(train: train(), inputs: inputs(timetable: "rail:r1|timetable:t2")),
            RouteDigestIndex.key(train: train(), inputs: inputs(build: "b2")),
            RouteDigestIndex.key(train: train(), inputs: inputs(registry: "jp:unavailable:none")),
        ]
        for key in changed { #expect(key != nil && key != base) }
        var other = inputs()
        other.solverCacheVersion = "29"
        #expect(RouteDigestIndex.key(train: train(), inputs: other) != base)
        other = inputs()
        other.historyRevision = "h2"
        #expect(RouteDigestIndex.key(train: train(), inputs: other) != base)
    }

    @Test("Lookup returns exactly what was recorded and survives persistence")
    func roundTrip() throws {
        let sections = try #require(train().routeSections)
        #expect(RouteDigestIndex.roundTrips(sections))
        var index = RouteDigestIndex()
        let first = index.record("k", digest: "d1", expectedSections: sections)
        let again = index.record("k", digest: "d1", expectedSections: sections)
        #expect(first)
        #expect(!again)
        let data = try JSONEncoder().encode(index)
        var decoded = RouteDigestIndex.decoded(from: data)
        let found = decoded.lookup("k")
        let entry = try #require(found)
        #expect(entry.digest == "d1")
        #expect(entry.expectedSections == sections)
        let missing = decoded.lookup("missing")
        #expect(missing == nil)
    }

    @Test("Unreadable or foreign data decodes as an empty index")
    func damaged() {
        #expect(RouteDigestIndex.decoded(from: Data("{}".utf8)).entries.isEmpty)
        #expect(RouteDigestIndex.decoded(from: Data([0xff])).entries.isEmpty)
    }

    @Test("Trimming drops the least recently used entries")
    func trim() {
        var index = RouteDigestIndex()
        index.record("a", digest: "1", expectedSections: [])
        index.record("b", digest: "2", expectedSections: [])
        index.record("c", digest: "3", expectedSections: [])
        _ = index.lookup("a")
        index.trim(to: 2)
        #expect(Set(index.entries.keys) == ["a", "c"])
    }
}

struct RouteCacheSweepTests {
    private func entry(_ digest: String, _ age: TimeInterval) -> RouteCacheSweep.Entry {
        RouteCacheSweep.Entry(digest: digest, written: Date(timeIntervalSince1970: age))
    }

    @Test("Within budget nothing is removed")
    func withinBudget() {
        #expect(RouteCacheSweep.victims([entry("a", 1), entry("b", 2)], budget: 2, protected: []).isEmpty)
    }

    @Test("Oldest unprotected entries go first, current digests never")
    func protectsCurrent() {
        let entries = [entry("old-live", 1), entry("old", 2), entry("mid", 3), entry("new", 4)]
        let victims = RouteCacheSweep.victims(entries, budget: 2, protected: ["old-live"])
        #expect(victims.map(\.digest) == ["old", "mid"])
    }

    @Test("A live set over budget keeps every live entry")
    func liveOverBudget() {
        let entries = [entry("a", 1), entry("b", 2), entry("c", 3)]
        let victims = RouteCacheSweep.victims(entries, budget: 1, protected: ["a", "b", "c"])
        #expect(victims.isEmpty)
        let partial = RouteCacheSweep.victims(entries + [entry("d", 0)], budget: 1, protected: ["a", "b", "c"])
        #expect(partial.map(\.digest) == ["d"])
    }
}
