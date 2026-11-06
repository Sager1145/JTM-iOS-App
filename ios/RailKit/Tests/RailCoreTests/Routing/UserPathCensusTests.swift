import Foundation
import Testing
@_spi(Testing) @testable import RailCore

/// Opt-in census of the bundled example trips through the SAME path a
/// reader's own journey takes (539cd7da3, "one resolve path for example and
/// user trips").
///
/// The app no longer ships precomputed sample parts. A sample is decoded as a
/// plain `TrainStore` (`RideStorage.decodeSample`), merged into the working
/// set, and on a route-cache miss `RiddenRouteStore` solves it live:
///
///     decode → decodeUncached → solveMissing(allowLegacy: false)   // inference pass
///                             → solveMissing(allowLegacy: true)    // legacy pass, for what pass 1 dropped
///       solveMissing → canonicalRouteInput (registry upgrade, export
///                      normalisation, timetable enrichment, corridor preference)
///                    → solveMissingSequentialWithPermit
///                      → RideRouteResolution(inputs:country:network:officialIntervals:graphStore:)
///                        .resolve(_:allowLegacy:)
///
/// `RideRouteResolution` (RailCore) owns the whole physical-route policy,
/// including the display canonicalisation (`RouteNetwork.sourceCertification`
/// / `canonicalizeRouteFeature`), so every `Segment.drawnCoordinates` it
/// returns is exactly the WGS84 stroke the map draws (the app only applies
/// `AppleMapDatum.display` afterwards, and applies the same displacement to
/// the network layer, so comparisons here stay in WGS84).
///
/// This test calls that RailCore entry directly with inputs built the way the
/// app builds them. The app-target pieces RailKit cannot reach are mirrored at
/// their minimum; each mirror names its source at 539cd7da3:
///
/// - `RiddenRouteStore.prepareSolverInputs` (RiddenRouteStore.swift:1285-1327):
///   rail-sections / stations per graph region in catalog order, rail-history
///   overlay applied (`applyRailHistory`, :1720-1738, unmatched retirements are
///   a load error), identity periods, `physical-rail-junctions.json` junctions
///   for the ride-order regions.
/// - `RiddenRouteStore.fallbackGraphStore` (:1393-1409): one
///   `RouteGraphStore(.physicalRailway, .bounded(100_000))` per scope, shared
///   by both passes and every ride in the scope (`decode`, :837-853).
/// - `DisplayNetworkCache.network(scope:)` / `assemble`
///   (DisplayNetworkCache.swift:114-126, :387-401): `<cc>-2025.json` →
///   `DisplayParts.parts` → `RouteNetwork`, lines concatenated in catalog
///   order for a cross-border scope.
/// - `SolverInputCache.networkIndexes` / `officialIntervals` (:1213-1235):
///   `RideRouteResolution.NetworkInputs(network:inputs:)` and
///   `inputs.officialIntervals`.
/// - `RiddenRouteStore.canonicalRouteInput` (:1013-1040) with
///   `BundledRegistry.upgradeIfReady` (BundledRegistry.swift:247-252 →
///   `RegistryIdentityUpgrade.apply`) and `TimetableRouteEvidence.match`
///   (TimetableRouteEvidence.swift:53-119, minus the editor-applied evidence
///   store and the revision-keyed memo, neither of which changes an answer).
/// - `awaitScopeRegistry` (:1806-1834): the solve runs after the registry
///   settles, so the registry phase is `.ready` for every region with a
///   `registry-bundle/<cc>.json` (task-local test phase, not a global install).
/// - `RouteScope` / `RegionScopeRule.regionCodesTouched` / `RouteScope.ordered`
///   (RegionCatalog.swift:356-417, RegionScopeRule.swift:169-191): grouping
///   by scope, compact scopes first.
/// - `solveMissing` pass logic (:1073-1127, :1502-1573, :858-889): a ride whose
///   inference pass returns `.unsupported/.awaitingConfirmation/.noSections`
///   is dropped from pass 1 and solved again with `allowLegacy: true`.
///
/// Per drawn part it records the original census fields
/// (`app/scripts/samples/audit-sample-routes.py` reads `ride`, `from`, `to`,
/// `projected`, `displayLines`, `sourceToDrawnMaxM`, `drawnToSourceMaxM`)
/// plus how the part was produced and how far the drawn stroke strays from
/// the display network it claims to follow. "source" is now the path the
/// solver actually walked (`Segment.sourceCoordinates`), not a precomputed
/// part.
///
///     SAMPLE_DISPLAY_CENSUS=1 SAMPLE_DISPLAY_CENSUS_OUTPUT=/abs/out.json \
///       swift test -c release -Xswiftc -enable-testing --filter UserPathCensusTests
///
/// `SAMPLE_DISPLAY_CENSUS_STRICT=1` additionally fails the test for every
/// ride that is not fully solved, projected, certified and on the network.
@Suite(.serialized)
struct UserPathCensusTests {

    // MARK: - What the app ships

    /// `RideLibrary.Sample.all` order (RideLibrary.swift:37-45); the repo file
    /// `copy-rail-packages.sh:251-271` bundles as `<resource>.json`.
    static let samples: [(resource: String, path: String)] = [
        ("train-store", "app/data/train-store.json"),
        ("new-year-grand-loop", "app/data/special-samples/new-year-grand-loop.json"),
        ("tokyo-limited-express-loop", "app/data/special-samples/tokyo-limited-express-loop.json"),
        ("train-store-tw", "app/data/train-store-tw.json"),
        ("train-store-hk", "app/data/train-store-hk.json"),
        ("train-store-mo", "app/data/train-store-mo.json"),
        ("train-store-kr", "app/data/train-store-kr.json"),
    ]

