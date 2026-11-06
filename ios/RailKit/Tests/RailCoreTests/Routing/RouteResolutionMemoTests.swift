import Foundation
import Testing
@testable import RailCore

struct RouteResolutionMemoTests {
    private let a = Coordinate(lon: 139, lat: 35)
    private let b = Coordinate(lon: 139.01, lat: 35)

    private func solved(index: Int = 0) -> RouteSolver.SolvedSection {
        .init(segmentIndex: index, fromStationIndex: 0, toStationIndex: 1,
            coordinates: [a, b], rawPathKeys: ["qualified:operator:line:a", "qualified:operator:line:b"],
            hints: .init(requiredLines: ["Line"], requiredOperators: ["Operator"]),
            allowedInstitutionTypeCodes: ["2"], usedInstitutionTypeCodes: ["2"],
            snapFrom: 0, snapTo: 0, physicalLength: 900, rawPhysicalLength: 900,
            cost: 900, attemptIndex: 0, historyIDs: ["history:1"],
            validFrom: "2020-01-01", validTo: "2030-01-01", temporalKind: .current)
    }

    private func stations() -> Stations.Index {
        let features = zip([a, b], [("A", "大分"), ("B", "小倉")]).map { point, identity in
            Stations.Feature(properties: ["n02_station_code": .string(identity.0),
                "station_name": .string(identity.1), "line_name": .string("日豊線"),
                "operator": .string("九州旅客鉄道"), "institution_type_code": .string("2")],
                geometry: .init(type: "Point", coordinates: .array([
                    .number(point.lon), .number(point.lat)])))
        }
        return .init(features)
    }

