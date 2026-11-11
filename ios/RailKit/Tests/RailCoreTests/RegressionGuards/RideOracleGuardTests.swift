import Foundation
import Testing
@_spi(Testing) @testable import RailCore

/// Frozen oracle of what the CURRENT trip-loading pipeline produces for the
/// bundled example trips (trip-loading plan, unit U0a). Later waves compare
/// their resolver against `Resources/ride-oracle.json` to prove which trips
/// would change; nothing here is wired into the app.
///
/// What is recorded, per distinct sample trip (287: later store wins a
/// duplicate id), per route section: the display line ids and the line km the
/// resolver attributes, the official interval codes when the part was drawn
/// from intervals, the solver-path and drawn length in km, the temporal kind,
/// the provenance, and the gap flag (`interior` = excluded from mileage,
/// `unproven` = plausibility-rejected track, `boundary` = missing connection
/// before an independently drawn leg). No coordinates are stored.
///
/// How it is produced: `UserPathCensusTests` already mirrors the app's whole
/// route path (registry upgrade, canonical input with timetable evidence,
/// inference pass then legacy pass, display network, shared graph store). This
/// oracle reuses those mirrors and keeps only the decision fields, so the run
/// skips the census's geometry measurements.
///
/// Two tiers:
/// - Always on, fast (fixture only): shape, counts, ordering, internal
///   consistency. Fails when the fixture is edited by hand or truncated.
/// - Opt-in, full (live pipeline, minutes): `RIDE_ORACLE_VERIFY=1` re-runs all
///   287 trips and requires the result to equal the fixture;
///   `RIDE_ORACLE_EXPORT=1` rewrites the fixture. The always-on tier also
///   re-solves the small non-Japan scopes (hk, mo, kr) live.
///
///     RIDE_ORACLE_EXPORT=1 swift test --package-path ios/RailKit -c release \
///       -Xswiftc -enable-testing --filter RegressionGuardRideOracle
///
/// The oracle is regenerated only when the current pipeline legitimately
/// changes before wave 3; after the switch it is history and must not move.
@Suite(.serialized)
struct RegressionGuardRideOracle {
    // MARK: - Fixture model

    struct Document: Codable, Equatable {
        var version: Int
        var note: String
        var counts: Counts
        var rides: [Ride]
    }

    struct Counts: Codable, Equatable {
        var rides: Int
        var sections: Int
        var drawnParts: Int
        var unsolvedSections: Int
        var gapSections: Int
        var skippedRides: Int
        var byStore: [String: Int]
    }

    struct Ride: Codable, Equatable {
        var id: String
        var store: String
        /// Scope key, e.g. `jp` or `jp+tw`.
        var scope: String
        /// `inference` or `legacy` (the pass that produced the result);
        /// `none` for rides the app never solves.
        var pass: String
        /// `RideRouteResolution.Result.Disposition`, or `skipped`.
        var disposition: String
        var timetableMatched: Bool
        var sections: [Section]
    }

    struct Section: Codable, Equatable {
        var index: Int
        var from: String?
        var to: String?
        /// `none`, `interior`, `unproven` or `boundary`.
        var gap: String
        var parts: [Part]
    }

    struct Part: Codable, Equatable {
        var part: Int
        var lineIDs: [String]
        /// Km per attributed line, same order as `lineIDs`.
        var lineKm: [Double]
        var intervalCodes: [String]
        /// Interval traversal directions, same order as `intervalCodes`.
        var intervalDirections: [Int]
        var sourceKm: Double
        var drawnKm: Double
        var temporalKind: String
        var provenance: String?
    }

    static let version = 1
    static let fixtureNote =
        "Frozen output of the pre-switch trip-loading pipeline for the bundled sample trips. "
        + "Regenerate only with RIDE_ORACLE_EXPORT=1 (see RideOracleGuardTests.swift)."

    static let fixturePath = "ios/RailKit/Tests/RailCoreTests/RegressionGuards/Resources/ride-oracle.json"
    static let expectedRides = 287
    static let expectedStores: [String: Int] = [
        "train-store": 201, "new-year-grand-loop": 39, "tokyo-limited-express-loop": 16,
        "train-store-tw": 28, "train-store-hk": 1, "train-store-mo": 1, "train-store-kr": 1,
    ]

    // MARK: - Fixture IO

    static func encode(_ document: Document) throws -> Data {
        // One ride per line keeps diffs readable and the file small.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var head = document
        head.rides = []
        var headText = String(decoding: try encoder.encode(head), as: UTF8.self)
        // Replace the empty rides array with one line per ride.
        let marker = "\"rides\":[]"
        guard let range = headText.range(of: marker) else { throw CocoaError(.coderInvalidValue) }
        let lines = try document.rides.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let body = "\"rides\":[\n" + lines.joined(separator: ",\n") + "\n]"
        headText.replaceSubrange(range, with: body)
        return Data((headText + "\n").utf8)
    }