    /// `Region.allCases` (RegionCatalog.swift:52-58): the catalog order.
    static let catalog = ["jp", "tw", "hk", "mo", "kr", "cn"]
    /// `Region.ordered` (RegionCatalog.swift:67).
    static let interfaceOrder = ["mo", "hk", "tw", "kr", "jp", "cn"]
    /// `Region.dataWeight == .large` (RegionCatalog.swift:134-139).
    static let largeRegions: Set<String> = ["jp", "cn"]

    /// Stroke deviation, in metres, above which strict mode fails a part.
    static let strictToleranceM = 25.0
    /// Off-network distances are exact below this and reported as this above it.
    static let networkCapM = 350.0

    // MARK: - Census record

    struct Leg: Encodable {
        // Original census fields — names and meanings unchanged.
        let store: String
        let ride: String
        let segment: Int
        let from: String?
        let to: String?
        var projected = false
        var displayLineIDs: [String] = []
        var displayLines: [String] = []
        var displayOperators: [String] = []
        var sourceLengthM = 0.0
        var drawnLengthM = 0.0
        /// Largest distance from a solved-path sample to the drawn stroke.
        var sourceToDrawnMaxM = 0.0
        /// Largest distance from a drawn sample to the solved path.
        var drawnToSourceMaxM = 0.0
        /// Longest straight drawn edge between consecutive vertices.
        var longestDrawnEdgeM = 0.0

        // New fields.
        /// Part index within the section (`Segment.partIndex`).
        var part = 0
        /// A drawn segment exists for this section.
        var solved = false
        /// `<pass>/<branch>`: pass is `inference` (`allowLegacy: false`) or
        /// `legacy` (`allowLegacy: true`); branch is `intervals` (materialised
        /// interval codes → `sourceCertification` + `canonicalizeRouteFeature`),
        /// `solver+display` (official-interval / on-demand graph solve, then
        /// `canonicalizeRouteFeature`), `solver-raw` (graph solve drawn as-is:
        /// canonicalisation refused or the path is historical) or `unsolved`.
        /// `none/<disposition>` when the app emits no ride at all.
        var solvePath = ""
        /// `RideRouteResolution.Result.Disposition` of the pass that produced the ride.
        var disposition = ""
        /// `PhysicalRouteSelection.Provenance` of the part, when it has one.
        var provenance: String?
        /// Where `displayLineIDs` came from: `selection` (the app's own
        /// `physicalRoute.lines`, what the journey card shows), `geometry`
        /// (lines within 2 m of the drawn stroke, when the app has no
        /// selection) or `none`.
        var displayLineSource = "none"
        var temporalKind: String?
        /// No interior `PhysicalGap` for this section.
        var certified = false
        /// A boundary `PhysicalGap` before this section.
        var boundaryGap = false
        /// Largest distance from a drawn sample to ANY display-network line
        /// (straight chords, missing geometry). Capped at `networkCapM`.
        var drawnOffNetworkMaxM = 0.0
        /// Largest distance from a drawn sample to the display lines this
        /// part is attributed to (wrong line drawn under a right label).
        /// Capped at `networkCapM`; nil without attribution.
        var drawnOffDisplayLinesMaxM: Double?
        var requestedLineIDs: [String] = []
        var requestedLineNames: [String] = []
        var requestedOperatorNames: [String] = []
        /// Attributed display line ids the section did not ask for (only
        /// computed when the section names `line_ids`).
        var displayLineIDsOutsideRequest: [String] = []
        var timetableMatched = false
        var timetableFailure: String?
        /// Wall time of the pass(es) that produced this ride, per ride.
        var rideSolveMs = 0.0
        /// Number of route sections the resolver considered for the ride.
        var legCount = 0
        /// Drawn stroke, `[lon, lat]` WGS84, before any `AppleMapDatum`.
        var drawnCoordinates: [[Double]] = []
        /// Ride-level `RiddenLineSequence` summary run names, in travel order.
        var lineSummary: [String] = []
        /// `RiddenLineSequence.Source` per route section, in section order.
        var lineSources: [String] = []
        /// Summary boundaries as `<station code or ?>:<kind>`.
        var lineBoundaries: [String] = []
    }

    // MARK: - Mirrored scope rules (RegionScopeRule, RouteScope)