    @Test("Repeated sections share complete results while each caller keeps its segment index")
    func repeatedSectionRemapsPresentationIndex() throws {
        let memo = RouteResolutionMemo()
        let original = solved(index: 40)
        let section = RouteSection(from: "東京", to: "品川", lineNames: ["Line"])
        var builds = 0
        let first = try #require(memo.solve(section: section, segmentIndex: 3,
            context: .init(id: "train-one"), country: "jp", stations: stations()) {
                builds += 1
                return original
            })
        let repeated = try #require(memo.solve(section: section, segmentIndex: 8,
            context: .init(id: "train-two", number: "2号"), country: "jp", stations: stations()) {
                builds += 1
                return nil
            })
        var expected = original
        expected.segmentIndex = 3
        #expect(first == expected)
        expected.segmentIndex = 8
        #expect(repeated == expected)
        #expect(builds == 1)
        #expect(memo.retainedEntryCount == 1)
    }

    @Test("Service inference uses every train hint field and fills code-only endpoint names")
    func derivedServiceConstraints() throws {
        let memo = RouteResolutionMemo()
        let section = RouteSection(fromN02StationCode: "A", toN02StationCode: "B")
        let value = solved()
        let index = stations()
        var builds = 0
        func request(_ context: RouteSolver.TrainContext) throws {
            _ = try memo.solve(section: section, segmentIndex: 0, context: context,
                country: "jp", stations: index) { builds += 1; return value }
        }
        try request(.init(id: "plain-one"))
        try request(.init(id: "plain-two", number: "2号"))
        #expect(builds == 1)
        // Only the derived constraints matter: these identities all infer the
        // same 日豊線/九州旅客鉄道 requirement after station names are restored.
        for context in [RouteSolver.TrainContext(id: "sonic-one"),
            .init(number: "ソニック1号"), .init(trainType: "sonic"),
            .init(origin: "sonic"), .init(destination: "sonic")] {
            try request(context)
        }
        #expect(builds == 2)
        try request(.init(id: "haruka-one"))
        try request(.init(number: "はるか2号"))
        #expect(builds == 3)
        // A company also derives a preferred operator; it cannot share with
        // an otherwise identical Sonic identity that has no company preference.
        try request(.init(company: "sonic"))
        #expect(builds == 4)
    }

    @Test("Date spelling, continuity, country and every original section field remain constraints")
    func requestDifferencesMiss() throws {
        let memo = RouteResolutionMemo()
        let value = solved()
        let index = stations()
        let base = RouteSection(from: "東京", to: "品川", fromN02StationCode: "A",
            toN02StationCode: "B", lineNames: ["Line"], operatorNames: ["Operator"],
            lineIDs: ["line:1"], sectionCodes: ["section:1"])
        var builds = 0
        func request(_ section: RouteSection = .init(from: "東京", to: "品川",
            fromN02StationCode: "A", toN02StationCode: "B", lineNames: ["Line"],
            operatorNames: ["Operator"], lineIDs: ["line:1"], sectionCodes: ["section:1"]),
            date: String? = nil, anchor: Coordinate? = nil, key: String? = nil,
            country: String = "jp") throws {
            _ = try memo.solve(section: section, segmentIndex: 0, context: .init(rideDate: date),
                country: country, stations: index, continuityAnchor: anchor,
                physicalContinuationKey: key) { builds += 1; return value }
        }
        try request(base)
        try request(base, date: "2020-01-01")
        try request(base, date: "2020-01-02")
        // Both invalid spellings normalize to `none` in solveContext; exact
        // strings still separate the raw date inputs the solver reads.
        try request(base, date: "2020/01/01")
        try request(base, date: "2020/01/02")
        try request(base, anchor: a)
        try request(base, anchor: b)
        try request(base, key: "qualified:first")
        try request(base, key: "qualified:second")
        try request(base, country: "tw")
        #expect(builds == 10)
        for mutate in [
            { (s: inout RouteSection) in s.from = "別府" },
            { (s: inout RouteSection) in s.to = "中津" },
            { (s: inout RouteSection) in s.fromN02StationCode = "C" },
            { (s: inout RouteSection) in s.toN02StationCode = "D" },
            { (s: inout RouteSection) in s.lineNames = ["Other line"] },
            { (s: inout RouteSection) in s.operatorNames = ["Other operator"] },
            { (s: inout RouteSection) in s.lineIDs = ["line:2"] },
            { (s: inout RouteSection) in s.sectionCodes = ["section:2"] },
            { (s: inout RouteSection) in s.number = "3号" },
            { (s: inout RouteSection) in s.name = "Branch" }
        ] {
            var section = base
            mutate(&section)
            try request(section)
        }
        #expect(builds == 20)
    }

    @Test("Explicit allowed codes do not erase hard train-type exclusions from the memo key")
    func hardExclusionDifferenceMisses() throws {
        let memo = RouteResolutionMemo()
        let value = solved()
        let section = RouteSection(from: "東京", to: "品川")
        var builds = 0
        for type in ["JR", "SHINKANSEN"] {
            _ = try memo.solve(section: section, segmentIndex: 0,
                context: .init(trainType: type, company: "JR", allowedInstitutionTypeCodes: ["1", "2"]),
                country: "jp", stations: stations()) { builds += 1; return value }
        }
        #expect(builds == 2)
    }

    @Test("Completed source proofs require identical multipart geometry, filters and graph provenance")
    func completeProofRequestIdentity() throws {
        let memo = RouteResolutionMemo()
        let snapshotID = UUID()
        let provenance = RouteGraph.SourceProofProvenance(snapshotID: snapshotID, featureIndices: [0, 1])
        let qualified = ["qualified:operator:line:a", "qualified:operator:line:b"]
        var builds = 0
        func request(lines: [[Coordinate]], date: String? = nil,
            section: RouteSection = .init(lineNames: ["Line"], operatorNames: ["Operator"]),
            names: [String] = [], anchors: [Set<Int>] = [],
            provenance: RouteGraph.SourceProofProvenance?) throws -> [String]? {
            try memo.proof(lines: lines, context: .init(rideDate: date), section: section,
                graphProvenance: provenance, displayRowNames: names, anchorIndices: anchors) {
                    builds += 1
                    return qualified
                }
        }
        #expect(try request(lines: [[a, b]], provenance: provenance) == qualified)
        #expect(try request(lines: [[a, b]], provenance: provenance) == qualified)
        #expect(builds == 1)
        _ = try request(lines: [[a], [b]], provenance: provenance)
        _ = try request(lines: [[b, a]], provenance: provenance)
        _ = try request(lines: [[a, b]], date: "2020-01-01", provenance: provenance)
        _ = try request(lines: [[a, b]], section: .init(lineNames: ["Other"],
            operatorNames: ["Operator"]), provenance: provenance)
        _ = try request(lines: [[a, b]], section: .init(lineNames: ["Line"],
            operatorNames: ["Other"]), provenance: provenance)
        _ = try request(lines: [[a, b]], names: ["Display row"], provenance: provenance)
        _ = try request(lines: [[a, b]], anchors: [[1]], provenance: provenance)
        _ = try request(lines: [[a, b]], provenance: .init(snapshotID: snapshotID, featureIndices: [1, 0]))
        _ = try request(lines: [[a, b]], provenance: .init(snapshotID: UUID(), featureIndices: [0, 1]))
        #expect(builds == 10)
        _ = try request(lines: [[a, b]], provenance: nil)
        _ = try request(lines: [[a, b]], provenance: nil)
        #expect(builds == 12)
        #expect(memo.retainedEntryCount == 10)
    }

    @Test("Nil and throwing operations retry; a later successful solve and proof can be reused")
    func failuresAreNotRetained() throws {
        enum Failure: Error { case expected }
        let memo = RouteResolutionMemo()
        let section = RouteSection(from: "東京", to: "品川")
        let index = stations()
        let value = solved()
        var builds = 0
        func request(_ operation: () throws -> RouteSolver.SolvedSection?) throws -> RouteSolver.SolvedSection? {
            try memo.solve(section: section, segmentIndex: 0, context: .init(), country: "jp",
                stations: index) { builds += 1; return try operation() }
        }
        #expect(try request { nil } == nil)
        do { _ = try request { throw Failure.expected }; Issue.record("Expected failed solve") }
        catch Failure.expected { }
        #expect(memo.retainedEntryCount == 0)
        #expect(try request { value } == value)
        #expect(try request { nil } == value)
        #expect(builds == 3)
        let provenance = RouteGraph.SourceProofProvenance(snapshotID: UUID(), featureIndices: [0])
        let lines = [[a, b]]
        var proofBuilds = 0
        for succeeds in [false, true, false] {
            let result = try memo.proof(lines: lines, context: .init(), section: section,
                graphProvenance: provenance) {
                    proofBuilds += 1
                    return succeeds ? value.rawPathKeys : nil
                }
            #expect(result == (proofBuilds == 1 ? nil : value.rawPathKeys))
        }
        #expect(proofBuilds == 2)
    }

    @Test("Entry and cost bounds evict least-recent successes and decline oversized values")
    func boundedRetention() throws {
        let memo = RouteResolutionMemo(maxEntries: 2, maxRetainedCost: 20_000)
        let value = solved()
        let index = stations()
        var builds = 0
        func request(_ name: String) throws {
            _ = try memo.solve(section: .init(from: name, to: "Destination"), segmentIndex: 0,
                context: .init(), country: "jp", stations: index) { builds += 1; return value }
        }
        try request("one")
        try request("two")
        try request("one") // refresh one; two is now oldest
        try request("three")
        try request("one")
        #expect(builds == 3)
        try request("two")
        #expect(builds == 4)
        #expect(memo.retainedEntryCount == 2)
        #expect(memo.retainedCost <= 20_000)
        let oversized = RouteResolutionMemo(maxEntries: 10, maxRetainedCost: 64)
        for _ in 0..<2 {
            #expect(try oversized.solve(section: .init(from: "one", to: "two"), segmentIndex: 0,
                context: .init(), country: "jp", stations: index) { value } == value)
        }
        #expect(oversized.retainedEntryCount == 0)
        #expect(oversized.retainedCost == 0)
        // A cost bound also evicts even when the entry limit has spare room.
        let probe = RouteResolutionMemo()
        _ = try probe.solve(section: .init(from: "one", to: "end"), segmentIndex: 0,
            context: .init(), country: "jp", stations: index) { value }
        let oneEntryCost = probe.retainedCost
        let costBounded = RouteResolutionMemo(maxEntries: 10, maxRetainedCost: oneEntryCost)
        var boundedBuilds = 0
        for name in ["one", "two", "one"] {
            _ = try costBounded.solve(section: .init(from: name, to: "end"), segmentIndex: 0,
                context: .init(), country: "jp", stations: index) { boundedBuilds += 1; return value }
        }
        #expect(boundedBuilds == 3)
        #expect(costBounded.retainedEntryCount == 1)
        #expect(costBounded.retainedCost <= oneEntryCost)
        // Both kinds of graph-free value spend the same owner's budget.
        let shared = RouteResolutionMemo(maxEntries: 1)
        _ = try shared.solve(section: .init(from: "one", to: "end"), segmentIndex: 0,
            context: .init(), country: "jp", stations: index) { value }
        _ = try shared.proof(lines: [[a, b]], context: .init(), section: .init(),
            graphProvenance: .init(snapshotID: UUID(), featureIndices: [0])) { value.rawPathKeys }
        var solveWasEvicted = false
        _ = try shared.solve(section: .init(from: "one", to: "end"), segmentIndex: 0,
            context: .init(), country: "jp", stations: index) { solveWasEvicted = true; return value }
        #expect(solveWasEvicted)
    }

    @Test("Cancellation bypasses hits and discards completed operations before retention")
    func cancellationDoesNotCache() async throws {
        let memo = RouteResolutionMemo()
        let value = solved()
        let index = stations()
        let section = RouteSection(from: "東京", to: "品川")
        _ = try memo.solve(section: section, segmentIndex: 0, context: .init(),
            country: "jp", stations: index) { value }
        let hitWasCancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try memo.solve(section: section, segmentIndex: 0, context: .init(),
                    country: "jp", stations: index) { Issue.record("Cancelled hit must not build"); return value }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(hitWasCancelled)
        let empty = RouteResolutionMemo()
        let buildWasCancelled = await Task {
            do {
                _ = try empty.solve(section: section, segmentIndex: 0, context: .init(),
                    country: "jp", stations: index) {
                        withUnsafeCurrentTask { $0?.cancel() }
                        return value
                    }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(buildWasCancelled)
        #expect(empty.retainedEntryCount == 0)
        #expect(try empty.solve(section: section, segmentIndex: 0, context: .init(),
            country: "jp", stations: index) { value } == value)
        #expect(empty.retainedEntryCount == 1)
        let proofMemo = RouteResolutionMemo()
        let provenance = RouteGraph.SourceProofProvenance(snapshotID: UUID(), featureIndices: [0])
        let lines = [[a, b]]
        let proofWasCancelled = await Task {
            do {
                _ = try proofMemo.proof(lines: lines, context: .init(), section: section,
                    graphProvenance: provenance) {
                        withUnsafeCurrentTask { $0?.cancel() }
                        return value.rawPathKeys
                    }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(proofWasCancelled)
        #expect(proofMemo.retainedEntryCount == 0)
        #expect(try proofMemo.proof(lines: lines, context: .init(), section: section,
            graphProvenance: provenance) { value.rawPathKeys } == value.rawPathKeys)
        let proofHitWasCancelled = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try proofMemo.proof(lines: lines, context: .init(), section: section,
                    graphProvenance: provenance) {
                        Issue.record("Cancelled proof hit must not build")
                        return value.rawPathKeys
                    }
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(proofHitWasCancelled)
    }
}