    static func loadFixture() throws -> Document {
        let url = try PortFixtures.repositoryRoot().appending(path: fixturePath)
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
    }

    static func counts(of rides: [Ride]) -> Counts {
        var byStore: [String: Int] = [:]
        for ride in rides { byStore[ride.store, default: 0] += 1 }
        let sections = rides.flatMap(\.sections)
        return Counts(
            rides: rides.count,
            sections: sections.count,
            drawnParts: sections.reduce(0) { $0 + $1.parts.count },
            unsolvedSections: sections.filter { $0.parts.isEmpty }.count,
            gapSections: sections.filter { $0.gap != "none" }.count,
            skippedRides: rides.filter { $0.disposition == "skipped" }.count,
            byStore: byStore)
    }

    // MARK: - Live pipeline

    typealias Census = UserPathCensusTests

    /// Mirrors `UserPathCensusTests.userPathCensus` ride decoding.
    static func sampleRides(root: URL) throws -> [Census.Ride] {
        var rides: [Census.Ride] = []
        var position: [String: Int] = [:]
        for sample in Census.samples {
            let store = try JSONDecoder().decode(
                TrainStore.self, from: Data(contentsOf: root.appending(path: sample.path)))
            for train in store.trains {
                try TrainValidation.validateSupportedRegions(train)
                guard train.region?.isEmpty == false else {
                    throw CocoaError(.coderInvalidValue, userInfo: [
                        NSLocalizedDescriptionKey: "untagged sample ride \(train.id)"])
                }
                let ride = Census.Ride(store: sample.resource, train: train)
                if let index = position[train.id] { rides[index] = ride }
                else { position[train.id] = rides.count; rides.append(ride) }
            }
        }
        return rides
    }

    /// Resolves `rides` the way the app does, scope by scope, and returns the
    /// decision records in input order.
    static func resolve(rides: [Census.Ride], root: URL) throws -> [Ride] {
        let data = root.appending(path: "app/data")
        let regionsInUse = Set(rides.flatMap { Census.regionsTouched($0.train) })
        var bundles: [String: RegistryBundle] = [:]
        for region in regionsInUse {
            let url = data.appending(path: "registry-bundle/\(region).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bundle = try JSONDecoder().decode(RegistryBundle.self, from: Data(contentsOf: url))
            if bundle.region.lowercased() == region { bundles[region] = bundle }
        }
        let registry = Census.Registry(bundles: bundles, identities: bundles.mapValues(RegistryIdentity.init(bundle:)))
        let identities = registry.identities
        let junctionRegistry = try PhysicalRailJunctionRegistry(
            data: Data(contentsOf: data.appending(path: "physical-rail-junctions.json")))
        let timetableURL = data.appending(path: "train-service-history/derived/train-service-timetable.sqlite")
        guard FileManager.default.fileExists(atPath: timetableURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: timetableURL.path])
        }
        let timetable = Census.TimetableEvidence(url: timetableURL)