    static func regionCode(forStationCode code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let pieces = code.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count >= 3, pieces[0] == "st" || pieces[0] == "op" {
            let region = String(pieces[1]).lowercased()
            if catalog.contains(region) { return region }
        }
        if code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) { return "jp" }
        guard let dash = code.firstIndex(of: "-") else { return nil }
        let head = String(code[code.startIndex..<dash]).lowercased()
        return catalog.contains(head) ? head : nil
    }

    static func regionsTouched(_ train: Train) -> [String] {
        var seen: [String] = []
        func add(_ region: String?) {
            guard let region, !seen.contains(region) else { return }
            seen.append(region)
        }
        if let declared = train.region, catalog.contains(declared) { add(declared) }
        for stop in train.stops { add(regionCode(forStationCode: stop.stationID)) }
        add(regionCode(forStationCode: train.operatorID))
        for stop in train.stops { add(regionCode(forStationCode: stop.n02StationCode)) }
        for section in train.routeSections ?? [] {
            add(regionCode(forStationCode: section.fromN02StationCode))
            add(regionCode(forStationCode: section.toN02StationCode))
        }
        return seen.isEmpty ? ["jp"] : seen
    }

    struct Scope: Hashable {
        let regions: [String]
        var home: String { regions.first ?? "jp" }
        var graphRegions: [String] { UserPathCensusTests.catalog.filter { regions.contains($0) } }
        var key: String { regions.count > 1 ? graphRegions.joined(separator: "+") : home }
        var isLarge: Bool { regions.contains { UserPathCensusTests.largeRegions.contains($0) } }
    }

    static func ordered(_ scopes: some Sequence<Scope>) -> [Scope] {
        scopes.sorted { left, right in
            if left.isLarge != right.isLarge { return !left.isLarge }
            let l = interfaceOrder.firstIndex(of: left.home) ?? 0
            let r = interfaceOrder.firstIndex(of: right.home) ?? 0
            if l != r { return l < r }
            return left.key < right.key
        }
    }

    static func countrySuffixed(_ family: String, _ country: String) -> String {
        country == "jp" ? family : "\(family)-\(country)"
    }

    // MARK: - Mirrored registry + canonical route input

    struct Registry: Sendable {
        let bundles: [String: RegistryBundle]
        let identities: [String: RegistryIdentity]

        /// `BundledRegistry.upgradeIfReady` with the phase settled.
        func upgradeIfReady(_ train: Train) -> Train {
            let region = train.region?.lowercased() ?? ""
            guard !region.isEmpty, identities[region] != nil, let bundle = bundles[region] else { return train }
            return RegistryIdentityUpgrade.apply(train, bundle: bundle)
        }
    }

    /// `TimetableRouteEvidence.match`, synchronous, with a six-date memo like
    /// the actor's `SharedRouteWork(maxEntries: 6)`.
    final class TimetableEvidence {
        let database: Result<TrainTimetableDatabase, Error>
        private var byDate: [String: TimetablePhysicalRouteMatch.CandidateIndex] = [:]
        private var dateOrder: [String] = []

        init(url: URL) {
            database = Result { try TrainTimetableDatabase(url: url) }
        }

        func match(train: Train, country: String, sections: [RouteSection]) throws
            -> TimetablePhysicalRouteMatch.Match?
        {
            guard country == "jp", TrainTimetableDatabase.accepts(train),
                  !train.requiresRouteConfirmation, !sections.isEmpty,
                  train.vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  train.stops.count >= 2,
                  train.stops.allSatisfy({ $0.n02StationCode?.isEmpty == false }),
                  let rideDate = train.date,
                  case .valid(_, _, _, let canonicalDate) = EditorTime.parseDate(rideDate),
                  canonicalDate == rideDate
            else { return nil }
            let opened = try database.get()
            var candidates: [TimetablePhysicalRouteMatch.CandidateIndex] = []
            for offset in 0...2 {
                guard let serviceDate = Dates.addDays(rideDate, -offset),
                      case .valid(_, _, _, let canonical) = EditorTime.parseDate(serviceDate),
                      canonical == serviceDate else { return nil }
                if let ready = byDate[serviceDate] {
                    candidates.append(ready)
                } else {
                    let index = TimetablePhysicalRouteMatch.CandidateIndex(trips: try opened.trips(on: serviceDate))
                    byDate[serviceDate] = index
                    dateOrder.append(serviceDate)
                    if dateOrder.count > 6 { byDate.removeValue(forKey: dateOrder.removeFirst()) }
                    candidates.append(index)
                }
            }
            if case .matched(let match) = TimetablePhysicalRouteMatch.resolve(
                for: train, routeSections: sections, indexedBy: candidates) {
                return match
            }
            return nil
        }
    }

    struct CanonicalInput {
        let train: Train
        let databaseSections: Set<Int>
        let databaseProvenance: TimetablePhysicalRouteMatch.Provenance?
        let timetableFailure: String?
    }

    /// `RiddenRouteStore.canonicalRouteInput` (RiddenRouteStore.swift:1013-1040).
    static func canonicalRouteInput(
        _ stored: Train, country: String, registry: Registry, timetable: TimetableEvidence
    ) -> CanonicalInput {
        let raw = registry.upgradeIfReady(stored)
        var base = TrainValidation.normalizeExportTrain(
            TrainValidation.restoringRouteSectionEndpointNames(raw), country: country,
            stations: TrainValidation.StationTable.empty)
        let originalSections = base.routeSections ?? []
        var match: TimetablePhysicalRouteMatch.Match?
        var failure: String?
        do {
            match = try timetable.match(train: raw, country: country, sections: originalSections)
        } catch {
            failure = error.localizedDescription
        }
        if let match {
            base.routeSections = match.enrichedRouteSections
            base.date = match.serviceDate
            let added = Set(originalSections.indices.filter { originalSections[$0].sectionCodes?.isEmpty != false })
            return CanonicalInput(train: RecordedRouteAdmission.applyingCorridorPreference(to: base),
                                  databaseSections: added, databaseProvenance: match.provenance,
                                  timetableFailure: nil)
        }
        return CanonicalInput(train: RecordedRouteAdmission.applyingCorridorPreference(to: base),
                              databaseSections: [], databaseProvenance: nil, timetableFailure: failure)
    }

    // MARK: - Mirrored solver inputs and display network

    struct ScopeData {
        let inputs: RideRouteResolution.SourceInputs
        let network: RouteNetwork
        let prepared: RideRouteResolution.NetworkInputs
        let graphStore: RouteGraph.RouteGraphStore
        let grid: SegmentGrid
        let lineIndices: [String: [Int32]]
    }

    static func displayNetwork(country: String, root: URL) throws -> RouteNetwork {
        let loaded = try DisplayParts.LoadedPackage.load(
            contentsOf: root.appending(path: "app/public/rail/\(country)-2025.json"))
        return RouteNetwork(lines: loaded.package.lines.map { line in
            RouteNetwork.Line(
                lineId: line.id, name: line.name, operator: line.operator,
                isLoop: line.isLoop, alignmentDirection: line.alignmentDirection,
                parts: DisplayParts.parts(for: line, topology: loaded.topologyByLineID[line.id] ?? .init()),
                intervals: RailIntervalCodes.intervals(for: line), compactLine: line)
        })
    }

    static func load(scope: Scope, root: URL, junctions registry: PhysicalRailJunctionRegistry) throws -> ScopeData {
        let data = root.appending(path: "app/data")
        var sections: [RouteGraph.SectionFeature] = []
        var stations: [Stations.Feature] = []
        var identityPeriods: [RailHistoryOverlay.IdentityPeriod] = []
        for region in scope.graphRegions {
            var regionSections = try RouteGraph.SectionFeatureCollection.load(
                contentsOf: data.appending(path: countrySuffixed("rail-sections", region) + ".json")).features
            var regionStations = try Stations.FeatureCollection.load(
                contentsOf: data.appending(path: countrySuffixed("stations", region) + ".json")).features
            let historyURL = data.appending(path: countrySuffixed("rail-history", region) + ".json")
            if FileManager.default.fileExists(atPath: historyURL.path) {
                let overlay = try RailHistoryOverlay.load(from: historyURL)
                let report = RailHistory.apply(overlay, sections: &regionSections, stations: &regionStations)
                try #require(report.unmatchedRetirements.isEmpty,
                             "rail-history \(region): unmatched retirements \(report.unmatchedRetirements)")
                identityPeriods += overlay.identityPeriods
            }
            sections += regionSections
            stations += regionStations
        }
        let inputs = RideRouteResolution.SourceInputs(
            sections: sections, stationCollection: Stations.FeatureCollection(features: stations),
            physicalJunctions: scope.regions.flatMap { registry.junctions(for: $0) },
            identityPeriods: identityPeriods)

        let network: RouteNetwork
        if scope.regions.count > 1 {
            var lines: [RouteNetwork.Line] = []
            for region in scope.graphRegions { lines += try displayNetwork(country: region, root: root).lines }
            network = RouteNetwork(lines: lines)
        } else {
            network = try displayNetwork(country: scope.home, root: root)
        }

        var grid = SegmentGrid()
        var lineIndices: [String: [Int32]] = [:]
        for (index, line) in network.lines.enumerated() {
            lineIndices[line.lineId, default: []].append(Int32(index))
            for part in line.parts { grid.insert(part, owner: index) }
        }
        return ScopeData(
            inputs: inputs, network: network,
            prepared: RideRouteResolution.NetworkInputs(network: network, inputs: inputs),
            graphStore: RouteGraph.RouteGraphStore(
                sections: inputs.sections, policy: .physicalRailway, junctions: inputs.physicalJunctions,
                cachePolicy: .bounded(maximumNodes: 100_000),
                identityPeriods: inputs.identityPeriods, sourceSnapshotID: inputs.snapshotID),
            grid: grid, lineIndices: lineIndices)
    }

    // MARK: - Geometry

    /// Uniform grid of segments for nearest-segment queries.
    struct SegmentGrid {
        static let cell = 0.005
        private var starts: [Coordinate] = []
        private var ends: [Coordinate] = []
        private(set) var owners: [Int32] = []
        private var buckets: [Int64: [Int32]] = [:]

        private static func key(_ x: Int, _ y: Int) -> Int64 {
            (Int64(x) << 32) ^ Int64(UInt32(truncatingIfNeeded: y))
        }
        private static func index(_ value: Double) -> Int { Int((value / cell).rounded(.down)) }
        /// Own cell first, so a point on its own segment exits immediately.
        private static let ringOrder: [(Int, Int)] = [(0, 0), (-1, -1), (-1, 0), (-1, 1),
                                                      (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

        /// Distance below which a one-ring query is exact.
        static func exactRadius(lat: Double) -> Double { cell * 111_320 * cos(lat * .pi / 180) }

        mutating func insert(_ line: [Coordinate], owner: Int) {
            guard let first = line.first else { return }
            let pairs = line.count == 1 ? [(first, first)] : Array(zip(line, line.dropFirst()))
            for (a, b) in pairs {
                let id = Int32(starts.count)
                starts.append(a); ends.append(b); owners.append(Int32(owner))
                for x in Self.index(min(a.lon, b.lon))...Self.index(max(a.lon, b.lon)) {
                    for y in Self.index(min(a.lat, b.lat))...Self.index(max(a.lat, b.lat)) {
                        buckets[Self.key(x, y), default: []].append(id)
                    }
                }
            }
        }

        func nearest(_ p: Coordinate, allowed: Set<Int32>? = nil, stopBelow: Double = 0)
            -> (meters: Double, owner: Int32)?
        {
            let sy = 111_320.0, sx = 111_320.0 * cos(p.lat * .pi / 180)
            let cx = Self.index(p.lon), cy = Self.index(p.lat)
            var best: (meters: Double, owner: Int32)?
            for (dx, dy) in Self.ringOrder {
                guard let ids = buckets[Self.key(cx + dx, cy + dy)] else { continue }
                for id in ids {
                    let i = Int(id)
                    if let allowed, !allowed.contains(owners[i]) { continue }
                    let d = Geometry.perpDistanceMeters(p, starts[i], ends[i], sx: sx, sy: sy)
                    if best == nil || d < best!.meters {
                        best = (d, owners[i])
                        if d <= stopBelow { return best }
                    }
                }
            }
            return best
        }
    }

    static func resample(_ line: [Coordinate], step: Double) -> [Coordinate] {
        guard var previous = line.first else { return [] }
        var out = [previous]
        for next in line.dropFirst() {
            let distance = Geometry.distanceMeters(previous, next)
            let count = max(1, Int(distance / step))
            for i in 1...count {
                let t = Double(i) / Double(count)
                out.append(Coordinate(lon: previous.lon + (next.lon - previous.lon) * t,
                                      lat: previous.lat + (next.lat - previous.lat) * t))
            }
            previous = next
        }
        return out
    }

    static func bruteDistance(_ point: Coordinate, to lines: [[Coordinate]]) -> Double {
        let sy = 111_320.0, sx = 111_320.0 * cos(point.lat * .pi / 180)
        var best = Double.infinity
        for line in lines {
            if line.count == 1 { best = min(best, Geometry.distanceMeters(point, line[0])) }
            for (a, b) in zip(line, line.dropFirst()) {
                best = min(best, Geometry.perpDistanceMeters(point, a, b, sx: sx, sy: sy))
            }
        }
        return best
    }

    /// Exact max over `points` of the distance to `lines` (grid, brute-force fallback).
    static func maxDistance(_ points: [Coordinate], to lines: [[Coordinate]]) -> Double {
        var grid = SegmentGrid()
        for line in lines { grid.insert(line, owner: 0) }
        var worst = 0.0
        for point in points {
            if let hit = grid.nearest(point), hit.meters <= SegmentGrid.exactRadius(lat: point.lat) {
                worst = max(worst, hit.meters)
            } else {
                worst = max(worst, bruteDistance(point, to: lines))
            }
        }
        return worst
    }

    static func length(_ line: [Coordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + Geometry.distanceMeters($1.0, $1.1) }
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - The census

    struct Ride {
        let store: String
        let train: Train
    }

    @Test("Every bundled example ride through the user-journey route path",
          .enabled(if: ProcessInfo.processInfo.environment["SAMPLE_DISPLAY_CENSUS"] == "1"))
    func userPathCensus() throws {
        let environment = ProcessInfo.processInfo.environment
        let strict = environment["SAMPLE_DISPLAY_CENSUS_STRICT"] == "1"
        let root = try PortFixtures.repositoryRoot()
        let data = root.appending(path: "app/data")

        // RideStorage.decodeSample + ItineraryStore.merge: decode, validate,
        // keep store order, later sample wins a duplicate id.
        var rides: [Ride] = []
        var position: [String: Int] = [:]
        for sample in Self.samples {
            let store = try JSONDecoder().decode(
                TrainStore.self, from: Data(contentsOf: root.appending(path: sample.path)))
            for train in store.trains {
                try TrainValidation.validateSupportedRegions(train)
                // MergedStore.regionTagged / taggingRegion: every shipped
                // sample already declares its region; an untagged one would
                // need RegionCodeIndex, which this census does not mirror.
                try #require(train.region?.isEmpty == false, "untagged sample ride \(train.id)")
                let ride = Ride(store: sample.resource, train: train)
                if let index = position[train.id] { rides[index] = ride }
                else { position[train.id] = rides.count; rides.append(ride) }
            }
        }

        let regionsInUse = Set(rides.flatMap { Self.regionsTouched($0.train) })
        var bundles: [String: RegistryBundle] = [:]
        for region in regionsInUse {
            let url = data.appending(path: "registry-bundle/\(region).json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bundle = try JSONDecoder().decode(RegistryBundle.self, from: Data(contentsOf: url))
            if bundle.region.lowercased() == region { bundles[region] = bundle }
        }
        let registry = Registry(bundles: bundles, identities: bundles.mapValues(RegistryIdentity.init(bundle:)))
        let identities = registry.identities
        let junctionRegistry = try PhysicalRailJunctionRegistry(
            data: Data(contentsOf: data.appending(path: "physical-rail-junctions.json")))
        let timetableURL = data.appending(path: "train-service-history/derived/train-service-timetable.sqlite")
        try #require(FileManager.default.fileExists(atPath: timetableURL.path))
        let timetable = TimetableEvidence(url: timetableURL)

        let legs: [Leg] = try RegistryIdentityLookup.withTestPhase({ region in
            identities[region.lowercased()].map(RegistryPhase.ready) ?? .unavailable
        }) {
            var legs: [Leg] = []
            // RiddenRouteStore.decode: requiresRouteConfirmation rides are never solved.
            for ride in rides where ride.train.requiresRouteConfirmation {
                legs.append(Leg(store: ride.store, ride: ride.train.id, segment: -1, from: nil, to: nil,
                                solvePath: "none/awaitingConfirmation", disposition: "skipped"))
            }
            let solvable = rides.filter { !$0.train.requiresRouteConfirmation }
            let byScope = Dictionary(grouping: solvable) { Scope(regions: Self.regionsTouched($0.train)) }
            for scope in Self.ordered(byScope.keys) {
                // One scope resident at a time, as DisplayNetworkCache and
                // SolverInputCache keep one generation.
                legs += try Self.census(scope: scope, rides: byScope[scope] ?? [], root: root,
                                        junctions: junctionRegistry, registry: registry, timetable: timetable)
            }
            return legs
        }

        // Report.
        let rideIDs = Set(rides.map(\.train.id))
        let solvedParts = legs.filter(\.solved)
        let offNetwork = solvedParts.filter { $0.drawnOffNetworkMaxM > Self.strictToleranceM }
        let unprojected = solvedParts.filter { !$0.projected }
        let unsolved = legs.filter { !$0.solved }
        let uncertified = solvedParts.filter { !$0.certified }
        var paths: [String: Int] = [:]
        for leg in legs { paths[leg.solvePath, default: 0] += 1 }
        print("user-path census: \(rideIDs.count) rides, \(legs.count) records, "
              + "\(solvedParts.count) drawn parts, \(unsolved.count) unsolved sections/rides, "
              + "\(unprojected.count) raw (unprojected) parts, \(uncertified.count) uncertified parts, "
              + "\(offNetwork.count) parts > \(Int(Self.strictToleranceM)) m off the display network")
        print("user-path census paths: \(paths.sorted { $0.key < $1.key })")

        #expect(!legs.isEmpty)
        #expect(Set(legs.map(\.ride)) == rideIDs, "every ride must produce at least one record")
        if strict {
            for leg in legs {
                #expect(leg.solved, "\(leg.ride) #\(leg.segment): \(leg.solvePath)")
                guard leg.solved else { continue }
                #expect(leg.projected, "\(leg.ride) #\(leg.segment).\(leg.part): drawn from the raw solver path")
                #expect(leg.certified, "\(leg.ride) #\(leg.segment).\(leg.part): physical gap")
                #expect(leg.drawnOffNetworkMaxM <= Self.strictToleranceM,
                        "\(leg.ride) #\(leg.segment).\(leg.part): \(Int(leg.drawnOffNetworkMaxM)) m off the network")
                #expect((leg.drawnOffDisplayLinesMaxM ?? 0) <= Self.strictToleranceM,
                        "\(leg.ride) #\(leg.segment).\(leg.part): off its own display lines \(leg.displayLines)")
                #expect(leg.displayLineIDsOutsideRequest.isEmpty,
                        "\(leg.ride) #\(leg.segment).\(leg.part): unrequested lines \(leg.displayLineIDsOutsideRequest)")
            }
        }

        let output = environment["SAMPLE_DISPLAY_CENSUS_OUTPUT"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.temporaryDirectory.appending(path: "sample-display-census.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(legs).write(to: output)
        print("user-path census -> \(output.path)")
    }

    /// One scope: the two passes of `decodeUncached`, then one record per drawn part.
    static func census(
        scope: Scope, rides: [Ride], root: URL, junctions: PhysicalRailJunctionRegistry,
        registry: Registry, timetable: TimetableEvidence
    ) throws -> [Leg] {
        let data = try load(scope: scope, root: root, junctions: junctions)
        let country = scope.home
        let lineStrict = ProcessInfo.processInfo.environment["SAMPLE_LINE_NAMES_STRICT"] == "1"

        // canonicalRouteInput runs per pass in the app; it is deterministic
        // (and memoised there), so it runs once per ride here.
        var canonical: [String: CanonicalInput] = [:]
        for ride in rides {
            canonical[ride.train.id] = canonicalRouteInput(
                ride.train, country: country, registry: registry, timetable: timetable)
        }

        func solve(_ ride: Ride, allowLegacy: Bool) throws -> RideRouteResolution.Result {
            let input = canonical[ride.train.id]!
            // A fresh resolver per ride over the scope's shared graph store,
            // as solveMissing → solveMissingSequentialWithPermit([train]) does.
            var resolver = RideRouteResolution(
                inputs: data.inputs, country: country, network: data.prepared,
                officialIntervals: data.inputs.officialIntervals, graphStore: data.graphStore)
            // The working-set train after the registry settle commit
            // (ItineraryStore.applySettledIdentity) is the upgraded one.
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

        // Pass 1 over every ride, then pass 2 over what pass 1 did not emit.
        func timed(_ body: () throws -> RideRouteResolution.Result) rethrows
            -> (RideRouteResolution.Result, Double)
        {
            let start = ContinuousClock.now
            let value = try body()
            let elapsed = ContinuousClock.now - start
            return (value, Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15)
        }

        var outcomes: [String: (pass: String, result: RideRouteResolution.Result, ms: Double)] = [:]
        var missing: [Ride] = []
        for ride in rides {
            let (result, ms) = try timed { try solve(ride, allowLegacy: false) }
            outcomes[ride.train.id] = ("inference", result, ms)
            if !emitsRide(result) { missing.append(ride) }
        }
        for ride in missing {
            let (result, ms) = try timed { try solve(ride, allowLegacy: true) }
            outcomes[ride.train.id] = ("legacy", result, (outcomes[ride.train.id]?.ms ?? 0) + ms)
        }

        var legs: [Leg] = []
        for ride in rides {
            guard let outcome = outcomes[ride.train.id] else { continue }
            let result = outcome.result
            let input = canonical[ride.train.id]!
            let disposition = String(describing: result.disposition)
            guard emitsRide(result) else {
                var leg = Leg(store: ride.store, ride: ride.train.id, segment: -1, from: nil, to: nil)
                leg.solvePath = "none/\(disposition)"
                leg.disposition = disposition
                leg.timetableFailure = input.timetableFailure
                leg.rideSolveMs = outcome.ms
                legs.append(leg)
                continue
            }
            let sections = result.expectedSections
            let drawnSections = Set(result.segments.map(\.segmentIndex))
            let selections = RiddenLineSequence.selections(
                result.segments.map { (segmentIndex: $0.segmentIndex, selection: $0.physicalRoute) })
            let lineSequence = RiddenLineSequence(
                train: ride.train, sections: sections, selections: selections,
                drawnSections: drawnSections, gaps: result.physicalGaps, solveSettled: true)
            let lineSummary = lineSequence.summary
            let summaryNames = lineSummary.runs.map(\.name)
            let summarySources = lineSequence.sections.map(\.source.rawValue)
            let summaryBoundaries = lineSummary.boundaries.map { boundary -> String in
                let kind: String
                switch boundary.kind {
                case .throughService(let codes): kind = "through(\(codes.joined(separator: ",")))"
                case .operatorChange: kind = "operatorChange"
                case .lineChange: kind = "lineChange"
                }
                return "\(boundary.stationCode ?? "?"):\(kind)"
            }
            if lineStrict {
                Self.checkLineSequence(lineSequence, ride: ride.train, sections: sections, selections: selections)
            }
            func base(_ index: Int, from: String?, to: String?) -> Leg {
                var leg = Leg(store: ride.store, ride: ride.train.id, segment: index, from: from, to: to)
                leg.lineSummary = summaryNames
                leg.lineSources = summarySources
                leg.lineBoundaries = summaryBoundaries
                leg.disposition = disposition
                leg.timetableMatched = input.databaseProvenance != nil
                leg.timetableFailure = input.timetableFailure
                leg.rideSolveMs = outcome.ms
                leg.legCount = sections.count
                leg.certified = !result.physicalGaps.contains { $0.segmentIndex == index && !$0.isBoundary }
                leg.boundaryGap = result.physicalGaps.contains { $0.segmentIndex == index && $0.isBoundary }
                if sections.indices.contains(index) {
                    let section = sections[index]
                    leg.requestedLineIDs = section.lineIDs ?? []
                    leg.requestedLineNames = section.lineNames ?? []
                    leg.requestedOperatorNames = section.operatorNames ?? []
                }
                return leg
            }

            for segment in result.segments {
                var leg = base(segment.segmentIndex, from: segment.from, to: segment.to)
                leg.part = segment.partIndex
                leg.solved = true
                leg.temporalKind = segment.temporalKind.rawValue
                leg.provenance = segment.physicalRoute?.provenance.rawValue
                let drawn = segment.drawnCoordinates
                let source = segment.sourceCoordinates
                let intervals = segment.physicalRoute.map { $0.provenance != .matchedGeometry } ?? false
                leg.projected = intervals || drawn != source
                let branch = intervals ? "intervals" : (leg.projected ? "solver+display" : "solver-raw")
                leg.solvePath = "\(outcome.pass)/\(branch)"

                let drawnSamples = Self.resample(drawn, step: 50)
                if let lines = segment.physicalRoute?.lines, !lines.isEmpty {
                    leg.displayLineIDs = Self.unique(lines.map(\.lineID))
                    leg.displayLineSource = "selection"
                } else if leg.projected {
                    var hits: [String] = []
                    for point in drawnSamples {
                        if let hit = data.grid.nearest(point, stopBelow: 0.5), hit.meters <= 2 {
                            hits.append(data.network.lines[Int(hit.owner)].lineId)
                        }
                    }
                    leg.displayLineIDs = Self.unique(hits)
                    leg.displayLineSource = hits.isEmpty ? "none" : "geometry"
                }
                let attributed = leg.displayLineIDs.flatMap { data.lineIndices[$0] ?? [] }
                leg.displayLines = leg.displayLineIDs.map { id in
                    data.lineIndices[id]?.first.flatMap { data.network.lines[Int($0)].name } ?? id
                }
                leg.displayOperators = Array(Set(attributed.compactMap {
                    data.network.lines[Int($0)].operator })).sorted()
                if !leg.requestedLineIDs.isEmpty {
                    leg.displayLineIDsOutsideRequest = leg.displayLineIDs.filter { !leg.requestedLineIDs.contains($0) }
                }

                leg.sourceLengthM = Self.length(source)
                leg.drawnLengthM = Self.length(drawn)
                leg.drawnCoordinates = drawn.map { [$0.lon, $0.lat] }
                for (a, b) in zip(drawn, drawn.dropFirst()) {
                    leg.longestDrawnEdgeM = max(leg.longestDrawnEdgeM, Geometry.distanceMeters(a, b))
                }
                leg.sourceToDrawnMaxM = Self.maxDistance(Self.resample(source, step: 50), to: [drawn])
                leg.drawnToSourceMaxM = Self.maxDistance(drawnSamples, to: [source])

                let allowed = Set(attributed)
                var offNetwork = 0.0
                var offOwn = 0.0
                for point in drawnSamples {
                    let any = data.grid.nearest(point, stopBelow: 0.5)?.meters ?? .infinity
                    offNetwork = max(offNetwork, min(any, Self.networkCapM))
                    if !allowed.isEmpty {
                        let own = data.grid.nearest(point, allowed: allowed, stopBelow: 0.5)?.meters ?? .infinity
                        offOwn = max(offOwn, min(own, Self.networkCapM))
                    }
                }
                leg.drawnOffNetworkMaxM = offNetwork
                leg.drawnOffDisplayLinesMaxM = allowed.isEmpty ? nil : offOwn
                legs.append(leg)
            }

            for (index, section) in sections.enumerated() where !drawnSections.contains(index) {
                var leg = base(index, from: section.from, to: section.to)
                leg.solvePath = "\(outcome.pass)/unsolved"
                legs.append(leg)
            }
            if sections.isEmpty && result.segments.isEmpty {
                var leg = base(-1, from: nil, to: nil)
                leg.solvePath = "\(outcome.pass)/unsolved"
                legs.append(leg)
            }
        }
        return legs
    }

    // MARK: - Line-name contract (SAMPLE_LINE_NAMES_STRICT=1)

    /// (a) an emitted ride names at least one line; (b) a selected section's
    /// runs are its intervals' run-length encoded line ids, folded by
    /// `RiddenLineSequence.continues`; (c) a section that requests line ids
    /// shows no other derived id; (d) a consecutive (A, B, S) the catalog
    /// joins on the ride date is a through-service boundary, unless it is an
    /// operator change on one named line.
    static func checkLineSequence(
        _ sequence: RiddenLineSequence, ride: Train, sections: [RouteSection],
        selections: [Int: RideRouteResolution.PhysicalRouteSelection]
    ) {
        typealias Line = RiddenLineSequence.Line
        let id = ride.id
        #expect(!sequence.summary.runs.isEmpty, "\(id): empty line summary")
        let date = ride.date.map { String($0.prefix(10)) }
        func through(_ a: String, _ b: String, _ station: String) -> Bool {
            !(RiddenLineSequence.bundledContinuations(a, b, station, date)
                + RiddenLineSequence.bundledContinuations(b, a, station, date)).isEmpty
        }
        func isThrough(_ kind: RiddenLineSequence.BoundaryKind) -> Bool {
            if case .throughService = kind { return true }
            return false
        }
        func line(_ lineID: String, in selection: RideRouteResolution.PhysicalRouteSelection) -> Line {
            let known = selection.lines.first { $0.lineID == lineID }
            return Line(lineID: lineID, name: known?.name ?? lineID, operatorName: known?.operatorName)
        }
        func sameNameOtherOperator(_ a: Line, _ b: Line) -> Bool {
            TrainServiceBranding.canonicalLineName(a.name) == TrainServiceBranding.canonicalLineName(b.name)
                && a.operatorName != b.operatorName
        }
        for section in sequence.sections {
            let index = section.sectionIndex
            if section.source == .solved, let selection = selections[index] {
                var ids: [String] = []
                for lineID in (selection.intervals.isEmpty
                    ? selection.lines.map(\.lineID) : selection.intervals.map(\.lineID))
                where ids.last != lineID { ids.append(lineID) }
                var expected: [Line] = []
                for lineID in ids {
                    let next = line(lineID, in: selection)
                    if let last = expected.last, RiddenLineSequence.continues(last, next) { continue }
                    expected.append(next)
                }
                #expect(section.runs.map(\.lineID) == expected.map(\.lineID),
                        "\(id) #\(index): runs \(section.runs.map(\.name)) vs intervals \(ids)")

                // (d) inside the section, at the station two intervals share.
                for (a, b) in zip(selection.intervals, selection.intervals.dropFirst()) where a.lineID != b.lineID {
                    guard let p = RailIntervalCodes.stationCodes(ofIntervalCode: a.code),
                          let q = RailIntervalCodes.stationCodes(ofIntervalCode: b.code) else { continue }
                    let shared = Set([p.0, p.1]).intersection([q.0, q.1])
                    guard shared.count == 1, let station = shared.first, through(a.lineID, b.lineID, station),
                          !sameNameOtherOperator(line(a.lineID, in: selection), line(b.lineID, in: selection)),
                          !RiddenLineSequence.continues(line(a.lineID, in: selection), line(b.lineID, in: selection))
                    else { continue }
                    #expect(section.boundaries.contains { $0.stationCode == station && isThrough($0.kind) },
                            "\(id) #\(index): \(a.lineID) → \(b.lineID) at \(station) is not a through boundary")
                }
            }
            if sections.indices.contains(index), let requested = sections[index].lineIDs, !requested.isEmpty,
               section.source == .solved || section.source == .geometry {
                let outside = section.runs.compactMap(\.lineID).filter { !requested.contains($0) }
                #expect(outside.isEmpty, "\(id) #\(index): runs outside the requested lines \(outside)")
            }
        }
        // (d) across section joins.
        for (later, join) in sequence.joins {
            // Only solved-to-solved joins are checkable against selections.
            guard sequence.sections.first(where: { $0.sectionIndex == later - 1 })?.source == .solved,
                  sequence.sections.first(where: { $0.sectionIndex == later })?.source == .solved,
                  let previous = selections[later - 1], let next = selections[later],
                  let a = previous.intervals.last?.lineID, let b = next.intervals.first?.lineID,
                  a != b, through(a, b, previous.toStationCode),
                  !sameNameOtherOperator(line(a, in: previous), line(b, in: next)) else { continue }
            #expect(isThrough(join.kind),
                    "\(id) join #\(later): \(a) → \(b) at \(previous.toStationCode) is not a through boundary")
        }
    }
}
