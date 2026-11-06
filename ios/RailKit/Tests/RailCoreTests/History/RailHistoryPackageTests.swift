import Foundation
import Testing

@_spi(Testing) @testable import RailCore

/// End-to-end coverage for ADR 0011's rail-history overlay
/// (`app/data/rail-history.json`) against the real Japanese solver package:
/// a retired line only routes a ride dated inside its validity window, and
/// an undated ride never uses retired track.
///
/// Follows `SonicRouteConstraintTests`'s data-loading and solve pattern, but
/// goes through `RouteGraph.RouteGraphStore` + `RouteSolver.solveSectionOnDemand`
/// (per `RiddenRouteStore.solveMissing`) because that is the path that
/// actually exercises the dated rail-history edges end to end.
/// `.serialized`: every case shares one `RouteGraph.RouteGraphStore`, whose
/// regional-graph cache is mutated in place by `solveSectionOnDemand` — the
/// default parallel execution corrupts that shared cache across threads
/// (observed as a segfault in the test process, not an assertion failure).
@Suite(.serialized)
struct RailHistoryPackageTests {
    struct Environment {
        let graphStore: RouteGraph.RouteGraphStore
        let stations: Stations.Index
        let overlay: RailHistoryOverlay
    }

    nonisolated(unsafe) static let environment: Environment = {
        let root = try! PortFixtures.repositoryRoot()
        var sections = try! RouteGraph.SectionFeatureCollection.load(
            contentsOf: root.appending(path: "app/data/rail-sections.json")
        ).features
        var stationFeatures = try! Stations.FeatureCollection.load(
            contentsOf: root.appending(path: "app/data/stations.json")
        ).features
        let overlay = try! RailHistoryOverlay.load(
            from: root.appending(path: "app/data/rail-history.json"))
        _ = RailHistory.apply(overlay, sections: &sections, stations: &stationFeatures)

        let stationCollection = Stations.FeatureCollection(features: stationFeatures)
        let stations = Stations.Index(stationCollection)
        let registry = try! PhysicalRailJunctionRegistry(data: Data(contentsOf:
            root.appending(path: "app/data/physical-rail-junctions.json")))
        // Match the production physical graph: reviewed junctions, no passenger
        // transfer augmentation. Legacy browser audits retain their own graph.
        let graphStore = RouteGraph.RouteGraphStore(
            sections: sections, policy: .physicalRailway,
            junctions: registry.junctions(for: "jp"),
            cachePolicy: .bounded(maximumNodes: 100_000),
            identityPeriods: overlay.identityPeriods)
        return Environment(graphStore: graphStore, stations: stations, overlay: overlay)
    }()