        var records: [String: Ride] = [:]
        try RegistryIdentityLookup.withTestPhase({ region in
            identities[region.lowercased()].map(RegistryPhase.ready) ?? .unavailable
        }) {
            for ride in rides where ride.train.requiresRouteConfirmation {
                records[ride.train.id] = Ride(
                    id: ride.train.id, store: ride.store, scope: "", pass: "none",
                    disposition: "skipped", timetableMatched: false, sections: [])
            }
            let solvable = rides.filter { !$0.train.requiresRouteConfirmation }
            let byScope = Dictionary(grouping: solvable) { Census.Scope(regions: Census.regionsTouched($0.train)) }
            for scope in Census.ordered(byScope.keys) {
                for record in try resolve(
                    scope: scope, rides: byScope[scope] ?? [], root: root,
                    junctions: junctionRegistry, registry: registry, timetable: timetable)
                {
                    records[record.id] = record
                }
            }
        }
        return try rides.map { ride in
            guard let record = records[ride.train.id] else { throw OracleError.noRecord(ride.train.id) }
            return record
        }
    }

    enum OracleError: Error, CustomStringConvertible {
        case noRecord(String)
        case mixedGapKinds(ride: String, section: Int, kinds: [String])
        var description: String {
            switch self {
            case .noRecord(let id): "ride \(id) got no record from the live pipeline"
            case .mixedGapKinds(let ride, let section, let kinds):
                "ride \(ride) section \(section) has several gap kinds \(kinds); the oracle stores one, extend the schema"
            }
        }
    }

    /// One scope: the app's two passes, then one record per ride. Mirrors
    /// `UserPathCensusTests.census`.
    static func resolve(
        scope: Census.Scope, rides: [Census.Ride], root: URL, junctions: PhysicalRailJunctionRegistry,
        registry: Census.Registry, timetable: Census.TimetableEvidence
    ) throws -> [Ride] {
        let data = try Census.load(scope: scope, root: root, junctions: junctions)
        let country = scope.home
        var canonical: [String: Census.CanonicalInput] = [:]
        for ride in rides {
            canonical[ride.train.id] = Census.canonicalRouteInput(
                ride.train, country: country, registry: registry, timetable: timetable)
        }
        func solve(_ ride: Census.Ride, allowLegacy: Bool) throws -> RideRouteResolution.Result {
            let input = canonical[ride.train.id]!
            var resolver = RideRouteResolution(
                inputs: data.inputs, country: country, network: data.prepared,
                officialIntervals: data.inputs.officialIntervals, graphStore: data.graphStore)
            return try resolver.resolve(.init(
                train: registry.upgradeIfReady(ride.train), canonicalTrain: input.train,
                databaseSections: input.databaseSections, databaseProvenance: input.databaseProvenance),
                allowLegacy: allowLegacy)
        }
        func emitsRide(_ result: RideRouteResolution.Result) -> Bool {
            switch result.disposition {
            case .geometry, .unavailable: true
            case .unsupported, .awaitingConfirmation, .noSections: false
            }
        }
        var outcomes: [String: (pass: String, result: RideRouteResolution.Result)] = [:]
        var missing: [Census.Ride] = []
        for ride in rides {
            let result = try solve(ride, allowLegacy: false)
            outcomes[ride.train.id] = ("inference", result)
            if !emitsRide(result) { missing.append(ride) }
        }
        for ride in missing {
            outcomes[ride.train.id] = ("legacy", try solve(ride, allowLegacy: true))
        }

        return try rides.map { ride in
            let (pass, result) = outcomes[ride.train.id]!
            let timetableMatched = canonical[ride.train.id]!.databaseProvenance != nil
            let disposition = String(describing: result.disposition)
            guard emitsRide(result) else {
                return Ride(id: ride.train.id, store: ride.store, scope: scope.key, pass: pass,
                            disposition: disposition, timetableMatched: timetableMatched, sections: [])
            }
            var sections: [Section] = []
            for (index, section) in result.expectedSections.enumerated() {
                var kinds: [String] = []
                let own = result.physicalGaps.filter { $0.segmentIndex == index }
                if own.contains(where: \.isBoundary) { kinds.append("boundary") }
                if own.contains(where: \.isUnproven) { kinds.append("unproven") }
                if own.contains(where: { !$0.isBoundary && !$0.isUnproven }) { kinds.append("interior") }
                // The fixture stores one gap label per section; refuse to hide a second kind.
                guard kinds.count <= 1 else {
                    throw OracleError.mixedGapKinds(ride: ride.train.id, section: index, kinds: kinds)
                }
                let gap = kinds.first ?? "none"
                let parts = result.segments
                    .filter { $0.segmentIndex == index }
                    .sorted { $0.partIndex < $1.partIndex }
                    .map { segment -> Part in
                        let route = segment.physicalRoute
                        return Part(
                            part: segment.partIndex,
                            lineIDs: route?.lines.map(\.lineID) ?? [],
                            lineKm: route?.lines.map { round3($0.km) } ?? [],
                            intervalCodes: route?.intervals.map(\.code) ?? [],
                            intervalDirections: route?.intervals.map(\.direction) ?? [],
                            sourceKm: round3(Census.length(segment.sourceCoordinates) / 1000),
                            drawnKm: round3(Census.length(segment.drawnCoordinates) / 1000),
                            temporalKind: segment.temporalKind.rawValue,
                            provenance: route?.provenance.rawValue)
                    }
                sections.append(Section(index: index, from: section.from, to: section.to, gap: gap, parts: parts))
            }
            return Ride(id: ride.train.id, store: ride.store, scope: scope.key, pass: pass,
                        disposition: disposition, timetableMatched: timetableMatched, sections: sections)
        }
    }

    static func round3(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }

    // MARK: - Fast guards (fixture only)

    @Test("The fixture loads and its counts match the bundled samples")
    func fixtureShapeAndCounts() throws {
        let document = try Self.loadFixture()
        #expect(document.version == Self.version)
        #expect(document.rides.count == Self.expectedRides)
        #expect(Set(document.rides.map(\.id)).count == Self.expectedRides, "ride ids must be distinct")
        #expect(document.counts == Self.counts(of: document.rides), "header counts disagree with the rides")
        #expect(document.counts.byStore == Self.expectedStores)
    }

    @Test("Every ride is accounted for and its sections are well formed")
    func fixtureInternalConsistency() throws {
        let document = try Self.loadFixture()
        for ride in document.rides {
            #expect(["inference", "legacy", "none"].contains(ride.pass), "\(ride.id): pass \(ride.pass)")
            if ride.disposition == "skipped" || ride.sections.isEmpty {
                #expect(ride.sections.allSatisfy { $0.parts.isEmpty }, "\(ride.id)")
                continue
            }
            #expect(ride.sections.map(\.index) == Array(ride.sections.indices), "\(ride.id): section order")
            for section in ride.sections {
                #expect(["none", "interior", "unproven", "boundary"].contains(section.gap),
                        "\(ride.id) #\(section.index): gap \(section.gap)")
                #expect(section.parts.map(\.part) == section.parts.map(\.part).sorted(), "\(ride.id) #\(section.index)")
                for part in section.parts {
                    #expect(part.lineIDs.count == part.lineKm.count, "\(ride.id) #\(section.index)")
                    #expect(part.intervalCodes.count == part.intervalDirections.count, "\(ride.id) #\(section.index)")
                    #expect(part.sourceKm >= 0 && part.drawnKm >= 0, "\(ride.id) #\(section.index)")
                    #expect(RouteGraph.TemporalKind(rawValue: part.temporalKind) != nil,
                            "\(ride.id) #\(section.index): temporal kind \(part.temporalKind)")
                }
            }
        }
        // The sample set is expected to exercise the interesting cases.
        let sections = document.rides.flatMap(\.sections)
        #expect(sections.contains { $0.parts.contains { !$0.intervalCodes.isEmpty } }, "no interval-coded part")
        #expect(sections.contains { $0.gap != "none" }, "no gap section")
    }

    @Test("The fixture is canonical: re-encoding it reproduces the file")
    func fixtureIsCanonical() throws {
        let url = try PortFixtures.repositoryRoot().appending(path: Self.fixturePath)
        let onDisk = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(Document.self, from: onDisk)
        #expect(try Self.encode(document) == onDisk,
                "not canonical: hand edit, or the toolchain's JSONEncoder formatting (Double or escapes) changed; regenerate with RIDE_ORACLE_EXPORT=1 only if the live checks still pass")
    }

    // MARK: - Live checks

    /// Small non-Japanese scopes, cheap enough for the default run: re-solved
    /// live and required to equal the fixture.
    @Test("hk, mo and kr samples still resolve exactly as frozen")
    func liveFastSubset() throws {
        let root = try PortFixtures.repositoryRoot()
        let fixture = try Self.loadFixture()
        let subsetStores: Set<String> = ["train-store-hk", "train-store-mo", "train-store-kr"]
        let rides = try Self.sampleRides(root: root).filter { subsetStores.contains($0.store) }
        #expect(rides.count == 3)
        let live = try Self.resolve(rides: rides, root: root)
        let frozen = Dictionary(uniqueKeysWithValues: fixture.rides.map { ($0.id, $0) })
        #expect(live.map(\.id) == rides.map(\.train.id), "every sample ride must produce a record")
        for ride in live { #expect(frozen[ride.id] == ride, "\(ride.id) differs from the oracle") }
    }

    @Test("Full run: all 287 trips resolve exactly as frozen",
          .enabled(if: ProcessInfo.processInfo.environment["RIDE_ORACLE_VERIFY"] == "1"))
    func liveFullRun() throws {
        let root = try PortFixtures.repositoryRoot()
        let fixture = try Self.loadFixture()
        let start = ContinuousClock.now
        let live = try Self.resolve(rides: try Self.sampleRides(root: root), root: root)
        print("ride oracle verify: \(live.count) rides in \(ContinuousClock.now - start)")
        #expect(live.map(\.id) == fixture.rides.map(\.id))
        let frozen = Dictionary(uniqueKeysWithValues: fixture.rides.map { ($0.id, $0) })
        var different: [String] = []
        for ride in live where frozen[ride.id] != ride { different.append(ride.id) }
        #expect(different.isEmpty, "\(different.count) trips differ from the oracle: \(different.prefix(10))")
    }

    @Test("Export: rewrite ride-oracle.json from the live pipeline",
          .enabled(if: ProcessInfo.processInfo.environment["RIDE_ORACLE_EXPORT"] == "1"))
    func export() throws {
        let root = try PortFixtures.repositoryRoot()
        let start = ContinuousClock.now
        let rides = try Self.resolve(rides: try Self.sampleRides(root: root), root: root)
        print("ride oracle export: \(rides.count) rides in \(ContinuousClock.now - start)")
        #expect(rides.count == Self.expectedRides)
        let document = Document(
            version: Self.version, note: Self.fixtureNote, counts: Self.counts(of: rides), rides: rides)
        let data = try Self.encode(document)
        try data.write(to: root.appending(path: Self.fixturePath))
        print("ride oracle export: \(data.count) bytes, \(document.counts)")
    }
}
