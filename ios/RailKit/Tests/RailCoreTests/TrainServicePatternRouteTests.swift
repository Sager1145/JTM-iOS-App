import Foundation
import Testing

@testable import RailCore

/// The same apply/normalization/section-generation and dated graph path used
/// by the editor and RiddenRouteStore. Connectivity alone does not certify a
/// historical timetable or its exact via lines; those remain separate results.
/// Serialized because RouteGraphStore mutates its regional graph cache.
@Suite(.serialized)
struct TrainServicePatternRouteTests {
    struct Environment {
        let graphStore: RouteGraph.RouteGraphStore
        let stations: Stations.Index
        let historyRevision: String
    }

    nonisolated(unsafe) static let environment: Environment = {
        let root = try! PortFixtures.repositoryRoot()
        var sections = try! RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")).features
        var stationFeatures = try! Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json")).features
        let overlay = try! RailHistoryOverlay.load(
            from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)
        let stationCollection = Stations.FeatureCollection(features: stationFeatures)
        let graphStore = RouteGraph.RouteGraphStore(sections: sections)
        graphStore.augment = { graph, bbox in
            // Match RiddenRouteStore: connectors only see stations in this
            // regional graph, avoiding unrelated nationwide platform searches.
            let features = stationCollection.features.filter { feature in
                guard let bbox else { return true }
                guard let pair = Stations.displayCoordinate(feature),
                      let coordinate = Coordinate(pair: pair) else { return false }
                return coordinate.lon >= bbox.minX && coordinate.lon <= bbox.maxX
                    && coordinate.lat >= bbox.minY && coordinate.lat <= bbox.maxY
            }
            RouteSolver.addStationTransferConnectorEdges(graph: graph, stations: features)
        }
        return Environment(
            graphStore: graphStore, stations: Stations.Index(stationCollection),
            historyRevision: overlay.revision)
    }()

    final class Report: @unchecked Sendable {
        static let shared = Report()
        /// Identifies this process's report. A previous file with another id
        /// is not evidence for this run.
        static let runId = UUID().uuidString
        private let lock = NSLock()
        private var ledger = TrainServicePatternAcceptance.Ledger()
        private var rollups: [String: [String: Any]] = [:]
        private var lastWriteError: String?

        static var outputURL: URL? {
            guard let path = ProcessInfo.processInfo.environment["TRAIN_PATTERN_ROUTE_REPORT"]
            else { return nil }
            return URL(fileURLWithPath: path)
        }