    struct SurveyedHop: Hashable { let from: String; let to: String }
    static func assertNativeSurveyedPath(
        _ solved: RouteSolver.SolvedSection, section: RouteSection, rideDate: String, id: String
    ) {
        #expect(solved.coordinates.count == solved.rawPathKeys.count)
        #expect(abs(solved.physicalLength - solved.rawPhysicalLength) < 0.000001)
        #expect(abs(solved.physicalLength - RouteSolver.pathLength(for: solved.coordinates)) < 0.000001)
        let wanted = Set(zip(solved.rawPathKeys, solved.rawPathKeys.dropFirst()).map {
            SurveyedHop(from: $0.0, to: $0.1)
        })
        var matched = Set<SurveyedHop>()
        let lines = Set(section.lineNames ?? [])
        for source in Self.environment.graphStore.sections where lines.contains(source.properties.lineName) {
            guard RouteGraph.RailValidity.isValid(validFrom: source.properties.validFrom,
                validTo: source.properties.validTo, on: rideDate) else { continue }
            for line in source.quantisedLines {
                for (a, b) in zip(line, line.dropFirst()) {
                    let from = RouteGraph.physicalNodeKey(a, identity: source.physicalTrackIdentity)
                    let to = RouteGraph.physicalNodeKey(b, identity: source.physicalTrackIdentity)
                    for hop in [SurveyedHop(from: from, to: to), SurveyedHop(from: to, to: from)]
                    where wanted.contains(hop) { matched.insert(hop) }
                }
            }
        }
        // A reviewed registry junction (app/data/physical-rail-junctions.json)
        // is a legitimate physical join between two surveyed identities: a
        // zero-length hop at an identical vertex or a short reviewed link. It
        // is not section geometry, so read it back from the production graph
        // and accept it only when that edge is a non-connector physical
        // junction valid on the ride date.
        let unmatched = wanted.subtracting(matched)
        if !unmatched.isEmpty, let box = Self.pathBBox(solved.coordinates) {
            let env = Self.environment
            defer { env.graphStore.invalidate() }
            let graph = env.graphStore.regionalGraph(
                for: RouteGraph.padBBoxMeters(box, meters: 2_000), routeSolveInProgress: true)
            for hop in unmatched where (graph.adjacency[hop.from] ?? []).contains(where: { edge in
                edge.to == hop.to && edge.connector == nil && edge.physicalJunction != nil
                    && RouteGraph.RailValidity.isValid(
                        validFrom: edge.validFrom, validTo: edge.validTo, on: rideDate)
            }) { matched.insert(hop) }
        }
        #expect(!wanted.isEmpty && matched == wanted,
                "\(id): every native hop must be adjacent surveyed source geometry valid on the ride date")
        for (key, coordinate) in zip(solved.rawPathKeys, solved.coordinates) {
            #expect(key.hasSuffix("@" + Grid.coordKey(coordinate)),
                    "\(id): native coordinates must remain raw physical graph vertices")
        }
    }

    static func pathBBox(_ coordinates: [Coordinate]) -> RouteGraph.BBox? {
        guard let first = coordinates.first else { return nil }
        return coordinates.dropFirst().reduce(RouteGraph.BBox(
            minX: first.lon, minY: first.lat, maxX: first.lon, maxY: first.lat)) { box, p in
            RouteGraph.BBox(minX: min(box.minX, p.lon), minY: min(box.minY, p.lat),
                            maxX: max(box.maxX, p.lon), maxY: max(box.maxY, p.lat))
        }
    }

    /// The endpoint station candidates `RouteSolver.prepareSectionEndpoints`
    /// hands the solver: registry company-station codes when a jp lookup is
    /// installed, otherwise name/group expansion filtered by the ride date.
    static func endpointCandidates(
        _ section: RouteSection, rideDate: String, allowedCodes: [String]
    ) -> (from: [Int], to: [Int]) {
        let stations = Self.environment.stations
        if case .ready = SolverRegistryInput.availability(region: "jp") {
            return RouteSolver.registryEndpointIndices(
                section: section, country: "jp", stations: stations, rideDate: rideDate) ?? ([], [])
        }
        let lines = (section.lineNames ?? []).filter { !$0.isEmpty }
        func expand(_ name: String?, _ code: String?) -> [Int] {
            RouteSolver.filterStationCandidatesByRideDate(
                RouteSolver.resolveRouteEndpointStationCandidates(
                    .stop(.init(name: name, n02StationCode: code)), in: stations,
                    allowedCodes: allowedCodes, sectionLineNames: lines,
                    sectionOperatorNames: section.operatorNames ?? [], rideDate: rideDate),
                in: stations, rideDate: rideDate)
        }
        return (expand(section.from, section.fromN02StationCode),
                expand(section.to, section.toN02StationCode))
    }

    /// `dedupeSameTrainRouteFeatures` (app-route-graph.js) for one solved
    /// feature, which the browser applies before the fixture digest: drop
    /// zero-length steps (a zero-length registry junction repeats its vertex)
    /// and any direction-independent segment already drawn in this section.
    /// The JS pushes one shared `uniqueLine` array and later clears and
    /// refills it, so every emitted member aliases the final run; this mirror
    /// reproduces that output exactly.
    static func webDedupedLines(_ coordinates: [Coordinate]) -> [[Coordinate]] {
        var seen = Set<String>()
        var line: [Coordinate] = []
        var pushes = 0
        for (from, to) in zip(coordinates, coordinates.dropFirst()) {
            if from == to { continue }
            guard seen.insert(Grid.routeCoordinateSegmentKey(from, to)).inserted else { continue }
            if line.isEmpty {
                line.append(from)
            } else if line[line.count - 1] != from {
                if line.count >= 2 { pushes += 1 }
                line = [from]
            }
            line.append(to)
        }
        if line.count >= 2 { pushes += 1 }
        return Array(repeating: line, count: pushes)
    }

    struct WebTwin { let physicalLengthM: Double; let pathDigest: String }

    /// The Swift twin of a `port-fixtures/historical-routes.json` answer at
    /// ``RouteGraph/routeSolverCacheVersion``. The fixture is the browser
    /// `RouteService` solve on the same physical identity graph with the same
    /// reviewed junctions (`app-route-graph.js` keys nodes `identity@coord`),
    /// so its raw path is the native raw path. The browser then completes each
    /// end to the display point of the station whose candidate node the path
    /// starts or ends on (`completeRouteEndpointCoordinates` with
    /// `best.fromCandidate.stationFeature` in `app-route-solver.js`);
    /// `physical_length_m` is measured over that completed line, and
    /// `path_digest` over it after `dedupeSameTrainRouteFeatures`. Native
    /// SolvedSection deliberately keeps only surveyed vertices and the fixed
    /// station identity, so the twin rebuilds the routing candidate here.
    static func webTwin(
        _ solved: RouteSolver.SolvedSection, section: RouteSection, rideDate: String
    ) -> WebTwin {
        let env = Self.environment
        let features = env.stations.features
        var fromStation = solved.fromStationIndex
        var toStation = solved.toStationIndex
        if let box = Self.pathBBox(solved.coordinates) {
            defer { env.graphStore.invalidate() }
            let graph = env.graphStore.regionalGraph(
                for: RouteGraph.padBBoxMeters(box, meters: 3_000), routeSolveInProgress: true)
            let ends = Self.endpointCandidates(
                section, rideDate: rideDate, allowedCodes: solved.allowedInstitutionTypeCodes)
            func routing(_ stations: [Int], key: String?) -> Int? {
                RouteSolver.collectStationCandidateGraphNodes(
                    stationIndices: stations, stations: env.stations, graph: graph,
                    hints: solved.hints, allowedCodes: solved.allowedInstitutionTypeCodes
                ).first { $0.key == key }?.stationIndex
            }
            let from = routing(ends.from, key: solved.rawPathKeys.first)
            let to = routing(ends.to, key: solved.rawPathKeys.last)
            #expect(from != nil && to != nil, "routing candidate station for the solved endpoints")
            fromStation = from ?? fromStation
            toStation = to ?? toStation
        }
        let completed = RouteSolver.completeRouteEndpointCoordinates(
            solved.coordinates, fromStation: features[fromStation], toStation: features[toStation])
        let canonical = Self.webDedupedLines(completed).map(Self.canonicalPath).joined(separator: "|")
        return WebTwin(
            physicalLengthM: (RouteSolver.pathLength(for: completed) * 100).rounded() / 100,
            pathDigest: RouteGraph.keyDigest(canonical))
    }

    /// Exact Swift↔JS parity: the hundredth-rounded `physical_length_m` and
    /// the `path_digest`.
    static func assertWebParity(
        _ solved: RouteSolver.SolvedSection, section: RouteSection,
        answer: HistoricalRoutesFixture.Answer, id: String
    ) {
        let twin = Self.webTwin(solved, section: section, rideDate: answer.train.date)
        #expect(twin.physicalLengthM == answer.physicalLengthM,
                "\(id) web physical_length_m at \(answer.train.date)")
        #expect(twin.pathDigest == answer.pathDigest,
                "\(id) web path digest at \(answer.train.date)")
    }

    static func train(rideDate: String?) -> RouteSolver.TrainContext {
        RouteSolver.TrainContext(
            id: "rail-history-test", number: "", trainType: "", company: "",
            origin: "", destination: "", preferredLineNames: [], preferredOperatorNames: [],
            allowedInstitutionTypeCodes: nil, institutionFilterMode: "soft", rideDate: rideDate)
    }

    static func solve(
        _ from: String, _ to: String, lineName: String? = nil, rideDate: String?
    ) -> RouteSolver.SolvedSection? {
        let section = RouteSection(
            from: from, to: to, lineNames: lineName.map { [$0] })
        return Self.solve(section, rideDate: rideDate)
    }

    static func solve(_ section: RouteSection, rideDate: String?) -> RouteSolver.SolvedSection? {
        let env = Self.environment
        // Release graph and compiled-region memos after each native query too.
        defer { env.graphStore.invalidate() }
        return RouteSolver.solveSectionOnDemand(
            section, segmentIndex: 0, train: Self.train(rideDate: rideDate), country: "jp",
            graphStore: env.graphStore, stations: env.stations, continuityAnchor: nil)
    }

    static func km(_ solved: RouteSolver.SolvedSection) -> Double {
        solved.physicalLength / 1000
    }

    @Test func sameCorridorHankaiBranchExistsOnlyBeforeClosure() throws {
        let solved = try #require(Self.solve("住吉", "住吉公園", lineName: "上町線",
                                             rideDate: "2016-01-30"))
        #expect(Self.km(solved) > 0.05 && Self.km(solved) < 0.5)
        #expect(Self.solve("住吉", "住吉公園", lineName: "上町線",
                           rideDate: "2016-01-31") == nil)
    }

    @Test func operatorTransferPreservesDonanPredecessorLineIdentity() throws {
        let old = try #require(Self.solve("五稜郭", "木古内", lineName: "江差線",
                                         rideDate: "2016-03-25"))
        #expect(Self.withinTolerance(Self.km(old), 37.8))
        let new = try #require(Self.solve("五稜郭", "木古内", lineName: "道南いさりび鉄道線",
                                         rideDate: "2016-03-26"))
        #expect(Self.withinTolerance(Self.km(new), 37.8))
    }

    @Test func historicalStationNameResolvesBeforeKeikyuRename() throws {
        #expect(Self.solve("糀谷", "羽田空港国内線ターミナル", lineName: "空港線",
                           rideDate: "2020-03-13") != nil)
        #expect(Self.solve("糀谷", "羽田空港第1・第2ターミナル", lineName: "空港線",
                           rideDate: "2020-03-14") != nil)
        #expect(Self.solve("糀谷", "羽田空港国内線ターミナル", lineName: "空港線",
                           rideDate: "2020-03-14") == nil)
    }

    @Test func disasterSuspensionDoesNotRemainRideableUntilLegalClosure() throws {
        #expect(Self.solve("延岡", "高千穂", lineName: "高千穂線",
                           rideDate: "2005-09-06") == nil)
        #expect(Self.solve("柳津", "気仙沼", lineName: "気仙沼線",
                           rideDate: "2011-03-12") == nil)
        #expect(Self.solve("東名", "野蒜", lineName: "仙石線",
                           rideDate: "2014-01-01") == nil)
        #expect(Self.solve("坂元", "新地", lineName: "常磐線",
                           rideDate: "2014-01-01") == nil)
    }

    static func withinTolerance(_ measured: Double, _ expected: Double, factor: Double = 0.25)
        -> Bool
    {
        abs(measured - expected) <= expected * factor
    }

    /// Nearest solved vertex to `point`, in metres.
    static func minDistanceMeters(_ point: Coordinate, path: [Coordinate]) -> Double {
        path.map { Geometry.distanceMeters(point, $0) }.min() ?? .infinity
    }

    /// `display_point` if present, else the geometry's first coordinate —
    /// good enough for both a `Point` station and a retired `LineString`
    /// section-style feature.
    static func firstCoordinate(_ feature: Stations.Feature) -> Coordinate? {
        if let pair = Stations.displayCoordinate(feature), let coordinate = Coordinate(pair: pair)
        {
            return coordinate
        }
        guard case .array(let coordinates)? = feature.geometry?.coordinates else { return nil }
        if coordinates.count == 2, case .number(let lon) = coordinates[0],
            case .number(let lat) = coordinates[1]
        {
            return Coordinate(lon: lon, lat: lat)
        }
        if case .array(let first)? = coordinates.first, first.count == 2,
            case .number(let lon) = first[0], case .number(let lat) = first[1]
        {
            return Coordinate(lon: lon, lat: lat)
        }
        return nil
    }

    /// `path_digest` in `port-fixtures/historical-routes.json`: five decimal
    /// `lon,lat`, semicolons between coordinates, pipes between MultiLineString
    /// members. One solved section is one LineString feature.
    static func canonicalPath(_ coordinates: [Coordinate]) -> String {
        coordinates.map { coordinate in
            Self.fixed5(coordinate.lon) + "," + Self.fixed5(coordinate.lat)
        }.joined(separator: ";")
    }

    /// JavaScript `Number.prototype.toFixed(5)` (half away from zero).
    static func fixed5(_ value: Double) -> String {
        var scaled = (value * 100_000).rounded()
        if scaled == 0 { scaled = 0 }
        let negative = scaled < 0
        let digits = Int(abs(scaled).rounded())
        let body = "\(digits / 100_000)." + String(format: "%05d", digits % 100_000)
        return negative ? "-" + body : body
    }

    struct HistoricalRoutesFixture: Decodable {
        struct Answer: Decodable {
            struct Section: Decodable {
                let from: String
                let to: String
                let lineNames: [String]
                let operatorNames: [String]
                let fromStationCode: String?
                let toStationCode: String?
                enum CodingKeys: String, CodingKey {
                    case from, to
                    case lineNames = "line_names"
                    case operatorNames = "operator_names"
                    case fromStationCode = "from_n02_station_code"
                    case toStationCode = "to_n02_station_code"
                }
            }
            struct TrainBody: Decodable { let date: String }
            struct Revisions: Decodable { let jp: String }
            struct SolverContext: Decodable {
                let historyRevisions: Revisions
                let solverVersion: String
                enum CodingKeys: String, CodingKey {
                    case historyRevisions = "history_revisions"
                    case solverVersion = "solver_version"
                }
            }
            let id: String
            let train: TrainBody
            let section: Section
            let solverContext: SolverContext
            let outcome: String
            let segmentCount: Int
            let pathDigest: String
            let physicalLengthM: Double
            enum CodingKeys: String, CodingKey {
                case id, train, section, outcome
                case solverContext = "solver_context"
                case segmentCount = "segment_count"
                case pathDigest = "path_digest"
                case physicalLengthM = "physical_length_m"
            }
        }
        let cases: [Answer]
        let pinned: [Answer]
        struct Boundary: Decodable {
            let id: String
            let before: Answer
            let at: Answer
        }
        let eventBoundaries: [Boundary]
    }

    @Test func everyGeneratedRouteBoundaryMatchesWebSolve() throws {
        let fixture = try PortFixtures.decode(HistoricalRoutesFixture.self, "historical-routes.json")
        let answers = fixture.eventBoundaries.flatMap { [$0.before, $0.at] } + fixture.pinned
        for answer in answers {
            let section = RouteSection(from: answer.section.from, to: answer.section.to,
                fromN02StationCode: answer.section.fromStationCode,
                toN02StationCode: answer.section.toStationCode,
                lineNames: answer.section.lineNames,
                operatorNames: answer.section.operatorNames)
            #expect(answer.solverContext.solverVersion == RouteGraph.routeSolverCacheVersion)
            let native = Self.solve(section, rideDate: answer.train.date)
            #expect((native != nil) == (answer.outcome == "solved"),
                    "\(answer.id): native physical validity at \(answer.train.date)")
            if let native {
                Self.assertNativeSurveyedPath(native, section: section,
                    rideDate: answer.train.date, id: answer.id)
                Self.assertWebParity(native, section: section, answer: answer, id: answer.id)
            } else {
                #expect(answer.pathDigest == RouteGraph.keyDigest(""), "\(answer.id) unsolved digest")
            }
        }
    }

    /// Same generated boundaries as the fixture replay, with the shipped jp
    /// registry installed. A boundary is recorded only when the registry
    /// changes the fixture outcome or digest. The fixture-replay test is unchanged.
    @Test func generatedBoundariesWithInstalledRegistryMatchExpectedDifferences() throws {
        struct Difference: Codable, Equatable {
            var id: String
            var fixtureOutcome: String
            var registryOutcome: String
            var reason: String
        }
        struct Document: Codable {
            var schema: String
            var provenance: ArtifactProvenance?
            var differences: [Difference]
        }
        let root = try PortFixtures.repositoryRoot()
        let bundleData = try Data(contentsOf: root.appending(path: "app/data/registry-bundle/jp.json"))
        let bundle = try JSONDecoder().decode(RegistryBundle.self, from: bundleData)
        let identity = RegistryIdentity(bundle: bundle)
        let expectedData = try Data(contentsOf: root.appending(
            path: "app/data/registry/jp/history-registry-differences.json"))
        let expected = try JSONDecoder().decode(Document.self, from: expectedData)
        let fixture = try PortFixtures.decode(HistoricalRoutesFixture.self, "historical-routes.json")
        let answers = fixture.eventBoundaries.flatMap { [$0.before, $0.at] } + fixture.pinned
        var found: [Difference] = []
        RegistryIdentityLookup.withTestProvider({ region in
            region.lowercased() == "jp" ? identity : nil
        }) {
            for answer in answers {
                // Upgrade exactly as production does at load, before solving.
                let raw = RouteSection(
                    from: answer.section.from, to: answer.section.to,
                    fromN02StationCode: answer.section.fromStationCode,
                    toN02StationCode: answer.section.toStationCode,
                    lineNames: answer.section.lineNames,
                    operatorNames: answer.section.operatorNames)
                let company = answer.section.operatorNames.filter { !$0.isEmpty }.joined(separator: "/")
                let upgradedTrain = RegistryIdentityUpgrade.apply(
                    Train(id: answer.id, date: answer.train.date, number: "", company: company.isEmpty ? nil : company,
                          origin: answer.section.from, destination: answer.section.to,
                          routeSections: [raw], stops: [], region: "jp"),
                    bundle: bundle)
                let section = upgradedTrain.routeSections?.first ?? raw
                let native = Self.solve(section, rideDate: answer.train.date)
                if native == nil && answer.outcome != "solved" { continue }
                if let native {
                    let digest = Self.webTwin(native, section: section, rideDate: answer.train.date).pathDigest
                    if digest == answer.pathDigest && answer.outcome == "solved" { continue }
                    let reason = digest == answer.pathDigest
                        ? "registry solve succeeded where the fixture was recorded as \(answer.outcome)"
                        : "registry solve changed the path digest (from_station_id \(section.fromStationID ?? "nil"), to_station_id \(section.toStationID ?? "nil"))"
                    found.append(Difference(
                        id: answer.id, fixtureOutcome: answer.outcome,
                        registryOutcome: "solved", reason: reason))
                } else {
                    func label(_ name: String, _ code: String?) -> String { code.map { "\($0)" } ?? "name \(name)" }
                    var missing: [String] = []
                    if section.fromStationID == nil { missing.append("from \(label(section.from ?? "", section.fromN02StationCode))") }
                    if section.toStationID == nil { missing.append("to \(label(section.to ?? "", section.toN02StationCode))") }
                    let reason = missing.isEmpty
                        ? "station_id resolves for both endpoints (\(section.fromStationID ?? ""), \(section.toStationID ?? "")) but the registry solve found no path"
                        : "endpoint has no station_id after upgrade: " + missing.joined(separator: "; ")
                    found.append(Difference(
                        id: answer.id, fixtureOutcome: answer.outcome,
                        registryOutcome: "unsolved", reason: reason))
                }
            }
        }
        found.sort { $0.id < $1.id }
        if ProcessInfo.processInfo.environment["JTM_REGENERATE_HISTORY_REGISTRY_DIFFERENCES"] != nil {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let provenance = ArtifactProvenance.current(
                root: root,
                generator: "ios/RailKit/Tests/RailCoreTests/History/RailHistoryPackageTests.swift",
                regenerate: "JTM_REGENERATE_HISTORY_REGISTRY_DIFFERENCES=1 swift test --package-path ios/RailKit --filter generatedBoundariesWithInstalledRegistryMatchExpectedDifferences",
                inputs: [
                    "port-fixtures/historical-routes.json",
                    "app/data/registry-bundle/jp.json",
                    "app/data/rail-history.json",
                    "app/data/rail-sections.json",
                    "app/data/stations.json",
                    "app/data/physical-rail-junctions.json",
                ], solverDependent: true)
            var out = try encoder.encode(Document(
                schema: "jtm-history-registry-differences/1", provenance: provenance, differences: found))
            out.append(0x0A)
            try out.write(to: root.appending(path: "app/data/registry/jp/history-registry-differences.json"))
            return
        }
        let mismatched = zip(found, expected.differences).filter { $0 != $1 }.prefix(3)
            .map { "\($0.id) vs \($1.id)" }
        #expect(expected.schema == "jtm-history-registry-differences/1")
        #expect(found.count == expected.differences.count, "count \(found.count) vs \(expected.differences.count); first \(mismatched)")
        #expect(found == expected.differences)
    }

    /// The six Gate A rides, solved on demand, against the current-solver fixture.
    @Test func historicalFixtureSixRidesMatchOnDemandSolve() throws {
        let fixture = try PortFixtures.decode(HistoricalRoutesFixture.self, "historical-routes.json")
        let expectedOutcome = [
            "yubari:historical": "solved",
            "yubari:unsolvable-2019-04-01": "unsolvable",
            "mashike:historical": "solved",
            "mashike:unsolvable-2020-06-01": "unsolvable",
            "joban:historical": "solved",
            "joban:post-relocation-2020-06-01": "solved",
        ]
        let answers = Dictionary(
            uniqueKeysWithValues: (fixture.cases + fixture.pinned).map { ($0.id, $0) })
        for id in expectedOutcome.keys.sorted() {
            let outcome = expectedOutcome[id]!
            let answer = try #require(answers[id])
            #expect(answer.outcome == outcome)
            #expect(answer.solverContext.historyRevisions.jp == Self.environment.overlay.revision)
            #expect(answer.solverContext.solverVersion == RouteGraph.routeSolverCacheVersion)
            let lineName = answer.section.lineNames.first { !$0.isEmpty }
            let section = RouteSection(from: answer.section.from, to: answer.section.to,
                                       lineNames: lineName.map { [$0] })
            let native = Self.solve(section, rideDate: answer.train.date)
            #expect((native != nil) == (outcome == "solved"), "\(id) native outcome")
            if let native {
                Self.assertNativeSurveyedPath(native, section: section, rideDate: answer.train.date, id: id)
            }
            if outcome == "unsolvable" {
                #expect(answer.segmentCount == 0)
                #expect(answer.pathDigest == RouteGraph.keyDigest(""))
            } else {
                let native = try #require(native, "\(id) native outcome")
                #expect(answer.segmentCount == 1)
                Self.assertWebParity(native, section: section, answer: answer, id: id)
            }
        }
    }

    /// Generate a boundary assertion from every shipped temporal feature and
    /// retirement rule. This catches a newly added event whose switch day is
    /// off by one without adding a hand-written route for each fragment.
    @Test func allHistoryIntervalsUseHalfOpenBoundaries() throws {
        let overlay = Self.environment.overlay
        var intervals = overlay.sections.map {
            ($0.properties.validFrom, $0.properties.validTo)
        }
        intervals += overlay.stations.map {
            ($0.properties["valid_from"]?.jsString, $0.properties["valid_to"]?.jsString)
        }
        intervals += overlay.retirements.map { ($0.validFrom, $0.validTo) }
        #expect(intervals.count >= 900)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        for (from, to) in intervals {
            if let from {
                let date = try #require(formatter.date(from: from))
                let before = try #require(formatter.calendar.date(byAdding: .day, value: -1, to: date))
                #expect(!RouteGraph.RailValidity.isValid(
                    validFrom: from, validTo: to, on: formatter.string(from: before)))
                #expect(RouteGraph.RailValidity.isValid(
                    validFrom: from, validTo: to, on: from))
            }
            if let to {
                let date = try #require(formatter.date(from: to))
                let before = try #require(formatter.calendar.date(byAdding: .day, value: -1, to: date))
                #expect(RouteGraph.RailValidity.isValid(
                    validFrom: from, validTo: to, on: formatter.string(from: before)))
                #expect(!RouteGraph.RailValidity.isValid(
                    validFrom: from, validTo: to, on: to))
            }
        }
    }

    // MARK: - 1. 石勝線 新夕張→夕張 (夕張支線, retired 2019-04-01)

    @Test func shintoyuubariToYuubariSolves2018() throws {
        let solved = try #require(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: "2018-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 16.1))
    }

    @Test func shintoyuubariToYuubariNotSolvedAfterRetirement() throws {
        #expect(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: "2019-04-01") == nil)
    }

    @Test func shintoyuubariToYuubariNotSolvedUndated() throws {
        #expect(Self.solve("新夕張", "夕張", lineName: "石勝線", rideDate: nil) == nil)
    }

    // MARK: - 2. 留萌線 深川→増毛 (増毛延伸区間, retired 2016-12-05)

    @Test func fukagawaToMashikeSolves2015() throws {
        let solved = try #require(Self.solve("深川", "増毛", lineName: "留萌線", rideDate: "2015-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 66.8))
    }

    @Test func fukagawaToMashikeNotSolved2020() throws {
        #expect(Self.solve("深川", "増毛", lineName: "留萌線", rideDate: "2020-06-01") == nil)
    }

    // MARK: - 3. 高千穂線 延岡→高千穂 (retired 2008)

    @Test func nobeokaToTakachihoSolves2004() throws {
        let solved = try #require(
            Self.solve("延岡", "高千穂", lineName: "高千穂線", rideDate: "2004-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 50.0))
    }

    // MARK: - 4. 大船渡線 気仙沼→盛 (rail service ended with the 2011 disaster)

    @Test func kesennumaToSakariSolves2010() throws {
        let solved = try #require(
            Self.solve("気仙沼", "盛", lineName: "大船渡線", rideDate: "2010-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 43.7))
    }

    @Test func kesennumaToSakariCannotUseBRTAsRail2019() {
        let solved = Self.solve("気仙沼", "盛", lineName: "大船渡線", rideDate: "2019-06-01")
        // A solver may find another railway route. It must not reuse the
        // 43.7 km coastal railway whose trains never resumed.
        if let solved { #expect(Self.km(solved) > 100) }
    }

    // MARK: - 5. 日高線 鵡川→様似 (retired 2021-04-01)

    @Test func mukawaToSamaniSolves2014() throws {
        let solved = try #require(
            Self.solve("鵡川", "様似", lineName: "日高線", rideDate: "2014-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 116))
    }

    @Test func mukawaToSamaniNotSolved2020() {
        #expect(Self.solve("鵡川", "様似", lineName: "日高線", rideDate: "2020-06-01") == nil)
    }

    @Test func hidakaPartialResumptionDoesNotReopenNorthernSection() throws {
        let solved = try #require(Self.solve("静内", "様似", lineName: "日高線", rideDate: "2015-02-01"))
        #expect(Self.km(solved) > 50)
        #expect(Self.solve("鵡川", "様似", lineName: "日高線", rideDate: "2015-02-01") == nil)
        #expect(Self.solve("静内", "様似", lineName: "日高線", rideDate: "2015-03-01") == nil)
    }

    @Test(arguments: [
        ("西船橋", "東葉勝田台", "東葉高速線", "1996-04-26", "1996-04-27"),
        ("横浜", "元町・中華街", "みなとみらい21線", "2004-01-31", "2004-02-01"),
        ("名古屋", "金城ふ頭", "西名古屋港線", "2004-10-05", "2004-10-06"),
        ("秋葉原", "つくば", "常磐新線", "2005-08-23", "2005-08-24"),
        ("日暮里", "見沼代親水公園", "日暮里・舎人ライナー", "2008-03-29", "2008-03-30"),
    ])
    func wholeLineOpeningsRespectExactDay(_ from: String, _ to: String, _ line: String,
                                         _ before: String, _ opening: String) throws {
        #expect(Self.solve(from, to, lineName: line, rideDate: before) == nil)
        let solved = try #require(Self.solve(from, to, lineName: line, rideDate: opening))
        #expect(Self.km(solved) > 1)
    }

    // MARK: - 6. 常磐線 相馬→亘理 (old coastal alignment via 新地, replaced 2016-12-10)

    /// The old coastal alignment (service suspended 2011-03-11) must splice into the
    /// undated track at both ends; the inland alignment is dated
    /// valid_from 2016-12-10, so a 2010 ride can only take the old one.
    @Test func somaToWatariSolvesOldAlignment2010() throws {
        let solved = try #require(
            Self.solve("相馬", "亘理", lineName: "常磐線", rideDate: "2010-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 34))

        let oldShinchi = try #require(
            Self.environment.overlay.stations.first {
                Stations.stationName($0) == "新地"
                    && $0.properties["valid_to"]?.jsString == "2011-03-12"
            })
        let oldPoint = try #require(Self.firstCoordinate(oldShinchi))
        #expect(Self.minDistanceMeters(oldPoint, path: solved.coordinates) <= 300)
    }

    @Test func somaToWatariSolvesNewAlignment2020() throws {
        let solved = try #require(
            Self.solve("相馬", "亘理", lineName: "常磐線", rideDate: "2020-06-01"))

        let currentShinchi = try #require(
            Self.environment.stations.features.first {
                Stations.stationName($0) == "新地" && Stations.stationLineName($0) == "常磐線"
                    && ($0.properties["valid_to"]?.jsString.isEmpty ?? true)
            })
        let currentPoint = try #require(Self.firstCoordinate(currentShinchi))
        #expect(Self.minDistanceMeters(currentPoint, path: solved.coordinates) <= 300)
    }

    // MARK: - 7. 留萌線 深川→石狩沼田 (remaining stub, retired 2026-04-01)

    @Test func fukagawaToIshikariNumataNotSolvedAfterRetirement() throws {
        #expect(Self.solve("深川", "石狩沼田", lineName: "留萌線", rideDate: "2026-07-01") == nil)
    }

    @Test func fukagawaToIshikariNumataSolvesBeforeRetirement() throws {
        let solved = try #require(
            Self.solve("深川", "石狩沼田", lineName: "留萌線", rideDate: "2026-03-01"))
        #expect(Self.withinTolerance(Self.km(solved), 14.4))
    }

    // MARK: - Joins land on the right railway (review of the builder)

    /// 屋代線 must splice into しなの鉄道 at 屋代, not into 北陸新幹線 47 m away.
    @Test func yashiroToSuzakaSolves2011() throws {
        let solved = try #require(
            Self.solve("屋代", "須坂", lineName: "屋代線", rideDate: "2011-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 24.4))
    }

    /// 江差線 must meet the 在来線 at 木古内, not 北海道新幹線 (opened 2016).
    @Test func kikonaiToEsashiSolves2013() throws {
        let solved = try #require(
            Self.solve("木古内", "江差", lineName: "江差線", rideDate: "2013-06-01"))
        #expect(Self.withinTolerance(Self.km(solved), 42.1))
    }
}