        /// Git blob IDs identify the actual working files, including local edits.
        /// The commit alone cannot identify a report generated in a dirty checkout.
        private static func git(_ arguments: [String]) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-c", "core.fsmonitor=false"] + arguments
            process.currentDirectoryURL = try? PortFixtures.repositoryRoot()
            let pipe = Pipe()
            process.standardOutput = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return "unavailable" }
                return String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch { return "unavailable" }
        }

        private static let metadata: [String: String] = [
            "schemaVersion": "3.2",
            "commitSHA": git(["rev-parse", "HEAD"]),
            "workingTreeStatus": git(["status", "--porcelain"]),
            "hashAlgorithm": "git-blob-object-id",
            "patternCatalogHash": git(["hash-object", "ios/RailKit/Sources/RailCore/Resources/train-service-patterns.json"]),
            "stationPackageHash": git(["hash-object", "app/data/stations.json"]),
            "editorStationPackageHash": git(["hash-object", "app/public/rail/jp-2025.json"]),
            "railSectionsHash": git(["hash-object", "app/data/rail-sections.json"]),
            "historyOverlayRevision": TrainServicePatternRouteTests.environment.historyRevision,
            "historyOverlayHash": git(["hash-object", "app/data/rail-history.json"]),
            "solverVersion": git(["hash-object", "ios/RailKit/Sources/RailCore/RouteSolver.swift"]),
            "graphVersion": git(["hash-object", "ios/RailKit/Sources/RailCore/RouteGraph.swift"]),
            "testVersion": git(["hash-object", "ios/RailKit/Tests/RailCoreTests/TrainServicePatternRouteTests.swift"]),
            "testDate": "per-pattern catalog validFrom when validity is complete; otherwise unverified",
            "asOfDate": "not used; deterministic catalog evidence",
        ]

        func record(patternId: String, rideDate: String, directions: [String: [String: Any]]) {
            lock.lock()
            defer { lock.unlock() }
            for (direction, result) in directions {
                let key = TrainServicePatternAcceptance.CaseKey(
                    patternId: patternId, rideDate: rideDate, direction: direction,
                    variant: TrainServicePatternAcceptance.variantDefault)
                ledger.record(storageKey: key.storageKey, result: result)
            }
            rollups[patternId] = TrainServicePatternAcceptance.patternRollup(directions)
            guard let url = Self.outputURL else { return }
            do {
                try TrainServicePatternAcceptance.write(document: makeDocument(), to: url)
                lastWriteError = nil
            } catch {
                lastWriteError = String(describing: error)
            }
        }

        func writeError() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return lastWriteError
        }

        /// `runComplete` is case completeness: both directions of every catalog
        /// pattern are present. It is not an all-dimensions pass.
        private func makeDocument() -> [String: Any] {
            let expected = TrainServicePatternAcceptance.expectedCaseKeys(
                TrainServicePatterns.patterns.map { pattern in
                    (
                        id: pattern.id,
                        rideDate: TrainServicePatternAcceptance.rideDateKey(
                            validityComplete: pattern.completeness.validity == .complete,
                            hasSource: pattern.source?.isEmpty == false,
                            validFrom: pattern.validFrom)
                    )
                })
            var document: [String: Any] = rollups
            document["_cases"] = TrainServicePatternAcceptance.caseObject(ledger.cases)
            var metadata: [String: Any] = Self.metadata
            metadata["runId"] = Self.runId
            metadata["expectedPatternCount"] = TrainServicePatterns.patterns.count
            metadata["completedPatternCount"] = rollups.count
            metadata["expectedCaseCount"] = expected.count
            metadata["completedCaseCount"] = ledger.cases.count
            metadata["runComplete"] = ledger.runComplete(expected: expected)
            document["_metadata"] = metadata
            return document
        }
    }

    static func context(_ train: Train) -> RouteSolver.TrainContext {
        .init(
            id: train.id, number: train.number, trainType: train.trainType ?? "",
            company: train.company ?? "", origin: train.origin,
            destination: train.destination,
            preferredLineNames: train.routePolicy?.preferredLineNames ?? [],
            preferredOperatorNames: train.routePolicy?.preferredOperatorNames ?? [],
            allowedInstitutionTypeCodes: train.routePolicy?.allowedInstitutionTypeCodes,
            institutionFilterMode: train.routePolicy?.institutionFilterMode ?? "soft",
            rideDate: Dates.normalizeDateString(train.date))
    }

    @Test func fixedCodeNeverExpandsToDistantPreferredInstitution() {
        func station(code: String, institution: String, lon: Double, lat: Double) -> Stations.Feature {
            Stations.Feature(properties: [
                "station_name": .string("高田"), "n02_station_code": .string(code),
                "institution_type_code": .string(institution),
                "display_point": .array([.number(lon), .number(lat)]),
            ])
        }
        let fixed = station(code: "001632", institution: "5", lon: 138.242, lat: 37.115)
        let distant = station(code: "007802", institution: "2", lon: 135.745, lat: 34.516)
        let nearby = station(code: "nearby-platform", institution: "2", lon: 138.243, lat: 37.115)
        let endpoint = Stations.Query.stop(Stations.Stop(name: "高田", n02StationCode: "001632"))
        let withoutNearby = Stations.Index([fixed, distant])
        #expect(RouteSolver.resolveRouteEndpointStationCandidates(
            endpoint, in: withoutNearby, allowedCodes: ["2"], sectionLineNames: []) == [0])
        let withNearby = Stations.Index([fixed, distant, nearby])
        let candidates = RouteSolver.resolveRouteEndpointStationCandidates(
            endpoint, in: withNearby, allowedCodes: ["2"], sectionLineNames: [])
        #expect(candidates.contains(0))
        #expect(candidates.contains(2))
        #expect(!candidates.contains(1))
    }

    @Test func fixedCodeRecognizesOnlyExplicitOrExactHistoricalStationIdentity() {
        func station(
            name: String, code: String, group: String, coordinates: [Stations.Value]
        ) -> Stations.Feature {
            Stations.Feature(
                properties: [
                    "station_name": .string(name), "n02_station_code": .string(code),
                    "n02_group_code": .string(group),
                ],
                geometry: .init(type: "LineString", coordinates: .array(coordinates)))
        }
        let shape: [Stations.Value] = [
            .array([.number(136.64858), .number(36.57927)]),
            .array([.number(136.64711), .number(36.57726)]),
        ]
        let index = Stations.Index([
            station(name: "金沢", code: "002093", group: "002093", coordinates: shape),
            station(name: "金沢", code: "002092", group: "002092", coordinates: shape),
            station(name: "尼崎", code: "006918", group: "006918", coordinates: shape),
            station(name: "尼崎", code: "006920", group: "006918", coordinates: [
                .array([.number(135.43066), .number(34.73204)]),
                .array([.number(135.43290), .number(34.73167)]),
            ]),
            station(name: "金沢", code: "distant", group: "distant", coordinates: [
                .array([.number(139.0), .number(36.0)]),
                .array([.number(139.1), .number(36.1)]),
            ]),
            station(name: "別駅", code: "other-name", group: "other", coordinates: shape),
        ])

        #expect(index.hasSameStationIdentity(referenceCode: "002093", actualIndex: 0))
        #expect(index.hasSameStationIdentity(referenceCode: "002093", actualIndex: 1))
        #expect(index.hasSameStationIdentity(referenceCode: "006918", actualIndex: 3))
        #expect(!index.hasSameStationIdentity(referenceCode: "002093", actualIndex: 4))
        #expect(!index.hasSameStationIdentity(referenceCode: "002093", actualIndex: 5))
        #expect(!index.hasSameStationIdentity(referenceCode: "missing", actualIndex: 0))
    }

    @Test func crossCompanyPatternsKeepFixedStationIdentity() throws {
        for id in ["shirayuki-niigata-joetsumyoko", "super-inaba-okayama-tottori"] {
            let pattern = try #require(TrainServicePatterns.patterns.first { $0.id == id })
            try everyLegSolves(pattern: pattern)
        }
    }

    /// はちおうじ ended on 2025-03-15. The Chūō line did not. Ending a service
    /// pattern must not be asserted by demanding the solver return no path.
    @Test func serviceEndLeavesTheRailwaySolvable() throws {
        let pattern = try #require(
            TrainServicePatterns.patterns.first { $0.id == "hachioji-tokyo-hachioji" })
        let end = try #require(pattern.validUntil)
        #expect(end == "2025-03-15")
        #expect(pattern.isValid(on: "2025-03-14"))
        #expect(pattern.applicability(on: end) == .notApplicable)
        #expect(!pattern.isValid(on: end))

        let applied = TrainServicePatterns.apply(
            pattern,
            to: Train(
                id: pattern.id, date: end, number: "",
                origin: "", destination: "", stops: []))
        let canonical = TrainValidation.normalizeExportTrain(applied, country: "jp")
        let sections = StoreOperations.rideRouteSections(for: canonical)
        #expect(sections.count == pattern.stopRefs.count - 1)
        let train = Self.context(canonical)
        var anchor: Coordinate?
        for (index, section) in sections.enumerated() {
            let solved = RouteSolver.solveSectionOnDemand(
                section, segmentIndex: index, train: train, country: "jp",
                graphStore: Self.environment.graphStore, stations: Self.environment.stations,
                continuityAnchor: anchor)
            let pair = [pattern.stopRefs[index].name, pattern.stopRefs[index + 1].name]
            if pattern.unsolvableLegs.contains(pair) { continue }
            let solvedSection = try #require(
                solved, "\(pair.joined(separator: "→")) still has a railway on \(end)")
            anchor = solvedSection.coordinates.last
        }
    }

    /// A retired branch is a property of the railway, not of a service pattern.
    /// The same production solver the pattern regression uses must take the
    /// branch on a historical date and refuse it on the retirement day.
    /// 常磐線 相馬→亘理's old-versus-new alignment is the sibling case in
    /// `RailHistoryPackageTests`.
    @Test func retiredBranchIsRefusedOnItsEndDayAndSolvedBefore() throws {
        let historical = try #require(
            Self.solveNamedSection("新夕張", "夕張", lineName: "石勝線", rideDate: "2018-06-01"))
        #expect(historical.physicalLength > 0)
        #expect(Self.solveNamedSection("新夕張", "夕張", lineName: "石勝線", rideDate: "2019-04-01") == nil)
    }

    private static func solveNamedSection(
        _ from: String, _ to: String, lineName: String, rideDate: String
    ) -> RouteSolver.SolvedSection? {
        let section = RouteSection(from: from, to: to, lineNames: [lineName])
        return RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0,
            train: .init(
                id: "pattern-suite-rail-history", number: "", trainType: "", company: "",
                origin: from, destination: to, preferredLineNames: [],
                preferredOperatorNames: [], allowedInstitutionTypeCodes: nil,
                institutionFilterMode: "soft", rideDate: rideDate),
            country: "jp", graphStore: environment.graphStore, stations: environment.stations,
            continuityAnchor: nil)
    }

    @Test(arguments: TrainServicePatterns.patterns)
    func everyLegSolves(pattern: TrainServicePatterns.Pattern) throws {
        let env = Self.environment
        // Use an explicitly documented boundary, never an invented historical year.
        // Partial/missing windows receive structural/reference coverage only;
        // an undated solve cannot establish historical acceptance.
        let testDate = pattern.completeness.validity == .complete
            && pattern.source?.isEmpty == false ? pattern.validFrom : nil
        if let testDate { #expect(pattern.isValid(on: testDate)) }
        if let until = pattern.validUntil {
            // Service cessation does not imply the underlying railway disappears.
            #expect(!pattern.isValid(on: until))
        }
        let rideDateKey = TrainServicePatternAcceptance.rideDateKey(
            validityComplete: pattern.completeness.validity == .complete,
            hasSource: pattern.source?.isEmpty == false,
            validFrom: pattern.validFrom)
        final class DirectionOutcome {
            var failed: [String] = []
            var unresolvedReferences: [String] = []
            var saveReopenFailures: [String] = []
            var structurePassed = true
            var unsolvableCount = 0
            var legCount = 0
            var attemptedLegs = 0
            var solvedLegs: [[String: Any]] = []
            let started = Date()
        }
        var outcomes: [String: DirectionOutcome] = [:]
        for reversed in [false, true] {
            let direction = reversed ? "reverse" : "forward"
            let outcome = DirectionOutcome()
            outcomes[direction] = outcome
            let refs = reversed ? Array(pattern.stopRefs.reversed()) : pattern.stopRefs
            let applied = TrainServicePatterns.apply(
                pattern, to: Train(id: pattern.id, date: testDate, number: "",
                                   origin: "", destination: "", stops: []), reversed: reversed)
            let canonical = TrainValidation.normalizeExportTrain(applied, country: "jp")
            let sections = StoreOperations.rideRouteSections(for: canonical)
            #expect(canonical.stops.map(\.n02StationCode) == refs.map { Optional($0.sourceCode) })
            #expect(canonical.stops.map(\.name) == refs.map(\.name))
            #expect(sections.count == max(refs.count - 1, 0))
            outcome.structurePassed = canonical.stops.map(\.n02StationCode) == refs.map { Optional($0.sourceCode) }
                && canonical.stops.map(\.name) == refs.map(\.name)
                && sections.count == max(refs.count - 1, 0)
            for ref in refs {
                let exact = env.stations.candidateIndices(
                    for: .stop(Stations.Stop(n02StationCode: ref.sourceCode)))
                if exact.isEmpty {
                    outcome.unresolvedReferences.append("\(direction): missing code \(ref.name) [\(ref.sourceCode)]")
                }
            }
            if let failure = Self.saveReopenFailure(of: applied, direction: direction) {
                outcome.saveReopenFailures.append(failure)
            }
            let train = Self.context(canonical)
            var anchor: Coordinate?
            for (index, section) in sections.enumerated() {
                outcome.legCount += 1
                #expect(section.fromN02StationCode == refs[index].sourceCode)
                #expect(section.toN02StationCode == refs[index + 1].sourceCode)
                let label = "\(refs[index].name)→\(refs[index + 1].name)"
                guard testDate != nil else { continue }
                outcome.attemptedLegs += 1
                let solved = RouteSolver.solveSectionOnDemand(
                    section, segmentIndex: index, train: train, country: "jp",
                    graphStore: env.graphStore, stations: env.stations, continuityAnchor: anchor)
                guard let solved, let last = solved.coordinates.last else {
                    let pair = reversed ? [refs[index + 1].name, refs[index].name]
                        : [refs[index].name, refs[index + 1].name]
                    if pattern.unsolvableLegs.contains(pair) { outcome.unsolvableCount += 1 }
                    else { outcome.failed.append("\(direction): \(label)") }
                    anchor = nil
                    continue
                }
                for (ref, actual) in [(refs[index], solved.fromStationIndex),
                                      (refs[index + 1], solved.toStationIndex)] {
                    // The stop keeps its fixed directory code. A dated solve
                    // may select another line/operator membership only when
                    // the station index proves the same physical identity.
                    // Same-name or nearby platforms still fail.
                    let actualCode = Stations.stationCode(env.stations.features[actual])
                    let sameStationIdentity = env.stations.hasSameStationIdentity(
                        referenceCode: ref.sourceCode, actualIndex: actual)
                    let valid = RouteSolver.filterStationCandidatesByRideDate(
                        [actual], in: env.stations, rideDate: testDate)
                    let nameMatches = Stations.normalizeStationName(
                        Stations.stationName(env.stations.features[actual]))
                        == Stations.normalizeStationName(ref.name)
                        || (testDate != nil && env.stations.isCertifiedHistoricalNameAlias(
                            actualIndex: actual, referenceName: ref.name,
                            referenceCode: ref.sourceCode))
                    if TrainServicePatternAcceptance.referenceIntegrity(
                        expectedCode: ref.sourceCode, actualCode: actualCode,
                        sameStationIdentity: sameStationIdentity) != "passed"
                        || valid.isEmpty || !nameMatches {
                        outcome.unresolvedReferences.append(
                            "\(direction): \(ref.name) [\(ref.sourceCode)]")
                    }
                }
                outcome.solvedLegs.append([
                    "direction": direction, "fromCode": refs[index].sourceCode,
                    "toCode": refs[index + 1].sourceCode, "attemptIndex": solved.attemptIndex,
                    "fromLine": Stations.stationLineName(env.stations.features[solved.fromStationIndex]),
                    "toLine": Stations.stationLineName(env.stations.features[solved.toStationIndex]),
                    "physicalLengthMeters": solved.physicalLength,
                ])
                anchor = last
            }
        }
        var payloads: [String: [String: Any]] = [:]
        for (direction, outcome) in outcomes {
            payloads[direction] = [
                "legs": outcome.legCount,
                "attemptedLegs": outcome.attemptedLegs,
                "failed": outcome.failed,
                "unsolvable": outcome.unsolvableCount,
                "seconds": Date().timeIntervalSince(outcome.started),
                "solvedLegs": outcome.solvedLegs,
                "testDate": testDate as Any? ?? NSNull(),
                "dateSource": pattern.source as Any? ?? NSNull(),
                "structuralIntegrity": outcome.structurePassed ? "passed" : "failed",
                "referenceIntegrity": outcome.unresolvedReferences.isEmpty ? "passed" : "failed",
                "unresolvedReferences": outcome.unresolvedReferences,
                "dateApplicability": testDate == nil ? "unverified" : "catalog-covered",
                "routeConnectivity": TrainServicePatternAcceptance.routeConnectivity(
                    hasRideDate: testDate != nil,
                    failedLegCount: outcome.failed.count,
                    unsolvableLegCount: outcome.unsolvableCount),
                "historicalCorrectness": TrainServicePatternAcceptance.historicalCorrectness(
                    independentEvidenceMatches: false),
                "viaCorrectness": TrainServicePatternAcceptance.viaUnverified,
                "saveReopenConsistency": outcome.saveReopenFailures.isEmpty ? "passed" : "failed",
                "saveReopenFailures": outcome.saveReopenFailures,
            ]
        }
        Report.shared.record(patternId: pattern.id, rideDate: rideDateKey, directions: payloads)
        let unresolvedReferences = outcomes.values.flatMap(\.unresolvedReferences)
        let saveReopenFailures = outcomes.values.flatMap(\.saveReopenFailures)
        let failed = outcomes.values.flatMap(\.failed)
        #expect(unresolvedReferences.isEmpty, "\(pattern.id) wrong station identity: \(unresolvedReferences)")
        #expect(saveReopenFailures.isEmpty, "\(pattern.id) save/reopen: \(saveReopenFailures)")
        #expect(failed.isEmpty, "\(pattern.id) (\(pattern.name)) failed legs: \(failed)")
        if Report.outputURL != nil {
            #expect(Report.shared.writeError() == nil, "report write failed")
        }
    }

    /// The applied record, plus a reader-entered time and one unridden leg,
    /// through Codable, canonical export, import, and a cold section rebuild.
    /// An absent ride date becomes `UNDATED` on import; that is the store
    /// contract, and the station identity must still match.
    private static func saveReopenFailure(of applied: Train, direction: String) -> String? {
        guard !applied.stops.isEmpty else { return "\(direction): no stops" }
        var recorded = applied
        recorded.stops[0].departure = "07:15"
        if recorded.stops.count > 1 {
            recorded.stops[1].rideSegment = false
        }
        let expected = identity(recorded)
        do {
            let saved = try JSONEncoder().encode(TrainStore(trains: [recorded]))
            let reopened = try JSONDecoder().decode(TrainStore.self, from: saved).trains.first
            guard let reopened, identity(reopened) == expected, reopened.date == recorded.date else {
                return "\(direction): Codable round-trip changed the record"
            }
            let workspace = StoreOperations.Workspace(
                store: TrainStore(trains: [reopened]), country: "jp")
            let exported = StoreOperations.exportTrainStore(workspace)
            let durableDate = Dates.normalizeTrainDate(
                Dates.Train(id: recorded.id, date: recorded.date))
            let disk = try JSONDecoder().decode(TrainStore.self, from: Data(exported.utf8)).trains.first
            guard let disk, identity(disk) == expected, disk.date == durableDate else {
                return "\(direction): canonical export changed the record"
            }
            let parsed = try TrainValidation.JSON.parse(exported)
            try TrainValidation.validateTrainStore(parsed)
            guard case .array(let rows)? = parsed["trains"], let row = rows.first else {
                return "\(direction): export had no train"
            }
            var importedWorkspace = StoreOperations.Workspace(country: "jp")
            _ = try StoreOperations.appendImportedTrain(row, in: &importedWorkspace)
            guard let imported = importedWorkspace.store.trains.first,
                  identity(imported) == expected else {
                return "\(direction): import changed stop identity"
            }
            guard imported.date == durableDate else {
                return "\(direction): import date \(imported.date ?? "nil") != \(durableDate)"
            }
            var cleared = imported
            cleared.routeSections = nil
            let rebuilt = StoreOperations.rideRouteSections(for: cleared)
            let original = StoreOperations.rideRouteSections(for: recorded)
            guard rebuilt.count == original.count else {
                return "\(direction): cold rebuild section count"
            }
            for (rebuiltSection, originalSection) in zip(rebuilt, original) {
                guard rebuiltSection.from == originalSection.from,
                      rebuiltSection.to == originalSection.to,
                      rebuiltSection.fromN02StationCode == originalSection.fromN02StationCode,
                      rebuiltSection.toN02StationCode == originalSection.toN02StationCode
                else { return "\(direction): cold rebuild dropped a station code" }
            }
            return nil
        } catch {
            return "\(direction): \(error)"
        }
    }

    private struct StopIdentity: Equatable {
        let name: String
        let code: String?
        let arrival: String?
        let departure: String?
        let stopType: String
        let ridden: Bool
    }

    private static func identity(_ train: Train) -> [StopIdentity] {
        train.stops.map {
            StopIdentity(
                name: $0.name, code: $0.n02StationCode, arrival: $0.arrival,
                departure: $0.departure, stopType: $0.stopType, ridden: $0.rideSegment)
        }
    }
}
